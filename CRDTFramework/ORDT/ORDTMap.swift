//
//  CRDTMap.swift
//  CloudKitRealTimeCollabTest
//
//  Created by Alexei Baboulevitch on 2017-10-27.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import Foundation

// TODO: base class generic ORDT w/weft, lamport, maybe op array, revision, comparator stub, etc. ("frame")
// TODO: copy needs to change owner
//          * malloc a UUID with uniqueReference etc. stuff?
//          * what about situations where original obj is not actually mutated?
//          * what about using cloudkit uuid?
//          * what about adding uuid to sitemap?
//          * thought: don't generate uuid until mutating method is called
// TODO: shared lamport timestamps: a) different owners == bigger site maps, b) same owners == same source of monotonicity
//          * e.g., don't want to get into a situation where two ORDTs are updated with parallel Lamports, since
//            a Lamport weft will capture a different snapshot depending on the merge
//          * hmm, still won't fix O1-50 / O2-51 / O1-52 / O2-53; O2 weft 51 would not capture 50; also wrong index
//          * maybe: different objects can use single monotonicity source, but same objects have to change owner? enforce?
// TODO: copy-on-write, inout
// TODO: structs vs. classes & the site map; independent objects vs. data layer and everything in between
//          * site map lives separately from ordtdocument? then delegate manages site mapping, indices, etc.?
//          * all site mapping stuff as separate protocol? UUID as generic? SiteId phased out?

/// A simple LWW map.
public struct ORDTMap <KeyT: Comparable & Hashable, ValueT> : ORDT, UsesGlobalLamport
{
    // TODO: remove these
    public init(from decoder: Decoder) throws { fatalError() }
    public func encode(to encoder: Encoder) throws { fatalError() }
    
    public typealias OperationT = Operation<PairValue<KeyT, ValueT>>
    
    weak public var lamportDelegate: ORDTGlobalLamportDelegate?
    
    // primary state
    // AB: don't read from this unless necessary, use `slice` instead; preserved whole in revisions
    private var _operations: [OperationT]
    
    // caches
    public private(set) var lamportClock: ORDTClock
    public private(set) var timestampWeft: ORDTLocalTimestampWeft
    public private(set) var indexWeft: ORDTLocalIndexWeft
    
    // these are merely convenience variables and do not affect hashes, etc.
    public private(set) var owner: InstancedLUID

    // data access
    private var isRevision: Bool { return _revisionSlice != nil }
    private let _revisionSlice: ArbitraryIndexSlice<OperationT>?
    private var slice: ArbitraryIndexSlice<OperationT>
    {
        get
        {
            if let slice = _revisionSlice
            {
                return slice
            }
            else
            {
                return ArbitraryIndexSlice<OperationT>.init(self._operations, withValidIndices: nil)
            }
        }
    }
    
    public init(withOwner owner: InstancedLUID, reservingCapacity capacity: Int? = nil)
    {
        self._operations = []
        if let capacity = capacity { self._operations.reserveCapacity(capacity) }
        self.owner = owner
        self.timestampWeft = ORDTLocalTimestampWeft()
        self.indexWeft = ORDTLocalIndexWeft()
        self.lamportClock = 0
        self._revisionSlice = nil
    }
    
    // AB: separate init method instead of doing everything in `revision` so that we can set `_revisionSlice`
    private init(copyFromMap map: ORDTMap, withRevisionWeft weft: ORDTLocalTimestampWeft)
    {
        let slice = map.operations(withWeft: weft)
        self.owner = map.owner
        self._operations = map._operations
        self.timestampWeft = weft
        self.lamportClock = slice.reduce(0) { (result, a) -> ORDTClock in max(result, a.id.logicalTimestamp) }
        self._revisionSlice = slice
        
        // PERF: can we do this without O(n)?
        initIndexWeft: do
        {
            var indexWeft = ORDTLocalIndexWeft()
            slice.forEach { indexWeft.update(operation: $0.id) }
            self.indexWeft = indexWeft
        }
    }
    
    public func revision(_ weft: ORDTLocalTimestampWeft?) -> ORDTMap
    {
        if weft == nil || weft == self.timestampWeft
        {
            return self
        }
        
        return ORDTMap.init(copyFromMap: self, withRevisionWeft: weft!)
    }
    
    mutating public func changeOwner(_ owner: InstancedLUID)
    {
        self.owner = owner
    }
    
    mutating public func setValue(_ value: ValueT, forKey key: KeyT)
    {
        if self.isRevision
        {
            assert(false, "can't edit ORDT revision")
            return
        }
        
        let lamportClock = (self.lamportDelegate?.delegateLamportClock ?? self.lamportClock) + 1
        let index = (self.indexWeft.valueForSite(site: self.owner) != nil ? self.indexWeft.valueForSite(site: self.owner)! + 1 : 0)
        
        let id = OperationID.init(logicalTimestamp: ORDTClock(lamportClock), index: index, siteID: self.owner.luid, instanceID: owner.instanceID)
        let op = OperationT.init(id: id, value: PairValue(key: key, value: value))
        
        updateData: do
        {
            let index = self._operations.insertionIndexOf(elem: op, isOrderedBefore: ORDTMap.order)
            self._operations.insert(op, at: index)
        }
        
        updateCaches: do
        {
            self.timestampWeft.update(operation: id)
            self.indexWeft.update(operation: id)
            self.lamportClock = lamportClock
        }
    }
    
    // TODO: PERF: binary search
    public func value(forKey key: KeyT) -> ValueT?
    {
        var lastOp: OperationT?
        for op in self.slice
        {
            if op.value.key == key
            {
                lastOp = op
            }
        }
        return lastOp?.value.value
    }
    
    mutating public func integrate(_ v: inout ORDTMap)
    {
        if self.isRevision
        {
            assert(false, "can't edit ORDT revision")
            return
        }
        
        var newOperations: [OperationT] = []
        var newTimestampWeft = ORDTLocalTimestampWeft()
        var newIndexWeft = ORDTLocalIndexWeft()
        var newLamport: ORDTClock = 0
        
        mergeSort: do
        {
            var i = 0
            var j = 0
            
            while i < self._operations.count || j < v._operations.count
            {
                let a = (i < self._operations.count ? self._operations[i] : nil)
                let b = (j < v._operations.count ? v._operations[j] : nil)
                
                let aBeforeB = (a == nil ? false : b == nil || ORDTMap.order(a1: a!, a2: b!))
                
                if aBeforeB
                {
                    newOperations.append(a!)
                    newTimestampWeft.update(operation: a!.id)
                    newIndexWeft.update(operation: a!.id)
                    newLamport = max(newLamport, a!.id.logicalTimestamp)
                    i += 1
                }
                else
                {
                    newOperations.append(b!)
                    newTimestampWeft.update(operation: b!.id)
                    newIndexWeft.update(operation: b!.id)
                    newLamport = max(newLamport, b!.id.logicalTimestamp)
                    j += 1
                }
            }
        }

        updateData: do
        {
            self._operations = newOperations
        }
        
        updateCaches: do
        {
            self.timestampWeft = newTimestampWeft
            self.indexWeft = newIndexWeft
            self.lamportClock = newLamport
        }
    }
    
    public func superset(_ v: inout ORDTMap) -> Bool
    {
        return self.timestampWeft.isSuperset(of: v.timestampWeft)
    }
    
    public func validate() throws -> Bool
    {
        var newTimestampWeft = ORDTLocalTimestampWeft()
        var newIndexWeft = ORDTLocalIndexWeft()
        var newLamport: Clock = 0
        
        validateSorted: do
        {
            for i in 0..<self.slice.count
            {
                if i < self.slice.count - 1
                {
                    let order = ORDTMap.order(a1: self.slice[i], a2: self.slice[i + 1])
                    if !order
                    {
                        throw ValidationError.incorrectOperationOrder
                        //return false
                    }
                }
                
                newLamport = max(newLamport, Clock(self.slice[i].id.logicalTimestamp))
                newTimestampWeft.update(operation: self.slice[i].id)
                newIndexWeft.update(operation: self.slice[i].id)
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
    
    public static func ==(lhs: ORDTMap, rhs: ORDTMap) -> Bool
    {
        return lhs.timestampWeft == rhs.timestampWeft
    }
    
    public var hashValue: Int
    {
        var hash: Int = 0

        for op in self.slice
        {
            hash ^= op.id.hashValue
        }

        return hash
    }
    
    mutating public func remapIndices(_ map: [SiteId:SiteId])
    {
        if self.isRevision
        {
            assert(false, "can't edit ORDT revision")
            return
        }
        
        for i in 0..<self._operations.count
        {
            self._operations[i].remapIndices(map)
        }
        
        self.timestampWeft.remapIndices(map)
        self.indexWeft.remapIndices(map)
        self.owner.remapIndices(map)
    }
    
    public func operations(withWeft weft: ORDTLocalTimestampWeft? = nil) -> ArbitraryIndexSlice<OperationT>
    {
        precondition(weft == nil || self.timestampWeft.isSuperset(of: weft!), "weft not included in current ORDT revision")
        
        if let weft = weft, weft != self.timestampWeft
        {
            var ranges: [CountableRange<Int>] = []
            var currentRange: CountableRange<Int>!
            
            for p in self._operations.enumerated()
            {
                if !weft.included(p.element.id)
                {
                    continue
                }
                
                if currentRange == nil
                {
                    currentRange = p.offset..<(p.offset + 1)
                }
                else if p.offset == currentRange.endIndex
                {
                    currentRange = currentRange.startIndex..<(p.offset + 1)
                }
                else
                {
                    ranges.append(currentRange)
                    currentRange = p.offset..<(p.offset + 1)
                }
            }
            if currentRange != nil
            {
                ranges.append(currentRange)
            }
            
            return ArbitraryIndexSlice.init(self._operations, withValidIndices: ranges)
        }
        else
        {
            return self.slice
        }
    }
    
    // PERF: rather slow: O(nlogn) * 2 or more
    public func yarn(forSite site: LUID, withWeft weft: ORDTLocalTimestampWeft? = nil) -> ArbitraryIndexSlice<OperationT>
    {
        precondition(weft == nil || self.timestampWeft.isSuperset(of: weft!), "weft not included in current ORDT revision")
        
        let weft = weft ?? self.timestampWeft
        
        var indexArray: [Int] = []
        indexArray.reserveCapacity(self._operations.count)
        
        // O(n)
        for i in 0..<self._operations.count
        {
            if !weft.included(self._operations[i].id)
            {
                continue
            }

            if self._operations[i].id.siteID != site
            {
                continue
            }
            
            indexArray.append(i)
        }

        // O(nlogn)
        indexArray.sort
        { (i1, i2) -> Bool in
            if self._operations[i1].id.siteID < self._operations[i2].id.siteID
            {
                return true
            }
            else if self._operations[i1].id.siteID > self._operations[i2].id.siteID
            {
                return false
            }
            else
            {
                return self._operations[i1].id < self._operations[i2].id
            }
        }

        var ranges: [CountableRange<Int>] = []
        var currentRange: CountableRange<Int>!

        // O(n)
        for i in indexArray
        {
            if currentRange == nil
            {
                currentRange = i..<(i + 1)
            }
            else if i == currentRange.endIndex
            {
                currentRange = currentRange.startIndex..<(i + 1)
            }
            else
            {
                ranges.append(currentRange)
                currentRange = i..<(i + 1)
            }
        }
        if currentRange != nil
        {
            ranges.append(currentRange)
        }
        
        return ArbitraryIndexSlice.init(self._operations, withValidIndices: ranges)
    }
    
    public var baseline: ORDTLocalTimestampWeft? { return nil }
    public func setBaseline(_ weft: ORDTLocalTimestampWeft) throws
    {
        throw SetBaselineError.notSupported
    }
    
    private static func order(a1: OperationT, a2: OperationT) -> Bool
    {
        if a1.value.key < a2.value.key
        {
            return true
        }
        else if a1.value.key > a2.value.key
        {
            return false
        }
        else
        {
            return a1.id < a2.id
        }
    }
}

// for "degenerate" maps that simply act as e.g. site registers
extension ORDTMap where KeyT == InstancedLUID
{
    mutating public func setValue(_ value: ValueT)
    {
        setValue(value, forKey: self.owner)
    }
}

public struct PairValue <KeyT: Hashable, ValueT> : IndexRemappable
{
    public private(set) var key: KeyT
    public private(set) var value: ValueT
    
    public init(key: KeyT, value: ValueT)
    {
        self.key = key
        self.value = value
    }
}

// automatic IndexRemappable handling
extension PairValue
{
    private mutating func remapKey(_ map: [SiteId:SiteId]) {}
    private mutating func remapValue(_ map: [SiteId:SiteId]) {}
    
    public mutating func remapIndices(_ map: [SiteId:SiteId])
    {
        remapKey(map)
        remapValue(map)
    }
}
extension PairValue where KeyT == LUID
{
    private mutating func remapKey(_ map: [SiteId:SiteId])
    {
        if let newKey = map[SiteId(self.key)]
        {
            self.key = LUID(newKey)
        }
    }
}
extension PairValue where KeyT: IndexRemappable
{
    private mutating func remapKey(_ map: [SiteId:SiteId])
    {
        self.key.remapIndices(map)
    }
}
extension PairValue where ValueT == LUID
{
    private mutating func remapValue(_ map: [SiteId:SiteId])
    {
        if let newValue = map[SiteId(self.value)]
        {
            self.value = LUID(newValue)
        }
    }
}
extension PairValue where ValueT: IndexRemappable
{
    private mutating func remapValue(_ map: [SiteId:SiteId])
    {
        self.value.remapIndices(map)
    }
}
