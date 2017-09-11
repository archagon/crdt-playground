//
//  AppDelegate.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-8-28.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

// NEXT: no need to save commit if a) you're already aware of the site so far, b) you're connecting to the last item
// NEXT: completeWeft() vs. siteLocalWeft()? (i.e. what does my site know so that I can strategically place my commits?)
// NEXT: overlapping site id bug in hard concurrency demo weave?

import Cocoa

typealias CausalTreeT = CausalTree<UUID,UniChar>

struct TestStruct {
    var site: Int32
    var causingSite: Int32
    var index: Int64
    var causingIndex: Int64
    var value: UniChar
}

let characters: [UniChar] = ["a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p","q","r","s","t","u","v","w","x","y","z"].map {
    UnicodeScalar($0)!.utf16.first!
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, ControlViewControllerDelegate, CausalTreeDisplayViewControllerDelegate
{
    class Group
    {
        var crdt: CausalTreeT
        
        var isOnline: Bool = false
        var groupConnections = Set<Int>()
        
        var controls: NSWindowController
        unowned var controlVC: ControlViewController
        var treeView: NSWindowController?
        weak var treeVC: ViewController?
        
        init(storyboard: NSStoryboard, sender: AppDelegate, crdt: CausalTreeT)
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
            wc2.window?.title = "Site #\(uuid().hashValue)"
            wc2.showWindow(sender)
        }
        
        func showWeave(storyboard: NSStoryboard, sender: AppDelegate)
        {
            if treeView == nil
            {
                let wc1 = storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(rawValue: "TreeView")) as! NSWindowController
                self.treeView = wc1
                let tvc = wc1.contentViewController as! ViewController
                tvc.delegate = sender
                self.treeVC = tvc
                NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: nil, using:
                { (notification: Notification) in
                    if self.treeView?.window == notification.object as? NSWindow
                    {
                        self.treeView = nil
                        self.treeVC = nil
                    }
                })
                wc1.window?.title = "Weave #\(uuid().hashValue)"
                wc1.showWindow(sender)
            }
        }
        
        func uuid() -> UUID
        {
            return crdt.siteIndex.site(crdt.weave.owner)!
        }
    }
    
    let storyboard = NSStoryboard.init(name: NSStoryboard.Name(rawValue: "Main"), bundle: nil)
    var groups: [Group] = []
    var clock: Timer!
    
    var randomArray = ContiguousArray<TestStruct>()
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        quickPerfCheck: do {
            let startCharCount = 500000
            let iterationCount = 1500
            
            print("Size of test struct: \(MemoryLayout<TestStruct>.size)")
            
            timeMe({
                for _ in 0..<startCharCount {
                    let val: UniChar = characters[Int(arc4random_uniform(UInt32(characters.count)))]
                    let aStruct = TestStruct(site: Int32(arc4random_uniform(8)), causingSite: Int32(arc4random_uniform(8)), index: Int64(arc4random_uniform(10000000)), causingIndex: Int64(arc4random_uniform(10000000)), value: val)
                    randomArray.append(aStruct)
                }
            }, "TestArrayGen")
            
            for _ in 0..<iterationCount {
                timeMe({
                    let randomIndex = Int(arc4random_uniform(UInt32(randomArray.count)))
                    let val: UniChar = characters[Int(arc4random_uniform(UInt32(characters.count)))]
                    let aStruct = TestStruct(site: Int32(arc4random_uniform(8)), causingSite: Int32(arc4random_uniform(8)), index: Int64(arc4random_uniform(10000000)), causingIndex: Int64(arc4random_uniform(10000000)), value: val)
                    randomArray.insert(aStruct, at: randomIndex)
                }, "TestArrayBenchmark", every: 200)
            }
            
            let testMap: [Int32:Int32] = [0:3,1:2,2:7,5:6,7:0]
            timeMe({
                for i in 0..<randomArray.count {
                    if let fromMap = testMap[randomArray[i].site] {
                        randomArray[i].site = fromMap
                    }
                    if let toMap = testMap[randomArray[i].causingSite] {
                        randomArray[i].causingSite = toMap
                    }
                }
            }, "TestArrayRewrite")
            
            clock = Timer.scheduledTimer(withTimeInterval: 2, repeats: true, block: { (_: Timer) in
                for (i,g) in self.groups.enumerated()
                {
                    if g.isOnline
                    {
                        var result = ""
                        result += "Syncing \(i):"
                        
                        for c in g.groupConnections
                        {
                            timeMe({
                                self.groups[c].crdt.integrate(&g.crdt)
                            }, "Integrate")
                            self.groups[c].treeVC?.reloadData()
                            self.groups[c].controlVC.reloadData()
                            
                            result += " \(c)"
                        }
                        
                        print(result)
                    }
                }
            })
            addSite()
        }
    }
    
    func groupForController(_ vc: NSViewController) -> Group?
    {
        for g in groups
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
    
    func selectedAtom(forControlViewController vc: ControlViewController) -> CausalTreeT.WeaveT.Atom
    {
        guard let g = groupForController(vc) else { return CausalTreeT.WeaveT.Atom(id: CausalTreeT.WeaveT.NullAtomId, cause: CausalTreeT.WeaveT.NullAtomId, clock: NullClock, value: 0) }
        return g.crdt.weave.yarn(forSite: 0).first!
    }
    
    func atomWeft(_ atom: CausalTreeT.WeaveT.AtomId, forControlViewController vc: ControlViewController) -> CausalTreeT.WeaveT.Weft
    {
        guard let g = groupForController(vc) else { return CausalTreeT.WeaveT.Weft() }
        return g.crdt.weave.completeWeft()
    }
    
    func printWeave(forControlViewController vc: ControlViewController)
    {
        guard let g = groupForController(vc) else { return }
        print("Generating \(g.crdt.weave.atomCount())-character string...")
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
                //print("String result (\(sum.count) char): \(sum)")
                for c in sum { let b = c }
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
            string += "\(a.id.site):\(a.id.index)-\(a.cause.site):\(a.cause.index)"
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
        
        g.controlVC.reloadData()
        g.treeVC?.reloadData()
    }
    
    func addSite(forControlViewController vc: ControlViewController)
    {
        guard let g = groupForController(vc) else { return }
        addSite(fromGroup: g)
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
        for (i,aG) in groups.enumerated()
        {
            let uuid = aG.crdt.siteIndex.site(aG.crdt.weave.owner)!
            if uuid == targetUuid
            {
                return g.groupConnections.contains(i)
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
        for (i,aG) in groups.enumerated()
        {
            let uuid = aG.crdt.siteIndex.site(aG.crdt.weave.owner)!
            if uuid == targetUuid
            {
                if connect
                {
                    g.groupConnections.insert(i)
                }
                else
                {
                    g.groupConnections.remove(i)
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
    
    func crdtCopy(forCausalTreeDisplayViewController vc: ViewController) -> CausalTreeT
    {
        guard let g = groupForController(vc) else { return CausalTreeT(site: UUID.zero, clock: NullClock) }
        return g.crdt.copy() as! CausalTreeT
    }
    
    func addSite(fromGroup: Group? = nil) {
        let tree: CausalTreeT
        
        if let group = fromGroup
        {
            tree = group.crdt.copy() as! CausalTreeT
            let site = tree.siteIndex.addSite(UUID(), withClock: Int64(CACurrentMediaTime() * 1000))
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
        
        let g1 = Group(storyboard: self.storyboard, sender: self, crdt: tree)
        self.groups.append(g1)
        g1.controlVC.reloadData()
    }
}

