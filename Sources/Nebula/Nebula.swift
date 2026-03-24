//
//  Nebula.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation
import NIO

public final class Nebula: Sendable {

    public static let standard: Nebula = Nebula()

    private init() {}
}

// MARK: - Server Helpers

extension Nebula {

    public static func server<Target: NMTServerTarget>(
        with target: Target
    ) -> NMTServerBuilder<Target> {
        NMTServerBuilder(target: target)
    }
}

// MARK: - Client Helpers

extension Nebula {

    /// Create a `RoguePlanet` connected to a Galaxy via a connection URI.
    ///
    /// URI format: `nmtp://host:port/galaxy/amas/stellar`
    /// - host:port = Galaxy address
    /// - path segments = namespace (joined with `.`)
    public static func planet(
        connecting uriString: String,
        service: String,
        eventLoopGroup: MultiThreadedEventLoopGroup? = nil
    ) async throws -> RoguePlanet {
        let uri = try NebulaURI(uriString)

        let galaxyAddress = try SocketAddress.makeAddressResolvingHost(
            uri.galaxyHost, port: uri.galaxyPort
        )
        let client = try await NMTClient.connect(
            to: galaxyAddress,
            as: .galaxy,
            eventLoopGroup: eventLoopGroup
        )
        return .init(galaxyClient: client, identifier: .init(), namespace: uri.namespace, service: service)
    }
}
