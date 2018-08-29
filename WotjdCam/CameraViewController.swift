//
//  CameraViewController.swift
//  WotjdCam
//
//  Created by wotjd on 2018. 8. 13..
//  Copyright © 2018년 wotjd. All rights reserved.
//

import UIKit
import CoreFoundation
import VideoToolbox
import Alamofire

class CameraViewController : UIViewController {
    var frameExtractor: FrameExtractor!
    var videoEncoder: VideoEncoder!
    var audioEncoder: AudioEncoder!
    
    @IBOutlet weak var imageView: UIImageView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        initAudioDecoder()
        initVideoDecoder()
        initFrameExtractor()
    }
    
}

extension CameraViewController : FrameExtractorDelegate {
    func initFrameExtractor() {
        frameExtractor = FrameExtractor()
        
        // set viewController to be the delegate
        frameExtractor.delegate = self
    }
    
    func compressToH264(sampleBuffer: CVImageBuffer, presentationTimeStamp: CMTime, duration: CMTime) {
        videoEncoder.encode(sampleBuffer, presentationTimeStamp: presentationTimeStamp, duration: duration)
    }
    
    func compressToAAC(sampleBuffer: CMSampleBuffer) {
        audioEncoder.encodeSampleBuffer(sampleBuffer)
        
    }
    
    func videoCaptured(image: UIImage) {
        //        NSLog("Setting image")
        imageView.image = image
    }
}

extension CameraViewController : VideoEncoderDelegate {
    func initVideoDecoder() {
        videoEncoder = VideoEncoder()
        
        videoEncoder.delegate = self
    }
    
    func didEncodeFrame(frame: CMSampleBuffer) {
//        print("frame encoded.")
        
        //----AVCC to Elem stream-----//
        let elementaryStream = NSMutableData()
        
        // 1. check if CMBuffer had I-frame
        var isIFrame:Bool = false
        let attachmentsArray:CFArray = CMSampleBufferGetSampleAttachmentsArray(frame, false)!
        
        // check how many attachments
        if CFArrayGetCount(attachmentsArray) > 0 {
            let dict = CFArrayGetValueAtIndex(attachmentsArray, 0)
            let dictRef:CFDictionary = unsafeBitCast(dict, to: CFDictionary.self)
            
            // get value
            if CFDictionaryGetValue(dictRef, unsafeBitCast(kCMSampleAttachmentKey_NotSync, to: UnsafeRawPointer.self)) != nil {
//                print ("IFrame found...")
                isIFrame = true
            }
        }
        
        // 2. define the start code
        let nStartCodeLength:size_t = 4
        let nStartCode:[UInt8] = [0x00, 0x00, 0x00, 0x01]
        
        // 3. write the SPS and PPS before I-frame
        if isIFrame {
            let description:CMFormatDescription = CMSampleBufferGetFormatDescription(frame)!
            
            // how many params
            var numParams:size_t = 0
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description, 0, nil, nil, &numParams, nil)
            
            // write each param-set to elementary stream
//            print("Write param to elementaryStream ", numParams)
            for i in 0 ..< numParams {
                var parameterSetPointer:UnsafePointer<UInt8>? = nil
                var parameterSetLength:size_t = 0
                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description, i, &parameterSetPointer, &parameterSetLength, nil, nil)
                elementaryStream.append(nStartCode, length: nStartCodeLength)
                elementaryStream.append(parameterSetPointer!, length: parameterSetLength)
            }
        }
        
        // 4. Get a pointer to the raw AVCC NAL unit data in the sample buffer
        var blockBufferLength:size_t = 0
        var bufferDataPointer: UnsafeMutablePointer<Int8>? = nil
        CMBlockBufferGetDataPointer(CMSampleBufferGetDataBuffer(frame)!, 0, nil, &blockBufferLength, &bufferDataPointer)
//        print ("Block length = ", blockBufferLength)
        
        // 5. Loop through all the NAL units in the block buffer
        var bufferOffset:size_t = 0
        let AVCCHeaderLength:Int = 4
        while (bufferOffset < (blockBufferLength - AVCCHeaderLength) ) {
            
            // Read the NAL unit length
            var NALUnitLength:UInt32 =  0
            memcpy(&NALUnitLength, bufferDataPointer! + bufferOffset, AVCCHeaderLength)

            // Big-Endian to Little-Endian
            NALUnitLength = CFSwapInt32(NALUnitLength)
            
            if ( NALUnitLength > 0 ){
//                print ( "NALUnitLen = ", NALUnitLength)
                
                // Write start code to the elementary stream
                elementaryStream.append(nStartCode, length: nStartCodeLength)
                
                // Write the NAL unit without the AVCC length header to the elementary stream
                elementaryStream.append(bufferDataPointer! + bufferOffset + AVCCHeaderLength, length: Int(NALUnitLength))
                
                // Move to the next NAL unit in the block buffer
                bufferOffset += AVCCHeaderLength + size_t(NALUnitLength);
//                print("Moving to next NALU...")
            }
        }
//        print("Read completed...")
        
        let pts = CMSampleBufferGetPresentationTimeStamp(frame).value
//        print("pts = \(String(pts))")
        
        Alamofire.upload(elementaryStream as Data , to: "http://192.168.0.10:3000/upload?av=video&pts=" + String(pts))
    }
    
    func didFailToEncodeFrame() {
        print("frame drop while encoding")
    }
}

extension CMBlockBuffer {
    var dataLength: Int {
        return CMBlockBufferGetDataLength(self)
    }
    
    var data: Data? {
        var length: Int = 0
        var buffer: UnsafeMutablePointer<Int8>? = nil
        guard CMBlockBufferGetDataPointer(self, 0, nil, &length, &buffer) == noErr else {
            return nil
        }
        return Data(bytes: buffer!, count: length)
    }
}

extension CameraViewController : AudioEncoderDelegate {
    func initAudioDecoder() {
        audioEncoder = AudioEncoder()
        
        audioEncoder.delegate = self
    }
    
    func getAdts(_ length: Int) -> [UInt8] {
        let type : UInt8 = 2    // AAC-LC
        let frequency : UInt8 = 4   // 44100Hz
        let channel : UInt8 = 1
        
        let size: Int = 7
        let fullSize: Int = size + length
        var adts: [UInt8] = [UInt8](repeating: 0x00, count: size)
        adts[0] = 0xFF
        adts[1] = 0xF9
        adts[2] = (type - 1) << 6 | (frequency << 2) | (channel >> 2)
        adts[3] = (channel & 3) << 6 | UInt8(fullSize >> 11)
        adts[4] = UInt8((fullSize & 0x7FF) >> 3)
        adts[5] = ((UInt8(fullSize & 7)) << 5) + 0x1F
        adts[6] = 0xFC
        
        return adts
    }
    
    func didEncode(sampleBuffer: CMSampleBuffer) {
        guard let payload: Data = sampleBuffer.dataBuffer?.data else {
            print("sample data is null")
            return
        }
        var aac : Data = Data()
        
        aac.append(contentsOf: getAdts(payload.count))
        aac.append(payload)
        
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).value
//        print("[AudioEncoderDelegate] encoded : pts = \(String(pts))")
        
        Alamofire.upload(aac, to: "http://192.168.0.10:3000/upload?av=audio&pts=" + String(pts))
    }
    
    func didFailToEncode() {
        print("failed to encode")
    }
    

}
