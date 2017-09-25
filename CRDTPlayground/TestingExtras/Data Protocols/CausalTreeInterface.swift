//
//  CausalTreeInterface.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-9-18.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import AppKit

/* Kind of a catch-all delegate that sends queries to the driver for processing, but also specializes with some
 types through the use of protocol extensions. Not sure if this is a good idea, but it keeps most of the
 VC delegate junk away from the driver. */

protocol CausalTreeInterfaceDelegate: class
{
    // peer queries
    func isOnline(_ s: Int) -> Bool
    func isConnected(_ s: Int, toPeer s1: Int) -> Bool
    func goOnline(_ o: Bool, _ s: Int)
    func connect(_ o: Bool, _ s: Int, toPeer s1: Int)
    func fork(_ s: Int) -> Int
    
    // peer mapping
    func siteId(_ s: Int) -> SiteId
    func id(ofSite: SiteId, _ s: Int) -> Int
    func siteId(ofPeer s1: Int, inPeer s: Int) -> SiteId?
    
    // ui messages
    func showWeaveWindow(_ s: Int)
    func showAwarenessInWeaveWindow(forAtom atom: AtomId?, _ s: Int)
    func selectedAtom(_ s: Int) -> AtomId?
    func didSelectAtom(_ atom: AtomId?, _ s: Int)
    func reloadData(_ s: Int)
}

protocol CausalTreeInterfaceProtocol: CausalTreeControlViewControllerDelegate, CausalTreeDisplayViewControllerDelegate
{
    associatedtype SiteUUIDT: CausalTreeSiteUUIDT
    associatedtype ValueT: CausalTreeValueT

    var id: Int { get }
    var uuid: SiteUUIDT { get }
    var storyboard: NSStoryboard { get }
    var contentView: NSView { get }
    
    // AB: I'd *much* prefer to access the CRDT through a delegate call, but I can't figure out associated type delegates
    unowned var delegate: CausalTreeInterfaceDelegate { get }
    unowned var crdt: CausalTree<SiteUUIDT, ValueT> { get }
    var crdtCopy: CausalTree<SiteUUIDT, ValueT>? { get set }

    init(id: Int, uuid: SiteUUIDT, storyboard: NSStoryboard, crdt: CausalTree<SiteUUIDT, ValueT>, delegate: CausalTreeInterfaceDelegate)
    
    func createContentView() -> NSView
    func reloadData()
}

extension CausalTreeInterfaceProtocol
{
    typealias CTIDSiteUUIDT = SiteUUIDT
    typealias CTIDSiteValueT = ValueT
    
    func showWeave(forControlViewController vc: CausalTreeControlViewController)
    {
        self.delegate.showWeaveWindow(self.id)
    }

    func siteUUID(forControlViewController vc: CausalTreeControlViewController) -> SiteUUIDT
    {
        return crdt.ownerUUID()
    }

    func siteId(forControlViewController vc: CausalTreeControlViewController) -> SiteId
    {
        return delegate.siteId(id)
    }

    func selectedAtom(forControlViewController vc: CausalTreeControlViewController) -> AtomId?
    {
        return self.delegate.selectedAtom(self.id)
    }

    func atomWeft(_ atom: AtomId, forControlViewController vc: CausalTreeControlViewController) -> Weft
    {
        return crdt.weave.completeWeft()
    }
    
    func generateWeave(forControlViewController vc: CausalTreeControlViewController) -> String
    {
        return crdt.weave.atomsDescription
    }
    
    func addSite(forControlViewController vc: CausalTreeControlViewController)
    {
        let _ = delegate.fork(id)
    }
    
    func isOnline(forControlViewController vc: CausalTreeControlViewController) -> Bool
    {
        return self.delegate.isOnline(self.id)
    }
    
    func isConnected(toSite site: SiteId, forControlViewController vc: CausalTreeControlViewController) -> Bool
    {
        let i = delegate.id(ofSite: site, self.id)
        return delegate.isConnected(self.id, toPeer: i)
    }

    func goOnline(_ online: Bool, forControlViewController vc: CausalTreeControlViewController)
    {
        self.delegate.goOnline(online, self.id)
    }
    
    func connect(_ connect: Bool, toSite site: SiteId, forControlViewController vc: CausalTreeControlViewController)
    {
        let i = delegate.id(ofSite: site, self.id)
        delegate.connect(connect, self.id, toPeer: i)
    }
    
    func allSites(forControlViewController vc: CausalTreeControlViewController) -> [SiteId]
    {
        var allSites = Array(crdt.siteIndex.siteMapping().values)
        allSites.sort()
        allSites.remove(at: allSites.index(of: ControlSite)!)
        return allSites
    }

    func showAwareness(forAtom atom: AtomId?, inControlViewController vc: CausalTreeControlViewController)
    {
        self.delegate.showAwarenessInWeaveWindow(forAtom: atom, self.id)
    }

    func generateCausalBlock(forAtom atom: AtomId, inControlViewController vc: CausalTreeControlViewController) -> CountableClosedRange<WeaveIndex>?
    {
        guard let index = crdt.weave.atomWeaveIndex(atom) else { return nil }
        if let block = crdt.weave.causalBlock(forAtomIndexInWeave: index)
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
        TestingRecorder.shared?.recordAction(uuid, atom, withId: TestCommand.deleteAtom.rawValue)
    
        let _ = crdt.weave.deleteAtom(atom, atTime: Clock(CACurrentMediaTime() * 1000))
        delegate.didSelectAtom(nil, id)
        delegate.reloadData(id)
        reloadData()
    }

    func atomIdForWeaveIndex(_ weaveIndex: WeaveIndex, forControlViewController vc: CausalTreeControlViewController) -> AtomId?
    {
        return crdt.weave.weave()[Int(weaveIndex)].id
    }

    func dataView(forControlViewController vc: CausalTreeControlViewController) -> NSView
    {
        return contentView
    }
    
    func crdtSize(forControlViewController vc: CausalTreeControlViewController) -> Int
    {
        return crdt.sizeInBytes()
    }

    func atomCount(forControlViewController vc: CausalTreeControlViewController) -> Int
    {
        return crdt.weave.atomCount()
    }
    
    func crdtCopy(forCausalTreeDisplayViewController vc: CausalTreeDisplayViewController) -> CausalTree<SiteUUIDT, ValueT>
    {
        return crdt.copy() as! CausalTree<SiteUUIDT, ValueT>
    }
    
    func didSelectAtom(_ atom: AtomId?, withButton button: Int, inCausalTreeDisplayViewController vc: CausalTreeDisplayViewController)
    {
        // so as to not interfere with basic dragging implementation
        if button >= 1
        {
            delegate.didSelectAtom(nil, id) //to reset awareness
            delegate.didSelectAtom(atom, id)
        }
        if button == 2, let a = atom
        {
            // HACK: vc is unused but I don't want to have to design a scheme to retrieve it from the driver
            appendAtom(toAtom: a, forControlViewController: (vc as! CausalTreeControlViewController))
        }
    }
    
    func sites(forCausalTreeDisplayViewController vc: CausalTreeDisplayViewController) -> [SiteId]
    {
        guard let c = crdtCopy else { assert(false); return []; }
        return c.siteIndex.allSites()
    }
    
    func length(forSite site: SiteId, forCausalTreeDisplayViewController vc: CausalTreeDisplayViewController) -> Int
    {
        guard let c = crdtCopy else { assert(false); return 0; }
        return c.weave.yarn(forSite: site).count
    }
    
    func metadata(forAtom atom: AtomId, forCausalTreeDisplayViewController vc: CausalTreeDisplayViewController) -> AtomMetadata?
    {
        guard let c = crdtCopy else { assert(false); return nil; }
        return c.weave.atomForId(atom)?.metadata
    }
    
    func awareness(forAtom atom: AtomId, forCausalTreeDisplayViewController vc: CausalTreeDisplayViewController) -> Weft?
    {
        guard let c = crdtCopy else { assert(false); return nil; }
        return c.weave.awarenessWeft(forAtom: atom)
    }
    
    func description(forAtom atom: AtomId, forCausalTreeDisplayViewController vc: CausalTreeDisplayViewController) -> String?
    {
        guard let c = crdtCopy else { assert(false); return nil; }
        return c.weave.atomForId(atom)?.value.atomDescription
    }
    
    func beginDraw(forCausalTreeDisplayViewController vc: CausalTreeDisplayViewController)
    {
        assert(crdtCopy == nil)
        crdtCopy = (crdt.copy() as! CausalTree<SiteUUIDT, ValueT>)
    }
    
    func endDraw(forCausalTreeDisplayViewController vc: CausalTreeDisplayViewController)
    {
        assert(crdtCopy != nil)
        crdtCopy = nil
    }
}
