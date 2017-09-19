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

typealias GroupId = Int

// simulates device
// TODO: this should be close to a dumb struct
class Peer <S: CausalTreeSiteUUIDT, V: CausalTreeValueT>
{
    typealias CausalTreeT = CausalTree<S, V>
    
    var crdt: CausalTreeT
    var crdtCopy: CausalTreeT? //used while rendering
    
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
        var crdt = try! BinaryDecoder.decode(CausalTreeT.self, data: data)
        
        TestingRecorder.shared?.recordAction(self.crdt.ownerUUID(), crdt.ownerUUID(), self.crdt.weave.completeWeft(), crdt.weave.completeWeft(), withId: TestCommand.mergeSite.rawValue)
        
        timeMe({
            do
            {
                let _ = try crdt.validate()
            }
            catch
            {
                assert(false, "validation error: \(error)")
            }
        }, "Validation")
        
        timeMe({
            self.crdt.integrate(&crdt)
        }, "Integration")
        
        self.crdt.weave.assertTreeIntegrity()
        
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
class Driver <S, V, InterfaceT: CausalTreeInterfaceProtocol> : NSObject where InterfaceT.SiteUUIDT == S, InterfaceT.ValueT == V
{
    typealias SiteUUIDT = S
    typealias ValueT = V
    
    typealias CausalTreeT = CausalTree<S,V>
    typealias PeerT = Peer<S,V>
    
    fileprivate var peers: [PeerT] = []
    fileprivate var interfaces: [InterfaceT] = []
    private var clock: Timer?
    
    let storyboard: NSStoryboard = NSStoryboard.init(name: NSStoryboard.Name(rawValue: "Main"), bundle: nil)
    
    override init() {
        super.init()
        self.clock = Timer.scheduledTimer(timeInterval: 2, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
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
            TestingRecorder.shared?.recordAction(ownerUUID, peers[peer].uuid(), peers[peer].crdt.weave.completeWeft(), withId: TestCommand.forkSite.rawValue)

            tree = peers[peer].crdt.copy() as! CausalTreeT
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
        interface.reloadData() //TODO: should be consolidated
        
        return id
    }
    
    @objc func tick() {}
}

extension Driver: CausalTreeInterfaceDelegate
{
    typealias CTIDSiteUUIDT = S
    typealias CTIDValueT = V
    
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
}

class PeerToPeerDriver <S, V, I: CausalTreeInterfaceProtocol> : Driver<S, V, I> where S == I.SiteUUIDT, V == I.ValueT
{
    override func tick() {
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
                            let crdt = g.crdt.copy() as! CausalTreeT
                            data = try! BinaryEncoder.encode(crdt)
                            //serialized = try! encoder.encode(crdt)
                        }, "Encode")
                        
                        self.peers[c].receiveData(data: data)
                        interfaces[c].reloadData() //TODO: should be consolidated
                        
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
