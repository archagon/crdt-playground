//
//  CRDTCausalTreesWeaveDeprecated.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-10-10.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

/* Before, we used "awareness wefts" to sort sibling atoms. This was expensive, often with a O(weave) factor, and
 prevented us from validating CTs with large numbers of sites. With Lamport timestamps, this is no longer a concern.
 However, the awareness code is still valid and might prove useful in the future. */

import Foundation

extension Weave
{
    ///
    /// **Preconditions:** The atom must be part of the weave.
    ///
    /// **Complexity:** O(weave)
    ///
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
    
    func addCommit(fromSite: SiteId, toSite: SiteId) -> (AtomId, WeaveIndex)?
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
        let commitAtom = Atom(id: generateNextAtomId(forSite: fromSite), cause: NullAtomId, type: .commit, timestamp: lamportTimestamp.increment(), value: ValueT(), reference: lastCommitSiteAtom.id)
        
        if let e = integrateAtom(commitAtom)
        {
            return (commitAtom.id, e)
        }
        else
        {
            return nil
        }
    }
    
    func generateCompleteAwareness()
    {
        let minCutoff = 20
        let sitesCount = Int(yarnsMap.keys.max() ?? 0) + 1
        let atomsCount = atoms.count
        let logAtomsCount = Int(log2(Double(atomsCount == 0 ? 1 : atomsCount)))
        
        var atomAwareness = ContiguousArray<Int>(repeating: -1, count: atomsCount * sitesCount)
        
        // these all use yarns layout
        // TODO: unify this with regular awareness calculation; move everything over to ContiguousArray?
        var awarenessProcessingQueue = ContiguousArray<Int>()
        awarenessProcessingQueue.reserveCapacity(atomsCount)
        func awareness(forAtom a: Int) -> ArraySlice<Int>
        {
            return atomAwareness[(a * sitesCount)..<((a * sitesCount) + sitesCount)]
        }
        func updateAwareness(forAtom a1: Int, fromAtom a2: Int)
        {
            if a1 == -1 || a2 == -1 { return }
            for s in 0..<sitesCount
            {
                atomAwareness[(a1 * sitesCount) + s] = max(atomAwareness[(a1 * sitesCount) + s], atomAwareness[(a2 * sitesCount) + s])
            }
        }
        func compareAwareness(a1: Int, a2: Int) -> Bool
        {
            return atomAwareness[(a1 * sitesCount)..<((a1 * sitesCount) + sitesCount)].lexicographicallyPrecedes(atomAwareness[(a2 * sitesCount)..<((a2 * sitesCount) + sitesCount)])
        }
        func aware(a1: Int, of a2: Int) -> Bool
        {
            return compareAwareness(a1: a2, a2: a1)
        }
        func awarenessCalculated(a: Int) -> Bool
        {
            // every tree atom is necessarily aware of the first atom
            return atomAwareness[(a * sitesCount) + 0] != -1
        }
        
        // preseed atom 0 awareness
        atomAwareness[0] = 0
        
        // We can calculate awareness in dependency order by iterating over our atoms in absolute temporal
        // order. We don't have this information for all combined sites, but we do have it for each individual
        // site, and so we can iterate all our sites in unison until a dependency is violated -- at which point
        // we pause iterating the offending site until the dependency is resolved on the other end. We're sort
        // of brute-forcing the temporal order, but it's still O(N * S) == O(N * log(N)) in the end so it
        // doesn't really matter.
        generateAwareness: do
        {
            // next atom to check for each yarn/site
            var yarnsIndex = ContiguousArray<Int>(repeating: 0, count: sitesCount)
        
            while true
            {
                var atLeastOneSiteMovedForward = false
                var doneCount = 0
        
                for site in 0..<Int(yarnsIndex.count)
                {
                    let index = yarnsIndex[site]
        
                    if index >= yarnsMap[SiteId(site)]?.count ?? 0
                    {
                        doneCount += 1
                        continue
                    }
        
                    guard let a = atomYarnsIndex(AtomId(site: SiteId(site), index: YarnIndex(index))) else
                    {
                        assert(false, "likely corruption")
                    }
        
                    let atom = yarns[Int(a)]
        
                    // PERF: can precalculate all of these
                    let c = atomYarnsIndex(atom.cause) ?? -1
                    let p = atomYarnsIndex(AtomId(site: atom.site, index: atom.index - 1)) ?? -1
                    let r = atomYarnsIndex(atom.reference) ?? -1
        
                    // dependency checking
                    if c != -1 && !awarenessCalculated(a: Int(c))
                    {
                        continue
                    }
                    if p != -1 && !awarenessCalculated(a: Int(p))
                    {
                        continue
                    }
                    if r != -1 && !awarenessCalculated(a: Int(r))
                    {
                        continue
                    }
        
                    atomAwareness[Int(a) * sitesCount + site] = index
                    updateAwareness(forAtom: Int(a), fromAtom: Int(c))
                    updateAwareness(forAtom: Int(a), fromAtom: Int(p))
                    updateAwareness(forAtom: Int(a), fromAtom: Int(r))
        
                    yarnsIndex[site] += 1
                    atLeastOneSiteMovedForward = true
                }
        
                let done = (doneCount == sitesCount)
        
                assert(done || atLeastOneSiteMovedForward, "causality violation")
        
                if done
                {
                    break
                }
            }
        }
    }
}
