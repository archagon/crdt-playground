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
// TODO: make everything a struct?
// TODO: special atoms -- save points, start/end, etc.

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
protocol CausalTreeValueT: DefaultInitializable, CustomStringConvertible {}

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

final class CausalTree <SiteUUIDT: CausalTreeSiteUUIDT, ValueT: CausalTreeValueT> : CvRDT, NSCopying
{
    // these are separate b/c they are serialized separately and grow separately -- and, really, are separate CRDTs
    var siteIndex: SiteIndex<SiteUUIDT> = SiteIndex<SiteUUIDT>()
    var weave: Weave<SiteUUIDT,ValueT>
    
    init(site: SiteId)
    {
        self.weave = Weave<SiteUUIDT,ValueT>(site: site)
    }
    
    public func copy(with zone: NSZone? = nil) -> Any
    {
        let returnTree = CausalTree<SiteUUIDT,ValueT>(site: NullSite)
        returnTree.siteIndex = self.siteIndex.copy(with: nil) as! SiteIndex<SiteUUIDT>
        returnTree.weave = self.weave.copy(with: nil) as! Weave<SiteUUIDT,ValueT>
        return returnTree
    }
    
    func integrate(_ v: inout CausalTree)
    {
        let oldSiteIndex = siteIndex.copy() as! SiteIndex<SiteUUIDT>
        let firstDifferentIndex = siteIndex.integrateReturningFirstDiffIndex(&v.siteIndex)
        siteIndex.integrate(&v.siteIndex)
        var remapMap: [SiteId:SiteId] = [:]
        if let index = firstDifferentIndex
        {
            let newMapping = siteIndex.siteMapping()
            for i in index..<oldSiteIndex.siteCount()
            {
                let oldSite = SiteId(i)
                let newSite = newMapping[oldSiteIndex.site(oldSite)!]
                remapMap[oldSite] = newSite
            }
        }
        weave.remapIndices(remapMap)
        weave.integrate(&v.weave)
    }
}

///////////////////////
// MARK: -
// MARK: - Site Index -
// MARK: -
///////////////////////

final class SiteIndex <SiteUUIDT: CausalTreeSiteUUIDT> : CvRDT, NSCopying
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
    
    // we assume this is always sorted in lexographic order -- first by clock, then by UUID
    private var mapping: ContiguousArray<SiteIndexKey> = []
    
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
    func integrateReturningFirstDiffIndex(_ v: inout SiteIndex) -> Int?
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
}

//////////////////
// MARK: -
// MARK: - Weave -
// MARK: -
//////////////////

// an ordered collection of atoms and their trees/yarns, for multiple sites
final class Weave <SiteUUIDT: CausalTreeSiteUUIDT, ValueT: CausalTreeValueT> : CvRDT, NSCopying
{
    //////////////////
    // MARK: - Types -
    //////////////////
    
    typealias YarnIndex = Int64
    typealias WeaveIndex = Int64
    typealias AllYarnsIndex = Int64
    
    struct AtomId: Equatable
    {
        let site: SiteId
        let index: YarnIndex
        
        public static func ==(lhs: AtomId, rhs: AtomId) -> Bool
        {
            return lhs.site == rhs.site && lhs.index == rhs.index
        }
    }
    
    struct Atom
    {
        let site: SiteId
        let causingSite: SiteId
        let index: YarnIndex
        let causingIndex: YarnIndex
        let clock: Clock //not required, but possibly useful for user
        let value: ValueT
        
        init(id: AtomId, cause: AtomId, clock: Clock, value: ValueT) {
            self.site = id.site
            self.causingSite = cause.site
            self.index = id.index
            self.causingIndex = cause.index
            self.clock = clock
            self.value = value
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
    }
    
    // TODO: I don't like that this tiny structure has to be malloc'd
    struct Weft: Equatable
    {
        var mapping: [SiteId:YarnIndex] = [:]
        
        mutating func update(site: SiteId, index: YarnIndex)
        {
            mapping[site] = max(mapping[site] ?? NullIndex, index)
        }
        
        mutating func update(atom: AtomId) {
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
            if let index = mapping[atom.site] {
                if atom.index <= index {
                    return true
                }
            }
            return false
        }
        
        public static func ==(lhs: Weft, rhs: Weft) -> Bool
        {
            return (lhs.mapping as NSDictionary).isEqual(to: rhs.mapping)
        }
    }
    
    private enum CommitStrategyType
    {
        case onCausedByRemoteSite
        case onSync
    }
    
    //////////////////////
    // MARK: - Constants -
    //////////////////////
    
    static var NullIndex: YarnIndex { get { return -1 }} //max (NullIndex, index) needs to always return index
    static var NullAtomId: AtomId { return AtomId(site: NullSite, index: NullIndex) }
    
    private static var CommitStrategy: CommitStrategyType { return .onCausedByRemoteSite }
    
    /////////////////
    // MARK: - Data -
    /////////////////
    
    private var site: SiteId
    
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
    
    init(site: SiteId, weave: inout ContiguousArray<Atom>?)
    {
        self.site = site
        
        if let aWeave = weave
        {
            self.atoms = aWeave
            
            generateCache: do
            {
                generateYarns: do
                {
                    var yarns = aWeave
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
                            weft.update(atom: self.yarns[i].id)
                            if let range = yarnsMap[self.yarns[i].site]
                            {
                                yarnsMap[self.yarns[i].site] = range.lowerBound...i
                            }
                            else
                            {
                                yarnsMap[self.yarns[i].site] = i...i
                            }
                        }
                        
                        self.weft = weft
                        self.yarnsMap = yarnsMap
                    }, "CacheGen")
                }
            }
        }
        else
        {
            // starting from scratch
            addBaseYarn: do
            {
                let siteId = ControlSite
                
                let startAtomId = AtomId(site: siteId, index: 0)
                let endAtomId = AtomId(site: siteId, index: 1)
                let startAtom = Atom(id: startAtomId, cause: startAtomId, clock: StartClock, value: ValueT())
                let endAtom = Atom(id: endAtomId, cause: startAtomId, clock: EndClock, value: ValueT())
                
                atoms.append(startAtom)
                atoms.append(endAtom)
                weft.update(atom: startAtomId)
                weft.update(atom: endAtomId)
                updateYarnsCache(withAtom: startAtom)
                updateYarnsCache(withAtom: endAtom)
                
                assert(atomWeaveIndex(startAtomId) == startAtomId.index)
                assert(atomWeaveIndex(endAtomId) == endAtomId.index)
            }
        }
    }
    
    convenience init(site: SiteId)
    {
        var array: ContiguousArray<Atom>? = nil
        self.init(site: site, weave: &array)
    }
    
    func addAtom(withValue value: ValueT, causedBy cause: AtomId, atTime clock: Clock) -> AtomId?
    {
        return _debugAddAtom(atSite: self.site, withValue: value, causedBy: cause, atTime: clock)
    }
    
    func _debugAddAtom(atSite: SiteId, withValue value: ValueT, causedBy cause: AtomId, atTime clock: Clock, noCommit: Bool = false) -> AtomId?
    {
        if !noCommit && type(of: self).CommitStrategy == .onCausedByRemoteSite
        {
            let _ = addCommit(fromSite: atSite, toSite: cause.site, atTime: clock)
        }
        
        let atom = Atom(id: generateNextAtomId(forSite: atSite), cause: cause, clock: clock, value: value)
        let e = integrateAtom(atom, inFront: true)
        
        return (e ? atom.id : nil)
    }
    
    // adds awareness atom, usually prior to another add to ensure convergent sibling conflict resolution
    private func addCommit(fromSite: SiteId, toSite: SiteId, atTime time: Clock) -> AtomId?
    {
        // TODO: add some way to identify this atom as causal, i.e. non-present in output
        if fromSite == toSite
        {
            return nil
        }
        
        guard let lastCommitSiteAtomIndex = lastSiteAtomWeaveIndex(toSite) else
        {
            return nil
        }
        
        // TODO: check if we're already up-to-date, to avoid duplicate commits... though, this isn't really important
        
        let lastCommitSiteAtom = atoms[Int(lastCommitSiteAtomIndex)]
        let commitAtom = Atom(id: generateNextAtomId(forSite: fromSite), cause: lastCommitSiteAtom.id, clock: time, value: ValueT())
        
        // AB: commit atom always wins b/c it's necessarily more aware than the atom it connects to
        let e = integrateAtom(commitAtom, inFront: true, withPrecomputedHeadIndex: lastCommitSiteAtomIndex)
        return (e ? commitAtom.id : nil)
    }
    
    // lets us treat weave like an actual tree
    private func integrateAtom(_ atom: Atom, inFront: Bool, withPrecomputedHeadIndex index: WeaveIndex? = nil) -> Bool
    {
        let headIndex: Int
        
        if let aIndex = index
        {
            headIndex = Int(aIndex)
            assert(atoms[headIndex].id == atom.cause, "precomputed index does not match atom cause")
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
        
        if inFront
        {
            // no awareness recalculation, just assume it belongs in front
            atoms.insert(atom, at: headIndex + 1)
            weft.update(atom: atom.id)
            updateYarnsCache(withAtom: atom)
            return true
        }
        else
        {
            // costly awareness recalculation
            // NEXT: TODO:
            assert(false)
            return false
        }
    }
    
    private func updateYarnsCache(withAtom atom: Atom)
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
        }
        else
        {
            assert(atom.id.index == 0, "adding atom out of order")
            yarns.append(atom)
            yarnsMap[atom.site] = (yarns.count - 1)...(yarns.count - 1)
        }
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
    
    public func copy(with zone: NSZone? = nil) -> Any
    {
        let returnWeave = Weave(site: self.site)
        
        // TODO: verify that these structs do copy as expected
        returnWeave.site = self.site
        returnWeave.atoms = self.atoms
        returnWeave.weft = self.weft
        returnWeave.yarns = self.yarns
        returnWeave.yarnsMap = self.yarnsMap
        
        return returnWeave
    }
    
    func remapIndices(_ indices: [SiteId:SiteId])
    {
        // NEXT: iterate weave and substitue indices as needed
        // don't forget to include local site index
    }
    
    func integrate(_ v: inout Weave<SiteUUIDT,ValueT>)
    {
        // we assume that indices have been correctly remapped at this point
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
    func atomWeaveIndex(_ atomId: AtomId) -> WeaveIndex?
    {
        var index: Int? = nil
        for i in 0..<atoms.count
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
                        //guard !checkIfIncluded(atomId: aAtom.cause, inWeft: &workingWeft) else
                        //{
                        //    break enqueueCausalAtom //are we going to be considering this atom in this loop iteration anyway? (note: superset of completedWeft)
                        //}
                        
                        nextWeft.update(site: aAtom.cause.site, index: aAtom.cause.index)
                        //add(atomIndex: nil, clock: aAtom.cause.clock, atSite: aAtom.cause.site, toWeft: &nextWeft)
                    }
                }
            }
            
            // fill in missing gaps
            workingWeft.mapping.forEach(
            { (v: (site: SiteId, index: YarnIndex)) in
                nextWeft.update(site: v.site, index: v.index)
                //add(atomIndex: v.indices.atomIndex, clock: v.indices.clock, atSite: v.site, toWeft: &nextWeft)
            })
            // update completed weft
            workingWeft.mapping.forEach(
            { (v: (site: SiteId, index: YarnIndex)) in
                completedWeft.update(site: v.site, index: v.index)
                //add(atomIndex: v.indices.atomIndex, clock: v.indices.clock, atSite: v.site, toWeft: &completedWeft)
            })
            // swap
            swap(&workingWeft, &nextWeft)
        }
        
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
}
