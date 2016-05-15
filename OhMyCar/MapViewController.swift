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
    @IBOutlet weak var markLocationButton: UIBarButtonItem!
    @IBOutlet weak var navigateButton: UIBarButtonItem!
    @IBOutlet weak var undoViewBottom: NSLayoutConstraint!
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
                markLocationButton.image = UIImage(named: "PinToolbarUnfilled")
                captureViewController.clear()
                navigateButton.enabled = false
                return
            }
            
            markLocationButton.image = UIImage(named: "PinToolbarFilled")
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
        
        location = Database.instance.current
        self.prefersStatusBarHidden()
        
        if let location = location {
            annotation.title = "My Car"
            annotation.coordinate = location.coordinate
            mapView.addAnnotation(annotation)
        }
        
        hideUndo()
        
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
        guard self.location == nil else {
            self.location = nil
            Database.instance.current = nil
            Database.instance.save()
            
            let lastCenter = mapView.centerCoordinate
            showUndo("Location discarded") {
                self.location = Database.instance.restoreBackup()
                self.mapView.centerCoordinate = lastCenter
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
    private func hideUndo() {
        NSObject.cancelPreviousPerformRequestsWithTarget(self, selector: #selector(hideUndo), object: nil)
        
        undoViewBottom.constant = -undoView.frame.size.height

        UIView.animateWithDuration(0.25, animations: {
            self.view.layoutIfNeeded()
            }) { (_) in
                self.undoView.hidden = true
        }
    }
    
    private func showUndo(message: String, action: ()->Void) {
        undoAction = action
        undoLabel.text = message
        
        undoViewBottom.constant = 0
        undoView.hidden = false
        UIView.animateWithDuration(0.25) {
            self.view.layoutIfNeeded()
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
        location?.image = image
        Database.instance.save()
    }
}
