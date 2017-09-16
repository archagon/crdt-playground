//
//  CRDTCausalTrees.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-8-28.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import Foundation

// TODO: weft needs to be stored in contiguous memory
// TODO: totalWeft should be derived from yarnMap
// TODO: ownerWeft
// TODO: make everything a struct?
// TODO: mark all sections where weave is mutated and ensure code-wise that caches always get updated
// TODO: need O(N) integrity check verifying all assertions not encoded into data structure; otherwise, malicious users can corrupt our data
// TODO: ranged deletes
// TODO: ranged inserts (paste) that don't require looking up the index for each atom (insert whole causal tree)
// TODO: (eventually) baseline garbage collection

/* Complexity Consideration
 Most common ops:
     > N = all ops, n = yarn ops, S = number of sites (<< N)
     * get array index of atom id
         * yarns: O(1), if we keep the index around
         * weave: O(N)
         * 2weav: O(1)
     * iterate yarn, start to end
         * yarns: O(n)
         * weave: O(N*log(N)) = O(N*log(N))+O(N), first to generate sorted weave, then to iterate it; should be cached; MAKE SURE SORTING ALGO DOESN'T DO N^2 WORST CASE!
         * 2weav: O(n)
     * insert/delete (atom id)
         * yarns: O(n)
         * weave: O(N) = O(N)+O(N), first to find atom, then to modify the array
         * 2weav: O(N) = O(N)+O(N)
     * generate awareness weft
         > for each atom, find all cross-site atoms <= atom in yarn and add to next iteration
         > at worst, we look at evey single atom and iterate every single yarn, assuming cached
         > however, no more than the total yarn size will ever be iterated
         * yarns: O(N) = O(N+S*n), iterating all yarn atoms & all connected atoms and O(1) updating a "max processed" weft
         * weave: O(N*log(N)) = O(N*log(N))+O(N), for generating yarn data structure and then doing the above
         * 2weav: O(N)
     * read segment to construct string, from atom id
         * yarns: O(N^2) = O(N*N)+O(N), assuming worst case awareness resolution (every item) -- but more likely O(N*log(N))-ish
         * weave: O(N) = O(N)+k, find the atom and then simply iterate
         * 2weav: O(N)
     > ideas: keep sorted weft around? same as keeping yarns, but O(N) insert instead of O(1)
     > alternatively, with the yarn technique: can awareness be generated for the entire graph in O(N)? space would be O(N*S) though, potentially up to O(N^2)
 */

protocol CausalTreeSiteUUIDT: DefaultInitializable, CustomStringConvertible, Hashable, Zeroable, Comparable {}
protocol CausalTreeValueT: DefaultInitializable, CustomStringConvertible, CausalTreeAtomPrintable {}

typealias SiteId = Int16
typealias Clock = Int64

// no other atoms can have these clock numbers
let NullSite: SiteId = SiteId(SiteId.max)
let ControlSite: SiteId = SiteId(0)
let NullClock: Clock = Clock(0)
let StartClock: Clock = Clock(1)
let EndClock: Clock = Clock(2)

////////////////////////
// MARK: -
// MARK: - Causal Tree -
// MARK: -
////////////////////////

final class CausalTree <SiteUUIDT: CausalTreeSiteUUIDT, ValueT: CausalTreeValueT> : CvRDT, NSCopying, CustomDebugStringConvertible, ApproxSizeable
{
    typealias SiteIndexT = SiteIndex<SiteUUIDT>
    typealias WeaveT = Weave<SiteUUIDT,ValueT>
    
    // these are separate b/c they are serialized separately and grow separately -- and, really, are separate CRDTs
    var siteIndex: SiteIndexT = SiteIndexT()
    var weave: WeaveT
    
    init(owner: SiteUUIDT, clock: Clock, mapping: inout ContiguousArray<SiteIndexT.SiteIndexKey>, weave: inout ContiguousArray<WeaveT.Atom>)
    {
        self.siteIndex = SiteIndexT(mapping: &mapping)
        let id = self.siteIndex.addSite(owner, withClock: clock) //if owner exists, will simply fetch the id
        self.weave = WeaveT(owner: id, weave: &weave)
    }
    
    // starting from scratch
    init(site: SiteUUIDT, clock: Clock)
    {
        self.siteIndex = SiteIndexT()
        let id = self.siteIndex.addSite(site, withClock: clock)
        self.weave = WeaveT(owner: id)
    }
    
    public func copy(with zone: NSZone? = nil) -> Any
    {
        let returnTree = CausalTree<SiteUUIDT,ValueT>(site: SiteUUIDT.zero, clock: 0)
        returnTree.siteIndex = self.siteIndex.copy(with: nil) as! SiteIndex<SiteUUIDT>
        returnTree.weave = self.weave.copy(with: nil) as! Weave<SiteUUIDT,ValueT>
        return returnTree
    }
    
    func ownerUUID() -> SiteUUIDT
    {
        let uuid = siteIndex.site(weave.owner)
        assert(uuid != nil, "could not find uuid for owner")
        return uuid!
    }
    
    // WARNING: the inout tree will be mutated, so make absolutely sure it's a copy you're willing to waste!
    func integrate(_ v: inout CausalTree)
    {
        // an incoming causal tree might have added sites, and our site ids are distributed in lexicographic-ish order,
        // so we may need to remap some site ids if the orders no longer line up
        func remapIndices(localTree: CausalTree, remoteSiteIndex: SiteIndexT)
        {
            let oldSiteIndex = localTree.siteIndex.copy() as! SiteIndexT
            var remoteSiteIndexPointer = remoteSiteIndex
            
            let firstDifferentIndex = localTree.siteIndex.integrateReturningFirstDiffIndex(&remoteSiteIndexPointer)
            var remapMap: [SiteId:SiteId] = [:]
            if let index = firstDifferentIndex
            {
                let newMapping = localTree.siteIndex.siteMapping()
                for i in index..<oldSiteIndex.siteCount()
                {
                    let oldSite = SiteId(i)
                    let newSite = newMapping[oldSiteIndex.site(oldSite)!]
                    remapMap[oldSite] = newSite
                }
            }
            localTree.weave.remapIndices(remapMap)
        }
        
        remapIndices(localTree: self, remoteSiteIndex: v.siteIndex)
        remapIndices(localTree: v, remoteSiteIndex: self.siteIndex) //to account for concurrently added sites
        
        weave.integrate(&v.weave)
    }
    
    func validate() -> Bool
    {
        let indexValid = siteIndex.validate()
        let weaveValid = weave.validate()
        // TODO: check that site mapping corresponds to weave sites
        
        return indexValid && weaveValid
    }
    
    func superset(_ v: inout CausalTree) -> Bool
    {
        return siteIndex.superset(&v.siteIndex) && weave.superset(&v.weave)
    }
    
    var debugDescription: String
    {
        get
        {
            return "Sites: \(siteIndex.debugDescription), Weave: \(weave.debugDescription)"
        }
    }
    
    func sizeInBytes() -> Int
    {
        return siteIndex.sizeInBytes() + weave.sizeInBytes()
    }
}

///////////////////////
// MARK: -
// MARK: - Site Index -
// MARK: -
///////////////////////

final class SiteIndex <SiteUUIDT: CausalTreeSiteUUIDT> : CvRDT, NSCopying, CustomDebugStringConvertible, ApproxSizeable
{
    struct SiteIndexKey: Comparable
    {
        let clock: Clock //assuming ~ clock sync, allows us to rewrite only last few ids at most, on average
        let id: SiteUUIDT
        
        // PERF: is comparing UUID strings quick enough?
        public static func <(lhs: SiteIndexKey, rhs: SiteIndexKey) -> Bool
        {
            return (lhs.clock == rhs.clock ? lhs.id < rhs.id : lhs.clock < rhs.clock)
        }
        public static func <=(lhs: SiteIndexKey, rhs: SiteIndexKey) -> Bool
        {
            return (lhs.clock == rhs.clock ? lhs.id <= rhs.id : lhs.clock <= rhs.clock)
        }
        public static func >=(lhs: SiteIndexKey, rhs: SiteIndexKey) -> Bool
        {
            return (lhs.clock == rhs.clock ? lhs.id >= rhs.id : lhs.clock >= rhs.clock)
        }
        public static func >(lhs: SiteIndexKey, rhs: SiteIndexKey) -> Bool
        {
            return (lhs.clock == rhs.clock ? lhs.id > rhs.id : lhs.clock > rhs.clock)
        }
        public static func ==(lhs: SiteIndexKey, rhs: SiteIndexKey) -> Bool
        {
            return lhs.id == rhs.id && lhs.clock == rhs.clock
        }
    }
    
    // we assume this is always sorted in lexicographic order -- first by clock, then by UUID
    private var mapping: ContiguousArray<SiteIndexKey> = []
    
    init(mapping: inout ContiguousArray<SiteIndexKey>)
    {
        assert({
            let sortedMapping = mapping.sorted()
            var allMatch = true
            for i in 0..<mapping.count
            {
                if mapping[i] != sortedMapping[i]
                {
                    allMatch = false
                    break
                }
            }
            return allMatch
        }(), "mapping not sorted")
        assert(mapping[0] == SiteIndexKey(clock: 0, id: SiteUUIDT.zero), "mapping does not have control site")
        self.mapping = mapping
    }
    
    // starting from scratch
    init()
    {
        let _ = addSite(SiteUUIDT.zero, withClock: 0)
    }
    
    public func copy(with zone: NSZone? = nil) -> Any
    {
        let returnValue = SiteIndex<SiteUUIDT>()
        returnValue.mapping = self.mapping
        return returnValue
    }
    
    // Complexity: O(S)
    func siteMapping() -> [SiteUUIDT:SiteId]
    {
        var returnMap: [SiteUUIDT:SiteId] = [:]
        for i in 0..<mapping.count
        {
            returnMap[mapping[i].id] = SiteId(i)
        }
        return returnMap
    }
    
    // Complexity: O(1)
    func siteCount() -> Int
    {
        return mapping.count
    }
    
    // Complexity: O(1)
    func site(_ siteId: SiteId) -> SiteUUIDT?
    {
        if siteId >= self.mapping.count
        {
            return nil
        }
        return self.mapping[Int(siteId)].id
    }
    
    // PERF: use binary search
    // Complexity: O(S)
    func addSite(_ id: SiteUUIDT, withClock clock: Clock) -> SiteId
    {
        let newKey = SiteIndexKey(clock: clock, id: id)
        
        let index = mapping.index
        { (key: SiteIndexKey) -> Bool in
            key >= newKey
        }
        
        if let aIndex = index
        {
            if mapping[aIndex] == newKey
            {
                return SiteId(aIndex)
            }
            else
            {
                mapping.insert(newKey, at: aIndex)
                return SiteId(aIndex)
            }
        }
        else
        {
            mapping.append(newKey)
            return SiteId(SiteId(mapping.count - 1))
        }
    }
    
    func integrate(_ v: inout SiteIndex)
    {
        let _ = integrateReturningFirstDiffIndex(&v)
    }
    
    // returns first changed site index, after and including which, site indices in weave have to be rewritten; nil means no edit or empty
    // Complexity: O(S)
    fileprivate func integrateReturningFirstDiffIndex(_ v: inout SiteIndex) -> Int?
    {
        var firstEdit: Int? = nil
        
        var i = 0
        var j = 0
        
        while j < v.mapping.count
        {
            if i == self.mapping.count
            {
                // v has more sites than us, keep adding until we get to the end
                self.mapping.insert(v.mapping[j], at: i)
                if firstEdit == nil { firstEdit = i }
                i += 1
                j += 1
            }
            else if self.mapping[i] > v.mapping[j]
            {
                // v has new data, integrate
                self.mapping.insert(v.mapping[j], at: i)
                if firstEdit == nil { firstEdit = i }
                i += 1
                j += 1
            }
            else if self.mapping[i] < v.mapping[j]
            {
                // we have newer data, skip
                i += 1
            }
            else
            {
                // data is the same, all is well
                i += 1
                j += 1
            }
        }
        
        return firstEdit
    }
    
    func validate() -> Bool
    {
        for i in 0..<mapping.count
        {
            if i > 0
            {
                if !(mapping[i-1] < mapping[i])
                {
                    return false
                }
            }
        }
        
        return true
    }
    
    func superset(_ v: inout SiteIndex) -> Bool
    {
        if siteCount() < v.siteCount()
        {
            return false
        }
        
        let uuids = siteMapping()
        
        for i in 0..<v.mapping.count
        {
            if uuids[v.mapping[i].id] == nil
            {
                return false
            }
        }
        
        return true
    }
    
    var debugDescription: String
    {
        get
        {
            var string = "["
            for i in 0..<mapping.count
            {
                if i != 0
                {
                    string += ", "
                }
                string += "\(i):#\(mapping[i].id.hashValue)"
            }
            string += "]"
            return string
        }
    }
    
    func sizeInBytes() -> Int
    {
        return mapping.count * (MemoryLayout<SiteId>.size + MemoryLayout<UUID>.size)
    }
}

//////////////////
// MARK: -
// MARK: - Weave -
// MARK: -
//////////////////

// an ordered collection of atoms and their trees/yarns, for multiple sites
final class Weave <SiteUUIDT: CausalTreeSiteUUIDT, ValueT: CausalTreeValueT> : CvRDT, NSCopying, CustomDebugStringConvertible, ApproxSizeable
{
    //////////////////
    // MARK: - Types -
    //////////////////
    
    typealias YarnIndex = Int32
    typealias WeaveIndex = Int32
    typealias AllYarnsIndex = Int32 //TODO: this is underused -- mistakenly use YarnsIndex
    
    enum SpecialType: Int8, CustomStringConvertible
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
    
    struct AtomId: Equatable, Comparable, CustomStringConvertible
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
        static func <(lhs: Weave<SiteUUIDT, ValueT>.AtomId, rhs: Weave<SiteUUIDT, ValueT>.AtomId) -> Bool {
            return (lhs.site == rhs.site ? lhs.index < rhs.index : lhs.site < rhs.site)
        }
    }
    
    struct Atom: CustomStringConvertible
    {
        let site: SiteId
        let causingSite: SiteId
        let index: YarnIndex
        let causingIndex: YarnIndex
        let clock: Clock //not required, but possibly useful for user
        let value: ValueT
        let reference: AtomId //a "child", or weak ref, not part of the DFS, e.g. a commit pointer or the closing atom of a segment
        let type: SpecialType
        
        init(id: AtomId, cause: AtomId, type: SpecialType, clock: Clock, value: ValueT, reference: AtomId = NullAtomId)
        {
            self.site = id.site
            self.causingSite = cause.site
            self.index = id.index
            self.causingIndex = cause.index
            self.type = type
            self.clock = clock
            self.value = value
            self.reference = reference
        }
        
        var id: AtomId
        {
            get
            {
                return AtomId(site: site, index: index)
            }
        }
        
        var cause: AtomId
        {
            get
            {
                return AtomId(site: causingSite, index: causingIndex)
            }
        }
        
        var description: String
        {
            get
            {
                return "\(id)-\(cause)"
            }
        }
    }
    
    // TODO: I don't like that this tiny structure has to be malloc'd
    struct Weft: Equatable, Comparable, CustomStringConvertible
    {
        private(set) var mapping: [SiteId:YarnIndex] = [:]
        
        mutating func update(site: SiteId, index: YarnIndex)
        {
            if site == Weave.NullAtomId.site { return }
            mapping[site] = max(mapping[site] ?? NullIndex, index)
        }
        
        mutating func update(atom: AtomId) {
            if atom == Weave.NullAtomId { return }
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
            if atom == Weave.NullAtomId
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
    
    enum CommitStrategyType
    {
        case onCausedByRemoteSite
        case onSync
    }
    
    //////////////////////
    // MARK: - Constants -
    //////////////////////
    
    static var NullIndex: YarnIndex { get { return -1 }} //max (NullIndex, index) needs to always return index
    static var NullAtomId: AtomId { return AtomId(site: NullSite, index: NullIndex) }
    
    static var CommitStrategy: CommitStrategyType { return .onCausedByRemoteSite }
    
    /////////////////
    // MARK: - Data -
    /////////////////
    
    var owner: SiteId
    
    // CONDITION: this data must be the same locally as in the cloud, i.e. no object oriented cache layers etc.
    private var atoms: ContiguousArray<Atom> = [] //solid chunk of memory for optimal performance
    
    ///////////////////
    // MARK: - Caches -
    ///////////////////
    
    // these must be updated whenever the canonical data structures above are mutated; do not have to be the same on different sites
    private var weft: Weft = Weft()
    private var yarns: ContiguousArray<Atom> = []
    private var yarnsMap: [SiteId:CountableClosedRange<Int>] = [:]
    
    //////////////////////
    // MARK: - Lifecycle -
    //////////////////////
    
    // Complexity: O(N * log(N))
    init(owner: SiteId, weave: inout ContiguousArray<Atom>)
    {
        assert(false, "still need to implement commit to originating yarn")
        self.owner = owner
        self.atoms = weave
        
        generateCache: do
        {
            generateYarns: do
            {
                var yarns = weave
                yarns.sort(by:
                { (a1: Atom, a2: Atom) -> Bool in
                    if a1.id.site < a2.id.site
                    {
                        return true
                    }
                    else if a1.id.site > a2.id.site
                    {
                        return false
                    }
                    else
                    {
                        return a1.id.index < a2.id.index
                    }
                })
                self.yarns = yarns
            }
            processYarns: do
            {
                timeMe(
                {
                    var weft = Weft()
                    var yarnsMap = [SiteId:CountableClosedRange<Int>]()
                    
                    // PERF: we don't have to update each atom -- can simply detect change
                    for i in 0..<self.yarns.count
                    {
                        if let range = yarnsMap[self.yarns[i].site]
                        {
                            yarnsMap[self.yarns[i].site] = range.lowerBound...i
                        }
                        else
                        {
                            yarnsMap[self.yarns[i].site] = i...i
                        }
                        weft.update(atom: self.yarns[i].id)
                    }
                    
                    self.weft = weft
                    self.yarnsMap = yarnsMap
                }, "CacheGen")
            }
        }
    }
    
    // starting from scratch
    init(owner: SiteId)
    {
        self.owner = owner
        
        addBaseYarn: do
        {
            let siteId = ControlSite
            
            let startAtomId = AtomId(site: siteId, index: 0)
            let endAtomId = AtomId(site: siteId, index: 1)
            let startAtom = Atom(id: startAtomId, cause: startAtomId, type: .start, clock: StartClock, value: ValueT())
            let endAtom = Atom(id: endAtomId, cause: Weave.NullAtomId, type: .end, clock: EndClock, value: ValueT(), reference: startAtomId)
            
            atoms.append(startAtom)
            updateCaches(withAtom: startAtom)
            atoms.append(endAtom)
            updateCaches(withAtom: endAtom)
            
            assert(atomWeaveIndex(startAtomId) == startAtomId.index)
            assert(atomWeaveIndex(endAtomId) == endAtomId.index)
        }
    }
    
    public func copy(with zone: NSZone? = nil) -> Any
    {
        let returnWeave = Weave(owner: self.owner)
        
        // TODO: verify that these structs do copy as expected
        returnWeave.owner = self.owner
        returnWeave.atoms = self.atoms
        returnWeave.weft = self.weft
        returnWeave.yarns = self.yarns
        returnWeave.yarnsMap = self.yarnsMap
        
        return returnWeave
    }
    
    /////////////////////
    // MARK: - Mutation -
    /////////////////////
    
    func addAtom(withValue value: ValueT, causedBy cause: AtomId, atTime clock: Clock) -> AtomId?
    {
        return _debugAddAtom(atSite: self.owner, withValue: value, causedBy: cause, atTime: clock)
    }
    func _debugAddAtom(atSite: SiteId, withValue value: ValueT, causedBy cause: AtomId, atTime clock: Clock, noCommit: Bool = false) -> AtomId?
    {
        if !noCommit && type(of: self).CommitStrategy == .onCausedByRemoteSite
        {
            // find all siblings and make sure awareness of their yarns is committed
            // AB: note that this works because commit atoms are non-causal, ergo we do not need to sort them all the way down the DFS chain
            // AB: could just commit the sibling atoms themselves, but why not get the whole yarn? more truthful!
            // PERF: O(N) -- is this too slow?
            var childrenSites = Set<SiteId>()
            for i in 0..<atoms.count
            {
                if atoms[i].cause == cause
                {
                    childrenSites.insert(atoms[i].site)
                }
            }
            for site in childrenSites
            {
                let _ = addCommit(fromSite: atSite, toSite: site, atTime: clock)
            }
        }
        
        let atom = Atom(id: generateNextAtomId(forSite: atSite), cause: cause, type: .none, clock: clock, value: value)
        let e = integrateAtom(atom)
        
        return (e ? atom.id : nil)
    }
    
    func deleteAtom(_ atomId: AtomId, atTime time: Clock) -> AtomId?
    {
        guard let index = atomYarnsIndex(atomId) else
        {
            return nil
        }
        
        let targetAtom = yarns[Int(index)]
        
        if targetAtom.type != .none
        {
            return nil
        }
        
        let deleteAtom = Atom(id: generateNextAtomId(forSite: owner), cause: atomId, type: .delete, clock: time, value: ValueT())
        
        let e = integrateAtom(deleteAtom)
        return (e ? deleteAtom.id : nil)
    }
    
    // adds awareness atom, usually prior to another add to ensure convergent sibling conflict resolution
    func addCommit(fromSite: SiteId, toSite: SiteId, atTime time: Clock) -> AtomId?
    {
        if fromSite == toSite
        {
            return nil
        }
        
        guard let lastCommitSiteYarnsIndex = lastSiteAtomYarnsIndex(toSite) else
        {
            return nil
        }
        
        // TODO: check if we're already up-to-date, to avoid duplicate commits... though, this isn't really important
        
        let lastCommitSiteAtom = yarns[Int(lastCommitSiteYarnsIndex)]
        let commitAtom = Atom(id: generateNextAtomId(forSite: fromSite), cause: Weave.NullAtomId, type: .commit, clock: time, value: ValueT(), reference: lastCommitSiteAtom.id)
        
        let e = integrateAtom(commitAtom)
        return (e ? commitAtom.id : nil)
    }
    
    private func updateCaches(withAtom atom: Atom)
    {
        updateCaches(withAtom: atom, orFromWeave: nil)
    }
    private func updateCaches(afterMergeWithWeave weave: Weave)
    {
        updateCaches(withAtom: nil, orFromWeave: weave)
    }
    
    // no splatting, so we have to do this the ugly way
    // Complexity: O(N * c), where c is 1 for the case of a single atom
    fileprivate func updateCaches(withAtom a: Atom?, orFromWeave w: Weave?)
    {
        assert((a != nil || w != nil))
        assert((a != nil && w == nil) || (a == nil && w != nil))
        
        if let atom = a
        {
            if let existingRange = yarnsMap[atom.site]
            {
                assert((existingRange.upperBound - existingRange.lowerBound) + 1 == atom.id.index, "adding atom out of order")
                
                let newUpperBound = existingRange.upperBound + 1
                yarns.insert(atom, at: newUpperBound)
                yarnsMap[atom.site] = existingRange.lowerBound...newUpperBound
                for (site,range) in yarnsMap
                {
                    if range.lowerBound >= newUpperBound
                    {
                        yarnsMap[site] = (range.lowerBound + 1)...(range.upperBound + 1)
                    }
                }
                weft.update(atom: atom.id)
            }
            else
            {
                assert(atom.id.index == 0, "adding atom out of order")
                
                yarns.append(atom)
                yarnsMap[atom.site] = (yarns.count - 1)...(yarns.count - 1)
                weft.update(atom: atom.id)
            }
        }
        else if let weave = w
        {
            // O(S * log(S))
            let sortedSiteMap = Array(yarnsMap).sorted(by: { (k1, k2) -> Bool in
                return k1.value.upperBound < k2.value.lowerBound
            })
            
            // O(N * c)
            modifyKnownSites: do
            {
                // we go backwards to preserve the yarnsMap indices
                for i in (0..<sortedSiteMap.count).reversed()
                {
                    let site = sortedSiteMap[i].key
                    let localRange = sortedSiteMap[i].value
                    let localLength = localRange.count
                    let remoteLength = weave.yarnsMap[site]?.count ?? 0
                    
                    assert(localLength != 0, "we should not have 0-length yarns")
                    
                    if remoteLength > localLength
                    {
                        assert({
                            let yarn = weave.yarn(forSite: site) //AB: risky w/yarnsMap mutation, but logic is sound & this is in debug
                            let indexOffset = localLength - 1
                            let yarnIndex = yarn.startIndex + indexOffset
                            return yarns[localRange.upperBound].id == yarn[yarnIndex].id
                        }(), "end atoms for yarns do not match")
                        
                        let diff = remoteLength - localLength
                        let remoteRange = weave.yarnsMap[site]!
                        let remoteDiffRange = (remoteRange.lowerBound + localLength)...remoteRange.upperBound
                        let remoteInsertContents = weave.yarn(forSite: site)[remoteDiffRange]
                        
                        yarns.insert(contentsOf: remoteInsertContents, at: localRange.upperBound + 1)
                        yarnsMap[site] = localRange.lowerBound...(localRange.upperBound + diff)
                        var j = i + 1; while j < sortedSiteMap.count
                        {
                            // the indices we've already processed need to be shifted as well
                            let shiftedSite = sortedSiteMap[j].key
                            yarnsMap[shiftedSite] = (yarnsMap[shiftedSite]!.lowerBound + diff)...(yarnsMap[shiftedSite]!.upperBound + diff)
                            j += 1
                        }
                        weft.update(atom: yarns[yarnsMap[site]!.upperBound].id)
                    }
                }
            }
            
            // O(N) + O(S)
            appendUnknownSites: do
            {
                var unknownSites = Set<SiteId>()
                for k in weave.yarnsMap { if yarnsMap[k.key] == nil { unknownSites.insert(k.key) }}
                
                for site in unknownSites
                {
                    let remoteInsertRange = weave.yarnsMap[site]!
                    let remoteInsertContents = weave.yarn(forSite: site)[remoteInsertRange]
                    let newLocalRange = yarns.count...(yarns.count + remoteInsertRange.count - 1)
                    
                    yarns.insert(contentsOf: remoteInsertContents, at: yarns.count)
                    yarnsMap[site] = newLocalRange
                    weft.update(atom: yarns[yarnsMap[site]!.upperBound].id)
                }
            }
        }
        
        assert(atoms.count == yarns.count, "yarns cache was corrupted on update")
    }
    
    // Complexity: O(1)
    private func generateNextAtomId(forSite site: SiteId) -> AtomId
    {
        if let lastIndex = weft.mapping[site]
        {
            return AtomId(site: site, index: lastIndex + 1)
        }
        else
        {
            return AtomId(site: site, index: 0)
        }
    }
    
    ////////////////////////
    // MARK: - Integration -
    ////////////////////////
    
    // TODO: make a protocol that atom, value, etc. conform to
    func remapIndices(_ indices: [SiteId:SiteId])
    {
        func updateAtom(inArray array: inout ContiguousArray<Atom>, atIndex i: Int)
        {
            var id: AtomId? = nil
            var cause: AtomId? = nil
            var reference: AtomId? = nil
            
            if let newOwner = indices[array[i].site]
            {
                id = AtomId(site: newOwner, index: array[i].index)
            }
            if let newOwner = indices[array[i].causingSite]
            {
                cause = AtomId(site: newOwner, index: array[i].causingIndex)
            }
            if let newOwner = indices[array[i].reference.site]
            {
                reference = AtomId(site: newOwner, index: array[i].reference.index)
            }
            
            if id != nil || cause != nil
            {
                array[i] = Atom(id: id ?? array[i].id, cause: cause ?? array[i].cause, type: array[i].type, clock: array[i].clock, value: array[i].value, reference: reference ?? array[i].reference)
            }
        }
        
        if let newOwner = indices[self.owner]
        {
            self.owner = newOwner
        }
        for i in 0..<self.atoms.count
        {
            updateAtom(inArray: &self.atoms, atIndex: i)
        }
        weft: do
        {
            var newWeft = Weft()
            for v in self.weft.mapping
            {
                if let newOwner = indices[v.key]
                {
                    newWeft.update(site: newOwner, index: v.value)
                }
                else
                {
                    newWeft.update(site: v.key, index: v.value)
                }
            }
            self.weft = newWeft
        }
        for i in 0..<self.yarns.count
        {
            updateAtom(inArray: &self.yarns, atIndex: i)
        }
        yarnsMap: do
        {
            var newYarnsMap = [SiteId:CountableClosedRange<Int>]()
            for v in self.yarnsMap
            {
                if let newOwner = indices[v.key]
                {
                    newYarnsMap[newOwner] = v.value
                }
                else
                {
                    newYarnsMap[v.key] = v.value
                }
            }
            self.yarnsMap = newYarnsMap
        }
    }
    
    // adds atom as firstmost child of head atom, or appends to end if non-causal; lets us treat weave like an actual tree
    // Complexity: O(N)
    private func integrateAtom(_ atom: Atom) -> Bool
    {
        let headIndex: Int
        let causeAtom = atomForId(atom.cause)
        
        if causeAtom != nil && causeAtom!.type.childless
        {
            assert(false, "appending atom to non-causal parent")
            return false
        }
        
        if atom.type.unparented && causeAtom != nil
        {
            assert(false, "unparented atom still has a cause")
            return false
        }
        
        if atom.type.unparented, let nullableIndex = unparentedAtomWeaveInsertionIndex(atom.id)
        {
            headIndex = Int(nullableIndex) - 1 //subtract to avoid special-casing math below
        }
        else if let aIndex = atomWeaveIndex(atom.cause)
        {
            headIndex = Int(aIndex)
        }
        else
        {
            assert(false, "could not determine location of causing atom")
            return false
        }
        
        if !atom.type.unparented
        {
            if headIndex < atoms.count
            {
                let prevAtom = atoms[headIndex]
                assert(atom.cause == prevAtom.id, "atom is not attached to the correct parent")
            }
            if headIndex + 1 < atoms.count
            {
                let nextAtom = atoms[headIndex + 1]
                if nextAtom.cause == atom.cause //siblings
                {
                    assert(Weave.atomSiblingOrder(a1: atom, a2: nextAtom, a1MoreAwareThanA2: true), "atom is not ordered correctly")
                }
            }
        }
        
        // no awareness recalculation, just assume it belongs in front
        atoms.insert(atom, at: headIndex + 1)
        updateCaches(withAtom: atom)
        
        return true
    }
    
    enum MergeError
    {
        case invalidUnparentedAtomComparison
        case invalidAwareSiblingComparison
        case invalidUnawareSiblingComparison
        case unknownSiblingComparison
        case unknownTypeComparison
    }
    
    // we assume that indices have been correctly remapped at this point
    // we also assume that remote weave was correctly generated and isn't somehow corrupted
    // IMPORTANT: this function should only be called with a validated weave, because we do not check consistency here
    // PERF: don't need to generate entire weave + caches... just need O(N) awareness weft generation + weave
    func integrate(_ v: inout Weave<SiteUUIDT,ValueT>)
    {
        typealias Insertion = (localIndex: WeaveIndex, remoteRange: CountableClosedRange<Int>)
        
        // in order of traversal, so make sure to iterate backwards when actually mutating the weave to keep indices correct
        var insertions: [Insertion] = []
        
        let local = weave()
        let remote = v.weave()
        let localWeft = completeWeft()
        let remoteWeft = v.completeWeft()
        
        var i = local.startIndex
        var j = remote.startIndex
        
        // instead of inserting atoms one-by-one -- an O(N) operation -- we accumulate change ranges and process
        // them later; one of these functions is called with each atom
        var currentInsertion: Insertion?
        func insertAtom(atLocalIndex: WeaveIndex, fromRemoteIndex: WeaveIndex)
        {
            if let insertion = currentInsertion
            {
                assert(fromRemoteIndex == insertion.remoteRange.upperBound + 1, "skipped some atoms without committing")
                currentInsertion = (insertion.localIndex, insertion.remoteRange.lowerBound...Int(fromRemoteIndex))
            }
            else
            {
                currentInsertion = (atLocalIndex, Int(fromRemoteIndex)...Int(fromRemoteIndex))
            }
        }
        func commitInsertion()
        {
            if let insertion = currentInsertion
            {
                insertions.append(insertion)
                currentInsertion = nil
            }
        }
        
        // here be the actual merge algorithm
        while j < remote.endIndex
        {
            var mergeError: MergeError? = nil
            
            // past local bounds in unparented atom territory, so just append remote
            if i >= local.endIndex
            {
                insertAtom(atLocalIndex: WeaveIndex(i), fromRemoteIndex: WeaveIndex(j))
                j += 1
            }
                
            // simple equality
            else if local[i].id == remote[j].id
            {
                commitInsertion()
                i += 1
                j += 1
            }
                
            // testing for unparented section of weave
            else if local[i].type.unparented && remote[j].type.unparented
            {
                let ijOrder = Weave.unparentedAtomOrder(a1: local[i].id, a2: remote[j].id)
                let jiOrder = Weave.unparentedAtomOrder(a1: remote[j].id, a2: local[i].id)
                
                if !ijOrder && !jiOrder
                {
                    // atoms are equal, simply continue
                    commitInsertion()
                    i += 1
                    j += 1
                }
                else if ijOrder
                {
                    // local < remote
                    commitInsertion()
                    i += 1
                }
                else if jiOrder
                {
                    // remote < local
                    insertAtom(atLocalIndex: WeaveIndex(i), fromRemoteIndex: WeaveIndex(j))
                    j += 1
                }
                else
                {
                    mergeError = .invalidUnparentedAtomComparison
                }
            }
                
            // assuming local weave is valid, we can just insert our local changes
            else if localWeft.included(remote[j].id)
            {
                // local < remote, fast forward through to the next matching sibling
                // AB: this and the below block would be more "correct" with causal blocks, but those
                //     require expensive awareness derivation; this is functionally equivalent since we know
                //     that one is aware of the other, so we have to reach the other one eventually
                //     (barring corruption)
                repeat {
                    commitInsertion()
                    i += 1
                } while local[i].id != remote[j].id
            }
                
            // assuming remote weave is valid, we can just insert remote's changes
            else if remoteWeft.included(local[i].id)
            {
                // remote < local, fast forward through to the next matching sibling
                repeat {
                    insertAtom(atLocalIndex: WeaveIndex(i), fromRemoteIndex: WeaveIndex(j))
                    j += 1
                } while local[i].id != remote[j].id
            }
                
            // testing for unaware sibling merge
            else if
                local[i].cause == remote[j].cause,
                let localAwareness = awarenessWeft(forAtom: local[i].id),
                let remoteAwareness = v.awarenessWeft(forAtom: remote[j].id),
                let localCausalBlock = causalBlock(forAtomIndexInWeave: WeaveIndex(i), withPrecomputedAwareness: localAwareness),
                let remoteCausalBlock = v.causalBlock(forAtomIndexInWeave: WeaveIndex(j), withPrecomputedAwareness: remoteAwareness)
            {
                let ijOrder = Weave.atomSiblingOrder(a1: local[i], a2: remote[j], a1MoreAwareThanA2: localAwareness > remoteAwareness)
                let jiOrder = Weave.atomSiblingOrder(a1: remote[j], a2: local[i], a1MoreAwareThanA2: remoteAwareness > localAwareness)
                
                if !ijOrder && !jiOrder
                {
                    mergeError = .invalidUnawareSiblingComparison
                }
                else if ijOrder
                {
                    processLocal: do
                    {
                        commitInsertion()
                        i += localCausalBlock.count
                    }
                }
                else if jiOrder
                {
                    for _ in 0..<remoteCausalBlock.count
                    {
                        insertAtom(atLocalIndex: WeaveIndex(i), fromRemoteIndex: WeaveIndex(j))
                        j += 1
                    }
                }
                else
                {
                    mergeError = .invalidUnawareSiblingComparison
                }
            }
                
            else
            {
                mergeError = .unknownTypeComparison
            }
            
            // this should never happen in theory, but in practice... let's not trust our algorithms too much
            if let error = mergeError
            {
                assert(false, "atoms unequal, unaware, and not siblings -- cannot merge (error \(error))")
                // TODO: return false here
            }
            
//            if i >= local.endIndex
//            {
//                // we're past local bounds, so just append remote
//                insertAtom(atLocalIndex: WeaveIndex(i), fromRemoteIndex: WeaveIndex(j))
//                j += 1
//            }
//            else if local[i].id != remote[j].id
//            {
//                // make sure non-causal atoms are pushed to the end of the weave, and that they're correctly ordered
//                if local[i].type.unparented || remote[j].type.unparented
//                {
//                    if local[i].type.unparented && !remote[j].type.unparented
//                    {
//                        assert(local[i].type == .end, "both sites should be past the end marker at this point")
//                        insertAtom(atLocalIndex: WeaveIndex(i), fromRemoteIndex: WeaveIndex(j))
//                        j += 1
//                    }
//                    else if !local[i].type.unparented && remote[j].type.unparented
//                    {
//                        assert(remote[j].type == .end, "both sites should be past the end marker at this point")
//                        commitInsertion()
//                        i += 1
//                    }
//                    else
//                    {
//                        if local[i].id < remote[j].id
//                        {
//                            commitInsertion()
//                            i += 1
//                        }
//                        else
//                        {
//                            insertAtom(atLocalIndex: WeaveIndex(i), fromRemoteIndex: WeaveIndex(j))
//                            j += 1
//                        }
//                    }
//                }
//                else if remoteWeft.included(local[i].id)
//                {
//                    // remote is aware of local atom, so order is correct: stick remote atom before local atom
//                    // i.e., remote can keep going until it hits the local atom
//                    insertAtom(atLocalIndex: WeaveIndex(i), fromRemoteIndex: WeaveIndex(j))
//                    j += 1
//                }
//                else if localWeft.included(remote[j].id)
//                {
//                    // local is aware of remote atom, so don't have to do anything: new local content
//                    // i.e., local can keep going until it hits the remote atom
//                    commitInsertion()
//                    i += 1
//                }
//                else
//                {
//                    // unaware siblings
//
//                    guard let localAwareness = awarenessWeft(forAtom: local[i].id),
//                        let remoteAwareness = v.awarenessWeft(forAtom: remote[j].id) else
//                    {
//                        // TODO: integration error/failure
//                        assert(false)
//                        return
//                    }
//
//                    guard let localCausalBlock = causalBlock(forAtomIndexInWeave: WeaveIndex(i), withPrecomputedAwareness: localAwareness),
//                        let remoteCausalBlock = v.causalBlock(forAtomIndexInWeave: WeaveIndex(j), withPrecomputedAwareness: remoteAwareness) else
//                    {
//                        // TODO: integration error/failure
//                        assert(false)
//                        return
//                    }
//
//                    if localAwareness > remoteAwareness
//                    {
//                        processLocal: do
//                        {
//                            commitInsertion()
//                            i += localCausalBlock.count
//                        }
//                    }
//                    else
//                    {
//                        for _ in 0..<remoteCausalBlock.count
//                        {
//                            insertAtom(atLocalIndex: WeaveIndex(i), fromRemoteIndex: WeaveIndex(j))
//                            j += 1
//                        }
//                    }
//                }
//            }
//            else
//            {
//                // do nothing, as atoms are the same
//                assert(local[i].cause == remote[j].cause, "matching ids but different causes; index remap error?")
//                commitInsertion()
//                i += 1
//                j += 1
//            }
        }
        commitInsertion() //TODO: maybe avoid commit and just start new range when disjoint interval?
        
        process: do
        {
            // we go in reverse to avoid having to update our indices
            for i in (0..<insertions.count).reversed()
            {
                let remoteContent = remote[insertions[i].remoteRange]
                atoms.insert(contentsOf: remoteContent, at: Int(insertions[i].localIndex))
            }
            updateCaches(afterMergeWithWeave: v)
        }
    }
    
    // note that we only need this for the weave, since yarn positions are not based on causality
    // Complexity: O(<N), i.e. O(UnparentedAtoms)
    func unparentedAtomWeaveInsertionIndex(_ atom: AtomId) -> WeaveIndex?
    {
        // TODO: maybe manually search for last unparented atom instead?
        guard let endAtomIndex = atomWeaveIndex(AtomId(site: ControlSite, index: 1), searchInReverse: true) else
        {
            assert(false, "end atom not found")
            return nil
        }
        
        var i = Int(endAtomIndex); while i < atoms.count
        {
            let unordered = Weave.unparentedAtomOrder(a1: atoms[i].id, a2: atom)
            
            if unordered
            {
                i += 1
            }
            else
            {
                break
            }
        }
        
        return WeaveIndex(i)
    }
    
    func validate() -> Bool
    {
        // TODO: check DFS unparented section/order, DFS consistency, atom type consistency
        return true
    }
    
    // Complexity: O(N^2) or more... heavy stuff
    func assertTreeIntegrity()
    {
        #if DEBUG
            if atoms.count == 0
            {
                return
            }
            
            // returns children
            func bfs(atomIndex: WeaveIndex) -> [WeaveIndex]?
            {
                var returnChildren = [WeaveIndex]()
                let head = weave()[Int(atomIndex)]
                guard let block = causalBlock(forAtomIndexInWeave: atomIndex) else
                {
                    return nil
                }
                for i in block
                {
                    let a = weave()[Int(i)]
                    if a.cause == head.id && a.cause != a.id
                    {
                        returnChildren.append(i)
                    }
                }
                return returnChildren
            }
            
            var visitedArray = Array<Bool>(repeating: false, count: atoms.count)
            
            // check that a) every atom is in the tree, and b) every node's children are correctly ordered
            traverseAtoms: do
            {
                var children = [WeaveIndex(0)]
                
                while !children.isEmpty
                {
                    var nextChildren = [WeaveIndex]()
                    
                    for atom in children
                    {
                        guard let atomChildren = bfs(atomIndex: atom) else
                        {
                            assert(false, "could not get causal block for atom \(atom)")
                            return
                        }
                        verifyChildrenOrder: do
                        {
                            let awarenesses = atomChildren.map { index in awarenessWeft(forAtom: weave()[Int(index)].id)! }
                            for (i,_) in atomChildren.enumerated()
                            {
                                if i > 0 && atoms[i-1].cause == atoms[i].cause
                                {
                                    let a1 = atoms[i-1]
                                    let a2 = atoms[i]
                                    let ordered = Weave.atomSiblingOrder(a1: a1, a2: a2, a1MoreAwareThanA2: awarenesses[i-1]>awarenesses[i])
                                    assert(ordered, "children not sorted")
                                }
                            }
                        }
                        visitedArray[Int(atom)] = true
                        nextChildren.append(contentsOf: atomChildren)
                    }
                    
                    swap(&children, &nextChildren)
                }
            }
            
            traverseUnparentedAtoms: do
            {
                guard let indexOfLastCausalAtom = atomWeaveIndex(AtomId(site: ControlSite, index: 1), searchInReverse: true) else
                {
                    assert(false, "could not find index of last causal atom")
                    return
                }
                
                var i = indexOfLastCausalAtom; while i < atoms.count
                {
                    assert(atoms[Int(i)].type.unparented, "atom at end of weave is parented")
                    assert(atoms[Int(i)].cause == Weave.NullAtomId, "atom at end of weave is parented")
                    visitedArray[Int(i)] = true
                    i += 1
                }
            }
            
            assert(visitedArray.reduce(true) { soFar,val in soFar && val }, "some atoms were not visited")
            
            verifyCache: do
            {
                assert(atoms.count == yarns.count)
                
                visitedArray = Array<Bool>(repeating: false, count: atoms.count)
                var sitesCount = 0
                
                // check that a) every weave atom has a corresponding yarn atom, and b) the yarn atoms are sequential
                verifyYarnsCoverageAndSequentiality: do
                {
                    var p = (-1,-1)
                    for i in 0..<yarns.count
                    {
                        guard let weaveIndex = atomWeaveIndex(yarns[i].id) else
                        {
                            assert(false, "no weave index for atom \(yarns[i].id)")
                            return
                        }
                        visitedArray[Int(weaveIndex)] = true
                        if p.0 != yarns[i].site
                        {
                            assert(yarns[i].index == 0, "non-sequential yarn atom at \(i))")
                            sitesCount += 1
                            if p.0 != -1
                            {
                                assert(weft.mapping[SiteId(p.0)] == YarnIndex(p.1), "weft does not match yarn")
                            }
                        }
                        else
                        {
                            assert(p.1 + 1 == Int(yarns[i].index), "non-sequential yarn atom at \(i))")
                        }
                        p = (Int(yarns[i].site), Int(yarns[i].index))
                    }
                }
                
                assert(visitedArray.reduce(true) { soFar,val in soFar && val }, "some atoms were not visited")
                assert(weft.mapping.count == sitesCount, "weft does not have same counts as yarns")
                
                verifyYarnMapCoverage: do
                {
                    let sortedYarnMap = yarnsMap.sorted { v0,v1 -> Bool in return v0.value.upperBound < v1.value.lowerBound }
                    let totalCount = sortedYarnMap.last!.value.upperBound -  sortedYarnMap.first!.value.lowerBound + 1
                    
                    assert(totalCount == yarns.count, "yarns and yarns map count do not match")
                    
                    for i in 0..<sortedYarnMap.count
                    {
                        if i != 0
                        {
                            assert(sortedYarnMap[i].value.lowerBound == sortedYarnMap[i - 1].value.upperBound + 1, "yarn map is not contiguous")
                        }
                    }
                }
            }
            
            print("CRDT verified!")
        #endif
    }
    
    //////////////////////////
    // MARK: - Basic Queries -
    //////////////////////////
    
    // Complexity: O(1)
    func atomForId(_ atomId: AtomId) -> Atom?
    {
        if let index = atomYarnsIndex(atomId)
        {
            return yarns[Int(index)]
        }
        else
        {
            return nil
        }
    }
    
    // Complexity: O(1)
    func atomYarnsIndex(_ atomId: AtomId) -> AllYarnsIndex?
    {
        if atomId == Weave.NullAtomId
        {
            return nil
        }
        
        if let range = yarnsMap[atomId.site]
        {
            let count = (range.upperBound - range.lowerBound) + 1
            if atomId.index < count
            {
                return AllYarnsIndex(range.lowerBound + Int(atomId.index))
            }
            else
            {
                return nil
            }
        }
        else
        {
            return nil
        }
    }
    
    // Complexity: O(N)
    func atomWeaveIndex(_ atomId: AtomId, searchInReverse: Bool = false) -> WeaveIndex?
    {
        if atomId == Weave.NullAtomId
        {
            return nil
        }
        
        var index: Int? = nil
        let range = (searchInReverse ? (0..<atoms.count).reversed() : (0..<atoms.count).reversed().reversed()) //"type casting", heh
        for i in range
        {
            if atoms[i].id == atomId
            {
                index = i
                break
            }
        }
        return (index != nil ? WeaveIndex(index!) : nil)
    }
    
    // Complexity: O(1)
    func lastSiteAtomYarnsIndex(_ site: SiteId) -> AllYarnsIndex?
    {
        if let range = yarnsMap[site]
        {
            return AllYarnsIndex(range.upperBound)
        }
        else
        {
            return nil
        }
    }
    
    // Complexity: O(N)
    func lastSiteAtomWeaveIndex(_ site: SiteId) -> WeaveIndex?
    {
        var maxIndex: Int? = nil
        for i in 0..<atoms.count
        {
            let a = atoms[i]
            if a.id.site == site
            {
                if let aMaxIndex = maxIndex
                {
                    if a.id.index > atoms[aMaxIndex].id.index
                    {
                        maxIndex = i
                    }
                }
                else
                {
                    maxIndex = i
                }
            }
        }
        return (maxIndex == nil ? nil : WeaveIndex(maxIndex!))
    }
    
    // Complexity: O(1)
    func completeWeft() -> Weft
    {
        return weft
    }
    
    // Complexity: O(1)
    func atomCount() -> Int
    {
        return atoms.count
    }
    
    // Complexity: O(n)
    // WARNING: do not mutate!
    func yarn(forSite site:SiteId) -> ArraySlice<Atom>
    {
        if let yarnRange = yarnsMap[site]
        {
            return yarns[yarnRange]
        }
        else
        {
            return ArraySlice<Atom>()
        }
    }
    
    // Complexity: O(N)
    // WARNING: do not mutate!
    func weave() -> ArraySlice<Atom>
    {
        return atoms[0..<atoms.count]
    }
    
    // i.e., causal tree branch
    // Complexity: O(N)
    func causalBlock(forAtomIndexInWeave index: WeaveIndex, withPrecomputedAwareness preAwareness: Weft? = nil) -> CountableClosedRange<WeaveIndex>?
    {
        assert(index < atoms.count)
        
        let atom = atoms[Int(index)]
        
        // unparented atoms are arranged differently than typical atoms, and thusly don't have any causal blocks
        if atom.type.unparented
        {
            return nil
        }
        
        let awareness: Weft
        
        if let aAwareness = preAwareness
        {
            awareness = aAwareness
        }
        else if let aAwareness = awarenessWeft(forAtom: atom.id)
        {
            awareness = aAwareness
        }
        else
        {
            assert(false)
            return nil
        }
        
        var range: CountableClosedRange<WeaveIndex> = WeaveIndex(index)...WeaveIndex(index)
        
        var i = Int(index) + 1
        while i < atoms.count
        {
            let nextAtomParent = atoms[i].cause
            if nextAtomParent != atom.id && awareness.included(nextAtomParent)
            {
                break
            }
            
            range = range.lowerBound...WeaveIndex(i)
            i += 1
        }
        
        assert(!atom.type.childless || range.count == 1, "childless atom seems to have children")
        
        return range
    }
    
    ////////////////////////////
    // MARK: - Complex Queries -
    ////////////////////////////
    
    // Complexity: O(N)
    func awarenessWeft(forAtom atomId: AtomId) -> Weft?
    {
        // have to make sure atom exists in the first place
        guard let startingAtomIndex = atomYarnsIndex(atomId) else
        {
            return nil
        }
        
        var completedWeft = Weft() //needed to compare against workingWeft to figure out unprocessed atoms
        var workingWeft = Weft() //read-only, used to seed nextWeft
        var nextWeft = Weft() //acquires buildup from unseen workingWeft atom connections for next loop iteration
        
        workingWeft.update(site: atomId.site, index: yarns[Int(startingAtomIndex)].id.index)
        
        while completedWeft != workingWeft
        {
            for (site, _) in workingWeft.mapping
            {
                guard let atomIndex = workingWeft.mapping[site] else
                {
                    assert(false, "atom not found for index")
                    continue
                }
                
                let aYarn = yarn(forSite: site)
                assert(!aYarn.isEmpty, "indexed atom came from empty yarn")
                
                // process each un-processed atom in the given yarn; processing means following any causal links to other yarns
                for i in (0...atomIndex).reversed()
                {
                    // go backwards through the atoms that we haven't processed yet
                    if completedWeft.mapping[site] != nil
                    {
                        guard let completedIndex = completedWeft.mapping[site] else
                        {
                            assert(false, "atom not found for index")
                            continue
                        }
                        if i <= completedIndex
                        {
                            break
                        }
                    }
                    
                    enqueueCausalAtom: do
                    {
                        // get the atom
                        let aIndex = aYarn.startIndex + Int(i)
                        let aAtom = aYarn[aIndex]
                        
                        // AB: since we've added the atomIndex method, these don't appear to be necessary any longer for perf
                        guard aAtom.cause.site != site else
                        {
                            break enqueueCausalAtom //no need to check same-site connections since we're going backwards along the weft anyway
                        }
                        
                        nextWeft.update(site: aAtom.cause.site, index: aAtom.cause.index)
                        nextWeft.update(atom: aAtom.reference) //"weak" references indicate awareness, too!
                    }
                }
            }
            
            // fill in missing gaps
            workingWeft.mapping.forEach(
            { (v: (site: SiteId, index: YarnIndex)) in
                nextWeft.update(site: v.site, index: v.index)
            })
            // update completed weft
            workingWeft.mapping.forEach(
            { (v: (site: SiteId, index: YarnIndex)) in
                completedWeft.update(site: v.site, index: v.index)
            })
            // swap
            swap(&workingWeft, &nextWeft)
        }
        
        // implicit awareness
        completedWeft.update(atom: yarns[Int(startingAtomIndex)].id)
        completedWeft.update(atom: yarns[Int(startingAtomIndex)].cause)
        completedWeft.update(atom: yarns[Int(startingAtomIndex)].reference)
        
        return completedWeft
    }
    
    func process<T>(_ startValue: T, _ reduceClosure: ((T,ValueT)->T)) -> T
    {
        var sum = startValue
        for i in 0..<atoms.count
        {
            // TODO: skip non-value atoms
            sum = reduceClosure(sum, atoms[i].value)
        }
        return sum
    }
    
    //////////////////
    // MARK: - Other -
    //////////////////
    
    func superset(_ v: inout Weave) -> Bool
    {
        if completeWeft().mapping.count < v.completeWeft().mapping.count
        {
            return false
        }
        
        for pair in v.completeWeft().mapping
        {
            if let value = completeWeft().mapping[pair.key]
            {
                if value < pair.value
                {
                    return false
                }
            }
            else
            {
                return false
            }
        }
        
        return true
    }
    
    var atomsDescription: String
    {
        var string = "["
        for i in 0..<atoms.count
        {
            if i != 0 {
                string += "|"
            }
            let a = atoms[i]
            string += "\(a)"
        }
        string += "]"
        return string
    }
    
    var debugDescription: String
    {
        get
        {
            let allSites = Array(completeWeft().mapping.keys).sorted()
            var string = "["
            for i in 0..<allSites.count
            {
                if i != 0
                {
                    string += ", "
                }
                if allSites[i] == self.owner
                {
                    string += ">"
                }
                string += "\(i):\(completeWeft().mapping[allSites[i]]!)"
            }
            string += "]"
            return string
        }
    }
    
    func sizeInBytes() -> Int
    {
        return atoms.count * MemoryLayout<Atom>.size + MemoryLayout<SiteId>.size
    }
    
    ////////////////////////////////////
    // MARK: - Canonical Atom Ordering -
    ////////////////////////////////////
    
    // a1 < a2, i.e. "to the left of"; results undefined for non-sibling or unparented atoms
    static func atomSiblingOrder(a1: Atom, a2: Atom, a1MoreAwareThanA2: Bool) -> Bool
    {
        if a1.id == a2.id
        {
            return false
        }
        
        // special case for priority atoms
        checkPriority: do
        {
            if a1.type.priority && !a2.type.priority
            {
                return true
            }
            else if !a1.type.priority && a2.type.priority
            {
                return false
            }
            // else, sort as default
        }
        
        defaultSort: do
        {
            return a1MoreAwareThanA2
        }
    }
    
    // separate from atomSiblingOrder b/c unparented atoms are not really siblings (well... "siblings of the void")
    // results undefined for non-unparented atoms
    static func unparentedAtomOrder(a1: AtomId, a2: AtomId) -> Bool
    {
        return a1 < a2
    }
}
