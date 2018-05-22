//
//  AppDelegate.swift
//  Ohmycar
//
//  Created by Solomenchuk, Vlad on 5/11/16.
//  Copyright © 2016 Aramzamzam LLC. All rights reserved.
//

import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func applicationDidFinishLaunching(_ application: UIApplication) {
        Database.instance.load()
    }
}

