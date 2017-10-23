//
//  CausalTreeCloudKitTextStorage.swift
//  CloudKitRealTimeCollabTest
//
//  Created by Alexei Baboulevitch on 2017-10-19.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

/* NSTextView storage that uses our Causal Tree CRDT. Allows us to plug our CRDT right into NSTextView
 without any mapping or translation work. */

import UIKit

class CausalTreeCloudKitTextStorage: NSTextStorage
{
    private static var defaultAttributes: [NSAttributedStringKey:Any]
    {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        
        return [
            NSAttributedStringKey.font: UIFont(name: "Helvetica", size: 16)!,
            NSAttributedStringKey.foregroundColor: UIColor.black,
            NSAttributedStringKey.paragraphStyle: paragraphStyle
        ]
    }
    
    var revision: Weft?
    {
        didSet
        {
            self.backedString.revision = revision
            reloadData()
        }
    }
    
    private var isFixingAttributes = false
    private var cache: NSMutableAttributedString!
    
    required init(withCRDT crdt: CausalTreeString)
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
    
    required init?(pasteboardPropertyList propertyList: Any, ofType type: UIPasteboard.Type)
    {
        fatalError("init(pasteboardPropertyList:ofType:) has not been implemented")
    }
    
    func reloadData()
    {
        self.beginEditing()
        let oldLength = self.cache.length
        let newString = self.backedString
        self.cache.replaceCharacters(in: NSMakeRange(0, oldLength), with: newString as String)
        let newLength = self.cache.length
        assert((newString as NSString).length == self.cache.length)
        self.edited(NSTextStorageEditActions.editedCharacters, range: NSMakeRange(0, oldLength), changeInLength: newLength - oldLength)
        self.endEditing()
    }
    
    private var backedString: CausalTreeStringWrapper
    override var string: String
    {
        //return self.backedString
        return self.cache.string
    }
    
    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedStringKey : Any]
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
