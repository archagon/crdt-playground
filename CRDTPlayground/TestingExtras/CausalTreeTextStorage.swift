//
//  CausalTreeTextStorage.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-9-13.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

/* NSTextView storage that uses our Causal Tree CRDT. Allows us to plug our CRDT right into NSTextView
 without any mapping or translation work. WARNING: performance is potentially dog-slow since we feed
 our CRDT into the String directly as a sequence, meaning possibly no caches and no indexing. */

import AppKit

// TODO: emoji/unicode does not currently work correctly

class CausalTreeTextStorage: NSTextStorage
{
    private static var defaultAttributes: [NSAttributedStringKey:Any]
    {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        
        return [
            NSAttributedStringKey.font: NSFont(name: "Helvetica", size: 12)!,
            NSAttributedStringKey.foregroundColor: NSColor.black,
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
        let oldLength = self.cache.length
        let newString = self.crdtString
        self.cache.replaceCharacters(in: NSMakeRange(0, oldLength), with: newString)
        let newLength = self.cache.length
        assert((newString as NSString).length == self.cache.length)
        self.edited(NSTextStorageEditActions.editedCharacters, range: NSMakeRange(0, oldLength), changeInLength: newLength - oldLength)
    }
    
    var crdtString: String
    {
        let string = String(bytes: CausalTreeStringWrapper(crdt: self.crdt), encoding: String.Encoding.utf8)!
        return string
    }
    
    override var string: String
    {
        return self.crdtString
        //return self.cache.string
    }
    
    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedStringKey : Any]
    {
        return self.cache.attributes(at: location, effectiveRange: range)
    }
    
    override func replaceCharacters(in nsRange: NSRange, with str: String)
    {
        guard let range = Range(nsRange, in: self.string) else
        {
            assert(false, "NSRange could not be mapped to Swift string")
            return
        }
        
        // PERF: might be slow
        var sequence = CausalTreeStringWrapper(crdt: self.crdt)

        var attachmentAtom: Int = -1
        var deletion: (start: Int, length: Int)?
        
        // insertion index query
        if range.lowerBound == self.string.startIndex
        {
            attachmentAtom = 0
        }
        else
        {
            let previousCharRange = self.string.index(range.lowerBound, offsetBy: -1)
            let previousChar = self.string[previousCharRange..<range.lowerBound]
            let utf8EndIndex = previousChar.utf8.endIndex
            let locationRange = (self.string.utf8.startIndex..<utf8EndIndex)
            let location = self.string.utf8[locationRange].count
            
            sequence.reset()
            for _ in 0..<location { let _ = sequence.next() }
            attachmentAtom = Int(sequence.weaveIndex!)
        }
        assert(attachmentAtom != -1, "could not find attachment point")
        
        // deletion index query
        if nsRange.length > 0
        {
            let deleteChar = self.string[range.lowerBound..<range.upperBound]
            let utf8StartIndex = deleteChar.utf8.startIndex
            let utf8EndIndex = deleteChar.utf8.endIndex
            let locationRange = (self.string.utf8.startIndex..<utf8StartIndex)
            let lengthRange = (utf8StartIndex..<utf8EndIndex)
            let location = self.string.utf8[locationRange].count
            let length = self.string.utf8[lengthRange].count
            
            sequence.reset()
            for _ in 0...location { let _ = sequence.next() }
            deletion = (Int(sequence.weaveIndex!), length)
        }

        // deletion; this goes first, b/c the inserted atom will precede these atoms
        if let d = deletion
        {
            for i in (d.start..<(d.start + d.length)).reversed()
            {
                let a = crdt.weave.weave()[i].id
                
                TestingRecorder.shared?.recordAction(crdt.ownerUUID(), a, withId: TestCommand.deleteAtom.rawValue)
                
                let _ = crdt.weave.deleteAtom(a, atTime: Clock(CACurrentMediaTime() * 1000))
            }
        }
        
        // insertion
        var prevAtom = crdt.weave.weave()[attachmentAtom].id
        for u in str.utf8
        {
            TestingRecorder.shared?.recordAction(crdt.ownerUUID(), prevAtom, CausalTreeT.WeaveT.SpecialType.none, withId: TestCommand.addAtom.rawValue)
            
            prevAtom = crdt.weave.addAtom(withValue: UTF8Char(u), causedBy: prevAtom, atTime: Clock(CACurrentMediaTime() * 1000))!
        }

        // cache update
        let oldCacheLength = self.cache.length
        self.cache.replaceCharacters(in: nsRange, with: str)
        let newCacheLength = self.cache.length
        self.edited(NSTextStorageEditActions.editedCharacters, range: nsRange, changeInLength: newCacheLength - oldCacheLength)
        assert(self.cache.length == (self.crdtString as NSString).length)
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
        super.processEditing()
        //self.isFixingAttributes = true
        self.setAttributes(nil, range: self.editedRange)
        self.setAttributes(type(of: self).defaultAttributes, range: self.editedRange)
        //self.isFixingAttributes = false
    }
}

