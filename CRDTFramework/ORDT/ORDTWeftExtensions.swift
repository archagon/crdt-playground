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
extension ORDTClock: DefaultInitializable { public init() { self = 0 } }
extension ORDTClock: Zeroable { public static var zero: ORDTClock { return 0 } }
extension ORDTSiteIndex: DefaultInitializable { public init() { self = 0 } }
extension ORDTSiteIndex: Zeroable { public static var zero: ORDTSiteIndex { return 0 } }

public struct InstancedID <IDT: Comparable & Hashable>
{
    var id: IDT
    var instanceID: InstanceID
    
    public init(id: IDT, instanceID: InstanceID? = nil)
    {
        self.id = id
        self.instanceID = instanceID ?? 0
    }
}
extension InstancedID: Comparable
{
    public static func <(lhs: InstancedID, rhs: InstancedID) -> Bool
    {
        return (lhs.id < rhs.id ? true : lhs.id > rhs.id ? false : lhs.instanceID < rhs.instanceID)
    }
    
    public static func ==(lhs: InstancedID, rhs: InstancedID) -> Bool
    {
        return !(lhs < rhs) && !(lhs > rhs)
    }
    
}
extension InstancedID: Hashable
{
    public func hash(into hasher: inout Hasher)
    {
        hasher.combine(self.id)
        hasher.combine(self.instanceID)
    }
}
extension InstancedID: CustomStringConvertible, CustomDebugStringConvertible
{
    public var description: String
    {
        return "\(self.id)\(self.instanceID == 0 ? "" : ".\(self.instanceID)")"
    }
    
    public var debugDescription: String
    {
        return "\(self.id).\(self.instanceID)"
    }
}
extension InstancedID: ORDTIndexRemappable
{
    public mutating func remapIndices(_ map: [LUID:LUID]) {}
}
extension InstancedID where IDT == LUID
{
    public init(id: IDT, instanceID: InstanceID? = nil)
    {
        precondition(id != NullSiteID)
        self.init(uncheckedId: id, instanceID: instanceID ?? 0)
    }
    
    // AB: for generating NullInstancedLUID
    init(uncheckedId id: IDT, instanceID: InstanceID)
    {
        self.id = id
        self.instanceID = instanceID
    }
}
extension InstancedID where IDT == LUID
{
    public mutating func remapIndices(_ map: [LUID:LUID])
    {
        if let newSite = map[self.id]
        {
            self.id = newSite
        }
    }
}
extension InstancedID where IDT == LUID
{
    public init(integerLiteral value: LUID)
    {
        self.init(id: value)
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
    public mutating func remapIndices(_ map: [LUID:LUID])
    {
        var newMap: [SiteT:ValueT] = [:]
        
        for (k,v) in self.mapping
        {
            if let newSite = map[k.id]
            {
                newMap[InstancedLUID.init(id: newSite, instanceID: k.instanceID)] = v
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
        if let clock = mapping[InstancedLUID.init(id: operation.siteID, instanceID: operation.instanceID)]
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
        update(site: InstancedLUID.init(id: operation.siteID, instanceID: operation.instanceID), value: operation.logicalTimestamp)
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
        if let index = mapping[InstancedLUID.init(id: operation.siteID, instanceID: operation.instanceID)]
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
        update(site: InstancedLUID.init(id: operation.siteID, instanceID: operation.instanceID), value: operation.index)
    }
}
