//
//  CRDTCausalTreesBasicTypes.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-9-18.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import Foundation

protocol CausalTreeSiteUUIDT: DefaultInitializable, CustomStringConvertible, Hashable, Zeroable, Comparable, Codable {}
protocol CausalTreeValueT: DefaultInitializable, CausalTreeAtomPrintable, Codable {}

typealias SiteId = Int16
typealias Clock = Int64
typealias ArrayType = Array //AB: ContiguousArray makes me feel safer, but is not Codable by default :(

typealias YarnIndex = Int32
typealias WeaveIndex = Int32
typealias AllYarnsIndex = Int32 //TODO: this is underused -- mistakenly use YarnsIndex

// no other atoms can have these clock numbers
let ControlSite: SiteId = SiteId(0)
let StartClock: Clock = Clock(1)
let EndClock: Clock = Clock(2)
let NullSite: SiteId = SiteId(SiteId.max)
let NullClock: Clock = Clock(0)
let NullIndex: YarnIndex = -1 //max (NullIndex, index) needs to always return index
let NullAtomId: AtomId = AtomId(site: NullSite, index: NullIndex)

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

enum AtomType: Int8, CustomStringConvertible, Codable
{
    case none = 0
    case commit = 1 //unordered child: appended to back of weave, since only yarn position matters
    case start = 2
    case end = 3
    case delete = 4
    //case undelete = 5
    
    // not part of DFS ordering and output; might only use atom reference
    var unparented: Bool
    {
        // TODO: end should probably be parented, but childless
        // AB: end is also non-causal for convenience, since we can't add anything to it and it will start off our non-causal segment
        return self == .commit || self == .end
    }
    
    // cannot cause anything; useful for invisible and control atoms
    var childless: Bool
    {
        return self == .end || self == .delete
    }
    
    // pushed to front of child ordering, so that e.g. control atoms with specific targets are not regargeted on merge
    var priority: Bool
    {
        return self == .delete
    }
    
    var description: String
    {
        switch self {
        case .none:
            return "None"
        case .commit:
            return "Commit"
        case .start:
            return "Start"
        case .end:
            return "End"
        case .delete:
            return "Delete"
        }
    }
}

// avoids having to generify every freakin' view controller
struct AtomMetadata
{
    let id: AtomId
    let cause: AtomId
    let reference: AtomId
    let type: AtomType
    let clock: Clock
}

// TODO: I don't like that this tiny structure has to be malloc'd
struct Weft: Equatable, Comparable, CustomStringConvertible
{
    private(set) var mapping: [SiteId:YarnIndex] = [:]
    
    mutating func update(site: SiteId, index: YarnIndex)
    {
        if site == NullAtomId.site { return }
        mapping[site] = max(mapping[site] ?? NullIndex, index)
    }
    
    mutating func update(atom: AtomId) {
        if atom == NullAtomId { return }
        update(site: atom.site, index: atom.index)
    }
    
    mutating func update(weft: Weft)
    {
        for (site, index) in weft.mapping
        {
            update(site: site, index: index)
        }
    }
    
    func included(_ atom: AtomId) -> Bool {
        if atom == NullAtomId
        {
            return true //useful default when generating causal blocks for non-causal atoms
        }
        if let index = mapping[atom.site] {
            if atom.index <= index {
                return true
            }
        }
        return false
    }
    
    // assumes that both wefts have equivalent site id maps
    // Complexity: O(S)
    static func <(lhs: Weft, rhs: Weft) -> Bool
    {
        // remember that we can do this efficiently b/c site ids increase monotonically -- no large gaps
        let maxLhsSiteId = lhs.mapping.keys.max() ?? 0
        let maxRhsSiteId = rhs.mapping.keys.max() ?? 0
        let maxSiteId = Int(max(maxLhsSiteId, maxRhsSiteId)) + 1
        var lhsArray = Array<YarnIndex>(repeating: -1, count: maxSiteId)
        var rhsArray = Array<YarnIndex>(repeating: -1, count: maxSiteId)
        lhs.mapping.forEach { lhsArray[Int($0.key)] = $0.value }
        rhs.mapping.forEach { rhsArray[Int($0.key)] = $0.value }
        
        return lhsArray.lexicographicallyPrecedes(rhsArray)
    }
    
    public static func ==(lhs: Weft, rhs: Weft) -> Bool
    {
        return (lhs.mapping as NSDictionary).isEqual(to: rhs.mapping)
    }
    
    var description: String
    {
        get
        {
            var string = "["
            let sites = Array<SiteId>(mapping.keys).sorted()
            for (i,site) in sites.enumerated()
            {
                if i != 0
                {
                    string += ", "
                }
                string += "\(site):\(mapping[site]!)"
            }
            string += "]"
            return string
        }
    }
}
