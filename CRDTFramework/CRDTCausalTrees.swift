//
//  CRDTCausalTreesWeave.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-9-18.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import Foundation

// TODO: weft needs to be stored in contiguous memory
// TODO: totalWeft should be derived from yarnMap
// TODO: ownerWeft
// TODO: make everything a struct?
// TODO: mark all sections where weave is mutated and ensure code-wise that caches always get updated
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
 */

////////////////////////
// MARK: -
// MARK: - Causal Tree -
// MARK: -
////////////////////////

public final class CausalTree
    <S: CausalTreeSiteUUIDT, V: CausalTreeValueT> :
    CvRDT, NSCopying, CustomDebugStringConvertible, ApproxSizeable
{
    public typealias SiteUUIDT = S
    public typealias ValueT = V
    public typealias SiteIndexT = SiteIndex<SiteUUIDT>
    public typealias WeaveT = Weave<ValueT>
    
    // these are separate b/c they are serialized separately and grow separately -- and, really, are separate CRDTs
    public private(set) var siteIndex: SiteIndexT = SiteIndexT()
    public private(set) var weave: WeaveT
    
    // starting from scratch
    public init(site: SiteUUIDT, clock: Clock)
    {
        self.siteIndex = SiteIndexT()
        let id = self.siteIndex.addSite(site, withClock: clock)
        self.weave = WeaveT(owner: id)
    }
    
    public func copy(with zone: NSZone? = nil) -> Any
    {
        let returnTree = CausalTree<SiteUUIDT,ValueT>(site: SiteUUIDT.zero, clock: 0)
        
        returnTree.siteIndex = self.siteIndex.copy() as! SiteIndex<SiteUUIDT>
        returnTree.weave = self.weave.copy() as! Weave<ValueT>
        
        return returnTree
    }
    
    public func ownerUUID() -> SiteUUIDT
    {
        let uuid = siteIndex.site(weave.owner)
        assert(uuid != nil, "could not find uuid for owner")
        return uuid!
    }
    
    // WARNING: the inout tree will be mutated, so make absolutely sure it's a copy you're willing to waste!
    public func integrate(_ v: inout CausalTree)
    {
        let _ = integrateReturningSiteIdRemaps(&v)
    }
    
    // WARNING: the inout tree will be mutated, so make absolutely sure it's a copy you're willing to waste!
    public func integrateReturningSiteIdRemaps(_ v: inout CausalTree) -> (localRemap:[SiteId:SiteId], remoteRemap:[SiteId:SiteId])
    {
        let remapLocal = CausalTree.remapIndices(localSiteIndex: self.siteIndex, remoteSiteIndex: v.siteIndex)
        let remapRemote = CausalTree.remapIndices(localSiteIndex: v.siteIndex, remoteSiteIndex: self.siteIndex) //to account for concurrently added sites
        
        self.weave.remapIndices(remapLocal)
        v.weave.remapIndices(remapRemote)
        
        siteIndex.integrate(&v.siteIndex)
        weave.integrate(&v.weave) //possible since both now share the same siteId mapping
        
        return (remapLocal, remapRemote)
    }
    
    // returns same remap as above
    public func transferToNewOwner(withUUID uuid: SiteUUIDT, clock: Clock) -> ([SiteId:SiteId])
    {
        if ownerUUID() == uuid
        {
            return ([:])
        }
        
        let remapLocal: ([SiteId:SiteId])
        
        if siteIndex.siteMapping()[uuid] == nil
        {
            var newOwnerSiteMap = SiteIndexT()
            let _ = newOwnerSiteMap.addSite(uuid, withClock: clock)
            
            // AB: technically, this should never get triggered since clock will be most recent -- but why rely on this fact?
            remapLocal = CausalTree.remapIndices(localSiteIndex: siteIndex, remoteSiteIndex: newOwnerSiteMap)
            siteIndex.integrate(&newOwnerSiteMap)
            weave.remapIndices(remapLocal)
        }
        else
        {
            remapLocal = ([:])
        }
        
        let siteId = siteIndex.siteMapping()[uuid]!
        weave.owner = siteId
        
        return remapLocal
    }
    
    public func validate() throws -> Bool
    {
        let indexValid = siteIndex.validate()
        let weaveValid = try weave.validate()
        // TODO: check that site mapping corresponds to weave sites
        
        return indexValid && weaveValid
    }
    
    public func superset(_ v: inout CausalTree) -> Bool
    {
        // we need to convert to absolute units so that we don't have to remap indices yet
        let lAbs = convert(localWeft: completeWeft())
        let rAbs = v.convert(localWeft: v.completeWeft())
        
        assert(lAbs != nil && rAbs != nil, "could not convert local weft to absolute weft")

        // incorporates both the site index and weave weft, so we don't have to superset each one directly
        return lAbs!.isSuperset(of: rAbs!)
    }
    
    public var debugDescription: String
    {
        get
        {
            return "Sites: \(siteIndex.debugDescription), Weave: \(weave.debugDescription)"
        }
    }
    
    public func sizeInBytes() -> Int
    {
        return siteIndex.sizeInBytes() + weave.sizeInBytes()
    }
    
    public static func ==(lhs: CausalTree, rhs: CausalTree) -> Bool
    {
        return lhs.siteIndex == rhs.siteIndex && lhs.weave == rhs.weave
    }

    public func hash(into hasher: inout Hasher)
    {
        hasher.combine(siteIndex)
        hasher.combine(weave)
    }

    // an incoming causal tree might have added sites, and our site ids are distributed in lexicographic-ish order,
    // so we may need to remap some site ids if the orders no longer line up; neither site index is mutated
    static func remapIndices(localSiteIndex: SiteIndexT, remoteSiteIndex: SiteIndexT) -> [SiteId:SiteId]
    {
        let oldSiteIndex = localSiteIndex
        let newSiteIndex = localSiteIndex.copy() as! SiteIndexT
        var remoteSiteIndexPointer = remoteSiteIndex
        
        let firstDifferentIndex = newSiteIndex.integrateReturningFirstDiffIndex(&remoteSiteIndexPointer)
        var remapMap: [SiteId:SiteId] = [:]
        if let index = firstDifferentIndex
        {
            let newMapping = newSiteIndex.siteMapping()
            for i in index..<oldSiteIndex.siteCount()
            {
                let oldSite = SiteId(i)
                let newSite = newMapping[oldSiteIndex.site(oldSite)!]
                remapMap[oldSite] = newSite
            }
        }
        
        assert(remapMap.values.count == Set(remapMap.values).count, "some sites mapped to identical sites")
        
        return remapMap
    }
}

///////////////////////////////////////
// MARK: - Local/Absolute Conversions -
///////////////////////////////////////

// TODO: consistent naming
extension CausalTree
{
    public typealias WeftT = Weft<SiteUUIDT>
    public typealias AbsoluteAtomIdT = AbsoluteAtomId<SiteUUIDT>
    
    // returns a weft that includes sites that the CT is aware of, but have no atoms yet
    public func completeWeft() -> LocalWeft
    {
        var weft = weave.currentWeft()
        
        // ensures that weft is complete and includes sites with no atoms -- needed to compare wefts across CT revisions
        for (_,site) in siteIndex.siteMapping()
        {
            weft.update(site: site, index: NullIndex)
        }
        
        return weft
    }
    
    public func convert(localWeft: LocalWeft) -> WeftT?
    {
        if localWeft.mapping.count != completeWeft().mapping.count
        {
            warning(false, "possibly outdated weft")
        }
        
        var returnWeft = WeftT()
        
        for (site,val) in localWeft.mapping
        {
            guard let uuid = siteIndex.site(site) else
            {
                warning(false, "could not find site")
                return nil
            }
            returnWeft.update(site: uuid, index: val)
        }
        
        return returnWeft
    }
    
    public func convert(weft: WeftT) -> LocalWeft?
    {
        var returnWeft = LocalWeft()
        
        for (uuid,val) in weft.mapping
        {
            guard let site = siteIndex.siteMapping()[uuid] else
            {
                warning(false, "could not find site")
                return nil
            }
            returnWeft.update(site: site, index: val)
        }
        
        return returnWeft
    }
    
    public func convert(localAtom: AtomId) -> AbsoluteAtomIdT?
    {
        guard let _ = weave.atomForId(localAtom) else
        {
            // atom not found in weave
            return nil
        }
        
        guard let uuid = siteIndex.site(localAtom.site) else
        {
            assert(false, "atom id present in weave, but uuid not found")
            return nil
        }
        
        return AbsoluteAtomIdT(site: uuid, index: localAtom.index)
    }
    
    public func convert(absoluteAtom: AbsoluteAtomIdT) -> AtomId?
    {
        guard let site = siteIndex.siteMapping()[absoluteAtom.site] else
        {
            // site not found for uuid
            return nil
        }
        
        let atom = AtomId(site: site, index: absoluteAtom.index)
        
        guard let _ = weave.atomForId(atom) else
        {
            // atom not found in weave
            return nil
        }
        
        return atom
    }
}
