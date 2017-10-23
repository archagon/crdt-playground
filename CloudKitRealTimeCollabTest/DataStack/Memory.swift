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
    public typealias InstanceID = UUID
    
    public private(set) var openInstances = Set<InstanceID>()
    private var instances = [InstanceID:CausalTreeString]()
    
    init()
    {
    }
    
    public func getInstance(_ id: InstanceID) -> CausalTreeString?
    {
        return instances[id]
    }
    
    // creates new tree and associates it with an id
    public func create(_ data: CausalTreeString? = nil) -> InstanceID
    {
        let tree = data ?? CausalTreeString(site: DataStack.sharedInstance.id, clock: 0)
        let id = UUID()
        open(tree, id)
        return id
    }
    
    // associates a tree with an id
    public func open(_ model: CausalTreeString, _ id: InstanceID)
    {
        openInstances.insert(id)
        instances[id] = model
    }
    
    // unbinds a tree from its id
    public func close(_ id: InstanceID)
    {
        instances.removeValue(forKey: id)
        openInstances.remove(id)
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
    }
}
