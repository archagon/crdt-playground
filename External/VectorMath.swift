//
//  CRDTCausalTrees.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-8-28.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import Foundation

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
    typealias SiteId = Int16
    typealias Clock = Int32
    
    struct AtomId {
        let site: SiteId
        let clock: Clock
    }
    
    struct Atom {
        let id: AtomId
        let cause: AtomId?
        let value: ValueT
    }
    
    // no other atoms can have these clock numbers
    static var ControlSite: SiteId { get { return SiteId(0) }}
    static var StartClock: Clock { get { return Clock(1) }}
    static var EndClock: Clock { get { return Clock(2) }}
    
    // TODO: not actually solid chunk
    var sites: ContiguousArray<SiteUUIDT> = [] // list of site global ids; regular site id is index into this array
    var yarns: Array<ContiguousArray<Atom>> = [] // solid, 2d chunk of memory for optimal performance
    
    init() {
        clear()
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
    
    // a weave up to and including the provided commits, or everything if nil, with omitted site ids also be omitted in the return collection
//    func weave(forCommits commits: [SiteId: Int?]) -> AnyBidirectionalCollection<AnyBidirectionalCollection<(time: Int, value: ValueT)>> {
////        let collection = AnyBidirectionalCollection(yarns)
////        return collection
//    }
    
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
    
    func clear() {
        yarns.removeAll(keepingCapacity: true)
        addBaseYarn()
    }
    
    // TODO: PERF: very slow, use binary search
    // last index, inclusive, for <= commit
    func index(forSite site: SiteId, beforeCommit commit: Clock, equalOnly: Bool = false) -> Int? {
        let aYarn = yarn(forSite: site)
        
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
    
    private func addBaseYarn() {
        let uuid = SiteUUIDT.zero
        assert(siteId(forSite: uuid) == nil)
        
        sites.append(uuid)
        yarns.append(ContiguousArray<Atom>())
        let yarnIndex = Int(siteId(forSite: uuid)!)
        let aSiteId = SiteId(yarnIndex)
        assert(aSiteId == type(of: self).ControlSite)
        
        let startAtom = Atom(id: AtomId(site: aSiteId, clock: type(of: self).StartClock), cause: nil, value: ValueT())
        let endAtom = Atom(id: AtomId(site: aSiteId, clock: type(of: self).EndClock), cause: startAtom.id, value: ValueT())
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
        
        let minCount = 50
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
            
            let atom = Atom(id: AtomId(site: Weave.SiteId(yarnIndex), clock: currentClock),
                            cause: cause,
                            value: element)
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

func WeaveTest(_ weave: inout Weave<UUID, String>) {
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
