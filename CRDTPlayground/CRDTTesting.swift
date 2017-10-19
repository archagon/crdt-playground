//
//  CRDTTesting.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-9-5.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import Foundation
import CRDTFramework_OSX

fileprivate func k(_ s: String) -> UTF8Char { return s.utf8.first! }
fileprivate func t() -> Clock { return Clock(Date().timeIntervalSinceReferenceDate * 1000 * 1000) } //hacky microseconds

func WeaveHardConcurrency() -> CausalTreeTextT
{
    let ai = UUID()
    let bi = UUID()
    let ci = UUID()
    let di = UUID()
    
    let tree = CausalTreeTextT(site: ai, clock: t())
    
    let a = tree.siteIndex.siteMapping()[ai]!
    let b = tree.siteIndex.addSite(bi, withClock: t())
    let c = tree.siteIndex.addSite(ci, withClock: t())
    let d = tree.siteIndex.addSite(di, withClock: t())
    
    let startId = AtomId(site: ControlSite, index: 0)
    let endId = AtomId(site: ControlSite, index: 1)
    
    let a1 = tree.weave._debugAddAtom(atSite: a, withValue: k("ø"), causedBy: endId, atTime: t(), noCommit: true)!.0
    let a2 = tree.weave._debugAddAtom(atSite: a, withValue: k("1"), causedBy: startId, atTime: t(), noCommit: true)!.0
    let a3 = tree.weave._debugAddAtom(atSite: a, withValue: k("2"), causedBy: a2, atTime: t(), noCommit: true)!.0
    let a4 = tree.weave._debugAddAtom(atSite: a, withValue: k("3"), causedBy: a3, atTime: t(), noCommit: true)!.0
    let a5 = tree.weave._debugAddAtom(atSite: a, withValue: k("4"), causedBy: a4, atTime: t(), noCommit: true)!.0
    
    let b1 = tree.weave._debugAddAtom(atSite: b, withValue: k("ø"), causedBy: a1, atTime: t(), noCommit: true)!.0
    let b2 = tree.weave._debugAddAtom(atSite: b, withValue: k("ø"), causedBy: a4, atTime: t(), noCommit: true)!.0
    let b3 = tree.weave._debugAddAtom(atSite: b, withValue: k("5"), causedBy: a2, atTime: t(), noCommit: true)!.0
    let b4 = tree.weave._debugAddAtom(atSite: b, withValue: k("6"), causedBy: a3, atTime: t(), noCommit: true)!.0
    let b5 = tree.weave._debugAddAtom(atSite: b, withValue: k("7"), causedBy: b4, atTime: t(), noCommit: true)!.0
    
    let c1 = tree.weave._debugAddAtom(atSite: c, withValue: k("ø"), causedBy: b5, atTime: t(), noCommit: true)!.0
    
    let d1 = tree.weave._debugAddAtom(atSite: d, withValue: k("ø"), causedBy: a1, atTime: t(), noCommit: true)!.0
    let d2 = tree.weave._debugAddAtom(atSite: d, withValue: k("ø"), causedBy: b5, atTime: t(), noCommit: true)!.0
    
    let a6 = tree.weave._debugAddAtom(atSite: a, withValue: k("ø"), causedBy: b5, atTime: t(), noCommit: true)!.0
    
    let c2 = tree.weave._debugAddAtom(atSite: c, withValue: k("ø"), causedBy: a6, atTime: t(), noCommit: true)!.0
    let c3 = tree.weave._debugAddAtom(atSite: c, withValue: k("8"), causedBy: a5, atTime: t(), noCommit: true)!.0
    let c4 = tree.weave._debugAddAtom(atSite: c, withValue: k("9"), causedBy: c3, atTime: t(), noCommit: true)!.0
    let c5 = tree.weave._debugAddAtom(atSite: c, withValue: k("a"), causedBy: c4, atTime: t(), noCommit: true)!.0
    let c6 = tree.weave._debugAddAtom(atSite: c, withValue: k("b"), causedBy: b5, atTime: t(), noCommit: true)!.0
    
    let d3 = tree.weave._debugAddAtom(atSite: d, withValue: k("ø"), causedBy: c6, atTime: t(), noCommit: true)!.0
    let d4 = tree.weave._debugAddAtom(atSite: d, withValue: k("c"), causedBy: b4, atTime: t(), noCommit: true)!.0
    let d5 = tree.weave._debugAddAtom(atSite: d, withValue: k("d"), causedBy: d4, atTime: t(), noCommit: true)!.0
    let d6 = tree.weave._debugAddAtom(atSite: d, withValue: k("e"), causedBy: d5, atTime: t(), noCommit: true)!.0
    let d7 = tree.weave._debugAddAtom(atSite: d, withValue: k("f"), causedBy: d6, atTime: t(), noCommit: true)!.0
    let d8 = tree.weave._debugAddAtom(atSite: d, withValue: k("g"), causedBy: c6, atTime: t(), noCommit: true)!.0
    
    let a7 = tree.weave._debugAddAtom(atSite: a, withValue: k("ø"), causedBy: c6, atTime: t(), noCommit: true)!.0
    let a8 = tree.weave._debugAddAtom(atSite: a, withValue: k("ø"), causedBy: d8, atTime: t(), noCommit: true)!.0
    
    let b6 = tree.weave._debugAddAtom(atSite: b, withValue: k("ø"), causedBy: c6, atTime: t(), noCommit: true)!.0
    let b7 = tree.weave._debugAddAtom(atSite: b, withValue: k("ø"), causedBy: d8, atTime: t(), noCommit: true)!.0
    
    let c7 = tree.weave._debugAddAtom(atSite: c, withValue: k("ø"), causedBy: d8, atTime: t(), noCommit: true)!.0
    
    // hacky warning suppression
    let _ = [a1,a2,a3,a4,a5,a6,a7,a8, b1,b2,b3,b4,b5,b6,b7, c1,c2,c3,c4,c5,c6,c7, d1,d2,d3,d4,d5,d6,d7,d8]
    
    return tree
}

func WeaveHardConcurrencyAutocommit() -> CausalTreeTextT
{
    let ai = UUID()
    let bi = UUID()
    let ci = UUID()
    let di = UUID()
    
    let tree = CausalTreeTextT(site: ai, clock: t())
    
    let a = tree.siteIndex.siteMapping()[ai]!
    let b = tree.siteIndex.addSite(bi, withClock: t())
    let c = tree.siteIndex.addSite(ci, withClock: t())
    let d = tree.siteIndex.addSite(di, withClock: t())
    
    let startId = AtomId(site: ControlSite, index: 0)
    
    let a2 = tree.weave._debugAddAtom(atSite: a, withValue: k("1"), causedBy: startId, atTime: t(), noCommit: false)!.0
    let a3 = tree.weave._debugAddAtom(atSite: a, withValue: k("2"), causedBy: a2, atTime: t(), noCommit: false)!.0
    let a4 = tree.weave._debugAddAtom(atSite: a, withValue: k("3"), causedBy: a3, atTime: t(), noCommit: false)!.0
    let a5 = tree.weave._debugAddAtom(atSite: a, withValue: k("4"), causedBy: a4, atTime: t(), noCommit: false)!.0
    
    let b3 = tree.weave._debugAddAtom(atSite: b, withValue: k("5"), causedBy: a2, atTime: t(), noCommit: false)!.0
    let b4 = tree.weave._debugAddAtom(atSite: b, withValue: k("6"), causedBy: a3, atTime: t(), noCommit: false)!.0
    let b5 = tree.weave._debugAddAtom(atSite: b, withValue: k("7"), causedBy: b4, atTime: t(), noCommit: false)!.0
    
    let c3 = tree.weave._debugAddAtom(atSite: c, withValue: k("8"), causedBy: a5, atTime: t(), noCommit: false)!.0
    let c4 = tree.weave._debugAddAtom(atSite: c, withValue: k("9"), causedBy: c3, atTime: t(), noCommit: false)!.0
    let c5 = tree.weave._debugAddAtom(atSite: c, withValue: k("a"), causedBy: c4, atTime: t(), noCommit: false)!.0
    let c6 = tree.weave._debugAddAtom(atSite: c, withValue: k("b"), causedBy: b5, atTime: t(), noCommit: false)!.0
    
    let d4 = tree.weave._debugAddAtom(atSite: d, withValue: k("c"), causedBy: b4, atTime: t(), noCommit: false)!.0
    let d5 = tree.weave._debugAddAtom(atSite: d, withValue: k("d"), causedBy: d4, atTime: t(), noCommit: false)!.0
    let d6 = tree.weave._debugAddAtom(atSite: d, withValue: k("e"), causedBy: d5, atTime: t(), noCommit: false)!.0
    let d7 = tree.weave._debugAddAtom(atSite: d, withValue: k("f"), causedBy: d6, atTime: t(), noCommit: false)!.0
    let d8 = tree.weave._debugAddAtom(atSite: d, withValue: k("g"), causedBy: c6, atTime: t(), noCommit: false)!.0
    
    // hacky warning suppression
    let _ = [a2,a3,a4,a5, b3,b4,b5, c3,c4,c5,c6, d4,d5,d6,d7,d8]
    
    return tree
}

// does not account for sync points
func WeaveTypingSimulation(_ amount: Int) -> CausalTreeTextT
{
    let minSites = 3
    let maxSites = 10
    let minAverageYarnAtoms = min(amount, 100)
    let maxAverageYarnAtoms = amount
    let minRunningSequence = 1
    let maxRunningSequence = 20
    let attachRange = 100
    
    var stringCharacters = ["a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p","q","r","s","t","u","v","w","x","y","z"]
    stringCharacters += [" "," "," "," "," "," "," "]
    let characters = stringCharacters.map { $0.utf8.first! }
    
    let stringRandomGen = { return characters[Int(arc4random_uniform(UInt32(characters.count)))] }
    
    let numberOfSites = minSites + Int(arc4random_uniform(UInt32(maxSites - minSites + 1)))
    var siteUUIDs: [UUID] = []
    var siteIds: [SiteId] = []
    var siteAtoms: [SiteId:Int] = [:]
    var siteAtomTotal: [SiteId:Int] = [:]
    
    var tree: CausalTreeTextT!
    
    for _ in 0..<numberOfSites
    {
        let siteUUID = UUID()
        let siteId: SiteId
        
        if tree == nil
        {
            tree = CausalTreeTextT(site: siteUUID, clock: t())
            siteId = tree.siteIndex.siteMapping()[siteUUID]!
        }
        else
        {
            siteId = tree.siteIndex.addSite(siteUUID, withClock: t())
        }
        
        siteUUIDs.append(siteUUID)
        siteIds.append(siteId)
        let siteAtomsCount = minAverageYarnAtoms + Int(arc4random_uniform(UInt32(maxAverageYarnAtoms - minAverageYarnAtoms + 1)))
        siteAtoms[siteId] = siteAtomsCount
    }
    
    // hook up first yarn
    let _ = tree.weave.addAtom(withValue: k("ø"), causedBy: AtomId(site: ControlSite, index: 1), atTime: t())
    siteAtomTotal[siteIds[0]] = 1
    
    while siteAtoms.reduce(0, { (total,pair) in total+pair.value }) != 0
    {
        let randomSiteIndex = Int(arc4random_uniform(UInt32(siteIds.count)))
        let randomSite = siteIds[randomSiteIndex]
        let randomSiteUUID = siteUUIDs[randomSiteIndex]
        let atomsToSequentiallyAdd = min(minRunningSequence + Int(arc4random_uniform(UInt32(maxRunningSequence - minRunningSequence + 1))), siteAtoms[randomSite]!)
        
        // pick random, non-self yarn with atoms in it for attachment point
        let array = Array(siteAtomTotal)
        let randomCausalSite = array[Int(arc4random_uniform(UInt32(array.count)))].key
        let yarn = tree.weave.yarn(forSite: randomCausalSite)
        let atomCount = yarn.count
        
        // pick random atom for attachment
        let randomAtom = Int(arc4random_uniform(UInt32(atomCount)))
        let randomIndex = yarn.startIndex + randomAtom
        let atom = yarn[randomIndex]
        
        var lastAtomId = atom.id
        for _ in 0..<atomsToSequentiallyAdd
        {
            timeMe({
                lastAtomId = tree.weave._debugAddAtom(atSite: randomSite, withValue: stringRandomGen(), causedBy: lastAtomId, atTime: t(), noCommit: true)!.0
            }, "AtomAdd", every: 250)
        }
        
        siteAtoms[randomSite]! -= atomsToSequentiallyAdd
        if siteAtomTotal[randomSite] == nil
        {
            siteAtomTotal[randomSite] = atomsToSequentiallyAdd
        }
        else
        {
            siteAtomTotal[randomSite]! += atomsToSequentiallyAdd
        }
        if siteAtoms[randomSite]! <= 0
        {
            let index = siteIds.index(of: randomSite)!
            siteIds.remove(at: index)
            siteUUIDs.remove(at: index)
            siteAtoms.removeValue(forKey: randomSite)
        }
    }
    
    let total = siteAtomTotal.reduce(0) { (r:Int, v:(key:SiteId, val:Int)) -> Int in return r + v.val }
    print("Total test atoms: \(total)")
    
    return tree
}
