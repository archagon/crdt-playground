//
//  CRDTStringCharacterAtom.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-11-1.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import Foundation

class StringCharacterAtom: CausalTreeValueT, CRDTValueReference, Codable
{
    var value: StringCharacterValueType
    
    required init()
    {
        self.value = .null
    }
    
    init(insert c: UInt16, toTheRightOf id: AtomId)
    {
        self.value = .insert(char: c, ref: id)
    }
    
    init(deleteOf id: AtomId)
    {
        self.value = .delete(ref: id)
    }
    
    var reference: AtomId?
    {
        return nil
    }
    
    var atomDescription: String
    {
        switch value
        {
        case .null:
            return "ø"
        case .insert(let char, _):
            return "\(Character(UnicodeScalar(char) ?? UnicodeScalar(0)))"
        case .delete(_):
            return "X"
        }
    }
    
    var childless: Bool
    {
        switch value
        {
        case .null:
            return false
        case .insert(_, _):
            return false
        case .delete(_):
            return true
        }
    }
    
    var priority: UInt8
    {
        switch value
        {
        case .null:
            return 0
        case .insert(_, _):
            return 0
        case .delete(_):
            return 1
        }
    }
    
    func remapIndices(_ map: [SiteId : SiteId])
    {
        switch value
        {
        case .null:
            break
        case .insert(let char, let ref):
            if let newSite = map[ref.site]
            {
                value = .insert(char: char, ref: AtomId(site: newSite, index: ref.index))
            }
        case .delete(let ref):
            if let newSite = map[ref.site]
            {
                value = .delete(ref: AtomId(site: newSite, index: ref.index))
            }
        }
    }
}

enum StringCharacterValueType
{
    case null
    case insert(char: UInt16, ref: AtomId)
    case delete(ref: AtomId)
}
extension StringCharacterValueType: Codable
{
    private enum CodingKeys: CodingKey
    {
        case null
        case insert
        case delete
    }
    
    enum CodingError: Error
    {
        case decoding(String)
    }
    
    private struct Pair<T1: Codable, T2: Codable>: Codable
    {
        let o1: T1
        let o2: T2
    }
    
    init(from decoder: Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        if let null = try? container.decode(Bool.self, forKey: .null), null == true
        {
            self = .null
        }
        else if let insert = try? container.decode(Pair<UInt16, AtomId>.self, forKey: .insert)
        {
            self = .insert(char: insert.o1, ref: insert.o2)
        }
        else if let delete = try? container.decode(AtomId.self, forKey: .delete)
        {
            self = .delete(ref: delete)
        }
        else
        {
            throw CodingError.decoding("Decoding error: \(dump(container))")
        }
    }
    
    func encode(to encoder: Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self
        {
        case .null:
            try container.encode(true, forKey: .null)
        case .insert(let char, let ref):
            try container.encode(Pair<UInt16, AtomId>(o1: char, o2: ref), forKey: .insert)
        case .delete(let ref):
            try container.encode(ref, forKey: .delete)
        }
    }
}
