//
//  AudioEncoder.swift
//  WotjdCam
//
//  Created by wotjd on 2018. 8. 27..
//  Copyright © 2018년 wotjd. All rights reserved.
//

import AVFoundation
import AudioToolbox
import CoreFoundation

extension CMSampleBuffer {
    var dependsOnOthers: Bool {
        guard
            let attachments = CMSampleBufferGetSampleAttachmentsArray(self, false) else {
                return false
        }
        let attachment: [NSObject: AnyObject] = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFDictionary.self) as [NSObject: AnyObject]
        return attachment["DependsOnOthers" as NSObject] as! Bool
    }
    var dataBuffer: CMBlockBuffer? {
        get {
            return CMSampleBufferGetDataBuffer(self)
        }
        set {
            _ = newValue.map {
                CMSampleBufferSetDataBuffer(self, $0)
            }
        }
    }
    var imageBuffer: CVImageBuffer? {
        return CMSampleBufferGetImageBuffer(self)
    }
    var numSamples: CMItemCount {
        return CMSampleBufferGetNumSamples(self)
    }
    var duration: CMTime {
        return CMSampleBufferGetDuration(self)
    }
    var formatDescription: CMFormatDescription? {
        return CMSampleBufferGetFormatDescription(self)
    }
    var decodeTimeStamp: CMTime {
        return CMSampleBufferGetDecodeTimeStamp(self)
    }
    var presentationTimeStamp: CMTime {
        return CMSampleBufferGetPresentationTimeStamp(self)
    }
}

extension CMSampleTimingInfo {
    init(sampleBuffer: CMSampleBuffer) {
        self.init()
        duration = sampleBuffer.duration
        decodeTimeStamp = sampleBuffer.decodeTimeStamp
        presentationTimeStamp = sampleBuffer.presentationTimeStamp
    }
}

extension CMAudioFormatDescription {
    var streamBasicDescription: UnsafePointer<AudioStreamBasicDescription>? {
        return CMAudioFormatDescriptionGetStreamBasicDescription(self)
    }
}

extension CMFormatDescription {
    var extensions: [String: AnyObject]? {
        return CMFormatDescriptionGetExtensions(self) as? [String: AnyObject]
    }
    
    func `extension`(by key: String) -> [String: AnyObject]? {
        return CMFormatDescriptionGetExtension(self, key as CFString) as? [String: AnyObject]
    }
}

public protocol AudioEncoderDelegate : class {
    func didEncode(sampleBuffer: CMSampleBuffer)
    func didFailToEncode()
}

class AudioEncoder: NSObject {
    var delegate: AudioEncoderDelegate? = nil
    
    var converter : AudioConverterRef? = nil
    private var currentBufferList: UnsafeMutableAudioBufferListPointer?
    
    var classDescription : AudioClassDescription = AudioClassDescription(
        mType: kAudioEncoderComponentType,
        mSubType: kAudioFormatMPEG4AAC,
        mManufacturer: kAppleHardwareAudioCodecManufacturer)
    
    var formatDescription: CMFormatDescription? = nil
//    var formatDescription: CMFormatDescription? {
//        didSet {
//            if !CMFormatDescriptionEqual(formatDescription, oldValue) {
//                delegate?.didSetFormatDescription(audio: formatDescription)
//            }
//        }
//    }
    
    override init() {
        super.init()
    }
    
    func setupEncoder(sampleBuffer: CMSampleBuffer) {
        guard converter == nil else {
            print("already created")
            return
        }
        
        var inAudioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(CMSampleBufferGetFormatDescription(sampleBuffer)!)!.pointee
        
        var outAudioStreamBasicDescription : AudioStreamBasicDescription = AudioStreamBasicDescription(
            mSampleRate: 44100, // inAudioStreamBasicDescription.mSampleRate,
            mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: UInt32(MPEG4ObjectID.AAC_LC.rawValue),
            mBytesPerPacket: 0,
            mFramesPerPacket: 1024,
            mBytesPerFrame: 0,
            mChannelsPerFrame: inAudioStreamBasicDescription.mChannelsPerFrame,
            mBitsPerChannel: 0,
            mReserved: 0)
    
        CMAudioFormatDescriptionCreate(
            kCFAllocatorDefault, &outAudioStreamBasicDescription, 0, nil, 0, nil, nil, &formatDescription
        )
        
        let status = AudioConverterNewSpecific(
            &inAudioStreamBasicDescription,
            &outAudioStreamBasicDescription,
            1, &classDescription,
            &converter)
        
        if status != noErr {
            print("error : \(status.description)")
        }
        
        var outputBitRate = 192000
        let propSize = UInt32(MemoryLayout.size(ofValue: outputBitRate))
        guard let converter = self.converter, AudioConverterSetProperty(converter, kAudioConverterEncodeBitRate, propSize, &outputBitRate) == 0 else {
            print("setting bitrate")
            return
        }
    }
    
    func onInputDataForAudioConverter(
        _ ioNumberDataPackets: UnsafeMutablePointer<UInt32>,
        ioData: UnsafeMutablePointer<AudioBufferList>,
        outDataPacketDescription: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?) -> OSStatus {
        
        guard let bufferList: UnsafeMutableAudioBufferListPointer = currentBufferList else {
            ioNumberDataPackets.pointee = 0
            return -1
        }
        
        memcpy(ioData, bufferList.unsafePointer, AudioBufferList.sizeInBytes(maximumBuffers: 1))
        ioNumberDataPackets.pointee = 1
        free(bufferList.unsafeMutablePointer)
        currentBufferList = nil
        
        return noErr
    }
    
    private var inputDataProc: AudioConverterComplexInputDataProc = {(
        converter: AudioConverterRef,
        ioNumberDataPackets: UnsafeMutablePointer<UInt32>,
        ioData: UnsafeMutablePointer<AudioBufferList>,
        outDataPacketDescription: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?,
        inUserData: UnsafeMutableRawPointer?) in
        return Unmanaged<AudioEncoder>.fromOpaque(inUserData!).takeUnretainedValue().onInputDataForAudioConverter(
            ioNumberDataPackets,
            ioData: ioData,
            outDataPacketDescription: outDataPacketDescription
        )
    }
    
    let inInputDataProc : AudioConverterComplexInputDataProc = {
        ( inAudioConverter : AudioConverterRef,
          ioNumberDataPackets: UnsafeMutablePointer<UInt32>,
          ioData: UnsafeMutablePointer<AudioBufferList>,
          outDataPacketDescription: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?,
          inUserData: UnsafeMutableRawPointer? ) in
        
            var audioBufferList = inUserData!.assumingMemoryBound(to: AudioBufferList.self).pointee    // struct
            //        var audioBufferList : AudioBufferList = Unmanaged<AudioBufferList>.fromOpaque(inUserData!).takeUnretainedValue()  // error : Unmanaged needs parameter type as class

            ioData.pointee.mBuffers.mData = audioBufferList.mBuffers.mData;
            ioData.pointee.mBuffers.mDataByteSize = audioBufferList.mBuffers.mDataByteSize;
        
        return noErr
    }
    
    func encodeSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let format : CMAudioFormatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return
        }
        
        if converter == nil {
            setupEncoder(sampleBuffer: sampleBuffer)
        }
        
        var blockBuffer: CMBlockBuffer?
        
        currentBufferList = AudioBufferList.allocate(maximumBuffers: 1)
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, nil,
            currentBufferList!.unsafeMutablePointer,
            AudioBufferList.sizeInBytes(maximumBuffers: 1),
            kCFAllocatorDefault, kCFAllocatorDefault, 0,
            &blockBuffer)
        
        if blockBuffer == nil {
            print("blockBuffer not available");
            return
        }
        
        var isOutputDataPacketSize: UInt32 = 1
        let dataLength = CMBlockBufferGetDataLength(blockBuffer!);
        
        let outputData: UnsafeMutableAudioBufferListPointer = AudioBufferList.allocate(maximumBuffers: 1)
        outputData[0].mData = UnsafeMutableRawPointer.allocate(byteCount: dataLength, alignment: 0)
        outputData[0].mDataByteSize = UInt32(dataLength)
        outputData[0].mNumberChannels = 1
        
        let status = AudioConverterFillComplexBuffer(
            converter!,
            inInputDataProc,
            UnsafeMutableRawPointer(currentBufferList!.unsafeMutablePointer),
            &isOutputDataPacketSize, outputData.unsafeMutablePointer, nil)
        switch status {
        // kAudioConverterErr_InvalidInputSize: perhaps mistake. but can support macOS BuiltIn Mic #61
            case noErr, kAudioConverterErr_InvalidInputSize:
                var result: CMSampleBuffer?
                var timing: CMSampleTimingInfo = CMSampleTimingInfo(sampleBuffer: sampleBuffer)
                let numSamples: CMItemCount = sampleBuffer.numSamples
                CMSampleBufferCreate(kCFAllocatorDefault, nil, false, nil, nil, formatDescription, numSamples, 1, &timing, 0, nil, &result)
                CMSampleBufferSetDataBufferFromAudioBufferList(result!, kCFAllocatorDefault, kCFAllocatorDefault, 0, outputData.unsafePointer)
                
                delegate?.didEncode(sampleBuffer: result!)
            default: break;
        }
        
        for i in 0..<outputData.count {
            free(outputData[i].mData)
        }
        
        free(outputData.unsafeMutablePointer)
    }

    func encode() {
        print("[AudioEncoder] encode");
    }
}
