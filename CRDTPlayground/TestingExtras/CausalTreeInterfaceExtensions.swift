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
    func contentView(withCRDT crdt: CausalTree<SiteUUIDT,ValueT>) -> NSView
    {
        let scrollView = NSScrollView(frame: NSMakeRect(0, 0, 100, 100))
        let contentSize = scrollView.contentSize
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false

        let textStorage = CausalTreeTextStorage(withCRDT: crdt)
        let textContainer = NSTextContainer()
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        textContainer.lineBreakMode = .byCharWrapping
        textContainer.size = NSMakeSize(contentSize.width, CGFloat.greatestFiniteMagnitude)
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        let textView = NSTextView(frame: NSMakeRect(0, 0, contentSize.width, contentSize.height), textContainer: textContainer)
        //let textView = NSTextView(frame: NSMakeRect(0, 0, contentSize.width, contentSize.height))
        textView.minSize = NSMakeSize(0, contentSize.height)
        textView.maxSize = NSMakeSize(CGFloat.greatestFiniteMagnitude, CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        // AB: hack b/c can't seem to make extension conform to extra protocol
        textView.delegate = (self as! NSTextViewDelegate)
        
        scrollView.documentView = textView
        return scrollView
    }
    
    func appendAtom(toAtom: AtomId?, forControlViewController vc: CausalTreeControlViewController)
    {
        guard let g = groupForController(vc) else { return }

        if let atom = toAtom
        {
            TestingRecorder.shared?.recordAction(g.crdt.ownerUUID(), atom, AtomType.none, withId: TestCommand.addAtom.rawValue)

            let id = g.crdt.weave.addAtom(withValue: characters[Int(arc4random_uniform(UInt32(characters.count)))], causedBy: atom, atTime: Clock(CACurrentMediaTime() * 1000))
            g.selectedAtom = id
            g.reloadData()
        }
        else
        {
            let index = g.crdt.weave.completeWeft().mapping[g.crdt.weave.owner] ?? -1
            let cause = (index == -1 ? AtomId(site: ControlSite, index: 0) : AtomId(site: g.crdt.weave.owner, index: index))

            TestingRecorder.shared?.recordAction(g.crdt.ownerUUID(), cause, AtomType.none, withId: TestCommand.addAtom.rawValue)

            let id = g.crdt.weave.addAtom(withValue: characters[Int(arc4random_uniform(UInt32(characters.count)))], causedBy: cause, atTime: Clock(CACurrentMediaTime() * 1000))
            g.selectedAtom = id
            g.reloadData()
        }
    }
    
    func printWeave(forControlViewController vc: CausalTreeControlViewController) -> String
    {
        guard let g = groupForController(vc) else { return "" }
        let str = String(bytes: CausalTreeStringWrapper(crdt: g.crdt), encoding: String.Encoding.utf8)!
        return str
    }
}

class CausalTreeTextInterface : NSObject, CausalTreeInterfaceProtocol, NSTextStorageDelegate
{
    typealias SiteUUIDT = CausalTreeTextT.SiteUUIDT
    typealias ValueT = CausalTreeTextT.ValueT
    typealias DelegateT = Driver<CausalTreeTextT.SiteUUIDT, CausalTreeTextT.ValueT, CausalTreeTextInterface>
    
    let storyboard: NSStoryboard = NSStoryboard.init(name: NSStoryboard.Name(rawValue: "Main"), bundle: nil)
    unowned var delegate: DelegateT
    
    var id: Int
    var site: PeerT
    {
        return self.delegate.site(forInterface: self.id)!
    }
    var peers: [PeerT]
    {
        return self.delegate.peers(forInterface: self.id)
    }
    
    init(withId id: Int, delegate: DelegateT)
    {
        self.id = id
        self.delegate = delegate
        super.init()
    }
    
    func appendPeer(_ peer: Peer<SiteUUIDT,ValueT>)
    {
        self.delegate.appendPeer(peer, forInterface: self.id)
    }
    
    // needs to be here b/c @objc method
    @objc func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int)
    {
        for g in self.peers
        {
            if ((g.dataView as? NSScrollView)?.documentView as? NSTextView)?.textStorage == textStorage
            {
                g.reloadData(withModel: false)
            }
        }
    }
}
