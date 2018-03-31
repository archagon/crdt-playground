/// Implementations of BinaryCodable for built-in types.

import Foundation


// AB: addition
extension Dictionary: BinaryCodable {
    public func binaryEncode(to encoder: BinaryEncoder) throws {
        guard Key.self is Encodable.Type else {
            throw BinaryEncoder.Error.typeNotConformingToEncodable(Element.self)
        }
        guard Value.self is Encodable.Type else {
            throw BinaryEncoder.Error.typeNotConformingToEncodable(Element.self)
        }

        try encoder.encode(self.count)
        for pair in self {
            try (pair.key as! Encodable).encode(to: encoder)
            try (pair.value as! Encodable).encode(to: encoder)
        }
    }

    public init(fromBinary decoder: BinaryDecoder) throws {
        guard let binaryKeyElement = Key.self as? Decodable.Type else {
            throw BinaryDecoder.Error.typeNotConformingToDecodable(Element.self)
        }
        guard let binaryValueElement = Value.self as? Decodable.Type else {
            throw BinaryDecoder.Error.typeNotConformingToDecodable(Element.self)
        }

        let count = try decoder.decode(Int.self)
        self.init()
        self.reserveCapacity(count)
        for _ in 0 ..< count {
            let decodedKey = try binaryKeyElement.init(from: decoder)
            let decodedValue = try binaryValueElement.init(from: decoder)
            self[decodedKey as! Key] = (decodedValue as! Value)
        }
    }
}

extension Array: BinaryCodable {
    public func binaryEncode(to encoder: BinaryEncoder) throws {
        guard Element.self is Encodable.Type else {
            throw BinaryEncoder.Error.typeNotConformingToEncodable(Element.self)
        }

        try encoder.encode(self.count)
        for element in self {
            try (element as! Encodable).encode(to: encoder)
        }
    }

    public init(fromBinary decoder: BinaryDecoder) throws {
        guard let binaryElement = Element.self as? Decodable.Type else {
            throw BinaryDecoder.Error.typeNotConformingToDecodable(Element.self)
        }

        let count = try decoder.decode(Int.self)
        self.init()
        self.reserveCapacity(count)
        for _ in 0 ..< count {
            let decoded = try binaryElement.init(from: decoder)
            self.append(decoded as! Element)
        }
    }
}

extension String: BinaryCodable {
    public func binaryEncode(to encoder: BinaryEncoder) throws {
        try Array(self.utf8).binaryEncode(to: encoder)
    }

    public init(fromBinary decoder: BinaryDecoder) throws {
        let utf8: [UInt8] = try Array(fromBinary: decoder)
        if let str = String(bytes: utf8, encoding: .utf8) {
            self = str
        } else {
            throw BinaryDecoder.Error.invalidUTF8(utf8)
        }
    }
}
