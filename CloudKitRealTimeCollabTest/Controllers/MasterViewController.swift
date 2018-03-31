//
//  MasterViewController.swift
//  CloudKitRealTimeCollabTest
//
//  Created by Alexei Baboulevitch on 2017-10-19.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import UIKit

class MasterViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var label: UILabel!
    @IBOutlet weak var spinner: UIActivityIndicatorView!
    var detailViewController: DetailViewController? = nil

    var ids: [Network.FileID] = []

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.leftBarButtonItem = editButtonItem

        let addButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(insertNewObject(_:)))
        navigationItem.rightBarButtonItem = addButton

        self.tableView.contentInset = UIEdgeInsetsMake(0, 0, label.superview!.bounds.height, 0)

        if let split = splitViewController {
            let controllers = split.viewControllers
            detailViewController = (controllers[controllers.count-1] as! UINavigationController).topViewController as? DetailViewController
        }

        NotificationCenter.default.addObserver(forName: .FileChanged, object: nil, queue: nil) { n in
            // TODO: use these for things other than reload
            let changedIdsArray: [Network.FileID] = n.userInfo?[Network.FileChangedNotificationIDsKey] as? [Network.FileID] ?? []
            let changedIds = Set(changedIdsArray)

            let newIds = DataStack.sharedInstance.network.ids()

            let oldIdsSet = Set(self.ids)
            let newIdsSet = Set(newIds)

            assert(oldIdsSet.count == self.ids.count && newIdsSet.count == newIds.count)

            let insertions = newIdsSet.subtracting(oldIdsSet)
            let deletions = oldIdsSet.subtracting(newIdsSet)
            let refreshes = newIdsSet.intersection(oldIdsSet).intersection(changedIds)

            var insertionCommands: [IndexPath] = []
            var deletionCommands: [IndexPath] = []
            var refreshCommands: [IndexPath] = []

            var i = 0
            while i < self.ids.count {
                if refreshes.contains(self.ids[i]) {
                    refreshCommands.append(IndexPath(row: i, section: 0))
                }

                if deletions.contains(self.ids[i]) {
                    deletionCommands.append(IndexPath(row: i, section: 0))
                }

                i += 1
            }

            var j = 0
            while j < newIds.count {
                if insertions.contains(newIds[j]) {
                    insertionCommands.append(IndexPath(row: j, section: 0))
                }

                j += 1
            }

            self.ids = newIds

            self.tableView.beginUpdates()
            self.tableView.reloadRows(at: refreshCommands, with: UITableViewRowAnimation.automatic)
            self.tableView.deleteRows(at: deletionCommands, with: UITableViewRowAnimation.automatic)
            self.tableView.insertRows(at: insertionCommands, with: UITableViewRowAnimation.automatic)
            self.tableView.endUpdates()

            if let id = self.detailViewController?.id, deletions.contains(id) {
                self.navigationController?.popViewController(animated: true)
            }
        }

        prepare()
    }

    override func viewWillAppear(_ animated: Bool) {
        if splitViewController?.isCollapsed == true {
            tableView.selectRow(at: nil, animated: false, scrollPosition: .none)
        }

        super.viewWillAppear(animated)
    }

    @objc func insertNewObject(_ sender: Any) {
        create()
    }

    // MARK: - Segues

    var pendingMemoryId: Memory.InstanceID?

    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        if identifier == "showDetail" {
            if let indexPath = tableView.indexPathForSelectedRow {
                let id = self.ids[indexPath.row]

                let group = DispatchGroup()
                group.enter()

                var memoryId: Memory.InstanceID?
                var returnError: Error? = nil

                // this should actually not take any thread-time if the data was retrieved correctly
                DataStack.sharedInstance.memoryNetworkLayer.sendNetworkToInstance(id, createIfNeeded: true, continuingAfterMergeConflict: false) { id,e in
                    defer {
                        group.leave()
                    }

                    if let error = e {
                        returnError = error
                    }
                    else {
                        memoryId = id
                    }
                }

                group.wait()

                pendingMemoryId = memoryId

                if let e = returnError {
                    err("Error retrieving file: \(e)")
                }

                return returnError == nil ? true : false
            }
            else {
                return false
            }
        }

        return false
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "showDetail" {
            let controller = (segue.destination as! UINavigationController).topViewController as! DetailViewController

            if let indexPath = tableView.indexPathForSelectedRow, let memoryId = pendingMemoryId {
                let crdt = DataStack.sharedInstance.memory.instance(for: memoryId)
                controller.crdt = crdt
                controller.id = self.ids[indexPath.row]
                controller.navigationItem.leftBarButtonItem = splitViewController?.displayModeButtonItem
                controller.navigationItem.leftItemsSupplementBackButton = true
            }

            detailViewController = controller
            pendingMemoryId = nil
        }
    }

    // MARK: - Table View

    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.ids.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)

        let metadata = DataStack.sharedInstance.network.metadata(self.ids[indexPath.row])!
        cell.textLabel!.text = metadata.name

        var hue: CGFloat = 0
        UIColor.green.getHue(&hue, saturation: nil, brightness: nil, alpha: nil)
        let green = UIColor(hue: hue, saturation: 0.9, brightness: 0.8, alpha: 1.0)

        cell.textLabel!.textColor = (metadata.remoteShared ? green : (metadata.associatedShare != nil ? UIColor.blue : UIColor.black))
        return cell
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return true
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            delete(ids[indexPath.row])
        }
        else if editingStyle == .insert {
            // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view.
        }
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        self.tableView.setEditing(editing, animated: true)
    }

    // MARK: - Sync

    func enableInterface(_ enable: Bool) {
        self.tableView.isUserInteractionEnabled = enable
        self.tableView.allowsSelection = enable
        self.navigationItem.leftBarButtonItem?.isEnabled = enable
        self.navigationItem.rightBarButtonItem?.isEnabled = enable
    }

    func prepare() {
        enableInterface(false)

        prg("Logging in...")

        DataStack.sharedInstance.network.login { e in
            if let error = e {
                self.err("Could not log in: \(error)")
            }
            else {
                if let error = e {
                    self.err("Could not get files: \(error)")
                }
                else {
                    self.scs("Retrieved files, ready to roll!")

                    self.ids = DataStack.sharedInstance.network.ids()
                    self.tableView.reloadData()

                    self.enableInterface(true)
                }
            }
        }
    }

    func create() {
        let id = DataStack.sharedInstance.memory.create(withString: "Edit me! Created on \(Date().description) by \(DataStack.sharedInstance.id)", orWithData: nil)
        let tree = DataStack.sharedInstance.memory.instance(for: id)!

        enableInterface(false)

        prg("Creating file...")

        DataStack.sharedInstance.memoryNetworkLayer.sendInstanceToNetwork(id, createIfNeeded: true) { n,e in
            defer {
                // file was only opened to save
                DataStack.sharedInstance.memory.close(id)
                DataStack.sharedInstance.memoryNetworkLayer.tempUnmap(memory: id)
            }

            if let error = e {
                self.err("Could not create file: \(error)")

                self.enableInterface(true)
            }
            else {
                self.scs("Created file, good to go!")

                // notification will have arrived at this point to alter table

                self.enableInterface(true)
            }
        }
    }

    func delete(_ id: Network.FileID) {
        let indexRow = self.ids.index(of: id)!
        let indexPath = IndexPath(row: indexRow, section: 0)

        enableInterface(false)

        prg("Deleting file...")

        DataStack.sharedInstance.memoryNetworkLayer.delete(id) { e in
            if let error = e {
                self.err("Could not delete file: \(error)")

                self.enableInterface(true)
            }
            else {
                self.msg("Deleted file!")

                // notification will have arrived at this point to alter table

                self.enableInterface(true)
            }
        }
    }

//    lazy var syncQueue: OperationQueue = {
//        let queue = OperationQueue()
//        queue.name = "sync"
//        return queue
//    }()

    func sync(file: Int) {
    }

    // case: auth toggle on view did appear again

    // MARK: - Other

    func err(_ msg: String) {
        self.spinner.stopAnimating()
        self.spinner.isHidden = true

        self.label.textColor = UIColor.red
        self.label.text = msg
    }

    func scs(_ msg: String) {
        self.spinner.stopAnimating()
        self.spinner.isHidden = true

        var hue: CGFloat = 0
        UIColor.green.getHue(&hue, saturation: nil, brightness: nil, alpha: nil)
        self.label.textColor = UIColor(hue: hue, saturation: 0.8, brightness: 0.7, alpha: 1.0)
        self.label.text = msg
    }

    func prg(_ msg: String) {
        self.spinner.startAnimating()
        self.spinner.isHidden = false

        var hue: CGFloat = 0
        UIColor.blue.getHue(&hue, saturation: nil, brightness: nil, alpha: nil)
        self.label.textColor = UIColor(hue: hue, saturation: 0.9, brightness: 1.0, alpha: 1.0)
        self.label.text = msg
    }

    func msg(_ msg: String, spin: Bool = false) {
        self.spinner.stopAnimating()
        self.spinner.isHidden = true

        var hue: CGFloat = 0
        UIColor.blue.getHue(&hue, saturation: nil, brightness: nil, alpha: nil)
        self.label.textColor = UIColor(hue: hue, saturation: 0.9, brightness: 1.0, alpha: 1.0)
        self.label.text = msg
    }
}
