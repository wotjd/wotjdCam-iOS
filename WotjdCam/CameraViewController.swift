//
//  ViewController.swift
//  WotjdCam
//
//  Created by wotjd on 2018. 8. 9..
//  Copyright © 2018년 wotjd. All rights reserved.
//

import UIKit
import AVFoundation


class CameraViewController: UIViewController {
    @IBOutlet weak var statusLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        if discoverCamera() {
            print("found camera!")
        } else {
            print("camera not found")
        }
    }
    
    func discoverCamera() -> Bool {
        let deviceDiscoverySession = AVCaptureDevice.default(.builtInWideAngleCamera, for: AVMediaType.video, position: .back)
        
        guard let captureDevice = deviceDiscoverySession else {
            print("Failed to get the camera device")
            return false
        }
        
        print("\(captureDevice.localizedName)")
        return true
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    @IBAction func onCheckButton(_ sender: Any) {
//        statusLabel
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:   // The user has previously granted access to the camera
            statusLabel.text = "authorized"
        case .notDetermined:// The user has not yet been asked for camera access.
            statusLabel.text = "notDetermined"
        case .denied:       // The user has previously denied access.
            statusLabel.text = "denied"
        case .restricted:   // The user can't grant access due to restrictions
            statusLabel.text = "restricted"
        }
    }
    
    @IBAction func onRequestButton(_ sender: Any) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            if granted {
                NSLog("permission granted")
            }
        }
    }
}
