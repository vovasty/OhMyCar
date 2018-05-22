//
//  Database.swift
//  Ohmycar
//
//  Created by Solomenchuk, Vlad on 5/11/16.
//  Copyright © 2016 Aramzamzam LLC. All rights reserved.
//

import MapKit

extension CLLocationCoordinate2D: Codable {
    enum CodingKeys: String, CodingKey {
        case lon
        case lat
    }
    
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try values.decode(Double.self, forKey: .lat)
        let longitude = try values.decode(Double.self, forKey: .lon)
        
        self = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .lat)
        try container.encode(longitude, forKey: .lon)
    }
}

class Location: Codable {
    var coordinate: CLLocationCoordinate2D
    var address: [String: AnyObject]?
    var date = Date()
    var editable = false
    
    private var imageName: String?
    fileprivate var basePath: URL?
    private var imagePath: URL? {
        guard let imageName = imageName else { return nil }
        return basePath?.appendingPathComponent(imageName)
    }
    fileprivate var clearResources = true
    
    
    enum CodingKeys: String, CodingKey {
        case coordinate, date
    }

    var image: UIImage? {
        set {
            guard let image = newValue else {
                if let imagePath = imagePath {
                    do {
                        try FileManager.default.removeItem(at: imagePath)
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
                imageName = NSUUID().uuidString
            }

            let imageData = UIImageJPEGRepresentation(image, 0.7)
            try? imageData?.write(to: imagePath!)

            print("image saved to \(imagePath!)")
        }

        get {
            guard let path = imagePath?.path else { return nil }
            return UIImage(contentsOfFile: path)
        }
    }

    fileprivate init(coordinate: CLLocationCoordinate2D, address: [String: AnyObject]?, basePath: URL? = nil) {
        self.address = address
        self.coordinate = coordinate
        self.basePath = basePath
    }

    var formattedAddress: String? {
        return (address?["FormattedAddressLines"] as? [String])?.joined(separator: " ")
    }

    deinit {
        guard clearResources, let imagePath = imagePath else { return }
        do {
            try FileManager.default.removeItem(at: imagePath)
            print("removed image \(imagePath)")
        }
        catch {
            print("unable to remove image \(error)")
        }
    }
}

class Database {
    var location: Location?
    let savePath: URL
    
    static var instance : Database = Database(savePath: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("location.plist"))
    
    init(savePath: URL) {
        self.savePath = savePath
    }

    func recordLocation(coordinate: CLLocationCoordinate2D, address: [String: AnyObject]?) -> Location {
        location = Location(coordinate: coordinate, address: address, basePath: savePath.baseURL)
        
        return location!
    }
    
    func save() {
        if let location = location {
            let encoder = PropertyListEncoder()
            let data = try! encoder.encode(location)
            try! data.write(to: savePath)
        }
        else {
            do {
                try FileManager.default.removeItem(at: savePath)
            }
            catch {
                print("unable to remove locations \(error)")
            }
        }
    }
    
    func load() {
        guard let location = NSKeyedUnarchiver.unarchiveObject(withFile: savePath.path) as? Location else { return }
        location.basePath = savePath.baseURL!
        self.location = location
    }
    
    deinit {
        location?.clearResources = false
    }
}
