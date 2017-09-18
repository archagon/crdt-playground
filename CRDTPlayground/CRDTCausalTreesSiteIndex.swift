//
//  CRDTCausalTreesSiteIndex.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-9-18.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import Foundation

///////////////////////
// MARK: -
// MARK: - Site Index -
// MARK: -
///////////////////////

final class SiteIndex <SiteUUIDT: CausalTreeSiteUUIDT> : CvRDT, NSCopying, CustomDebugStringConvertible, ApproxSizeable
{
    struct SiteIndexKey: Comparable, Codable
    {
        let clock: Clock //assuming ~ clock sync, allows us to rewrite only last few ids at most, on average
        let id: SiteUUIDT
        
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
    
    init(mapping: inout ArrayType<SiteIndexKey>)
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
    init()
    {
        let _ = addSite(SiteUUIDT.zero, withClock: 0)
    }
    
    public func copy(with zone: NSZone? = nil) -> Any
    {
        let returnValue = SiteIndex<SiteUUIDT>()
        returnValue.mapping = self.mapping
        return returnValue
    }
    
    // Complexity: O(S)
    func siteMapping() -> [SiteUUIDT:SiteId]
    {
        var returnMap: [SiteUUIDT:SiteId] = [:]
        for i in 0..<mapping.count
        {
            returnMap[mapping[i].id] = SiteId(i)
        }
        return returnMap
    }
    
    // Complexity: O(1)
    func siteCount() -> Int
    {
        return mapping.count
    }
    
    // Complexity: O(1)
    func site(_ siteId: SiteId) -> SiteUUIDT?
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
        let newKey = SiteIndexKey(clock: clock, id: id)
        
        let index = mapping.index
        { (key: SiteIndexKey) -> Bool in
            key >= newKey
        }
        
        if let aIndex = index
        {
            if mapping[aIndex] == newKey
            {
                return SiteId(aIndex)
            }
            else
            {
                mapping.insert(newKey, at: aIndex)
                return SiteId(aIndex)
            }
        }
        else
        {
            mapping.append(newKey)
            return SiteId(SiteId(mapping.count - 1))
        }
    }
    
    func integrate(_ v: inout SiteIndex)
    {
        let _ = integrateReturningFirstDiffIndex(&v)
    }
    
    // returns first changed site index, after and including which, site indices in weave have to be rewritten; nil means no edit or empty
    // Complexity: O(S)
    func integrateReturningFirstDiffIndex(_ v: inout SiteIndex) -> Int?
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
    
    func validate() -> Bool
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
        
        return true
    }
    
    func superset(_ v: inout SiteIndex) -> Bool
    {
        if siteCount() < v.siteCount()
        {
            return false
        }
        
        let uuids = siteMapping()
        
        for i in 0..<v.mapping.count
        {
            if uuids[v.mapping[i].id] == nil
            {
                return false
            }
        }
        
        return true
    }
    
    var debugDescription: String
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
    
    func sizeInBytes() -> Int
    {
        return mapping.count * (MemoryLayout<SiteId>.size + MemoryLayout<UUID>.size)
    }
}
