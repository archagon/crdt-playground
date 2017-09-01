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

protocol DefaultInitializable {
    init()
}
extension UUID: DefaultInitializable {}
extension String: DefaultInitializable {}

protocol Zeroable {
    static var zero: Self { get }
}
extension UUID: Zeroable {
    static var zero = UUID(uuid: uuid_t((0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)))
}

// an ordered collection of yarns for multiple sites
// TODO: store as an actual weave? prolly not worth it -- mostly useful for transmission
class Weave<
    SiteUUIDT: DefaultInitializable & CustomStringConvertible & Hashable & Zeroable,
    ValueT: DefaultInitializable & CustomStringConvertible>
{
    // NEXT: read paper again, figure o ut how site ids (esp. on new user join) and awareness wefts are handled
    // NEXT: why does closed weft include end token?
    // NEXT: caching awareness wefts: ??? local only? atom site indexing on transfer?
    typealias SiteId = Int16 //warning: older atoms might have different site ids, since we use lexographic order!
    typealias Clock = Int32
    
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
    
    struct Atom: Comparable {
        let id: AtomId
        let cause: AtomId
        let value: ValueT
        
        public static func <(lhs: Atom, rhs: Atom) -> Bool {
            return lhs.id < rhs.id
        }
        public static func <=(lhs: Atom, rhs: Atom) -> Bool {
            return lhs.id <= rhs.id
        }
        public static func >=(lhs: Atom, rhs: Atom) -> Bool {
            return lhs.id >= rhs.id
        }
        public static func >(lhs: Atom, rhs: Atom) -> Bool {
            return lhs.id > rhs.id
        }
        public static func ==(lhs: Atom, rhs: Atom) -> Bool {
            return lhs.id == rhs.id
        }
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
    
    // TODO: not actually solid chunk
    var sites: ContiguousArray<SiteUUIDT> = [] //list of site global ids; regular site id is index into this array
    var yarns: Array<ContiguousArray<Atom>> = [] //solid, 2d chunk of memory for optimal performance
    
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
        
        if aYarn.count == 0 {
            return nil
        }
        
        var returnI = -1
        for (_, v) in aYarn.enumerated() {
            if v.id.clock > commit {
                break
            }
            returnI += 1
        }
        
        if returnI == -1 {
            return nil
        }
        else if equalOnly && aYarn[aYarn.index(aYarn.startIndex, offsetBy: Int64(returnI))].id.clock != commit {
            return nil
        }
        else {
            return returnI
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
    
    // for debugging
    func addRandomYarn(withCount count: Int, randomGenerator: (()->ValueT)? = nil) -> SiteUUIDT {
        let uuid = SiteUUIDT()
        assert(siteId(forSite: uuid) == nil)
        
        sites.append(uuid)
        yarns.append(ContiguousArray<Atom>())
        let yarnIndex = Int(siteId(forSite: uuid)!)
        
        let minCount = min(15, count)
        let realCount = max(0, count - minCount)
        let amount = minCount + Int(arc4random_uniform(UInt32(realCount + 1)))
        
        let clockStart = type(of: self).StartClock + 1 + Clock(arc4random_uniform(100))
        let clockVariance = 10
        var lastClock: Clock = -1
        var currentClock: Clock = clockStart
        
        for _ in 0..<amount {
            let element: ValueT
            if let randomGenerator = randomGenerator {
                element = randomGenerator()
            }
            else {
                element = ValueT()
            }
            
            let causeSiteDelta: Int
            let causeAtomDelta: Int
            
            calculateCauseDelta: do {
                if arc4random_uniform(5) == 0 {
                    causeSiteDelta = ((arc4random_uniform(2) == 0 ? -1 : -1) * 1)
                }
                else if arc4random_uniform(10) == 0 {
                    causeSiteDelta = ((arc4random_uniform(2) == 0 ? -1 : -1) * 2)
                }
                else {
                    causeSiteDelta = 0
                }
                
                if causeSiteDelta !=  0 {
                    if arc4random_uniform(2) == 0 {
                        causeAtomDelta = ((arc4random_uniform(2) == 0 ? +1 : -1) * 1)
                    }
                    else if arc4random_uniform(5) == 0 {
                        causeAtomDelta = ((arc4random_uniform(2) == 0 ? +1 : -1) * 2)
                    }
                    else if arc4random_uniform(10) == 0 {
                        causeAtomDelta = (Int(arc4random_uniform(2) == 0 ? +1 : -1) * Int(3 + arc4random_uniform(5)))
                    }
                    else {
                        causeAtomDelta = 0
                    }
                }
                else {
                    if lastClock == -1 {
                        causeAtomDelta = 0
                    }
                    else {
                        causeAtomDelta = -1
                    }
                }
            }
            
            var cause: AtomId? = nil
            
            findCauseAtom: do {
                let causeYarnIndex = yarnIndex + causeSiteDelta
                let causeAtomIndex = yarns[yarnIndex].count + causeAtomDelta
                
                if causeYarnIndex >= 0 && causeYarnIndex < yarns.count {
                    if causeAtomIndex >= 0 && causeAtomIndex < yarns[causeYarnIndex].count {
                        cause = yarns[causeYarnIndex][causeAtomIndex].id
                    }
                }
            }
            
            let atom = Atom(id: AtomId(site: Weave.SiteId(yarnIndex), clock: currentClock), cause: (cause ?? Weave.NullAtomId), value: element)
            yarns[yarnIndex].append(atom)
            lastClock = currentClock
            currentClock += 1 + Clock(arc4random_uniform(UInt32(clockVariance + 1)))
        }
        
        debugPrint: do {
            break debugPrint
            var output = "Added yarn \(uuid) (\(yarnIndex)):"
            
            for v in yarns[yarnIndex] {
                output += " \(v.id.clock):\(v.value.description)"
            }
            
            print(output)
        }
        
        return uuid
    }
}

func WeaveHardConcurrency(_ weave: inout Weave<UUID, String>) {
    let weaveT = type(of: weave)
    
    weave.clear()
    
    let a = UUID()
    let b = UUID()
    let c = UUID()
    let d = UUID()
    
    let a1 = weave.add(value: "ø", forSite: a, causedBy: weaveT.AtomId(site: weaveT.ControlSite, clock: weaveT.EndClock))
    let a2 = weave.add(value: "1", forSite: a, causedBy: weaveT.AtomId(site: weaveT.ControlSite, clock: weaveT.StartClock))
    let a3 = weave.add(value: "2", forSite: a, causedBy: a2)
    let a4 = weave.add(value: "3", forSite: a, causedBy: a3)
    let a5 = weave.add(value: "4", forSite: a, causedBy: a4)
    
    let b1 = weave.add(value: "ø", forSite: b, causedBy: a1)
    let b2 = weave.add(value: "ø", forSite: b, causedBy: a4)
    let b3 = weave.add(value: "5", forSite: b, causedBy: a2)
    let b4 = weave.add(value: "6", forSite: b, causedBy: a3)
    let b5 = weave.add(value: "7", forSite: b, causedBy: b4)
    
    let c1 = weave.add(value: "ø", forSite: c, causedBy: b5)
    
    let d1 = weave.add(value: "ø", forSite: d, causedBy: a1)
    let d2 = weave.add(value: "ø", forSite: d, causedBy: b5)
    
    let a6 = weave.add(value: "ø", forSite: a, causedBy: b5)
    
    let c2 = weave.add(value: "ø", forSite: c, causedBy: a6)
    let c3 = weave.add(value: "8", forSite: c, causedBy: a5)
    let c4 = weave.add(value: "9", forSite: c, causedBy: c3)
    let c5 = weave.add(value: "a", forSite: c, causedBy: c4)
    let c6 = weave.add(value: "b", forSite: c, causedBy: b5)
    
    let d3 = weave.add(value: "ø", forSite: d, causedBy: c6)
    let d4 = weave.add(value: "c", forSite: d, causedBy: b4)
    let d5 = weave.add(value: "d", forSite: d, causedBy: d4)
    let d6 = weave.add(value: "e", forSite: d, causedBy: d5)
    let d7 = weave.add(value: "f", forSite: d, causedBy: d6)
    let d8 = weave.add(value: "g", forSite: d, causedBy: c6)
    
    let a7 = weave.add(value: "ø", forSite: a, causedBy: c6)
    let a8 = weave.add(value: "ø", forSite: a, causedBy: d8)
    
    let b6 = weave.add(value: "ø", forSite: b, causedBy: c6)
    let b7 = weave.add(value: "ø", forSite: b, causedBy: d8)
    
    let c7 = weave.add(value: "ø", forSite: c, causedBy: d8)
    
    // hacky warning suppression
    let _ = [a1,a2,a3,a4,a5,a6,a7,a8, b1,b2,b3,b4,b5,b6,b7, c1,c2,c3,c4,c5,c6,c7, d1,d2,d3,d4,d5,d6,d7,d8]
}

// does not account for sync points
func WeaveTypingSimulation(_ weave: inout WeaveT) {
    weave.clear()
    
    let minSites = 3
    let maxSites = 10
    let minAverageYarnAtoms = 20
    let maxAverageYarnAtoms = 100
    let minRunningSequence = 1
    let maxRunningSequence = 20
    
    var characters = ["a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p","q","r","s","t","u","v","w","x","y","z"]
    characters += [" "," "," "," "," "," "," "]
    let stringRandomGen = { return characters[Int(arc4random_uniform(UInt32(characters.count)))] }
    
    let numberOfSites = minSites + Int(arc4random_uniform(UInt32(maxSites - minSites + 1)))
    var siteUUIDs: [UUID] = []
    var siteIds: [WeaveT.SiteId] = []
    var siteAtoms: [WeaveT.SiteId:Int] = [:]
    var siteAtomTotal: [WeaveT.SiteId:Int] = [:]
    
    for _ in 0..<numberOfSites {
        let siteUUID = UUID()
        let siteId = weave.addYarn(forSite: siteUUID)
        siteUUIDs.append(siteUUID)
        siteIds.append(siteId)
        let siteAtomsCount = minAverageYarnAtoms + Int(arc4random_uniform(UInt32(maxAverageYarnAtoms - minAverageYarnAtoms + 1)))
        siteAtoms[siteId] = siteAtomsCount
    }
    
    // hook up first yarn
    let _ = weave.add(value: "ø", forSite: siteUUIDs[0], causedBy: WeaveT.AtomId(site: WeaveT.ControlSite, clock: WeaveT.EndClock))
    siteAtomTotal[siteIds[0]] = 1
    
    while siteAtoms.reduce(0, { (total,pair) in total+pair.value }) != 0 {
        let randomSiteIndex = Int(arc4random_uniform(UInt32(siteIds.count)))
        let randomSite = siteIds[randomSiteIndex]
        let randomSiteUUID = siteUUIDs[randomSiteIndex]
        let atomsToSequentiallyAdd = min(minRunningSequence + Int(arc4random_uniform(UInt32(maxRunningSequence - minRunningSequence + 1))), siteAtoms[randomSite]!)
        
        // pick random, non-self yarn with atoms in it for attachment point
        let array = Array(siteAtomTotal)
        let randomCausalSite = array[Int(arc4random_uniform(UInt32(array.count)))].key
        let yarn = weave.yarn(forSite: randomCausalSite)
        let atomCount = yarn.count
        
        // pick random atom for attachment
        let randomAtom = Int(arc4random_uniform(UInt32(atomCount)))
        let randomIndex = yarn.index(yarn.startIndex, offsetBy: Int64(randomAtom))
        let atom = yarn[randomIndex]
        
        var lastAtomId = atom.id
        for _ in 0..<atomsToSequentiallyAdd {
            lastAtomId = weave.add(value: stringRandomGen(), forSite: randomSiteUUID, causedBy: lastAtomId)
        }
        
        siteAtoms[randomSite]! -= atomsToSequentiallyAdd
        if siteAtomTotal[randomSite] == nil {
            siteAtomTotal[randomSite] = atomsToSequentiallyAdd
        }
        else {
            siteAtomTotal[randomSite]! += atomsToSequentiallyAdd
        }
        if siteAtoms[randomSite]! <= 0 {
            let index = siteIds.index(of: randomSite)!
            siteIds.remove(at: index)
            siteUUIDs.remove(at: index)
            siteAtoms.removeValue(forKey: randomSite)
        }
    }
}

func WeaveTest(_ weave: inout WeaveT) {
    var characters = ["a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p","q","r","s","t","u","v","w","x","y","z"]
    characters += [" "," "," "," "," "," "," "]
    let stringRandomGen = { return characters[Int(arc4random_uniform(UInt32(characters.count)))] }
    
    var yarns: [UUID] = []
    
    print("Generating yarns...")
    for _ in 0..<5 {
        let uuid = weave.addRandomYarn(withCount: 500, randomGenerator: stringRandomGen)
        yarns.append(uuid)
    }
    
    print("\n")
    print("---------")
    print("\n")
    
    print("Checking yarns...")
    print("\n")
    for i in 0..<yarns.count {
        var contents = "Yarn \(yarns[i]):"
        for v in weave.yarn(forSite: weave.siteId(forSite: yarns[i])!, upToCommit: 100).enumerated() {
            contents += " \(v.element.id.clock):\(v.element.value)"
        }
        print(contents)
    }
    print("\n")
}
