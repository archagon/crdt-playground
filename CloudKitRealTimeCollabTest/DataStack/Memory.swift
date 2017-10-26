//
//  Memory.swift
//  CloudKitRealTimeCollabTest
//
//  Created by Alexei Baboulevitch on 2017-10-21.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import Foundation

// owns in-memory objects, working at the model layer
class Memory
{
    public static let InstanceChangedNotification = NSNotification.Name(rawValue: "InstanceChangedNotification")
    public static let InstanceChangedInternallyNotification = NSNotification.Name(rawValue: "InstanceChangedInternallyNotification")
    public static let InstanceChangedNotificationHashesKey = "hashes"
    public static let InstanceChangedInternallyNotificationIDKey = "id"
    
    public typealias InstanceID = UUID
    
    public private(set) var openInstances = Set<InstanceID>()
    private var instances = [InstanceID:CausalTreeString]()
    private var hashes: [InstanceID:Int] = [:]
    private var changeChecker: Timer!
    
    init()
    {
        // TODO: weak
        self.changeChecker = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true, block:
        { [weak self] t in
            guard let `self` = self else
            {
                return
            }
            
            var newHashes: [InstanceID]?
            
            for p in self.hashes
            {
                let h = self.instances[p.key]!.hashValue
                
                if p.value != h
                {
                    if newHashes == nil
                    {
                        newHashes = []
                    }
                    newHashes!.append(p.key)
                }
            }
            
            if let hashes = newHashes
            {
                NotificationCenter.default.post(name: Memory.InstanceChangedNotification, object: nil, userInfo: [Memory.InstanceChangedNotificationHashesKey:hashes])
                
                for p in hashes
                {
                    self.hashes[p] = self.instances[p]!.hashValue
                }
            }
        })
    }
    
    public func getInstance(_ id: InstanceID) -> CausalTreeString?
    {
        return instances[id]
    }
    
    // creates new tree and associates it with an id
    public func create(withString string: String? = nil, orWithData data: CausalTreeString? = nil) -> InstanceID
    {
        let tree: CausalTreeString
        
        if let str = string
        {
            let tr = CausalTreeString(site: DataStack.sharedInstance.id, clock: 0)
            let crdtString = CausalTreeStringWrapper()
            crdtString.initialize(crdt: tr)
            crdtString.append(str)
            tree = tr
        }
        else if let dat = data
        {
            tree = dat
            tree.transferToNewOwner(withUUID: DataStack.sharedInstance.id)
        }
        else
        {
            tree = CausalTreeString(site: DataStack.sharedInstance.id, clock: 0)
        }
        
        let id = UUID()
        open(tree, id)
        return id
    }
    
    // associates a tree with an id
    public func open(_ model: CausalTreeString, _ id: InstanceID)
    {
        print("Memory currently contains \(DataStack.sharedInstance.memory.openInstances.count) items, need to clear/unmap eventually...")
        
        openInstances.insert(id)
        instances[id] = model
        hashes[id] = model.hashValue
    }
    
    // unbinds a tree from its id
    public func close(_ id: InstanceID)
    {
        instances.removeValue(forKey: id)
        openInstances.remove(id)
        hashes.removeValue(forKey: id)
    }
    
    // merges a new tree into an existing tree
    public func merge(_ id: InstanceID, _ model: inout CausalTreeString)
    {
        guard let tree = getInstance(id) else
        {
            assert(false)
            return
        }
        
        tree.integrate(&model)
        
        // NEXT: create, open on 2nd device, edit on 2nd device, edit on 1st device -- wrong siteid merge
        let wrapper = CausalTreeStringWrapper()
        wrapper.initialize(crdt: model)
        let wrapper2 = CausalTreeStringWrapper()
        wrapper2.initialize(crdt: tree)
        
        NotificationCenter.default.post(name: Memory.InstanceChangedInternallyNotification, object: nil, userInfo: [Memory.InstanceChangedInternallyNotificationIDKey:id])
    }
}
