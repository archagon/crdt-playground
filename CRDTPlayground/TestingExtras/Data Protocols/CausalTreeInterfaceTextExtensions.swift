//
//  CausalTreeInterfaceTextExtensions.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-9-18.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import AppKit
//import CRDTFramework_OSX

class TextScrollView: NSScrollView, CausalTreeContentView, NSTextStorageDelegate {
    weak var listener: CausalTreeListener? = nil
    var lastCursorPosition: CausalTreeTextT.AbsoluteAtomIdT? = nil

    @objc func causalTreeWillUpdate(sender: NSObject?) {
        if
            let textView = self.documentView as? NSTextView,
            let storage = textView.textStorage as? CausalTreeTextStorage {
            // AB: kind of a kludgy way to do this, but oh well
            if let cursorAtom = storage.backedString.atomForCharacterAtIndex(textView.selectedRange().location) {
                let absoluteCursorAtom = storage.backedString.crdt.convert(localAtom: cursorAtom)
                self.lastCursorPosition = absoluteCursorAtom
            }
        }
    }

    @objc func causalTreeDidUpdate(sender: NSObject?) {
        if
            let textView = self.documentView as? NSTextView,
            let storage = textView.textStorage as? CausalTreeTextStorage {
            storage.reloadData()

            if
                let absoluteCursor = self.lastCursorPosition,
                let cursor = storage.backedString.crdt.convert(absoluteAtom: absoluteCursor),
                let cursorIndex = storage.backedString.characterIndex(for: cursor) {
                textView.setSelectedRange(NSMakeRange(cursorIndex, 0))
                self.lastCursorPosition = nil
            }
        }
    }

    // needs to be here b/c @objc method
    @objc func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        self.listener?.causalTreeDidUpdate?(sender: self)
    }

    func updateRevision(_ revision: Weft<CausalTreeStandardUUIDT>?) {
        (self.documentView as? NSTextView)?.isEditable = (revision == nil)
        ((self.documentView as? NSTextView)?.textStorage as? CausalTreeTextStorage)?.revision = revision
        (self.documentView as? NSTextView)?.setNeedsDisplay(.infinite) //AB: see CausalTreeTextStorage for reason
    }
}

extension CausalTreeInterfaceProtocol where SiteUUIDT == CausalTreeTextT.SiteUUIDT, ValueT == CausalTreeTextT.ValueT {
    func createContentView() -> NSView & CausalTreeContentView {
        let scrollView = TextScrollView(frame: NSMakeRect(0, 0, 100, 100))
        let contentSize = scrollView.contentSize
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false

        let textStorage = CausalTreeTextStorage(withCRDT: crdt)
        let textContainer = NSTextContainer()
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        textContainer.lineBreakMode = .byCharWrapping
        textContainer.size = NSMakeSize(contentSize.width, .greatestFiniteMagnitude)
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        let textView = NSTextView(frame: NSRect(size: contentSize), textContainer: textContainer)
        //let textView = NSTextView(frame: NSMakeRect(0, 0, contentSize.width, contentSize.height))
        textView.minSize = NSMakeSize(0, contentSize.height)
        textView.maxSize = .max
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textStorage.delegate = scrollView

        scrollView.documentView = textView

        scrollView.listener = self
        return scrollView
    }

    func preferredWindowSize() -> NSSize {
        return NSMakeSize(450, 430)
    }

    func printWeave(forControlViewController vc: CausalTreeControlViewController) -> String {
        let str = CausalTreeStringWrapper()
        str.initialize(crdt: crdt)

        return str as String
    }
}

class CausalTreeTextInterface : NSObject, CausalTreeInterfaceProtocol {
    typealias SiteUUIDT = CausalTreeTextT.SiteUUIDT
    typealias ValueT = CausalTreeTextT.ValueT

    var id: Int
    var uuid: SiteUUIDT
    let storyboard: NSStoryboard
    lazy var contentView: NSView & CausalTreeContentView = createContentView()

    unowned var crdt: CausalTree<SiteUUIDT, ValueT>
    var crdtCopy: CausalTree<SiteUUIDT, ValueT>?
    unowned var delegate: CausalTreeInterfaceDelegate

    required init(id: Int, uuid: SiteUUIDT, storyboard: NSStoryboard, crdt: CausalTree<SiteUUIDT, ValueT>, delegate: CausalTreeInterfaceDelegate) {
        self.id = id
        self.uuid = uuid
        self.storyboard = storyboard
        self.crdt = crdt
        self.delegate = delegate
    }

    // stupid boilerplate b/c can't include @objc in protocol extensions
    @objc func causalTreeDidUpdate(sender: NSObject?) {
        // change from content view, so update interface
        delegate.reloadData(self.id)
    }
}
