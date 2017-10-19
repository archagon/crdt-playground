//
//  AppDelegate.swift
//  CloudKitRealTimeCollabTest
//
//  Created by Alexei Baboulevitch on 2017-10-19.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import UIKit
import CRDTFramework_iOS

func rb() -> UInt8 { return UInt8(arc4random_uniform(UInt32(UInt8.max))) }

@UIApplicationMain class AppDelegate: UIResponder, UIApplicationDelegate, UISplitViewControllerDelegate
{
    var window: UIWindow?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool
    {
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
                    a = UUID(uuid: uuid_t(rb(),rb(),rb(),rb(),rb(),rb(),rb(),rb(),rb(),rb(),rb(),rb(),rb(),rb(),rb(),rb()))
                    b = UUID(uuid: uuid_t(rb(),rb(),rb(),rb(),rb(),rb(),rb(),rb(),rb(),rb(),rb(),rb(),rb(),rb(),rb(),rb()))
                }
                
                static var zero: LargeStruct
                {
                    return LargeStruct(a: UUID.zero, b: UUID.zero)
                }
            }
            
            let count = (50 * 1024 * 1024) / MemoryLayout<LargeStruct>.size
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
            print("Character size: \(MemoryLayout<Character>.size)")
            
            let string = CausalTreeString(site: UUID(), clock: 0)
            
            let count = (50 * 1024 * 1024) / MemoryLayout<CausalTreeString.WeaveT.Atom>.size
            print("Count: \(count)")
            
            timeMe({
                var prevAtom = string.weave.weave()[0].id
                for i in 0..<count
                {
                    let newAtom = string.weave.addAtom(withValue: UTF8Char(arc4random_uniform(UInt32(UTF8Char.max))), causedBy: prevAtom, atTime: 0)
                    prevAtom = newAtom!.0
                }
            }, "String Create")
            
            for _ in 0..<100
            {
                timeMe({
                    let weave = string.weave.weave()
                    let randomAtom = 1 + Int(arc4random_uniform(UInt32(weave.count - 2)))
                    let _ = string.weave.addAtom(withValue: UTF8Char(arc4random_uniform(UInt32(UTF8Char.max))), causedBy: weave[randomAtom].id, atTime: 0)
                }, "String Insert", every: 10)
            }
        }
        
        let splitViewController = window!.rootViewController as! UISplitViewController
        let navigationController = splitViewController.viewControllers[splitViewController.viewControllers.count-1] as! UINavigationController
        navigationController.topViewController!.navigationItem.leftBarButtonItem = splitViewController.displayModeButtonItem
        splitViewController.delegate = self
        return true
    }

    // MARK: - Split view

    func splitViewController(_ splitViewController: UISplitViewController, collapseSecondary secondaryViewController:UIViewController, onto primaryViewController:UIViewController) -> Bool
    {
        guard let secondaryAsNavController = secondaryViewController as? UINavigationController else { return false }
        guard let topAsDetailController = secondaryAsNavController.topViewController as? DetailViewController else { return false }
        if topAsDetailController.detailItem == nil
        {
            // Return true to indicate that we have handled the collapse by doing nothing; the secondary controller will be discarded.
            return true
        }
        return false
    }
}
