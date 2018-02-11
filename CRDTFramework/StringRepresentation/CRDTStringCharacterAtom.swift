//
//  CRDTStringCharacterAtom.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-11-1.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import Foundation

public enum StringCharacterAtom: CausalTreeValueT, CRDTValueReference, Codable
{
    case null
    case insert(char: UInt16)
    case delete
    
    public init()
    {
        self = .null
    }
    
    public init(insert c: UInt16)
    {
        self = .insert(char: c)
    }
    
    public init(withDelete: Bool)
    {
        self = .delete
    }
    
    public var reference: AtomId
    {
        return NullAtomId
    }
    
    public var atomDescription: String
    {
        switch self
        {
        case .null:
            return "ø"
        case .insert(let char):
            return "\(Character(UnicodeScalar(char) ?? UnicodeScalar(0)))"
        case .delete:
            return "X"
        }
    }
    
    public var childless: Bool
    {
        switch self
        {
        case .null:
            return false
        case .insert(_):
            return false
        case .delete:
            return true
        }
    }
    
    public var priority: UInt8
    {
        switch self
        {
        case .null:
            return 0
        case .insert(_):
            return 0
        case .delete:
            return 1
        }
    }
    
    public mutating func remapIndices(_ map: [SiteId : SiteId])
    {
        return
    }
}

extension StringCharacterAtom
{
    private enum CodingKeys: Int, CodingKey
    {
        case null
        case insert
        case delete
        case meta
    }
    private var codingKey: CodingKeys
    {
        switch self
        {
        case .null:
            return .null
        case .insert:
            return .insert
        case .delete:
            return .delete
        }
    }
    
    public init(from decoder: Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // get id
        var meta = try container.nestedUnkeyedContainer(forKey: .meta)
        let metaVal = try meta.decode(Int.self)
        let type = CodingKeys(rawValue: metaVal) ?? .meta
        
        // get associated type
        switch type
        {
        case .null:
            self = .null
        case .insert:
            let insert = try container.decode(UInt16.self, forKey: .insert)
            self = .insert(char: insert)
        case .delete:
            self = .delete
        case .meta:
            throw DecodingError.dataCorruptedError(in: meta, debugDescription: "out of date: missing datum with id \(metaVal)")
        }
    }
    
    public func encode(to encoder: Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        // store id
        var meta = container.nestedUnkeyedContainer(forKey: .meta)
        try meta.encode(codingKey.rawValue)
        
        // store associated data
        switch self
        {
        case .null:
            break
        case .insert(let char):
            try container.encode(char, forKey: .insert)
        case .delete:
            break
        }
    }
}
