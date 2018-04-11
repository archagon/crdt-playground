//
//  ORDT.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2018-4-9.
//  Copyright © 2018 Alexei Baboulevitch. All rights reserved.
//

import Foundation

/// A self-contained ORDT data structure.
public protocol ORDT: CvRDT, ApproxSizeable, IndexRemappable
{
    var lamportClock: Clock { get }
    
    // TODO: maybe setRevision would be better?
    func operations(_ weft: Int) -> ArraySlice<Int>
    
    mutating func setBaseline(_ weft: Int) throws
    var baseline: Int? { get }
}

/// An ORDT by itself doesn't have access to global properties such as the full Lamport clock of the document,
/// or to mappings between local site IDs and UUIDs. This delegate can provide that information.
public protocol ORDTDelegate
{
    var delegateLamportClock: Int { get }
    
    func LUIDForUUID(_ luid: SiteId)
    func UUIDForLUID(_ uuid: UUID)
}

/// When multiple ORDTs are processed together, baseline and operation commands no longer make sense. Therefore, it's
/// sensible to have a container ORDT that only exposes the methods that make sense in aggregate.
public protocol ORDTContainer: CvRDT, ApproxSizeable, IndexRemappable
{
    var lamportClock: Clock { get }
}

/// We can't have vararg generics, so individual declarations for tuples will have to do. Boilerplate.
public protocol ORDTTuple: ORDTContainer {}

public struct ORDTTuple2 <O1: ORDT, O2: ORDT> : ORDTTuple
{
    public var ordt1: O1
    public var ordt2: O2
    
    public var lamportClock: Clock
    {
        return max(self.ordt1.lamportClock, self.ordt2.lamportClock)
    }
    
    init(ordt1: O1, ordt2: O2)
    {
        self.ordt1 = ordt1
        self.ordt2 = ordt2
    }
    
    public mutating func integrate(_ v: inout ORDTTuple2<O1,O2>)
    {
        self.ordt1.integrate(&v.ordt1)
        self.ordt2.integrate(&v.ordt2)
    }
    
    public func superset(_ v: inout ORDTTuple2<O1,O2>) -> Bool
    {
        return
            self.ordt1.superset(&v.ordt1) &&
            self.ordt2.superset(&v.ordt2)
    }
    
    public func validate() throws -> Bool
    {
        let v1 = try self.ordt1.validate()
        let v2 = try self.ordt2.validate()
        return v1 && v2
    }
    
    public mutating func remapIndices(_ map: [SiteId:SiteId])
    {
        self.ordt1.remapIndices(map)
        self.ordt2.remapIndices(map)
    }
    
    public func sizeInBytes() -> Int
    {
        return
            self.ordt1.sizeInBytes() +
            self.ordt2.sizeInBytes()
    }
    
    public var hashValue: Int
    {
        return self.ordt1.hashValue ^ self.ordt2.hashValue
    }
    
    public static func ==(lhs: ORDTTuple2<O1,O2>, rhs: ORDTTuple2<O1,O2>) -> Bool
    {
        return lhs.ordt1 == rhs.ordt1 && lhs.ordt2 == rhs.ordt2
    }
}

/// A document comprised of one or more ORDTs, together with a site map.
public struct ORDTDocument <S: CausalTreeSiteUUIDT, T: ORDTContainer> : CvRDT, ApproxSizeable
{
    public private(set) var ordts: T
    public private(set) var siteMap: SiteIndex<S>
    
    public init()
    {
    }
    
    public mutating func integrate(_ v: inout ORDTDocument<S,T>)
    {
        let localIndexMap: [SiteId:SiteId]
        let remoteIndexMap: [SiteId:SiteId]
        
        generateIndexMaps: do
        {
            localIndexMap = SiteIndex<S>.indexMap(localSiteIndex: self.siteMap, remoteSiteIndex: v.siteMap)
            remoteIndexMap = SiteIndex<S>.indexMap(localSiteIndex: v.siteMap, remoteSiteIndex: self.siteMap) //to account for concurrently added sites
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
    
    var lamportClock: Clock
    {
        // an approximation of hybrid logical clock
        return max(self.ordts.lamportClock, Clock(Date().timeIntervalSince1970))
    }
    
    func copy(with zone: NSZone? = nil) -> Any
    {
        return NSObject()
    }
    
    public var hashValue: Int
    {
        return self.ordts.hashValue ^ self.siteMap.hashValue
    }
    
    public static func ==(lhs: ORDTDocument<S,T>, rhs: ORDTDocument<S,T>) -> Bool
    {
        return false
    }
}
