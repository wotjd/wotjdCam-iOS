//
//  CameraViewController.swift
//  WotjdCam
//
//  Created by wotjd on 2018. 8. 13..
//  Copyright © 2018년 wotjd. All rights reserved.
//

import UIKit
import Photos
import CoreFoundation
import VideoToolbox
import Alamofire

extension CMBlockBuffer {
    var data: Data? {
        var length: Int = 0
        var buffer: UnsafeMutablePointer<Int8>? = nil
        guard CMBlockBufferGetDataPointer(self, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &buffer) == noErr else {
            return nil
        }
        return Data(bytes: buffer!, count: length)
    }
}

class CameraViewController : UIViewController {
    var frameExtractor: FrameExtractor!
    var videoEncoder: VideoEncoder?
    var audioEncoder: AudioEncoder?
    var fileWriter: AVFileWriter?
    var firstFrame = false
    var isRecording = false
    let useWriterAsEncoder = false
    var currentPath : URL!
    
    @IBOutlet weak var camView: UIView!
    @IBOutlet weak var recordSwitch: UISwitch!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        initFrameExtractor()
        initAudioEncoder()
        initVideoEncoder()
        initfileWriter()
    }
    
    func setRecordState(_ state: Bool) {
        if state {
            if !self.isRecording {
                currentPath = getTempPath()
                self.fileWriter?.startWriter(currentPath)
                self.videoEncoder?.startEncoding()
                self.audioEncoder?.startEncoding()
                self.frameExtractor.startCapturing()
                isRecording = true
            }
        } else if self.isRecording {
            self.frameExtractor.stopCapturing()
            self.audioEncoder?.stopEncoding()
            self.videoEncoder?.stopEncoding()
            self.fileWriter?.stopWriter { url in
                print("writing has done : \(url)")
                PHPhotoLibrary.shared().performChanges({ () -> Void in
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                }) { (isSuccess, error) in
                    print("saving video has done")
                }
            }
            self.isRecording = false;
        }
    }
    
    @IBAction func onRecord(_ sender: UISwitch) {
        self.setRecordState(sender.isOn)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        self.frameExtractor.stopSession()
        self.setRecordState(false)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        self.frameExtractor.startSession()
    }
    
}

extension CameraViewController {
    func initfileWriter() {
        self.fileWriter = AVFileWriter(self.useWriterAsEncoder, false)
    }
    
    func getTempPath() -> URL? {
        let directory = NSTemporaryDirectory() as NSString
        
        guard directory != "" else {
            return nil
        }
        
        let path = directory.appendingPathComponent(NSUUID().uuidString + ".mp4")
        print("\(path)")
        
        return URL(fileURLWithPath: path)
    }
}

extension CameraViewController : FrameExtractorDelegate {
    func initFrameExtractor() {
        self.frameExtractor = FrameExtractor(camView)
        self.frameExtractor.delegate = self
        self.frameExtractor.startSession()
    }
    
    func compressToH264(_ sampleBuffer: CMSampleBuffer) {
        if self.useWriterAsEncoder {
            self.fileWriter?.appendBuffer(sampleBuffer, isVideo: true)
        } else {
            guard let buffer: CVImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                print("[FrameExtractor] cannot get CVImageBuffer")
                return
            }
            
            self.videoEncoder?.encode(buffer, presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer), duration: CMSampleBufferGetDuration(sampleBuffer))
        }
    }
    
    func compressToAAC(_ sampleBuffer: CMSampleBuffer) {
        if useWriterAsEncoder {
            self.fileWriter?.appendBuffer(sampleBuffer, isVideo: false)
        } else {
            self.audioEncoder?.encodeSampleBuffer(sampleBuffer)
        }
    }
}

extension CameraViewController : VideoEncoderDelegate {
    func didGetVideoFormatDescription(desc: CMFormatDescription?) {
        guard desc != nil else {
            return
        }
        self.fileWriter?.addVideoInput(desc)
    }
    
    func initVideoEncoder() {
        self.videoEncoder = VideoEncoder()
        self.videoEncoder!.delegate = self
    }
    
    func didEncodeH264(sampleBuffer: CMSampleBuffer) {
        makeVideoPacket(sampleBuffer: sampleBuffer)
        
        if !self.useWriterAsEncoder {
            self.fileWriter?.appendBuffer(sampleBuffer, isVideo: true)
        } else {
            print("warning! encoded with custom encoder while useWriterAsEncoder flag has set!")
        }
//        Alamofire.upload(elementaryStream as Data , to: "http://192.168.0.10:3000/upload?av=video&pts=" + String(pts))
    }
    
    func makeVideoPacket(sampleBuffer: CMSampleBuffer) {
        //----AVCC to Elem stream-----//
        let elementaryStream = NSMutableData()
        
        // 1. check if CMBuffer had I-frame
        var isIFrame:Bool = false
        let attachmentsArray:CFArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)!
        
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
            let description:CMFormatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)!
            
            // how many params
            var numParams:size_t = 0
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: &numParams, nalUnitHeaderLengthOut: nil)
            
            // write each param-set to elementary stream
            //            print("Write param to elementaryStream ", numParams)
            for i in 0 ..< numParams {
                var parameterSetPointer:UnsafePointer<UInt8>? = nil
                var parameterSetLength:size_t = 0
                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description, parameterSetIndex: i, parameterSetPointerOut: &parameterSetPointer, parameterSetSizeOut: &parameterSetLength, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
                elementaryStream.append(nStartCode, length: nStartCodeLength)
                elementaryStream.append(parameterSetPointer!, length: parameterSetLength)
            }
        }
        
        // 4. Get a pointer to the raw AVCC NAL unit data in the sample buffer
        var blockBufferLength:size_t = 0
        var bufferDataPointer: UnsafeMutablePointer<Int8>? = nil
        CMBlockBufferGetDataPointer(CMSampleBufferGetDataBuffer(sampleBuffer)!, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &blockBufferLength, dataPointerOut: &bufferDataPointer)
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
        
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).value
        //        print("pts = \(String(pts))")
    }
}

extension CameraViewController : AudioEncoderDelegate {
    func initAudioEncoder() {
        self.audioEncoder = AudioEncoder()
        
        self.audioEncoder!.delegate = self
    }

    func didGetAudioFormatDescription(desc: CMFormatDescription?) {
        guard desc != nil else {
            return
        }

        self.fileWriter?.addAudioInput(desc)
    }
    
    func didEncodeAAC(sampleBuffer: CMSampleBuffer) {
        makeAudioPacket(sampleBuffer)
        
        if !self.useWriterAsEncoder {
            self.fileWriter?.appendBuffer(sampleBuffer, isVideo: false)
        }
//        Alamofire.upload(aac, to: "http://192.168.0.10:3000/upload?av=audio&pts=" + String(pts))
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
    
    func makeAudioPacket(_ sampleBuffer: CMSampleBuffer) {
        guard let payload: Data = sampleBuffer.dataBuffer?.data else {
            print("sample data is null")
            return
        }
        var aac : Data = Data()
        
        aac.append(contentsOf: getAdts(payload.count))
        aac.append(payload)
        
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).value
    }
}
