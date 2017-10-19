//
//  CausalTreeStringWrapper.swift
//  CloudKitRealTimeCollabTest
//
//  Created by Alexei Baboulevitch on 2017-10-20.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import Foundation

class CausalTreeStringWrapper: NSMutableString
{
    // MARK: - Model -
    
    private weak var crdt: CausalTreeString!
    
    var revision: Weft?
    {
        didSet
        {
            if revision == nil
            {
                _slice = nil
            }
            else
            {
                _slice = crdt.weave.weave(withWeft: revision)
            }
            
            updateCache()
        }
    }
    
    // MARK: - Caches -
    
    private var _slice: CausalTreeString.WeaveT.AtomsSlice?
    private var slice: CausalTreeString.WeaveT.AtomsSlice
    {
        if let slice = _slice
        {
            return slice
        }
        else
        {
            return crdt.weave.weave(withWeft: nil)
        }
    }
    
    private var visibleCharacters: [WeaveIndex] = []
    
    // MARK: - Lifecycle -
    
    func initialize(crdt: CausalTreeString, revision: Weft? = nil)
    {
        self.crdt = crdt
        self.revision = revision
        
        updateCache()
    }
    
    // O(N), so use sparingly
    func updateCache()
    {
        let weave = self.crdt.weave.weave()
     
        var newCache: [WeaveIndex] = []
        
        var i = 0
        while i < weave.count
        {
            if weave[i].type == .value
            {
                var j = 0
                while (i + j + 1) < weave.count
                {
                    if weave[i + j + 1].type == .delete
                    {
                        j += 1
                    }
                    else
                    {
                        break
                    }
                }
                
                if j == 0 //not deleted
                {
                    newCache.append(WeaveIndex(i))
                }
                
                i += (j + 1)
            }
            else
            {
                i += 1
            }
        }
        
        self.visibleCharacters = newCache
        self._slice = (revision != nil ? crdt.weave.weave(withWeft: revision) : nil)
    }
    
    // MARK: - Essential Overrides -
    
    override var length: Int
    {
        return self.visibleCharacters.count
    }

    override func character(at index: Int) -> unichar
    {
        let i = self.visibleCharacters[index]
        return self.slice[Int(i)].value
    }
    
    // TODO: PERF: batch deletes and inserts, otherwise it's O(N^2) per length of insert, which is egregious for pastes
    override func replaceCharacters(in range: NSRange, with aString: String)
    {
        let anchor: AtomId
        
        if range.location == 0
        {
            anchor = slice[0].id
        }
        else
        {
            let index = visibleCharacters[range.location - 1]
            anchor = slice[Int(index)].id
        }
        
        var atomsToDelete: [AtomId] = []
        for i in range.lowerBound..<range.upperBound
        {
            let index = visibleCharacters[i]
            atomsToDelete.append(slice[Int(index)].id)
        }
        
        insert: do
        {
            var prevChar = anchor
            for char in aString.utf16
            {
                prevChar = crdt.weave.addAtom(withValue: char, causedBy: prevChar, atTime: 0)!.0
            }
        }
        
        delete: do
        {
            for a in atomsToDelete
            {
                let _ = crdt.weave.deleteAtom(a, atTime: 0)
            }
        }
        
        // PERF: slow, can delta-update this stuff
        updateCache()
    }
}
