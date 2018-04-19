//
//  ORDTWeft.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2018-4-17.
//  Copyright © 2018 Alexei Baboulevitch. All rights reserved.
//

import Foundation

public protocol ORDTWeftType: Equatable, CustomStringConvertible, IndexRemappable
{
    associatedtype SiteT: DefaultInitializable, CustomStringConvertible, Hashable, Zeroable, Comparable
    associatedtype ValueT: Hashable, Comparable, Zeroable
    
    mutating func update(weft: Self)
    mutating func update(site: SiteT, value: ValueT)
    
    func valueForSite(site: SiteT) -> ValueT?
    func isSuperset(of: Self) -> Bool
    func allSites() -> [SiteT]
    
    init()
    init(withMapping: [SiteT:ValueT])
}

public struct ORDTWeft
    <SiteT: DefaultInitializable & CustomStringConvertible & Hashable & Zeroable & Comparable, ValueT: Hashable & Comparable & Zeroable>
    : ORDTWeftType
{
    public var mapping: [SiteT:ValueT] = [:]
    
    public init() {}
    
    public init(withMapping mapping: [SiteT:ValueT])
    {
        self.mapping = mapping
    }
    
    public mutating func update(weft: ORDTWeft)
    {
        for (site, value) in weft.mapping
        {
            update(site: site, value: value)
        }
    }
    
    public mutating func update(site: SiteT, value: ValueT)
    {
        mapping[site] = max(mapping[site] ?? ValueT.zero, value)
    }
    
    public func valueForSite(site: SiteT) -> ValueT?
    {
        return mapping[site]
    }
    
    public func isSuperset(of other: ORDTWeft) -> Bool
    {
        for (id,clock) in other.mapping
        {
            guard let myClock = self.mapping[id] else
            {
                return false
            }
            
            if !(myClock >= clock)
            {
                return false
            }
        }
        
        return true
    }
    
    public func allSites() -> [SiteT]
    {
        return Array(self.mapping.keys)
    }
}
extension ORDTWeft: Equatable
{
    public static func ==(lhs: ORDTWeft, rhs: ORDTWeft) -> Bool
    {
        if lhs.mapping.count != rhs.mapping.count
        {
            return false
        }
        
        for (k,_) in lhs.mapping
        {
            if lhs.mapping[k] != rhs.mapping[k]
            {
                return false
            }
        }
        
        return true
    }
}
extension ORDTWeft: Hashable
{
    public var hashValue: Int
    {
        var hash = 0
        
        // TODO: is this hashvalue correct?
        for (_,pair) in mapping.enumerated()
        {
            hash ^= pair.key.hashValue
            hash ^= pair.value.hashValue
        }
        
        return hash
    }
}
extension ORDTWeft: CustomStringConvertible
{
    public var description: String
    {
        get
        {
            var string = "["
            let sites = Array<SiteT>(mapping.keys).sorted()
            for (i,site) in sites.enumerated()
            {
                if i != 0
                {
                    string += ", "
                }
                string += "\(site):\(mapping[site]!)"
            }
            string += "]"
            return string
        }
    }
}
extension ORDTWeft: IndexRemappable
{
    public mutating func remapIndices(_ map: [SiteId:SiteId]) {}
}
extension ORDTWeft where SiteT == LUID
{
    mutating func update(site: SiteT, value: ValueT)
    {
        if site == NullSiteID { return }
        mapping[site] = max(mapping[site] ?? ValueT.zero, value)
    }
}
extension ORDTWeft where SiteT == LUID
{
    public mutating func remapIndices(_ map: [SiteId:SiteId])
    {
        var newMap: [SiteT:ValueT] = [:]
        
        for (k,v) in self.mapping
        {
            if let newSite = map[SiteId(k)]
            {
                newMap[LUID(newSite)] = v
            }
            else
            {
                newMap[k] = v
            }
        }
        
        self.mapping = newMap
    }
}
extension ORDTWeft where SiteT == LUID, ValueT == ORDTClock
{
    public func included(_ operation: OperationID) -> Bool
    {
        if operation == NullOperationID
        {
            return true //useful default when generating causal blocks for non-causal atoms
        }
        if let clock = mapping[operation.siteID]
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
        update(site: operation.siteID, value: operation.logicalTimestamp)
    }
}
extension ORDTWeft where SiteT == LUID, ValueT == ORDTSiteIndex
{
    public func included(_ operation: OperationID) -> Bool
    {
        if operation == NullOperationID
        {
            return true //useful default when generating causal blocks for non-causal atoms
        }
        if let index = mapping[operation.siteID]
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
        update(site: operation.siteID, value: operation.index)
    }
}
