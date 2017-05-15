//
//  BufferManager.swift
//  aurioTouch
//
//  Translated by OOPer in cooperation with shlab.jp, on 2015/1/30.
//
//
/*

 Copyright (C) 2016 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information

 Abstract:
 This class handles buffering of audio data that is shared between the view and audio controller

 */

import AudioToolbox
import libkern


let kNumDrawBuffers = 12
let kDefaultDrawSamples = 1024


class BufferManager {
    
    var displayMode: AudioController.aurioTouchDisplayMode
    
    
    private(set) var drawBuffers: UnsafeMutablePointer<UnsafeMutablePointer<Float32>?>
    
    var currentDrawBufferLength: Int
    
    var hasNewFFTData: Bool {return mHasNewFFTData != 0}
    var needsNewFFTData: Bool {return mNeedsNewFFTData != 0}
    
    var FFTOutputBufferLength: Int {return mFFTInputBufferLen / 2}
    
    private var mDrawBufferIndex: Int
    
    private var mFFTInputBuffer: UnsafeMutablePointer<Float32>?
    private var mFFTInputBufferFrameIndex: Int
    private var mFFTInputBufferLen: Int
    private var mHasNewFFTData: Int32   //volatile
    private var mNeedsNewFFTData: Int32 //volatile
    
    private var mFFTHelper: FFTHelper
    
    
    // fixed array of size of how many points are drawn, data input is always 512
    var fixedArrayData = [Float](repeating: Float(0), count: kDefaultDrawSamples/2)
    var fixedArrayDataFFT = [Float](repeating: Float(0), count: kDefaultDrawSamples/2)
    
    // class variables for max, min, avg, med
    var avg_val = Float()
    var med_val = Float()
    var max_val = Float()
    var min_val = Float()
    
    var freq = Float()
    var zeroCrossings = Int()


    
    
    
    
    init(maxFramesPerSlice inMaxFramesPerSlice: Int) {
        displayMode = .oscilloscopeWaveform
        drawBuffers = UnsafeMutablePointer.allocate(capacity: Int(kNumDrawBuffers))
        mDrawBufferIndex = 0
        currentDrawBufferLength = kDefaultDrawSamples
        mFFTInputBuffer = nil
        mFFTInputBufferFrameIndex = 0
        mFFTInputBufferLen = inMaxFramesPerSlice
        mHasNewFFTData = 0
        mNeedsNewFFTData = 0
        for i in 0..<kNumDrawBuffers {
            drawBuffers[Int(i)] = UnsafeMutablePointer.allocate(capacity: Int(inMaxFramesPerSlice))
        }
        
        mFFTInputBuffer = UnsafeMutablePointer.allocate(capacity: Int(inMaxFramesPerSlice))
        mFFTHelper = FFTHelper(maxFramesPerSlice: inMaxFramesPerSlice)
        OSAtomicIncrement32Barrier(&mNeedsNewFFTData)
    }
    
    
    deinit {
        for i in 0..<kNumDrawBuffers {
            drawBuffers[Int(i)]?.deallocate(capacity: mFFTInputBufferLen)
            drawBuffers[Int(i)] = nil
        }
        drawBuffers.deallocate(capacity: kNumDrawBuffers)
        
        mFFTInputBuffer?.deallocate(capacity: mFFTInputBufferLen)
    }
    
    
    func copyAudioDataToDrawBuffer(_ inData: UnsafePointer<Float32>?, inNumFrames: Int) {
        if inData == nil { return }
        
        for i in 1..<inNumFrames {
            if i + mDrawBufferIndex >= currentDrawBufferLength {
                cycleDrawBuffers()
                mDrawBufferIndex = -i
            }
            drawBuffers[0]?[i + mDrawBufferIndex] = (inData?[i])!
            
            // adding to fixed sized array
            // fixedArrayData will be overwritten each iteration
            //fixedArrayData[i] = (fixedArrayData[i] + fixedArrayData[i-1]) / 2;
            fixedArrayData[i] = (inData?[i])!
            
        }
        mDrawBufferIndex += inNumFrames
        
        
        // compute zeroCrossings, average, median, max, min of input
        medianArray(nums: fixedArrayData)
        minArray(nums: fixedArrayData)
        maxArray(nums: fixedArrayData)
        averageArray(nums: fixedArrayData)
        freq = frequencyCalc(inputData: fixedArrayData, inputLength: inNumFrames, sampleRate: 44100)
        
        // print computations and zeroCrossings after array is full
        print("--------------------")
        print("Frequency: \(freq)")
        print("Average: \(avg_val)")
        print("Max value: \(max_val)")
        print("Min value: \(min_val)")
        print("Median: \(med_val)")
    }
    
    
    func cycleDrawBuffers() {
        // Cycle the lines in our draw buffer so that they age and fade. The oldest line is discarded.
        for drawBuffer_i in stride(from: (kNumDrawBuffers - 2), through: 0, by: -1) {
            memmove(drawBuffers[drawBuffer_i + 1], drawBuffers[drawBuffer_i], size_t(currentDrawBufferLength))
        }
    }
    
    
    func CopyAudioDataToFFTInputBuffer(_ inData: UnsafePointer<Float32>, numFrames: Int) {
        let framesToCopy = min(numFrames, mFFTInputBufferLen - mFFTInputBufferFrameIndex)
        memcpy(mFFTInputBuffer?.advanced(by: mFFTInputBufferFrameIndex), inData, size_t(framesToCopy * MemoryLayout<Float32>.size))
        
        // assign values from inData to a fixed sized array
        // fixedArrayDataFFT will be overwritten each time
        for i in 1..<numFrames {
            
           //fixedArrayDataFFT[i] = (fixedArrayDataFFT[i] + fixedArrayDataFFT[i-1]) / 2;
        
            fixedArrayDataFFT[i] = inData[i]
        }
        
        // compute average, median, max, min of input
        medianArray(nums: fixedArrayDataFFT)
        minArray(nums: fixedArrayDataFFT)
        maxArray(nums: fixedArrayDataFFT)
        averageArray(nums: fixedArrayDataFFT)
        
        // print computations after array is full
        print("--------------------")
        print("Average: \(avg_val)")
        print("Max value: \(max_val)")
        print("Min value: \(min_val)")
        print("Median: \(med_val)")
        
        
        
        mFFTInputBufferFrameIndex += framesToCopy * MemoryLayout<Float32>.size
        if mFFTInputBufferFrameIndex >= mFFTInputBufferLen {
            OSAtomicIncrement32(&mHasNewFFTData)
            OSAtomicDecrement32(&mNeedsNewFFTData)
        }
    }
    
    
    // find average of a given array of floats
    // updates class variable, avg
    func averageArray(nums: [Float]){
        if nums.count != 0{
            var sum = Float(0)
            for num in nums{
                sum += num
            }
            avg_val = sum/Float(nums.count)
        }
        else {
            avg_val = Float(0)
        }
    }
    
    // find max of a given array of floats
    // updates class variable, max
    func maxArray(nums: [Float]){
        if nums.max() != nil{
            max_val = nums.max()!
        } else {
            max_val = Float(0)
        }
    }
    
    // find min of a given array of floats
    // updates class variable, min
    func minArray(nums: [Float]){
        if nums.min() != nil{
            min_val = Float(nums.min()!)
        } else {
            min_val = Float(0)
        }
    }
    
    // find median of a given array of floats
    // updates class variable, med
    func medianArray(nums: [Float]){
        if nums.count != 0{
            let nums_sorted = nums.sorted()
            med_val = nums_sorted[nums_sorted.count/2]
        }
        else {
            med_val = Float(0)
        }
    }
    
    // find zeroCrossings
    // returns an Inter value
    func zeroCrossingsArray(nums: [Float]) -> Int {
        // how many zero crossings
        // variable to keep track of zero crossings
        var zeroCrossings = 0
        // variable to keep track of pos neg values
        var isPos = false
        
        // check if first value in input is pos or neg
        if fixedArrayData[0] >= Float(0) {
            isPos = true
        } else {
            isPos = false
        }
        
        // use for loop to find out when pos -> neg, neg -> pos
        for i in 0..<fixedArrayData.count {
            if isPos {
                if fixedArrayData[i] < Float(0) {
                    isPos = false
                    zeroCrossings += 1
                }
            }
                
            else {
                if fixedArrayData[i] >= Float(0) {
                    isPos = true
                    zeroCrossings += 1
                }
                
            }
        }
        
        return zeroCrossings
    }
    
    func frequencyCalc(inputData: [Float], inputLength: Int, sampleRate: Int) -> Float {
        // frequency = wave speed / wave length
        // wavelength = sample rate
        
        // get zeroCrossings
        let zeroCross = zeroCrossingsArray(nums: inputData)
        // how many cylces
        let speed = Float(zeroCross/2)
    
        let length = Float(sampleRate)/Float(inputLength)
        
        return speed*length
    }
    
    
    func GetFFTOutput(_ outFFTData: UnsafeMutablePointer<Float32>) {
        mFFTHelper.computeFFT(mFFTInputBuffer, outFFTData: outFFTData)
        mFFTInputBufferFrameIndex = 0
        OSAtomicDecrement32Barrier(&mHasNewFFTData)
        OSAtomicIncrement32Barrier(&mNeedsNewFFTData)
    }
}
