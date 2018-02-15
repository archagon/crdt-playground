//
//  FakePeerSwarm.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-9-11.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

/* Fake P2P client swarm, along with a central "driver" that pumps the handle. When connected, clients
 send each other their CRDTs and merge them if necessary. Right now, clients also contain their own view
 controllers, which isn't that great... should fix. */

// TODO: reloadData is split up between peer, interface, and driver; consolidate

import AppKit
//import CRDTFramework_OSX

typealias GroupId = Int

// simulates device
// TODO: this should be close to a dumb struct
class Peer <S: CausalTreeSiteUUIDT, V: CausalTreeValueT>
{
    typealias CausalTreeT = CausalTree<S, V>
    
    var crdt: CausalTreeT
    var crdtCopy: CausalTreeT? //used while rendering
    
    private var _revisions: [CausalTreeT.WeftT] = []
    var revisions: [CausalTreeT.WeftT] { return _revisions + [crdt.convert(localWeft: crdt.completeWeft())] }
    var selectedRevision: Int? = nil
    
    var isOnline: Bool = false
    var peerConnections = Set<GroupId>()
    var selectedAtom: AtomId?
    {
        didSet
        {
            self.treeVC?.drawSelection(forAtom: selectedAtom)
            reloadData()
        }
    }
    
    // TODO: move these over to interface
    var controls: NSWindowController
    unowned var controlVC: CausalTreeControlViewController
    var treeView: NSWindowController?
    weak var treeVC: CausalTreeDisplayViewController?
    var dataView: NSView!
    
    weak var delegate: (CausalTreeDisplayViewControllerDelegate & CausalTreeControlViewControllerDelegate)?
    {
        didSet
        {
            self.controlVC.delegate = delegate
            self.treeVC?.delegate = delegate
        }
    }
    
    init(storyboard: NSStoryboard, crdt: CausalTreeT)
    {
        weaveSetup: do
        {
            print(crdt)
            self.crdt = crdt
        }
        
        self.delegate = nil
        let wc2 = storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(rawValue: "Control")) as! NSWindowController
        let cvc = wc2.contentViewController as! CausalTreeControlViewController
        self.controls = wc2
        self.controlVC = cvc
        wc2.window?.title = "Site \(displayId())"
        wc2.window?.styleMask = [.titled, .miniaturizable, .resizable]
        wc2.showWindow(nil)
    }
    
    func receiveData(data: [UInt8])
    {
        //let decoder = DecoderT()
        //var crdt = try! decoder.decode(CausalTreeT.self, from: crdt)
        var newCrdt = try! BinaryDecoder.decode(CausalTreeT.self, data: data)
        
        timeMe({
            do
            {
                let _ = try newCrdt.validate()
            }
            catch
            {
                assert(false, "remote validation error: \(error)")
            }
            do
            {
                let _ = try self.crdt.validate()
            }
            catch
            {
                assert(false, "local validation error: \(error)")
            }
        }, "Validation")
        
        // save our state in case we want to revert
        _revisions.append(crdt.convert(localWeft: crdt.completeWeft()))
        
        timeMe({
            self.crdt.integrate(&newCrdt)
            let _ = self.crdt.weave.lamportTimestamp.increment() //per Lamport rules -- receive
        }, "Integration")
        
        self.reloadData()
    }
    
    func showWeave(storyboard: NSStoryboard)
    {
        if treeView == nil
        {
            let wc1 = storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(rawValue: "TreeView")) as! NSWindowController
            self.treeView = wc1
            let tvc = wc1.contentViewController as! CausalTreeDisplayViewController
            tvc.delegate = self.delegate
            self.treeVC = tvc
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: nil, using:
                { (notification: Notification) in
                    if self.treeView?.window == notification.object as? NSWindow
                    {
                        self.selectedAtom = nil
                        self.treeView = nil
                        self.treeVC = nil
                    }
            })
            if let w = wc1.window, let w2 = self.controls.window
            {
                w.title = "Weave \(displayId())"
                w.setFrameTopLeftPoint(NSMakePoint(w2.frame.origin.x + (w2.frame.size.width - w.frame.size.width)/2,
                                                   w2.frame.origin.y))
            }
            wc1.showWindow(nil)
        }
    }
    
    func reloadData(withModel: Bool = true)
    {
        self.controlVC.reloadData()
        self.treeVC?.reloadData()
    }
    
    func uuid() -> S
    {
        return crdt.siteIndex.site(crdt.weave.owner)!
    }
    
    func displayId() -> String
    {
        return "#\(uuid().hashValue)"
    }
}

// simulates connectivity & coordinates between peers
class Driver <S, V, InterfaceT: CausalTreeInterfaceProtocol> : NSObject, CausalTreeInterfaceDelegate where InterfaceT.SiteUUIDT == S, InterfaceT.ValueT == V
{
    typealias SiteUUIDT = S
    typealias ValueT = V
    
    typealias CausalTreeT = CausalTree<S,V>
    typealias PeerT = Peer<S,V>
    
    fileprivate var peers: [PeerT] = []
    fileprivate var interfaces: [InterfaceT] = []
    private var clock: Timer?
    
    let storyboard: NSStoryboard = NSStoryboard.init(name: NSStoryboard.Name(rawValue: "Main"), bundle: nil)
    
    required init(_ time: TimeInterval)
    {
        super.init()
        
        self.clock = Timer.scheduledTimer(timeInterval: time, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
    }

    func peerForId(_ id: Int) -> Peer<S,V>
    {
        return peers[id]
    }
    
    func createTree(fromPeer: Int?) -> CausalTreeT
    {
        let ownerUUID = SiteUUIDT()
        let tree: CausalTreeT
        
        if let peer = fromPeer
        {
            tree = peers[peer].crdt.copy() as! CausalTreeT
            tree.transferToNewOwner(withUUID: ownerUUID, clock: Int64(CACurrentMediaTime() * 1000))
        }
        else
        {
            tree =
                //WeaveHardConcurrency()
                //WeaveHardConcurrencyAutocommit()
                //WeaveTypingSimulation(100)
                CausalTreeT(site: ownerUUID, clock: Int64(CACurrentMediaTime() * 1000))
        }
        
        return tree
    }
    
    func appendPeer(fromPeer peer: Int?) -> Int
    {
        let id = peers.count
        
        let tree = createTree(fromPeer: peer)
        let peer = Peer(storyboard: storyboard, crdt: tree)
        let interface = InterfaceT(id: id, uuid: tree.ownerUUID(), storyboard: self.storyboard, crdt: peer.crdt, delegate: self)
        
        peers.append(peer)
        interfaces.append(interface)
        
        peer.delegate = interface
        peer.reloadData()
        interface.didUpdateCausalTree() //TODO: should be consolidated
        
        return id
    }
    
    @objc func tick() {}
}

extension Driver
{
    func isOnline(_ s: Int) -> Bool
    {
        return peerForId(s).isOnline
    }
    
    func isConnected(_ s: Int, toPeer s1: Int) -> Bool
    {
        let a = peerForId(s)

        if s == s1
        {
            return true
        }
        else
        {
            return a.peerConnections.contains(s1)
        }
    }
    
    func goOnline(_ o: Bool, _ s: Int)
    {
        peerForId(s).isOnline = o
    }
    
    func allOnline(_ o: Bool, _ s: Int)
    {
        for peer in peers
        {
            peer.isOnline = o
            peer.reloadData()
        }
    }
    
    func connect(_ o: Bool, _ s: Int, toPeer s1: Int)
    {
        let a = peerForId(s)
        
        if !o
        {
            a.peerConnections.remove(s1)
        }
        else
        {
            a.peerConnections.insert(s1)
        }
    }
    
    func fork(_ s: Int) -> Int
    {
        return appendPeer(fromPeer: s)
    }
    
    func siteId(_ s: Int) -> SiteId
    {
        let a = peerForId(s)
        
        return a.crdt.weave.owner
    }
    
    func id(ofSite site: SiteId, _ s: Int) -> Int
    {
        let a = peerForId(s)
        
        let uuid = a.crdt.siteIndex.site(site)!
        
        for (i,p) in self.peers.enumerated()
        {
            if p.uuid() == uuid
            {
                return i
            }
        }
        
        return -1
    }
    
    func siteId(ofPeer s1: Int, inPeer s: Int) -> SiteId?
    {
        let a = peerForId(s)
        let b = peerForId(s1)
        
        return a.crdt.siteIndex.siteMapping()[b.uuid()]
    }
    
    func showWeaveWindow(_ s: Int)
    {
        let a = peerForId(s)
        
        a.showWeave(storyboard: storyboard)
    }
    
    func showAwarenessInWeaveWindow(forAtom atom: AtomId?, _ s: Int)
    {
        let a = peerForId(s)
        
        a.treeVC?.drawAwareness(forAtom: atom)
    }
    
    func selectedAtom(_ s: Int) -> AtomId?
    {
        let a = peerForId(s)
        
        return a.selectedAtom
    }
    
    func didSelectAtom(_ atom: AtomId?, _ s: Int)
    {
        let a = peerForId(s)
        
        a.selectedAtom = atom
    }
    
    func reloadData(_ s: Int) {
        let a = peerForId(s)
        
        a.reloadData()
    }
    
    func revisions(_ s: Int) -> [Weft<CausalTreeStandardUUIDT>]
    {
        let a = peerForId(s)

        // KLUDGE: I couldn't figure out how to extend the class only when S == UUID, so we'll have to make do
        precondition(S.self == CausalTreeStandardUUIDT.self, "we need to implement code to handle other S types")
        return (a as! Peer<CausalTreeStandardUUIDT,V>).revisions
    }
    
    func selectedRevision(_ s: Int) -> Int?
    {
        let a = peerForId(s)
        
        return a.selectedRevision
    }
    
    func setRevision(_ r: Int?, _ s: Int)
    {
        let a = peerForId(s)
        
        a.selectedRevision = r
        
        // TODO: this should probably be placed elsewhere; and we should remove the reloadDatas from the VCs which trigger this
        interfaces[s].didUpdateRevision()
    }
}

class PeerToPeerDriver <S, V, I: CausalTreeInterfaceProtocol> : Driver<S, V, I> where S == I.SiteUUIDT, V == I.ValueT
{
    override func tick()
    {
        for (i,g) in self.peers.enumerated()
        {
            if g.isOnline
            {
                var result = ""
                
                for c in g.peerConnections
                {
                    let equal = self.peers[c].crdt.superset(&g.crdt)
                    
                    if !equal
                    {
                        if result.count == 0
                        {
                            result += "Syncing \(i):"
                        }
                        
                        // AB: simulating what happens over the network
                        //var serialized: Data!
                        var data: [UInt8]!
                        timeMe({
                            //let encoder = EncoderT()
                            let _ = g.crdt.weave.lamportTimestamp.increment() //per Lamport rules -- send
                            let crdt = g.crdt.copy() as! CausalTreeT
                            data = try! BinaryEncoder.encode(crdt)
                            print("Actual Size: \(String(format: "%.1f", CGFloat(data.count) / 1024)) kb")
                            //serialized = try! encoder.encode(crdt)
                        }, "Encode")
                        
                        self.peers[c].receiveData(data: data)
                        interfaces[c].didUpdateCausalTree() //TODO: should be consolidated
                        
                        result += " \(c)"
                    }
                }
                
                if result.count != 0
                {
                    print(result)
                }
            }
        }
    }
}
