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
    private var operations: [OperationT]
    
    // caches
    public private(set) var lamportClock: Clock
    public private(set) var indexWeft: Weft<SiteId>
    
    // these are merely convenience variables and do not affect hashes, etc.
    private var owner: SiteId

    // data access
    private var revisionWeft: Weft<SiteId>? = nil
    private var _revisionSlice: ArbitraryIndexSlice<OperationT>? = nil
    private var slice: ArbitraryIndexSlice<OperationT>
    {
        get
        {
            if let weft = revisionWeft
            {
                if _revisionSlice == nil
                {
                    assert(false, "revision slice should have been generated")
                    return self.operations(withWeft: weft)
                }
                else
                {
                    return _revisionSlice!
                }
            }
            else
            {
                return ArbitraryIndexSlice<OperationT>.init(self.operations, withValidIndices: nil)
            }
        }
    }
    
    public init(withOwner owner: SiteId)
    {
        self.operations = []
        self.owner = owner
        self.indexWeft = Weft<SiteId>()
        self.lamportClock = 0
    }
    
    // TODO: remove
    public init(from decoder: Decoder) throws { fatalError("init(from) has not been implemented") }
    public func encode(to encoder: Encoder) throws { fatalError("encode(to) has not been implemented") }
    
    mutating public func setValue(_ value: ValueT, forKey key: KeyT)
    {
        if self.revisionWeft != nil
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
            let index = self.operations.insertionIndexOf(elem: op, isOrderedBefore: ORDTMap.order)
            self.operations.insert(op, at: index)
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
        if self.revisionWeft != nil
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
            
            while i < self.operations.count || j < v.operations.count
            {
                let a = (i < self.operations.count ? self.operations[i] : nil)
                let b = (j < v.operations.count ? v.operations[j] : nil)
                
                let aBeforeB = b == nil || ORDTMap.order(a1: a!, a2: b!)
                
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
            self.operations = newOperations
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
                throw ValidationError.inconsistentCaches
                //return false
            }
            if newLamport != self.lamportClock
            {
                throw ValidationError.inconsistentCaches
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
        if self.revisionWeft != nil
        {
            assert(false, "can't edit ORDT revision")
            return
        }
        
        for i in 0..<self.operations.count
        {
            self.operations[i].remapIndices(map)
        }
        
        // TODO: indexWeft, revisionWeft
        
        if let newOwner = map[self.owner]
        {
            self.owner = newOwner
        }
    }
    
    public func operations(withWeft weft: Weft<SiteId>? = nil) -> ArbitraryIndexSlice<OperationT>
    {
        if let weft = weft, weft != self.indexWeft
        {
            let filteredArray = self.operations.enumerated().filter
            { (p) -> Bool in
                return weft.included(p.element.id)
            }
            
            var ranges: [CountableRange<Int>] = []
            var currentRange: CountableRange<Int>!
            
            for p in filteredArray
            {
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
            
            return ArbitraryIndexSlice.init(self.operations, withValidIndices: ranges)
        }
        else
        {
            return ArbitraryIndexSlice.init(self.operations, withValidIndices: nil)
        }
    }
    
    // PERF: rather slow: O(nlogn) * 2 or more
    public func yarn(forSite site: SiteId, withWeft weft: Weft<SiteId>? = nil) -> ArbitraryIndexSlice<OperationT>
    {
        let sortedArray = self.operations.enumerated().sorted
        { (p1, p2) -> Bool in
            if p1.element.id.site < p2.element.id.site
            {
                return true
            }
            else if p1.element.id.site > p2.element.id.site
            {
                return false
            }
            else
            {
                return p1.element.id.index < p2.element.id.index
            }
        }
        
        let sortedSiteArray = sortedArray.filter
        { (p) -> Bool in
            if let weft = weft, !weft.included(p.element.id)
            {
                return false
            }
            
            return p.element.id.site == site
        }
        
        var ranges: [CountableRange<Int>] = []
        var currentRange: CountableRange<Int>!
        
        for p in sortedSiteArray
        {
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
        
        return ArbitraryIndexSlice.init(self.operations, withValidIndices: ranges)
    }
    
    public func revision(_ weft: Weft<SiteId>?) -> ORDTMap
    {
        if weft == nil || weft == self.indexWeft
        {
            return self
        }
        
        precondition(self.indexWeft.isSuperset(of: weft!), "weft not included in current ORDT revision")
        
        // TODO: does this actually avoid copies?
        var copy = ORDTMap.init(withOwner: self.owner)
        copy.operations = self.operations
        copy.indexWeft = self.indexWeft
        copy.lamportClock = self.lamportClock
        copy.revisionWeft = weft!
        copy._revisionSlice = copy.operations(withWeft: weft!)
        
        return copy
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
