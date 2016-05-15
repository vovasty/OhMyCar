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
    @IBOutlet weak var errorView: UIView!
    @IBOutlet weak var errorLabel: UILabel!
    @IBOutlet weak var openSettingsButton: UIButton!
    
    weak var delegate: CaptureViewControllerDelegate?
    
    override var setupResult: CamSetupResult {
        didSet {
            switch self.setupResult {
            case .Success:
                self.errorView.hidden = true
                break
            case .CameraNotAuthorized:
                dispatch_async(dispatch_get_main_queue()) {
                    self.errorView.hidden = false
                    self.errorLabel.text = "Have no permission to use the camera"
                    self.openSettingsButton.hidden = false
                }
            case .SessionConfigurationFailed:
                dispatch_async(dispatch_get_main_queue()) {
                    self.errorView.hidden = false
                    self.openSettingsButton?.hidden = true
                    self.errorLabel.text = "Unable to use the camera"
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
        self.image = nil
        self.editable = false
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
            captureButton.hidden = true
        }
    }
    
    var editable: Bool = true {
        didSet {
            discardButton.hidden = !editable
        }
    }
    
    func capture() {
        imageView.hidden = true
        
        showCurtain()
        snapStillImage { (image, error) in
            guard let image = image where error == nil else {
                self.image = nil
                self.editable = false
                self.hideCurtain()
                return
            }
            
            self.image = image
            self.imageView.hidden = false
            self.captureButton.hidden = true
            
            self.delegate?.captureViewController(self, didCaptureImage: image)
            self.hideCurtain()
        }
    }
    
    @IBAction func openSettings(sender: AnyObject) {
        UIApplication.sharedApplication().openURL(NSURL(string: UIApplicationOpenSettingsURLString)!)
    }
    
    
    @IBAction func discard(sender: AnyObject) {
        self.captureButton.hidden = true
        delegate?.captureViewController(self, didDiscardImage: self.imageView.image)
        
        transition { () in
            self.captureButton.hidden = false
            self.imageView.image = nil
            self.imageView.hidden = true
        }
    }
    
    func clear() {
        transition { () in
            self.imageView.hidden = true
            self.captureButton.hidden = true
            self.imageView.image = nil
        }
    }
    
    @IBAction func capture(sender: AnyObject) {
        capture()
    }
    
    private func showCurtain(closure: (()->Void)? = nil) {
        curtainView.hidden = false
        curtainView.alpha = 0
        
        UIView.animateWithDuration(0.25, animations: {
            self.curtainView.alpha = 1
            }, completion: { (_) in
                closure?()
        })
    }
    
    private func hideCurtain() {
        UIView.animateWithDuration(0.25, animations: {
            self.curtainView.alpha = 0
            }, completion: { (_) in
                self.curtainView.hidden = true
        })
    }

    private func transition(closure: ()->Void) {
        showCurtain {
            closure()
            self.hideCurtain()
        }
    }
}

