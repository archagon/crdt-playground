//
//  SiteMap.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2018-4-18.
//  Copyright © 2018 Alexei Baboulevitch. All rights reserved.
//

import Foundation

public struct SiteMap <SiteUUIDT: Hashable & Comparable & Zeroable> : ORDT, UsesGlobalLamport
{
    public struct Operation: OperationType
    {
        public struct ID: OperationIDType, CustomStringConvertible
        {
            public let uuid: SiteUUIDT
            public let logicalTimestamp: ORDTClock
            
            public init(uuid: SiteUUIDT, logicalTimestamp: ORDTClock)
            {
                self.uuid = uuid
                self.logicalTimestamp = logicalTimestamp
            }
            
            public static func ==(lhs: ID, rhs: ID) -> Bool
            {
                return lhs.uuid == rhs.uuid && lhs.logicalTimestamp == rhs.logicalTimestamp
            }
            
            public static func <(lhs: ID, rhs: ID) -> Bool
            {
                return (lhs.logicalTimestamp < rhs.logicalTimestamp ? true : lhs.logicalTimestamp > rhs.logicalTimestamp ? false : lhs.uuid < rhs.uuid)
            }

            public func hash(into hasher: inout Hasher)
            {
                hasher.combine(uuid)
                hasher.combine(logicalTimestamp)
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
    
    // TODO: remove these
    public init(from decoder: Decoder) throws { fatalError() }
    public func encode(to encoder: Encoder) throws { fatalError() }
    
    public typealias OperationT = Operation
    public typealias SiteIDT = SiteUUIDT
    public typealias AbsoluteTimestampWeft = ORDTWeft<SiteIDT, ORDTClock>
    public typealias AbsoluteIndexWeft = ORDTWeft<SiteIDT, ORDTSiteIndex>
    
    public var timeFunction: ORDTTimeFunction?
    
    // primary state
    // AB: don't read from this unless necessary, use `slice` instead; preserved whole in revisions
    private var _operations: [OperationT]
    
    // caches
    public private(set) var lamportClock: ORDTClock
    public private(set) var timestampWeft: AbsoluteTimestampWeft
    public private(set) var indexWeft: AbsoluteIndexWeft
    
    // data access
    private var slice: ArbitraryIndexSlice<OperationT>
    {
        get
        {
            return ArbitraryIndexSlice<OperationT>.init(self._operations, withValidIndices: nil)
        }
    }
    
    public init()
    {
        self._operations = []
        self.lamportClock = 0
        self.timestampWeft = AbsoluteTimestampWeft.init()
        self.indexWeft = AbsoluteIndexWeft.init()
    }

    public func uuidToLuidMap() -> [SiteUUIDT:LUID]
    {
        var dict: [SiteUUIDT:LUID] = [:]
        self.slice.enumerated().forEach
        {
            dict[$0.element.id.uuid] = LUID($0.offset + 1)
        }
        return dict
    }
    
    public func luidToUuidMap() -> [LUID:SiteUUIDT]
    {
        var dict: [LUID:SiteUUIDT] = [:]
        self.slice.enumerated().forEach
        {
            dict[LUID($0.offset + 1)] = $0.element.id.uuid
        }
        return dict
    }
    
    public func siteCount() -> Int
    {
        return self.slice.count
    }
    
    public func uuid(forLuid luid: LUID) -> SiteUUIDT?
    {
        if luid == NullSiteID
        {
            return nil
        }
        
        let index = Int(luid) - 1
        
        if index >= self.slice.count
        {
            return nil
        }
        
        return self.slice[index].id.uuid
    }
    
    // PERF: use binary search
    public func luid(forUuid uuid: SiteUUIDT) -> LUID?
    {
        for (i,key) in self.slice.enumerated()
        {
            if key.id.uuid == uuid
            {
                return LUID(i + 1)
            }
        }
        
        return nil
    }
    
    // PERF: use binary search
    public mutating func addUuid(_ uuid: SiteUUIDT) -> LUID
    {
        idAlreadyExists: do
        {
            for (i,key) in self.slice.enumerated()
            {
                if key.id.uuid == uuid
                {
                    //warning(uuid == SiteUUIDT.zero, "site already exists in mapping")
                    return LUID(i + 1)
                }
            }
        }
        
        addOperation: do
        {
            let lamportClock = max(self.timeFunction?() ?? self.lamportClock, self.lamportClock + 1)
            
            let id = Operation.ID.init(uuid: uuid, logicalTimestamp: lamportClock)
            let op = Operation.init(id: id)
            
            let index = self._operations.insertionIndexOf(elem: op, isOrderedBefore: SiteMap.order)
            
            // TODO: revision stuff, if needed -- avoid self.operations if possible
            self._operations.insert(op, at: index)
            
            updateCaches: do
            {
                self.timestampWeft.update(site: uuid, value: lamportClock)
                self.indexWeft.update(site: uuid, value: 0)
                self.lamportClock = lamportClock
            }
            
            return LUID(index + 1)
        }
    }
    
    public mutating func integrate(_ v: inout SiteMap)
    {
        let _ = integrateReturningFirstDiffIndex(&v)
    }
    
    /// Returns the first changed site index, after and including which, site indices in an ORDT have to be rewritten.
    /// `nil` means no edit or empty. `v` is not modified.
    // TODO: v slice or v operations?
    // TODO: use comparator func
    public mutating func integrateReturningFirstDiffIndex(_ v: inout SiteMap) -> Int?
    {
        var firstEdit: Int? = nil
        
        var i = 0
        var j = 0
        
        while j < v._operations.count
        {
            if i == self._operations.count
            {
                // v has more sites than us, keep adding until we get to the end
                self._operations.insert(v._operations[j], at: i)
                if firstEdit == nil { firstEdit = i }
                i += 1
                j += 1
            }
            else if self._operations[i].id > v._operations[j].id
            {
                // v has new data, integrate
                self._operations.insert(v._operations[j], at: i)
                if firstEdit == nil { firstEdit = i }
                i += 1
                j += 1
            }
            else if self._operations[i].id < v._operations[j].id
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
        
        updateCaches: do
        {
            self.lamportClock = max(self.lamportClock, v.lamportClock)
            self.indexWeft.update(weft: v.indexWeft)
            self.timestampWeft.update(weft: v.timestampWeft)
        }
        
        return firstEdit
    }
    
    // TODO: operations vs. revision?
    public func validate() throws -> Bool
    {
        var newTimestampWeft = TimestampWeftT()
        var newIndexWeft = IndexWeftT()
        var newLamport: Clock = 0
        
        validateSorted: do
        {
            for i in 0..<self.slice.count
            {
                if i < self.slice.count - 1
                {
                    let order = SiteMap.order(a1: self.slice[i], a2: self.slice[i + 1])
                    if !order
                    {
                        throw ValidationError.incorrectOperationOrder
                        //return false
                    }
                }
                
                newLamport = max(newLamport, Clock(self.slice[i].id.logicalTimestamp))
                newTimestampWeft.update(site: self.slice[i].id.uuid, value: self.slice[i].id.logicalTimestamp)
                newIndexWeft.update(site: self.slice[i].id.uuid, value: 0)
            }
        }
        
        validateCaches: do
        {
            if newTimestampWeft != self.timestampWeft
            {
                throw ValidationError.inconsistentWeft
                //return false
            }
            if newIndexWeft != self.indexWeft
            {
                throw ValidationError.inconsistentWeft
                //return false
            }
            if newLamport != self.lamportClock
            {
                throw ValidationError.inconsistentLamportTimestamp
                //return false
            }
            
            var calculatedLamport: ORDTClock = 0
            for site in self.timestampWeft.allSites()
            {
                calculatedLamport = max(self.timestampWeft.valueForSite(site: site) ?? 0, calculatedLamport)
            }
            if calculatedLamport != self.lamportClock
            {
                throw ValidationError.inconsistentWeft
                //return false
            }
            
            var calculatedLength: ORDTSiteIndex = 0
            for site in self.indexWeft.allSites()
            {
                calculatedLength += (self.indexWeft.valueForSite(site: site) ?? 0) + 1
            }
            if self.slice.count != calculatedLength
            {
                throw ValidationError.inconsistentWeft
                //return false
            }
            
            if self.timestampWeft.allSites().count != self.indexWeft.allSites().count
            {
                throw ValidationError.inconsistentWeft
                //return false
            }
        }
        
        return true
    }
    
    public func superset(_ v: inout SiteMap) -> Bool
    {
        return self.timestampWeft.isSuperset(of: v.timestampWeft)
    }

    public static func ==(lhs: SiteMap, rhs: SiteMap) -> Bool
    {
        return lhs.timestampWeft == rhs.timestampWeft
    }

    public func hash(into hasher: inout Hasher)
    {
        for op in self.slice
        {
            hasher.combine(op.id)
        }
    }

    private static func order(a1: OperationT, a2: OperationT) -> Bool
    {
        return (a1.id.logicalTimestamp < a2.id.logicalTimestamp ? true : a1.id.logicalTimestamp > a2.id.logicalTimestamp ? false : a1.id.uuid < a2.id.uuid)
    }
    
    // PERF: this should not use "integrate" but inout
    public static func indexMap(localSiteIndex: SiteMap, remoteSiteIndex: SiteMap) -> [LUID:LUID]
    {
        let oldSiteIndex = localSiteIndex
        var newSiteIndex = oldSiteIndex
        var remoteSiteIndexPointer = remoteSiteIndex

        let firstDifferentIndex = newSiteIndex.integrateReturningFirstDiffIndex(&remoteSiteIndexPointer)
        var remapMap: [LUID:LUID] = [:]
        if let index = firstDifferentIndex
        {
            let newMapping = newSiteIndex.uuidToLuidMap()
            for i in index..<oldSiteIndex.siteCount()
            {
                let oldSite = LUID(i + 1)
                let newSite = newMapping[oldSiteIndex.uuid(forLuid: oldSite)!]!
                remapMap[oldSite] = newSite
            }
        }

        assert(remapMap.values.count == Set(remapMap.values).count, "some sites mapped to identical sites")

        return remapMap
    }
}
extension SiteMap: CustomDebugStringConvertible
{
    public var debugDescription: String
    {
        get
        {
            var string = "["
            for i in 0..<self.slice.count
            {
                if i != 0
                {
                    string += ", "
                }
                string += "\(i):#\(self.slice[i].id.uuid.hashValue)"
            }
            string += "]"
            return string
        }
    }
}
// TODO: for later
extension SiteMap
{
    public func remapIndices(_ map: [LUID:LUID]) {}
    
    public func operations(withWeft weft: AbsoluteTimestampWeft?) -> ArbitraryIndexSlice<OperationT>
    {
        if weft == nil || weft == self.timestampWeft
        {
            return self.slice
        }
        
        assert(false)
        return ArbitraryIndexSlice.init([], withValidIndices: nil)
    }
    
    public func yarn(forSite site: SiteIDT, withWeft weft: AbsoluteTimestampWeft?) -> ArbitraryIndexSlice<OperationT>
    {
        if weft == nil || weft == self.timestampWeft
        {
            // PERF:
            for (i,v) in self._operations.enumerated()
            {
                if v.id.uuid == site
                {
                    return ArbitraryIndexSlice.init(self._operations, withValidIndices: [i..<(i+1)])
                }
            }
            
            return ArbitraryIndexSlice.init(self._operations, withValidIndices: [])
        }
        
        assert(false)
        return ArbitraryIndexSlice.init([], withValidIndices: nil)
    }
    
    public func revision(_ weft: AbsoluteTimestampWeft?) -> SiteMap
    {
        assert(false)
        return SiteMap.init()
    }
    
    public var baseline: AbsoluteTimestampWeft? { return nil }
    public func setBaseline(_ weft: AbsoluteTimestampWeft) throws
    {
        throw SetBaselineError.notSupported
    }
}

/// An ORDT can only change owners if a site map is present.
//public struct MappedORDT<ORDTT: ORDT, SiteMapT: SiteMap>: ORDT
//{
//}
