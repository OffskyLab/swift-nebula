//
//  NMTClient.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation
import NIO

public final class NMTClient<Target: NMTClientTarget>: @unchecked Sendable {
    public let targetAddress: SocketAddress
    public let target: Target

    private let channel: Channel
    private let pendingRequests: PendingRequests

    internal init(
        targetAddress: SocketAddress,
        target: Target,
        channel: Channel,
        pendingRequests: PendingRequests
    ) {
        self.targetAddress = targetAddress
        self.target = target
        self.channel = channel
        self.pendingRequests = pendingRequests
    }
}

// MARK: - Connect

extension NMTClient {

    public static func connect(
        to address: SocketAddress,
        as target: Target,
        eventLoopGroup: MultiThreadedEventLoopGroup? = nil
    ) async throws -> NMTClient<Target> {
        let elg = eventLoopGroup ?? MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        let pendingRequests = PendingRequests()
        let inboundHandler = NMTClientInboundHandler(pendingRequests: pendingRequests)

        let channel = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Channel, Error>) in
            ClientBootstrap(group: elg)
                .channelOption(.socketOption(.so_reuseaddr), value: 1)
                .channelInitializer { channel in
                    channel.pipeline.addHandlers([
                        ByteToMessageHandler(MatterDecoder()),
                        MessageToByteHandler(MatterEncoder()),
                        inboundHandler,
                    ])
                }
                .connect(to: address)
                .whenComplete { result in
                    continuation.resume(with: result)
                }
        }

        return NMTClient(
            targetAddress: address,
            target: target,
            channel: channel,
            pendingRequests: pendingRequests
        )
    }
}

// MARK: - Send

extension NMTClient {

    /// Fire-and-forget: send a Matter without waiting for a reply.
    public func fire(envelope: Matter) {
        channel.writeAndFlush(envelope, promise: nil)
    }

    /// Send a Matter and wait for a reply (matched by messageID).
    public func request(envelope: Matter) async throws -> Matter {
        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests.register(id: envelope.messageID, continuation: continuation)
            channel.writeAndFlush(envelope, promise: nil)
        }
    }

    public func close() async throws {
        try await channel.close().get()
    }
}

// MARK: - PendingRequests

final class PendingRequests: @unchecked Sendable {
    private var waiting: [UUID: CheckedContinuation<Matter, Error>] = [:]
    private let lock = NSLock()

    func register(id: UUID, continuation: CheckedContinuation<Matter, Error>) {
        lock.lock()
        waiting[id] = continuation
        lock.unlock()
    }

    func fulfill(_ envelope: Matter) {
        lock.lock()
        let continuation = waiting.removeValue(forKey: envelope.messageID)
        lock.unlock()
        continuation?.resume(returning: envelope)
    }

    func fail(id: UUID, error: Error) {
        lock.lock()
        let continuation = waiting.removeValue(forKey: id)
        lock.unlock()
        continuation?.resume(throwing: error)
    }
}

// MARK: - NMTClientInboundHandler

private final class NMTClientInboundHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = Matter

    private let pendingRequests: PendingRequests

    init(pendingRequests: PendingRequests) {
        self.pendingRequests = pendingRequests
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let envelope = unwrapInboundIn(data)
        pendingRequests.fulfill(envelope)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}
