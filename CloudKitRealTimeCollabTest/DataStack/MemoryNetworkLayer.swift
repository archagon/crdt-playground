//
//  MemoryNetworkLayer.swift
//  CloudKitRealTimeCollabTest
//
//  Created by Alexei Baboulevitch on 2017-10-21.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import Foundation

// deals with communication between memory and network (no disk storage in this sample code)
class MemoryNetworkLayer
{
    public enum ConsistencyError: Error
    {
        case memoryDoesNotContainContentsForId
        case networkDoesNotContainFileForId
    }
    
    private var mappingNM: [Network.FileID:Memory.InstanceID] = [:]
    private var mappingMN: [Memory.InstanceID:Network.FileID] = [:]
    private func updateMapping(_ mid: Memory.InstanceID, _ nid: Network.FileID) { mappingMN[mid] = nid; mappingNM[nid] = mid; }
    private func unmapM(_ mid: Memory.InstanceID) { mappingNM.removeValue(forKey: mappingMN[mid]!); mappingMN.removeValue(forKey: mid); }
    private func unmapN(_ nid: Network.FileID) { mappingMN.removeValue(forKey: mappingNM[nid]!); mappingNM.removeValue(forKey: nid); }
    
    init()
    {
        // subscribe to mutation/network notifications
        NotificationCenter.default.addObserver(forName: Memory.InstanceChangedNotification, object: nil, queue: nil)
        { n in
            guard let diffs = n.userInfo?[Memory.InstanceChangedNotificationHashesKey] as? [Memory.InstanceID] else
            {
                return
            }

            print("Tree changed for instances: \(diffs)")
            
            for id in diffs
            {
                self.sendInstanceToNetwork(id)
                { n,e in
                    print("Syncing instance \(id)...")
                    
                    if let error = e
                    {
                        print("Could not sync instance: \(error)")
                    }
                    else
                    {
                        print("Sync complete!")
                    }
                }
            }
        }
    }
    
    // TODO: mapping?
    // TODO: unmap on delete
    
    public func tempUnmap(memory: Memory.InstanceID) { unmapM(memory) }
    public func tempUnmap(network: Network.FileID) { unmapN(network) }
    
    // network -> memory, creating if necessary
    public func sendNetworkToInstance(_ id: Network.FileID, _ block: @escaping (Memory.InstanceID, Error?)->())
    {
        DataStack.sharedInstance.network.getFile(id)
        { p in
            guard let pair = p else
            {
                assert(false)
                block(Memory.InstanceID.zero, ConsistencyError.networkDoesNotContainFileForId)
                return
            }
            
            var tree = convertNetworkToMemory(pair.1)
            
            if let memoryId = mappingNM[id]
            {
                DataStack.sharedInstance.memory.merge(memoryId, &tree)
                block(memoryId, nil)
            }
            else
            {
                let mid = DataStack.sharedInstance.memory.create(tree)
                updateMapping(mid, id)
                block(mid, nil)
            }
        }
    }
    
    // memory -> network, creating if necessary
    public func sendInstanceToNetwork(_ id: Memory.InstanceID, _ block: @escaping (Network.FileID, Error?)->())
    {
        guard let tree = DataStack.sharedInstance.memory.getInstance(id) else
        {
            assert(false)
            block(Network.FileID.init(recordName: ""), ConsistencyError.memoryDoesNotContainContentsForId)
            return
        }
        
        let data = convertMemoryToNetwork(tree)
        
        if let networkId = mappingMN[id]
        {
            DataStack.sharedInstance.network.merge(networkId, data)
            { e in
                if let error = e
                {
                    block(Network.FileID.init(recordName: ""), error)
                }
                else
                {
                    block(networkId, nil)
                }
            }
        }
        else
        {
            DataStack.sharedInstance.network.create(file: data, named: Date().description)
            { m,e in
                if let error = e
                {
                    block(Network.FileID.init(recordName: ""), error)
                }
                else
                {
                    self.updateMapping(id, m.id)
                    block(m.id, nil)
                }
            }
        }
    }
    
    // network conflict could not be resolved on network layer, so try next layer
//    public func bubbleUpNetworkConflict(id: Network.FileID, withData data: Data, _ block: (Error?)->())
//    {
//        guard let memoryId = mappingNM[id] else
//        {
//            assert(false)
//            return
//        }
//
//        let mergeData = convertNetworkToMemory(data)
//
//        DataStack.sharedInstance.memory.merge(memoryId, mergeData)
//
//        block(nil)
//
//        // enqueue sync
//        syncInstanceToNetwork(memoryId) { id,e in }
//    }
    
    // TODO: async
    public func convertMemoryToNetwork(_ m: CausalTreeString) -> Data
    {
        let bytes = try! BinaryEncoder.encode(m)
        let data = Data.init(bytes: bytes)
        
        return data
    }
    
    // TODO: async
    public func convertNetworkToMemory(_ n: Data) -> CausalTreeString
    {
        let bytes = [UInt8](n)
        let tree = try! BinaryDecoder.decode(CausalTreeString.self, data: bytes)
        
        return tree
    }
}
