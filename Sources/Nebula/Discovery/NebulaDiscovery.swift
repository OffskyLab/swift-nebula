//
//  NebulaDiscovery.swift
//
//
//  Created by Grady Zhuo on 2026/3/23.
//

import Foundation
import NIO

/// Resolves logical Galaxy names to physical SocketAddresses.
///
/// Layer 1 provides `LocalDiscovery` (in-process).
/// Layer 2 will provide cloud-backed implementations (e.g. fetching from a
/// universe registry) while still allowing `register(_:at:)` for local overrides.
public protocol NebulaDiscovery: Sendable {
    /// Register a Galaxy name → address mapping.
    func register(_ name: String, at address: SocketAddress) async

    /// Resolve a Galaxy name to its SocketAddress.
    func resolve(_ name: String) async throws -> SocketAddress
}
