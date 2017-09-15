//
//  CRDTGeneral.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-9-6.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import Foundation

protocol CvRDT
{
    // must obey CRDT convergence properties
    mutating func integrate(_ v: inout Self)
    
    // for avoiding needless merging; should be efficient
    func superset(_ v: inout Self) -> Bool
    
    // ensures that our algorithm-based invariants are correct, for debugging and merge sanity checking
    func validate() -> Bool
}

protocol ApproxSizeable
{
    // approximate size when serialized -- mostly used for debugging
    func sizeInBytes() -> Int
}
