//
//  CRDTMap.swift
//  CloudKitRealTimeCollabTest
//
//  Created by Alexei Baboulevitch on 2017-10-27.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import Foundation

// TODO: base class generic ORDT w/weft, lamport, maybe op array, revision, comparator stub, etc. ("frame")

// TODO: remove zeroable requirements, as well as this quick fix
extension AtomId: Zeroable { public static var zero: AtomId { return AtomId.init(site: 0, index: 0) } }

/// A simple LWW map.
public struct ORDTMap
    <KeyT: Comparable & Hashable & Codable & Zeroable, ValueT: Codable & Zeroable>
    : ORDT, UsesGlobalLamport
{
    public typealias OperationT = Atom<PairValue<KeyT, ValueT>>
    
    weak public var lamportDelegate: ORDTGlobalLamportDelegate?
    
    // primary state
    // AB: don't read from this unless necessary, use `slice` instead; preserved whole in revisions
    private var _operations: [OperationT]
    
    // caches
    public private(set) var lamportClock: Clock
    public private(set) var indexWeft: Weft<SiteId>
    
    // these are merely convenience variables and do not affect hashes, etc.
    private var owner: SiteId

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
    
    public init(withOwner owner: SiteId, reservingCapacity capacity: Int? = nil)
    {
        self._operations = []
        if let capacity = capacity { self._operations.reserveCapacity(capacity) }
        self.owner = owner
        self.indexWeft = Weft<SiteId>()
        self.lamportClock = 0
        self._revisionSlice = nil
    }
    
    // AB: separate init method instead of doing everything in `revision` so that we can set `_revisionSlice`
    private init(copyFromMap map: ORDTMap, withRevisionWeft weft: Weft<SiteId>)
    {
        let slice = map.operations(withWeft: weft)
        self.owner = map.owner
        self._operations = map._operations
        self.indexWeft = weft
        self.lamportClock = slice.reduce(0) { (result, a) -> Clock in max(result, Clock(a.timestamp)) }
        self._revisionSlice = slice
    }
    
    public func revision(_ weft: Weft<SiteId>?) -> ORDTMap
    {
        if weft == nil || weft == self.indexWeft
        {
            return self
        }
        
        return ORDTMap.init(copyFromMap: self, withRevisionWeft: weft!)
    }
    
    // TODO: remove
    public init(from decoder: Decoder) throws { fatalError("init(from) has not been implemented") }
    public func encode(to encoder: Encoder) throws { fatalError("encode(to) has not been implemented") }
    
    mutating public func changeOwner(_ owner: SiteId)
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
        
        // TODO: 0 vs. 1?
        let lastIndex = self.indexWeft.mapping[self.owner] ?? -1
        let lamportClock = (self.lamportDelegate?.delegateLamportClock ?? Int(self.lamportClock)) + 1
        
        let id = AtomId(site: self.owner, index: lastIndex + 1)
        let op = Atom(id: id, cause: id, timestamp: YarnIndex(lamportClock), value: PairValue(key: key, value: value))
        
        updateData: do
        {
            let index = self._operations.insertionIndexOf(elem: op, isOrderedBefore: ORDTMap.order)
            self._operations.insert(op, at: index)
        }
        
        updateCaches: do
        {
            self.indexWeft.update(atom: id)
            self.lamportClock = Clock(lamportClock)
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
        var newWeft = Weft<SiteId>()
        var newLamport: Clock = 0
        
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
                    newWeft.update(atom: a!.id)
                    newLamport = max(newLamport, Clock(a!.timestamp))
                    i += 1
                }
                else
                {
                    newOperations.append(b!)
                    newWeft.update(atom: b!.id)
                    newLamport = max(newLamport, Clock(b!.timestamp))
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
            self.indexWeft = newWeft
            self.lamportClock = newLamport
        }
    }
    
    public func superset(_ v: inout ORDTMap) -> Bool
    {
        return self.indexWeft.isSuperset(of: v.indexWeft)
    }
    
    public func validate() throws -> Bool
    {
        var newWeft = Weft<SiteId>()
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
                
                newLamport = max(newLamport, Clock(self.slice[i].timestamp))
                newWeft.update(atom: self.slice[i].id)
            }
        }
        
        validateCaches: do
        {
            if newWeft != self.indexWeft
            {
                throw ValidationError.inconsistentWeft
                //return false
            }
            if newLamport != self.lamportClock
            {
                throw ValidationError.inconsistentLamportTimestamp
                //return false
            }
        }
        
        return true
    }
    
    public static func ==(lhs: ORDTMap, rhs: ORDTMap) -> Bool
    {
        return lhs.indexWeft == rhs.indexWeft
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
        
        // TODO: indexWeft
        
        if let newOwner = map[self.owner]
        {
            self.owner = newOwner
        }
    }
    
    public func operations(withWeft weft: Weft<SiteId>? = nil) -> ArbitraryIndexSlice<OperationT>
    {
        precondition(weft == nil || self.indexWeft.isSuperset(of: weft!), "weft not included in current ORDT revision")
        
        if let weft = weft, weft != self.indexWeft
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
    public func yarn(forSite site: SiteId, withWeft weft: Weft<SiteId>? = nil) -> ArbitraryIndexSlice<OperationT>
    {
        precondition(weft == nil || self.indexWeft.isSuperset(of: weft!), "weft not included in current ORDT revision")
        
        let weft = weft ?? self.indexWeft
        
        var indexArray: [Int] = []
        indexArray.reserveCapacity(self._operations.count)
        
        // O(n)
        for i in 0..<self._operations.count
        {
            if !weft.included(self._operations[i].id)
            {
                continue
            }

            if self._operations[i].id.site != site
            {
                continue
            }
            
            indexArray.append(i)
        }

        // O(nlogn)
        indexArray.sort
        { (i1, i2) -> Bool in
            if self._operations[i1].id.site < self._operations[i2].id.site
            {
                return true
            }
            else if self._operations[i1].id.site > self._operations[i2].id.site
            {
                return false
            }
            else
            {
                return self._operations[i1].id.index < self._operations[i2].id.index
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
    
    public var baseline: Weft<SiteId>? { return nil }
    public func setBaseline(_ weft: Weft<SiteId>) throws
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
            if a1.timestamp < a2.timestamp
            {
                return true
            }
            else if a1.timestamp > a2.timestamp
            {
                return false
            }
            else
            {
                return a1.id.site < a2.id.site
            }
        }
    }
}

// for "degenerate" maps that simply act as e.g. site registers
extension ORDTMap where KeyT == SiteId
{
    mutating public func setValue(_ value: ValueT)
    {
        setValue(value, forKey: self.owner)
    }
}

public struct PairValue <KeyT: Hashable & Codable & Zeroable, ValueT: Codable & Zeroable> : CRDTValueT
{
    public private(set) var key: KeyT
    public private(set) var value: ValueT
    
    public init()
    {
        self.key = KeyT.zero
        self.value = ValueT.zero
    }
    
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
extension PairValue where KeyT == SiteId
{
    private mutating func remapKey(_ map: [SiteId:SiteId])
    {
        if let newKey = map[self.key]
        {
            self.key = newKey
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
extension PairValue where ValueT == SiteId
{
    private mutating func remapValue(_ map: [SiteId:SiteId])
    {
        if let newValue = map[self.value]
        {
            self.value = newValue
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
