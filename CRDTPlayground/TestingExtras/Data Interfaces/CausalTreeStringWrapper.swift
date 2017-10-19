//
//  CausalTreeStringWrapper.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-9-16.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import Foundation
//import CRDTFramework_OSX

struct CausalTreeStringWrapper: Sequence, IteratorProtocol
{
    private unowned var crdt: CausalTreeTextT
    
    private let revision: Weft?
    private let _slice: CausalTreeTextT.WeaveT.AtomsSlice?
    private var slice: CausalTreeTextT.WeaveT.AtomsSlice
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
    
    var weaveIndex: WeaveIndex? = nil
    
    init(crdt: CausalTreeTextT, revision: Weft?)
    {
        self.crdt = crdt
        self.revision = revision
        
        if revision == nil
        {
            _slice = nil
        }
        else
        {
            _slice = crdt.weave.weave(withWeft: revision)
        }
    }
    
    mutating func next() -> UTF8Char?
    {
        let i: WeaveIndex
        if let i0 = weaveIndex
        {
            i = i0 + 1
        }
        else
        {
            i = WeaveIndex(0)
        }
        
        if let index = nextCharacterIndex(startingIndex: i)
        {
            let v = slice[Int(index)].value
            
            weaveIndex = index
            
            return v
        }
        else
        {
            return nil
        }
    }
    
    private func nextCharacterIndex(startingIndex: WeaveIndex) -> WeaveIndex?
    {
        let i = Int(startingIndex)
        
        if i >= slice.count
        {
            return nil
        }
        
        let a = slice[i]
        
        if a.type.unparented
        {
            return nil
        }
        
        if a.type.value && a.value != 0
        {
            let j = i + 1
            if j < slice.count && slice[j].type == .delete
            {
                return nextCharacterIndex(startingIndex: WeaveIndex(i + 1))
            }
            else
            {
                return startingIndex
            }
        }
        else
        {
            return nextCharacterIndex(startingIndex: WeaveIndex(i + 1))
        }
    }
    
    mutating func reset()
    {
        weaveIndex = nil
    }
}
