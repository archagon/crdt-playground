//
//  StringTypeUtilities.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-9-16.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import Foundation

struct CausalTreeStringWrapper: Sequence, IteratorProtocol
{
    unowned var crdt: CausalTreeT
    var weaveIndex: CausalTreeT.WeaveT.WeaveIndex? = nil
    
    init(crdt: CausalTreeT) {
        self.crdt = crdt
    }
    
    mutating func next() -> UTF8Char?
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
            
            weaveIndex = index
            
            return v
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
        
        if a.type.unparented
        {
            return nil
        }
        
        if a.type == .none && a.value != 0
        {
            let j = i + 1
            if j < crdt.weave.weave().count && crdt.weave.weave()[j].type == .delete
            {
                return nextCharacterIndex(startingIndex: CausalTreeT.WeaveT.WeaveIndex(i + 1))
            }
            else
            {
                return startingIndex
            }
        }
        else
        {
            return nextCharacterIndex(startingIndex: CausalTreeT.WeaveT.WeaveIndex(i + 1))
        }
    }
    
    mutating func reset()
    {
        weaveIndex = nil
    }
}
