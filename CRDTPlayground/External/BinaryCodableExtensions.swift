/// Implementations of BinaryCodable for built-in types.

import Foundation


// AB: addition
extension Dictionary: BinaryCodable where Key:Codable, Value:Codable {
    public func binaryEncode(to encoder: BinaryEncoder) throws {
        try encoder.encode(self.count)
        for pair in self {
            try (pair.key).encode(to: encoder)
            try (pair.value).encode(to: encoder)
        }
    }
    
    public init(fromBinary decoder: BinaryDecoder) throws {
        let count = try decoder.decode(Int.self)
        self.init()
        self.reserveCapacity(count)
        for _ in 0 ..< count {
            let decodedKey = try Key.init(from: decoder)
            let decodedValue = try Value.init(from: decoder)
            self[decodedKey] = (decodedValue)
        }
    }
}

extension Array: BinaryCodable where Element:Codable {
    public func binaryEncode(to encoder: BinaryEncoder) throws {
        try encoder.encode(self.count)
        for element in self {
            try (element as Encodable).encode(to: encoder)
        }
    }
    
    public init(fromBinary decoder: BinaryDecoder) throws {
        let count = try decoder.decode(Int.self)
        self.init()
        self.reserveCapacity(count)
        for _ in 0 ..< count {
            let decoded = try Element.init(from: decoder)
            self.append(decoded)
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
