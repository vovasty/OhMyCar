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
                self.errorView.isHidden = true
                break
            case .CameraNotAuthorized:
                DispatchQueue.main.async {
                    self.errorView.isHidden = false
                    self.errorLabel.text = "Have no permission to use the camera"
                    self.openSettingsButton.isHidden = false
                }
            case .SessionConfigurationFailed:
                DispatchQueue.main.async {
                    self.errorView.isHidden = false
                    self.openSettingsButton?.isHidden = true
                    self.errorLabel.text = "Unable to use the camera"
                }
                break
            }

        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        imageView.isOpaque = true
        imageView.layer.masksToBounds = true
        imageView.isHidden = true
        captureButton.isHidden = true
        self.image = nil
        self.editable = false
        curtainView.alpha = 0
    }
    
    var image: UIImage? {
        didSet {
            
            if image == nil {
                imageView.contentMode = .center
                imageView.image = UIImage(named: "LoadingScreenupper")
            }
            else {
                imageView.contentMode = .scaleAspectFill
                imageView.image = image
            }
            
            imageView.isHidden = false
            captureButton.isHidden = true
        }
    }
    
    var editable: Bool = true {
        didSet {
            discardButton.isHidden = !editable
        }
    }
    
    func capture() {
        imageView.isHidden = true
        
        showCurtain()
        snapStillImage { (image, error) in
            guard let image = image, error == nil else {
                self.image = nil
                self.editable = false
                self.hideCurtain()
                return
            }
            
            self.image = image
            self.imageView.isHidden = false
            self.captureButton.isHidden = true
            
            self.delegate?.captureViewController(controller: self, didCaptureImage: image)
            self.hideCurtain()
        }
    }
    
    @IBAction func openSettings(sender: AnyObject) {
        UIApplication.shared.openURL(URL(string: UIApplicationOpenSettingsURLString)!)
    }
    
    
    @IBAction func discard(sender: AnyObject) {
        self.captureButton.isHidden = true
        delegate?.captureViewController(controller: self, didDiscardImage: self.imageView.image)
        
        transition { () in
            self.captureButton.isHidden = self.setupResult != .Success
            self.imageView.image = nil
            self.imageView.isHidden = true
        }
    }
    
    func clear() {
        transition { () in
            self.imageView.isHidden = true
            self.captureButton.isHidden = true
            self.imageView.image = nil
        }
    }
    
    @IBAction func capture(sender: AnyObject) {
        capture()
    }
    
    private func showCurtain(closure: (()->Void)? = nil) {
        curtainView.isHidden = false
        curtainView.alpha = 0
        
        UIView.animate(withDuration: 0.25, animations: {
            self.curtainView.alpha = 1
            }, completion: { (_) in
                closure?()
        })
    }
    
    private func hideCurtain() {
        UIView.animate(withDuration: 0.25, animations: {
            self.curtainView.alpha = 0
            }, completion: { (_) in
                self.curtainView.isHidden = true
        })
    }

    private func transition(closure: @escaping ()->Void) {
        showCurtain {
            closure()
            self.hideCurtain()
        }
    }
}

