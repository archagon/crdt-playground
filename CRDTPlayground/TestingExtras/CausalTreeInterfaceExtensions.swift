//
//  CausalTreeInterfaceExtensions.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-9-18.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import AppKit

extension CausalTreeInterfaceProtocol where SiteUUIDT == CausalTreeTextT.SiteUUIDT, ValueT == CausalTreeTextT.ValueT
{
//    func contentView(withCRDT crdt: CausalTree<SiteUUIDT,ValueT>) -> NSView
//    {
//        let scrollView = NSScrollView(frame: NSMakeRect(0, 0, 100, 100))
//        let contentSize = scrollView.contentSize
//        scrollView.borderType = .noBorder
//        scrollView.hasVerticalScroller = true
//        scrollView.hasHorizontalScroller = false
//
//        let textStorage = CausalTreeTextStorage(withCRDT: crdt)
//        let textContainer = NSTextContainer()
//        textContainer.widthTracksTextView = true
//        textContainer.heightTracksTextView = false
//        textContainer.lineBreakMode = .byCharWrapping
//        textContainer.size = NSMakeSize(contentSize.width, CGFloat.greatestFiniteMagnitude)
//        let layoutManager = NSLayoutManager()
//        layoutManager.addTextContainer(textContainer)
//        textStorage.addLayoutManager(layoutManager)
//
//        let textView = NSTextView(frame: NSMakeRect(0, 0, contentSize.width, contentSize.height), textContainer: textContainer)
//        //let textView = NSTextView(frame: NSMakeRect(0, 0, contentSize.width, contentSize.height))
//        textView.minSize = NSMakeSize(0, contentSize.height)
//        textView.maxSize = NSMakeSize(CGFloat.greatestFiniteMagnitude, CGFloat.greatestFiniteMagnitude)
//        textView.isVerticallyResizable = true
//        textView.isHorizontallyResizable = false
//        textView.autoresizingMask = [.width]
//
//        // AB: hack b/c can't seem to make extension conform to extra protocol
//        textView.delegate = (self as! NSTextViewDelegate)
//
//        scrollView.documentView = textView
//        return scrollView
//    }
//
//    func appendAtom(toAtom: AtomId?, forControlViewController vc: CausalTreeControlViewController)
//    {
//        guard let g = groupForController(vc) else { return }
//
//        if let atom = toAtom
//        {
//            TestingRecorder.shared?.recordAction(g.crdt.ownerUUID(), atom, AtomType.none, withId: TestCommand.addAtom.rawValue)
//
//            let id = g.crdt.weave.addAtom(withValue: characters[Int(arc4random_uniform(UInt32(characters.count)))], causedBy: atom, atTime: Clock(CACurrentMediaTime() * 1000))
//            g.selectedAtom = id
//            g.reloadData()
//        }
//        else
//        {
//            let index = g.crdt.weave.completeWeft().mapping[g.crdt.weave.owner] ?? -1
//            let cause = (index == -1 ? AtomId(site: ControlSite, index: 0) : AtomId(site: g.crdt.weave.owner, index: index))
//
//            TestingRecorder.shared?.recordAction(g.crdt.ownerUUID(), cause, AtomType.none, withId: TestCommand.addAtom.rawValue)
//
//            let id = g.crdt.weave.addAtom(withValue: characters[Int(arc4random_uniform(UInt32(characters.count)))], causedBy: cause, atTime: Clock(CACurrentMediaTime() * 1000))
//            g.selectedAtom = id
//            g.reloadData()
//        }
//    }
//
//    func printWeave(forControlViewController vc: CausalTreeControlViewController) -> String
//    {
//        guard let g = groupForController(vc) else { return "" }
//        let str = String(bytes: CausalTreeStringWrapper(crdt: g.crdt), encoding: String.Encoding.utf8)!
//        return str
//    }
}

class CausalTreeTextInterface : NSObject, CausalTreeInterfaceProtocol, NSTextStorageDelegate
{
    func isOnline(forControlViewController: CausalTreeControlViewController) -> Bool {
        return false
    }
    func isConnected(toSite: SiteId, forControlViewController: CausalTreeControlViewController) -> Bool {
        return false
    }
    func goOnline(_ online: Bool, forControlViewController: CausalTreeControlViewController) {
        return
    }
    func connect(_ connect: Bool, toSite: SiteId, forControlViewController: CausalTreeControlViewController) {
        return
    }
    func allSites(forControlViewController: CausalTreeControlViewController) -> [SiteId] {
        return []
    }
    func showWeave(forControlViewController: CausalTreeControlViewController) {
        return
    }
    func showAwareness(forAtom: AtomId?, inControlViewController: CausalTreeControlViewController) {
        return
    }
    func printWeave(forControlViewController: CausalTreeControlViewController) -> String {
        return ""
    }
    func generateWeave(forControlViewController: CausalTreeControlViewController) -> String {
        return ""
    }
    func generateCausalBlock(forAtom atom: AtomId, inControlViewController vc: CausalTreeControlViewController) -> CountableClosedRange<WeaveIndex>? {
        return nil
    }
    func appendAtom(toAtom: AtomId?, forControlViewController: CausalTreeControlViewController) {
        return
    }
    func deleteAtom(_ atom: AtomId, forControlViewController: CausalTreeControlViewController) {
        return
    }
    func addSite(forControlViewController: CausalTreeControlViewController) {
        return
    }
    func siteUUID(forControlViewController: CausalTreeControlViewController) -> UUID {
        return UUID()
    }
    func siteId(forControlViewController: CausalTreeControlViewController) -> SiteId {
        return 0
    }
    func selectedAtom(forControlViewController: CausalTreeControlViewController) -> AtomId? {
        return nil
    }
    func atomIdForWeaveIndex(_ weaveIndex: WeaveIndex, forControlViewController: CausalTreeControlViewController) -> AtomId? {
        return nil
    }
    func atomWeft(_ atom: AtomId, forControlViewController: CausalTreeControlViewController) -> Weft {
        return Weft()
    }
    func dataView(forControlViewController: CausalTreeControlViewController) -> NSView {
        return NSView()
    }
    func crdtSize(forControlViewController: CausalTreeControlViewController) -> Int {
        return 0
    }
    func atomCount(forControlViewController: CausalTreeControlViewController) -> Int {
        return 0
    }
    func didSelectAtom(_ atom: AtomId?, withButton: Int, inCausalTreeDisplayViewController: CausalTreeDisplayViewController) {
        return
    }
    func sites(forCausalTreeDisplayViewController vc: CausalTreeDisplayViewController) -> [SiteId] {
        return []
    }
    func length(forSite site: SiteId, forCausalTreeDisplayViewController vc: CausalTreeDisplayViewController) -> Int {
        return 0
    }
    func metadata(forAtom atom: AtomId, forCausalTreeDisplayViewController vc: CausalTreeDisplayViewController) -> AtomMetadata? {
        return nil
    }
    func awareness(forAtom atom: AtomId, forCausalTreeDisplayViewController vc: CausalTreeDisplayViewController) -> Weft? {
        return nil
    }
    func description(forAtom atom: AtomId, forCausalTreeDisplayViewController vc: CausalTreeDisplayViewController) -> String? {
        return nil
    }
    func beginDraw(forCausalTreeDisplayViewController vc: CausalTreeDisplayViewController) {
        return
    }
    func endDraw(forCausalTreeDisplayViewController vc: CausalTreeDisplayViewController) {
        return
    }
    
    typealias SiteUUIDT = CausalTreeTextT.SiteUUIDT
    typealias ValueT = CausalTreeTextT.ValueT
    
//    let storyboard: NSStoryboard = NSStoryboard.init(name: NSStoryboard.Name(rawValue: "Main"), bundle: nil)
//    unowned var delegate: DelegateT
    
    var id: Int
    
    required init(id: Int) {
        self.id = id
    }
    
//    var site: PeerT
//    {
//        return self.delegate.site(forInterface: self.id)!
//    }
//    var peers: [PeerT]
//    {
//        return self.delegate.peers(forInterface: self.id)
//    }
//    
//    required init(id: Int, delegate: DelegateT) {
//        self.id = id
//        self.delegate = delegate
//        super.init()
//    }
//    
//    func appendPeer(_ crdt: CausalTree<SiteUUIDT, ValueT>)
//    {
//        let _ = self.delegate.appendPeer(withCRDT: crdt, forInterface: self.id)
//    }
//    
//    // needs to be here b/c @objc method
//    @objc func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int)
//    {
//        for g in self.peers
//        {
//            if ((g.dataView as? NSScrollView)?.documentView as? NSTextView)?.textStorage == textStorage
//            {
//                g.reloadData(withModel: false)
//            }
//        }
//    }
}
