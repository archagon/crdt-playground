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
final class Weave
    <S: CausalTreeSiteUUIDT, V: CausalTreeValueT> :
    CvRDT, NSCopying, CustomDebugStringConvertible, ApproxSizeable
{
    typealias SiteUUIDT = S
    typealias ValueT = V
    
    //////////////////
    // MARK: - Types -
    //////////////////
    
    // TODO: this isn't the best way to do this; the generic "value" is keeping us from using this in view controllers;
    //       better to just split out the value and the rest of the atom?
    struct Atom: CustomStringConvertible, Codable
    {
        let site: SiteId
        let causingSite: SiteId
        let index: YarnIndex
        let causingIndex: YarnIndex
        let timestamp: YarnIndex //"precomputed awareness", if you prefer -- used for sibling sorting
        let value: ValueT
        let reference: AtomId //a "child", or weak ref, not part of the DFS, e.g. a commit pointer or the closing atom of a segment
        let type: AtomType
        
        init(id: AtomId, cause: AtomId, type: AtomType, timestamp: YarnIndex, value: ValueT, reference: AtomId = NullAtomId)
        {
            self.site = id.site
            self.causingSite = cause.site
            self.index = id.index
            self.causingIndex = cause.index
            self.type = type
            self.timestamp = timestamp
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
        
        var debugDescription: String
        {
            get
            {
                return "\(id): c[\(cause)], r[\(reference)], \"\(type)\", \(value)"
            }
        }
        
        var metadata: AtomMetadata
        {
            return AtomMetadata(id: id, cause: cause, reference: reference, type: type, timestamp: timestamp)
        }
    }
    
    /////////////////
    // MARK: - Data -
    /////////////////
    
    var owner: SiteId
    
    // CONDITION: this data must be the same locally as in the cloud, i.e. no object oriented cache layers etc.
    private var atoms: ArrayType<Atom> = [] //solid chunk of memory for optimal performance
    
    // needed for sibling sorting
    var lamportTimestamp: CRDTCounter<YarnIndex>
    
    ///////////////////
    // MARK: - Caches -
    ///////////////////
    
    // these must be updated whenever the canonical data structures above are mutated; do not have to be the same on different sites
    private var weft: Weft = Weft()
    private var yarns: ArrayType<Atom> = []
    private var yarnsMap: [SiteId:CountableClosedRange<Int>] = [:]
    
    //////////////////////
    // MARK: - Lifecycle -
    //////////////////////
    
    enum CodingKeys: String, CodingKey {
        case owner
        case atoms
        case lamportTimestamp
    }
    
    // Complexity: O(N * log(N))
    // NEXT: proofread + consolidate?
    init(owner: SiteId, weave: inout ArrayType<Atom>, timestamp: YarnIndex)
    {
        self.owner = owner
        self.atoms = weave
        self.lamportTimestamp = CRDTCounter<YarnIndex>(withValue: timestamp)
        
        // TODO: move this over to generic updateCaches method
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
    
    convenience init(from decoder: Decoder) throws
    {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let owner = try values.decode(SiteId.self, forKey: .owner)
        var atoms = try values.decode(Array<Atom>.self, forKey: .atoms)
        let timestamp = try values.decode(CRDTCounter<YarnIndex>.self, forKey: .lamportTimestamp)
        
        self.init(owner: owner, weave: &atoms, timestamp: timestamp.counter)
    }
    
    // starting from scratch
    init(owner: SiteId)
    {
        self.owner = owner
        self.lamportTimestamp = CRDTCounter<YarnIndex>(withValue: 0)
        
        addBaseYarn: do
        {
            let siteId = ControlSite
            
            let startAtomId = AtomId(site: siteId, index: 0)
            let endAtomId = AtomId(site: siteId, index: 1)
            let startAtom = Atom(id: startAtomId, cause: startAtomId, type: .start, timestamp: lamportTimestamp.increment(), value: ValueT())
            let endAtom = Atom(id: endAtomId, cause: NullAtomId, type: .end, timestamp: lamportTimestamp.increment(), value: ValueT(), reference: startAtomId)
            
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
        returnWeave.lamportTimestamp = self.lamportTimestamp.copy() as! CRDTCounter<YarnIndex>
        
        return returnWeave
    }
    
    /////////////////////
    // MARK: - Mutation -
    /////////////////////
    
    func addAtom(withValue value: ValueT, causedBy cause: AtomId, atTime clock: Clock, priority: Bool = false, withReference: AtomId? = nil) -> (AtomId, WeaveIndex)?
    {
        return _debugAddAtom(atSite: self.owner, withValue: value, causedBy: cause, atTime: clock, priority: priority, withReference: withReference)
    }
    
    // TODO: rename, put CRDT in framework, make moduleprivate
    func _debugAddAtom(atSite: SiteId, withValue value: ValueT, causedBy cause: AtomId, atTime clock: Clock, noCommit: Bool = false, priority: Bool = false, withReference: AtomId? = nil) -> (AtomId, WeaveIndex)?
    {
        if !noCommit
        {
            // find all siblings and make sure awareness of their yarns is committed
            // AB: note that this works because commit atoms are non-causal, ergo we do not need to sort them all the way down the DFS chain
            // AB: could just commit the sibling atoms themselves, but why not get the whole yarn? more truthful!
            // PERF: O(N) -- is this too slow?
            // PERF: start iterating from index of parent, not 0
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
        
        let atom = Atom(id: generateNextAtomId(forSite: atSite), cause: cause, type: (priority ? .valuePriority : .value), timestamp: lamportTimestamp.increment(), value: value, reference: (withReference ?? NullAtomId))
        
        if let e = integrateAtom(atom)
        {
            return (atom.id, e)
        }
        else
        {
            return nil
        }
    }
    
    func deleteAtom(_ atomId: AtomId, atTime _: Clock) -> (AtomId, WeaveIndex)?
    {
        guard let index = atomYarnsIndex(atomId) else
        {
            return nil
        }
        
        let targetAtom = yarns[Int(index)]
        
        if !targetAtom.type.value
        {
            return nil
        }
        
        let deleteAtom = Atom(id: generateNextAtomId(forSite: owner), cause: atomId, type: .delete, timestamp: lamportTimestamp.increment(), value: ValueT())
        
        if let e = integrateAtom(deleteAtom)
        {
            return (deleteAtom.id, e)
        }
        else
        {
            return nil
        }
    }
    
    // adds awareness atom, usually prior to another add to ensure convergent sibling conflict resolution
    // AB: no-op because we use Lamports now... but the implementation does work
    func addCommit(fromSite: SiteId, toSite: SiteId, atTime time: Clock) -> (AtomId, WeaveIndex)?
    {
        //if fromSite == toSite
        //{
        //    return nil
        //}
        //
        //guard let lastCommitSiteYarnsIndex = lastSiteAtomYarnsIndex(toSite) else
        //{
        //    return nil
        //}
        //
        //// TODO: check if we're already up-to-date, to avoid duplicate commits... though, this isn't really important
        //
        //let lastCommitSiteAtom = yarns[Int(lastCommitSiteYarnsIndex)]
        //let commitAtom = Atom(id: generateNextAtomId(forSite: fromSite), cause: NullAtomId, type: .commit, clock: time, value: ValueT(), reference: lastCommitSiteAtom.id)
        //
        //if let e = integrateAtom(commitAtom)
        //{
        //    return (commitAtom.id, e)
        //}
        //else
        //{
        //    return nil
        //}
        
        return nil
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
        func updateAtom(inArray array: inout ArrayType<Atom>, atIndex i: Int)
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
                array[i] = Atom(id: id ?? array[i].id, cause: cause ?? array[i].cause, type: array[i].type, timestamp: array[i].timestamp, value: array[i].value, reference: reference ?? array[i].reference)
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
    private func integrateAtom(_ atom: Atom) -> WeaveIndex?
    {
        var headIndex: Int = -1
        let causeAtom = atomForId(atom.cause)
        
        if causeAtom != nil && causeAtom!.type.childless
        {
            assert(false, "appending atom to non-causal parent")
            return nil
        }
        
        if atom.type.unparented && causeAtom != nil
        {
            assert(false, "unparented atom still has a cause")
            return nil
        }
        
        if atom.type.unparented, let nullableIndex = unparentedAtomWeaveInsertionIndex(atom.id)
        {
            headIndex = Int(nullableIndex) - 1 //subtract to avoid special-casing math below
        }
        else if let aIndex = atomWeaveIndex(atom.cause)
        {
            headIndex = Int(aIndex)
            
            // safety check 1
            if headIndex < atoms.count
            {
                let prevAtom = atoms[headIndex]
                assert(atom.cause == prevAtom.id, "atom is not attached to the correct parent")
            }
            
            // resolve priority ordering
            if !atom.type.priority && (headIndex + 1) < atoms.count
            {
                let nextAtom = atoms[headIndex + 1]
                if nextAtom.cause == atom.cause && nextAtom.type.priority
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
                        if a.cause == atom.cause && !a.type.priority
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
        
        //#if DEBUG
        //    let debugCopy = self.copy() as! Weave
        //    let remoteCopy = v.copy() as! Weave
        //#endif
        
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
                
            else if let comparison = try? atomArbitraryOrder(a1: local[i], a2: remote[j], basicOnly: true)
            {
                if comparison == .orderedAscending
                {
                    commitInsertion()
                    i += 1
                }
                else if comparison == .orderedDescending
                {
                    insertAtom(atLocalIndex: WeaveIndex(i), fromRemoteIndex: WeaveIndex(j))
                    j += 1
                }
                else
                {
                    commitInsertion()
                    i += 1
                    j += 1
                }
            }
                
            // assuming local weave is valid, we can just insert our local changes; relies on trust
            else if localWeft.included(remote[j].id)
            {
                // local < remote, fast forward through to the next matching sibling
                // AB: this and the below block would be more "correct" with causal blocks, but those
                // require expensive awareness derivation; this is functionally equivalent since we know
                // that one is aware of the other, so we have to reach the other one eventually
                // (barring corruption)
                repeat {
                    commitInsertion()
                    i += 1
                } while local[i].id != remote[j].id
            }
                
            // assuming remote weave is valid, we can just insert remote's changes; relies on trust
            else if remoteWeft.included(local[i].id)
            {
                // remote < local, fast forward through to the next matching sibling
                repeat {
                    insertAtom(atLocalIndex: WeaveIndex(i), fromRemoteIndex: WeaveIndex(j))
                    j += 1
                } while local[i].id != remote[j].id
            }
                
            // testing for unaware atoms merge
            // PERF: awareness generation and causal block generation are O(N)... what happens if lots of concurrent changes?
            // PERF: TODO: in the case of non-sibling priority atoms conflicting with non-priority atoms, perf will be O(N),
            // can fix by precalculating weave indices for all atoms in O(N); this is only applicable in the edgiest of edge
            // cases where the number of those types of conflicts is more than one or two in a merge (super rare)
            else if
                //let localAwareness = awarenessWeft(forAtom: local[i].id),
                //let remoteAwareness = v.awarenessWeft(forAtom: remote[j].id),
                let comparison = try? atomArbitraryOrder(a1: local[i], a2: remote[j], basicOnly: false),
                let localCausalBlock = causalBlock(forAtomIndexInWeave: WeaveIndex(i)),
                let remoteCausalBlock = v.causalBlock(forAtomIndexInWeave: WeaveIndex(j))
            {
                if comparison == .orderedAscending
                {
                    processLocal: do
                    {
                        commitInsertion()
                        i += localCausalBlock.count
                    }
                }
                else
                {
                    for _ in 0..<remoteCausalBlock.count
                    {
                        insertAtom(atLocalIndex: WeaveIndex(i), fromRemoteIndex: WeaveIndex(j))
                        j += 1
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
            // we go in reverse to avoid having to update our indices
            for i in (0..<insertions.count).reversed()
            {
                let remoteContent = remote[insertions[i].remoteRange]
                atoms.insert(contentsOf: remoteContent, at: Int(insertions[i].localIndex))
            }
            updateCaches(afterMergeWithWeave: v)
            lamportTimestamp.integrate(&v.lamportTimestamp)
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
    
    enum ValidationError: Error
    {
        case noAtoms
        case noSites
        case causalityViolation
        case atomUnawareOfParent
        case atomUnawareOfReference
        case childlessAtomHasChildren
        case treeAtomIsUnparented
        case unparentedAtomIsParented
        case incorrectTreeAtomOrder
        case incorrectUnparentedAtomOrder
        case missingStartOfUnparentedSection
        case likelyCorruption
    }
    
    // a quick check of the invariants, so that (for example) malicious users couldn't corrupt our data
    // prerequisite: we assume that the yarn cache was successfully generated
    // assuming a reasonable (~log(N)) number of sites, O(N*log(N)) at worst, and O(N) for typical use
    func validate() throws -> Bool
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
        
        let minCutoff = 20
        let sitesCount = Int(yarnsMap.keys.max() ?? 0) + 1
        let atomsCount = atoms.count
        let logAtomsCount = Int(log2(Double(atomsCount == 0 ? 1 : atomsCount)))
        
        try vassert(atomsCount >= 2, .noAtoms)
        try vassert(sitesCount >= 1, .noSites)
        
        if sitesCount < max(minCutoff, logAtomsCount)
        {
            var lastAtomChild = ContiguousArray<Int>(repeating: -1, count: atomsCount)
            
            //var atomAwareness = ContiguousArray<Int>(repeating: -1, count: atomsCount * sitesCount)
            //
            //// these all use yarns layout
            //// TODO: unify this with regular awareness calculation; move everything over to ContiguousArray?
            //var awarenessProcessingQueue = ContiguousArray<Int>()
            //awarenessProcessingQueue.reserveCapacity(atomsCount)
            //func awareness(forAtom a: Int) -> ArraySlice<Int>
            //{
            //    return atomAwareness[(a * sitesCount)..<((a * sitesCount) + sitesCount)]
            //}
            //func updateAwareness(forAtom a1: Int, fromAtom a2: Int)
            //{
            //    if a1 == -1 || a2 == -1 { return }
            //    for s in 0..<sitesCount
            //    {
            //        atomAwareness[(a1 * sitesCount) + s] = max(atomAwareness[(a1 * sitesCount) + s], atomAwareness[(a2 * sitesCount) + s])
            //    }
            //}
            //func compareAwareness(a1: Int, a2: Int) -> Bool
            //{
            //    return atomAwareness[(a1 * sitesCount)..<((a1 * sitesCount) + sitesCount)].lexicographicallyPrecedes(atomAwareness[(a2 * sitesCount)..<((a2 * sitesCount) + sitesCount)])
            //}
            //func aware(a1: Int, of a2: Int) -> Bool
            //{
            //    return compareAwareness(a1: a2, a2: a1)
            //}
            //func awarenessCalculated(a: Int) -> Bool
            //{
            //    // every tree atom is necessarily aware of the first atom
            //    return atomAwareness[(a * sitesCount) + 0] != -1
            //}
            //
            //// preseed atom 0 awareness
            //atomAwareness[0] = 0
            //
            //// We can calculate awareness in dependency order by iterating over our atoms in absolute temporal
            //// order. We don't have this information for all combined sites, but we do have it for each individual
            //// site, and so we can iterate all our sites in unison until a dependency is violated -- at which point
            //// we pause iterating the offending site until the dependency is resolved on the other end. We're sort
            //// of brute-forcing the temporal order, but it's still O(N * S) == O(N * log(N)) in the end so it
            //// doesn't really matter.
            //generateAwareness: do
            //{
            //    // next atom to check for each yarn/site
            //    var yarnsIndex = ContiguousArray<Int>(repeating: 0, count: sitesCount)
            //
            //    while true
            //    {
            //        var atLeastOneSiteMovedForward = false
            //        var doneCount = 0
            //
            //        for site in 0..<Int(yarnsIndex.count)
            //        {
            //            let index = yarnsIndex[site]
            //
            //            if index >= yarnsMap[SiteId(site)]?.count ?? 0
            //            {
            //                doneCount += 1
            //                continue
            //            }
            //
            //            guard let a = atomYarnsIndex(AtomId(site: SiteId(site), index: YarnIndex(index))) else
            //            {
            //                try vassert(false, .likelyCorruption); return false
            //            }
            //
            //            let atom = yarns[Int(a)]
            //
            //            // PERF: can precalculate all of these
            //            let c = atomYarnsIndex(atom.cause) ?? -1
            //            let p = atomYarnsIndex(AtomId(site: atom.site, index: atom.index - 1)) ?? -1
            //            let r = atomYarnsIndex(atom.reference) ?? -1
            //
            //            // dependency checking
            //            if c != -1 && !awarenessCalculated(a: Int(c))
            //            {
            //                continue
            //            }
            //            if p != -1 && !awarenessCalculated(a: Int(p))
            //            {
            //                continue
            //            }
            //            if r != -1 && !awarenessCalculated(a: Int(r))
            //            {
            //                continue
            //            }
            //
            //            atomAwareness[Int(a) * sitesCount + site] = index
            //            updateAwareness(forAtom: Int(a), fromAtom: Int(c))
            //            updateAwareness(forAtom: Int(a), fromAtom: Int(p))
            //            updateAwareness(forAtom: Int(a), fromAtom: Int(r))
            //
            //            yarnsIndex[site] += 1
            //            atLeastOneSiteMovedForward = true
            //        }
            //
            //        let done = (doneCount == sitesCount)
            //
            //        try vassert(done || atLeastOneSiteMovedForward, .causalityViolation)
            //
            //        if done
            //        {
            //            break
            //        }
            //    }
            //}
            
            var i = 0
            
            checkTree: do
            {
                while i < atoms.count
                {
                    let atom = atoms[i]
                    
                    if atom.type.unparented
                    {
                        break //move on to unparented section
                    }
                    
                    guard let a = atomYarnsIndex(atom.id) else
                    {
                        try vassert(false, .likelyCorruption); return false
                    }
                    guard let c = atomYarnsIndex(atom.cause) else
                    {
                        try vassert(false, .treeAtomIsUnparented); return false
                    }
                    
                    let cause = yarns[Int(c)]
                    let r = atomYarnsIndex(atom.reference)
                    
                    atomChecking: do
                    {
                        try vassert(!cause.type.childless, .childlessAtomHasChildren)
                        try vassert(!atom.type.unparented, .treeAtomIsUnparented)
                    }
                    
                    awarenessProcessing: do
                    {
                        if a != 0
                        {
                            //try vassert(aware(a1: Int(a), of: Int(c)), .atomUnawareOfParent)
                            try vassert(atom.timestamp > yarns[Int(c)].timestamp, .atomUnawareOfParent)
                        }
                        if let aR = r
                        {
                            //try vassert(aware(a1: Int(a), of: Int(aR)), .atomUnawareOfReference)
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
            
            try vassert(atoms[i].id == AtomId(site: ControlSite, index: 1), .missingStartOfUnparentedSection)
            
            checkUnparented: do
            {
                // start with second unparented atom
                i += 1
                
                while i < atoms.count
                {
                    let prevAtom = atoms[i - 1]
                    let atom = atoms[i]
                    
                    try vassert(atom.type.unparented, .unparentedAtomIsParented)
                    try vassert(atom.cause == NullAtomId, .unparentedAtomIsParented)
                    
                    try vassert(Weave.unparentedAtomOrder(a1: prevAtom.id, a2: atom.id), .incorrectUnparentedAtomOrder)
                    
                    i += 1
                }
            }
            
            return try lamportTimestamp.validate()
        }
        else
        {
            fatalError("efficient verification for large number of sites not yet implemented")
        }
    }
    
    // TODO: refactor this
    func assertTreeIntegrity()
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
    struct AtomsSlice: RandomAccessCollection
    {
        private unowned let fullWeave: Weave
        private let startingWeft: Weft
        
        private let targetWeft: Weft?
        private var generatedIndices: ContiguousArray<Int>? = nil
        private var yarnSite: SiteId?
        
        init(withWeave weave: Weave, weft: Weft?, yarnOrderWithSite: SiteId? = nil)
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
        
        var startIndex: Int
        {
            assert(fullWeave.completeWeft() == self.startingWeft, "weave was mutated")
            
            return 0
        }
        
        var endIndex: Int
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
        
        func index(after i: Int) -> Int
        {
            assert(fullWeave.completeWeft() == self.startingWeft, "weave was mutated")
            
            return i + 1
        }
        
        func index(before i: Int) -> Int
        {
            assert(fullWeave.completeWeft() == self.startingWeft, "weave was mutated")
            
            return i - 1
        }
        
        subscript(position: Int) -> Atom
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
    
    func weave(withWeft weft: Weft? = nil) -> AtomsSlice
    {
        return AtomsSlice(withWeave: self, weft: weft)
    }
    
    func yarn(forSite site:SiteId, withWeft weft: Weft? = nil) -> AtomsSlice
    {
        return AtomsSlice(withWeave: self, weft: weft, yarnOrderWithSite: site)
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
    func atomWeaveIndex(_ atomId: AtomId, searchInReverse: Bool = false) -> WeaveIndex?
    {
        if atomId == NullAtomId
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
    
    // i.e., causal tree branch
    // Complexity: O(N)
    func causalBlock(forAtomIndexInWeave index: WeaveIndex) -> CountableClosedRange<WeaveIndex>?
    {
        assert(index < atoms.count)
        
        let atom = atoms[Int(index)]
        
        // unparented atoms are arranged differently than typical atoms, and thusly don't have any causal blocks
        if atom.type.unparented
        {
            return nil
        }
        
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
        
        assert(!atom.type.childless || range.count == 1, "childless atom seems to have children")
        
        return range
    }
    
    ////////////////////////////
    // MARK: - Complex Queries -
    ////////////////////////////
    
    ///
    /// **Preconditions:** The atom must be part of the weave.
    ///
    /// **Complexity:** O(weave)
    ///
    // AB: commented out b/c we're using Lamport timestamps now, which make everything a lot easier and save us O(N)
    // work in some cases... but the implementation DOES work
    //
    //func awarenessWeft(forAtom atomId: AtomId) -> Weft?
    //{
    //    // have to make sure atom exists in the first place
    //    guard let startingAtomIndex = atomYarnsIndex(atomId) else
    //    {
    //        return nil
    //    }
    //
    //    var completedWeft = Weft() //needed to compare against workingWeft to figure out unprocessed atoms
    //    var workingWeft = Weft() //read-only, used to seed nextWeft
    //    var nextWeft = Weft() //acquires buildup from unseen workingWeft atom connections for next loop iteration
    //
    //    workingWeft.update(site: atomId.site, index: yarns[Int(startingAtomIndex)].id.index)
    //
    //    while completedWeft != workingWeft
    //    {
    //        for (site, _) in workingWeft.mapping
    //        {
    //            guard let atomIndex = workingWeft.mapping[site] else
    //            {
    //                assert(false, "atom not found for index")
    //                continue
    //            }
    //
    //            let aYarn = yarn(forSite: site)
    //            assert(!aYarn.isEmpty, "indexed atom came from empty yarn")
    //
    //            // process each un-processed atom in the given yarn; processing means following any causal links to other yarns
    //            for i in (0...atomIndex).reversed()
    //            {
    //                // go backwards through the atoms that we haven't processed yet
    //                if completedWeft.mapping[site] != nil
    //                {
    //                    guard let completedIndex = completedWeft.mapping[site] else
    //                    {
    //                        assert(false, "atom not found for index")
    //                        continue
    //                    }
    //                    if i <= completedIndex
    //                    {
    //                        break
    //                    }
    //                }
    //
    //                enqueueCausalAtom: do
    //                {
    //                    // get the atom
    //                    let aIndex = aYarn.startIndex + Int(i)
    //                    let aAtom = aYarn[aIndex]
    //
    //                    // AB: since we've added the atomIndex method, these don't appear to be necessary any longer for perf
    //                    guard aAtom.cause.site != site else
    //                    {
    //                        break enqueueCausalAtom //no need to check same-site connections since we're going backwards along the weft anyway
    //                    }
    //
    //                    nextWeft.update(site: aAtom.cause.site, index: aAtom.cause.index)
    //                    nextWeft.update(atom: aAtom.reference) //"weak" references indicate awareness, too!
    //                }
    //            }
    //        }
    //
    //        // fill in missing gaps
    //        workingWeft.mapping.forEach(
    //        { (v: (site: SiteId, index: YarnIndex)) in
    //            nextWeft.update(site: v.site, index: v.index)
    //        })
    //        // update completed weft
    //        workingWeft.mapping.forEach(
    //        { (v: (site: SiteId, index: YarnIndex)) in
    //            completedWeft.update(site: v.site, index: v.index)
    //        })
    //        // swap
    //        swap(&workingWeft, &nextWeft)
    //    }
    //
    //    // implicit awareness
    //    completedWeft.update(atom: yarns[Int(startingAtomIndex)].id)
    //    completedWeft.update(atom: yarns[Int(startingAtomIndex)].cause)
    //    completedWeft.update(atom: yarns[Int(startingAtomIndex)].reference)
    //
    //    return completedWeft
    //}
    
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
        var string = "[ "
        for i in 0..<atoms.count
        {
            if i != 0 {
                string += " | "
            }
            let a = atoms[i]
            string += "\(i).\(a.value.atomDescription),\(a.id)"
        }
        string += " ]"
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
        return atoms.count * MemoryLayout<Atom>.size + MemoryLayout<SiteId>.size + MemoryLayout<CRDTCounter<YarnIndex>>.size
    }
    
    ////////////////////////////////////
    // MARK: - Canonical Atom Ordering -
    ////////////////////////////////////
    
    enum ComparisonError: Error
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
    func atomArbitraryOrder(a1: Atom, a2: Atom, basicOnly basic: Bool) throws -> ComparisonResult
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
            
            unparented: do
            {
                if a1.type.unparented && a2.type.unparented
                {
                    let a1a2 = Weave.unparentedAtomOrder(a1: a1.id, a2: a2.id)
                    if a1a2 { return .orderedAscending } else { return .orderedDescending }
                }
                else if a1.type.unparented
                {
                    return .orderedDescending
                }
                else if a2.type.unparented
                {
                    return .orderedAscending
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
    
    // a1 < a2, i.e. "to the left of"; results undefined for non-sibling or unparented atoms
    static func atomSiblingOrder(a1: Atom, a2: Atom) -> Bool
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
    
    // separate from atomSiblingOrder b/c unparented atoms are not really siblings (well... "siblings of the void")
    // results undefined for non-unparented atoms
    static func unparentedAtomOrder(a1: AtomId, a2: AtomId) -> Bool
    {
        return a1 < a2
    }
}
