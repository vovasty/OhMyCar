//
//  HistoryViewController.swift
//  Ohmycar
//
//  Created by Solomenchuk, Vlad on 5/11/16.
//  Copyright © 2016 Aramzamzam LLC. All rights reserved.
//

import UIKit

class HistoryViewController: UITableViewController {
    var location: Location?
    
    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Database.instance.locations.count
    }
    
    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier("HistoryCell")!
        let location = Database.instance.locations[indexPath.row]
        
        cell.textLabel?.text = location.formattedAddress ?? "My Car"
        
        return cell
    }
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        guard let indexPath = tableView.indexPathForSelectedRow else { return }
        location = Database.instance.locations[indexPath.row]
    }
}
