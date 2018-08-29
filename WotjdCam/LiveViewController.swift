//
//  LiveViewController.swift
//  WotjdCam
//
//  Created by wotjd on 2018. 8. 21..
//  Copyright © 2018년 wotjd. All rights reserved.
//

import UIKit
import HaishinKit
import AVFoundation

class LiveViewController: UIViewController {
    @IBOutlet weak var hkView: GLHKView!

    override func viewDidLoad() {
        print("hi")
        super.viewDidLoad()
        
        let session: AVAudioSession = AVAudioSession.sharedInstance()
        do {
            try session.setPreferredSampleRate(44_100)
            try session.setCategory(AVAudioSessionCategoryPlayAndRecord, with: .allowBluetooth)
            try session.setMode(AVAudioSessionModeDefault)
            try session.setActive(true)
        } catch {
        }
        
        let httpStream = HTTPStream()
        httpStream.attachCamera(AVCaptureDevice.default(for: .video))
        httpStream.attachAudio(AVCaptureDevice.default(for: .audio))
        httpStream.publish("hello")
        
        let view = HKView(frame: self.hkView.bounds)
        view.attachStream(httpStream)
        
        let httpService = HLSService(domain: "192.168.0.9", type: "_http._tcp", name: "hk", port: 8080)
        httpService.startRunning()
        httpService.addHTTPStream(httpStream)
        
        hkView.addSubview(view)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

}
