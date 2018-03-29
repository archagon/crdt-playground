
import CoreFoundation


/// A protocol for types which can be encoded to binary.
public protocol BinaryEncodable: Encodable {
    func binaryEncode(to encoder: BinaryEncoder) throws
}

/// Provide a default implementation which calls through to `Encodable`. This
/// allows `BinaryEncodable` to use the `Encodable` implementation generated by the
/// compiler.
public extension BinaryEncodable {
    func binaryEncode(to encoder: BinaryEncoder) throws {
        try self.encode(to: encoder)
    }
}

/// The actual binary encoder class.
public class BinaryEncoder {
    fileprivate var data: [UInt8] = []

    public init() {}
}

/// A convenience function for creating an encoder, encoding a value, and
/// extracting the resulting data.
public extension BinaryEncoder {
    static func encode(_ value: BinaryEncodable) throws -> [UInt8] {
        let encoder = BinaryEncoder()
        try value.binaryEncode(to: encoder)
        return encoder.data
    }
}

/// The error type.
public extension BinaryEncoder {
    /// All errors which `BinaryEncoder` itself can throw.
    enum Error: Swift.Error {
        /// Attempted to encode a type which is `Encodable`, but not `BinaryEncodable`. (We
        /// require `BinaryEncodable` because `BinaryEncoder` doesn't support full keyed
        /// coding functionality.)
        case typeNotConformingToBinaryEncodable(Encodable.Type)

        /// Attempted to encode a type which is not `Encodable`.
        case typeNotConformingToEncodable(Any.Type)
    }
}

/// Methods for decoding various types.
public extension BinaryEncoder {
    func encode(_ value: Bool) throws {
        try encode(value ? 1 as UInt8 : 0 as UInt8)
    }

    func encode(_ value: Float) {
        appendBytes(of: CFConvertFloatHostToSwapped(value))
    }

    func encode(_ value: Double) {
        appendBytes(of: CFConvertDoubleHostToSwapped(value))
    }

    func encode(_ encodable: Encodable) throws {
        switch encodable {
        case let v as Int:
            try encode(Int64(v))
        case let v as UInt:
            try encode(UInt64(v))
        //case let v as FixedWidthInteger:
        //    v.binaryEncode(to: self)

        case let v as Float:
            encode(v)
        case let v as Double:
            encode(v)

        case let v as Bool:
            try encode(v)

        case let binary as BinaryEncodable:
            try binary.binaryEncode(to: self)

        default:
            throw Error.typeNotConformingToBinaryEncodable(type(of: encodable))
        }
    }
}

/// Internal method for encoding raw data.
private extension BinaryEncoder {
    /// Append the raw bytes of the parameter to the encoder's data. No byte-swapping
    /// or other encoding is done.
    func appendBytes<T>(of: T) {
        var target = of
        withUnsafeBytes(of: &target) {
            data.append(contentsOf: $0)
        }
    }
}

extension BinaryEncoder: Encoder {
    public var codingPath: [CodingKey] { return [] }

    public var userInfo: [CodingUserInfoKey : Any] { return [:] }

    public func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key : CodingKey {
        return KeyedEncodingContainer(KeyedContainer<Key>(encoder: self))
    }

    public func unkeyedContainer() -> UnkeyedEncodingContainer {
        return UnkeyedContanier(encoder: self)
    }

    public func singleValueContainer() -> SingleValueEncodingContainer {
        return UnkeyedContanier(encoder: self)
    }

    private struct KeyedContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
        var encoder: BinaryEncoder

        var codingPath: [CodingKey] { return [] }

        func encode<T>(_ value: T, forKey key: Key) throws where T : Encodable {
            try encoder.encode(value)
        }

        func encodeNil(forKey key: Key) throws {}

        func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
            return encoder.container(keyedBy: keyType)
        }

        func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
            return encoder.unkeyedContainer()
        }

        func superEncoder() -> Encoder {
            return encoder
        }

        func superEncoder(forKey key: Key) -> Encoder {
            return encoder
        }
    }

    private struct UnkeyedContanier: UnkeyedEncodingContainer, SingleValueEncodingContainer {
        var encoder: BinaryEncoder

        var codingPath: [CodingKey] { return [] }

        var count: Int { return 0 }

        func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
            return encoder.container(keyedBy: keyType)
        }

        func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
            return self
        }

        func superEncoder() -> Encoder {
            return encoder
        }

        func encodeNil() throws {}

        func encode<T>(_ value: T) throws where T : Encodable {
            try encoder.encode(value)
        }
    }
}

extension BinaryEncodable where Self: FixedWidthInteger {
    public func binaryEncode(to encoder: BinaryEncoder) {
        encoder.appendBytes(of: self.bigEndian)
    }
}
extension UInt8: BinaryEncodable {}
extension Int8: BinaryEncodable {}
extension UInt16: BinaryEncodable {}
extension Int16: BinaryEncodable {}
extension UInt32: BinaryEncodable {}
extension Int32: BinaryEncodable {}
extension UInt64: BinaryEncodable {}
extension Int64: BinaryEncodable {}
