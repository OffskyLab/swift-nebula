// Sources/Nebula/NMT/Argument.swift

import Foundation
import MessagePacker

/// A named, opaque-encoded RPC argument.
///
/// The `data` field carries a MessagePack-encoded value.
/// Callers use `wrap(key:value:)` and `unwrap(as:)` to encode/decode.
public struct Argument: Sendable {
    public let key: String
    public let data: Data

    public init(key: String, data: Data) {
        self.key = key
        self.data = data
    }
}

// MARK: - Encoding helpers

extension Argument {

    public static func wrap<T: Encodable>(key: String, value: T) throws -> Argument {
        let data = try MessagePackEncoder().encode(value)
        return Argument(key: key, data: data)
    }

    public func unwrap<T: Decodable>(as type: T.Type) throws -> T {
        try MessagePackDecoder().decode(type, from: data)
    }
}

// MARK: - Array helpers

/// Wire-safe encoded argument (key + raw Data). Used in Matter bodies.
public struct EncodedArgument: Codable, Sendable {
    public var key: String
    public var value: Data

    public init(key: String, value: Data) {
        self.key = key
        self.value = value
    }
}

extension Array where Element == Argument {

    public func toEncoded() -> [EncodedArgument] {
        map { EncodedArgument(key: $0.key, value: $0.data) }
    }
}

extension Array where Element == EncodedArgument {

    public func toArguments() -> [Argument] {
        map { Argument(key: $0.key, data: $0.value) }
    }
}
