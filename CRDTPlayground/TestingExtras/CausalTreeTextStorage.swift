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

class CausalTreeTextStorage: NSTextStorage
{
    struct CausalTreeStringWrapper: Sequence, IteratorProtocol
    {
        unowned var crdt: CausalTreeT
        var weaveIndex: CausalTreeT.WeaveT.WeaveIndex? = nil
        
        mutating func next() -> Character?
        {
            let i: CausalTreeT.WeaveT.WeaveIndex
            if let i0 = weaveIndex
            {
                i = i0 + 1
            }
            else
            {
                i = CausalTreeT.WeaveT.WeaveIndex(0)
            }
            
            if let index = nextCharacterIndex(startingIndex: i)
            {
                let v = crdt.weave.weave()[Int(index)].value
                let uc = UnicodeScalar(v)!
                let c = Character(uc)
                
                weaveIndex = index
                
                return c
            }
            else
            {
                return nil
            }
        }
        
        private func nextCharacterIndex(startingIndex: CausalTreeT.WeaveT.WeaveIndex) -> CausalTreeT.WeaveT.WeaveIndex?
        {
            let i = Int(startingIndex)
            
            if i >= crdt.weave.weave().count
            {
                return nil
            }
            
            let a = crdt.weave.weave()[i]
            
            if a.type.nonCausal
            {
                return nil
            }
            
            if a.value != 0
            {
                return startingIndex
            }
            else
            {
                return nextCharacterIndex(startingIndex: CausalTreeT.WeaveT.WeaveIndex(i + 1))
            }
        }
    }
    
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
        let oldLength = self.cache.string.count
        let newString = self.crdtString
        self.cache.replaceCharacters(in: NSMakeRange(0, oldLength), with: newString)
        let newLength = self.cache.string.count
        assert(newString.count == self.cache.length)
        self.edited(NSTextStorageEditActions.editedCharacters, range: NSMakeRange(0, oldLength), changeInLength: newLength - oldLength)
    }
    
    var crdtString: String
    {
        let string = String(CausalTreeStringWrapper(crdt: self.crdt, weaveIndex: nil))
        return string
    }
    
    override var string: String
    {
        //return self.cache.string
        return self.crdtString
    }
    
    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedStringKey : Any]
    {
        return self.cache.length == 0 || location >= self.cache.length ? [:] : self.cache.attributes(at: location, effectiveRange: range)
    }
    
    override func replaceCharacters(in range: NSRange, with str: String)
    {
        if range.length != 0
        {
            // TODO:
            print("Deletion not yet supported!")
        }
        else
        {
            // PERF: might be slow
            var sequence = CausalTreeStringWrapper(crdt: self.crdt, weaveIndex: nil)
            var resultString: String? = nil
            
            for _ in 0..<range.location
            {
                let _ = sequence.next()
            }
            let aIndex: CausalTreeT.WeaveT.WeaveIndex?
            if let i = sequence.weaveIndex
            {
                aIndex = i
            }
            else if range.location == 0
            {
                aIndex = 0
            }
            else
            {
                aIndex = nil
            }
            if let index = aIndex
            {
                var prevAtom = crdt.weave.weave()[Int(index)].id
                for c in str.characters
                {
                    if c.unicodeScalars.count > 1
                    {
                        continue
                    }
                    for u in c.unicodeScalars
                    {
                        if u.utf16.count != 1
                        {
                            continue
                        }
                        
                        TestingRecorder.shared?.recordAction(crdt.ownerUUID(), prevAtom, CausalTreeT.WeaveT.SpecialType.none, withId: TestCommand.addAtom.rawValue)
                        
                        let uc = u.utf16.first!
                        prevAtom = crdt.weave.addAtom(withValue: UniChar(uc), causedBy: prevAtom, atTime: Clock(CACurrentMediaTime() * 1000))!
                        if resultString == nil { resultString = "" }
                        resultString!.append(c)
                    }
                }
                
                if let rString = resultString
                {
                    let oldCacheLength = self.cache.length
                    self.cache.replaceCharacters(in: range, with: rString)
                    let newCacheLength = self.cache.length
                    self.edited(NSTextStorageEditActions.editedCharacters, range: range, changeInLength: newCacheLength - oldCacheLength)
                }
            }
        }
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

