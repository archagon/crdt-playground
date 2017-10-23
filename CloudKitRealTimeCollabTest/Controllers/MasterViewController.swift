//
//  MasterViewController.swift
//  CloudKitRealTimeCollabTest
//
//  Created by Alexei Baboulevitch on 2017-10-19.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import UIKit

class MasterViewController: UIViewController, UITableViewDataSource, UITableViewDelegate
{
    @IBOutlet var tableView: UITableView!
    @IBOutlet var label: UILabel!
    @IBOutlet var spinner: UIActivityIndicatorView!
    var detailViewController: DetailViewController? = nil
    
    var ids: [Network.FileID] = []
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        navigationItem.leftBarButtonItem = editButtonItem

        let addButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(insertNewObject(_:)))
        navigationItem.rightBarButtonItem = addButton
        
        if let split = splitViewController
        {
            let controllers = split.viewControllers
            detailViewController = (controllers[controllers.count-1] as! UINavigationController).topViewController as? DetailViewController
        }
        
        prepare()
    }

    override func viewWillAppear(_ animated: Bool)
    {
        if splitViewController?.isCollapsed == true
        {
            tableView.selectRow(at: nil, animated: false, scrollPosition: .none)
        }

        super.viewWillAppear(animated)
    }

    override func didReceiveMemoryWarning()
    {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    @objc func insertNewObject(_ sender: Any)
    {
        create()
    }

    // MARK: - Segues

    var pendingMemoryId: Memory.InstanceID?
    
    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool
    {
        if identifier == "showDetail"
        {
            if let indexPath = tableView.indexPathForSelectedRow
            {
                let id = self.ids[indexPath.row]
                
                let group = DispatchGroup()
                group.enter()
                
                var memoryId: Memory.InstanceID?
                var returnError: Error? = nil
                
                // this should actually not take any thread-time if the data was retrieved correctly
                DataStack.sharedInstance.memoryNetworkLayer.sendNetworkToInstance(id)
                { id,e in
                    defer
                    {
                        group.leave()
                    }
                    
                    if let error = e
                    {
                        returnError = error
                    }
                    else
                    {
                        memoryId = id
                    }
                }
                
                group.wait()
                
                pendingMemoryId = memoryId
                
                if let e = returnError
                {
                    err("Error retrieving file: \(e)")
                }
                
                return returnError == nil ? true : false
            }
            else
            {
                return false
            }
        }
        
        return false
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?)
    {
        if segue.identifier == "showDetail"
        {
            if let _ = tableView.indexPathForSelectedRow, let memoryId = pendingMemoryId
            {
                let controller = (segue.destination as! UINavigationController).topViewController as! DetailViewController

                let crdt = DataStack.sharedInstance.memory.getInstance(memoryId)
                controller.crdt = crdt
                controller.navigationItem.leftBarButtonItem = splitViewController?.displayModeButtonItem
                controller.navigationItem.leftItemsSupplementBackButton = true
            }
            
            pendingMemoryId = nil
        }
    }

    // MARK: - Table View

    func numberOfSections(in tableView: UITableView) -> Int
    {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int
    {
        return self.ids.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell
    {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)

        let metadata = DataStack.sharedInstance.network.metadata(self.ids[indexPath.row])!
        cell.textLabel!.text = metadata.name
        return cell
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool
    {
        // Return false if you do not want the specified item to be editable.
        return true
    }

//    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath)
//    {
//        if editingStyle == .delete
//        {
//            objects.remove(at: indexPath.row)
//            tableView.deleteRows(at: [indexPath], with: .fade)
//        }
//        else if editingStyle == .insert
//        {
//            // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view.
//        }
//    }
    
    // MARK: - Sync
    
    func enableInterface(_ enable: Bool)
    {
        self.tableView.allowsSelection = enable
        self.navigationItem.leftBarButtonItem?.isEnabled = enable
        self.navigationItem.rightBarButtonItem?.isEnabled = enable
    }
    
    func prepare()
    {
        enableInterface(false)
        
        msg("Logging in...")
        
        DataStack.sharedInstance.network.updateLogin
        { e in
            if let error = e
            {
                self.err("Could not log in: \(error)")
            }
            else
            {
                self.msg("Logged in, getting files...")
                
                DataStack.sharedInstance.network.syncCache
                { e in
                    if let error = e
                    {
                        self.err("Could not get files: \(error)")
                    }
                    else
                    {
                        self.scs("Retrieved files, ready to roll!")
                        
                        self.ids = DataStack.sharedInstance.network.ids()
                        self.tableView.reloadData()
                        
                        self.enableInterface(true)
                    }
                }
            }
        }
    }
    
    func create()
    {
        let id = DataStack.sharedInstance.memory.create()
        let tree = DataStack.sharedInstance.memory.getInstance(id)!
        let crdtString = CausalTreeStringWrapper()
        crdtString.initialize(crdt: tree)
        crdtString.append("Edit me! Created on \(Date().description) by \(DataStack.sharedInstance.id)")
        
        enableInterface(false)
        
        msg("Creating file...")
        
        DataStack.sharedInstance.memoryNetworkLayer.sendInstanceToNetwork(id)
        { n,e in
            defer
            {
                // file was only opened to save
                DataStack.sharedInstance.memory.close(id)
                DataStack.sharedInstance.memoryNetworkLayer.tempUnmap(memory: id)
            }
            
            if let error = e
            {
                self.err("Could not create file: \(error)")
            }
            else
            {
                self.scs("Created file, good to go!")
                
                self.ids.insert(n, at: 0)
                let indexPath = IndexPath(row: 0, section: 0)
                self.tableView.insertRows(at: [indexPath], with: .automatic)
                
                self.enableInterface(true)
            }
        }
    }
    
//    lazy var syncQueue: OperationQueue =
//    {
//        let queue = OperationQueue()
//        queue.name = "sync"
//        return queue
//    }()
    
    func sync(file: Int)
    {
    }
    
    // case: auth toggle on view did appear again
    
    // MARK: - Other
    
    func err(_ msg: String)
    {
        self.spinner.stopAnimating()
        self.spinner.isHidden = true
        
        self.label.textColor = UIColor.red
        self.label.text = msg
    }
    
    func scs(_ msg: String)
    {
        self.spinner.stopAnimating()
        self.spinner.isHidden = true
        
        var hue: CGFloat = 0
        UIColor.green.getHue(&hue, saturation: nil, brightness: nil, alpha: nil)
        self.label.textColor = UIColor(hue: hue, saturation: 0.85, brightness: 0.95, alpha: 1.0)
        self.label.text = msg
    }
    
    func msg(_ msg: String)
    {
        self.spinner.startAnimating()
        self.spinner.isHidden = false
        
        var hue: CGFloat = 0
        UIColor.blue.getHue(&hue, saturation: nil, brightness: nil, alpha: nil)
        self.label.textColor = UIColor(hue: hue, saturation: 0.9, brightness: 1.0, alpha: 1.0)
        self.label.text = msg
    }
}
