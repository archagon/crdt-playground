//
//  ORDTBasicDataStructures.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2018-4-10.
//  Copyright © 2018 Alexei Baboulevitch. All rights reserved.
//

import Foundation

/// We can't have vararg generics, so individual declarations for tuples will have to do. Boilerplate.
public protocol ORDTTuple: ORDTContainer {}

public struct ORDTTuple2 <O1: ORDT, O2: ORDT> : ORDTTuple
{
    public var ordt1: O1
    public var ordt2: O2
    
    public var lamportClock: ORDTClock
    {
        return max(self.ordt1.lamportClock, self.ordt2.lamportClock)
    }
    
    public init(_ ordt1: O1, _ ordt2: O2)
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
    
    public mutating func remapIndices(_ map: [LUID:LUID])
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

    public func hash(into hasher: inout Hasher)
    {
        hasher.combine(self.ordt1)
        hasher.combine(self.ordt2)
    }
    
    public static func ==(lhs: ORDTTuple2<O1,O2>, rhs: ORDTTuple2<O1,O2>) -> Bool
    {
        return lhs.ordt1 == rhs.ordt1 && lhs.ordt2 == rhs.ordt2
    }
}

/// A slice with arbitrary index order (including possible repetitions). Does not preserve indices from sequence.
public struct ArbitraryIndexSlice<T> : RandomAccessCollection
{
    // AB: yeah, this is cheating since it only serves to give us a generic wrapper around sequences,
    // but ArraySlice uses some private, seemingly code-genned buffers under the hood that just aren't
    // worth re-implementing
    private var buffer: ArraySlice<T>
    
    public private(set) var indexRanges: [CountableRange<Index>]?
    public private(set) var indexCount: Int
    
    /// If `validIndices` is nil, the entire range will be used.
    public init<S>(_ s: S, withValidIndices validIndices: [CountableRange<Int>]?) where S:Sequence, Element == S.Element
    {
        let slice = ArraySlice<T>(s)
        
        var length = 0
        for range in validIndices ?? []
        {
            precondition(range.startIndex >= slice.startIndex, "invalid start index for range")
            precondition(range.endIndex <= slice.endIndex, "invalid end index for range")
            
            length += range.count
        }
        
        self.buffer = slice
        self.indexRanges = validIndices
        self.indexCount = (validIndices == nil ? slice.count : length)
    }
    
    public var startIndex: Int
    {
        return 0
    }
    
    public var endIndex: Int
    {
        return self.indexCount
    }
    
    public func index(after i: Int) -> Int
    {
        precondition(i >= self.startIndex, "index must be greater than or equal to startIndex")
        precondition(i < self.endIndex, "index must be less than endIndex")
        
        return i + 1
    }
    
    public func index(before i: Int) -> Int
    {
        precondition(i > self.startIndex, "index must be greater than startIndex")
        precondition(i <= self.endIndex, "index must be less than or equal to endIndex")
        
        return i - 1
    }
    
    public func index(_ i: Int, offsetBy n: Int) -> Int
    {
        precondition(i >= self.startIndex && i < self.endIndex, "index must be inside bounds")
        precondition(i + n < self.endIndex, "offset must not put index outside bounds")
        
        return i + n
    }
    
    public func distance(from start: Int, to end: Int) -> Int
    {
        precondition(start >= self.startIndex && start <= self.endIndex, "start must be inside bounds")
        precondition(end >= self.startIndex && end <= self.endIndex, "end must be inside bounds")
        
        return end - start
    }
    
    public subscript(position: Int) -> T
    {
        if self.indexRanges == nil
        {
            return self.buffer[position]
        }
        
        var originalIndex: Int!
        var currentPosition = position
        
        for range in self.indexRanges!
        {
            if range.count <= currentPosition
            {
                currentPosition -= range.count
            }
            else
            {
                originalIndex = range.startIndex + currentPosition
                break
            }
        }
        
        precondition(originalIndex != nil, "position exceeds index ranges")
        
        return self.buffer[originalIndex]
    }
}
