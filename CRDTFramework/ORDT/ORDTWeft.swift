//
//  ORDTWeft.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2018-4-17.
//  Copyright © 2018 Alexei Baboulevitch. All rights reserved.
//

import Foundation

public protocol ORDTWeftType: Equatable, CustomStringConvertible, ORDTIndexRemappable
{
    associatedtype SiteT: Hashable, Comparable
    associatedtype ValueT: Hashable, Comparable, Zeroable
    
    mutating func update(weft: Self)
    mutating func update(site: SiteT, value: ValueT)
    
    func valueForSite(site: SiteT) -> ValueT?
    func isSuperset(of: Self) -> Bool
    func allSites() -> [SiteT]
    
    init()
    init(withMapping: [SiteT:ValueT])
}

public struct ORDTWeft <SiteT: Hashable & Comparable, ValueT: Hashable & Comparable & Zeroable> : ORDTWeftType
{
    public internal(set) var mapping: [SiteT:ValueT] = [:]
    
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
    public func hash(into hasher: inout Hasher)
    {
        // TODO: is this hashvalue correct?
        for (_,pair) in mapping.enumerated()
        {
            hasher.combine(pair.key)
            hasher.combine(pair.value)
        }
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
extension ORDTWeft: ORDTIndexRemappable
{
    public mutating func remapIndices(_ map: [LUID:LUID]) {}
}
