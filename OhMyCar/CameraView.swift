//
//  CameraView.swift
//  Ohmycar
//
//  Created by Solomenchuk, Vlad on 5/11/16.
//  Copyright © 2016 Aramzamzam LLC. All rights reserved.
//

import UIKit
import AVFoundation

class CameraView: UIView {

    override class func layerClass() -> AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    var session: AVCaptureSession {
        set {
            (self.layer as! AVCaptureVideoPreviewLayer).session = newValue
            (self.layer as! AVCaptureVideoPreviewLayer).videoGravity = AVLayerVideoGravityResizeAspectFill
        }
        
        get {
             return (layer as! AVCaptureVideoPreviewLayer).session
        }
    }
}
