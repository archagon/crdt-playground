//
//  CRDTTesting.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-9-5.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import Foundation

extension Weave {
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
            
            let atom = Atom(id: AtomId(site: SiteId(yarnIndex), clock: currentClock), cause: (cause ?? Weave.NullAtomId), value: element)
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
    let maxAverageYarnAtoms = 1500
    let minRunningSequence = 1
    let maxRunningSequence = 20
    
    var characters = ["a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p","q","r","s","t","u","v","w","x","y","z"]
    characters += [" "," "," "," "," "," "," "]
    let stringRandomGen = { return characters[Int(arc4random_uniform(UInt32(characters.count)))] }
    
    let numberOfSites = minSites + Int(arc4random_uniform(UInt32(maxSites - minSites + 1)))
    var siteUUIDs: [UUID] = []
    var siteIds: [SiteId] = []
    var siteAtoms: [SiteId:Int] = [:]
    var siteAtomTotal: [SiteId:Int] = [:]
    
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
