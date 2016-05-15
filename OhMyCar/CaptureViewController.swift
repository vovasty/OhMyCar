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
    func captureViewController(controller: CameraViewController, didDiscardImage image: UIImage?)
}

class CaptureViewController: CameraViewController {
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var captureButton: UIButton!
    @IBOutlet weak var curtainView: UIView!
    @IBOutlet weak var discardButton: UIButton!
    
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
        imageView.hidden = true
        captureButton.hidden = true
        curtainView.alpha = 0
    }
    
    var image: UIImage? {
        didSet {
            
            if image == nil {
                imageView.contentMode = .Center
                imageView.image = UIImage(named: "LoadingScreenupper")
            }
            else {
                imageView.contentMode = .ScaleAspectFill
                imageView.image = image
            }
            
            imageView.hidden = false
            view.bringSubviewToFront(imageView)
            
        }
    }
    
    var editable: Bool = true {
        didSet {
            discardButton.hidden = !editable
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
            
            self.image = image
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
        delegate?.captureViewController(self, didDiscardImage: self.imageView.image)
        
        transition { () in
            self.captureButton.hidden = false
            self.imageView.image = nil
        }
    }
    
    func clear() {
        transition { () in
            self.view.sendSubviewToBack(self.imageView)
            self.captureButton.hidden = true
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

