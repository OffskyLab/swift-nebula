//
//  LocalDiscovery.swift
//
//
//  Created by Grady Zhuo on 2026/3/23.
//

import Foundation
import NIO

/// In-process Discovery implementation.
/// Stores Galaxy name → SocketAddress mappings locally.
///
/// Usage:
/// ```swift
/// await Nebula.discovery.register("production", at: SocketAddress(ipAddress: "::1", port: 9000))
/// ```
public actor LocalDiscovery: NebulaDiscovery {
    private var registry: [String: SocketAddress] = [:]

    public init() {}

    public func register(_ name: String, at address: SocketAddress) {
        registry[name] = address
    }

    public func resolve(_ name: String) throws -> SocketAddress {
        guard let address = registry[name] else {
            throw NebulaError.discoveryFailed(name: name)
        }
        return address
    }
}
