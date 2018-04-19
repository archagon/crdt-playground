//
//  ORDTWeftExtensions.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2018-4-18.
//  Copyright © 2018 Alexei Baboulevitch. All rights reserved.
//

import Foundation

// TODO: remove these
extension LUID: DefaultInitializable { public init() { self = 0 } }
extension LUID: Zeroable { public static var zero: LUID { return 0 } }
extension InstancedLUID: DefaultInitializable { public init() { self.luid = NullSiteID; self.instanceID = 0; } }
extension InstancedLUID: Zeroable { public static var zero: InstancedLUID { return InstancedLUID() } }
extension ORDTClock: DefaultInitializable { public init() { self = 0 } }
extension ORDTClock: Zeroable { public static var zero: ORDTClock { return 0 } }
extension ORDTSiteIndex: DefaultInitializable { public init() { self = 0 } }
extension ORDTSiteIndex: Zeroable { public static var zero: ORDTSiteIndex { return 0 } }

extension InstancedLUID
{
    public init(luid: LUID, instanceID: InstanceID? = nil)
    {
        precondition(luid != NullSiteID)
        
        self.luid = luid
        self.instanceID = instanceID ?? 0
    }
}
extension InstancedLUID: ExpressibleByIntegerLiteral
{
    public init(integerLiteral value: LUID)
    {
        self.init(luid: value)
    }
}
extension InstancedLUID: Comparable
{
    public static func <(lhs: InstancedLUID, rhs: InstancedLUID) -> Bool
    {
        return (lhs.luid < rhs.luid ? true : lhs.luid > rhs.luid ? false : lhs.instanceID < rhs.instanceID)
    }
    
    public static func ==(lhs: InstancedLUID, rhs: InstancedLUID) -> Bool
    {
        return !(lhs < rhs) && !(lhs > rhs)
    }
    
}
extension InstancedLUID: Hashable
{
    public var hashValue: Int
    {
        return self.luid.hashValue ^ self.instanceID.hashValue
    }
}
extension InstancedLUID: CustomStringConvertible, CustomDebugStringConvertible
{
    public var description: String
    {
        return "\(self.luid)\(self.instanceID == 0 ? "" : ".\(self.instanceID)")"
    }
    
    public var debugDescription: String
    {
        return "\(self.luid).\(self.instanceID)"
    }
}
extension InstancedLUID: IndexRemappable
{
    public mutating func remapIndices(_ map: [SiteId:SiteId])
    {
        if let newSite = map[SiteId(self.luid)]
        {
            self.luid = LUID(newSite)
        }
    }
}

extension ORDTWeft where SiteT == InstancedLUID
{
    mutating func update(site: SiteT, value: ValueT)
    {
        if site == NullInstancedLUID { return }
        mapping[site] = max(mapping[site] ?? ValueT.zero, value)
    }
}
extension ORDTWeft where SiteT == InstancedLUID
{
    public mutating func remapIndices(_ map: [SiteId:SiteId])
    {
        var newMap: [SiteT:ValueT] = [:]
        
        for (k,v) in self.mapping
        {
            if let newSite = map[SiteId(k.luid)]
            {
                newMap[InstancedLUID.init(luid: LUID(newSite), instanceID: k.instanceID)] = v
            }
            else
            {
                newMap[k] = v
            }
        }
        
        self.mapping = newMap
    }
}
extension ORDTWeft where SiteT == InstancedLUID, ValueT == ORDTClock
{
    public func included(_ operation: OperationID) -> Bool
    {
        if operation == NullOperationID
        {
            return true //useful default when generating causal blocks for non-causal atoms
        }
        if let clock = mapping[InstancedLUID.init(luid: operation.siteID, instanceID: operation.instanceID)]
        {
            if operation.logicalTimestamp <= clock
            {
                return true
            }
        }
        return false
    }
    
    public mutating func update(operation: OperationID)
    {
        if operation == NullOperationID { return }
        update(site: InstancedLUID.init(luid: operation.siteID, instanceID: operation.instanceID), value: operation.logicalTimestamp)
    }
}
extension ORDTWeft where SiteT == InstancedLUID, ValueT == ORDTSiteIndex
{
    public func included(_ operation: OperationID) -> Bool
    {
        if operation == NullOperationID
        {
            return true //useful default when generating causal blocks for non-causal atoms
        }
        if let index = mapping[InstancedLUID.init(luid: operation.siteID, instanceID: operation.instanceID)]
        {
            if operation.index <= index
            {
                return true
            }
        }
        return false
    }
    
    public mutating func update(operation: OperationID)
    {
        if operation == NullOperationID { return }
        update(site: InstancedLUID.init(luid: operation.siteID, instanceID: operation.instanceID), value: operation.index)
    }
}
