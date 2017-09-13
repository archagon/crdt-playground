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
    var dataView: NSView
    
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
            textContainer.lineBreakMode = .byCharWrapping
            let layoutManager = NSLayoutManager()
            layoutManager.addTextContainer(textContainer)
            textStorage.addLayoutManager(layoutManager)
            let textView = NSTextView(frame: NSMakeRect(0, 0, 50, 50), textContainer: textContainer)
            self.dataView = textView
        }
        
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
            if let w = wc1.window, let w2 = self.controls.window
            {
                w.title = "Weave \(displayId())"
                w.setFrameTopLeftPoint(NSMakePoint(w2.frame.origin.x + (w2.frame.size.width - w.frame.size.width)/2,
                                                   w2.frame.origin.y))
            }
            wc1.showWindow(sender)
        }
    }
    
    func reloadData()
    {
        self.controlVC.reloadData()
        self.treeVC?.reloadData()
        ((self.dataView as? NSTextView)?.textStorage as? CausalTreeTextStorage)?.reloadData()
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

class CausalTreeTextStorage: NSTextStorage
{
    private static var defaultAttributes: [NSAttributedStringKey:Any]
    {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        
        return [
            NSAttributedStringKey.font: NSFont(name: "Futura", size: 14)!,
            NSAttributedStringKey.foregroundColor: NSColor.blue,
            NSAttributedStringKey.paragraphStyle: paragraphStyle
        ]
    }
    
    unowned var crdt: CausalTreeT
    private var isFixingAttributes = false
    private var cache: NSMutableAttributedString!
    
    required init(withCRDT crdt: CausalTreeT)
    {
        self.crdt = crdt
        super.init()
        self.cache = NSMutableAttributedString(string: crdtString, attributes: type(of: self).defaultAttributes)
    }
    
    required init?(coder aDecoder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init?(pasteboardPropertyList propertyList: Any, ofType type: NSPasteboard.PasteboardType)
    {
        fatalError("init(pasteboardPropertyList:ofType:) has not been implemented")
    }
    
    func reloadData()
    {
        let oldLength = self.string.count
        let newString = self.crdtString
        self.cache.replaceCharacters(in: NSMakeRange(0, oldLength), with: newString)
        let newLength = self.string.count
        self.edited(NSTextStorageEditActions.editedCharacters, range: NSMakeRange(0, oldLength), changeInLength: newLength - oldLength)
    }
    
    // AB: this is slow -- a string should really be able to the array directly -- but it's a demo app
    var crdtString: String
    {
        let weave = crdt.weave.weave()
        var string = ""
        weave.forEach
        { atom in
            if atom.value != 0 && !atom.type.nonCausal
            {
                let uc = UnicodeScalar(atom.value)!
                let c = Character(uc)
                string.append(c)
            }
        }
        return string
    }
    
    override var string: String
    {
        return self.cache.string
    }
    
    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedStringKey : Any]
    {
        return self.cache.length == 0 ? [:] : self.cache.attributes(at: location, effectiveRange: range)
    }
    
    override func replaceCharacters(in range: NSRange, with str: String)
    {
//        (self.tempString as NSMutableString).replaceCharacters(in: range, with: str)
//        self.cache.mutableString.replaceCharacters(in: range, with: str)
//        self.edited(NSTextStorageEditActions.editedCharacters, range: range, changeInLength: (str as NSString).length - range.length)
    }
    
    override func setAttributes(_ attrs: [NSAttributedStringKey : Any]?, range: NSRange)
    {
        // only allow attributes from attribute fixing (for e.g. emoji)
        if self.isFixingAttributes {
            self.cache.setAttributes(attrs, range: range)
            self.edited(NSTextStorageEditActions.editedAttributes, range: range, changeInLength: 0)
        }
    }
    
    override func fixAttributes(in range: NSRange)
    {
        self.isFixingAttributes = true
        super.fixAttributes(in: range)
        self.isFixingAttributes = false
    }
    
    override func processEditing()
    {
        self.isFixingAttributes = true
        self.setAttributes(nil, range: self.editedRange)
        self.setAttributes(type(of: self).defaultAttributes, range: self.editedRange)
        self.isFixingAttributes = false
        super.processEditing()
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
        return g.crdt.weave.atomsDescription
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
        
        g.crdt.weave.assertTreeIntegrity()
        
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
    
    func appendAtom(toAtom: CausalTreeT.WeaveT.AtomId?, forControlViewController vc: ControlViewController)
    {
        guard let g = groupForController(vc) else { return }
        
        if let atom = toAtom
        {
            let id = g.crdt.weave.addAtom(withValue: characters[Int(arc4random_uniform(UInt32(characters.count)))], causedBy: atom, atTime: Clock(CACurrentMediaTime() * 1000))
            g.selectedAtom = id
            g.reloadData()
        }
        else
        {
            let index = g.crdt.weave.completeWeft().mapping[g.crdt.weave.owner] ?? -1
            let cause = (index == -1 ? CausalTreeT.WeaveT.AtomId(site: ControlSite, index: 0) : CausalTreeT.WeaveT.AtomId(site: g.crdt.weave.owner, index: index))
            let id = g.crdt.weave.addAtom(withValue: characters[Int(arc4random_uniform(UInt32(characters.count)))], causedBy: cause, atTime: Clock(CACurrentMediaTime() * 1000))
            g.selectedAtom = id
            g.reloadData()
        }
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
        
        let g1 = Peer(storyboard: self.storyboard, crdt: tree)
        self.peers.append(g1)
        g1.controlVC.delegate = self
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
