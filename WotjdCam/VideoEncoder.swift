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
    func didEncodeFrame(frame: CMSampleBuffer)
    func didFailToEncodeFrame()
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
            encoder.delegate?.didEncodeFrame(frame: sampleBuffer)
        } else {
            encoder.delegate?.didFailToEncodeFrame()
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
                    kCFAllocatorDefault,
                    width, height, kCMVideoCodecType_H264,
                    nil, attributes as CFDictionary, nil, callback,
                    Unmanaged.passUnretained(self).toOpaque(), &_session) == noErr else {
                        return nil
                }
                VTSessionSetProperties(_session!, properties as CFDictionary)
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
    
    func encode(_ imageBuffer: CVImageBuffer, presentationTimeStamp: CMTime, duration: CMTime) {
        guard let session: VTCompressionSession = session else {
            print("[VideoEncoder] unavailable session")
            return
        }
        
//        print("[VideoEncoder] encode frame")
        var flags: VTEncodeInfoFlags = []
        let status : OSStatus = VTCompressionSessionEncodeFrame(session, imageBuffer, presentationTimeStamp, duration, nil, nil, &flags)
        if status != noErr {
            print(status.description)
        }
    }
}
