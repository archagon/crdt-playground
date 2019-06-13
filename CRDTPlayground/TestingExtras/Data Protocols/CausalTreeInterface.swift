//
//  CausalTreeInterface.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-9-18.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import AppKit
//import CRDTFramework_OSX

/* Kind of a catch-all delegate that sends queries to the driver for processing, but also specializes with some
 types through the use of protocol extensions. Not sure if this is a good idea, but it keeps most of the
 VC delegate junk away from the driver. */

// TODO: we use CausalTreeStandardUUIDT for revision information exchange to avoid associated types, but I'd like
// to eventually change that, if possible

@objc protocol CausalTreeListener
{
    // outside changes have come in: revalidate your layers, update caches and indentifiers, redraw, etc.
    @objc optional func causalTreeWillUpdate(sender: NSObject?)
    @objc optional func causalTreeDidUpdate(sender: NSObject?)
}

protocol CausalTreeContentView: CausalTreeListener
{
    var listener: CausalTreeListener? { get set }
    
    func updateRevision(_ revision: Weft<CausalTreeStandardUUIDT>?)
}

// adopted by driver; standard interface for faux network management and queries
protocol CausalTreeInterfaceDelegate: class
{
    // peer queries
    func isOnline(_ s: Int) -> Bool
    func isConnected(_ s: Int, toPeer s1: Int) -> Bool
    func goOnline(_ o: Bool, _ s: Int)
    func allOnline(_ o: Bool, _ s: Int)
    func connect(_ o: Bool, _ s: Int, toPeer s1: Int)
    func fork(_ s: Int) -> Int
    func revisions(_ s: Int) -> [Weft<CausalTreeStandardUUIDT>]
    func selectedRevision(_ s: Int) -> Int?
    func setRevision(_ r: Int?, _ s: Int)
    
    // peer mapping
    // TODO: ought to use CausalTreeStandardUUIDT for this, since SiteIDs are only valid if the site index doesn't change
    func siteId(_ s: Int) -> SiteId
    func id(ofSite: SiteId, _ s: Int) -> Int
    
    // ui messages
    func showWeaveWindow(_ s: Int)
    func showAwarenessInWeaveWindow(forAtom atom: AbsoluteAtomId<CausalTreeStandardUUIDT>?, _ s: Int)
    func selectedAtom(_ s: Int) -> AbsoluteAtomId<CausalTreeStandardUUIDT>?
    func didSelectAtom(_ atom: AbsoluteAtomId<CausalTreeStandardUUIDT>?, _ s: Int)
    func reloadData(_ s: Int)
}

// adopted by controllers
protocol CausalTreeInterfaceProtocol: CausalTreeControlViewControllerDelegate, CausalTreeDisplayViewControllerDelegate, CausalTreeListener
{
    associatedtype SiteUUIDT: CausalTreeSiteUUIDT
    associatedtype ValueT: CausalTreeValueT

    var id: Int { get }
    var uuid: SiteUUIDT { get }
    var storyboard: NSStoryboard { get }
    var contentView: NSView & CausalTreeContentView { get }
    
    // AB: I'd *much* prefer to access the CRDT through a delegate call, but I can't figure out associated type delegates
    var delegate: CausalTreeInterfaceDelegate { get }
    var crdt: CausalTree<SiteUUIDT, ValueT> { get }
    var crdtCopy: CausalTree<SiteUUIDT, ValueT>? { get set }

    init(id: Int, uuid: SiteUUIDT, storyboard: NSStoryboard, crdt: CausalTree<SiteUUIDT, ValueT>, delegate: CausalTreeInterfaceDelegate)
    
    func createContentView() -> NSView & CausalTreeContentView
    func preferredWindowSize() -> NSSize
    
    func willUpdateCausalTree()
    func didUpdateCausalTree()
    func didUpdateRevision()
}

extension CausalTreeInterfaceProtocol
{
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

    func selectedAtom(forControlViewController vc: CausalTreeControlViewController) -> AbsoluteAtomId<CausalTreeStandardUUIDT>?
    {
        return self.delegate.selectedAtom(self.id)
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
    
    func allOnline(_ online: Bool, forControlViewController: CausalTreeControlViewController)
    {
        self.delegate.allOnline(online, self.id)
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
        allSites.remove(at: allSites.firstIndex(of: ControlSite)!)
        return allSites
    }

    func showAwareness(forAtom atom: AbsoluteAtomId<CausalTreeStandardUUIDT>?, inControlViewController vc: CausalTreeControlViewController)
    {
        self.delegate.showAwarenessInWeaveWindow(forAtom: atom, self.id)
    }

    func dataView(forControlViewController vc: CausalTreeControlViewController) -> NSView
    {
        return contentView
    }
    
    func crdtSize(forControlViewController vc: CausalTreeControlViewController) -> Int
    {
        return crdt.sizeInBytes()
    }
    
    func selectedRevision(forControlViewController: CausalTreeControlViewController) -> Int?
    {
        return delegate.selectedRevision(self.id)
    }
    
    func setRevision(_ r: Int?, forControlViewController: CausalTreeControlViewController)
    {
        delegate.setRevision(r, self.id)
    }
    
    func getData(forControlViewController: CausalTreeControlViewController) -> Data
    {
        var data: [UInt8]!
        
        timeMe({
            data = try! BinaryEncoder.encode(self.crdt)
            print("Actual Size: \(String(format: "%.1f", CGFloat(data.count) / 1024)) kb")
        }, "Encode")
        
        let dataObj = Data(bytes: data)
        return dataObj
    }
    
    func crdtCopy(forCausalTreeDisplayViewController vc: CausalTreeDisplayViewController) -> CausalTree<SiteUUIDT, ValueT>
    {
        return crdt.copy() as! CausalTree<SiteUUIDT, ValueT>
    }
    
    func sites(forCausalTreeDisplayViewController vc: CausalTreeDisplayViewController) -> [SiteId]
    {
        guard let c = crdtCopy else { assert(false); return []; }
        return c.siteIndex.allSites()
    }
    
    func metadata(forAtom atom: AtomId, forCausalTreeDisplayViewController vc: CausalTreeDisplayViewController) -> AtomMetadata?
    {
        guard let c = crdtCopy else { assert(false); return nil; }
        return c.weave.atomForId(atom)?.metadata
    }
    
    func awareness(forAtom atom: AtomId, forCausalTreeDisplayViewController vc: CausalTreeDisplayViewController) -> LocalWeft?
    {
        // AB: if we ever make this funcitonal again, we need to probably use an absolute weft
        guard let _ = crdtCopy else { assert(false); return nil; } // c
        //return c.weave.awarenessWeft(forAtom: atom)
        return nil
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
    
    func willUpdateCausalTree()
    {
        contentView.causalTreeWillUpdate?(sender: (self as? NSObject ?? nil))
    }
    
    func didUpdateCausalTree()
    {
        // TODO: reset atom selection at some point in this chain
        contentView.causalTreeDidUpdate?(sender: (self as? NSObject ?? nil))
    }
}
extension CausalTreeInterfaceProtocol where SiteUUIDT == CausalTreeStandardUUIDT
{
    func revision() -> Weft<CausalTreeStandardUUIDT>?
    {
        let revisions = delegate.revisions(self.id)
        
        if let rev = delegate.selectedRevision(self.id)
        {
            return revisions[rev]
        }
        else
        {
            return nil
        }
    }
    
    func atomDescription(_ a: AbsoluteAtomId<CausalTreeStandardUUIDT>, forControlViewController: CausalTreeControlViewController) -> String
    {
        if let atomId = crdt.convert(absoluteAtom: a),
            let atom = crdt.weave.atomForId(atomId)
        {
            return atom.debugDescription
        }
        else
        {
            return "(unknown)"
        }
    }
    
    func generateCausalBlock(forAtom atom: AbsoluteAtomId<CausalTreeStandardUUIDT>, inControlViewController vc: CausalTreeControlViewController) -> CountableClosedRange<WeaveIndex>?
    {
        guard
            let localAtom = crdt.convert(absoluteAtom: atom),
            let index = crdt.weave.atomWeaveIndex(localAtom)
            else
        {
            return nil
        }
        
        if let block = crdt.weave.causalBlock(forAtomIndexInWeave: index)
        {
            return block
        }
        else
        {
            return nil
        }
    }
    
    func localRevisions(forControlViewController: CausalTreeControlViewController) -> [LocalWeft]
    {
        // PERF: slow
        return delegate.revisions(self.id).map
        {
            let rev = crdt.convert(weft: $0)
            assert(rev != nil, "could not convert revision to local weft")
            return rev!
        }
    }
    
    func atomIdForWeaveIndex(_ weaveIndex: WeaveIndex, forControlViewController vc: CausalTreeControlViewController) -> AtomId?
    {
        var localRev: LocalWeft? = nil
        if let rev = revision()
        {
            localRev = crdt.convert(weft: rev)
            assert(localRev != nil, "could not convert revision to local weft")
        }
        
        // PERF: TODO: very slow, cache this
        return crdt.weave.weave(withWeft: localRev)[Int(weaveIndex)].id
    }
    
    func atomCount(forControlViewController vc: CausalTreeControlViewController) -> Int
    {
        var localRev: LocalWeft? = nil
        if let rev = revision()
        {
            localRev = crdt.convert(weft: rev)
            assert(localRev != nil, "could not convert revision to local weft")
        }
        
        // PERF: TODO: very slow, cache this
        return crdt.weave.weave(withWeft: localRev).count
    }
    
    func length(forSite site: SiteId, forCausalTreeDisplayViewController vc: CausalTreeDisplayViewController) -> Int
    {
        guard let c = crdtCopy else { assert(false); return 0; }
        
        var localRev: LocalWeft? = nil
        if let rev = revision()
        {
            localRev = c.convert(weft: rev)
            assert(localRev != nil, "could not convert revision to local weft")
        }
        
        // PERF: TODO: very slow, cache this
        return c.weave.yarn(forSite: site, withWeft: localRev).count
    }
    
    func didSelectAtom(_ atom: AtomId?, withButton button: Int, inCausalTreeDisplayViewController vc: CausalTreeDisplayViewController)
    {
        // so as to not interfere with basic dragging implementation
        if button >= 1
        {
            if
                let atom = atom,
                let absAtom = crdt.convert(localAtom: atom)
            {
                delegate.didSelectAtom(nil, id) //to reset awareness
                delegate.didSelectAtom(absAtom, id)
            }
        }
    }
    
    func didUpdateRevision()
    {
        contentView.updateRevision(revision())
    }
}
