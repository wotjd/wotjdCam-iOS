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
            let attachments = CMSampleBufferGetSampleAttachmentsArray(self, createIfNecessary: false) else {
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
                CMSampleBufferSetDataBuffer(self, newValue: $0)
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
        return CMFormatDescriptionGetExtension(self, extensionKey: key as CFString) as? [String: AnyObject]
    }
}

public protocol AudioEncoderDelegate : class {
    func didGetAudioFormatDescription(desc: CMFormatDescription?)
    func didEncodeAAC(sampleBuffer: CMSampleBuffer)
}

class AudioEncoder: NSObject {
    fileprivate let audioEncoderQueue = DispatchQueue(label: "AudioEncoder")
    var delegate: AudioEncoderDelegate? = nil
    
    var converter : AudioConverterRef? = nil
    private var currentBufferList: UnsafeMutableAudioBufferListPointer?
    
    var classDescription : AudioClassDescription = AudioClassDescription(
        mType: kAudioEncoderComponentType,
        mSubType: kAudioFormatMPEG4AAC,
        mManufacturer: kAppleHardwareAudioCodecManufacturer)
    
    var formatDescription: CMFormatDescription? {
        didSet {
            if !CMFormatDescriptionEqual(formatDescription, otherFormatDescription: oldValue) {
                delegate?.didGetAudioFormatDescription(desc: formatDescription)
            }
        }
    }
    
    private var outAudioStreamBasicDescription : AudioStreamBasicDescription?
    
    var isRunning = false
    
    override init() {
        super.init()
    }
    
    func startEncoding() {
        audioEncoderQueue.async {
            self.isRunning = true;
        }
    }
    
    func stopEncoding() {
        audioEncoderQueue.async {
            if self.converter != nil {
                AudioConverterDispose(self.converter!)
                self.converter = nil
            }
            self.formatDescription = nil
            self.outAudioStreamBasicDescription = nil
            self.currentBufferList = nil
            self.isRunning = false
        }
    }
    
    func setupEncoder(sampleBuffer: CMSampleBuffer) {
        guard self.isRunning, converter == nil else {
            print("already created")
            return
        }
        
        var inAudioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(CMSampleBufferGetFormatDescription(sampleBuffer)!)!.pointee
        
        self.outAudioStreamBasicDescription = AudioStreamBasicDescription(
            mSampleRate: 44100, // inAudioStreamBasicDescription.mSampleRate,
            mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: UInt32(MPEG4ObjectID.aac_Main.rawValue),
            mBytesPerPacket: 0,
            mFramesPerPacket: 1024,
            mBytesPerFrame: 0,
            mChannelsPerFrame: inAudioStreamBasicDescription.mChannelsPerFrame,
            mBitsPerChannel: 0,
            mReserved: 0)
    
        CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, asbd: &self.outAudioStreamBasicDescription!, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &formatDescription
        )
        
        let status = AudioConverterNewSpecific(
            &inAudioStreamBasicDescription,
            &self.outAudioStreamBasicDescription!,
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
    
    let inInputDataProc : AudioConverterComplexInputDataProc = {
        ( inAudioConverter : AudioConverterRef,
          ioNumberDataPackets: UnsafeMutablePointer<UInt32>,
          ioData: UnsafeMutablePointer<AudioBufferList>,
          outDataPacketDescription: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?,
          inUserData: UnsafeMutableRawPointer? ) in
        
            var audioBufferList = inUserData!.assumingMemoryBound(to: AudioBufferList.self).pointee    // struct

            ioData.pointee.mBuffers.mData = audioBufferList.mBuffers.mData;
            ioData.pointee.mBuffers.mDataByteSize = audioBufferList.mBuffers.mDataByteSize;
        
        return noErr
    }
    
    func encodeSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard self.isRunning, let _ : CMAudioFormatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return
        }
        
        if converter == nil {
            setupEncoder(sampleBuffer: sampleBuffer)
        }
        
        var blockBuffer: CMBlockBuffer?
        
        currentBufferList = AudioBufferList.allocate(maximumBuffers: 1)
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: nil,
            bufferListOut: currentBufferList!.unsafeMutablePointer,
            bufferListSize: AudioBufferList.sizeInBytes(maximumBuffers: 1),
            blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0,
            blockBufferOut: &blockBuffer)
        
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
        
        var packetDescription = AudioStreamPacketDescription()
        
        let status = AudioConverterFillComplexBuffer(
            converter!,
            inInputDataProc,
            UnsafeMutableRawPointer(currentBufferList!.unsafeMutablePointer),
            //            Unmanaged.passUnretained(self).toOpaque(),
            &isOutputDataPacketSize, outputData.unsafeMutablePointer, &packetDescription)
        switch status {
        // kAudioConverterErr_InvalidInputSize: perhaps mistake. but can support macOS BuiltIn Mic #61
        case noErr, kAudioConverterErr_InvalidInputSize:
            var result: CMSampleBuffer?
//            var timing: CMSampleTimingInfo = CMSampleTimingInfo(sampleBuffer: sampleBuffer)
//            let numSamples: CMItemCount = sampleBuffer.numSamples
            
            CMAudioSampleBufferCreateWithPacketDescriptions(
                allocator: kCFAllocatorDefault,
                dataBuffer: nil,
                dataReady: false,
                makeDataReadyCallback: nil,
                refcon: nil,
                formatDescription: formatDescription!,
                sampleCount: Int(currentBufferList!.unsafePointer.pointee.mNumberBuffers),
                presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer), packetDescriptions: &packetDescription,
                sampleBufferOut: &result)
            
            CMSampleBufferSetDataBufferFromAudioBufferList(result!, blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0, bufferList: outputData.unsafePointer)
            
            if CMSampleBufferGetSampleSizeArray(result!, entryCount: 0, arrayToFill: nil, entriesNeededOut: nil) == kCMSampleBufferError_BufferHasNoSampleSizes {
                print("[AudioEncoder] sampleBuffer from audiobuffer has no sample size")
                if CMSampleBufferGetSampleSizeArray(sampleBuffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: nil) == kCMSampleBufferError_BufferHasNoSampleSizes {
                    print("[AudioEncoder] original sampleBuffer also has no sample size")
                }
            }
            
            delegate?.didEncodeAAC(sampleBuffer: result!)
        default: break;
        }
        
        for i in 0..<outputData.count {
            free(outputData[i].mData)
        }
        
        free(outputData.unsafeMutablePointer)
    }
}
