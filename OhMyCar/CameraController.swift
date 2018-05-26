//
//  CameraController.swift
//  OhMyCar
//
//  Created by Solomenchuk, Vlad on 5/25/18.
//  Copyright © 2018 Aramzamzam LLC. All rights reserved.
//

import UIKit
import AVFoundation

protocol CameraControllerDelegate: AnyObject {
    func cameraControllerDidFinishSetup(_ controller: CameraController)
    func cameraController(_ controller: CameraController, setupFailedWith error: Error)
    func cameraController(_ controller: CameraController, capturingImage: Bool)
    func cameraController(_ controller: CameraController, sessionRunning: Bool)
}

class CameraController: NSObject {
    enum SetupResult {
        case success, cameraNotAuthorized, sessionConfigurationFailed
    }
    
    enum CameraControllerError: Error {
        case noImage, notConfigured, noConnection, noDevice, noOutput, cameraNotAuthorized, sessionConfigurationFailed
    }

    private let queue = DispatchQueue(label: "session queue", qos: .background)
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var stillImageOutput: AVCaptureStillImageOutput?
    private var kvoObservers: [NSKeyValueObservation] = []
    var setupResult: SetupResult = .cameraNotAuthorized
    let session = AVCaptureSession()
    weak var delegate: CameraControllerDelegate?

    func start() {
        queue.suspend()
        // Check video authorization status. Video access is required and audio access is optional.
        // If audio access is denied, audio is not recorded during movie recording.
        requestAccess(mediaType: .video) { [weak self] (granted) in
            guard let sself = self else { return }
            
            guard granted else {
                sself.setupResult = .cameraNotAuthorized
                DispatchQueue.main.async {
                    sself.delegate?.cameraController(sself, setupFailedWith: CameraControllerError.cameraNotAuthorized)
                }
                return
            }
            
            sself.queue.resume()
            
            sself.queue.async {
                guard let sself = self else { return }
                
                guard sself.setupSession() else {
                    sself.setupResult = .sessionConfigurationFailed
                    sself.stop()
                    DispatchQueue.main.async {
                        sself.delegate?.cameraController(sself, setupFailedWith: CameraControllerError.sessionConfigurationFailed)
                    }
                    return
                }
                
                sself.setupResult = .success
                sself.session.startRunning()
                sself.addObservers()
                
                DispatchQueue.main.async {
                    sself.delegate?.cameraControllerDidFinishSetup(sself)
                }
            }
        }
    }
    
    func stop() {
        queue.suspend()
        removeObservers()
        videoDeviceInput = nil
        stillImageOutput = nil
    }
    
    func focus(with mode: AVCaptureDevice.FocusMode, exposeWithMode exposureMode: AVCaptureDevice.ExposureMode,  atDevicePoint point: CGPoint, monitorSubjectAreaChange: Bool) {
        queue.async { [weak self] () in
            guard let sself = self else { return }
            
            guard let device = sself.videoDeviceInput?.device else { return }
            
            do {
                try device.lockForConfiguration()
            }
            catch {
                print("Could not lock device for configuration: \(error)")
                return
            }
            
            if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(mode) {
                device.focusPointOfInterest = point
                device.focusMode = mode
            }
            
            if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                device.exposurePointOfInterest = point
                device.exposureMode = exposureMode
            }
            
            device.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
            device.unlockForConfiguration()
        }
    }
    
    func snap(videoOrientation: AVCaptureVideoOrientation?
, closure: @escaping (Result<UIImage>)->Void) {
        guard setupResult == .success else {
            closure(Result<UIImage>.failure(CameraControllerError.notConfigured))
            return
        }
        
        queue.async { [weak self] () in
            guard let sself = self else { return }
            
            guard let connection = sself.stillImageOutput?.connection(with: AVMediaType.video) else {
                DispatchQueue.main.async {
                    closure(Result<UIImage>.failure(CameraControllerError.noConnection))
                }
                return
            }
            guard let device = sself.videoDeviceInput?.device else {
                DispatchQueue.main.async {
                    closure(Result<UIImage>.failure(CameraControllerError.noDevice))
                }
                return
            }
            
            guard let stillImageOutput = sself.stillImageOutput else {
                DispatchQueue.main.async {
                    closure(Result<UIImage>.failure(CameraControllerError.noOutput))
                }
                return
            }
            
            // Update the orientation on the still image output video connection before capturing.
            connection.videoOrientation = videoOrientation ?? connection.videoOrientation
            
            // Flash set to Auto for Still Capture.
            do {
                try CameraController.setFlashMode(flashMode: .auto, forDevice: device)
            } catch {
                DispatchQueue.main.async {
                    closure(Result<UIImage>.failure(error))
                }
            }
            
            // Capture a still image.
            stillImageOutput.captureStillImageAsynchronously(from: connection) { (imageDataSampleBuffer, error) in
                guard let imageDataSampleBuffer = imageDataSampleBuffer else {
                    DispatchQueue.main.async {
                        closure(Result<UIImage>.failure(CameraControllerError.noImage))
                    }
                    return
                }
                // The sample buffer is not retained. Create image data before saving the still image to the photo library asynchronously.
                guard let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageDataSampleBuffer), let image = UIImage(data: imageData) else {
                    DispatchQueue.main.async {
                        closure(Result<UIImage>.failure(CameraControllerError.noImage))
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    DispatchQueue.main.async {
                        closure(Result<UIImage>.success(image))
                    }
                }
            }
        }
    }
    
    var zoom: CGFloat {
        set {
            guard let device = self.videoDeviceInput?.device else { return }
    
            do {
                try device.lockForConfiguration()
            } catch {
                return
            }
    
            device.videoZoomFactor = max(1.0, min(newValue, device.activeFormat.videoMaxZoomFactor))
            device.unlockForConfiguration()
        }
        
        get {
            guard let device = self.videoDeviceInput?.device else { return 0 }
            
            return device.videoZoomFactor
        }
    }
    
    private func requestAccess(mediaType: AVMediaType, handler: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            handler(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: AVMediaType.video, completionHandler: { (granted) in
                handler(granted)
            })
        default:
            handler(false)
        }
    }
    
    private func setupSession() -> Bool {
        // Setup the capture session.
        // In general it is not safe to mutate an AVCaptureSession or any of its inputs, outputs, or connections from multiple threads at the same time.
        // Why not do all of this on the main queue?
        // Because -[AVCaptureSession startRunning] is a blocking call which can take a long time. We dispatch session setup to the sessionQueue
        // so that the main queue isn't blocked, which keeps the UI responsive.
        
        guard let videoDevice = CameraController.deviceWithMediaType(mediaType: .video, preferringPosition: .back) else {
            return false
        }
        
        let videoDeviceInput: AVCaptureDeviceInput
        
        do {
            videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
        }
        catch {
            return false
        }
        
        self.session.beginConfiguration()
        
        guard self.session.canAddInput(videoDeviceInput) else {
            return false
        }
        
        self.session.addInput(videoDeviceInput)
        self.videoDeviceInput = videoDeviceInput
        
        let stillImageOutput = AVCaptureStillImageOutput()
        guard self.session.canAddOutput(stillImageOutput) else {
            return false
        }
        
        stillImageOutput.outputSettings = [AVVideoCodecKey : AVVideoCodecJPEG]
        self.session.addOutput(stillImageOutput)
        self.stillImageOutput = stillImageOutput
        self.session.commitConfiguration()
        
        return true
    }
    
    private class func deviceWithMediaType(mediaType: AVMediaType, preferringPosition position: AVCaptureDevice.Position) -> AVCaptureDevice?
    {
        let devices = AVCaptureDevice.devices(for: mediaType)
        
        return devices.first(where: { $0.position == position }) ?? devices.first
    }
    
    private class func setFlashMode(flashMode: AVCaptureDevice.FlashMode, forDevice device: AVCaptureDevice) throws {
        guard device.hasFlash && device.isFlashModeSupported(flashMode) else {
            return
        }
        
        try device.lockForConfiguration()
        
        device.flashMode = flashMode
        device.unlockForConfiguration()
    }
    
    deinit {
        stop()
    }
}

//MARK: KVO and Notifications
extension CameraController {
    private func addObservers() {
        kvoObservers = [
            session.observe(\.running, options: [.new]) { [weak self] (session, value) in
                guard let sself = self else { return }
                guard let isSessionRunning  = value.newValue else { return }
                sself.delegate?.cameraController(sself, sessionRunning: isSessionRunning)
            },
            
            stillImageOutput!.observe(\AVCaptureStillImageOutput.capturingStillImage, options: [.new]) { [weak self] (session, value) in
                guard let sself = self else { return }
                guard let isCapturingImage  = value.newValue else { return }
                sself.delegate?.cameraController(sself, capturingImage: isCapturingImage)
            },
        ]
        
        
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
        kvoObservers = []
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc
    private func subjectAreaDidChange(_ notification: NSNotification) {
        let devicePoint = CGPoint(x: 0.5, y: 0.5 )
        self.focus(with: .continuousAutoFocus,
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
}
