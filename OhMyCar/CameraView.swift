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
    override class var layerClass: AnyClass {
        get {
            return AVCaptureVideoPreviewLayer.self
        }
    }

    var session: AVCaptureSession? {
        set {
            guard let layer = self.layer as? AVCaptureVideoPreviewLayer else { fatalError("no layer") }
            
            layer.session = newValue
            layer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        }
        
        get {
            return (layer as? AVCaptureVideoPreviewLayer)?.session
        }
    }
}
