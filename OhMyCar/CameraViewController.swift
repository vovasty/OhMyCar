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
}

private var CapturingStillImageContext = "CapturingStillImageContext"
private var SessionRunningContext = "SessionRunningContext"

class CameraViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let previewView = CameraView(frame: CGRect.zero)
    private let queue = DispatchQueue(label: "session queue", qos: .background)
    internal var setupResult = CamSetupResult.CameraNotAuthorized
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var stillImageOutput: AVCaptureStillImageOutput?
    
    private var sessionRunning: Bool  {
        return self.session.isRunning
    }
    
    class func deviceWithMediaType(mediaType: AVMediaType, preferringPosition position: AVCaptureDevice.Position) -> AVCaptureDevice?
    {
        let devices = AVCaptureDevice.devices(for: mediaType)
        
        return devices.first(where: { $0.position == position }) ?? devices.first
    }
    
    class func setFlashMode(flashMode: AVCaptureDevice.FlashMode, forDevice device: AVCaptureDevice) {
        guard device.hasFlash && device.isFlashModeSupported(flashMode) else {
            return
        }
        
        do {
            try device.lockForConfiguration()
        }
        catch {
            print("Could not lock device for configuration: \(error)")
            return
        }
        
        device.flashMode = flashMode
        device.unlockForConfiguration()
    }
    
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
        
        previewView.session = session
        
        self.setupResult = .Success
        
        // Check video authorization status. Video access is required and audio access is optional.
        // If audio access is denied, audio is not recorded during movie recording.
        
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            queue.suspend()
            AVCaptureDevice.requestAccess(for: AVMediaType.video, completionHandler: { (granted) in
                self.setupResult = .CameraNotAuthorized
                self.queue.resume()
            })
        default:
            self.setupResult = .CameraNotAuthorized
        }
        
        
        // Setup the capture session.
        // In general it is not safe to mutate an AVCaptureSession or any of its inputs, outputs, or connections from multiple threads at the same time.
        // Why not do all of this on the main queue?
        // Because -[AVCaptureSession startRunning] is a blocking call which can take a long time. We dispatch session setup to the sessionQueue
        // so that the main queue isn't blocked, which keeps the UI responsive.
        queue.async {
            guard self.setupResult == .Success else { return }
            
            guard let videoDevice = CameraViewController.deviceWithMediaType(mediaType: .video, preferringPosition: .back) else { return }
            let videoDeviceInput: AVCaptureDeviceInput
            
            do {
                videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            }
            catch {
                self.setupResult = .SessionConfigurationFailed
                return
            }
            
            self.session.beginConfiguration()
            
            guard self.session.canAddInput(videoDeviceInput) else {
                self.setupResult = .SessionConfigurationFailed
                return
            }
            
            self.session.addInput(videoDeviceInput)
            self.videoDeviceInput = videoDeviceInput
            
            DispatchQueue.main.async {
                // Why are we dispatching this to the main queue?
                // Because AVCaptureVideoPreviewLayer is the backing layer for AAPLPreviewView and UIView
                // can only be manipulated on the main thread.
                // Note: As an exception to the above rule, it is not necessary to serialize video orientation changes
                // on the AVCaptureVideoPreviewLayer’s connection with other session manipulation.
                
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
            
            let stillImageOutput = AVCaptureStillImageOutput()
            guard self.session.canAddOutput(stillImageOutput) else {
                self.setupResult = .SessionConfigurationFailed
                return
            }
            
            stillImageOutput.outputSettings = [AVVideoCodecKey : AVVideoCodecJPEG]
            self.session.addOutput(stillImageOutput)
            self.stillImageOutput = stillImageOutput
            self.session.commitConfiguration()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        queue.async {
            guard self.setupResult == .Success else { return }
            
            self.session.startRunning()
            self.addObservers()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        queue.async {
            guard self.setupResult == .Success else { return }
            self.session.stopRunning()
            self.removeObservers()
    }
        super.viewWillAppear(animated)
    }
    
    //MARK: Actions
    
    func snapStillImage(closure: @escaping (UIImage?, Error?)->Void) {
        guard setupResult == .Success else {
            closure(nil, nil)
            return
        }
        
        queue.async {
            guard let connection = self.stillImageOutput?.connection(with: AVMediaType.video) else { return }
            guard let previewLayer = self.previewView.layer as? AVCaptureVideoPreviewLayer else { fatalError("wrong layout") }
    
            // Update the orientation on the still image output video connection before capturing.
            connection.videoOrientation = previewLayer.connection?.videoOrientation ?? connection.videoOrientation
    
            // Flash set to Auto for Still Capture.
            CameraViewController.setFlashMode(flashMode: .auto, forDevice:self.videoDeviceInput!.device)
    
            // Capture a still image.
            self.stillImageOutput!.captureStillImageAsynchronously(from: connection) { (imageDataSampleBuffer, error) in
                guard let imageDataSampleBuffer = imageDataSampleBuffer else {
                    print( "Could not capture still image: \(error)")
                    closure(nil, error)
                    return
                }
				// The sample buffer is not retained. Create image data before saving the still image to the photo library asynchronously.
                guard let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageDataSampleBuffer), let image = UIImage(data: imageData) else {
                    print("no image")
                    return
                }

                DispatchQueue.main.async {
                    closure(image, nil)
                }
            }
        }
    }
    
    @objc
    private func focusAndExposeTap(_ gestureRecognizer: UIGestureRecognizer) {
        let devicePoint = (self.previewView.layer as! AVCaptureVideoPreviewLayer).captureDevicePointConverted(fromLayerPoint: gestureRecognizer.location(in: gestureRecognizer.view))
        self.focusWithMode(focusMode: .autoFocus, exposeWithMode: .autoExpose, atDevicePoint: devicePoint, monitorSubjectAreaChange: true)
    }

    @objc
    private func pinchToZoom(_ gestureRecognizer: UIPinchGestureRecognizer) {
        let pinchVelocityDividerFactor: CGFloat = 5.0
        
        guard gestureRecognizer.state == .changed else { return }
        
        let device = self.videoDeviceInput!.device


        do {
            try device.lockForConfiguration()
        }
        catch {
            print("Could not lock device for configuration: \(error)")
            return
        }

        let desiredZoomFactor = device.videoZoomFactor + atan2(gestureRecognizer.velocity, pinchVelocityDividerFactor)
        // Check if desiredZoomFactor fits required range from 1.0 to activeFormat.videoMaxZoomFactor
        device.videoZoomFactor = max(1.0, min(desiredZoomFactor, device.activeFormat.videoMaxZoomFactor))
        device.unlockForConfiguration()
    }
    
    //MARK: KVO and Notifications
    
    private func addObservers() {
        session.addObserver(self, forKeyPath: "running", options: .new, context: &SessionRunningContext)
        stillImageOutput?.addObserver(self, forKeyPath: "capturingStillImage", options: .new, context: &CapturingStillImageContext)
        NotificationCenter.default.addObserver(self, selector: #selector(subjectAreaDidChange(_:)), name: NSNotification.Name.AVCaptureDeviceSubjectAreaDidChange, object: videoDeviceInput!.device)

        NotificationCenter.default.addObserver(self, selector: #selector(sessionRuntimeError(_:)), name: NSNotification.Name.AVCaptureSessionRuntimeError, object: session)

        // A session can only run when the app is full screen. It will be interrupted in a multi-app layout, introduced in iOS 9,
        // see also the documentation of AVCaptureSessionInterruptionReason. Add observers to handle these session interruptions
        // and show a preview is paused message. See the documentation of AVCaptureSessionWasInterruptedNotification for other
        // interruption reasons.
        
        NotificationCenter.default.addObserver(self, selector: #selector(sessionWasInterrupted(_:)), name: NSNotification.Name.AVCaptureSessionWasInterrupted, object: session)
        
        NotificationCenter.default.addObserver(self, selector: #selector(sessionInterruptionEnded(_:)), name: NSNotification.Name.AVCaptureSessionInterruptionEnded, object: session)
    }

    
    private func removeObservers(){
        NotificationCenter.default.removeObserver(self)
        session.removeObserver(self, forKeyPath: "running", context: &SessionRunningContext)
        stillImageOutput?.removeObserver(self, forKeyPath: "capturingStillImage", context: &CapturingStillImageContext)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        switch context {
        case &CapturingStillImageContext:
            let isCapturingStillImage = change![NSKeyValueChangeKey.newKey] as! Bool
            guard isCapturingStillImage else { break }
            DispatchQueue.main.async {
                self.previewView.layer.opacity = 0.0
                UIView.animate(withDuration: 0.25){
                    self.previewView.layer.opacity = 1.0
                }
            }

        case &SessionRunningContext:
//            let isSessionRunning = change![NSKeyValueChangeNewKey] as! Bool
//            DispatchQueue.main.async {
//                isSessionRunning && ( [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo].count > 1 );
//            }
            break
        default:
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    
    @objc
    private func subjectAreaDidChange(_ notification: NSNotification) {
        let devicePoint = CGPoint(x: 0.5, y: 0.5 )
        self.focusWithMode(focusMode: .continuousAutoFocus,
                           exposeWithMode: .continuousAutoExposure,
                       atDevicePoint: devicePoint,
                       monitorSubjectAreaChange: false)
    }
    
    @objc
    private func sessionRuntimeError(_ notification: NSNotification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }
        print( "Capture session runtime error: \(error)")
    
        // Automatically try to restart the session running if media services were reset and the last start running succeeded.
        // Otherwise, enable the user to try to resume the session running.
        if error.code == AVError.mediaServicesWereReset {
            queue.async {
                self.session.startRunning()
            }
        }
    }
    
    @objc
    private func sessionWasInterrupted(_ notification: NSNotification) {
    // In some scenarios we want to enable the user to resume the session running.
    // For example, if music playback is initiated via control center while using AVCam,
    // then the user can let AVCam resume the session running, which will stop music playback.
    // Note that stopping music playback in control center will not automatically resume the session running.
    // Also note that it is not always possible to resume, see -[resumeInterruptedSession:].
//    BOOL showResumeButton = NO;
    
        let userInfo = notification.userInfo!
        if let reason = userInfo[AVCaptureSessionInterruptionReasonKey] as? Int, let interruptionReason = AVCaptureSession.InterruptionReason(rawValue: reason) {
            print("Capture session was interrupted with reason \(reason)")
            switch interruptionReason {
            case .audioDeviceInUseByAnotherClient, .videoDeviceInUseByAnotherClient:
                    //showResumeButton = YES;
                break
            case .videoDeviceNotAvailableWithMultipleForegroundApps:
                //    self.cameraUnavailableLabel.isHidden = NO;
                break
            default:
                //showResumeButton = ( [UIApplication sharedApplication].applicationState == UIApplicationStateInactive );
                break
            }
        }
    }
    
    @objc
    private func sessionInterruptionEnded(_ notification: NSNotification) {
        print("Capture session interruption ended")
//    
//    if ( ! self.resumeButton.isHidden ) {
//    [UIView animateWithDuration:0.25 animations:^{
//    self.resumeButton.alpha = 0.0;
//    } completion:^( BOOL finished ) {
//    self.resumeButton.isHidden = YES;
//    }];
//    }
//    if ( ! self.cameraUnavailableLabel.isHidden ) {
//    [UIView animateWithDuration:0.25 animations:^{
//    self.cameraUnavailableLabel.alpha = 0.0;
//    } completion:^( BOOL finished ) {
//    self.cameraUnavailableLabel.isHidden = YES;
//    }];
//    }
    }


    //MARK: Device Configuration
    
    private func focusWithMode(focusMode: AVCaptureDevice.FocusMode, exposeWithMode exposureMode: AVCaptureDevice.ExposureMode,  atDevicePoint point: CGPoint, monitorSubjectAreaChange: Bool) {
        queue.async {
            let device = self.videoDeviceInput!.device
            do {
                try device.lockForConfiguration()
            }
            catch {
                print("Could not lock device for configuration: \(error)")
                return
            }

            if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
				device.focusPointOfInterest = point
				device.focusMode = focusMode
            }
    
            if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
				device.exposurePointOfInterest = point
				device.exposureMode = exposureMode
            }
    
            device.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
            device.unlockForConfiguration()
        }
    }
}
