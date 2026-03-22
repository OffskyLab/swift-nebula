//
//  NMTServerBuilder.swift
//
//
//  Created by Grady Zhuo on 2026/3/23.
//

import Foundation
import NIO

public struct NMTServerBuilder<Target: NMTServerTarget>: Sendable {
    public let target: Target

    public func bind(
        on address: SocketAddress,
        eventLoopGroup: MultiThreadedEventLoopGroup? = nil
    ) async throws -> NMTServer<Target> {
        try await NMTServer.bind(on: address, target: target, eventLoopGroup: eventLoopGroup)
    }
}
