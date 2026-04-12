// Sources/Nebula/NMT/NMTDispatcher.swift

import Foundation
import NIO
import NMTP
import MessagePacker
import Synchronization

/// Table-driven `NMTHandler` that dispatches incoming Matter by `MatterPayload.typeID`.
///
/// Register handlers before binding the server:
/// ```swift
/// let dispatcher = NMTDispatcher()
/// await galaxy.register(on: dispatcher)
/// let server = try await Nebula.bind(dispatcher, on: address, tls: tls)
/// ```
public final class NMTDispatcher: NMTHandler, Sendable {

    // Each entry: receives (original Matter, raw body Data, Channel), returns optional reply Matter.
    private typealias Entry = @Sendable (Matter, Data, Channel) async throws -> Matter?

    private let table: TableBox

    public init() {
        self.table = TableBox()
    }

    // MARK: - Registration

    /// Register a handler for `A` that returns an `Encodable` reply.
    public func register<A: MatterBehavior, R: Encodable>(
        _ type: A.Type,
        handler: @escaping @Sendable (A, Channel) async throws -> R
    ) {
        let entry: Entry = { matter, body, channel in
            let action = try MessagePackDecoder().decode(A.self, from: body)
            let replyBody = try await handler(action, channel)
            return try matter.makeReply(body: replyBody)
        }
        table.set(key: A.typeID, entry: entry)
    }

    /// Register a handler for `A` that produces no reply (fire-and-forget).
    public func register<A: MatterBehavior>(
        _ type: A.Type,
        handler: @escaping @Sendable (A, Channel) async throws -> Void
    ) {
        let entry: Entry = { _, body, channel in
            let action = try MessagePackDecoder().decode(A.self, from: body)
            try await handler(action, channel)
            return nil
        }
        table.set(key: A.typeID, entry: entry)
    }

    // MARK: - NMTHandler

    public func handle(matter: Matter, channel: Channel) async throws -> Matter? {
        guard let payload = try? matter.decodePayload(),
              let entry = table.get(key: payload.typeID) else {
            return nil
        }
        return try await entry(matter, payload.body, channel)
    }
}

// MARK: - Thread-safe dispatch table

/// Sendable wrapper around the dispatch table dictionary.
private final class TableBox: Sendable {
    typealias Entry = @Sendable (Matter, Data, Channel) async throws -> Matter?
    private let lock = Mutex<[UInt16: Entry]>([:])

    func set(key: UInt16, entry: @escaping Entry) {
        lock.withLock { $0[key] = entry }
    }

    func get(key: UInt16) -> Entry? {
        lock.withLock { $0[key] }
    }
}
