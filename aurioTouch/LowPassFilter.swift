//  LowPassFilter.swift
//  aurioTouch
//
//  Created by Jake Miller on 4/30/17.
//
//

import AudioToolbox


class LowPassFilter {
    var value: Double = 0.0
    let resofreq: Double = 10000.0
    var r: Float = 1
    var eagl:EAGLView? = nil
    
    func processInplace(_ ioData: UnsafeMutablePointer<Float32>, numFrames: UInt32) {

       
        
        let c: Double = 2-2*cos(2 * 3.14 * resofreq / 44100)
        var pos: Float = 0
        var speed: Float = 0
        for i in 1..<Int(numFrames) {
           
            var speed = Float(speed) + (ioData[i] - Float32(pos)) * Float(c)
            pos = pos + speed
            speed = speed * r
            ioData[i] = Float32(pos)
            print(r)
        }
    }
    
}
