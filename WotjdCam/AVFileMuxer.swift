//
//  AVWriter.swift
//  WotjdCam
//
//  Created by wotjd on 2018. 8. 31..
//  Copyright © 2018년 wotjd. All rights reserved.
//

import AVFoundation
//import AssetsLibrary

class AVFileWriter : NSObject {
    private var assetWriter: AVAssetWriter!
    private var videoInputWriter: AVAssetWriterInput!
    private var audioInputWriter: AVAssetWriterInput!
    private var isFirstFrame = true
    private var isFirstAudio = true
    private var isStarted = false
    private let asEncoder : Bool
    private let isAudioMuted : Bool
    
    init(_ asEncoder: Bool, _ muteAudio: Bool) {
        self.asEncoder = asEncoder
        self.isAudioMuted = muteAudio
        super.init()
    }
    
    func getVideoOutputSettings() -> Dictionary<String, AnyObject>? {
        if asEncoder {
            let width = 1920, height = 1080
            return [
                AVVideoCodecKey : AVVideoCodecType.h264 as AnyObject,
                AVVideoWidthKey : width as AnyObject,
                AVVideoHeightKey : height as AnyObject
            ]
        } else {
            return nil
        }
    }
    
    func getAudioOutputSettings() -> Dictionary<String, AnyObject>? {
        if asEncoder {
            let samples = 44100, channels = 1
            return [
                AVFormatIDKey : Int(kAudioFormatMPEG4AAC) as AnyObject,
                AVNumberOfChannelsKey : channels as AnyObject,
                AVSampleRateKey : samples as AnyObject,
                AVEncoderBitRateKey : 128000 as AnyObject
            ]
        } else {
            return nil
        }
    }
    
    func initAVWriter(_ url:URL!) {
        self.assetWriter = try? AVAssetWriter(outputURL: url, fileType: AVFileType.mov)
    }
    
    func addVideoInput(_ formatDescription : CMFormatDescription?) {
        guard videoInputWriter == nil && self.isStarted else {
            print("videoInputWriter has already set")
            return
        }
        
        print("adding videoInputWriter")
        let videoOutputSettings: Dictionary<String, AnyObject>? = self.getVideoOutputSettings()
        
        self.videoInputWriter = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoOutputSettings, sourceFormatHint: formatDescription)
        
        self.videoInputWriter.expectsMediaDataInRealTime = true
        
        if self.assetWriter.canAdd(self.videoInputWriter) {
            assetWriter.add(videoInputWriter)
        }
        self.isFirstAudio = true
    }
    
    func addAudioInput(_ formatDescription : CMFormatDescription?) {
        guard audioInputWriter == nil && self.isStarted else {
            print("audioInputWriter has already set")
            return
        }
        if isAudioMuted {
            print("audio is muted")
        } else {
            print("adding audioInputWriter")
            let audioOutputSettings: Dictionary<String, AnyObject>? = self.getAudioOutputSettings()
            
            self.audioInputWriter = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: audioOutputSettings, sourceFormatHint: formatDescription) //
            
            self.audioInputWriter.expectsMediaDataInRealTime = true
            
            if self.assetWriter.canAdd(self.audioInputWriter) {
                assetWriter.add(audioInputWriter)
            }
        }
    }
    
    func startWriter(_ url:URL!) {
        guard !self.isStarted else {
            print("writer already started!")
            return
        }
        self.isFirstFrame = true
        self.initAVWriter(url)
        self.isStarted = true
    }
    
    func stopWriter(_ callback: @escaping (_ url: URL) -> Void) {
        guard self.isStarted else {
            print("[AVWriter] stopWriter : writer not started!")
            return
        }
        self.videoInputWriter.markAsFinished()
        if !self.isAudioMuted {
            self.audioInputWriter.markAsFinished()
        }
        
        self.assetWriter.finishWriting {
            self.videoInputWriter = nil
            self.audioInputWriter = nil
            
            callback(self.assetWriter.outputURL)
            
            self.assetWriter = nil
            self.isStarted = false
        }
    }
    
    func appendBuffer(_ sampleBuffer: CMSampleBuffer, isVideo: Bool) {
        guard self.isStarted else {
            print("[AVWriter] appendBuffer : writer not started!")
            return
        }
        
        if !isVideo && self.isFirstFrame {
            print("ignoring audio frame before first video frame..")
        } else if CMSampleBufferDataIsReady(sampleBuffer) {
            if self.assetWriter.status == AVAssetWriter.Status.unknown {
                addVideoInput(CMSampleBufferGetFormatDescription(sampleBuffer))
                print("Start writing, isVideo = \(isVideo), status = \(self.assetWriter.status.rawValue)")
                let startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                self.assetWriter.startWriting()
                self.assetWriter.startSession(atSourceTime: startTime)
                self.isFirstFrame = false
            }
            
            if self.assetWriter.status == AVAssetWriter.Status.failed {
                print("Error occured, isVideo = \(isVideo), status = \(self.assetWriter.status.rawValue), \(self.assetWriter.error!.localizedDescription)")
//                return
            }
            
            if isVideo {
                if self.videoInputWriter.isReadyForMoreMediaData {
                    self.videoInputWriter.append(sampleBuffer)
                }
            } else if !self.isAudioMuted {
                if self.audioInputWriter.isReadyForMoreMediaData {
                    if self.isFirstAudio {
                        let dict = CMTimeCopyAsDictionary(CMTimeMake(value: 1024, timescale: 44100), allocator: kCFAllocatorDefault)
                        CMSetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_TrimDurationAtStart, value: dict, attachmentMode: kCMAttachmentMode_ShouldNotPropagate)
                        print("setting attachment.")
                        self.isFirstAudio = false
                    }
                    if !self.audioInputWriter.append(sampleBuffer) {
                        print("Failed to append sample buffer to asset writer input: \(assetWriter.error!)")
                        print("Audio file writer status: \(assetWriter.status.rawValue)")
                        // 12735, kBufferHasNoSampleSizes
                    }
                }
            }
        }
    }
}
