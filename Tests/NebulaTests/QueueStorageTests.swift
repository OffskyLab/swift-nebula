// Tests/NebulaTests/QueueStorageTests.swift
import Testing
import Foundation
@testable import Nebula

@Suite("InMemoryQueueStorage")
struct QueueStorageTests {

    private func makeMessage(id: UUID = UUID()) -> QueuedMatter {
        QueuedMatter(id: id, namespace: "test.ns", service: "svc",
                     method: "method", arguments: [])
    }

    @Test func append_storesMessage() async {
        let storage = InMemoryQueueStorage()
        let msg = makeMessage()
        await storage.append(msg)
        let messages = await storage.pendingMessages()
        #expect(messages.count == 1)
        #expect(messages[0].id == msg.id)
    }

    @Test func append_duplicateID_overwrites() async {
        let storage = InMemoryQueueStorage()
        let id = UUID()
        let msg1 = makeMessage(id: id)
        let msg2 = QueuedMatter(id: id, namespace: "other.ns", service: "svc2",
                                method: "m2", arguments: [])
        await storage.append(msg1)
        await storage.append(msg2)
        let messages = await storage.pendingMessages()
        #expect(messages.count == 1)
        #expect(messages[0].namespace == "other.ns")
    }

    @Test func remove_deletesMessage() async {
        let storage = InMemoryQueueStorage()
        let msg = makeMessage()
        await storage.append(msg)
        await storage.remove(id: msg.id)
        let messages = await storage.pendingMessages()
        #expect(messages.isEmpty)
    }

    @Test func remove_nonexistentID_noError() async {
        let storage = InMemoryQueueStorage()
        await storage.remove(id: UUID())  // must not crash
    }

    @Test func pendingMessages_preservesInsertionOrder() async {
        let storage = InMemoryQueueStorage()
        let ids = [UUID(), UUID(), UUID()]
        for id in ids {
            await storage.append(makeMessage(id: id))
        }
        let messages = await storage.pendingMessages()
        #expect(messages.map(\.id) == ids)
    }
}
