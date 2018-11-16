//
//  CausalTreeTextStorage.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-9-13.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

/* NSTextView storage that uses our Causal Tree CRDT. Allows us to plug our CRDT right into NSTextView
 without any mapping or translation work. */

import AppKit
//import CRDTFramework_OSX

class CausalTreeTextStorage: NSTextStorage
{
    private static var defaultAttributes: [NSAttributedString.Key:Any]
    {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        
        return [
            NSAttributedString.Key.font: NSFont(name: "Helvetica", size: 24)!,
            NSAttributedString.Key.foregroundColor: NSColor.blue,
            NSAttributedString.Key.paragraphStyle: paragraphStyle
        ]
    }
    
    var revision: CausalTreeTextT.WeftT?
    {
        didSet
        {
            self.backedString.revision = revision
            
            // BUG: sometimes a revision will not stick if selected shortly after switching to an inactive window,
            // though oddly not when you're already viewing a revision; can sometimes be mitigated by clicking on the
            // text field, but not for the last revision entry; seemingly fixed by forcing setNeedsDisplay, but I
            // don't understand why this isn't handled automatically FOR JUST THOSE CASES
            reloadData()
        }
    }
    
    private var isFixingAttributes = false
    private var cache: NSMutableAttributedString!
    
    // AB: a new container is sometimes created on paste — presumably to hold the intermediary string — so we have
    // to do this slightly ugly hack; this CT is merely treated like an ordinary string and does not merge with anything
    var _kludgeCRDT: CausalTreeTextT?
    override convenience init()
    {
        let kludge = CausalTreeTextT(site: UUID.zero, clock: 0)
        self.init(withCRDT: kludge)
        self._kludgeCRDT = kludge
        print("WARNING: created blank container")
    }
    
    required init(withCRDT crdt: CausalTreeTextT)
    {
        self.backedString = CausalTreeStringWrapper()
        self.backedString.initialize(crdt: crdt)
        
        super.init()
        
        // AB: we do it in this order b/c we need the emojis to get their attributes
        let startingString = self.backedString
        self.cache = NSMutableAttributedString(string: startingString as String, attributes: type(of: self).defaultAttributes)
        //self.append(NSAttributedString(string: startingString as String))
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
        // PERF: this replacement should be piecewise
        self.beginEditing()
        let oldLength = self.cache.length
        //self.backedString.treeWasEdited() //updates indices @ string wrapper //AB: no longer needed, object updates itself
        let newString = self.backedString
        self.cache.replaceCharacters(in: NSMakeRange(0, oldLength), with: newString as String)
        let newLength = self.cache.length
        assert((newString as NSString).length == self.cache.length)
        self.edited(NSTextStorageEditActions.editedCharacters, range: NSMakeRange(0, oldLength), changeInLength: newLength - oldLength)
        self.endEditing()
    }
    
    private(set) var backedString: CausalTreeStringWrapper
    override var string: String
    {
        //return self.backedString
        return self.cache.string
    }
    
    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key : Any]
    {
        return self.cache.attributes(at: location, effectiveRange: range)
    }
    
    override func replaceCharacters(in nsRange: NSRange, with str: String)
    {
        assert(self.revision == nil)
        
        self.backedString.replaceCharacters(in: nsRange, with: str)
        
        // cache update
        let oldCacheLength = self.cache.length
        self.cache.replaceCharacters(in: nsRange, with: str)
        let newCacheLength = self.cache.length
        self.edited(NSTextStorageEditActions.editedCharacters, range: nsRange, changeInLength: newCacheLength - oldCacheLength)
        
        //print(self.backedString.crdt.weave.atomsDescription)
        assert(self.cache.length == self.backedString.length)
    }
    
    override func setAttributes(_ attrs: [NSAttributedString.Key : Any]?, range: NSRange)
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
