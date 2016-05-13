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
    private var annotation = MKPointAnnotation()
    private let geocoder = CLGeocoder()
    private var needUpdateTrackingMode = false
    private var captureViewController: CaptureViewController!
    
    var location: Location? {
        didSet {
            guard let location = location else { return }
            mapView.setCenterCoordinate(location.coordinate, animated: true)
            annotation.coordinate = location.coordinate
            mapView.removeAnnotation(annotation)
            mapView.showAnnotations([annotation], animated: true)
            captureViewController.image = location.image
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        location = Database.instance.locations.first
        
        if let location = location {
            annotation.title = "My Car"
            annotation.coordinate = location.coordinate
            mapView.addAnnotation(annotation)
        }
        
        LocationManager.userLocation { (location)->Void in
            guard let location = location else { return }
            
            let region = MKCoordinateRegion(center: location.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1))
            let scaledRegion = self.mapView.regionThatFits(region)
            self.mapView.setRegion(scaledRegion, animated:false)
            self.mapView.showsUserLocation = true
            self.mapView.userTrackingMode = MKUserTrackingMode.FollowWithHeading
        }
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
    @IBAction private func markLocation(sender: AnyObject) {
        let location: Location
        if var loc: Location? = self.location ?? Database.instance.locations.first {
            if !(loc?.editable ?? false) {
                loc = Database.instance.locations.first
            }
            
            if loc == nil {
                loc = Database.instance.recordLocation(mapView.centerCoordinate, address: nil)
                captureViewController.image = nil
            }
            
            location = loc!
            location.coordinate = mapView.centerCoordinate
            location.address = nil
            location.editable = true
        }
        else {
            location = Database.instance.recordLocation(mapView.centerCoordinate, address: nil)
            location.editable = true
            captureViewController.image = nil
        }
        
        Database.instance.save()
        self.location = location
        
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
    private func showCurrentLocation(sender: AnyObject) {
        needUpdateTrackingMode = true
        mapView.setCenterCoordinate(mapView.userLocation.coordinate, animated: true)
    }
    
    @objc
    @IBAction
    private func showHistoryLocation(segue: UIStoryboardSegue) {
        if let historyViewController = segue.sourceViewController as? HistoryViewController {
            self.location = historyViewController.location
        }
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
    }
}
