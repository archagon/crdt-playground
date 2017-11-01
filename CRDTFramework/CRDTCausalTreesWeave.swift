//
//  CRDTCausalTrees.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-8-28.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import Foundation

//////////////////
// MARK: -
// MARK: - Weave -
// MARK: -
//////////////////

// an ordered collection of atoms and their trees/yarns, for multiple sites
public final class Weave
    <S: CausalTreeSiteUUIDT, V: CausalTreeValueT> :
    CvRDT, NSCopying, CustomDebugStringConvertible, ApproxSizeable
{
    public typealias SiteUUIDT = S
    public typealias ValueT = V
    public typealias AtomT = Atom<ValueT>
    
    /////////////////
    // MARK: - Data -
    /////////////////
    
    // TODO: make owner setter, to ensure that nothing breaks
    public var owner: SiteId
    
    // CONDITION: this data must be the same locally as in the cloud, i.e. no object oriented cache layers etc.
    private var atoms: ArrayType<AtomT> = [] //solid chunk of memory for optimal performance
    
    // needed for sibling sorting
    public private(set) var lamportTimestamp: CRDTCounter<YarnIndex>
    
    ///////////////////
    // MARK: - Caches -
    ///////////////////
    
    // these must be updated whenever the canonical data structures above are mutated; do not have to be the same on different sites
    private var weft: Weft = Weft()
    private var yarns: ArrayType<AtomT> = []
    private var yarnsMap: [SiteId:CountableClosedRange<Int>] = [:]
    
    //////////////////////
    // MARK: - Lifecycle -
    //////////////////////
    
    private enum CodingKeys: String, CodingKey {
        case owner
        case atoms
        case lamportTimestamp
    }
    
    // Complexity: O(N * log(N))
    // NEXT: proofread + consolidate?
    public init(owner: SiteId, weave: inout ArrayType<AtomT>, timestamp: YarnIndex)
    {
        self.owner = owner
        self.atoms = weave
        self.lamportTimestamp = CRDTCounter<YarnIndex>(withValue: timestamp)
        
        generateCacheBySortingAtoms()
    }
    
    public convenience init(from decoder: Decoder) throws
    {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let owner = try values.decode(SiteId.self, forKey: .owner)
        var atoms = try values.decode(Array<AtomT>.self, forKey: .atoms)
        let timestamp = try values.decode(CRDTCounter<YarnIndex>.self, forKey: .lamportTimestamp)
        
        self.init(owner: owner, weave: &atoms, timestamp: timestamp.counter)
    }
    
    // starting from scratch
    public init(owner: SiteId)
    {
        self.owner = owner
        self.lamportTimestamp = CRDTCounter<YarnIndex>(withValue: 0)
        
        addBaseYarn: do
        {
            let siteId = ControlSite
            
            let startAtomId = AtomId(site: siteId, index: 0)
            let startAtom = AtomT(id: startAtomId, cause: startAtomId, timestamp: lamportTimestamp.increment(), value: ValueT())
            
            atoms.append(startAtom)
            updateCaches(withAtom: startAtom)
            
            assert(atomWeaveIndex(startAtomId) == startAtomId.index)
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
        returnWeave.lamportTimestamp = self.lamportTimestamp.copy() as! CRDTCounter<YarnIndex>
        
        return returnWeave
    }
    
    /////////////////////
    // MARK: - Mutation -
    /////////////////////
    
    public func addAtom(withValue value: ValueT, causedBy cause: AtomId) -> (AtomId, WeaveIndex)?
    {
        return _debugAddAtom(atSite: self.owner, withValue: value, causedBy: cause)
    }
    
    // TODO: rename, make moduleprivate
    public func _debugAddAtom(atSite: SiteId, withValue value: ValueT, causedBy cause: AtomId) -> (AtomId, WeaveIndex)?
    {
        let atom = Atom(id: generateNextAtomId(forSite: atSite), cause: cause, timestamp: lamportTimestamp.increment(), value: value)
        
        if let e = integrateAtom(atom)
        {
            return (atom.id, e)
        }
        else
        {
            return nil
        }
    }
    
    // adds awareness atom, usually prior to another add to ensure convergent sibling conflict resolution
    // AB: no-op because we use Lamports now
    public func addCommit(fromSite: SiteId, toSite: SiteId, atTime time: Clock) -> (AtomId, WeaveIndex)? { return nil }
    
    private func updateCaches(withAtom atom: AtomT)
    {
        updateCaches(withAtom: atom, orFromWeave: nil)
    }
    private func updateCaches(afterMergeWithWeave weave: Weave)
    {
        updateCaches(withAtom: nil, orFromWeave: weave)
    }
    
    // no splatting, so we have to do this the ugly way
    // Complexity: O(N * c), where c is 1 for the case of a single atom
    private func updateCaches(withAtom a: AtomT?, orFromWeave w: Weave?)
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
                        let localYarn = weave.yarn(forSite: site)
                        let offset = localYarn.startIndex - remoteRange.lowerBound
                        let remoteDiffRange = (remoteRange.lowerBound + localLength + offset)...(remoteRange.upperBound + offset)
                        let remoteInsertContents = localYarn[remoteDiffRange]
                        
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
                    let localYarn = weave.yarn(forSite: site)
                    let offset = localYarn.startIndex - remoteInsertRange.lowerBound
                    let remoteInsertOffsetRange = (remoteInsertRange.lowerBound + offset)...(remoteInsertRange.upperBound + offset)
                    let remoteInsertContents = localYarn[remoteInsertOffsetRange]
                    let newLocalRange = yarns.count...(yarns.count + remoteInsertRange.count - 1)
                    
                    yarns.insert(contentsOf: remoteInsertContents, at: yarns.count)
                    yarnsMap[site] = newLocalRange
                    weft.update(atom: yarns[yarnsMap[site]!.upperBound].id)
                }
            }
        }
        
        assert(atoms.count == yarns.count, "yarns cache was corrupted on update")
    }
    
    // TODO: combine somehow with updateCaches
    private func generateCacheBySortingAtoms()
    {
        generateYarns: do
        {
            var yarns = self.atoms
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
            timeMe({
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
    public func remapIndices(_ indices: [SiteId:SiteId])
    {
        func updateAtom(inArray array: inout ArrayType<AtomT>, atIndex i: Int)
        {
            array[i].remapIndices(indices)
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
    private func integrateAtom(_ atom: AtomT) -> WeaveIndex?
    {
        var headIndex: Int = -1
        let causeAtom = atomForId(atom.cause)
        
        if causeAtom != nil && causeAtom!.value.childless
        {
            assert(false, "appending atom to non-causal parent")
            return nil
        }
        
        if let aIndex = atomWeaveIndex(atom.cause, searchInReverse: true)
        {
            headIndex = Int(aIndex)
            
            // safety check 1
            if headIndex < atoms.count
            {
                let prevAtom = atoms[headIndex]
                assert(atom.cause == prevAtom.id, "atom is not attached to the correct parent")
            }
            
            // resolve priority ordering
            if !(atom.value.priority != 0) && (headIndex + 1) < atoms.count
            {
                let nextAtom = atoms[headIndex + 1]
                if nextAtom.cause == atom.cause && (nextAtom.value.priority != 0)
                {
                    // PERF: an unusual case: if we add a child atom to an atom that has priority children (usually
                    // deletes), then we need to find the last priority child that we can insert our new atom after;
                    // unfortunately, unlike the default case, this requires some O(N) operations
                    
                    guard let cb = causalBlock(forAtomIndexInWeave: WeaveIndex(headIndex)) else
                    {
                        assert(false, "sibling is priority but could not get causal block")
                        return nil
                    }
                    
                    for i in (cb.lowerBound + 1)...cb.upperBound
                    {
                        let a = atoms[Int(i)]
                        if a.cause == atom.cause && !(a.value.priority != 0)
                        {
                            break
                        }
                        
                        headIndex = Int(i)
                    }
                }
            }
            
            // safety check 2
            if headIndex + 1 < atoms.count
            {
                let nextAtom = atoms[headIndex + 1]
                if nextAtom.cause == atom.cause //siblings
                {
                    assert(Weave.atomSiblingOrder(a1: atom, a2: nextAtom), "atom is not ordered correctly")
                }
            }
        }
        else
        {
            assert(false, "could not determine location of causing atom")
            return nil
        }
        
        // no awareness recalculation, just assume it belongs in front
        atoms.insert(atom, at: headIndex + 1)
        updateCaches(withAtom: atom)
        
        return WeaveIndex(headIndex + 1)
    }
    
    public enum MergeError
    {
        case invalidAwareSiblingComparison
        case invalidUnawareSiblingComparison
        case unknownSiblingComparison
        case unknownTypeComparison
    }
    
    // we assume that indices have been correctly remapped at this point
    // we also assume that remote weave was correctly generated and isn't somehow corrupted
    // IMPORTANT: this function should only be called with a validated weave, because we do not check consistency here
    // PERF: don't need to generate entire weave + caches
    // PERF: TODO: this is currently O(W * c) (or maybe not???) and requires trusted peers; with lamport, we can do it in O(W * log(W)) and simultaneously verify + simplify our yarn algorithm
    public func integrate(_ v: inout Weave<SiteUUIDT,ValueT>)
    {
        typealias Insertion = (localIndex: WeaveIndex, remoteRange: CountableClosedRange<Int>)
        
        //#if DEBUG
        //    let debugCopy = self.copy() as! Weave
        //    let remoteCopy = v.copy() as! Weave
        //#endif
        
        // in order of traversal, so make sure to iterate backwards when actually mutating the weave to keep indices correct
        var insertions: [Insertion] = []
        
        var newAtoms: [AtomT] = []
        newAtoms.reserveCapacity(self.atoms.capacity)
        
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
        
        func commitLocal()
        {
            //commitInsertion()
            newAtoms.append(local[i])
            i += 1
        }
        func commitRemote()
        {
            //insertAtom(atLocalIndex: WeaveIndex(i), fromRemoteIndex: WeaveIndex(j))
            newAtoms.append(remote[j])
            j += 1
        }
        func commitBoth()
        {
            //commitInsertion()
            newAtoms.append(local[i])
            i += 1
            j += 1
        }
        
        // here be the actual merge algorithm
        while j < remote.endIndex
        {
            var mergeError: MergeError? = nil
            
            // past local bounds, so just append remote
            if i >= local.endIndex
            {
                commitRemote()
            }
                
            else if let comparison = try? atomArbitraryOrder(a1: local[i], a2: remote[j], basicOnly: true)
            {
                if comparison == .orderedAscending
                {
                    commitLocal()
                }
                else if comparison == .orderedDescending
                {
                    commitRemote()
                }
                else
                {
                    commitBoth()
                }
            }
                
            // assuming local weave is valid, we can just insert our local changes; relies on trust
            else if localWeft.included(remote[j].id)
            {
                // local < remote, fast forward through to the next matching sibling
                // AB: this and the below block would be more "correct" with causal blocks, but those
                // require O(weave) operations; this is functionally equivalent since we know
                // that one is aware of the other, so we have to reach the other one eventually
                // (barring corruption)
                repeat {
                    commitLocal()
                } while local[i].id != remote[j].id
            }
                
            // assuming remote weave is valid, we can just insert remote's changes; relies on trust
            else if remoteWeft.included(local[i].id)
            {
                // remote < local, fast forward through to the next matching sibling
                repeat {
                    commitRemote()
                } while local[i].id != remote[j].id
            }
                
            // testing for unaware atoms merge
            // PERF: causal block generation is O(N)... what happens if lots of concurrent changes?
            // PERF: TODO: in the case of non-sibling priority atoms conflicting with non-priority atoms, perf will be O(N),
            // can fix by precalculating weave indices for all atoms in O(N); this is only applicable in the edgiest of edge
            // cases where the number of those types of conflicts is more than one or two in a merge (super rare)
            else if
                let comparison = try? atomArbitraryOrder(a1: local[i], a2: remote[j], basicOnly: false),
                let localCausalBlock = causalBlock(forAtomIndexInWeave: WeaveIndex(i)),
                let remoteCausalBlock = v.causalBlock(forAtomIndexInWeave: WeaveIndex(j))
            {
                if comparison == .orderedAscending
                {
                    for _ in 0..<localCausalBlock.count
                    {
                        commitLocal()
                    }
                }
                else
                {
                    for _ in 0..<remoteCausalBlock.count
                    {
                        commitRemote()
                    }
                }
            }
                
            else
            {
                mergeError = .unknownTypeComparison
            }
            
            // this should never happen in theory, but in practice... let's not trust our algorithms too much
            if let error = mergeError
            {
                //#if DEBUG
                //    print("Tree 1 \(debugCopy.atomsDescription)")
                //    print("Tree 2 \(remoteCopy.atomsDescription)")
                //    print("Stopped at \(i),\(j)")
                //#endif
                
                assert(false, "atoms unequal, unaware, and not comparable -- cannot merge (\(error))")
                // TODO: return false here
            }
        }
        commitInsertion() //TODO: maybe avoid commit and just start new range when disjoint interval?
        
        process: do
        {
            //// we go in reverse to avoid having to update our indices
            //for i in (0..<insertions.count).reversed()
            //{
            //    let remoteContent = remote[insertions[i].remoteRange]
            //    atoms.insert(contentsOf: remoteContent, at: Int(insertions[i].localIndex))
            //}
            //updateCaches(afterMergeWithWeave: v)
            self.atoms = newAtoms
            generateCacheBySortingAtoms()
            lamportTimestamp.integrate(&v.lamportTimestamp)
        }
    }
    
    public enum ValidationError: Error
    {
        case noAtoms
        case noSites
        case causalityViolation
        case atomUnawareOfParent
        case atomUnawareOfReference
        case childlessAtomHasChildren
        case treeAtomIsUnparented
        case incorrectTreeAtomOrder
        case likelyCorruption
    }
    
    // a quick check of the invariants, so that (for example) malicious users couldn't corrupt our data
    // prerequisite: we assume that the yarn cache was successfully generated
    // assuming a reasonable (~log(N)) number of sites, O(N*log(N)) at worst, and O(N) for typical use
    public func validate() throws -> Bool
    {
        func vassert(_ b: Bool, _ e: ValidationError) throws
        {
            if !b
            {
                throw e
            }
        }
        
        // sanity check, since we rely on yarns being correct for the rest of this method
        try vassert(atoms.count == yarns.count, .likelyCorruption)
        
        let sitesCount = Int(yarnsMap.keys.max() ?? 0) + 1
        let atomsCount = atoms.count
        
        try vassert(atomsCount >= 2, .noAtoms)
        try vassert(sitesCount >= 1, .noSites)
        
        validate: do
        {
            var lastAtomChild = ContiguousArray<Int>(repeating: -1, count: atomsCount)
            
            var i = 0
            
            checkTree: do
            {
                while i < atoms.count
                {
                    let atom = atoms[i]
                    
                    guard let a = atomYarnsIndex(atom.id) else
                    {
                        try vassert(false, .likelyCorruption); return false
                    }
                    guard let c = atomYarnsIndex(atom.cause) else
                    {
                        try vassert(false, .treeAtomIsUnparented); return false
                    }
                    
                    let cause = yarns[Int(c)]
                    let r = atomYarnsIndex((atom as? CRDTValueReference)?.reference ?? NullAtomId)
                    
                    atomChecking: do
                    {
                        try vassert(!cause.value.childless, .childlessAtomHasChildren)
                    }
                    
                    causalityProcessing: do
                    {
                        if a != 0
                        {
                            try vassert(atom.timestamp > yarns[Int(c)].timestamp, .atomUnawareOfParent)
                        }
                        if let aR = r
                        {
                            try vassert(atom.timestamp > yarns[Int(aR)].timestamp, .atomUnawareOfReference)
                        }
                    }
                    
                    childrenOrderChecking: if a != 0
                    {
                        if lastAtomChild[Int(c)] == -1
                        {
                            lastAtomChild[Int(c)] = Int(a)
                        }
                        else
                        {
                            let lastChild = yarns[Int(lastAtomChild[Int(c)])]
                            
                            let order = Weave.atomSiblingOrder(a1: lastChild, a2: atom)
                            
                            try vassert(order, .incorrectTreeAtomOrder)
                        }
                    }
                    
                    i += 1
                }
            }
            
            return try lamportTimestamp.validate()
        }
    }
    
    // TODO: refactor this
    private func assertTreeIntegrity()
    {
         return
        #if DEBUG
            verifyCache: do
            {
                assert(atoms.count == yarns.count)
                
                var visitedArray = Array<Bool>(repeating: false, count: atoms.count)
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
    
    //////////////////////
    // MARK: - Iteration -
    //////////////////////
    
    // WARNING: if weft is not complete, there's an O(weave) initial cost; so be careful and be sure to cache!
    // TODO: invalidate on mutation; all we have to do is call generateIndices when the wefts don't match
    public struct AtomsSlice: RandomAccessCollection
    {
        private unowned let fullWeave: Weave
        private let startingWeft: Weft
        
        private let targetWeft: Weft?
        private var generatedIndices: ContiguousArray<Int>? = nil
        private var yarnSite: SiteId?
        
        public init(withWeave weave: Weave, weft: Weft?, yarnOrderWithSite: SiteId? = nil)
        {
            self.fullWeave = weave
            self.startingWeft = fullWeave.completeWeft()
            self.targetWeft = weft
            self.yarnSite = yarnOrderWithSite
            
            // generate indices, if needed
            if yarnOrderWithSite == nil, let weft = self.targetWeft, weft != self.startingWeft
            {
                generateIndices(forWeft: weft)
            }
        }
        
        mutating private func generateIndices(forWeft weft: Weft)
        {
            var indices = ContiguousArray<Int>()
            
            for i in 0..<fullWeave.atoms.count
            {
                if weft.included(fullWeave.atoms[i].id)
                {
                    indices.append(i)
                }
            }
            
            self.generatedIndices = indices
        }
        
        public var startIndex: Int
        {
            assert(fullWeave.completeWeft() == self.startingWeft, "weave was mutated")
            
            return 0
        }
        
        public var endIndex: Int
        {
            assert(fullWeave.completeWeft() == self.startingWeft, "weave was mutated")
            
            if let indices = self.generatedIndices
            {
                return indices.count
            }
            else
            {
                if let yarnSite = self.yarnSite
                {
                    let yarnIndex = fullWeave.completeWeft().mapping[yarnSite] ?? -1
                    
                    if let targetWeft = self.targetWeft
                    {
                        let targetIndex = targetWeft.mapping[yarnSite] ?? -1
                        
                        return Int(Swift.min(yarnIndex, targetIndex) + 1)
                    }
                    else
                    {
                        return Int(yarnIndex + 1)
                    }
                }
                else
                {
                    return fullWeave.atoms.count
                }
            }
        }
        
        public func index(after i: Int) -> Int
        {
            assert(fullWeave.completeWeft() == self.startingWeft, "weave was mutated")
            
            return i + 1
        }
        
        public func index(before i: Int) -> Int
        {
            assert(fullWeave.completeWeft() == self.startingWeft, "weave was mutated")
            
            return i - 1
        }
        
        public subscript(position: Int) -> AtomT
        {
            assert(fullWeave.completeWeft() == self.startingWeft, "weave was mutated")
            
            if let indices = self.generatedIndices
            {
                return fullWeave.atoms[indices[position]]
            }
            else
            {
                if let yarnSite = self.yarnSite
                {
                    let yarnSlice = fullWeave.yarns[fullWeave.yarnsMap[yarnSite]!]
                    return yarnSlice[yarnSlice.startIndex + position]
                }
                else
                {
                    return fullWeave.atoms[position]
                }
            }
        }
    }
    
    public func weave(withWeft weft: Weft? = nil) -> AtomsSlice
    {
        return AtomsSlice(withWeave: self, weft: weft)
    }
    
    public func yarn(forSite site:SiteId, withWeft weft: Weft? = nil) -> AtomsSlice
    {
        return AtomsSlice(withWeave: self, weft: weft, yarnOrderWithSite: site)
    }
    
    //////////////////////////
    // MARK: - Basic Queries -
    //////////////////////////
    
    // Complexity: O(1)
    public func atomForId(_ atomId: AtomId) -> AtomT?
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
    public func atomYarnsIndex(_ atomId: AtomId) -> AllYarnsIndex?
    {
        if atomId == NullAtomId
        {
            return nil
        }
        
        if let range = yarnsMap[atomId.site]
        {
            let count = (range.upperBound - range.lowerBound) + 1
            if atomId.index >= 0 && atomId.index < count
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
    public func atomWeaveIndex(_ atomId: AtomId, searchInReverse: Bool = false) -> WeaveIndex?
    {
        if atomId == NullAtomId
        {
            return nil
        }
        if atoms.count == 0
        {
            return nil
        }
        
        var index: Int? = nil
        
        for i in stride(from: (searchInReverse ? atoms.count - 1 : 0), through: (searchInReverse ? 0 : atoms.count - 1), by: (searchInReverse ? -1 : 1))
        {
            let atom = atoms[i]
            if atom.id == atomId
            {
                index = i
                break
            }
        }
        
        return (index != nil ? WeaveIndex(index!) : nil)
    }
    
    // Complexity: O(1)
    public func lastSiteAtomYarnsIndex(_ site: SiteId) -> AllYarnsIndex?
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
    public func lastSiteAtomWeaveIndex(_ site: SiteId) -> WeaveIndex?
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
    public func completeWeft() -> Weft
    {
        return weft
    }
    
    // Complexity: O(1)
    public func atomCount() -> Int
    {
        return atoms.count
    }
    
    // i.e., causal tree branch
    // Complexity: O(N)
    public func causalBlock(forAtomIndexInWeave index: WeaveIndex) -> CountableClosedRange<WeaveIndex>?
    {
        assert(index < atoms.count)
        
        let atom = atoms[Int(index)]
        
        var range: CountableClosedRange<WeaveIndex> = WeaveIndex(index)...WeaveIndex(index)
        
        var i = Int(index) + 1
        while i < atoms.count
        {
            let nextAtomParent = atoms[i]
            if nextAtomParent.id != atom.id && atom.timestamp > nextAtomParent.timestamp
            {
                break
            }
            
            range = range.lowerBound...WeaveIndex(i)
            i += 1
        }
        
        assert(!atom.value.childless || range.count == 1, "childless atom seems to have children")
        
        return range
    }
    
    ////////////////////////////
    // MARK: - Complex Queries -
    ////////////////////////////
    
//    public func process<T>(_ startValue: T, _ reduceClosure: ((T,ValueT)->T)) -> T
//    {
//        var sum = startValue
//        for i in 0..<atoms.count
//        {
//            // TODO: skip non-value atoms
//            sum = reduceClosure(sum, atoms[i].value)
//        }
//        return sum
//    }
    
    //////////////////
    // MARK: - Other -
    //////////////////
    
    public func superset(_ v: inout Weave) -> Bool
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
    
    public var atomsDescription: String
    {
        var string = "[ "
        for i in 0..<atoms.count
        {
            if i != 0 {
                string += " | "
            }
            let a = atoms[i]
            string += "\(i).\(a.value.atomDescription),\(a.cause)->\(a.id),T\(a.timestamp)"
        }
        string += " ]"
        return string
    }
    
    public var debugDescription: String
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
    
    public func sizeInBytes() -> Int
    {
        return atoms.count * MemoryLayout<AtomT>.size + MemoryLayout<SiteId>.size + MemoryLayout<CRDTCounter<YarnIndex>>.size
    }
    
    public static func ==(lhs: Weave, rhs: Weave) -> Bool
    {
        return lhs.completeWeft() == rhs.completeWeft()
    }
    
    public var hashValue: Int
    {
        return completeWeft().hashValue
    }
    
    ////////////////////////////////////
    // MARK: - Canonical Atom Ordering -
    ////////////////////////////////////
    
    public enum ComparisonError: Error
    {
        case insufficientInformation
        case unclearParentage
        case atomNotFound
    }
    
    ///
    /// **Notes:** This is a hammer for all comparison nails, but it's a bit expensive so use very carefully!
    ///
    /// **Preconditions:** Neither atom has to be in the weave, but both their parents have to be.
    ///
    /// **Complexity:** O(weave)
    ///
    public func atomArbitraryOrder(a1: AtomT, a2: AtomT, basicOnly basic: Bool) throws -> ComparisonResult
    {
        basicCases: do
        {
            if a1.id == a2.id
            {
                return ComparisonResult.orderedSame
            }
            
            rootAtom: do
            {
                if a1.cause == a1.id
                {
                    return ComparisonResult.orderedAscending
                }
                else if a2.cause == a2.id
                {
                    return ComparisonResult.orderedDescending
                }
            }
        }
        
        if basic
        {
            throw ComparisonError.insufficientInformation
        }
        
        // AB: we should very, very rarely reach this block -- basically, only if there's a merge conflict between
        // a concurrent, non-sibling priority and non-priority atom
        generalCase: do
        {
            let atomToCompare1: AtomId
            let atomToCompare2: AtomId
            
            lastCommonAncestor: do
            {
                var causeChain1: ContiguousArray<AtomId> = [a1.id]
                var causeChain2: ContiguousArray<AtomId> = [a2.id]
                
                // simple case: avoid calculating last common ancestor
                if a1.cause == a2.cause
                {
                    atomToCompare1 = a1.id
                    atomToCompare2 = a2.id
                    
                    break lastCommonAncestor
                }
                
                // this part is O(weave)
                var cause = a1.id
                while let nextCause = (cause == a1.id ? a1.cause : atomForId(cause)?.cause), nextCause != cause
                {
                    causeChain1.append(nextCause)
                    cause = nextCause
                }
                cause = a2.id
                while let nextCause = (cause == a2.id ? a2.cause : atomForId(cause)?.cause), nextCause != cause
                {
                    causeChain2.append(nextCause)
                    cause = nextCause
                }
                
                if !(causeChain1.count > 1 && causeChain2.count > 1)
                {
                    throw ComparisonError.unclearParentage
                }
                
                let causeChain1Reversed = causeChain1.reversed()
                let causeChain2Reversed = causeChain2.reversed()
                
                // this part is O(weave)
                var firstDiffIndex = 0
                while firstDiffIndex < causeChain1Reversed.count && firstDiffIndex < causeChain2Reversed.count
                {
                    let i1 = causeChain1Reversed.index(causeChain1Reversed.startIndex, offsetBy: firstDiffIndex)
                    let i2 = causeChain1Reversed.index(causeChain2Reversed.startIndex, offsetBy: firstDiffIndex)
                    if causeChain1Reversed[i1] != causeChain2Reversed[i2]
                    {
                        break
                    }
                    firstDiffIndex += 1
                }
                
                if firstDiffIndex == causeChain1Reversed.count
                {
                    return .orderedAscending //a2 includes a1
                }
                else
                {
                    let i1 = causeChain1Reversed.index(causeChain1Reversed.startIndex, offsetBy: firstDiffIndex)
                    atomToCompare1 = causeChain1Reversed[i1]
                }
                
                if firstDiffIndex == causeChain2Reversed.count
                {
                    return .orderedDescending //a1 includes a2
                }
                else
                {
                    let i2 = causeChain2Reversed.index(causeChain2Reversed.startIndex, offsetBy: firstDiffIndex)
                    atomToCompare2 = causeChain2Reversed[i2]
                }
            }
            
            guard
                let a1 = (atomToCompare1 == a1.id ? a1 : atomForId(atomToCompare1)),
                let a2 = (atomToCompare2 == a2.id ? a2 : atomForId(atomToCompare2))
                else
            {
                throw ComparisonError.atomNotFound
            }
            
            let a1a2 = Weave.atomSiblingOrder(a1: a1, a2: a2)
            if a1a2 { return .orderedAscending } else { return .orderedDescending }
        }
    }
    
    // a1 < a2, i.e. "to the left of"; results undefined for non-sibling atoms
    public static func atomSiblingOrder(a1: AtomT, a2: AtomT) -> Bool
    {
        precondition(a1.cause != a1.id && a2.cause != a2.id, "root atom has no siblings")
        precondition(a1.cause == a2.cause, "atoms must be siblings")
        
        if a1.id == a2.id
        {
            return false
        }
        
        // special case for priority atoms
        checkPriority: do
        {
            if (a1.value.priority != 0) && !(a2.value.priority != 0)
            {
                return true
            }
            else if !(a1.value.priority != 0) && (a2.value.priority != 0)
            {
                return false
            }
            // else, sort as default
        }
        
        defaultSort: do
        {
            if a1.timestamp == a2.timestamp
            {
                return a1.site > a2.site
            }
            else
            {
                return a1.timestamp > a2.timestamp
            }
        }
    }
}
