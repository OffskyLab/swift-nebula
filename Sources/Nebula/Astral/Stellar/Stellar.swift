//
//  Stellar.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation
import NIO
import NMTP

public protocol Stellar: Astral {
    /// Fully qualified namespace in forward order, e.g. "production.ml.embedding"
    var namespace: String { get }
}

extension Stellar {
    public static var category: AstralCategory { .stellar }
}

public typealias ServiceVersion = String

/// A Stellar that hosts named Services.
///
/// Middlewares are stacked via ``use(_:)`` before the server starts.
/// Each call to `use()` wraps the current chain from the outside, so the
/// **last-registered middleware runs outermost** (first to receive each matter).
///
/// ```swift
/// let stellar = try ServiceStellar(name: "account", namespace: "production.mendesky")
/// await stellar.use(LoggingMiddleware())      // inner — runs second
/// await stellar.use(LDAPAuthMiddleware(...))  // outer — runs first
/// await stellar.add(service: accountService)
/// ```
public actor ServiceStellar: Stellar {
    public let identifier: UUID
    public let name: String
    public let namespace: String

    private var availableServices: [ServiceVersion: Service] = [:]
    private var chain: NMTMiddlewareNext?

    public init(name: String, namespace: String, identifier: UUID = UUID()) throws {
        try Self.validateName(name)
        self.identifier = identifier
        self.name = name
        self.namespace = namespace
    }

    public func use(_ middleware: any NMTMiddleware) {
        let inner: NMTMiddlewareNext = chain ?? { [unowned self] matter in
            try await self.coreDispatch(matter: matter)
        }
        chain = { matter in try await middleware.handle(matter, next: inner) }
    }

    public func add(service: Service) {
        availableServices[service.name] = service
    }
}

// MARK: - NMTServerTarget

extension ServiceStellar: NMTServerTarget {

    public func handle(matter: Matter, channel: Channel) async throws -> Matter? {
        if let chain {
            return try await chain(matter)
        }
        return try await coreDispatch(matter: matter)
    }
}

// MARK: - Core dispatch (no middleware)

extension ServiceStellar {

    private func coreDispatch(matter: Matter) async throws -> Matter? {
        switch matter.type {
        case .call:
            return try await handleCall(envelope: matter)
        case .enqueue:
            return try await handleEnqueue(envelope: matter)
        case .clone:
            return try makeCloneReply(envelope: matter)
        default:
            return nil
        }
    }

    private func handleCall(envelope: Matter) async throws -> Matter {
        let body = try envelope.decodeBody(CallBody.self)

        guard let service = availableServices[body.service] else {
            throw NebulaError.serviceNotFound(namespace: body.service)
        }

        let arguments = body.arguments.map { Argument(key: $0.key, data: $0.value) }
        let result = try await service.perform(method: body.method, with: arguments)

        let reply = CallReplyBody(result: result)
        return try envelope.reply(body: reply)
    }

    private func handleEnqueue(envelope: Matter) async throws -> Matter {
        let body = try envelope.decodeBody(EnqueueBody.self)

        guard let service = availableServices[body.service] else {
            throw NebulaError.serviceNotFound(namespace: body.service)
        }

        let arguments = body.arguments.map { Argument(key: $0.key, data: $0.value) }
        _ = try await service.perform(method: body.method, with: arguments)

        return try envelope.reply(body: AckBody(matterID: envelope.matterID.uuidString))
    }

    private func makeCloneReply(envelope: Matter) throws -> Matter {
        let reply = CloneReplyBody(
            identifier: identifier.uuidString,
            name: name,
            category: AstralCategory.stellar.rawValue
        )
        return try envelope.reply(body: reply)
    }
}
