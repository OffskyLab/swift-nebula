//
//  Nebula.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import NIO
import NMTP

public final class Nebula: Sendable {

    public static let standard: Nebula = Nebula()

    private init() {}
}

// MARK: - Server Helpers

extension Nebula {

    /// Bind an NMT server using a dispatcher as the handler.
    /// Pass a `NebulaTLSContext` to enable mTLS on all incoming connections.
    public static func bind(
        _ dispatcher: NMTDispatcher,
        on address: SocketAddress,
        tls: NebulaTLSContext? = nil,
        eventLoopGroup: MultiThreadedEventLoopGroup? = nil
    ) async throws -> NMTServer {
        try await NMTServer.bind(on: address, handler: dispatcher, tls: tls, eventLoopGroup: eventLoopGroup)
    }
}
