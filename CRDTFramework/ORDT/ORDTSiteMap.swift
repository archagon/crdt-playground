//
//  SiteMap.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2018-4-18.
//  Copyright © 2018 Alexei Baboulevitch. All rights reserved.
//

import Foundation

public final class SiteMap <SiteUUIDT: CausalTreeSiteUUIDT> : ORDT
{
    // NEXT: local protocol, weft uuid type, remap indices
    
    public typealias OperationT = Operation
    public typealias SiteIDT = InstancedID<SiteUUIDT>
    public typealias AbsoluteTimestampWeft = ORDTWeft<SiteIDT, ORDTClock>
    public typealias AbsoluteIndexWeft = ORDTWeft<SiteIDT, ORDTSiteIndex>
    
    public func remapIndices(_ map: [SiteId:SiteId]) {}
    
    public var lamportClock: ORDTClock = 0

    public func operations(withWeft: AbsoluteTimestampWeft?) -> ArbitraryIndexSlice<OperationT>
    {
        return ArbitraryIndexSlice.init([], withValidIndices: nil)
    }
    
    public func yarn(forSite: SiteIDT, withWeft: AbsoluteTimestampWeft?) -> ArbitraryIndexSlice<OperationT>
    {
        return ArbitraryIndexSlice.init([], withValidIndices: nil)
    }
    
    public func revision(_ weft: AbsoluteTimestampWeft?) -> SiteMap
    {
        return SiteMap.init()
    }
    
    public var baseline: AbsoluteTimestampWeft? { return nil }
    public func setBaseline(_ weft: AbsoluteTimestampWeft) throws
    {
        throw SetBaselineError.notSupported
    }
    
    public var timestampWeft: AbsoluteTimestampWeft { return AbsoluteTimestampWeft() }
    public var indexWeft: AbsoluteIndexWeft { return AbsoluteIndexWeft() }
    
    public struct Operation: OperationType
    {
        public struct ID: OperationIDType, CustomStringConvertible
        {
            public let uuid: SiteUUIDT
            public let logicalTimestamp: ORDTClock
            
            public static func ==(lhs: ID, rhs: ID) -> Bool
            {
                return lhs.uuid == rhs.uuid && lhs.logicalTimestamp == rhs.logicalTimestamp
            }
            
            public static func <(lhs: ID, rhs: ID) -> Bool
            {
                return (lhs.logicalTimestamp < rhs.logicalTimestamp ? true : lhs.logicalTimestamp > rhs.logicalTimestamp ? false : lhs.uuid < rhs.uuid)
            }
            
            public var hashValue: Int
            {
                return self.uuid.hashValue ^ self.logicalTimestamp.hashValue
            }

            public var description: String
            {
                get
                {
                    return "[\(self.logicalTimestamp):\(self.uuid)]"
                }
            }
        }
        
        /// A placeholder, 0-size struct, since this operation doesn't actually need a value.
        public struct Empty {}
        
        public let id: ID
        public let value: Empty
        
        public init(id: ID)
        {
            self.init(id: id, value: Empty())
        }
        
        public init(id: ID, value: Empty)
        {
            self.id = id
            self.value = value
        }
    }
    
    public struct SiteIndexKey: Comparable, Codable
    {
        public let clock: Clock //assuming ~ clock sync, allows us to rewrite only last few ids at most, on average
        public let id: SiteUUIDT
        
        // PERF: is comparing UUID strings quick enough?
        public static func <(lhs: SiteIndexKey, rhs: SiteIndexKey) -> Bool
        {
            return (lhs.clock == rhs.clock ? lhs.id < rhs.id : lhs.clock < rhs.clock)
        }
        public static func <=(lhs: SiteIndexKey, rhs: SiteIndexKey) -> Bool
        {
            return (lhs.clock == rhs.clock ? lhs.id <= rhs.id : lhs.clock <= rhs.clock)
        }
        public static func >=(lhs: SiteIndexKey, rhs: SiteIndexKey) -> Bool
        {
            return (lhs.clock == rhs.clock ? lhs.id >= rhs.id : lhs.clock >= rhs.clock)
        }
        public static func >(lhs: SiteIndexKey, rhs: SiteIndexKey) -> Bool
        {
            return (lhs.clock == rhs.clock ? lhs.id > rhs.id : lhs.clock > rhs.clock)
        }
        public static func ==(lhs: SiteIndexKey, rhs: SiteIndexKey) -> Bool
        {
            return lhs.id == rhs.id && lhs.clock == rhs.clock
        }
    }
    
    // we assume this is always sorted in lexicographic order -- first by clock, then by UUID
    private var mapping: ArrayType<SiteIndexKey> = []
    
    public init(mapping: inout ArrayType<SiteIndexKey>)
    {
        assert({
            let sortedMapping = mapping.sorted()
            var allMatch = true
            for i in 0..<mapping.count
            {
                if mapping[i] != sortedMapping[i]
                {
                    allMatch = false
                    break
                }
            }
            return allMatch
        }(), "mapping not sorted")
        assert(mapping[0] == SiteIndexKey(clock: 0, id: SiteUUIDT.zero), "mapping does not have control site")
        self.mapping = mapping
    }
    
    // starting from scratch
    public init()
    {
        let _ = addSite(SiteUUIDT.zero, withClock: 0)
    }
    
    public func copy(with zone: NSZone? = nil) -> Any
    {
        let returnValue = SiteMap<SiteUUIDT>()
        returnValue.mapping = self.mapping
        return returnValue
    }
    
    // Complexity: O(S)
    public func allSites() -> [SiteId]
    {
        var sites = [SiteId]()
        for i in 0..<mapping.count
        {
            sites.append(SiteId(i))
        }
        return sites
    }
    
    // Complexity: O(S)
    public func siteMapping() -> [SiteUUIDT:SiteId]
    {
        var returnMap: [SiteUUIDT:SiteId] = [:]
        for i in 0..<mapping.count
        {
            returnMap[mapping[i].id] = SiteId(i)
        }
        return returnMap
    }
    
    // Complexity: O(1)
    public func siteCount() -> Int
    {
        return mapping.count
    }
    
    // Complexity: O(1)
    public func site(_ siteId: SiteId) -> SiteUUIDT?
    {
        if siteId >= self.mapping.count
        {
            return nil
        }
        return self.mapping[Int(siteId)].id
    }
    
    // PERF: use binary search
    // Complexity: O(S)
    func addSite(_ id: SiteUUIDT, withClock clock: Clock) -> SiteId
    {
        for (i,key) in mapping.enumerated()
        {
            if key.id == id
            {
                warning(id == SiteUUIDT.zero, "site already exists in mapping")
                return SiteId(i)
            }
        }
        
        let newKey = SiteIndexKey(clock: clock, id: id)
        
        let index = mapping.index
        { (key: SiteIndexKey) -> Bool in
            key >= newKey
        }
        
        if let aIndex = index
        {
            mapping.insert(newKey, at: aIndex)
            return SiteId(aIndex)
        }
        else
        {
            mapping.append(newKey)
            return SiteId(SiteId(mapping.count - 1))
        }
    }
    
    public func integrate(_ v: inout SiteMap)
    {
        let _ = integrateReturningFirstDiffIndex(&v)
    }
    
    // returns first changed site index, after and including which, site indices in weave have to be rewritten;
    // nil means no edit or empty, and v is not modified
    // Complexity: O(S)
    public func integrateReturningFirstDiffIndex(_ v: inout SiteMap) -> Int?
    {
        var firstEdit: Int? = nil
        
        var i = 0
        var j = 0
        
        while j < v.mapping.count
        {
            if i == self.mapping.count
            {
                // v has more sites than us, keep adding until we get to the end
                self.mapping.insert(v.mapping[j], at: i)
                if firstEdit == nil { firstEdit = i }
                i += 1
                j += 1
            }
            else if self.mapping[i] > v.mapping[j]
            {
                // v has new data, integrate
                self.mapping.insert(v.mapping[j], at: i)
                if firstEdit == nil { firstEdit = i }
                i += 1
                j += 1
            }
            else if self.mapping[i] < v.mapping[j]
            {
                // we have newer data, skip
                i += 1
            }
            else
            {
                // data is the same, all is well
                i += 1
                j += 1
            }
        }
        
        return firstEdit
    }
    
    public func validate() -> Bool
    {
        for i in 0..<mapping.count
        {
            if i > 0
            {
                if !(mapping[i-1] < mapping[i])
                {
                    return false
                }
            }
        }
        
        let allSites = mapping.map { $0.id }
        let allSitesSet = Set(allSites)
        
        if allSites.count != allSitesSet.count
        {
            // duplicate entries
            return false
        }
        
        return true
    }
    
    public func superset(_ v: inout SiteMap) -> Bool
    {
        assert(false, "don't compare site indices directly -- compare through the top-level CRDT")
        return false
    }
    
    public var debugDescription: String
    {
        get
        {
            var string = "["
            for i in 0..<mapping.count
            {
                if i != 0
                {
                    string += ", "
                }
                string += "\(i):#\(mapping[i].id.hashValue)"
            }
            string += "]"
            return string
        }
    }
    
    public static func ==(lhs: SiteMap, rhs: SiteMap) -> Bool
    {
        return lhs.mapping.elementsEqual(rhs.mapping)
    }
    
    public var hashValue: Int
    {
        var hash: Int = 0
     
        for (i,v) in mapping.enumerated()
        {
            if i == 0
            {
                hash = v.id.hashValue
            }
            else
            {
                hash ^= v.id.hashValue
            }
        }
        
        return hash
    }
    
    private static func order(a1: OperationT, a2: OperationT) -> Bool
    {
        return (a1.id.logicalTimestamp < a2.id.logicalTimestamp ? true : a1.id.logicalTimestamp > a2.id.logicalTimestamp ? false : a1.id.uuid < a2.id.uuid)
    }
    
    // an incoming causal tree might have added sites, and our site ids are distributed in lexicographic-ish order,
    // so we may need to remap some site ids if the orders no longer line up; neither site index is mutated
    static func indexMap(localSiteIndex: SiteMap, remoteSiteIndex: SiteMap) -> [SiteId:SiteId]
    {
        let oldSiteIndex = localSiteIndex
        let newSiteIndex = localSiteIndex.copy() as! SiteMap
        var remoteSiteIndexPointer = remoteSiteIndex
        
        let firstDifferentIndex = newSiteIndex.integrateReturningFirstDiffIndex(&remoteSiteIndexPointer)
        var remapMap: [SiteId:SiteId] = [:]
        if let index = firstDifferentIndex
        {
            let newMapping = newSiteIndex.siteMapping()
            for i in index..<oldSiteIndex.siteCount()
            {
                let oldSite = SiteId(i)
                let newSite = newMapping[oldSiteIndex.site(oldSite)!]
                remapMap[oldSite] = newSite
            }
        }
        
        assert(remapMap.values.count == Set(remapMap.values).count, "some sites mapped to identical sites")
        
        return remapMap
    }
}

/// An ORDT can only change owners if a site map is present.
//public struct MappedORDT<ORDTT: ORDT, SiteMapT: SiteMap>: ORDT
//{
//}

