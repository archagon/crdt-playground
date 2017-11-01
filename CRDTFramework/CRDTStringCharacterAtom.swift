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
    private enum CodingKeys: CodingKey
    {
        case null
        case insert
        case delete
    }
    
    private enum CodingError: Error
    {
        case decoding(String)
    }
    
    public init(from decoder: Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        if let null = try? container.decode(Bool.self, forKey: .null), null == true
        {
            self = .null
        }
        else if let insert = try? container.decode(UInt16.self, forKey: .insert)
        {
            self = .insert(char: insert)
        }
        else if let _ = try? container.decode(Bool.self, forKey: .delete)
        {
            self = .delete
        }
        else
        {
            throw CodingError.decoding("Decoding error: \(dump(container))")
        }
    }
    
    public func encode(to encoder: Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self
        {
        case .null:
            try container.encode(true, forKey: .null)
        case .insert(let char):
            try container.encode(char, forKey: .insert)
        case .delete:
            try container.encode(true, forKey: .delete)
        }
    }
}
