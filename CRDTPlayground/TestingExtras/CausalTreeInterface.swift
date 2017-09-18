//
//  CausalTreeInterface.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-9-18.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import AppKit

protocol CausalTreeInterfaceDelegate: class
{
    associatedtype SiteUUIDT: CausalTreeSiteUUIDT
    associatedtype ValueT: CausalTreeValueT
    
    func site(forInterface: Int) -> Peer<UUID,ValueT>?
    func peers(forInterface: Int) -> [Peer<SiteUUIDT,ValueT>]
    func appendPeer(_ peer: Peer<SiteUUIDT,ValueT>, forInterface: Int) -> Bool
}

protocol CausalTreeInterfaceProtocol: CausalTreeControlViewControllerDelegate, CausalTreeDisplayViewControllerDelegate
{
    associatedtype SiteUUIDT: CausalTreeSiteUUIDT
    associatedtype ValueT: CausalTreeValueT
    associatedtype DelegateT: CausalTreeInterfaceDelegate
    
    var storyboard: NSStoryboard { get }
    
    // TODO: remove this brittle dependency
    var id: Int { get }
    var site: Peer<SiteUUIDT,ValueT> { get }
    var peers: [Peer<SiteUUIDT,ValueT>] { get }
    func appendPeer(_ peer: Peer<SiteUUIDT,ValueT>)
    
    var delegate: DelegateT { get }
    
    func contentView(withCRDT crdt: CausalTree<SiteUUIDT,ValueT>) -> NSView
}

extension CausalTreeInterfaceProtocol
{
    typealias CausalTreeT = CausalTree<SiteUUIDT,ValueT>
    typealias PeerT = Peer<SiteUUIDT,ValueT>
    
    func groupForController(_ vc: NSViewController) -> PeerT?
    {
        return site
    }
    
    func showWeave(forControlViewController vc: CausalTreeControlViewController)
    {
        guard let g = groupForController(vc) else { return }
        g.showWeave(storyboard: storyboard)
    }
    
    func siteUUID(forControlViewController vc: CausalTreeControlViewController) -> SiteUUIDT
    {
        guard let g = groupForController(vc) else { return SiteUUIDT() }
        return g.crdt.siteIndex.site(g.crdt.weave.owner)!
    }
    
    func siteId(forControlViewController vc: CausalTreeControlViewController) -> SiteId
    {
        guard let g = groupForController(vc) else { return NullSite }
        return g.crdt.weave.owner
    }
    
    func selectedAtom(forControlViewController vc: CausalTreeControlViewController) -> AtomId?
    {
        guard let g = groupForController(vc) else { return NullAtomId }
        return g.selectedAtom
    }
    
    func atomWeft(_ atom: AtomId, forControlViewController vc: CausalTreeControlViewController) -> Weft
    {
        guard let g = groupForController(vc) else { return Weft() }
        return g.crdt.weave.completeWeft()
    }
    
    func generateWeave(forControlViewController vc: CausalTreeControlViewController) -> String
    {
        guard let g = groupForController(vc) else { return "" }
        return g.crdt.weave.atomsDescription
    }
    
    func addSite(forControlViewController vc: CausalTreeControlViewController)
    {
        guard let g = groupForController(vc) else { return }
        addSite(fromPeer: g)
    }
    
    func isOnline(forControlViewController vc: CausalTreeControlViewController) -> Bool
    {
        guard let g = groupForController(vc) else { return false }
        return g.isOnline
    }
    
    func isConnected(toSite site: SiteId, forControlViewController vc: CausalTreeControlViewController) -> Bool
    {
        guard let g = groupForController(vc) else { return false }
        
        if site == g.crdt.weave.owner
        {
            return true
        }
        
        let targetUuid = g.crdt.siteIndex.site(site)!
        for (i,aG) in peers.enumerated()
        {
            let uuid = aG.crdt.siteIndex.site(aG.crdt.weave.owner)!
            if uuid == targetUuid
            {
                return g.peerConnections.contains(i)
            }
        }
        
        return false
    }
    
    func goOnline(_ online: Bool, forControlViewController vc: CausalTreeControlViewController)
    {
        guard let g = groupForController(vc) else { return }
        g.isOnline = online
    }
    
    func connect(_ connect: Bool, toSite site: SiteId, forControlViewController vc: CausalTreeControlViewController)
    {
        guard let g = groupForController(vc) else { return }
        
        if site == g.crdt.weave.owner
        {
            return
        }
        
        let targetUuid = g.crdt.siteIndex.site(site)!
        for (i,aG) in peers.enumerated()
        {
            let uuid = aG.crdt.siteIndex.site(aG.crdt.weave.owner)!
            if uuid == targetUuid
            {
                if connect
                {
                    g.peerConnections.insert(i)
                }
                else
                {
                    g.peerConnections.remove(i)
                }
                return
            }
        }
    }
    
    func allSites(forControlViewController vc: CausalTreeControlViewController) -> [SiteId]
    {
        guard let g = groupForController(vc) else { return [] }
        var allSites = Array(g.crdt.siteIndex.siteMapping().values)
        allSites.sort()
        allSites.remove(at: allSites.index(of: ControlSite)!)
        return allSites
    }
    
    func showAwareness(forAtom atom: AtomId?, inControlViewController vc: CausalTreeControlViewController)
    {
        guard let g = groupForController(vc) else { return }
        g.treeVC?.drawAwareness(forAtom: atom)
    }
    
    func generateCausalBlock(forAtom atom: AtomId, inControlViewController vc: CausalTreeControlViewController) -> CountableClosedRange<WeaveIndex>?
    {
        guard let g = groupForController(vc) else { return nil }
        guard let index = g.crdt.weave.atomWeaveIndex(atom) else { return nil }
        if let block = g.crdt.weave.causalBlock(forAtomIndexInWeave: index)
        {
            return block
        }
        else
        {
            return nil
        }
    }
    
    func deleteAtom(_ atom: AtomId, forControlViewController vc: CausalTreeControlViewController)
    {
        guard let g = groupForController(vc) else { return }
        
        TestingRecorder.shared?.recordAction(g.crdt.ownerUUID(), atom, withId: TestCommand.deleteAtom.rawValue)
        
        let _ = g.crdt.weave.deleteAtom(atom, atTime: Clock(CACurrentMediaTime() * 1000))
        g.selectedAtom = nil
        g.reloadData()
    }
    
    func atomIdForWeaveIndex(_ weaveIndex: WeaveIndex, forControlViewController vc: CausalTreeControlViewController) -> AtomId?
    {
        guard let g = groupForController(vc) else { return nil }
        return g.crdt.weave.weave()[Int(weaveIndex)].id
    }
    
    func dataView(forControlViewController vc: CausalTreeControlViewController) -> NSView
    {
        guard let g = groupForController(vc) else { return NSView() }
        return g.dataView
    }
    
    func crdtSize(forControlViewController vc: CausalTreeControlViewController) -> Int
    {
        guard let g = groupForController(vc) else { return -1 }
        return g.crdt.sizeInBytes()
    }
    
    func atomCount(forControlViewController vc: CausalTreeControlViewController) -> Int
    {
        guard let g = groupForController(vc) else { return -1 }
        return g.crdt.weave.atomCount()
    }
    
    func addSite(fromPeer: PeerT? = nil) {
        let ownerUUID = SiteUUIDT()
        let tree: CausalTreeT
        
        if let group = fromPeer
        {
            TestingRecorder.shared?.recordAction(ownerUUID, group.crdt.ownerUUID(), group.crdt.weave.completeWeft(), withId: TestCommand.forkSite.rawValue)
            
            tree = group.crdt.copy() as! CausalTreeT
            let site = tree.siteIndex.addSite(ownerUUID, withClock: Int64(CACurrentMediaTime() * 1000))
            tree.weave.owner = site
        }
        else
        {
            TestingRecorder.shared?.recordAction(ownerUUID, withId: TestCommand.createSite.rawValue)
            
            tree =
                //WeaveHardConcurrency()
                //WeaveHardConcurrencyAutocommit()
                //WeaveTypingSimulation(100)
                CausalTreeT(site: ownerUUID, clock: Int64(CACurrentMediaTime() * 1000))
        }
        
        let g1 = Peer(storyboard: self.storyboard, crdt: tree)
        self.appendPeer(g1)
        g1.delegate = self
        g1.controlVC.reloadData()
    }
    
    func crdtCopy(forCausalTreeDisplayViewController vc: CausalTreeDisplayViewController) -> CausalTreeT
    {
        guard let g = groupForController(vc) else { return CausalTreeT(site: SiteUUIDT(), clock: NullClock) }
        return g.crdt.copy() as! CausalTreeT
    }
    
    func didSelectAtom(_ atom: AtomId?, withButton button: Int, inCausalTreeDisplayViewController vc: CausalTreeDisplayViewController)
    {
        guard let g = groupForController(vc) else { return }
        
        // so as to not interfere with basic dragging implementation
        if button >= 1
        {
            g.selectedAtom = nil //to reset awareness
            g.selectedAtom = atom
        }
        if button == 2, let a = atom
        {
            appendAtom(toAtom: a, forControlViewController: g.controlVC)
        }
    }
    
    func sites(forCausalTreeDisplayViewController vc: CausalTreeDisplayViewController) -> [SiteId]
    {
        guard let g = groupForController(vc) else { return [] }
        guard let c = g.crdtCopy else { assert(false); return [] }
        return c.siteIndex.allSites()
    }
    
    func length(forSite site: SiteId, forCausalTreeDisplayViewController vc: CausalTreeDisplayViewController) -> Int
    {
        guard let g = groupForController(vc) else { return 0 }
        guard let c = g.crdtCopy else { assert(false); return 0 }
        return c.weave.yarn(forSite: site).count
    }
    
    func metadata(forAtom atom: AtomId, forCausalTreeDisplayViewController vc: CausalTreeDisplayViewController) -> AtomMetadata?
    {
        guard let g = groupForController(vc) else { return nil }
        guard let c = g.crdtCopy else { assert(false); return nil }
        return c.weave.atomForId(atom)?.metadata
    }
    
    func awareness(forAtom atom: AtomId, forCausalTreeDisplayViewController vc: CausalTreeDisplayViewController) -> Weft?
    {
        guard let g = groupForController(vc) else { return nil }
        guard let c = g.crdtCopy else { assert(false); return nil }
        return c.weave.awarenessWeft(forAtom: atom)
    }
    
    func description(forAtom atom: AtomId, forCausalTreeDisplayViewController vc: CausalTreeDisplayViewController) -> String?
    {
        guard let g = groupForController(vc) else { return nil }
        guard let c = g.crdtCopy else { assert(false); return nil }
        return c.weave.atomForId(atom)?.value.atomDescription
    }
    
    func beginDraw(forCausalTreeDisplayViewController vc: CausalTreeDisplayViewController)
    {
        guard let g = groupForController(vc) else { return }
        assert(g.crdtCopy == nil)
        g.crdtCopy = (g.crdt.copy() as! CausalTreeT)
    }
    
    func endDraw(forCausalTreeDisplayViewController vc: CausalTreeDisplayViewController)
    {
        guard let g = groupForController(vc) else { return }
        assert(g.crdtCopy != nil)
        g.crdtCopy = nil
    }
}
