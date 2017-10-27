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
        case idsNotMapped
    }
    
    private var mappingNM: [Network.FileID:Memory.InstanceID] = [:]
    private var mappingMN: [Memory.InstanceID:Network.FileID] = [:]
    private func updateMapping(_ mid: Memory.InstanceID, _ nid: Network.FileID) { mappingMN[mid] = nid; mappingNM[nid] = mid; }
    private func unmapM(_ mid: Memory.InstanceID) { mappingNM.removeValue(forKey: mappingMN[mid]!); mappingMN.removeValue(forKey: mid); }
    private func unmapN(_ nid: Network.FileID) { mappingMN.removeValue(forKey: mappingNM[nid]!); mappingNM.removeValue(forKey: nid); }
    
    init()
    {
        NotificationCenter.default.addObserver(forName: Memory.InstanceChangedNotification, object: nil, queue: nil)
        { n in
            guard let diffs = n.userInfo?[Memory.InstanceChangedNotificationHashesKey] as? [Memory.InstanceID] else
            {
                precondition(false, "userInfo array missing object")
                return
            }

            print("Tree changed for instances: \(diffs)")
            
            for id in diffs
            {
                self.sendInstanceToNetwork(id, createIfNeeded: false)
                { n,e in
                    print("Syncing instance \(id)...")
                    
                    if let error = e
                    {
                        if let netErr = error as? Network.NetworkError, netErr == Network.NetworkError.mergeSupplanted
                        {
                            print("Mege already enqueued, continuing...")
                        }
                        else if let netErr = error as? Network.NetworkError, netErr == Network.NetworkError.mergeConflict
                        {
                            print("Conflict detected, merging back in...")
                            
                            self.sendNetworkToInstance(n, createIfNeeded: false)
                            { mid,e in
                                if let error = e
                                {
                                    print("Merge error: \(error)")
                                    assert(false)
                                }
                            }
                        }
                        else
                        {
                            print("Could not sync instance: \(error)")
                        }
                    }
                    else
                    {
                        print("Sync complete!")
                    }
                }
            }
        }
        
        NotificationCenter.default.addObserver(forName: Network.FileChangedNotification, object: nil, queue: nil)
        { n in
            guard let ids = n.userInfo?[Network.FileChangedNotificationIDsKey] as? [Network.FileID] else
            {
                precondition(false, "userInfo array missing object")
                return
            }
            
            for id in ids
            {
                DataStack.sharedInstance.network.getFile(id)
                { pair in
                    if pair == nil
                    {
                        assert(false, "deletion sync not yet implemented")
                    }
                    else
                    {
                        self.sendNetworkToInstance(id, createIfNeeded: false)
                        { mid,e in
                            if let error = e
                            {
                                print("Could not sync from remote: \(error)")
                            }
                            else
                            {
                                print("Sync from remote complete!")
                            }
                        }
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
    public func sendNetworkToInstance(_ id: Network.FileID, createIfNeeded: Bool, _ block: @escaping (Memory.InstanceID, Error?)->())
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
            let _ = tree.transferToNewOwner(withUUID: DataStack.sharedInstance.id)
            
            if let memoryId = mappingNM[id]
            {
                DataStack.sharedInstance.memory.merge(memoryId, &tree)
                block(memoryId, nil)
            }
            else if createIfNeeded
            {
                let mid = DataStack.sharedInstance.memory.create(withString: nil, orWithData: tree)
                updateMapping(mid, id)
                block(mid, nil)
            }
            else
            {
                // not really an error
                block(Memory.InstanceID.zero, ConsistencyError.idsNotMapped)
            }
        }
    }
    
    // memory -> network, creating if necessary
    public func sendInstanceToNetwork(_ id: Memory.InstanceID, createIfNeeded: Bool, _ block: @escaping (Network.FileID, Error?)->())
    {
        guard let tree = DataStack.sharedInstance.memory.getInstance(id) else
        {
            assert(false)
            block(Network.FileID(""), ConsistencyError.memoryDoesNotContainContentsForId)
            return
        }
        
        let data = convertMemoryToNetwork(tree)
        
        if let networkId = mappingMN[id]
        {
            DataStack.sharedInstance.network.merge(networkId, data)
            { e in
                if let error = e
                {
                    block(networkId, error)
                }
                else
                {
                    block(networkId, nil)
                }
            }
        }
        else if createIfNeeded
        {
            DataStack.sharedInstance.network.create(file: data, named: Date().description)
            { m,e in
                if let error = e
                {
                    assert(false)
                    block(Network.FileID(""), error)
                }
                else
                {
                    self.updateMapping(id, m.id.recordName)
                    block(m.id.recordName, nil)
                }
            }
        }
        else
        {
            assert(false)
            block(Network.FileID(""), ConsistencyError.idsNotMapped)
        }
    }
    
    // TODO: does this belong here?
    public func delete(_ nid: Network.FileID, _ block: @escaping (Error?)->())
    {
        if let mid = mappingNM[nid]
        {
            DataStack.sharedInstance.memory.close(mid)
            unmapM(mid)
        }
        
        DataStack.sharedInstance.network.delete(nid)
        { e in
            block(e)
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
