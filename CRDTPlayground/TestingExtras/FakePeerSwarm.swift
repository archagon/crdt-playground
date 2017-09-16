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
class Peer
{
    var crdt: CausalTreeT
    
    var isOnline: Bool = false
    var peerConnections = Set<GroupId>()
    var selectedAtom: CausalTreeT.WeaveT.AtomId?
    {
        didSet
        {
            self.treeVC?.drawSelection(forAtom: selectedAtom)
            reloadData()
        }
    }
    
    var controls: NSWindowController
    unowned var controlVC: ControlViewController
    var treeView: NSWindowController?
    weak var treeVC: CausalTreeDisplayViewController?
    var dataView: NSView
    
    weak var delegate: (NSTextStorageDelegate & CausalTreeDisplayViewControllerDelegate & ControlViewControllerDelegate)?
    {
        didSet
        {
            self.controlVC.delegate = delegate
            self.treeVC?.delegate = delegate
            (self.dataView as? NSTextView)?.textStorage?.delegate = delegate
        }
    }
    
    init(storyboard: NSStoryboard, crdt: CausalTreeT)
    {
        weaveSetup: do
        {
            print(crdt)
            self.crdt = crdt
        }
        
        dataViewSetup: do
        {
            let textStorage = CausalTreeTextStorage(withCRDT: self.crdt)
            let textContainer = NSTextContainer()
            textContainer.widthTracksTextView = true
            textContainer.heightTracksTextView = true
            textContainer.lineBreakMode = .byCharWrapping
            let layoutManager = NSLayoutManager()
            layoutManager.addTextContainer(textContainer)
            textStorage.addLayoutManager(layoutManager)
            let textView = NSTextView(frame: NSMakeRect(0, 0, 50, 50), textContainer: textContainer)
            self.dataView = textView
        }
        
        self.delegate = nil
        let wc2 = storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(rawValue: "Control")) as! NSWindowController
        let cvc = wc2.contentViewController as! ControlViewController
        self.controls = wc2
        self.controlVC = cvc
        wc2.window?.title = "Site \(displayId())"
        wc2.window?.styleMask = [.titled, .miniaturizable, .resizable]
        wc2.showWindow(nil)
    }
    
    func showWeave(storyboard: NSStoryboard, sender: Driver)
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
            wc1.showWindow(sender)
        }
    }
    
    func reloadData(withModel: Bool = true)
    {
        self.controlVC.reloadData()
        self.treeVC?.reloadData()
        
        if withModel
        {
            ((self.dataView as? NSTextView)?.textStorage as? CausalTreeTextStorage)?.reloadData()
        }
    }
    
    func uuid() -> UUID
    {
        return crdt.siteIndex.site(crdt.weave.owner)!
    }
    
    func displayId() -> String
    {
        return "#\(uuid().hashValue)"
    }
}

// simulates connectivity & coordinates between peers
class Driver: NSObject
{
    fileprivate var peers: [Peer] = []
    private var clock: Timer?
    
    private let storyboard = NSStoryboard.init(name: NSStoryboard.Name(rawValue: "Main"), bundle: nil)
    
    override init() {
        super.init()
        self.clock = Timer.scheduledTimer(timeInterval: 2, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
    }
    
    @objc func tick() {}
}

extension Driver: ControlViewControllerDelegate, CausalTreeDisplayViewControllerDelegate, NSTextStorageDelegate
{
    func groupForController(_ vc: NSViewController) -> Peer?
    {
        for g in peers
        {
            if g.controlVC == vc || g.treeVC == vc
            {
                return g
            }
        }
        return nil
    }
    
    func showWeave(forControlViewController vc: ControlViewController)
    {
        guard let g = groupForController(vc) else { return }
        g.showWeave(storyboard: storyboard, sender: self)
    }
    
    func siteUUID(forControlViewController vc: ControlViewController) -> UUID
    {
        guard let g = groupForController(vc) else { return UUID.zero }
        return g.crdt.siteIndex.site(g.crdt.weave.owner)!
    }
    
    func siteId(forControlViewController vc: ControlViewController) -> SiteId
    {
        guard let g = groupForController(vc) else { return NullSite }
        return g.crdt.weave.owner
    }
    
    func selectedAtom(forControlViewController vc: ControlViewController) -> CausalTreeT.WeaveT.AtomId?
    {
        guard let g = groupForController(vc) else { return CausalTreeT.WeaveT.NullAtomId }
        return g.selectedAtom
    }
    
    func atomWeft(_ atom: CausalTreeT.WeaveT.AtomId, forControlViewController vc: ControlViewController) -> CausalTreeT.WeaveT.Weft
    {
        guard let g = groupForController(vc) else { return CausalTreeT.WeaveT.Weft() }
        return g.crdt.weave.completeWeft()
    }
    
    func printWeave(forControlViewController vc: ControlViewController) -> String
    {
        guard let g = groupForController(vc) else { return "" }
        let str = String(bytes: CausalTreeStringWrapper(crdt: g.crdt), encoding: String.Encoding.utf8)!
        return str
    }
    
    func generateWeave(forControlViewController vc: ControlViewController) -> String
    {
        guard let g = groupForController(vc) else { return "" }
        return g.crdt.weave.atomsDescription
    }
    
    func addSite(forControlViewController vc: ControlViewController)
    {
        guard let g = groupForController(vc) else { return }
        addSite(fromPeer: g)
    }
    
    func isOnline(forControlViewController vc: ControlViewController) -> Bool
    {
        guard let g = groupForController(vc) else { return false }
        return g.isOnline
    }
    
    func isConnected(toSite site: SiteId, forControlViewController vc: ControlViewController) -> Bool
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
    
    func goOnline(_ online: Bool, forControlViewController vc: ControlViewController)
    {
        guard let g = groupForController(vc) else { return }
        g.isOnline = online
    }
    
    func connect(_ connect: Bool, toSite site: SiteId, forControlViewController vc: ControlViewController)
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
    
    func allSites(forControlViewController vc: ControlViewController) -> [SiteId]
    {
        guard let g = groupForController(vc) else { return [] }
        var allSites = Array(g.crdt.siteIndex.siteMapping().values)
        allSites.sort()
        allSites.remove(at: allSites.index(of: ControlSite)!)
        return allSites
    }
    
    func showAwareness(forAtom atom: CausalTreeT.WeaveT.AtomId?, inControlViewController vc: ControlViewController)
    {
        guard let g = groupForController(vc) else { return }
        g.treeVC?.drawAwareness(forAtom: atom)
    }
    
    func generateCausalBlock(forAtom atom: CausalTreeT.WeaveT.AtomId, inControlViewController vc: ControlViewController) -> CountableClosedRange<CausalTreeT.WeaveT.WeaveIndex>?
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
    
    func appendAtom(toAtom: CausalTreeT.WeaveT.AtomId?, forControlViewController vc: ControlViewController)
    {
        guard let g = groupForController(vc) else { return }
        
        if let atom = toAtom
        {
            TestingRecorder.shared?.recordAction(g.crdt.ownerUUID(), atom, CausalTreeT.WeaveT.SpecialType.none, withId: TestCommand.addAtom.rawValue)
            
            let id = g.crdt.weave.addAtom(withValue: characters[Int(arc4random_uniform(UInt32(characters.count)))], causedBy: atom, atTime: Clock(CACurrentMediaTime() * 1000))
            g.selectedAtom = id
            g.reloadData()
        }
        else
        {
            let index = g.crdt.weave.completeWeft().mapping[g.crdt.weave.owner] ?? -1
            let cause = (index == -1 ? CausalTreeT.WeaveT.AtomId(site: ControlSite, index: 0) : CausalTreeT.WeaveT.AtomId(site: g.crdt.weave.owner, index: index))
            
            TestingRecorder.shared?.recordAction(g.crdt.ownerUUID(), cause, CausalTreeT.WeaveT.SpecialType.none, withId: TestCommand.addAtom.rawValue)
            
            let id = g.crdt.weave.addAtom(withValue: characters[Int(arc4random_uniform(UInt32(characters.count)))], causedBy: cause, atTime: Clock(CACurrentMediaTime() * 1000))
            g.selectedAtom = id
            g.reloadData()
        }
    }
    
    func deleteAtom(_ atom: CausalTreeT.WeaveT.AtomId, forControlViewController vc: ControlViewController)
    {
        guard let g = groupForController(vc) else { return }
        
        TestingRecorder.shared?.recordAction(g.crdt.ownerUUID(), atom, withId: TestCommand.deleteAtom.rawValue)
        
        let _ = g.crdt.weave.deleteAtom(atom, atTime: Clock(CACurrentMediaTime() * 1000))
        g.selectedAtom = nil
        g.reloadData()
    }
    
    func atomIdForWeaveIndex(_ weaveIndex: CausalTreeT.WeaveT.WeaveIndex, forControlViewController vc: ControlViewController) -> CausalTreeT.WeaveT.AtomId?
    {
        guard let g = groupForController(vc) else { return nil }
        return g.crdt.weave.weave()[Int(weaveIndex)].id
    }
    
    func dataView(forControlViewController vc: ControlViewController) -> NSView
    {
        guard let g = groupForController(vc) else { return NSView() }
        return g.dataView
    }
    
    func crdtSize(forControlViewController vc: ControlViewController) -> Int
    {
        guard let g = groupForController(vc) else { return -1 }
        return g.crdt.sizeInBytes()
    }
    
    func atomCount(forControlViewController vc: ControlViewController) -> Int
    {
        guard let g = groupForController(vc) else { return -1 }
        return g.crdt.weave.atomCount()
    }
    
    func addSite(fromPeer: Peer? = nil) {
        let ownerUUID = UUID()
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
        self.peers.append(g1)
        g1.delegate = self
        g1.controlVC.reloadData()
    }
    
    func crdtCopy(forCausalTreeDisplayViewController vc: CausalTreeDisplayViewController) -> CausalTreeT
    {
        guard let g = groupForController(vc) else { return CausalTreeT(site: UUID.zero, clock: NullClock) }
        return g.crdt.copy() as! CausalTreeT
    }
    
    func didSelectAtom(_ atom: CausalTreeT.WeaveT.AtomId?, withButton button: Int, inCausalTreeDisplayViewController vc: CausalTreeDisplayViewController)
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
    
    public func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int)
    {
        for g in self.peers
        {
            if (g.dataView as? NSTextView)?.textStorage == textStorage
            {
                g.reloadData(withModel: false)
            }
        }
    }
}

class PeerToPeerDriver: Driver
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
                        
                        timeMe({
                            TestingRecorder.shared?.recordAction(self.peers[c].crdt.ownerUUID(), g.crdt.ownerUUID(), self.peers[c].crdt.weave.completeWeft(), g.crdt.weave.completeWeft(), withId: TestCommand.mergeSite.rawValue)
                            
                            var copy = g.crdt.copy() as! CausalTreeT
                            self.peers[c].crdt.integrate(&copy)
                        }, "Copy & Integrate")
                    
                        self.peers[c].crdt.weave.assertTreeIntegrity()
                        
                        self.peers[c].reloadData()
                        
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
