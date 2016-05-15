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

private var CapturingStillImageContext = "CapturingStillImageContext"
private var SessionRunningContext = "SessionRunningContext"

class CameraViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let previewView = CameraView(frame: CGRectZero)
    private let queue = dispatch_queue_create( "session queue", DISPATCH_QUEUE_SERIAL )
    internal var setupResult = CamSetupResult.CameraNotAuthorized
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var stillImageOutput: AVCaptureStillImageOutput?
    
    private var sessionRunning: Bool  {
        return self.session.running
    }
    
    class func deviceWithMediaType(mediaType: String, preferringPosition position: AVCaptureDevicePosition) -> AVCaptureDevice?
    {
        let devices = AVCaptureDevice.devicesWithMediaType(mediaType)
        var captureDevice: AVCaptureDevice?
        for device in devices {
            guard device.position == position else { continue }
            captureDevice = device as? AVCaptureDevice
        }
        
        return captureDevice ?? devices.first as? AVCaptureDevice
    }
    
    class func setFlashMode(flashMode: AVCaptureFlashMode, forDevice device: AVCaptureDevice) {
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
        
        let focusGesture = UITapGestureRecognizer(target: self, action: #selector(CameraViewController.focusAndExposeTap(_:)))
        view.addGestureRecognizer(focusGesture)
        
        let zoomGesture = UIPinchGestureRecognizer(target: self, action: #selector(CameraViewController.pinchToZoom(_:)))
        view.addGestureRecognizer(zoomGesture)
        
        // Setup the preview view.
        view.addSubview(previewView)
        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.topAnchor.constraintEqualToAnchor(view.topAnchor).active = true
        previewView.bottomAnchor.constraintEqualToAnchor(view.bottomAnchor).active = true
        previewView.leadingAnchor.constraintEqualToAnchor(view.leadingAnchor).active = true
        previewView.trailingAnchor.constraintEqualToAnchor(view.trailingAnchor).active = true
        
        previewView.session = session
        
        self.setupResult = .Success
        
        // Check video authorization status. Video access is required and audio access is optional.
        // If audio access is denied, audio is not recorded during movie recording.
        
        switch AVCaptureDevice.authorizationStatusForMediaType(AVMediaTypeVideo) {
        case .Authorized:
            break
        case .NotDetermined:
            dispatch_suspend(queue)
            AVCaptureDevice.requestAccessForMediaType(AVMediaTypeVideo, completionHandler: { (granted) in
                self.setupResult = .CameraNotAuthorized
                dispatch_resume( self.queue )
            })
        default:
            self.setupResult = .CameraNotAuthorized;
        }
        
        
        // Setup the capture session.
        // In general it is not safe to mutate an AVCaptureSession or any of its inputs, outputs, or connections from multiple threads at the same time.
        // Why not do all of this on the main queue?
        // Because -[AVCaptureSession startRunning] is a blocking call which can take a long time. We dispatch session setup to the sessionQueue
        // so that the main queue isn't blocked, which keeps the UI responsive.
        dispatch_async(queue) {
            guard self.setupResult == .Success else { return }
            
            let videoDevice = CameraViewController.deviceWithMediaType(AVMediaTypeVideo, preferringPosition: .Back)
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
            
            dispatch_async(dispatch_get_main_queue()) {
                // Why are we dispatching this to the main queue?
                // Because AVCaptureVideoPreviewLayer is the backing layer for AAPLPreviewView and UIView
                // can only be manipulated on the main thread.
                // Note: As an exception to the above rule, it is not necessary to serialize video orientation changes
                // on the AVCaptureVideoPreviewLayer’s connection with other session manipulation.
                
                // Use the status bar orientation as the initial video orientation. Subsequent orientation changes are handled by
                // -[viewWillTransitionToSize:withTransitionCoordinator:].
                let statusBarOrientation = UIApplication.sharedApplication().statusBarOrientation
                var initialVideoOrientation = AVCaptureVideoOrientation.Portrait
                if ( statusBarOrientation != .Unknown ) {
                    initialVideoOrientation = AVCaptureVideoOrientation(rawValue: statusBarOrientation.rawValue)!
                }
                
                let previewLayer = self.previewView.layer as! AVCaptureVideoPreviewLayer
                previewLayer.connection.videoOrientation = initialVideoOrientation
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
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        
        dispatch_async(queue) {
            guard self.setupResult == .Success else { return }
            
            self.session.startRunning()
            self.addObservers()
        }
    }
    
    override func viewDidDisappear(animated: Bool) {
        dispatch_async(queue) {
            guard self.setupResult == .Success else { return }
            self.session.stopRunning()
            self.removeObservers()
    }
        super.viewWillAppear(animated)
    }
    
    //MARK: Actions
    
    func snapStillImage(closure: (UIImage?, NSError?)->Void) {
        guard setupResult == .Success else {
            closure(nil, nil)
            return
        }
        
        dispatch_async(queue) {
            let connection = self.stillImageOutput!.connectionWithMediaType(AVMediaTypeVideo)
            let previewLayer = self.previewView.layer as! AVCaptureVideoPreviewLayer
    
            // Update the orientation on the still image output video connection before capturing.
            connection.videoOrientation = previewLayer.connection.videoOrientation
    
            // Flash set to Auto for Still Capture.
            CameraViewController.setFlashMode(.Auto, forDevice:self.videoDeviceInput!.device)
    
            // Capture a still image.
            self.stillImageOutput!.captureStillImageAsynchronouslyFromConnection(connection) { (imageDataSampleBuffer, error) in
                guard let imageDataSampleBuffer = imageDataSampleBuffer else {
                    print( "Could not capture still image: \(error)")
                    closure(nil, error)
                    return
                }
				// The sample buffer is not retained. Create image data before saving the still image to the photo library asynchronously.
				let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageDataSampleBuffer)
                let image = UIImage(data: imageData)

                closure(image, nil)
            }
        }
    }
    
    @objc
    private func focusAndExposeTap(gestureRecognizer: UIGestureRecognizer) {
        let devicePoint = (self.previewView.layer as! AVCaptureVideoPreviewLayer).captureDevicePointOfInterestForPoint(gestureRecognizer.locationInView(gestureRecognizer.view))
        self.focusWithMode(.AutoFocus, exposeWithMode: .AutoExpose, atDevicePoint: devicePoint, monitorSubjectAreaChange: true)
    }

    @objc
    private func pinchToZoom(gestureRecognizer: UIPinchGestureRecognizer) {
        let pinchVelocityDividerFactor: CGFloat = 5.0
        
        guard gestureRecognizer.state == .Changed else { return }
        
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
        session.addObserver(self, forKeyPath: "running", options: .New, context: &SessionRunningContext)
        stillImageOutput?.addObserver(self, forKeyPath: "capturingStillImage", options: .New, context: &CapturingStillImageContext)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(CameraViewController.subjectAreaDidChange(_:)), name: AVCaptureDeviceSubjectAreaDidChangeNotification, object: videoDeviceInput!.device)

        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(CameraViewController.sessionRuntimeError(_:)), name: AVCaptureSessionRuntimeErrorNotification, object: session)

        // A session can only run when the app is full screen. It will be interrupted in a multi-app layout, introduced in iOS 9,
        // see also the documentation of AVCaptureSessionInterruptionReason. Add observers to handle these session interruptions
        // and show a preview is paused message. See the documentation of AVCaptureSessionWasInterruptedNotification for other
        // interruption reasons.
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(CameraViewController.sessionWasInterrupted(_:)), name: AVCaptureSessionWasInterruptedNotification, object: session)
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(CameraViewController.sessionInterruptionEnded(_:)), name: AVCaptureSessionInterruptionEndedNotification, object: session)
    }

    
    private func removeObservers(){
        NSNotificationCenter.defaultCenter().removeObserver(self)
        session.removeObserver(self, forKeyPath: "running", context: &SessionRunningContext)
        stillImageOutput?.removeObserver(self, forKeyPath: "capturingStillImage", context: &CapturingStillImageContext)
    }
    
    override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {

        switch context {
        case &CapturingStillImageContext:
            let isCapturingStillImage = change![NSKeyValueChangeNewKey] as! Bool
            guard isCapturingStillImage else { break }
            dispatch_async(dispatch_get_main_queue()) {
                self.previewView.layer.opacity = 0.0
                UIView.animateWithDuration(0.25){
                    self.previewView.layer.opacity = 1.0
                }
            }

        case &SessionRunningContext:
//            let isSessionRunning = change![NSKeyValueChangeNewKey] as! Bool
//            dispatch_async(dispatch_get_main_queue()) {
//                isSessionRunning && ( [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo].count > 1 );
//            }
            break
        default:
            super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: context)
        }
    }
    
    @objc
    private func subjectAreaDidChange(notification: NSNotification) {
        let devicePoint = CGPoint(x: 0.5, y: 0.5 )
    self.focusWithMode(.ContinuousAutoFocus,
                       exposeWithMode: .ContinuousAutoExposure,
                       atDevicePoint: devicePoint,
                       monitorSubjectAreaChange: false)
    }
    
    @objc
    private func sessionRuntimeError(notification: NSNotification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] else { return }
        print( "Capture session runtime error: \(error)")
    
        // Automatically try to restart the session running if media services were reset and the last start running succeeded.
        // Otherwise, enable the user to try to resume the session running.
        if error.code == AVError.MediaServicesWereReset.rawValue {
            dispatch_async(queue) {
                self.session.startRunning()
            }
        }
    }
    
    @objc
    private func sessionWasInterrupted(notification: NSNotification) {
    // In some scenarios we want to enable the user to resume the session running.
    // For example, if music playback is initiated via control center while using AVCam,
    // then the user can let AVCam resume the session running, which will stop music playback.
    // Note that stopping music playback in control center will not automatically resume the session running.
    // Also note that it is not always possible to resume, see -[resumeInterruptedSession:].
//    BOOL showResumeButton = NO;
    
        let userInfo = notification.userInfo!
        if let reason = userInfo[AVCaptureSessionInterruptionReasonKey] as? Int, let interruptionReason = AVCaptureSessionInterruptionReason(rawValue: reason) {
            print("Capture session was interrupted with reason \(reason)")
            switch interruptionReason {
                case .AudioDeviceInUseByAnotherClient, .VideoDeviceInUseByAnotherClient:
                    //showResumeButton = YES;
                break
            case .VideoDeviceNotAvailableWithMultipleForegroundApps:
                //    self.cameraUnavailableLabel.hidden = NO;
                break
            default:
                //showResumeButton = ( [UIApplication sharedApplication].applicationState == UIApplicationStateInactive );
                break
            }
        }
    }
    
    @objc
    private func sessionInterruptionEnded(notification: NSNotification) {
        print("Capture session interruption ended")
//    
//    if ( ! self.resumeButton.hidden ) {
//    [UIView animateWithDuration:0.25 animations:^{
//    self.resumeButton.alpha = 0.0;
//    } completion:^( BOOL finished ) {
//    self.resumeButton.hidden = YES;
//    }];
//    }
//    if ( ! self.cameraUnavailableLabel.hidden ) {
//    [UIView animateWithDuration:0.25 animations:^{
//    self.cameraUnavailableLabel.alpha = 0.0;
//    } completion:^( BOOL finished ) {
//    self.cameraUnavailableLabel.hidden = YES;
//    }];
//    }
    }


    //MARK: Device Configuration
    
    private func focusWithMode(focusMode: AVCaptureFocusMode, exposeWithMode exposureMode: AVCaptureExposureMode,  atDevicePoint point:CGPoint, monitorSubjectAreaChange: Bool) {
        dispatch_async(queue) { 
            let device = self.videoDeviceInput!.device
            do {
                try device.lockForConfiguration()
            }
            catch {
                print("Could not lock device for configuration: \(error)")
                return
            }

            if device.focusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
				device.focusPointOfInterest = point
				device.focusMode = focusMode
            }
    
            if device.exposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
				device.exposurePointOfInterest = point
				device.exposureMode = exposureMode
            }
    
            device.subjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
            device.unlockForConfiguration()
        }
    }
}
