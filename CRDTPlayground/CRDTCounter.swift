//
//  CRDTCounter.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-10-10.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import Foundation

protocol Incrementable
{
    // an incremented variable MUST be > the non-incremented variable
    // TODO: rollover
    mutating func increment()
}

extension Int32: Incrementable { mutating func increment() { self += 1 } }

final class CRDTCounter
    <T: Incrementable & Comparable & Codable> :
    CvRDT, NSCopying, CustomDebugStringConvertible, ApproxSizeable
{
    private var counter: T
    
    init(withValue value: T)
    {
        self.counter = value
    }
    
    func copy(with zone: NSZone? = nil) -> Any
    {
        let returnValue = CRDTCounter<T>(withValue: counter)
        return returnValue
    }
    
    func increment()
    {
        counter.increment()
    }
    
    func integrate(_ v: inout CRDTCounter)
    {
        counter = max(counter, v.counter)
    }
    
    func superset(_ v: inout CRDTCounter) -> Bool
    {
        return v.counter > counter
    }
    
    func validate() throws -> Bool
    {
        return true
    }
    
    func sizeInBytes() -> Int
    {
        return MemoryLayout<T>.size
    }
    
    var debugDescription: String
    {
        return "C-\(counter)"
    }
}
