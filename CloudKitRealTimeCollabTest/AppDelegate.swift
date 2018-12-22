//
//  AppDelegate.swift
//  CloudKitRealTimeCollabTest
//
//  Created by Alexei Baboulevitch on 2017-10-19.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import UIKit
import UserNotifications
import CloudKit
//import CRDTFramework_iOS

// AB: bridged frameworks get 10x worse performance, so we're forced to just include the files until we figure
// out how to do a pure Swift framework
@UIApplicationMain class AppDelegate: UIResponder, UIApplicationDelegate, UISplitViewControllerDelegate
{
    var window: UIWindow?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        print("Device UUID: \(DataStack.sharedInstance.id)")
        
        // AB: for this to work, we need remote notification background mode enabled
        application.registerForRemoteNotifications()
        
        let megabytes = 50
        
        tests: do
        {
            break tests
            struct LargeStruct
            {
                let a: UUID
                let b: UUID
                
                init(a: UUID, b: UUID)
                {
                    self.a = a
                    self.b = b
                }
                
                init()
                {
                    a = UUID(uuid: uuid_t(rand(),rand(),rand(),rand(),rand(),rand(),rand(),rand(),rand(),rand(),rand(),rand(),rand(),rand(),rand(),rand()))
                    b = UUID(uuid: uuid_t(rand(),rand(),rand(),rand(),rand(),rand(),rand(),rand(),rand(),rand(),rand(),rand(),rand(),rand(),rand(),rand()))
                }
                
                static var zero: LargeStruct
                {
                    return LargeStruct(a: UUID.zero, b: UUID.zero)
                }
            }
            
            let count = (megabytes * 1024 * 1024) / MemoryLayout<LargeStruct>.size
            print("Count: \(count)")
            
            var data: [LargeStruct] = []
            func allocArray()
            {
                data = []
                data.reserveCapacity(count)
                for _ in 0..<count
                {
                    data.append(LargeStruct())
                }
            }
            
            timeMe({
                allocArray()
            }, "Large Array Alloc")
            
            timeMe({
                for i in 0..<data.count
                {
                    if Int(data[i].a.uuid.1) < UInt8.max
                    {
                        data[i] = LargeStruct.zero
                    }
                }
            }, "Large Array Mutate")
            
            //allocArray()
            //timeMe({
            //    let _ = data
            //}, "Large Array Assign")
            
            allocArray()
            timeMe({
                var newData = data
                newData[100] = LargeStruct()
            }, "Large Array Assign and Mutate")
            
            allocArray()
            timeMe({
                var newData = [LargeStruct](data)
                newData[100] = LargeStruct()
                newData[10000] = LargeStruct()
            }, "Large Array Init Copy")
            
            //allocArray()
            //timeMe({
            //    var newData = Array<LargeStruct>(data)
            //    newData[100] = LargeStruct()
            //    newData[100000] = LargeStruct()
            //}, "Large Array Init Copy 2")
            
            //allocArray()
            //timeMe({
            //    var newData = [LargeStruct](repeating: LargeStruct.zero, count: data.count)
            //    memcpy(&newData, &data, data.count)
            //}, "memcpy")
            
            allocArray()
            timeMe({
                let data = NSMutableData(bytes: &data, length: data.count)
                let bytes: [UInt8] = [8]
                data.replaceBytes(in: NSMakeRange(1000, 1), withBytes: bytes)
            }, "Data Copy")
            
            allocArray()
            for _ in 0..<100
            {
                timeMe({
                    data.insert(LargeStruct(), at: Int(arc4random_uniform(UInt32(data.count))))
                }, "Large Array Insert", every: 10)
            }
        }
        
        treeTest: do
        {
            break treeTest
            print("Character size: \(MemoryLayout<Character>.size)")
            
            let string = CausalTreeString(site: UUID(), clock: 0)
            
            let count = (megabytes * 1024 * 1024) / MemoryLayout<CausalTreeString.WeaveT.AtomT>.size
            print("Count: \(count)")
            
            timeMe({
                var prevAtom = string.weave.weave()[0].id
                for _ in 0..<count
                {
                    //if i % 1000 == 0
                    //{
                    //    print("on: \(i)")
                    //}
                    let newAtom = string.weave.addAtom(withValue: StringCharacterAtom(insert: rand()), causedBy: prevAtom)
                    prevAtom = newAtom!.0
                }
            }, "String Create")
            
            sleep(1)
            
            for _ in 0..<100
            {
                timeMe({
                    let weave = string.weave.weave()
                    let randomAtom = 1 + Int(arc4random_uniform(UInt32(weave.count - 2)))
                    let parent = weave[randomAtom].id
                    let _ = string.weave.addAtom(withValue: StringCharacterAtom(insert: rand()), causedBy: parent)
                }, "String Insert", every: 10)
            }
        }
        
        stringTest: do
        {
            break stringTest
            let tree = CausalTreeString(site: UUID(), clock: 0)
            let string = CausalTreeStringWrapper()
            string.initialize(crdt: tree)
            
            string.append("test")
            string.insert("oa", at: 1)
            string.deleteCharacters(in: NSMakeRange(3, 2))
            string.replaceCharacters(in: NSMakeRange(3, 1), with: "stiest")
            string.append("😀")
            string.insert("🇧🇴", at: 0)
            //string.replaceCharacters(in: NSMakeRange(1, 1), with: "gr")
            
            print(string)
            print("Count: \(string.length)")
            print(tree.weave.atomsDescription)
            print(tree.weave)
            let _ = try! tree.validate()
        }
        
        let splitViewController = window!.rootViewController as! UISplitViewController
        let navigationController = splitViewController.viewControllers[splitViewController.viewControllers.count-1] as! UINavigationController
        navigationController.topViewController!.navigationItem.leftBarButtonItem = splitViewController.displayModeButtonItem
        splitViewController.delegate = self
        
        return true
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data)
    {
        print("Yay, can receive remote changes!")
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error)
    {
        #if !(arch(i386) || arch(x86_64)) //simulator can't receive notifications
        assert(false, "remote notifications needed to receive changes")
        #endif
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void)
    {
        let ckNotification = CKNotification(fromRemoteNotificationDictionary: userInfo)
        DataStack.sharedInstance.network.receiveNotification(ckNotification)
        { e in
            if let error = e
            {
                print("Could not fetch changes: \(error)")
                completionHandler(UIBackgroundFetchResult.failed)
            }
            else
            {
                completionHandler(UIBackgroundFetchResult.newData)
            }
        }
    }
    
    private func application(_ application: UIApplication, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata)
    {
        let op = CKAcceptSharesOperation(shareMetadatas: [cloudKitShareMetadata])
        
        op.acceptSharesCompletionBlock =
        { error in
            if let error = error
            {
                print(error)
                assert(false)
            }
            else
            {
                print("share accepted")
            }
        }
        
        op.qualityOfService = .userInteractive
        
        CKContainer.default().add(op)
    }

    // MARK: - Split view

    func splitViewController(_ splitViewController: UISplitViewController, collapseSecondary secondaryViewController:UIViewController, onto primaryViewController:UIViewController) -> Bool
    {
        guard let secondaryAsNavController = secondaryViewController as? UINavigationController else { return false }
        guard let topAsDetailController = secondaryAsNavController.topViewController as? DetailViewController else { return false }
        if topAsDetailController.crdt == nil
        {
            // Return true to indicate that we have handled the collapse by doing nothing; the secondary controller will be discarded.
            return true
        }
        return false
    }
}
