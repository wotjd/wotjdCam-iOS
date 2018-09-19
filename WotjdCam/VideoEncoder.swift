//
//  VideoEncoder.swift
//  WotjdCam
//
//  Created by wotjd on 2018. 8. 22..
//  Copyright © 2018년 wotjd. All rights reserved.
//

import AVFoundation
import VideoToolbox
import CoreFoundation

public protocol VideoEncoderDelegate : class {
    func didGetVideoFormatDescription(desc: CMFormatDescription?)
    func didEncodeH264(sampleBuffer: CMSampleBuffer)
}

class VideoEncoder: NSObject {
    var delegate: VideoEncoderDelegate? = nil
    
    static let defaultAttributes:[NSString: AnyObject] = [
        kCVPixelBufferIOSurfacePropertiesKey: [:] as AnyObject,
        kCVPixelBufferOpenGLESCompatibilityKey: kCFBooleanTrue,
    ]
    
    let properties:[NSString: NSObject] = [
        kVTCompressionPropertyKey_RealTime: kCFBooleanTrue,
        kVTCompressionPropertyKey_ProfileLevel: kVTProfileLevel_H264_High_AutoLevel,
        /*kVTCompressionPropertyKey_AverageBitRate: 40000,*/
        kVTCompressionPropertyKey_ExpectedFrameRate: NSNumber(value: 60),
        kVTCompressionPropertyKey_MaxKeyFrameInterval: NSNumber(value: 2.0),
        kVTCompressionPropertyKey_AllowFrameReordering: true as NSObject,
        kVTCompressionPropertyKey_H264EntropyMode: kVTH264EntropyMode_CABAC,
        kVTCompressionPropertyKey_PixelTransferProperties: [
            kVTPixelTransferPropertyKey_ScalingMode as NSString: kVTScalingMode_Trim
            ] as NSObject
    ]
    
    private var _formatDescription: CMFormatDescription?
    private var formatDescription: CMFormatDescription? {
        get {
            return _formatDescription
        }
        set {
            if !CMFormatDescriptionEqual(newValue, otherFormatDescription: _formatDescription) {
                _formatDescription = newValue
                self.delegate?.didGetVideoFormatDescription(desc: _formatDescription)
            }
        }
    }
    
    private var callback: VTCompressionOutputCallback = {
        (outputCallbackRefCon: UnsafeMutableRawPointer?,
         sourceFrameRefCon: UnsafeMutableRawPointer?,
         status: OSStatus,
         infoFlags: VTEncodeInfoFlags,
         sampleBuffer: CMSampleBuffer?) in
//        print("[VideoEncoder] encoder callback")
        guard let refCon: UnsafeMutableRawPointer = outputCallbackRefCon else {
                print("[VideoEncoder] cannot convert encoder")
                return
        }
        
        let encoder: VideoEncoder = Unmanaged<VideoEncoder>.fromOpaque(refCon).takeUnretainedValue()
        if let sampleBuffer: CMSampleBuffer = sampleBuffer, status == noErr {
            encoder.formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)
            encoder.delegate?.didEncodeH264(sampleBuffer: sampleBuffer)
        }
    }
    
    private var _session: VTCompressionSession?
    private var session: VTCompressionSession? {
        get {
            if _session == nil {
                let width : Int32 = 1920, height : Int32 = 1080
                var attributes: [NSString: AnyObject] {
                    var attributes: [NSString: AnyObject] = VideoEncoder.defaultAttributes
                    attributes[kCVPixelBufferWidthKey] = NSNumber(value: width)
                    attributes[kCVPixelBufferHeightKey] = NSNumber(value: height)
                    return attributes
                }
                
                guard VTCompressionSessionCreate(
                    allocator: kCFAllocatorDefault,
                    width: width, height: height, codecType: kCMVideoCodecType_H264,
                    encoderSpecification: nil, imageBufferAttributes: attributes as CFDictionary, compressedDataAllocator: nil, outputCallback: callback,
                    refcon: Unmanaged.passUnretained(self).toOpaque(), compressionSessionOut: &_session) == noErr else {
                        return nil
                }
                VTSessionSetProperties(_session!, propertyDictionary: properties as CFDictionary)
            }
            return _session
        }
        set {
            if let session: VTCompressionSession = _session {
                VTCompressionSessionInvalidate(session)
            }
            _session = newValue
        }
    }
    
    func startEncoding() {
        guard let session = self.session else {
            return
        }
        VTCompressionSessionPrepareToEncodeFrames(session)
    }
    
    func stopEncoding() {
        if self.session != nil {
            self.session = nil
        }
        self.formatDescription = nil
    }
    
    func encode(_ imageBuffer: CVImageBuffer, presentationTimeStamp: CMTime, duration: CMTime) {
        guard let session: VTCompressionSession = self.session else {
            print("[VideoEncoder] unavailable session")
            return
        }
        
//        print("[VideoEncoder] encode frame")
        var flags: VTEncodeInfoFlags = []
        let status : OSStatus = VTCompressionSessionEncodeFrame(session, imageBuffer: imageBuffer, presentationTimeStamp: presentationTimeStamp, duration: duration, frameProperties: nil, sourceFrameRefcon: nil, infoFlagsOut: &flags)
        if status != noErr {
            print(status.description)
        }
    }
}
