//
//  ViewController.swift
//  Ohmycar
//
//  Created by Solomenchuk, Vlad on 5/11/16.
//  Copyright © 2016 Aramzamzam LLC. All rights reserved.
//

import UIKit
import MapKit

class MapViewController: UIViewController{
    @IBOutlet weak var mapView: MKMapView!
    @IBOutlet weak var markLocationButton: UIButton!
    @IBOutlet weak var navigateButton: UIBarButtonItem!
    @IBOutlet weak var undoView: UIView!
    @IBOutlet weak var undoLabel: UILabel!
    private var undoAction: (()->Void)?
    private var annotation = MKPointAnnotation()
    private let geocoder = CLGeocoder()
    private var needUpdateTrackingMode = false
    private var captureViewController: CaptureViewController!
    private var notificationObservers = [NSObjectProtocol]()
    override var prefersStatusBarHidden: Bool {
        return true
    }

    
    var location: Location? {
        didSet {
            guard let location = location else {
                mapView.removeAnnotation(annotation)
                markLocationButton.isSelected = false
                captureViewController.clear()
                navigateButton.isEnabled = false
                return
            }
            
            markLocationButton.isSelected = true
            mapView.setCenter(location.coordinate, animated: true)
            annotation.coordinate = location.coordinate
            annotation.subtitle = location.formattedAddress
            mapView.removeAnnotation(annotation)
            mapView.showAnnotations([annotation], animated: true)
            navigateButton.isEnabled = true
            captureViewController.image = location.image
            captureViewController.editable = location.editable
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        location = Database.instance.location
        
        if let location = location {
            annotation.title = "My Car"
            annotation.coordinate = location.coordinate
            mapView.addAnnotation(annotation)
        }
        
        hideUndo(animated: false)
        
        LocationManager.userLocation { (location)->Void in
            guard let location = location else { return }
            
            let region = MKCoordinateRegion(center: location.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1))
            let scaledRegion = self.mapView.regionThatFits(region)
            self.mapView.setRegion(scaledRegion, animated:false)
            self.mapView.showsUserLocation = true
            self.mapView.userTrackingMode = MKUserTrackingMode.followWithHeading
        }
        
        //set location ono-editable when entering background.
        notificationObservers.append(
            NotificationCenter.default.addObserver(forName: NSNotification.Name.UIApplicationDidEnterBackground, object: nil, queue: nil) { (_) in
                let loc = self.location
                loc?.editable = false
                self.location = loc
            }
        )
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        switch segue.identifier {
        case "CaptureViewController"?:
            captureViewController = segue.destination as! CaptureViewController
            captureViewController.delegate = self
        default:
            break
        }
    }
    
    @objc
    @IBAction
    func undo(sender: AnyObject) {
        undoAction?()
        hideUndo()
    }
    
    @objc
    @IBAction
    private func markLocation(_ sender: AnyObject) {
        hideUndo(animated: false)
        
        guard self.location == nil else {
            let savedLocation = self.location
            self.location = nil
            
            Database.instance.location = nil
            Database.instance.save()
            
            showUndo(message: "Spot discarded") {
                self.location = savedLocation
                Database.instance.location = savedLocation
                Database.instance.save()
                self.mapView.centerCoordinate = self.location!.coordinate
            }
            
            mapView.centerCoordinate = mapView.userLocation.coordinate
            return
        }
        
        let coordinate = mapView.userLocation.coordinate
        mapView.centerCoordinate = coordinate
        let location = Database.instance.recordLocation(coordinate: coordinate, address: nil)
        location.editable = true
        self.location = location
        Database.instance.save()
        
        if captureViewController.image == nil {
            captureViewController.capture()
        }
        
        updateAddress()
    }
    
    @objc
    @IBAction
    private func navigate(_ sender: AnyObject) {
        guard let location = location else { return }
        
        let placeMark = MKPlacemark(coordinate: location.coordinate, addressDictionary: location.address)
        let destination = MKMapItem(placemark: placeMark)
        destination.name = annotation.title
        
        let start = CLLocation(latitude: mapView.userLocation.coordinate.latitude, longitude: mapView.userLocation.coordinate.longitude)
        let end = CLLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        
        let distance = start.distance(from: end)
        
        //meters
        let directionsMode = distance > 2000 ? MKLaunchOptionsDirectionsModeTransit : MKLaunchOptionsDirectionsModeWalking
        
        destination.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: directionsMode])
    }
    
    @objc
    @IBAction
    private func showUserCurrentLocation(_ sender: AnyObject) {
        needUpdateTrackingMode = true
        
        let start = CLLocation(latitude: mapView.userLocation.coordinate.latitude, longitude: mapView.userLocation.coordinate.longitude)
        let end = CLLocation(latitude: mapView.centerCoordinate.latitude, longitude: mapView.centerCoordinate.longitude)
        
        let distance = start.distance(from: end)

        
        mapView.setCenter(mapView.userLocation.coordinate, animated: distance < 1000)
    }
    
    @objc
    private func hideUndo(animated: Bool = true) {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(hideUndo), object: nil)
        undoAction = nil
        
        if animated {
            UIView.animate(withDuration: 0.25, animations: {
                self.undoView.alpha = 0
            }) { (_) in
                self.undoView.isHidden = true
            }
        }
        else {
            undoView.alpha = 0
            undoView.isHidden = true
        }
    }
    
    private func showUndo(message: String, action: @escaping ()->Void) {
        undoAction = action
        undoLabel.text = message
        
        undoView.isHidden = false
        undoView.alpha = 0
        UIView.animate(withDuration: 0.25) {
            self.undoView.alpha = 1
        }
        
        perform(#selector(hideUndo), with: nil, afterDelay: 2)
    }
    
    private func updateAddress() {
        guard let location = location else { return }
        geocoder.cancelGeocode()
        self.annotation.subtitle = "Locating..."
        
        let loc = CLLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        geocoder.reverseGeocodeLocation(loc) { (placemarks, error) in
            guard let address = placemarks?.first?.addressDictionary as? [String: AnyObject], error == nil else { return }
            
            location.address = address
            self.annotation.subtitle = location.formattedAddress
            Database.instance.save()
        }
    }
    
    deinit {
        let nc = NotificationCenter.default
        for observer in notificationObservers {
            nc.removeObserver(observer)
        }
    }
}

// MARK: MKMapViewDelegate

extension MapViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        guard needUpdateTrackingMode else { return }
        self.mapView.userTrackingMode = MKUserTrackingMode.followWithHeading
        needUpdateTrackingMode = false
    }
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        
        if annotation is MKUserLocation {
            return nil
        }
        
        var annotationView: MKPinAnnotationView! = mapView.dequeueReusableAnnotationView(withIdentifier: "Annotation") as? MKPinAnnotationView
        if annotationView == nil {
            annotationView = MKPinAnnotationView(annotation: annotation, reuseIdentifier: "Annotation");
        }
        
        annotationView.animatesDrop = true
        annotationView.isDraggable = location!.editable
        annotationView.isEnabled = true
        annotationView.canShowCallout = true
        annotationView.pinTintColor = location!.editable ? .red : .purple
        
        return annotationView
    }
    
    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, didChange newState: MKAnnotationViewDragState, fromOldState oldState: MKAnnotationViewDragState) {
        guard let coordinate = view.annotation?.coordinate, newState == MKAnnotationViewDragState.ending else { return }
        
        location?.coordinate = coordinate
        Database.instance.save()
        
        updateAddress()
    }
}

//MARK: CaptureViewControllerDelegate
extension MapViewController: CaptureViewControllerDelegate {
    func captureViewController(controller: CameraViewController, didCaptureImage image: UIImage?) {
        hideUndo(animated: false)
        location?.image = image
        Database.instance.save()
    }

    func captureViewController(controller: CameraViewController, didDiscardImage image: UIImage?) {
        if let oldImage = image {
            hideUndo(animated: false)
            showUndo(message: "Image discarded") {
                self.location?.image = oldImage
                self.captureViewController.image = oldImage
                Database.instance.save()
            }
        }
        
        location?.image = nil
        Database.instance.save()
    }
}
