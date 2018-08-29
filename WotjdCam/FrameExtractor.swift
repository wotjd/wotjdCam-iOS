//
//  FrameExtactor.swift
//  WotjdCam
//
//  Created by wotjd on 2018. 8. 10..
//  Copyright © 2018년 wotjd. All rights reserved.
//

import UIKit
import AVFoundation
import VideoToolbox
import CoreFoundation

protocol FrameExtractorDelegate: class {
    func compressToH264(sampleBuffer: CVImageBuffer, presentationTimeStamp: CMTime, duration: CMTime)
    func compressToAAC(sampleBuffer: CMSampleBuffer)
    func videoCaptured(image: UIImage)
}

// The way AVCaptureVideoDataOutput works is by having a delegate object
// it can send each frame.
class FrameExtractor : NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    // The session coordinates the flow of data from the input to output
    weak var delegate: FrameExtractorDelegate?
    private let captureSession = AVCaptureSession()
    
    // create a serial queue, to be not blocked main thread when use the session
    private let sessionQueue = DispatchQueue(label: "session queue")
    
    // track if the permission is granted
    private var permissionGranted = false
    
    private let position = AVCaptureDevice.Position.back
    private let quality = AVCaptureSession.Preset.high
    
    private let context = CIContext()
    
    override init() {
        super.init()
//        print("FrameExtractor : Init")
        checkPermission()
        sessionQueue.sync { [unowned self] in
            self.configureSession()
            self.captureSession.startRunning()
        }
    }
    
    // MARK: AVSession configuration
    private func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: AVMediaType.video) {
        case .authorized :
            // The user has explicitly granted permission for media capture
            permissionGranted = true
        case .notDetermined :
            // The user has not yet been presented with the option to grant video access
            requestPermission()
        default :
            // The user has denied permisssion
            permissionGranted = false
        }
    }
    
    private func requestPermission() {
        sessionQueue.suspend()
        AVCaptureDevice.requestAccess(for: AVMediaType.video) { [unowned self] granted in
            self.permissionGranted = granted
            self.sessionQueue.resume()
        }
    }
    
    private func configureSession() {
        guard permissionGranted else { return }
        
        captureSession.beginConfiguration()
        defer {
            captureSession.commitConfiguration()
        }
        
        captureSession.sessionPreset = quality
        
        let (videoDevice, audioDevice) = selectCaptureDevice()
        guard videoDevice != nil else { return }
        
        // Create an AVcaptureDeviceinput
        guard let captureDeviceInput = try? AVCaptureDeviceInput(device: videoDevice!) else { return }
        
        // Check if the capture device input can be added to the session, and add it
        guard captureSession.canAddInput(captureDeviceInput) else { return }
        
        captureSession.addInput(captureDeviceInput)
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "sample buffer"))
        
        // add video output to the session
        guard captureSession.canAddOutput(videoOutput) else { return }
        
        captureSession.addOutput(videoOutput)
        
        guard let connection = videoOutput.connection(with: AVMediaType.video) else { return }
        guard connection.isVideoOrientationSupported else { return }
        connection.videoOrientation = currentVideoOrientation()
        guard connection.isVideoMirroringSupported else { return }
        connection.isVideoMirrored = position == .front
        
        
        // add audio input
        do {
            let micInput = try AVCaptureDeviceInput(device: audioDevice!)
            if captureSession.canAddInput(micInput) {
                captureSession.addInput(micInput)
            }
            
        } catch {
            print("Error Setting device audio input: \(error)");
            return
        }
        
        // add audio output
        let audioOutput = AVCaptureAudioDataOutput()
        audioOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "audio sample buffer"))
        
        
        captureSession.automaticallyConfiguresApplicationAudioSession = true
        if captureSession.canAddOutput(audioOutput) {
            captureSession.addOutput(audioOutput)
        }
    }
    
    private func currentVideoOrientation() -> AVCaptureVideoOrientation {
        var orientation: AVCaptureVideoOrientation
        
        switch UIDevice.current.orientation {
        case .portrait :
            orientation = AVCaptureVideoOrientation.portrait
        case .landscapeLeft :
            orientation = AVCaptureVideoOrientation.landscapeLeft
        case .landscapeRight :
            orientation = AVCaptureVideoOrientation.landscapeRight
        default :
            orientation = AVCaptureVideoOrientation.portraitUpsideDown
        }
        
        return orientation
    }
    
    private func selectCaptureDevice() -> (AVCaptureDevice?, AVCaptureDevice?) {
        let video = AVCaptureDevice.default(for: .video)
        let audio = AVCaptureDevice.default(for: .audio)
        return (video, audio)
    }
    
    private func imageFromSampleBuffer(sampleBuffer: CMSampleBuffer) -> UIImage? {
        // Transform the sample buffer to a CVImageBuffer
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        
        return UIImage(cgImage: cgImage)
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output is AVCaptureVideoDataOutput {
            updateView(sampleBuffer)
            compressVideo(sampleBuffer)
//            print("video : pts = \(String(CMSampleBufferGetPresentationTimeStamp(sampleBuffer).value))")
        } else if output is AVCaptureAudioDataOutput {
            compressAudio(sampleBuffer)
//            print("audio : pts = \(String(CMSampleBufferGetPresentationTimeStamp(sampleBuffer).value))")
        } else {
            print("not av stream")
        }
    }
    
    func compressAudio(_ sampleBuffer: CMSampleBuffer) {
//        guard let buffer
        
        self.delegate?.compressToAAC(sampleBuffer: sampleBuffer)
        
        return
    }
    
    func compressVideo(_ sampleBuffer: CMSampleBuffer) {
        guard let buffer: CVImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("[FrameExtractor] cannot get CVImageBuffer")
            return
        }
        
        self.delegate?.compressToH264(sampleBuffer: buffer, presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer), duration: CMSampleBufferGetDuration(sampleBuffer));
    }
    
    var lastVideo: Int64 = 0
    var lastAudio: Int64 = 0
    var frameCounter = 0
    
    func updateView(_ sampleBuffer: CMSampleBuffer) {
        var count: CMItemCount = 1
        var info = CMSampleTimingInfo()
        CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, count, &info, &count)
        
        lastVideo = info.presentationTimeStamp.value
        
//        let dts = CGFloat(info.decodeTimeStamp.value) / CGFloat(info.decodeTimeStamp.timescale) // nan
//        let duration = CGFloat(info.duration.value) / CGFloat(info.duration.timescale)          // nan
//        let pts = CGFloat(info.presentationTimeStamp.value) / CGFloat(info.presentationTimeStamp.timescale)
        
//        print("video frame (dts : \(dts), pts : \(pts), duaration : \(duration)")
        
        guard let uiImage = self.imageFromSampleBuffer(sampleBuffer: sampleBuffer) else { return }
        DispatchQueue.main.async { [unowned self] in
            self.delegate?.videoCaptured(image: uiImage)
        }
    }
}
