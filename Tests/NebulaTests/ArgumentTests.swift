// Tests/NebulaTests/ArgumentTests.swift

import Testing
import Foundation
@testable import Nebula

@Suite("Argument")
struct ArgumentTests {

    @Test("Argument.wrap / unwrap round-trips Int")
    func wrapUnwrapInt() throws {
        let arg = try Argument.wrap(key: "count", value: 42)
        #expect(arg.key == "count")
        let value = try arg.unwrap(as: Int.self)
        #expect(value == 42)
    }

    @Test("Argument.wrap / unwrap round-trips String")
    func wrapUnwrapString() throws {
        let arg = try Argument.wrap(key: "name", value: "nebula")
        let value = try arg.unwrap(as: String.self)
        #expect(value == "nebula")
    }

    @Test("Array<Argument>.toEncoded / toArguments round-trips")
    func arrayRoundTrip() throws {
        let args = [try Argument.wrap(key: "x", value: 1)]
        let encoded = args.toEncoded()
        let decoded = encoded.toArguments()
        #expect(decoded[0].key == "x")
        let value = try decoded[0].unwrap(as: Int.self)
        #expect(value == 1)
    }
}
