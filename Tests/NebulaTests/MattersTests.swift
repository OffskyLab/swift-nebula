// Tests/NebulaTests/MattersTests.swift

import Testing
import Foundation
import NMTP
import MessagePacker
@testable import Nebula

@Suite("Nebula *Matter types")
struct MattersTests {

    @Test("FindMatter conforms to MatterBehavior with correct metadata")
    func findMatterMetadata() {
        #expect(FindMatter.typeID == 0x0003)
        #expect(FindMatter.type == .query)
    }

    @Test("RegisterMatter is a command")
    func registerMatterIsCommand() {
        #expect(RegisterMatter.type == .command)
    }

    @Test("CallMatter is a command")
    func callMatterIsCommand() {
        #expect(CallMatter.type == .command)
    }

    @Test("CloneMatter is a query")
    func cloneMatterIsQuery() {
        #expect(CloneMatter.type == .query)
    }

    @Test("FindMatter round-trips MessagePack")
    func findMatterCodable() throws {
        let original = FindMatter(namespace: "test.echo")
        let data = try MessagePackEncoder().encode(original)
        let decoded = try MessagePackDecoder().decode(FindMatter.self, from: data)
        #expect(decoded.namespace == "test.echo")
    }

    @Test("FindMatter factory produces correct namespace")
    func findMatterFactory() {
        let m = FindMatter.find(namespace: "production.ml")
        #expect(m.namespace == "production.ml")
    }
}
