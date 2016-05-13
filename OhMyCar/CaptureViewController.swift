//
//  CaptureViewController.swift
//  Ohmycar
//
//  Created by Solomenchuk, Vlad on 5/12/16.
//  Copyright © 2016 Aramzamzam LLC. All rights reserved.
//

import UIKit

protocol CaptureViewControllerDelegate: class {
    func captureViewController(controller: CameraViewController, didCaptureImage image: UIImage?)
}

class CaptureViewController: CameraViewController {
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var captureButton: UIButton!
    @IBOutlet weak var curtainView: UIView!
    weak var delegate: CaptureViewControllerDelegate?
    
    override var setupResult: CamSetupResult {
        didSet {
            switch self.setupResult {
            case .Success:
                break
            case .CameraNotAuthorized:
                dispatch_async(dispatch_get_main_queue()) {
                    //                    self.delegate?.cameraViewController(self, failedToStart: NSError(domain: "net.aramzamzam.CameraViewController", code: -1, userInfo: [NSLocalizedDescriptionKey: "Camera access is not authorized"]))
                }
            case .SessionConfigurationFailed:
                dispatch_async(dispatch_get_main_queue()) {
                    //                    self.delegate?.cameraViewController(self, failedToStart: NSError(domain: "net.aramzamzam.CameraViewController", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to setup camera"]))
                }
                break
            }

        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        imageView.opaque = true
        imageView.layer.masksToBounds = true
        imageView.contentMode = .ScaleAspectFill
        imageView.hidden = true
        captureButton.hidden = true
        curtainView.alpha = 0
    }
    
    var image: UIImage? {
        set {
            imageView.image = newValue
            imageView.hidden = false
            view.bringSubviewToFront(imageView)
        }
        
        get {
            return imageView.image
        }
    }
    
    func capture() {
        imageView.hidden = true
        view.bringSubviewToFront(imageView)
        
        showCurtain()
        snapStillImage { (image, error) in
            guard let image = image where error == nil else {
                self.view.sendSubviewToBack(self.imageView)
                self.hideCurtain()
                return
            }
            
            self.imageView.image = image
            self.imageView.hidden = false
            
            dispatch_async(dispatch_get_main_queue()) {
                self.delegate?.captureViewController(self, didCaptureImage: image)
            }
            self.hideCurtain()
        }
    }
    
    @IBAction func discard(sender: AnyObject) {
        self.view.sendSubviewToBack(imageView)
        view.bringSubviewToFront(captureButton)
        self.captureButton.hidden = true
        delegate?.captureViewController(self, didCaptureImage: nil)
        
        transition { () in
            self.captureButton.hidden = false
            self.imageView.image = nil
        }
    }
    
    @IBAction func capture(sender: AnyObject) {
        capture()
    }
    
    private func showCurtain(closure: (()->Void)? = nil) {
        curtainView.alpha = 0
        view.bringSubviewToFront(curtainView)
        
        UIView.animateWithDuration(0.25, animations: {
            self.curtainView.alpha = 1
            }, completion: { (_) in
                closure?()
        })
    }
    
    private func hideCurtain() {
        view.bringSubviewToFront(curtainView)
        UIView.animateWithDuration(0.25, animations: {
            self.curtainView.alpha = 0
        })
    }

    private func transition(closure: ()->Void) {
        showCurtain {
            closure()
            self.hideCurtain()
        }
    }
}

