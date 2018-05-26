//
//  CameraViewController.swift
//  Ohmycar
//
//  Created by Solomenchuk, Vlad on 5/11/16.
//  Copyright © 2016 Aramzamzam LLC. All rights reserved.
//

import UIKit
import AVFoundation

enum CamSetupResult {
    case Success, CameraNotAuthorized, SessionConfigurationFailed
}

private extension AVCaptureVideoOrientation {
    var uiInterfaceOrientation: UIInterfaceOrientation {
        get {
            switch self {
            case .landscapeLeft:        return .landscapeLeft
            case .landscapeRight:       return .landscapeRight
            case .portrait:             return .portrait
            case .portraitUpsideDown:   return .portraitUpsideDown
            }
        }
    }
    
    init(ui: UIInterfaceOrientation) {
        switch ui {
        case .landscapeRight:       self = .landscapeRight
        case .landscapeLeft:        self = .landscapeLeft
        case .portrait:             self = .portrait
        case .portraitUpsideDown:   self = .portraitUpsideDown
        default:                    self = .portrait
        }
    }
    
    init(ui: UIDeviceOrientation) {
        switch ui {
        case .landscapeRight:       self = .landscapeRight
        case .landscapeLeft:        self = .landscapeLeft
        case .portrait:             self = .portrait
        case .portraitUpsideDown:   self = .portraitUpsideDown
        default:                    self = .portrait
        }
    }
}

class CameraViewController: UIViewController, CameraControllerDelegate {
    func cameraController(_ controller: CameraController, capturingImage: Bool) {
        guard capturingImage else { return }
        
        self.previewView.layer.opacity = 0.0
        UIView.animate(withDuration: 0.25){
            self.previewView.layer.opacity = 1.0
        }
    }
    
    func cameraController(_ controller: CameraController, sessionRunning: Bool) {
        
    }
    
    private let previewView = CameraView(frame: CGRect.zero)
    let cameraController = CameraController()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let focusGesture = UITapGestureRecognizer(target: self, action: #selector(focusAndExposeTap(_:)))
        view.addGestureRecognizer(focusGesture)
        
        let zoomGesture = UIPinchGestureRecognizer(target: self, action: #selector(pinchToZoom(_:)))
        view.addGestureRecognizer(zoomGesture)
        
        // Setup the preview view.
        view.insertSubview(previewView, at: 0)
        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        
        cameraController.delegate = self
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        cameraController.start()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        cameraController.stop()
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        guard let previewLayer = self.previewView.layer as? AVCaptureVideoPreviewLayer else { return }
        
        let deviceOrientation = UIDevice.current.orientation
        
        if deviceOrientation.isPortrait || deviceOrientation.isLandscape {
            previewLayer.connection?.videoOrientation = AVCaptureVideoOrientation(ui: deviceOrientation)
        }
    }
    
    func snap(closure: @escaping (Result<UIImage>) -> Void) {
        guard let previewLayer = self.previewView.layer as? AVCaptureVideoPreviewLayer else { fatalError("wrong layout") }
        
        cameraController.snap(videoOrientation: previewLayer.connection?.videoOrientation, closure: closure)
    }
    
    @objc
    private func focusAndExposeTap(_ gestureRecognizer: UIGestureRecognizer) {
        let devicePoint = (self.previewView.layer as! AVCaptureVideoPreviewLayer).captureDevicePointConverted(fromLayerPoint: gestureRecognizer.location(in: gestureRecognizer.view))
        cameraController.focus(with: .autoFocus, exposeWithMode: .autoExpose, atDevicePoint: devicePoint, monitorSubjectAreaChange: true)
    }

    @objc
    private func pinchToZoom(_ gestureRecognizer: UIPinchGestureRecognizer) {
        let pinchVelocityDividerFactor: CGFloat = 5.0
        
        guard gestureRecognizer.state == .changed else { return }
        
        let desiredZoomFactor = cameraController.zoom + atan2(gestureRecognizer.velocity, pinchVelocityDividerFactor)
        // Check if desiredZoomFactor fits required range from 1.0 to activeFormat.videoMaxZoomFactor
        cameraController.zoom = desiredZoomFactor
    }
    
    // MARK: CameraControllerDelegate
    
    func cameraControllerDidFinishSetup(_ controller: CameraController) {
        // Use the status bar orientation as the initial video orientation. Subsequent orientation changes are handled by
        // -[viewWillTransitionToSize:withTransitionCoordinator:].
        let statusBarOrientation = UIApplication.shared.statusBarOrientation
        var initialVideoOrientation = AVCaptureVideoOrientation.portrait
        if ( statusBarOrientation != .unknown ) {
            initialVideoOrientation = AVCaptureVideoOrientation(ui: statusBarOrientation)
        }
        
        let previewLayer = self.previewView.layer as! AVCaptureVideoPreviewLayer
        previewLayer.connection?.videoOrientation = initialVideoOrientation
    }
    
    func cameraController(_ controller: CameraController, setupFailedWith error: Error) {
        print(error)
    }
}
