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
    
    mutating func update(weft: Self)
    mutating func update(site: SiteT, value: Clock)
    
    func valueForSite(site: SiteT) -> Clock?
    func isSuperset(of: Self) -> Bool
    
    init()
    init(withMapping: [SiteT:Clock])
}

public struct ORDTWeft <SiteT: DefaultInitializable & CustomStringConvertible & Hashable & Zeroable & Comparable> : ORDTWeftType
{
    public var mapping: [SiteT:Clock] = [:]
    
    public init() {}
    
    public init(withMapping mapping: [SiteT:Clock])
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
    
    public mutating func update(site: SiteT, value: Clock)
    {
        mapping[site] = max(mapping[site] ?? NullClock, value)
    }
    
    public func valueForSite(site: SiteT) -> Clock?
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
    public mutating func remapIndices(_ map: [SiteId : SiteId]) {}
}
extension ORDTWeft where SiteT == SiteId
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
    
    mutating func update(site: SiteId, value: Clock)
    {
        if site == NullSiteID { return }
        mapping[site] = max(mapping[site] ?? NullClock, value)
    }
    
    public mutating func update(operation: OperationID) {
        if operation == NullOperationID { return }
        update(site: operation.siteID, value: operation.logicalTimestamp)
    }
}
extension ORDTWeft where SiteT == SiteId
{
    public mutating func remapIndices(_ map: [SiteId:SiteId])
    {
        var newMap: [SiteT:Clock] = [:]
        
        for (k,v) in self.mapping
        {
            newMap[map[k] ?? k] = v
        }
        
        self.mapping = newMap
    }
}
