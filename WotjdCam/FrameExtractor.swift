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
    func compressToH264(_ sampleBuffer: CMSampleBuffer)
    func compressToAAC(_ sampleBuffer: CMSampleBuffer)
}

// The way AVCaptureVideoDataOutput works is by having a delegate object
// it can send each frame.
class FrameExtractor : NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    // The session coordinates the flow of data from the input to output
    weak var delegate: FrameExtractorDelegate?
    private let captureSession = AVCaptureSession()
    private var previewLayer : AVCaptureVideoPreviewLayer!
    
    // create a serial queue, to be not blocked main thread when use the session
    private let sessionQueue = DispatchQueue(label: "session queue")
    
    // track if the permission is granted
    private var permissionGranted = false
    
    private let position = AVCaptureDevice.Position.back
    private let quality = AVCaptureSession.Preset.high
    
    private let context = CIContext()
    
    var isCapturing = false
    
    init(_ view: UIView) {
        super.init()
//        print("FrameExtractor : Init")
        checkPermission()
        self.configureSession()
        self.setPreview(view)
    }
    
    func startSession() {
        if !self.captureSession.isRunning {
            sessionQueue.sync { [unowned self] in
                self.captureSession.startRunning()
            }
        }
    }
    
    func stopSession() {
        self.stopCapturing()
        if self.captureSession.isRunning {
            self.sessionQueue.async {
                self.captureSession.stopRunning()
            }
        }
    }
    
    func startCapturing() {
        if self.captureSession.isRunning {
            print("start capturing...")
            self.isCapturing = true
        }
    }
    
    func stopCapturing() {
        print("stop capturing..")
        self.isCapturing = false
    }
    
    func setPreview(_ view: UIView) {
        self.previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
        self.previewLayer.frame = view.bounds
        self.previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(self.previewLayer)
        print("layer added")
    }
    
    // MARK: AVSession configuration
    private func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: AVMediaType.video) {
        case .authorized :
            // The user has explicitly granted permission for media capture
            self.permissionGranted = true
        case .notDetermined :
            // The user has not yet been presented with the option to grant video access
            self.requestPermission()
        default :
            // The user has denied permisssion
            self.permissionGranted = false
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
//        connection.videoOrientation = AVCaptureVideoOrientation.landscapeLeft
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
        case .portrait, .landscapeRight :
            orientation = AVCaptureVideoOrientation.landscapeRight
        default :
            orientation = AVCaptureVideoOrientation.landscapeLeft
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
        if self.isCapturing {
            if output is AVCaptureVideoDataOutput {
                compressVideo(sampleBuffer)
            } else if output is AVCaptureAudioDataOutput {
                compressAudio(sampleBuffer)
            } else {
                print("not av stream")
            }
        }
    }
    
    func compressAudio(_ sampleBuffer: CMSampleBuffer) {
        self.delegate?.compressToAAC(sampleBuffer)
    }
    
    func compressVideo(_ sampleBuffer: CMSampleBuffer) {
        self.delegate?.compressToH264(sampleBuffer)
    }
}
