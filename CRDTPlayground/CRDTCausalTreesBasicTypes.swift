//
//  CRDTCausalTreesBasicTypes.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-9-18.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import Foundation

protocol CausalTreeSiteUUIDT: DefaultInitializable, CustomStringConvertible, Hashable, Zeroable, Comparable, Codable {}
protocol CausalTreeValueT: DefaultInitializable, CustomStringConvertible, CausalTreeAtomPrintable, Codable {}

typealias SiteId = Int16
typealias Clock = Int64
typealias ArrayType = Array //AB: ContiguousArray makes me feel safer, but is not Codable by default :(

typealias YarnIndex = Int32
typealias WeaveIndex = Int32
typealias AllYarnsIndex = Int32 //TODO: this is underused -- mistakenly use YarnsIndex

// no other atoms can have these clock numbers
let NullSite: SiteId = SiteId(SiteId.max)
let ControlSite: SiteId = SiteId(0)
let NullClock: Clock = Clock(0)
let StartClock: Clock = Clock(1)
let EndClock: Clock = Clock(2)

struct AtomId: Equatable, Comparable, CustomStringConvertible, Codable
{
    let site: SiteId
    let index: YarnIndex
    
    public static func ==(lhs: AtomId, rhs: AtomId) -> Bool
    {
        return lhs.site == rhs.site && lhs.index == rhs.index
    }
    
    var description: String
    {
        get
        {
            if site == NullSite
            {
                return "x:x"
            }
            else
            {
                return "\(site):\(index)"
            }
        }
    }
    
    // WARNING: this does not mean anything structurally, and is just used for ordering non-causal atoms
    static func <(lhs: AtomId, rhs: AtomId) -> Bool {
        return (lhs.site == rhs.site ? lhs.index < rhs.index : lhs.site < rhs.site)
    }
}
