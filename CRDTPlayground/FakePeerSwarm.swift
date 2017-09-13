//
//  FakePeerSwarm.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-9-11.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

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
    
    init(storyboard: NSStoryboard, sender: Driver, crdt: CausalTreeT)
    {
        weaveSetup: do
        {
            print(crdt)
            self.crdt = crdt
        }
        
        let wc2 = storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(rawValue: "Control")) as! NSWindowController
        let cvc = wc2.contentViewController as! ControlViewController
        cvc.delegate = sender
        self.controls = wc2
        self.controlVC = cvc
        wc2.window?.title = "Site \(displayId())"
        wc2.showWindow(sender)
    }
    
    func showWeave(storyboard: NSStoryboard, sender: Driver)
    {
        if treeView == nil
        {
            let wc1 = storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(rawValue: "TreeView")) as! NSWindowController
            self.treeView = wc1
            let tvc = wc1.contentViewController as! CausalTreeDisplayViewController
            tvc.delegate = sender
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
            wc1.window?.title = "Weave \(displayId())"
            wc1.showWindow(sender)
        }
    }
    
    func reloadData()
    {
        self.controlVC.reloadData()
        self.treeVC?.reloadData()
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
class Driver
{
    fileprivate var peers: [Peer] = []
    private var clock: Timer?
    
    private let storyboard = NSStoryboard.init(name: NSStoryboard.Name(rawValue: "Main"), bundle: nil)
    
    init() {
        self.clock = Timer.scheduledTimer(timeInterval: 2, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
    }
    
    @objc func tick() {}
}

extension Driver: ControlViewControllerDelegate, CausalTreeDisplayViewControllerDelegate
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
    
    func printWeave(forControlViewController vc: ControlViewController)
    {
        guard let g = groupForController(vc) else { return }
        stringifyTest: do {
            timeMe({
                var sum = ""
                sum.reserveCapacity(g.crdt.weave.atomCount())
                let blank = 0
                let _ = g.crdt.weave.process(blank, { (_, v:UniChar) -> Int in
                    if v == 0 { return 0 }
                    let uc = UnicodeScalar(v)!
                    let c = Character(uc)
                    sum.append(c)
                    return 0
                })
                print("String (\(sum.count) char): \(sum)")
            }, "StringGeneration")
        }
    }
    
    func generateWeave(forControlViewController vc: ControlViewController) -> String
    {
        guard let g = groupForController(vc) else { return "" }
        var string = "["
        let weave = g.crdt.weave.weave()
        for i in weave.startIndex..<weave.endIndex
        {
            if i != 0 {
                string += "|"
            }
            let a = weave[i]
            string += "\(a)"
        }
        string += "]"
        return string
    }
    
    func addAtom(forControlViewController vc: ControlViewController)
    {
        guard let g = groupForController(vc) else { return }
        
        let owner = g.crdt.weave.owner
        let ownerCount = g.crdt.weave.completeWeft().mapping[owner] ?? 0
        
        let site: SiteId
        let chanceOfGraft = arc4random_uniform(5)
        
        if chanceOfGraft == 0 || ownerCount == 0
        {
            var sites = Array(g.crdt.weave.completeWeft().mapping.keys)
            if let ownerIndex = sites.index(of: owner)
            {
                sites.remove(at: ownerIndex)
            }
            site = sites[Int(arc4random_uniform(UInt32(sites.count)))]
        }
        else
        {
            site = owner
        }
        
        let yarnIndex: Int
        
        if site == ControlSite
        {
            yarnIndex = 0
        }
        else
        {
            let yarn = g.crdt.weave.yarn(forSite: site)
            let yarnLength = yarn.count
            if chanceOfGraft == 0
            {
                yarnIndex = Int(arc4random_uniform(UInt32(yarnLength)))
            }
            else
            {
                yarnIndex = yarnLength - 1
            }
        }
        
        let causeId = CausalTreeT.WeaveT.AtomId(site: site, index: Int32(yarnIndex))
        let _ = g.crdt.weave.addAtom(withValue: characters[Int(arc4random_uniform(UInt32(characters.count)))], causedBy: causeId, atTime: Clock(CACurrentMediaTime() * 1000))
        
        g.reloadData()
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
    
    func appendAtom(toAtom: CausalTreeT.WeaveT.AtomId, forControlViewController vc: ControlViewController)
    {
        guard let g = groupForController(vc) else { return }
        let id = g.crdt.weave.addAtom(withValue: characters[Int(arc4random_uniform(UInt32(characters.count)))], causedBy: toAtom, atTime: Clock(CACurrentMediaTime() * 1000))
        g.selectedAtom = id
        g.reloadData()
    }
    
    func atomIdForWeaveIndex(_ weaveIndex: CausalTreeT.WeaveT.WeaveIndex, forControlViewController vc: ControlViewController) -> CausalTreeT.WeaveT.AtomId?
    {
        guard let g = groupForController(vc) else { return nil }
        return g.crdt.weave.weave()[Int(weaveIndex)].id
    }
    
    func addSite(fromPeer: Peer? = nil) {
        let tree: CausalTreeT
        
        if let group = fromPeer
        {
            tree = group.crdt.copy() as! CausalTreeT
            let site = tree.siteIndex.addSite(UUID(), withClock: Int64(CACurrentMediaTime() * 1000))
            let oldOwner = tree.weave.owner
            tree.weave.owner = site
        }
        else
        {
            tree =
                //WeaveHardConcurrency()
                //WeaveHardConcurrencyAutocommit()
                //WeaveTypingSimulation(100)
                CausalTreeT(site: UUID(), clock: Int64(CACurrentMediaTime() * 1000))
        }
        
        let g1 = Peer(storyboard: self.storyboard, sender: self, crdt: tree)
        self.peers.append(g1)
        g1.controlVC.reloadData()
    }
    
    func crdtCopy(forCausalTreeDisplayViewController vc: CausalTreeDisplayViewController) -> CausalTreeT
    {
        guard let g = groupForController(vc) else { return CausalTreeT(site: UUID.zero, clock: NullClock) }
        return g.crdt.copy() as! CausalTreeT
    }
    
    func didSelectAtom(_ atom: CausalTreeT.WeaveT.AtomId?, inCausalTreeDisplayViewController vc: CausalTreeDisplayViewController)
    {
        guard let g = groupForController(vc) else { return }
        g.selectedAtom = nil //to reset awareness
        g.selectedAtom = atom
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
                result += "Syncing \(i):"
                
                for c in g.peerConnections
                {
                    timeMe({
                        self.peers[c].crdt.integrate(&g.crdt)
                    }, "Integrate")
                    
                    assert({
                        for p in self.peers[c].crdt.weave.completeWeft().mapping
                        {
                            if (g.crdt.weave.completeWeft().mapping[p.key] ?? -1) > p.value
                            {
                                return false
                            }
                        }
                        return true
                    }())
                    self.peers[c].crdt.weave.assertTreeIntegrity()
                    
                    self.peers[c].reloadData()
                    
                    result += " \(c)"
                }
                
                print(result)
            }
        }
    }
}
