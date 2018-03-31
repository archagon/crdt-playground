//
//  CausalTreeTypeSetup.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-9-25.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import AppKit
//import CRDTFramework_OSX

typealias CausalTreeStandardUUIDT = UUID
typealias CausalTreeTextT = CausalTreeString
typealias CausalTreeBezierT = CausalTree<UUID, DrawDatum>

enum DrawDatum: CausalTreeValueT, CRDTValueReference {
    struct ColorTuple: Codable {
        let r: UInt8
        let g: UInt8
        let b: UInt8
        let a: UInt8

        var rf: CGFloat { return CGFloat(r) / 255.0 }
        var gf: CGFloat { return CGFloat(g) / 255.0 }
        var bf: CGFloat { return CGFloat(b) / 255.0 }
        var af: CGFloat { return CGFloat(a) / 255.0 }

        init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
            self.r = UInt8(r * 255)
            self.g = UInt8(g * 255)
            self.b = UInt8(b * 255)
            self.a = UInt8(a * 255)
        }

        init(color: NSColor) {
            self.init(r: color.redComponent,
                      g: color.greenComponent,
                      b: color.blueComponent,
                      a: color.alphaComponent)
        }
    }

    case null //no-op for grouping other atoms
    case shape
    case point(pos: NSPoint)
    case pointSentinelStart
    case pointSentinelEnd
    case opTranslate(delta: NSPoint, ref: AtomId)
    case attrColor(ColorTuple)
    case attrRound(Bool)
    case delete
    // TODO: reserve space!

    // AB: maybe this is a stupid way to assign identifiers to our cases, but hey, it works
    enum Id: Int, CodingKey {
        case meta //unrelated to above, used for coding hijinks
        case null
        case shape
        case point
        case pointSentinelStart
        case pointSentinelEnd
        case opTranslate
        case attrColor
        case attrRound
        case delete
    }
    var id: Id {
        switch self {
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
        case .delete:
            return .delete
        }
    }

    var point: Bool {
        switch self {
        case .point, .pointSentinelStart, .pointSentinelEnd:
            return true
        default:
            return false
        }
    }

    var pointSentinel: Bool {
        switch self {
        case .pointSentinelStart, .pointSentinelEnd:
            return true
        default:
            return false
        }
    }

    var operation: Bool {
        if case .opTranslate(_) = self {
            return true
        }

        return false
    }

    var attribute: Bool {
        switch self {
        case .attrColor, .attrRound:
            return true
        default:
            return false
        }
    }

    var childless: Bool {
        switch self {
        case .delete:
            return true
        default:
            return false
        }
    }

    var priority: UInt8 {
        switch self {
        case .shape, .point, .pointSentinelStart, .pointSentinelEnd:
            return 0
        default:
            return 1
    }

    var reference: AtomId {
        switch self {
        case .opTranslate(_, let ref):
            return ref
        default:
            return .null
        }
    }

    mutating func remapIndices(_ map: [SiteId : SiteId]) {
        switch self {
        case let .opTranslate(delta, ref):
            if let newSite = map[ref.site] {
                self = .opTranslate(delta: delta, ref: AtomId(site: newSite, index: ref.index))
            }
        default:
            break
        }
    }

    init() {
        self = .null
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Id.self)

        // get id
        var meta = try container.nestedUnkeyedContainer(forKey: .meta)
        let metaVal = try meta.decode(Int.self)
        let type = Id(rawValue: metaVal) ?? .meta

        // get associated type
        switch type {
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
            let pair = try container.decode(Pair<NSPoint, AtomId>.self, forKey: .opTranslate)
            self = .opTranslate(delta: pair.o1, ref: pair.o2)
        case .attrColor:
            let colorStruct = try container.decode(ColorTuple.self, forKey: .attrColor)
            //let color = NSColor(red: colorStruct.r, green: colorStruct.g, blue: colorStruct.b, alpha: colorStruct.a)
            self = .attrColor(colorStruct)
        case .attrRound:
            let round = try container.decode(Bool.self, forKey: .attrRound)
            self = .attrRound(round)
        case .delete:
            self = .delete
        case .meta:
            throw DecodingError.dataCorruptedError(in: meta, debugDescription: "out of date: missing datum with id \(metaVal)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Id.self)

        // store id
        var meta = container.nestedUnkeyedContainer(forKey: .meta)
        try meta.encode(id.rawValue)

        // store associated data
        switch self {
        case let .point(pos):
            try container.encode(pos, forKey: .point)
        case let .opTranslate(delta, ref):
            try container.encode(Pair<NSPoint, AtomId>(o1: delta, o2: ref), forKey: .opTranslate)
        case let .attrColor(color):
            try container.encode(color, forKey: .attrColor)
        case let .attrRound(round):
            try container.encode(round, forKey: .attrRound)
        default:
            break
        }
    }
}

extension DrawDatum: CRDTValueAtomPrintable {
    public var atomDescription: String {
        switch self {
        case .null:
            return "N"
        case .shape:
            return "S"
        case .point:
            return "P"
        case .pointSentinelStart:
            return "P0"
        case .pointSentinelEnd:
            return "P1"
        case .opTranslate:
            return "OT"
        case .attrColor:
            return "AC"
        case .attrRound:
            return "AR"
        case  .delete:
            return "X"
        }
    }
}

extension UUID: BinaryCodable {}
extension NSPoint: BinaryCodable {}
extension CGFloat: BinaryCodable {}
extension CRDTCounter: BinaryCodable {}
extension CausalTree: BinaryCodable {}
extension SiteIndex: BinaryCodable {}
extension SiteIndex.Key: BinaryCodable {}
extension Weave: BinaryCodable {}
extension Atom: BinaryCodable {}
extension AtomId: BinaryCodable {}
extension DrawDatum: BinaryCodable {}
extension DrawDatum.ColorTuple: BinaryCodable {}
extension StringCharacterAtom: BinaryCodable {}
extension Pair: BinaryCodable {}
