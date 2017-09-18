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

import AppKit

typealias GroupId = Int

// simulates device
class Peer <SiteUUIDT: CausalTreeSiteUUIDT, ValueT: CausalTreeValueT>
{
    typealias CausalTreeT = CausalTree<SiteUUIDT, ValueT>
    
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
        
//        dataView
        
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
        
        if withModel
        {
//            (((self.dataView as? NSScrollView)?.documentView as? NSTextView)?.textStorage as? CausalTreeTextStorage)?.reloadData()
        }
    }
    
    func uuid() -> SiteUUIDT
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
    func site(forInterface i: Int) -> Peer<UUID, V>? {
        return peers[i] as! Peer<UUID, V>
    }
    
    typealias SiteUUIDT = S
    typealias ValueT = V
    
    typealias CausalTreeT = CausalTree<S, V>
    typealias PeerT = Peer<S, V>
    
    fileprivate var peers: [PeerT] = []
    private var interfaces: [InterfaceT] = []
    private var clock: Timer?
    
    override init() {
        super.init()
        self.clock = Timer.scheduledTimer(timeInterval: 2, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
    }

//    func site(forInterface i: Int) -> Peer<SiteUUIDT,ValueT>?
//    {
//        return peers[i]
//    }
    
    func peers(forInterface: Int) -> [Peer<SiteUUIDT,ValueT>]
    {
        return peers
    }
    
    func appendPeer(_ peer: Peer<SiteUUIDT,ValueT>, forInterface: Int) -> Bool
    {
        peers.append(peer)
        return true
    }
    
    @objc func tick() {}
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
