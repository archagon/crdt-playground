//
//  CausalTreeStringWrapper.swift
//  CloudKitRealTimeCollabTest
//
//  Created by Alexei Baboulevitch on 2017-10-20.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import Foundation

// AB: The extra cache in this class on top of the existing cache in the slice adds extra complexity.

class CausalTreeStringWrapper: NSMutableString
{
    // MARK: - Model -
    
    private(set) weak var crdt: CausalTreeString!
    
    var revision: CausalTreeString.WeftT?
    {
        didSet
        {
            if revision != oldValue
            {
                _slice = nil
            }
        }
    }
    
    // MARK: - Caches -
    
    private var _slice: CausalTreeString.WeaveT.AtomsSlice?
    private var slice: CausalTreeString.WeaveT.AtomsSlice
    {
        if let revision = self.revision
        {
            if _slice == nil || _slice!.invalid
            {
                _slice = crdt.weave.weave(withWeft: crdt.convert(weft: revision))
                assert(_slice != nil, "could not convert revision to local weft")
                updateCache()
            }
            return _slice!
        }
        else
        {
            if _slice == nil || _slice!.invalid
            {
                _slice = crdt.weave.weave(withWeft: nil)
                updateCache()
            }
            return _slice!
        }
    }
    
    private var _visibleCharacters: [WeaveIndex] = []
    private var visibleCharacters: [WeaveIndex]
    {
        let _ = self.slice //ensures that all our caches are up to date
        return _visibleCharacters
    }
    
    // MARK: - Lifecycle -
    
    func initialize(crdt: CausalTreeString, revision: CausalTreeString.WeftT? = nil)
    {
        self.crdt = crdt
        self.revision = revision
        
        updateCache()
    }
    
    // O(N), so use sparingly
    private func updateCache()
    {
        let weave = self.slice
     
        _visibleCharacters.removeAll()
        
        var i = 0
        while i < weave.count
        {
            if case .insert(_) = weave[i].value
            {
                var j = 0
                while (i + j + 1) < weave.count
                {
                    if case .delete = weave[i + j + 1].value
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
                    _visibleCharacters.append(WeaveIndex(i))
                }
                
                i += (j + 1)
            }
            else
            {
                i += 1
            }
        }
    }
    
    func atomForCharacterAtIndex(_ i: Int) -> AtomId?
    {
        if i > visibleCharacters.count || i < 0
        {
            return nil
        }
        
        if i == 0
        {
            return slice[0].id
        }
        else
        {
            return slice[Int(visibleCharacters[i - 1])].id
        }
    }
    
    // TODO: PERF: this is currently O(SxN), and will need tuning before production use
    func characterIndexForAtom(_ a: AtomId) -> Int?
    {
        if a == slice[0].id
        {
            return 0
        }
        
        for c in 0..<visibleCharacters.count
        {
            if slice[Int(visibleCharacters[c])].id == a
            {
                return c + 1
            }
        }
        
        return nil
    }
    
    // MARK: - Essential Overrides -
    
    override var length: Int
    {
        return self.visibleCharacters.count
    }

    override func character(at index: Int) -> unichar
    {
        let i = self.visibleCharacters[index]
        if case .insert(let char) = self.slice[Int(i)].value
        {
            return char
        }
        else
        {
            assert(false)
            return 0
        }
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
                prevChar = crdt.weave.addAtom(withValue: StringCharacterAtom(insert: char), causedBy: prevChar)!.atomID
            }
        }
        
        delete: do
        {
            for a in atomsToDelete
            {
                let _ = crdt.weave.addAtom(withValue: StringCharacterAtom.init(withDelete: true), causedBy: a)
            }
        }
        
        // PERF: cache update after this point is slow, should delta-update
        //updateCache()
    }
}
