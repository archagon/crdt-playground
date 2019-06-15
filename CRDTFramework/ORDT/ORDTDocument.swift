//
//  ORDT.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2018-4-9.
//  Copyright © 2018 Alexei Baboulevitch. All rights reserved.
//

import Foundation

/// A document comprised of one or more ORDTs, together with a site map.
public struct ORDTDocument <S: CausalTreeSiteUUIDT, T: CvRDT & ORDTIndexRemappable & ApproxSizeable> : CvRDT, ApproxSizeable
{
    public private(set) var ordts: T
    public private(set) var siteMap: SiteMap<S>
    
    // TODO: from data
    public init(ordts: T, siteMap: SiteMap<S>)
    {
        self.ordts = ordts
        self.siteMap = siteMap
    }
    
    public mutating func integrate(_ v: inout ORDTDocument<S,T>)
    {
        let localIndexMap: [LUID:LUID]
        let remoteIndexMap: [LUID:LUID]
        
        generateIndexMaps: do
        {
            localIndexMap = SiteMap<S>.indexMap(localSiteIndex: self.siteMap, remoteSiteIndex: v.siteMap)
            remoteIndexMap = SiteMap<S>.indexMap(localSiteIndex: v.siteMap, remoteSiteIndex: self.siteMap) //to account for concurrently added sites
        }
        
        remapIndices: do
        {
            self.ordts.remapIndices(localIndexMap)
            v.ordts.remapIndices(remoteIndexMap)
        }
        
        merge: do
        {
            self.siteMap.integrate(&v.siteMap)
            self.ordts.integrate(&v.ordts) //possible since both now share the same siteId mapping
        }
    }
    
    public func superset(_ v: inout ORDTDocument<S,T>) -> Bool
    {
        return self.ordts.superset(&v.ordts) && self.siteMap.superset(&v.siteMap)
    }
    
    public func validate() throws -> Bool
    {
        let v1 = try self.ordts.validate()
        let v2 = try self.siteMap.validate()
        return v1 && v2
    }
    
    public func sizeInBytes() -> Int
    {
        return self.ordts.sizeInBytes() + self.siteMap.sizeInBytes()
    }
    
    //var lamportClock: Clock
    //{
    //    // an approximation of hybrid logical clock
    //    return max(self.ordts.lamportClock, Clock(Date().timeIntervalSince1970))
    //}
    
    func copy(with zone: NSZone? = nil) -> Any
    {
        return NSObject()
    }

    public func hash(into hasher: inout Hasher)
    {
        hasher.combine(self.ordts)
        hasher.combine(self.siteMap)
    }

    public static func ==(lhs: ORDTDocument<S,T>, rhs: ORDTDocument<S,T>) -> Bool
    {
        return false
    }
}
extension ORDTDocument where T: ORDTContainer
{
    // TODO: revision/baseline stuff goes here; special treatment for when every CRDT is an ORDT
}

func test()
{
    let owner = InstancedLUID.init(id: 1)
    
    let siteMap = SiteMap<UUID>()
    let cursorMap = ORDTMap<LUID, OperationID>(withOwner: owner)
    let _ = ORDTCausalTree<StringCharacterAtom>(owner: owner)
    let _ = ORDTTuple2.init(cursorMap, siteMap)
}
