//
//  QueueStorage.swift
//
//
//  Created by Grady Zhuo on 2026/3/30.
//

import Foundation

/// Pluggable storage backend for a single queue (active or parked).
///
/// `BrokerAmas` holds two `QueueStorage` instances independently —
/// one for the active dispatch queue and one for parked messages.
/// This allows mixing backends, e.g. in-memory active + SQLite parked.
public protocol QueueStorage: Sendable {
    func append(_ message: QueuedMessage) async throws
    func remove(id: UUID) async throws
    func pendingMessages() async throws -> [QueuedMessage]
}

// MARK: - Default In-Memory Implementation

/// Non-persistent in-memory queue. Default for both active and parked slots.
public actor InMemoryQueueStorage: QueueStorage {
    private var messages: [UUID: QueuedMessage] = [:]
    private var order: [UUID] = []

    public init() {}

    public func append(_ message: QueuedMessage) {
        messages[message.id] = message
        order.append(message.id)
    }

    public func remove(id: UUID) {
        messages.removeValue(forKey: id)
        order.removeAll { $0 == id }
    }

    public func pendingMessages() -> [QueuedMessage] {
        order.compactMap { messages[$0] }
    }
}
