//
//  LocationManager.swift
//  Ohmycar
//
//  Created by Solomenchuk, Vlad on 5/11/16.
//  Copyright © 2016 Aramzamzam LLC. All rights reserved.
//

import MapKit

class LocationManager: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var authorizationHandlers: [(Bool)->Void] = []
    private var userLocationHandlers: [(CLLocation?)->Void] = []
    
    static var instance : LocationManager = LocationManager()
    
    override init(){
        super.init()
        locationManager.delegate = self
    }
    
    class func requestAuthorization(handler: (Bool)->Void) {
        switch CLLocationManager.authorizationStatus() {
        case .NotDetermined:
            LocationManager.instance.authorizationHandlers.append(handler)
            instance.locationManager.requestWhenInUseAuthorization()
        case .Restricted, .Denied:
            handler(false)
        default:
            handler(true)
        }
    }
    
    class func userLocation(handler: (CLLocation?)->Void) {
        requestAuthorization { (allowed) -> Void in
            if allowed {
                LocationManager.instance.userLocationHandlers.append(handler)
                LocationManager.instance.locationManager.startUpdatingLocation()
            }
            else {
                handler(nil)
            }
        }
    }
    
    //MARK: - CLLocationManagerDelegate
    
    func locationManager(manager: CLLocationManager, didChangeAuthorizationStatus status: CLAuthorizationStatus) {
        
        var allowed: Bool
        
        switch status {
        case .NotDetermined:
            //do nothing
            return
        case .Restricted, .Denied:
            allowed = false
        default:
            allowed = true
        }
        
        for handler in authorizationHandlers {
            handler(allowed)
        }
        
        authorizationHandlers = []
    }
    
    func locationManager(manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {
        guard let currentLocation = locations.first else { return }
        
        manager.stopUpdatingLocation()
        self.callUserLocationHandlers(currentLocation)
    }
    
    func locationManager(manager: CLLocationManager,
                         didFailWithError error: NSError) {
        print("failed to update location: \(error)")
        callUserLocationHandlers(nil)
        manager.stopUpdatingLocation()
    }
    
    //MARK: - private
    
    private func callUserLocationHandlers(location: CLLocation?) {
        for handler in userLocationHandlers{
            handler(location)
        }
        
        userLocationHandlers = []
    }
}