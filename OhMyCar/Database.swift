//
//  Database.swift
//  Ohmycar
//
//  Created by Solomenchuk, Vlad on 5/11/16.
//  Copyright © 2016 Aramzamzam LLC. All rights reserved.
//

import MapKit

class Location: NSObject, NSCoding {
    var coordinate: CLLocationCoordinate2D
    var address: [String: AnyObject]?
    var date = NSDate()
    var editable = false
    private var imageName: String?
    private var basePath: NSURL?
    private var imagePath: NSURL? {
        guard let imageName = imageName else { return nil }
        return basePath?.URLByAppendingPathComponent(imageName)
    }
    private var clearResources = true
    
    var image: UIImage? {
        set {
            guard let image = newValue else {
                if let imagePath = imagePath {
                    do {
                        try NSFileManager.defaultManager().removeItemAtURL(imagePath)
                        print("removed image \(imagePath)")
                    }
                    catch {
                        print("unable to remove image \(error)")
                    }
                }
                return
            }
            
            assert(basePath != nil)
            
            if imageName == nil {
                imageName = NSUUID().UUIDString
            }
            
            let imageData = UIImageJPEGRepresentation(image, 0.7)
            imageData?.writeToURL(imagePath!, atomically: true)
            
            print("image saved to \(imagePath!)")
        }
        
        get {
            guard let path = imagePath?.path else { return nil }
            return UIImage(contentsOfFile: path)
        }
    }
    
    private init(coordinate: CLLocationCoordinate2D, address: [String: AnyObject]?, basePath: NSURL? = nil) {
        self.address = address
        self.coordinate = coordinate
        self.basePath = basePath
    }
    
    required convenience init?(coder decoder: NSCoder) {
        let latitude = decoder.decodeDoubleForKey("latitude")
        let longitude = decoder.decodeDoubleForKey("longitude")
        let address = decoder.decodeObjectForKey("address") as? [String: AnyObject]
        let date = decoder.decodeObjectForKey("date") as! NSDate
        let imageName = decoder.decodeObjectForKey("imageName") as? String
        
        self.init(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), address: address)
        self.date = date
        self.imageName = imageName
    }
    
    func encodeWithCoder(coder: NSCoder) {
        coder.encodeDouble(coordinate.latitude, forKey: "latitude")
        coder.encodeDouble(coordinate.longitude, forKey: "longitude")
        
        if address != nil {
            coder.encodeObject(address, forKey: "address")
        }
        coder.encodeObject(date, forKey: "date")
        
        if imageName != nil {
            coder.encodeObject(imageName, forKey: "imageName")
        }
    }
    
    var formattedAddress: String? {
        guard let addressArray = address?["FormattedAddressLines"] as? [String] else { return nil }
        
        return addressArray.joinWithSeparator(" ")
    }
    
    deinit {
        guard clearResources, let imagePath = imagePath else { return }
        do {
            try NSFileManager.defaultManager().removeItemAtURL(imagePath)
            print("removed image \(imagePath)")
        }
        catch {
            print("unable to remove image \(error)")
        }
    }
}

class Database {
    var location: Location?
    let savePath: NSURL
    let basePath: NSURL
    
    static var instance : Database = Database(savePath: NSFileManager.defaultManager().URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask).first!.URLByAppendingPathComponent("locations.plist"))
    
    init(savePath: NSURL) {
        self.savePath = savePath
        self.basePath = savePath.URLByDeletingLastPathComponent!

    }

    func recordLocation(coordinate: CLLocationCoordinate2D, address: [String: AnyObject]?) -> Location {
        location = Location(coordinate: coordinate, address: address, basePath: basePath)
        
        return location!
    }
    
    func save() {
        if let location = location {
            NSKeyedArchiver.archiveRootObject(location, toFile: savePath.path!)
        }
        else {
            do {
                try NSFileManager.defaultManager().removeItemAtURL(savePath)
            }
            catch {
                print("unable to remove locations \(error)")
            }
        }
    }
    
    func load() {
        guard let location = NSKeyedUnarchiver.unarchiveObjectWithFile(savePath.path!) as? Location else { return }
        location.basePath = basePath
        self.location = location
    }
    
    deinit {
        location?.clearResources = false
    }
}