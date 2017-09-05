//
//  CRDTCausalTrees.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-8-28.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import Foundation

// TODO: store char instead of string -- need contiguous blocks of memory
// TODO: weft needs to be stored in contiguous memory

protocol CausalTreeSiteUUIDT: DefaultInitializable, CustomStringConvertible, Hashable, Zeroable, Comparable {}
protocol CausalTreeValueT: DefaultInitializable, CustomStringConvertible {}

typealias SiteId = Int16 //warning: older atoms might have different site ids, since we use lexographic order!
typealias Clock = Int64

final class CausalTree <SiteUUIDT: CausalTreeSiteUUIDT, ValueT: CausalTreeValueT> : CvRDT {
    // these are separate b/c they are serialized separately and grow separately -- and, really, are separate CRDTs
    var siteIndex: SiteIndex<SiteUUIDT> = SiteIndex<SiteUUIDT>()
    var weave: Weave<SiteUUIDT,ValueT> = Weave<SiteUUIDT,ValueT>()
    
    init() {
    }
    
    func integrate(_ v: inout CausalTree) {
        let indices = siteIndex.integrateReturningFirstDiffIndex(&v.siteIndex)
        siteIndex.integrate(&v.siteIndex)
        //TODO: weave update indices
        weave.integrate(&v.weave)
    }
    
    func serialize() {
    }
    
    func deserialize() {
    }
}

final class SiteIndex <SiteUUIDT: CausalTreeSiteUUIDT> : CvRDT {
    
    struct SiteIndexKey: Comparable {
        let clock: Clock
        let id: SiteUUIDT
        
        // PERF: is comparing UUID strings quick enough?
        public static func <(lhs: SiteIndexKey, rhs: SiteIndexKey) -> Bool {
            return (lhs.clock == rhs.clock ? lhs.id < rhs.id : lhs.clock < rhs.clock)
        }
        public static func <=(lhs: SiteIndexKey, rhs: SiteIndexKey) -> Bool {
            return (lhs.clock == rhs.clock ? lhs.id <= rhs.id : lhs.clock <= rhs.clock)
        }
        public static func >=(lhs: SiteIndexKey, rhs: SiteIndexKey) -> Bool {
            return (lhs.clock == rhs.clock ? lhs.id >= rhs.id : lhs.clock >= rhs.clock)
        }
        public static func >(lhs: SiteIndexKey, rhs: SiteIndexKey) -> Bool {
            return (lhs.clock == rhs.clock ? lhs.id > rhs.id : lhs.clock > rhs.clock)
        }
        public static func ==(lhs: SiteIndexKey, rhs: SiteIndexKey) -> Bool {
            return lhs.id == rhs.id && lhs.clock == rhs.clock
        }
    }
    
    // we assume this is always sorted in lexographic order -- first by clock, then by UUID
    private var mapping: ContiguousArray<SiteIndexKey> = []
    
    init() {
        addId(SiteUUIDT.zero, withClock: 0)
    }
    
    func siteId(forSite site: SiteUUIDT) -> SiteId {
        return 0
        // NEXT:
    }
    
    func addId(_ id: SiteUUIDT, withClock clock: Clock) {
        let key = SiteIndexKey(clock: clock, id: id)
        let insertionIndex = binarySearch(inputArr: mapping, searchItem: key, exact: false)
        // NEXT:
    }
    
    func integrate(_ v: inout SiteIndex) {
        let _ = integrateReturningFirstDiffIndex(&v)
    }
    
    // returns index of first local edit, after and including which, site indices in weave will have to be rewritten; nil means no edit or empty
    func integrateReturningFirstDiffIndex(_ v: inout SiteIndex) -> Int? {
        var firstEdit: Int? = nil
        
        var i = 0
        var j = 0
        
        while i < self.mapping.count || j < v.mapping.count {
            // TODO: tuples support equality checking by default???
            if self.mapping[i] > v.mapping[j] {
                // v has new data, integrate
                self.mapping.insert(v.mapping[j], at: i)
                firstEdit = i
                i += 1
                j += 1
            }
            else if self.mapping[i] < v.mapping[j] {
                // we have newer data, skip
                i += 1
            }
            else {
                // data is the same, all is well
                i += 1
                j += 1
            }
        }
        
        return firstEdit
    }
}

// an ordered collection of yarns for multiple sites
// TODO: store as an actual weave? prolly not worth it -- mostly useful for transmission
final class Weave<
    SiteUUIDT: DefaultInitializable & CustomStringConvertible & Hashable & Zeroable,
    ValueT: DefaultInitializable & CustomStringConvertible>
    : CvRDT
{
    // NEXT: weave + text generation
    // NEXT: merge
    
    struct AtomId: Comparable, Hashable {
        let site: SiteId
        let clock: Clock
        
        public var hashValue: Int {
            get { return site.hashValue ^ clock.hashValue }
        }
        public static func <(lhs: AtomId, rhs: AtomId) -> Bool {
            return (lhs.clock == rhs.clock ? lhs.site < rhs.site : lhs.clock < rhs.clock)
        }
        public static func <=(lhs: AtomId, rhs: AtomId) -> Bool {
            return (lhs.clock == rhs.clock ? lhs.site <= rhs.site : lhs.clock <= rhs.clock)
        }
        public static func >=(lhs: AtomId, rhs: AtomId) -> Bool {
            return (lhs.clock == rhs.clock ? lhs.site >= rhs.site : lhs.clock >= rhs.clock)
        }
        public static func >(lhs: AtomId, rhs: AtomId) -> Bool {
            return (lhs.clock == rhs.clock ? lhs.site > rhs.site : lhs.clock > rhs.clock)
        }
        public static func ==(lhs: AtomId, rhs: AtomId) -> Bool {
            return lhs.site == rhs.site && lhs.clock == rhs.clock
        }
    }
    
    struct Atom {
        let id: AtomId
        let cause: AtomId
        let value: ValueT
    }
    
    struct Weft: Equatable {
        var mapping: [SiteId:Clock]
        
        mutating func update(site: SiteId, clock: Clock) {
            mapping[site] = max(mapping[site] ?? NullClock, clock)
        }
        
        mutating func update(weft: Weft) {
            for (site, clock) in weft.mapping {
                update(site: site, clock: clock)
            }
        }
        
        public static func ==(lhs: Weft, rhs: Weft) -> Bool {
            return (lhs.mapping as NSDictionary).isEqual(to: rhs.mapping)
        }
    }
    
    // no other atoms can have these clock numbers
    static var NullSite: SiteId { get { return SiteId(SiteId.max) }}
    static var ControlSite: SiteId { get { return SiteId(0) }}
    static var NullClock: Clock { get { return Clock(0) }}
    static var StartClock: Clock { get { return Clock(1) }}
    static var EndClock: Clock { get { return Clock(2) }}
    static var NullAtomId: AtomId { return AtomId(site: NullSite, clock: NullClock) }
    
    // CONDITION: this data must be the same locally as in the cloud, i.e. no object oriented cache layers etc.
    var atoms: ContiguousArray<Atom> = [] //solid chunk of memory for optimal performance
    
    init() {
        clear()
    }
    
    func atom(_ atomId: AtomId) -> Atom? {
        let aYarn = yarn(forSite: atomId.site, upToCommit: atomId.clock)
        if let aAtom = aYarn.last, aAtom.id == atomId {
            return aAtom
        }
        return nil
    }
    
    // TODO: make lazy
    // TODO: mutable vs immutable?
    func yarn(forSite site:SiteId, upToCommit commit: Clock? = nil) -> AnyBidirectionalCollection<Atom> {
        if site < yarns.count {
            if let aCommit = commit {
                if let index = index(forSite: site, beforeCommit: aCommit) {
                    return AnyBidirectionalCollection(yarns[Int(site)][0...index])
                }
            }
            else {
                return AnyBidirectionalCollection(yarns[Int(site)])
            }
        }
        
        return AnyBidirectionalCollection<Atom>([])
    }
    
    // NEXT: for string generation + storage
    func weave(upToCommit commit: Clock? = nil) -> AnyBidirectionalCollection<Atom>? {
        return nil
    }
    
    // TODO: fix binary search
    // last index, inclusive, for <= commit
    var indexChecks = 0
    func index(forSite site: SiteId, beforeCommit commit: Clock, equalOnly: Bool = false) -> Int? {
        //print("\(indexChecks) index checks")
        indexChecks += 1
        let aYarn = yarn(forSite: site)
        
        let searchItem = Atom(id: AtomId(site: site, clock: commit), cause: Weave.NullAtomId, value: ValueT())
        if let item = binarySearch(inputArr: aYarn, searchItem: searchItem, exact: equalOnly) {
            return Int(item)
        }
        else {
            return nil
        }
    }
    
    // currently O(N * log(N)) in the worst case -- but in practice, probably mostly O(N)
    func awarenessWeft(forAtom atomId: AtomId/*, updatingCache cache: [AtomId:Weft]? = nil*/) -> Weft? {
        // I think it's definitely the case that the VAST majority of insertions take place on the same yarn,
        // wherein they can easily be conflict-resolved by simply comparing the clock value. But also,
        // since we're O(N) (at least) looking at the document on load anyway, it's probably best to just
        // cache the durn awareness wefts anyways.
        
        // weft derivation is local, so we're free to optimize by using indices, which will not change in this method
        // clocks work the same as indices, for the purpose of positional comparisons
        typealias AtomI = Int
        typealias WeftIC = [SiteId:(atomIndex:AtomI?,clock:Clock)] //the index can be calculated on demand
        
        // have to make sure atom exists in the first place
        guard let startingAtomIndex = index(forSite: atomId.site, beforeCommit: atomId.clock, equalOnly: true) else {
            return nil
        }
        
        var completedWeft: WeftIC = [:] //needed to compare against workingWeft to figure out unprocessed atoms
        var workingWeft: WeftIC = [atomId.site:(startingAtomIndex,atomId.clock)] //read-only, used to seed nextWeft
        var nextWeft: WeftIC = [:] //acquires buildup from unseen workingWeft atom connections for next loop iteration
        
        // weft manipulation functions
        func add(atomIndex: AtomI?, clock: Clock, atSite site: SiteId, toWeft weft: inout WeftIC)  {
            if let maxAtom = weft[site] {
                if clock >= maxAtom.clock {
                    weft[site] = ((maxAtom.atomIndex == nil ? atomIndex : maxAtom.atomIndex), clock)
                }
            }
            else {
                weft[site] = (atomIndex, clock)
            }
        }
        func equal(weft1: WeftIC, weft2: WeftIC) -> Bool {
            if weft1.count != weft2.count {
                return false
            }
            for (site, _) in weft1 {
                if weft1[site]?.clock != weft2[site]?.clock {
                    return false
                }
            }
            return true
        }
        func checkIfIncluded(atomId: AtomId, inWeft weft: inout WeftIC) -> Bool {
            if let lastProcessedClockAtSite = weft[atomId.site]?.clock {
                if atomId.clock <= lastProcessedClockAtSite {
                    return true
                }
            }
            return false
        }
        func getAtomIndex(forSite site: SiteId, inWeft weft: inout WeftIC) -> Int? {
            guard let indices = weft[site] else {
                return nil
            }
            if let aIndex = indices.atomIndex {
                return aIndex
            }
            else {
                // TODO: PERF: O(log(N)), but should not happen too often if we don't have criss-crossing updates
                let aIndex = index(forSite: site, beforeCommit: indices.clock, equalOnly: true)
                weft[site]?.atomIndex = aIndex
                return aIndex
            }
        }
        
        while !equal(weft1: completedWeft, weft2: workingWeft) {
            for (site, _) in workingWeft {
                guard let atomIndex = getAtomIndex(forSite: site, inWeft: &workingWeft) else {
                    assert(false, "atom not found for index")
                }
                
                let aYarn = yarn(forSite: site, upToCommit: nil) //no performance penalty, since we're getting the whole thing
                assert(!aYarn.isEmpty, "indexed atom came from empty yarn")
                
                // process each un-processed atom in the given yarn; processing means following any causal links to other yarns
                for i in (0...atomIndex).reversed() {
                    // go backwards through the atoms that we haven't processed yet
                    if completedWeft[site] != nil {
                        guard let completedIndex = getAtomIndex(forSite: site, inWeft: &completedWeft) else {
                            assert(false, "atom not found for index")
                        }
                        if i <= completedIndex {
                            break
                        }
                    }
                    
                    enqueueCausalAtom: do {
                        // get the atom
                        let aIndex = aYarn.index(aYarn.startIndex, offsetBy: Int64(i))
                        let aAtom = aYarn[aIndex]
                        
                        // AB: since we've added the atomIndex method, these don't appear to be necessary any longer for perf
                        guard aAtom.cause.site != site else {
                            break enqueueCausalAtom //no need to check same-site connections since we're going backwards along the weft anyway
                        }
                        //guard !checkIfIncluded(atomId: aAtom.cause, inWeft: &workingWeft) else {
                        //    break enqueueCausalAtom //are we going to be considering this atom in this loop iteration anyway? (note: superset of completedWeft)
                        //}
                        
                        add(atomIndex: nil, clock: aAtom.cause.clock, atSite: aAtom.cause.site, toWeft: &nextWeft)
                    }
                }
            }
            
            // fill in missing gaps
            workingWeft.forEach({ (v: (site: SiteId, indices: (atomIndex: AtomI?, clock: Clock))) in
                add(atomIndex: v.indices.atomIndex, clock: v.indices.clock, atSite: v.site, toWeft: &nextWeft)
            })
            // update completed weft
            workingWeft.forEach({ (v: (site: SiteId, indices: (atomIndex: AtomI?, clock: Clock))) in
                add(atomIndex: v.indices.atomIndex, clock: v.indices.clock, atSite: v.site, toWeft: &completedWeft)
            })
            // swap
            swap(&workingWeft, &nextWeft)
        }
        
        // generate non-indexed weft
        var returnWeft = Weft(mapping: [:])
        for (site, indices) in completedWeft {
            returnWeft.update(site: site, clock: indices.clock)
        }
        return returnWeft
    }
    
    func siteId(forSite site: SiteUUIDT) -> SiteId? {
        if let index = self.sites.index(of: site) {
            return SiteId(index)
        }
        else {
            return nil
        }
    }
    
    func lastCommit(forSite site:SiteId) -> Clock? {
        let aYarn = yarn(forSite: site)
        
        if let commit = aYarn.last {
            return commit.id.clock
        }
        return nil
    }
    
    func addYarn(forSite site: SiteUUIDT) -> SiteId {
        if let id = siteId(forSite: site) {
            return id
        }
        else {
            sites.append(site)
            yarns.append(ContiguousArray<Atom>())
            return Int16(sites.count) - 1
        }
    }
    
    func add(value: ValueT, forSite site: SiteUUIDT, causedBy cause: AtomId) -> AtomId {
        let siteIndex = Int(addYarn(forSite: site))
        let lastClock = (yarns[siteIndex].count > 0 ? yarns[siteIndex].last!.id.clock : Weave.EndClock)
        let atomId = AtomId(site: SiteId(siteIndex), clock: lastClock + 1 + Clock(arc4random_uniform(30)))
        let atom = Atom(id: atomId, cause: cause, value: value)
        yarns[siteIndex].append(atom)
        return atomId
    }
    
    func clear() {
        sites.removeAll()
        yarns.removeAll(keepingCapacity: true)
        addBaseYarn()
    }
    
    private func addBaseYarn() {
        let uuid = SiteUUIDT.zero
        assert(siteId(forSite: uuid) == nil)
        
        sites.append(uuid)
        yarns.append(ContiguousArray<Atom>())
        let yarnIndex = Int(siteId(forSite: uuid)!)
        let aSiteId = SiteId(yarnIndex)
        assert(aSiteId == type(of: self).ControlSite)
        
        let startAtomId = AtomId(site: aSiteId, clock: type(of: self).StartClock)
        let startAtom = Atom(id: startAtomId, cause: startAtomId, value: ValueT())
        let endAtom = Atom(id: AtomId(site: aSiteId, clock: type(of: self).EndClock), cause: startAtomId, value: ValueT())
        yarns[yarnIndex].append(startAtom)
        yarns[yarnIndex].append(endAtom)
    }
    
    func remapIndices(_ indices: [SiteId:SiteId]) {
        // NEXT: iterate weave and substitue indices as needed
    }
    
    func integrate(_ v: inout Weave<SiteUUIDT,ValueT>) {
        // we assume that indices have been correctly remapped at this point
    }
}
