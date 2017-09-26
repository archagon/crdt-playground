//
//  CausalTreeTypeSetup.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-9-25.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import AppKit

typealias CausalTreeTextT = CausalTree<UUID,UTF8Char>
typealias CausalTreeBezierT = CausalTree<UUID,DrawDatum>

// NEXT: what is the size of this thing?
enum DrawDatum
{
    case null //no-op for grouping other atoms
    case shape
    case point(pos: NSPoint)
    case pointSentinelStart
    case pointSentinelEnd
    case opTranslate(delta: NSPoint)
    case attrColor(NSColor)
    case attrRound(Bool)
    // TODO: reserve space!
    
    // AB: maybe this is a stupid way to assign identifiers to our cases, but hey, it works
    enum Id: Int, CodingKey
    {
        case meta //unrelated to above, used for coding hijinks
        case null
        case shape
        case point
        case pointSentinelStart
        case pointSentinelEnd
        case opTranslate
        case attrColor
        case attrRound
    }
    var id: Id
    {
        switch self
        {
        case .null:
            return .null
        case .shape:
            return .shape
        case .point:
            return .point
        case .pointSentinelStart:
            return .pointSentinelStart
        case .pointSentinelEnd:
            return .pointSentinelEnd
        case .opTranslate:
            return .opTranslate
        case .attrColor:
            return .attrColor
        case .attrRound:
            return .attrRound
        }
    }
    
    var point: Bool
    {
        if case .point(_) = self
        {
            return true
        }
        if case .pointSentinelStart = self
        {
            return true
        }
        if case .pointSentinelEnd = self
        {
            return true
        }
        
        return false
    }
    
    var pointSentinel: Bool
    {
        if case .pointSentinelStart = self
        {
            return true
        }
        if case .pointSentinelEnd = self
        {
            return true
        }
        
        return false
    }
    
    var operation: Bool
    {
        if case .opTranslate(_) = self
        {
            return true
        }
        
        return false
    }
    
    var attribute: Bool
    {
        if case .attrColor(_) = self
        {
            return true
        }
        else if case .attrRound(_) = self
        {
            return true
        }
        
        return false
    }
    
    init()
    {
        self = .null
    }
    
    init(from decoder: Decoder) throws
    {
        let container = try decoder.container(keyedBy: Id.self)
        
        // get id
        var meta = try container.nestedUnkeyedContainer(forKey: .meta)
        let metaVal = try meta.decode(Int.self)
        guard let type = Id(intValue: metaVal) else
        {
            throw DecodingError.dataCorruptedError(in: meta, debugDescription: "out of date: missing datum with id \(metaVal)")
        }
        
        // get associated type
        switch type
        {
        case .meta:
            throw DecodingError.dataCorruptedError(in: meta, debugDescription: "tried to unpack .meta datum")
        case .null:
            self = .null
        case .shape:
            self = .shape
        case .point:
            let pos = try container.decode(NSPoint.self, forKey: .point)
            self = .point(pos: pos)
        case .pointSentinelStart:
            self = .pointSentinelStart
        case .pointSentinelEnd:
            self = .pointSentinelEnd
        case .opTranslate:
            let delta = try container.decode(NSPoint.self, forKey: .opTranslate)
            self = .opTranslate(delta: delta)
        case .attrColor:
            let colorArray = try container.decode([CGFloat].self, forKey: .attrColor)
            let color = NSColor(red: colorArray[0], green: colorArray[1], blue: colorArray[2], alpha: colorArray[3])
            self = .attrColor(color)
        case .attrRound:
            let round = try container.decode(Bool.self, forKey: .attrRound)
            self = .attrRound(round)
        }
    }
    
    func encode(to encoder: Encoder) throws
    {
        var container = encoder.container(keyedBy: Id.self)
        
        // store id
        var meta = container.nestedUnkeyedContainer(forKey: .meta)
        try meta.encode(id.rawValue)
        
        // store associated data
        switch self
        {
        case .point(let pos):
            try container.encode(pos, forKey: .point)
        case .opTranslate(let delta):
            try container.encode(delta, forKey: .opTranslate)
        case .attrColor(let color):
            try container.encode([color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent], forKey: .attrColor)
        case .attrRound(let round):
            try container.encode(round, forKey: .attrRound)
        default:
            break
        }
    }
}

extension UTF8Char: CausalTreeValueT {}
extension UTF8Char: CausalTreeAtomPrintable
{
    var atomDescription: String
    {
        get
        {
            return String(self)
        }
    }
}

extension DrawDatum: CausalTreeValueT {}
extension DrawDatum: CausalTreeAtomPrintable
{
    var atomDescription: String
    {
        get
        {
            switch self {
            case .null:
                return "X0"
            case .shape:
                return "S0"
            case .point(let pos):
                return "P\(String(format: "%.1fx%.1f", pos.x, pos.y))"
            case .pointSentinelStart:
                return "P0"
            case .pointSentinelEnd:
                return "P1"
            case .opTranslate(let delta):
                return "T\(String(format: "%.1fx%.1f", delta.x, delta.y))"
            case .attrColor(let color):
                return "C\(String(format: "%x%x%x", Int(color.redComponent * 255), Int(color.greenComponent * 255), Int(color.blueComponent * 255)))"
            case .attrRound(let round):
                return "R\(round ? 1 : 0)"
            }
        }
    }
}

extension UUID: BinaryCodable {}
extension CausalTree: BinaryCodable {}
extension SiteIndex: BinaryCodable {}
extension SiteIndex.SiteIndexKey: BinaryCodable {}
extension Weave: BinaryCodable {}
extension Weave.Atom: BinaryCodable {}
extension AtomId: BinaryCodable {}
extension AtomType: BinaryCodable {}

// TODO: move this elsewhere
protocol CausalTreeAtomPrintable
{
    var atomDescription: String { get }
}
