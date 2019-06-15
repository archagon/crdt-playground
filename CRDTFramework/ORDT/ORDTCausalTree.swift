//
//  ORDTCausalTree.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2018-4-21.
//  Copyright © 2018 Alexei Baboulevitch. All rights reserved.
//

import Foundation

// AB: there are methods marked internal here which are in practice public since this class isn't packaged in a
// framework; unfortunately, using a framework comes with a performance penalty, so there seems to be no way around this

// an ordered collection of atoms and their trees/yarns, for multiple sites
// TODO: DefaultInitializable only used for null start atom, should be optional or something along those lines
public struct ORDTCausalTree
    <ValueT: DefaultInitializable & CRDTValueRelationQueries & CausalTreePriority>
    : ORDT, UsesGlobalLamport
{
    // TODO: remove these
    public init(from decoder: Decoder) throws { fatalError() }
    public func encode(to encoder: Encoder) throws { fatalError() }
    
    public typealias SiteIDT = InstancedLUID
    public typealias OperationT = CausalOperation<ValueT>
    public typealias CollectionT = ArbitraryIndexSlice<OperationT>
    public typealias TimestampWeftT = ORDTLocalTimestampWeft
    public typealias IndexWeftT = ORDTLocalIndexWeft
    
    public var timeFunction: ORDTTimeFunction?
    
    /////////////////
    // MARK: - Data -
    /////////////////
    
    private var atoms: [OperationT] = []
    
    ///////////////////
    // MARK: - Caches -
    ///////////////////
    
    public private(set) var owner: SiteIDT
    
    // these must be updated whenever the canonical data structures above are mutated; do not have to be the same on different sites
    public private(set) var lamportClock: ORDTClock
    public private(set) var indexWeft: ORDTLocalIndexWeft = ORDTLocalIndexWeft()
    public private(set) var timestampWeft: ORDTLocalTimestampWeft = ORDTLocalTimestampWeft()
    private var yarns: [OperationT] = []
    private var yarnsMap: [SiteIDT:CountableClosedRange<Int>] = [:]
    
    //////////////////////
    // MARK: - Lifecycle -
    //////////////////////
    
    // starting from scratch
    public init(owner: SiteIDT)
    {
        self.owner = owner
        self.lamportClock = 0
        
        addBaseYarn: do
        {
            // TODO: figure this out; HLC + lamport of all other ORDTs IN LOCAL DOCUMENT CONTEXT
            let lamportClock = self.timeFunction?() ?? 0
            
            let startAtomId = OperationID.init(logicalTimestamp: lamportClock, index: 0, siteID: owner.id, instanceID: owner.instanceID)
            let startAtom = OperationT.init(id: startAtomId, cause: startAtomId, value: ValueT())
            
            atoms.append(startAtom)
            updateCaches(withAtom: startAtom)
            
            assert(atomWeaveIndex(startAtomId) == WeaveIndex(startAtomId.index))
        }
    }
    
    public mutating func changeOwner(_ owner: SiteIDT)
    {
        self.owner = owner
    }
    
    /////////////////////
    // MARK: - Mutation -
    /////////////////////
    
    public mutating func addAtom(withValue value: ValueT, causedBy cause: OperationT.IDT) -> (atomID: OperationT.IDT,  weaveIndex: WeaveIndex)?
    {
        let atom = OperationT.init(id: generateNextAtomId(forSite: self.owner), cause: cause, value: value)
        
        if let e = integrateAtom(atom)
        {
            return (atom.id, e)
        }
        else
        {
            return nil
        }
    }
    
    // Complexity: O(N)
    private mutating func updateCaches(withAtom atom: OperationT)
    {
        if let existingRange = yarnsMap[atom.id.instancedSiteID]
        {
            assert(existingRange.count == atom.id.index, "adding atom out of order")
            
            let newUpperBound = existingRange.upperBound + 1
            yarns.insert(atom, at: newUpperBound)
            yarnsMap[atom.id.instancedSiteID] = existingRange.lowerBound...newUpperBound
            for (site,range) in yarnsMap
            {
                if range.lowerBound >= newUpperBound
                {
                    yarnsMap[site] = (range.lowerBound + 1)...(range.upperBound + 1)
                }
            }
            indexWeft.update(operation: atom.id)
            timestampWeft.update(operation: atom.id)
        }
        else
        {
            assert(atom.id.index == 0, "adding atom out of order")
            
            yarns.append(atom)
            yarnsMap[atom.id.instancedSiteID] = (yarns.count - 1)...(yarns.count - 1)
            indexWeft.update(operation: atom.id)
            timestampWeft.update(operation: atom.id)
        }
        
        assertCacheIntegrity()
    }
    
    // TODO: combine somehow with updateCaches
    private mutating func generateCacheBySortingAtoms()
    {
        generateYarns: do
        {
            var yarns = self.atoms
            yarns.sort(by:
                { (a1: OperationT, a2: OperationT) -> Bool in
                    if a1.id.instancedSiteID < a2.id.instancedSiteID
                    {
                        return true
                    }
                    else if a1.id.instancedSiteID > a2.id.instancedSiteID
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
                    var indexWeft = ORDTLocalIndexWeft()
                    var timestampWeft = ORDTLocalTimestampWeft()
                    var yarnsMap = [SiteIDT:CountableClosedRange<Int>]()
                    
                    // PERF: we don't have to update each atom -- can simply detect change
                    for i in 0..<self.yarns.count
                    {
                        if let range = yarnsMap[self.yarns[i].id.instancedSiteID]
                        {
                            yarnsMap[self.yarns[i].id.instancedSiteID] = range.lowerBound...i
                        }
                        else
                        {
                            yarnsMap[self.yarns[i].id.instancedSiteID] = i...i
                        }
                        indexWeft.update(operation: self.yarns[i].id)
                        timestampWeft.update(operation: self.yarns[i].id)
                    }
                    
                    self.indexWeft = indexWeft
                    self.timestampWeft = timestampWeft
                    self.yarnsMap = yarnsMap
            }, "CacheGen")
        }
        
        assertCacheIntegrity()
    }
    
    // Complexity: O(1)
    private mutating func generateNextAtomId(forSite site: SiteIDT) -> OperationT.IDT
    {
        self.lamportClock = self.incrementedClock()
        
        if let lastIndex = indexWeft.mapping[site]
        {
            return OperationT.IDT.init(logicalTimestamp: self.lamportClock, index: lastIndex + 1, instancedSiteID: site)
        }
        else
        {
            return OperationT.IDT.init(logicalTimestamp: self.lamportClock, index: 0, instancedSiteID: site)
        }
    }
    
    ////////////////////////
    // MARK: - Integration -
    ////////////////////////
    
    // TODO: make a protocol that atom, value, etc. conform to
    public mutating func remapIndices(_ map: [LUID:LUID])
    {
        self.owner.remapIndices(map)
        
        self.atoms.remapIndices(map)
        
        self.indexWeft.remapIndices(map)
        self.timestampWeft.remapIndices(map)

        self.yarns.remapIndices(map)
        
        yarnsMap: do
        {
            var newYarnsMap = [SiteIDT:CountableClosedRange<Int>]()
            for v in self.yarnsMap
            {
                var newKey = v.key
                newKey.remapIndices(map)
                newYarnsMap[newKey] = v.value
            }
            self.yarnsMap = newYarnsMap
        }
        
        assertCacheIntegrity()
    }
    
    // adds atom as firstmost child of head atom, or appends to end if non-causal; lets us treat weave like an actual tree
    // Complexity: O(N)
    private mutating func integrateAtom(_ atom: OperationT) -> WeaveIndex?
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
                    assert(ORDTCausalTree.atomSiblingOrder(a1: atom, a2: nextAtom), "atom is not ordered correctly")
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
    // TODO: refactor, "basic" no longer needed since Lamport comparison is fast
    public mutating func integrate(_ v: inout ORDTCausalTree)
    {
        typealias Insertion = (localIndex: WeaveIndex, remoteRange: CountableClosedRange<Int>)
        
        //#if DEBUG
        //    let debugCopy = self.copy() as! Weave
        //    let remoteCopy = v.copy() as! Weave
        //#endif
        
        // in order of traversal, so make sure to iterate backwards when actually mutating the weave to keep indices correct
        var insertions: [Insertion] = []
        
        var newAtoms: [OperationT] = []
        newAtoms.reserveCapacity(self.atoms.capacity)
        
        let local = operations()
        let remote = v.operations()
        let localWeft = self.indexWeft
        let remoteWeft = v.indexWeft
        
        var i = local.startIndex
        var j = remote.startIndex
        
        // instead of inserting atoms one-by-one -- an O(N) operation -- we accumulate change ranges and process
        // them later; one of these functions is called with each atom
        // TODO: get rid of this, no longer used
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
        while (i < local.endIndex || j < remote.endIndex) {
            var mergeError: MergeError? = nil
            
            // past local bounds, so just append remote
            if i >= local.endIndex
            {
                commitRemote()
            }
                
            else if j >= remote.endIndex
            {
                commitLocal()
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
            self.lamportClock = max(self.lamportClock, v.lamportClock)
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

        let sitesCount = yarnsMap.keys.count
        let atomsCount = atoms.count

        try vassert(atomsCount >= 1, .noAtoms)
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
                    //let r = atomYarnsIndex((atom as? CRDTValueReference)?.reference ?? NullAtomId)

                    atomChecking: do
                    {
                        try vassert(!cause.value.childless, .childlessAtomHasChildren)
                    }

                    causalityProcessing: do
                    {
                        if a != 0
                        {
                            try vassert(atom.id.logicalTimestamp > yarns[Int(c)].id.logicalTimestamp, .atomUnawareOfParent)
                        }
                        //if let aR = r
                        //{
                        //    try vassert(atom.id.logicalTimestamp > yarns[Int(aR)].id.logicalTimestamp, .atomUnawareOfReference)
                        //}
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

                            let order = ORDTCausalTree.atomSiblingOrder(a1: lastChild, a2: atom)

                            try vassert(order, .incorrectTreeAtomOrder)
                        }
                    }

                    i += 1
                }
            }

            return true
        }
    }
    
    private func assertCacheIntegrity()
    {
        #if DEBUG
            assert(atoms.count == yarns.count, "length mismatch between atoms and yarns")
            assert(yarnsMap.count == indexWeft.mapping.count, "length mismatch between yarns map count and weft site count")
            assert(yarnsMap.count == timestampWeft.mapping.count, "length mismatch between yarns map count and weft site count")
            
            verifyYarnMapCoverage: do
            {
                let sortedYarnMap = yarnsMap.sorted { v0,v1 -> Bool in return v0.value.upperBound < v1.value.lowerBound }
                let totalCount = sortedYarnMap.last!.value.upperBound - sortedYarnMap.first!.value.lowerBound + 1
                
                assert(totalCount == yarns.count, "yarns and yarns map count do not match")
                
                for i in 0..<sortedYarnMap.count
                {
                    if i != 0
                    {
                        assert(sortedYarnMap[i].value.lowerBound == sortedYarnMap[i - 1].value.upperBound + 1, "yarn map is not contiguous")
                    }
                }
            }
            
            var visitedArray = Array<Bool>(repeating: false, count: atoms.count)
            var visitedSites = Set<SiteIDT>()
            
            for i in 0..<atoms.count
            {
                guard let index = atomYarnsIndex(atoms[i].id) else
                {
                    assert(false, "atom not found in yarns")
                }
                
                assert(atoms[i].id == yarns[Int(index)].id, "weave atom does not match yarn atom")
                
                visitedArray[Int(index)] = true
                visitedSites.insert(atoms[i].id.instancedSiteID)
            }
            
            assert(visitedArray.reduce(true) { soFar,val in soFar && val }, "some atoms were not visited")
            assert(Set<SiteIDT>(indexWeft.mapping.keys) == visitedSites, "weft does not have same sites as yarns")
            assert(Set<SiteIDT>(timestampWeft.mapping.keys) == visitedSites, "weft does not have same sites as yarns")
        #endif
    }
    
    //////////////////////////
    // MARK: - Basic Queries -
    //////////////////////////
    
    // Complexity: O(1)
    public func atomForId(_ atomId: OperationT.IDT) -> OperationT?
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
    public func atomYarnsIndex(_ atomId: OperationT.IDT) -> AllYarnsIndex?
    {
        if atomId == NullOperationID
        {
            return nil
        }
        
        if let range = yarnsMap[atomId.instancedSiteID]
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
    public func atomWeaveIndex(_ atomId: OperationT.IDT, searchInReverse: Bool = false) -> WeaveIndex?
    {
        if atomId == NullOperationID
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
    public func lastSiteAtomYarnsIndex(_ site: SiteIDT) -> AllYarnsIndex?
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
    public func lastSiteAtomWeaveIndex(_ site: SiteIDT) -> WeaveIndex?
    {
        var maxIndex: Int? = nil
        for i in 0..<atoms.count
        {
            let a = atoms[i]
            if a.id.instancedSiteID == site
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
    public func atomCount() -> Int
    {
        return atoms.count
    }
    
    // i.e., causal tree branch
    // Complexity: O(N)
    public func causalBlock(forAtomIndexInWeave index: WeaveIndex) -> CountableClosedRange<WeaveIndex>?
    {
        // 0a. an atom always appears to the left of its descendants
        // 0b. an atom always has a lower lamport timestamp than its descendants
        // 0c. causal blocks are always contiguous intervals
        //
        // 1. the first atom not in head's causal block will have a parent to the left of head
        // 2. both head and this atom are part of this parent's causal block
        // 3. therefore, head is necessarily a descendant of parent
        // 4. therefore, head necessarily has a higher timestamp than parent
        // 5. meanwhile, every atom in head's causal block will necessarily have a higher timestamp than head
        // 6. thus: the first atom whose parent has a lower timestamp than head is past the end of the causal block
        
        assert(index < atoms.count)
        
        let head = atoms[Int(index)]
        
        var range: CountableClosedRange<WeaveIndex> = WeaveIndex(index)...WeaveIndex(index)
        
        var i = Int(index) + 1
        while i < atoms.count
        {
            let nextAtom = atoms[i]
            let nextAtomParent: OperationT! = atomForId(nextAtom.cause)
            assert(nextAtomParent != nil, "could not find atom parent")
            
            if nextAtomParent.id != head.id && head.id.logicalTimestamp > nextAtomParent.id.logicalTimestamp
            {
                break
            }
            
            range = range.lowerBound...WeaveIndex(i)
            i += 1
        }
        
        assert(!head.value.childless || range.count == 1, "childless atom seems to have children")
        
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
    
    public func superset(_ v: inout ORDTCausalTree) -> Bool
    {
        assert(false, "don't compare weaves directly -- compare through the top-level CRDT")
        return false
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
            string += "\(i).\(a.value),\(a.cause)->\(a.id),T\(a.id.logicalTimestamp)"
            // NEXT:
            //string += "\(i).\(a.value.atomDescription),\(a.cause)->\(a.id),T\(a.timestamp)"
        }
        string += " ]"
        return string
    }
    
    public var debugDescription: String
    {
        get
        {
            let allSites = Array(indexWeft.mapping.keys).sorted()
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
                string += "\(i):\(indexWeft.mapping[allSites[i]]!)"
            }
            string += "]"
            return string
        }
    }
    
    public func sizeInBytes() -> Int
    {
        return atoms.count * MemoryLayout<OperationT>.size + MemoryLayout<SiteId>.size + MemoryLayout<CRDTCounter<YarnIndex>>.size
    }
    
    public static func ==(lhs: ORDTCausalTree, rhs: ORDTCausalTree) -> Bool
    {
        return lhs.indexWeft == rhs.indexWeft
    }

    public func hash(into hasher: inout Hasher)
    {
        hasher.combine(indexWeft)
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
    public func atomArbitraryOrder(a1: OperationT, a2: OperationT, basicOnly basic: Bool) throws -> ComparisonResult
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
            let atomToCompare1: OperationT.IDT
            let atomToCompare2: OperationT.IDT
            
            lastCommonAncestor: do
            {
                var causeChain1: ContiguousArray<OperationT.IDT> = [a1.id]
                var causeChain2: ContiguousArray<OperationT.IDT> = [a2.id]
                
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
            
            let a1a2 = ORDTCausalTree.atomSiblingOrder(a1: a1, a2: a2)
            if a1a2 { return .orderedAscending } else { return .orderedDescending }
        }
    }
    
    // a1 < a2, i.e. "to the left of"; results undefined for non-sibling atoms
    public static func atomSiblingOrder(a1: OperationT, a2: OperationT) -> Bool
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
            if a1.id.logicalTimestamp == a2.id.logicalTimestamp
            {
                return a1.id.instancedSiteID > a2.id.instancedSiteID
            }
            else
            {
                return a1.id.logicalTimestamp > a2.id.logicalTimestamp
            }
        }
    }
}

// TODO: handle these later
extension ORDTCausalTree
{
    public func operations(withWeft weft: ORDTLocalTimestampWeft?) -> ArbitraryIndexSlice<CausalOperation<ValueT>>
    {
        if weft == nil || weft == self.timestampWeft
        {
            return CollectionT.init(self.atoms, withValidIndices: nil)
        }
        
        assert(false)
        return CollectionT.init([], withValidIndices: nil)
    }
    
    public func yarn(forSite site: InstancedLUID, withWeft weft: ORDTLocalTimestampWeft?) -> ArbitraryIndexSlice<CausalOperation<ValueT>>
    {
        if weft == nil || weft == self.timestampWeft, let range = self.yarnsMap[site], let f = range.first, let l = range.last
        {
            return CollectionT.init(self.yarns, withValidIndices: [f..<(l+1)])
        }
        
        assert(false)
        return CollectionT.init([], withValidIndices: nil)
    }
    
    public func revision(_ weft: ORDTLocalTimestampWeft?) -> ORDTCausalTree
    {
        fatalError()
    }
    
    public func setBaseline(_ weft: ORDTLocalTimestampWeft) throws {
        throw SetBaselineError.notSupported
    }
    public var baseline: ORDTLocalTimestampWeft? { return nil }
}
