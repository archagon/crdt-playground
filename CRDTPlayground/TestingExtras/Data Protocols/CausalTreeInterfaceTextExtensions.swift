//
//  CausalTreeInterfaceTextExtensions.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-9-18.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import AppKit
import CRDTFramework

class TextScrollView: NSScrollView, CausalTreeContentView, NSTextStorageDelegate
{
    weak var listener: CausalTreeListener? = nil
    
    @objc func causalTreeDidUpdate(sender: NSObject?)
    {
        ((self.documentView as? NSTextView)?.textStorage as? CausalTreeTextStorage)?.reloadData()
    }
    
    // needs to be here b/c @objc method
    @objc func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int)
    {
        self.listener?.causalTreeDidUpdate?(sender: self)
    }
    
    func updateRevision(_ revision: Weft?)
    {
        (self.documentView as? NSTextView)?.isEditable = (revision == nil)
        ((self.documentView as? NSTextView)?.textStorage as? CausalTreeTextStorage)?.revision = revision
    }
}

extension CausalTreeInterfaceProtocol where SiteUUIDT == CausalTreeTextT.SiteUUIDT, ValueT == CausalTreeTextT.ValueT
{
    func createContentView() -> NSView & CausalTreeContentView {
        let scrollView = TextScrollView(frame: NSMakeRect(0, 0, 100, 100))
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
        textStorage.delegate = scrollView

        scrollView.documentView = textView
        
        scrollView.listener = self
        return scrollView
    }

    func appendAtom(toAtom: AtomId?, forControlViewController vc: CausalTreeControlViewController)
    {
        if let atom = toAtom
        {
            TestingRecorder.shared?.recordAction(uuid, atom, AtomType.value, withId: TestCommand.addAtom.rawValue)

            let id = crdt.weave.addAtom(withValue: characters[Int(arc4random_uniform(UInt32(characters.count)))], causedBy: atom, atTime: Clock(CACurrentMediaTime() * 1000))?.0
            delegate.didSelectAtom(id, self.id)
            delegate.reloadData(self.id)
            
            didUpdateCausalTree()
        }
        else
        {
            let index = crdt.weave.completeWeft().mapping[crdt.weave.owner] ?? -1
            let cause = (index == -1 ? AtomId(site: ControlSite, index: 0) : AtomId(site: crdt.weave.owner, index: index))

            TestingRecorder.shared?.recordAction(uuid, cause, AtomType.value, withId: TestCommand.addAtom.rawValue)

            let id = crdt.weave.addAtom(withValue: characters[Int(arc4random_uniform(UInt32(characters.count)))], causedBy: cause, atTime: Clock(CACurrentMediaTime() * 1000))?.0
            delegate.didSelectAtom(id, self.id)
            delegate.reloadData(self.id)
            
            didUpdateCausalTree()
        }
    }

    func printWeave(forControlViewController vc: CausalTreeControlViewController) -> String
    {
        let str = String(bytes: CausalTreeStringWrapper(crdt: crdt, revision: nil), encoding: String.Encoding.utf8)!
        return str
    }
}

class CausalTreeTextInterface : NSObject, CausalTreeInterfaceProtocol
{    
    typealias SiteUUIDT = CausalTreeTextT.SiteUUIDT
    typealias ValueT = CausalTreeTextT.ValueT
    
    var id: Int
    var uuid: SiteUUIDT
    let storyboard: NSStoryboard
    lazy var contentView: NSView & CausalTreeContentView = createContentView()
    
    unowned var crdt: CausalTree<SiteUUIDT, ValueT>
    var crdtCopy: CausalTree<SiteUUIDT, ValueT>?
    unowned var delegate: CausalTreeInterfaceDelegate
    
    required init(id: Int, uuid: SiteUUIDT, storyboard: NSStoryboard, crdt: CausalTree<SiteUUIDT, ValueT>, delegate: CausalTreeInterfaceDelegate)
    {
        self.id = id
        self.uuid = uuid
        self.storyboard = storyboard
        self.crdt = crdt
        self.delegate = delegate
    }
    
    // stupid boilerplate b/c can't include @objc in protocol extensions
    @objc func causalTreeDidUpdate(sender: NSObject?)
    {
        // change from content view, so update interface
        delegate.reloadData(self.id)
    }
}
