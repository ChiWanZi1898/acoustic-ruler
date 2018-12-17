//
//  ViewController.swift
//  Acoustic Ruler
//
//  Created by Hongyu Zhu on 2018/12/16.
//  Copyright © 2018 Hongyu Zhu. All rights reserved.
//

import UIKit
import AVFoundation
import Accelerate


class ViewController: UIViewController {
    
    var audioEngine: AVAudioEngine!
    var inputNode: AVAudioInputNode!
    var receiverReformatNode: AVAudioMixerNode!
    var playerNode: AVAudioPlayerNode!
    var audioProcessor: AudioProcessor!
    var converter: AVAudioConverter!
    
    var sampleRate: Float = 0
    var bufferSize: UInt32 = 0
    var chirpSize: UInt32 = 0
    var isMeasuring = false
    var isBeaconing = false
    
    var startFrequency: Float = 18000
    var endFrequency: Float = 20500
    
    var format: AVAudioFormat!
    
    var fftLength: UInt32 = 65536
    var fft_weights: FFTSetup!
    
    var baseHostTime: Double = 0
    var currentHostTime: Double = 0
    var baseDeltaTime: Double = 0
    var currentDeltaTime: Double = 0
    var counter: UInt64=0
    var baseSlope: Double = 0
    
    var chirpData: [Float] = []
    var chirpFullData: [Float] = []
    
    var iirCoef: [Double] = []
    
    let deltaTimeListCapacity = 600
    var deltaTimeList = [Double]()
    
    var bufferMeanVolumeText: String? {
        willSet {
            bufferMeanVolumeDisplay.text = String("Buffer Mean Volume: \(newValue ?? "N\\A")")
        }
    }
    
    var distanceText: String? {
        willSet {
            distanceDisplay.text = String("Distance: \(newValue ?? "N\\A")")
        }
    }
    
    enum DisplayType {
        case bufferMeanVolume
    }
    
    @IBOutlet var measureButton: UIButton!
    @IBAction func switchMeasureStatus(_ sender: Any) {
        switch isMeasuring {
        case false:
            startMeasure()
        case true:
            stopMeasure()
        }
    }
    
    @IBOutlet var measureResetButton: UIButton!
    @IBAction func resetMeasure(_ sender: Any) {
        resetDistance()
    }
    
    
    @IBOutlet var beaconButton: UIButton!
    @IBAction func switchBeaconStatus(_ sender: Any) {
        switch isBeaconing {
        case false:
            startBeacon()
        case true:
            stopBeacon()
        }
    }
    
    
    @IBOutlet var bufferMeanVolumeDisplay: UILabel!

    
    @IBOutlet var distanceDisplay: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        
        
        
        try! AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .measurement)
        try! AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
        
        audioEngine = AVAudioEngine()
        inputNode = audioEngine.inputNode
        
        sampleRate = Float(inputNode.outputFormat(forBus: 0).sampleRate)
        bufferSize = UInt32(sampleRate / 10)
        chirpSize = bufferSize / 2
        
        switch sampleRate {
        case 44100:
            iirCoef = [0.2154816921749375, 0, -0.2154816921749375, 1.4458299168752418, 0.569036615650125]
        case 48000:
            iirCoef = [0.2917234452919156, 0, -0.2917234452919156, 1.1514404985368765, 0.41655310941616897]
        default:
            print("invalid sample rate: \(sampleRate).")
            return
        }
        
        format = AVAudioFormat(commonFormat: AVAudioCommonFormat.pcmFormatFloat32,
                               sampleRate: Double(sampleRate),
                               channels: 1,
                               interleaved: true)
        
//        converter = AVAudioConverter(from: inputNode.outputFormat(forBus: 0), to: format)
//        receiverReformatNode = AVAudioMixerNode()
//        audioEngine.attach(receiverReformatNode)
//        audioEngine.connect(inputNode, to: receiverReformatNode, format: inputNode.outputFormat(forBus: 0))
        
        playerNode = AVAudioPlayerNode()
        audioEngine.attach(playerNode)
        
        
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)

        audioProcessor = AudioProcessor(sampleRate: sampleRate)
        
        fft_weights = vDSP_create_fftsetup(vDSP_Length(log2(Double(fftLength))), FFTRadix(kFFTRadix2))!
        
        chirpData = audioProcessor.chirp(from: startFrequency, to: endFrequency, length: Int(chirpSize), bufferLength: Int(bufferSize))
        chirpFullData = audioProcessor.chirpFull(from: startFrequency, to: endFrequency, length: Int(chirpSize), bufferLength: Int(bufferSize))
        
        deltaTimeList.reserveCapacity(deltaTimeListCapacity)
//        print(slope(inputArray: &test))
    }
    
    func startMeasure() {
        
        if isMeasuring || isBeaconing {
            return
        }
        
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("\(error)")
            return
        }
        
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { (buffer, time) in
            DispatchQueue.main.async{
                self.process(buffer: buffer, time: time)
            }
        }
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            print("\(error)")
            return
        }
        
        measureButton.setTitle("stop", for: .normal)
        measureResetButton.isEnabled = true
        isMeasuring = true
    }
    
    func stopMeasure() {
        
        if !isMeasuring {
            return
        }
        
        inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("\(error)")
            return
        }
        
        measureButton.setTitle("start", for: .normal)
        measureResetButton.isEnabled = false
        
        
        bufferMeanVolumeText = String("N/A")
        distanceText = String("N/A")
        isMeasuring = false
    }
    
    func startBeacon() {
        
        if isMeasuring || isBeaconing {
            return
        }
        
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("\(error)")
            return
        }
        
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(bufferSize))
        
        
        for i in 0..<Int(bufferSize) {
            buffer?.floatChannelData?.pointee[i] = chirpData[i]
        }
        buffer?.frameLength = AVAudioFrameCount(bufferSize)
        playerNode.scheduleBuffer(buffer!, at: nil, options: .loops, completionHandler: nil)
    
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            print("\(error)")
            return
        }
        
        playerNode.play()
        beaconButton.setTitle("stop", for: .normal)
        isBeaconing = true
    }
    
    func stopBeacon() {
        if !isBeaconing {
            return
        }
        
        playerNode.stop()
        audioEngine.stop()
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("\(error)")
            return
        }
        beaconButton.setTitle("start", for: .normal)
        isBeaconing = false
        
    }
    
    func process(buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        
        counter += 1
        
        currentHostTime = AVAudioTime.seconds(forHostTime: time.hostTime)
        
        print(buffer.frameLength)
        
        let data = buffer.floatChannelData?.pointee
        let length = vDSP_Length(buffer.frameLength)
        var absData = [Float](repeating: 0, count: Int(length))
        vDSP_vabs(data!, 1, &absData, 1, length)
        var mean = Float(0)
        vDSP_meanv(&absData, 1, &mean, length)
        print(mean)
        
        // bandpass filter
//        let coef:[Double] = [0.2917234452919156, 0, -0.2917234452919156, 1.1514404985368765, 0.41655310941616897]
        let iir_weights = vDSP_biquad_CreateSetup(iirCoef, vDSP_Length(1))
        var delay = [Float](repeating: 0, count: 4)
        var filteredData = [Float](repeating: 0, count: Int(bufferSize))
        vDSP_biquad(iir_weights!, &delay, data!, 1, &filteredData, 1, vDSP_Length(bufferSize))
        
        var convolutedData = [Float](repeating: 0, count: Int(fftLength))
        vDSP_vmul(data!, 1, chirpData, 1, &convolutedData, 1, length)
        
        let fftOut = fft(inputArray: &convolutedData)
        
        var maxValue: Float = 0
        var maxIndex: vDSP_Length = 0
        vDSP_maxvi(fftOut, 1, &maxValue, &maxIndex, vDSP_Length(fftLength / 2))
        print(maxIndex)
        
        let deltaTime = Double(maxIndex) / Double(fftLength) * Double(sampleRate) / Double(endFrequency - startFrequency) * Double(chirpSize) / Double(sampleRate)
        currentDeltaTime = deltaTime
        
//        let conpensatedDeltaTime = currentDeltaTime - baseDeltaTime + currentHostTime - baseHostTime - Double(counter) * (Double(length) / Double(sampleRate))
//        print(length)
        print(currentDeltaTime - baseDeltaTime - baseSlope * Double(counter))
        let distance = (currentDeltaTime - baseDeltaTime - baseSlope * Double(counter)) * 340.0
        bufferMeanVolumeText = String(format: "%.4f", mean)
        distanceText = String(format: "%.4f", distance)
//        distanceText = String(format: "%d", maxIndex)
        
        appendDeltaTime(delta: currentDeltaTime)
    }
    
    func fft(inputArray: inout [Float]) -> [Float] {
        
        var fftMagnitudes = [Float](repeating:0.0, count:inputArray.count)
        var zeroArray = [Float](repeating:0.0, count:inputArray.count)
        var splitComplexInput = DSPSplitComplex(realp: &inputArray, imagp: &zeroArray)
        
        vDSP_fft_zip(fft_weights, &splitComplexInput, 1, vDSP_Length(log2(CDouble(inputArray.count))), FFTDirection(FFT_FORWARD));
        vDSP_zvmags(&splitComplexInput, 1, &fftMagnitudes, 1, vDSP_Length(inputArray.count));
        
        let roots = fftMagnitudes.map(){sqrt($0)}
        // vDSP_zvmagsD returns squares of the FFT magnitudes, so take the root here
        var normalizedValues = [Float](repeating:0.0, count:inputArray.count)
        
        vDSP_vsmul(roots, vDSP_Stride(1), [2.0 / Float(inputArray.count)], &normalizedValues, vDSP_Stride(1), vDSP_Length(inputArray.count))
        return normalizedValues
    }
    
    func slope(inputArray: inout [Double]) -> Double {
        let length = inputArray.count
        var negYMean = Double(0)
        vDSP_meanvD(&inputArray, 1, &negYMean, vDSP_Length(length))
        negYMean = 0 - negYMean
        
        var yMinusYMean = [Double](repeating: 0, count: length)
        vDSP_vsaddD(&inputArray, 1, &negYMean, &yMinusYMean, 1, vDSP_Length(length))
        var xMinusXMean = [Double](repeating: 0, count: length)
        var negXMean = Double(1 - length) / 2
        var increment = Double(1)
        vDSP_vrampD(&negXMean, &increment, &xMinusXMean, 1, vDSP_Length(length))
        
        var xXy = [Double](repeating: 0, count: length)
        vDSP_vmulD(&xMinusXMean, 1, &yMinusYMean, 1, &xXy, 1, vDSP_Length(length))
        var cor = Double(0)
        vDSP_sveD(xXy, 1, &cor, vDSP_Length(length))
        
        var xXx = [Double](repeating: 0, count: length)
        vDSP_vmulD(&xMinusXMean, 1, &xMinusXMean, 1, &xXx, 1, vDSP_Length(length))
        var vari = Double(0)
        vDSP_sveD(xXx, 1, &vari, vDSP_Length(length))
        
        let beta = cor / vari
        return beta
    }
    
    func resetDistance() {
        baseHostTime = currentHostTime
        baseDeltaTime = currentDeltaTime
        counter = 0
        var last10:[Double] = Array(deltaTimeList.suffix(100))
        baseSlope = slope(inputArray: &last10)
        deltaTimeList.removeAll()
    }
    
    func appendDeltaTime(delta: Double) {
        if deltaTimeList.count >= deltaTimeListCapacity {
            deltaTimeList.removeFirst(deltaTimeListCapacity - 100)
        }
        deltaTimeList.append(delta)
    }
}

