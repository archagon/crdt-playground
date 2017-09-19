//
//  CausalTreeInterfaceTextExtensions.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-9-18.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import AppKit

extension CausalTreeInterfaceProtocol where SiteUUIDT == CausalTreeTextT.SiteUUIDT, ValueT == CausalTreeTextT.ValueT
{
    func contentView() -> NSView
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
        if let atom = toAtom
        {
            TestingRecorder.shared?.recordAction(uuid, atom, AtomType.none, withId: TestCommand.addAtom.rawValue)

            let id = crdt.weave.addAtom(withValue: characters[Int(arc4random_uniform(UInt32(characters.count)))], causedBy: atom, atTime: Clock(CACurrentMediaTime() * 1000))
            delegate.didSelectAtom(id, self.id)
            delegate.reloadData(self.id)
        }
        else
        {
            let index = crdt.weave.completeWeft().mapping[crdt.weave.owner] ?? -1
            let cause = (index == -1 ? AtomId(site: ControlSite, index: 0) : AtomId(site: crdt.weave.owner, index: index))

            TestingRecorder.shared?.recordAction(uuid, cause, AtomType.none, withId: TestCommand.addAtom.rawValue)

            let id = crdt.weave.addAtom(withValue: characters[Int(arc4random_uniform(UInt32(characters.count)))], causedBy: cause, atTime: Clock(CACurrentMediaTime() * 1000))
            delegate.didSelectAtom(id, self.id)
            delegate.reloadData(self.id)
        }
    }

    func printWeave(forControlViewController vc: CausalTreeControlViewController) -> String
    {
        let str = String(bytes: CausalTreeStringWrapper(crdt: crdt), encoding: String.Encoding.utf8)!
        return str
    }
}

class CausalTreeTextInterface : NSObject, CausalTreeInterfaceProtocol, NSTextViewDelegate
{
    typealias SiteUUIDT = CausalTreeTextT.SiteUUIDT
    typealias ValueT = CausalTreeTextT.ValueT
    
    var id: Int
    var uuid: SiteUUIDT
    let storyboard: NSStoryboard
    unowned var crdt: CausalTree<SiteUUIDT, ValueT>
    var crdtCopy: CausalTree<UUID, UTF8Char>?
    unowned var delegate: CausalTreeInterfaceDelegate
    
    required init(id: Int, uuid: SiteUUIDT, storyboard: NSStoryboard, crdt: CausalTree<SiteUUIDT, ValueT>, delegate: CausalTreeInterfaceDelegate)
    {
        self.id = id
        self.uuid = uuid
        self.storyboard = storyboard
        self.crdt = crdt
        self.delegate = delegate
    }
    
    // needs to be here b/c @objc method
    @objc func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int)
    {
        delegate.reloadData(id)
    }
}
