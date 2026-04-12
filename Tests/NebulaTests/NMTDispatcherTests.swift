// Tests/NebulaTests/NMTDispatcherTests.swift

import Testing
import Foundation
import NIO
import NMTP
@testable import Nebula

@Suite("NMTDispatcher")
struct NMTDispatcherTests {

    private func embeddedChannel() -> Channel { EmbeddedChannel() }

    @Test("Dispatches to registered handler and returns encoded reply")
    func dispatchesToHandler() async throws {
        let dispatcher = NMTDispatcher()
        nonisolated(unsafe) var receivedNamespace: String?

        dispatcher.register(FindMatter.self) { matter, _ in
            receivedNamespace = matter.namespace
            return FindReplyMatter(stellarHost: "127.0.0.1", stellarPort: 1234)
        }

        let matter = try Matter.make(FindMatter(namespace: "test.echo"))
        let reply = try await dispatcher.handle(matter: matter, channel: embeddedChannel())

        #expect(receivedNamespace == "test.echo")
        let decoded = try #require(reply).decode(FindReplyMatter.self)
        #expect(decoded.stellarHost == "127.0.0.1")
        #expect(decoded.stellarPort == 1234)
        #expect(reply?.matterID == matter.matterID)
        #expect(reply?.type == .reply)
    }

    @Test("Returns nil for unregistered typeID")
    func returnsNilForUnregistered() async throws {
        let dispatcher = NMTDispatcher()
        let matter = Matter.make(type: .command, typeID: 0xFFFF)
        let reply = try await dispatcher.handle(matter: matter, channel: embeddedChannel())
        #expect(reply == nil)
    }

    @Test("Void handler sends no reply")
    func voidHandlerSendsNoReply() async throws {
        let dispatcher = NMTDispatcher()
        nonisolated(unsafe) var ackReceived = false

        dispatcher.register(AckMatter.self) { _, _ in
            ackReceived = true
        }

        let matter = try Matter.make(AckMatter(matterID: UUID().uuidString))
        let reply = try await dispatcher.handle(matter: matter, channel: embeddedChannel())

        #expect(ackReceived == true)
        #expect(reply == nil)
    }

    @Test("Multiple handlers registered for different typeIDs")
    func multipleHandlers() async throws {
        let dispatcher = NMTDispatcher()

        dispatcher.register(FindMatter.self) { matter, _ in
            FindReplyMatter(stellarHost: "stellar.host", stellarPort: 1000)
        }
        dispatcher.register(CloneMatter.self) { _, _ in
            CloneReplyMatter(identifier: "abc", name: "test-node", category: 1)
        }

        let findReply = try await dispatcher.handle(
            matter: try Matter.make(FindMatter(namespace: "ns")),
            channel: embeddedChannel()
        )
        let cloneReply = try await dispatcher.handle(
            matter: try Matter.make(CloneMatter()),
            channel: embeddedChannel()
        )

        let findBody = try #require(findReply).decode(FindReplyMatter.self)
        #expect(findBody.stellarHost == "stellar.host")

        let cloneBody = try #require(cloneReply).decode(CloneReplyMatter.self)
        #expect(cloneBody.name == "test-node")
    }

    @Test("Returns nil for Matter with no payload")
    func returnsNilForEmptyPayload() async throws {
        let dispatcher = NMTDispatcher()
        let matter = Matter(type: .command, payload: Data())
        let reply = try await dispatcher.handle(matter: matter, channel: embeddedChannel())
        #expect(reply == nil)
    }
}
