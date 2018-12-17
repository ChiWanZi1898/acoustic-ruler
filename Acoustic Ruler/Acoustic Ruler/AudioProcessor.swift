//
//  AudioProcessor.swift
//  Acoustic Ruler
//
//  Created by Hongyu Zhu on 2018/12/16.
//  Copyright © 2018 Hongyu Zhu. All rights reserved.
//

import Accelerate

class AudioProcessor {
    
    var sampleRate: Float = 0
    
    init(sampleRate: Float) {
        self.sampleRate = sampleRate
    }
    
    func chirp(from startFrequency: Float, to endFrequency: Float, length: Int, bufferLength: Int) -> [Float] {
        var data = [Float](repeating: 0, count: bufferLength)
        var initValue: Float = 0
        var increment: Float = 1
        vDSP_vramp(&initValue, &increment, &data, 1, vDSP_Length(length))
        
        let k = (endFrequency - startFrequency) / Float(length)
        data = data.map(){
            if $0 != 0 {
                return sin(2 * Float.pi * (startFrequency * $0 + k / 2 * $0 * $0) / sampleRate)
            } else {
                return Float(0)
            }
        }
        return data
    }
    
    func chirpFull(from startFrequency: Float, to endFrequency: Float, length: Int, bufferLength: Int) -> [Float] {
        var data = [Float](repeating: 0, count: bufferLength)
        var initValue: Float = 0
        var increment: Float = 1
        vDSP_vramp(&initValue, &increment, &data, 1, vDSP_Length(bufferLength))
        
        let k = (endFrequency - startFrequency) / Float(length)
        data = data.map(){
            let time = Float(Int($0) % length)
            return sin(2 * Float.pi * (startFrequency * time + k / 2 * time * time) / sampleRate)
        }
        return data
    }
}
