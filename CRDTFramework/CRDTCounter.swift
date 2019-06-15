//
//  CRDTCounter.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-10-10.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import Foundation

public protocol Incrementable
{
    // an incremented variable MUST be > the non-incremented variable
    // TODO: rollover
    mutating func increment()
}

extension Int32: Incrementable { public mutating func increment() { self += 1 } }
extension Int64: Incrementable { public mutating func increment() { self += 1 } }
extension UInt32: Incrementable { public mutating func increment() { self += 1 } }
extension UInt64: Incrementable { public mutating func increment() { self += 1 } }

public final class CRDTCounter
    <T: Incrementable & Comparable & Codable & Hashable> :
    CvRDT, NSCopying, CustomDebugStringConvertible, ApproxSizeable, Codable, Hashable
{
    public private(set) var counter: T
    
    public init(withValue value: T)
    {
        self.counter = value
    }
    
    public func copy(with zone: NSZone? = nil) -> Any
    {
        let returnValue = CRDTCounter<T>(withValue: counter)
        return returnValue
    }
    
    public func increment() -> T
    {
        let oldValue = counter
        counter.increment()
        return oldValue
    }
    
    public func integrate(_ v: inout CRDTCounter)
    {
        counter = max(counter, v.counter)
    }
    
    public func superset(_ v: inout CRDTCounter) -> Bool
    {
        return v.counter > counter
    }
    
    public func validate() throws -> Bool
    {
        return true
    }
    
    public func sizeInBytes() -> Int
    {
        return MemoryLayout<T>.size
    }
    
    public var debugDescription: String
    {
        return "C-\(counter)"
    }
    
    public static func ==(lhs: CRDTCounter<T>, rhs: CRDTCounter<T>) -> Bool
    {
        return lhs.counter == rhs.counter
    }

    public func hash(into hasher: inout Hasher)
    {
        hasher.combine(counter)
    }
}
