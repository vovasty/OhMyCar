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
    
    var location: Location? {
        didSet {
            guard let location = location else {
                mapView.removeAnnotation(annotation)
                markLocationButton.selected = false
                captureViewController.clear()
                navigateButton.enabled = false
                return
            }
            
            markLocationButton.selected = true
            mapView.setCenterCoordinate(location.coordinate, animated: true)
            annotation.coordinate = location.coordinate
            mapView.removeAnnotation(annotation)
            mapView.showAnnotations([annotation], animated: true)
            navigateButton.enabled = true
            captureViewController.image = location.image
            captureViewController.editable = location.editable
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        location = Database.instance.location
        self.prefersStatusBarHidden()
        
        if let location = location {
            annotation.title = "My Car"
            annotation.coordinate = location.coordinate
            mapView.addAnnotation(annotation)
        }
        
        hideUndo(false)
        
        LocationManager.userLocation { (location)->Void in
            guard let location = location else { return }
            
            let region = MKCoordinateRegion(center: location.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1))
            let scaledRegion = self.mapView.regionThatFits(region)
            self.mapView.setRegion(scaledRegion, animated:false)
            self.mapView.showsUserLocation = true
            self.mapView.userTrackingMode = MKUserTrackingMode.FollowWithHeading
        }
        
        //set location ono-editable when entering background.
        notificationObservers.append(
            NSNotificationCenter.defaultCenter().addObserverForName(UIApplicationDidEnterBackgroundNotification, object: nil, queue: nil) { (_) in
                let loc = self.location
                loc?.editable = false
                self.location = loc
            }
        )
    }
    
    override func prefersStatusBarHidden() -> Bool {
        return true
    }
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        switch segue.identifier {
        case "CaptureViewController"?:
            captureViewController = segue.destinationViewController as! CaptureViewController
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
    private func markLocation(sender: AnyObject) {
        hideUndo(false)
        
        guard self.location == nil else {
            let savedLocation = self.location
            self.location = nil
            
            Database.instance.location = nil
            Database.instance.save()
            
            showUndo("Spot discarded") {
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
        let location = Database.instance.recordLocation(coordinate, address: nil)
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
    private func navigate(sender: AnyObject) {
        guard let location = location else { return }
        
        let placeMark = MKPlacemark(coordinate: location.coordinate, addressDictionary: location.address)
        let destination = MKMapItem(placemark: placeMark)
        destination.name = annotation.title
        
        let start = CLLocation(latitude: mapView.userLocation.coordinate.latitude, longitude: mapView.userLocation.coordinate.longitude)
        let end = CLLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        
        let distance = start.distanceFromLocation(end)
        
        //meters
        let directionsMode = distance > 2000 ? MKLaunchOptionsDirectionsModeTransit : MKLaunchOptionsDirectionsModeWalking
        
        destination.openInMapsWithLaunchOptions([MKLaunchOptionsDirectionsModeKey: directionsMode])
    }
    
    @objc
    @IBAction
    private func showUserCurrentLocation(sender: AnyObject) {
        needUpdateTrackingMode = true
        
        let start = CLLocation(latitude: mapView.userLocation.coordinate.latitude, longitude: mapView.userLocation.coordinate.longitude)
        let end = CLLocation(latitude: mapView.centerCoordinate.latitude, longitude: mapView.centerCoordinate.longitude)
        
        let distance = start.distanceFromLocation(end)

        
        mapView.setCenterCoordinate(mapView.userLocation.coordinate, animated: distance < 1000)
    }
    
    @objc
    private func hideUndo(animated: Bool = true) {
        NSObject.cancelPreviousPerformRequestsWithTarget(self, selector: #selector(hideUndo), object: nil)
        undoAction = nil
        
        if animated {
            UIView.animateWithDuration(0.25, animations: {
                self.undoView.alpha = 0
            }) { (_) in
                self.undoView.hidden = true
            }
        }
        else {
            undoView.alpha = 0
            undoView.hidden = true
        }
    }
    
    private func showUndo(message: String, action: ()->Void) {
        undoAction = action
        undoLabel.text = message
        
        undoView.hidden = false
        undoView.alpha = 0
        UIView.animateWithDuration(0.25) {
            self.undoView.alpha = 1
        }
        
        performSelector(#selector(hideUndo), withObject: nil, afterDelay: 2)
    }
    
    private func updateAddress() {
        guard let location = location else { return }
        geocoder.cancelGeocode()
        self.annotation.subtitle = "Locating..."
        
        let loc = CLLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        geocoder.reverseGeocodeLocation(loc) { (placemarks, error) in
            guard let address = placemarks?.first?.addressDictionary as? [String: AnyObject] where error == nil else { return }
            
            location.address = address
            self.annotation.subtitle = location.formattedAddress
            Database.instance.save()
        }
    }
    
    deinit {
        let nc = NSNotificationCenter.defaultCenter()
        for observer in notificationObservers {
            nc.removeObserver(observer)
        }
    }
}

// MARK: MKMapViewDelegate

extension MapViewController: MKMapViewDelegate {
    func mapView(mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        guard needUpdateTrackingMode else { return }
        self.mapView.userTrackingMode = MKUserTrackingMode.FollowWithHeading
        needUpdateTrackingMode = false
    }
    
    func mapView(mapView: MKMapView, viewForAnnotation annotation: MKAnnotation) -> MKAnnotationView? {
        
        if annotation is MKUserLocation {
            return nil
        }
        
        var annotationView: MKPinAnnotationView! = mapView.dequeueReusableAnnotationViewWithIdentifier("Annotation") as? MKPinAnnotationView
        if annotationView == nil {
            annotationView = MKPinAnnotationView(annotation: annotation, reuseIdentifier: "Annotation");
            annotationView!.rightCalloutAccessoryView = UIButton(type: UIButtonType.DetailDisclosure) as UIView
        }
        
        annotationView.animatesDrop = true
        annotationView.draggable = location!.editable
        annotationView.enabled = true
        annotationView.canShowCallout = true
        annotationView.pinTintColor = location!.editable ? UIColor.redColor() : UIColor.purpleColor()
        
        return annotationView
    }
    
    func mapView(mapView: MKMapView, annotationView view: MKAnnotationView, didChangeDragState newState: MKAnnotationViewDragState, fromOldState oldState: MKAnnotationViewDragState) {
        guard let coordinate = view.annotation?.coordinate where newState == MKAnnotationViewDragState.Ending else { return }
        
        location?.coordinate = coordinate
        Database.instance.save()
        
        updateAddress()
    }
}

//MARK: CaptureViewControllerDelegate
extension MapViewController: CaptureViewControllerDelegate {
    func captureViewController(controller: CameraViewController, didCaptureImage image: UIImage?) {
        hideUndo(false)
        location?.image = image
        Database.instance.save()
    }

    func captureViewController(controller: CameraViewController, didDiscardImage image: UIImage?) {
        if let oldImage = image {
            hideUndo(false)
            showUndo("Image discarded") {
                self.location?.image = oldImage
                self.captureViewController.image = oldImage
                Database.instance.save()
            }
        }
        
        location?.image = nil
        Database.instance.save()
    }
}
