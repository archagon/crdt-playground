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
    public typealias WeaveT = Weave<SiteUUIDT,ValueT>
    
    // these are separate b/c they are serialized separately and grow separately -- and, really, are separate CRDTs
    public private(set) var siteIndex: SiteIndexT = SiteIndexT()
    public private(set) var weave: WeaveT
    
    public init(owner: SiteUUIDT, clock: Clock, mapping: inout ArrayType<SiteIndexT.SiteIndexKey>, weave: inout ArrayType<WeaveT.Atom>, timestamp: YarnIndex)
    {
        self.siteIndex = SiteIndexT(mapping: &mapping)
        let id = self.siteIndex.addSite(owner, withClock: clock) //if owner exists, will simply fetch the id
        self.weave = WeaveT(owner: id, weave: &weave, timestamp: timestamp)
    }
    
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
        returnTree.weave = self.weave.copy() as! Weave<SiteUUIDT,ValueT>
        
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
        // an incoming causal tree might have added sites, and our site ids are distributed in lexicographic-ish order,
        // so we may need to remap some site ids if the orders no longer line up
        func remapIndices(localTree: CausalTree, remoteSiteIndex: SiteIndexT)
        {
            let oldSiteIndex = localTree.siteIndex.copy() as! SiteIndexT
            var remoteSiteIndexPointer = remoteSiteIndex
            
            let firstDifferentIndex = localTree.siteIndex.integrateReturningFirstDiffIndex(&remoteSiteIndexPointer)
            var remapMap: [SiteId:SiteId] = [:]
            if let index = firstDifferentIndex
            {
                let newMapping = localTree.siteIndex.siteMapping()
                for i in index..<oldSiteIndex.siteCount()
                {
                    let oldSite = SiteId(i)
                    let newSite = newMapping[oldSiteIndex.site(oldSite)!]
                    remapMap[oldSite] = newSite
                }
            }
            localTree.weave.remapIndices(remapMap)
        }
        
        remapIndices(localTree: self, remoteSiteIndex: v.siteIndex)
        remapIndices(localTree: v, remoteSiteIndex: self.siteIndex) //to account for concurrently added sites
        
        weave.integrate(&v.weave)
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
        return siteIndex.superset(&v.siteIndex) && weave.superset(&v.weave)
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
    
    public var hashValue: Int
    {
        return siteIndex.hashValue ^ weave.hashValue
    }
}
