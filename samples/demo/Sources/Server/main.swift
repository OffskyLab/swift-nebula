import Foundation
import Nebula
import NebulaServiceLifecycle
import NIO
import ServiceLifecycle
import Logging

// MARK: - Galaxy

let galaxy = try StandardGalaxy(name: "production")
let galaxyServer = try await Nebula.server(with: galaxy)
    .bind(on: SocketAddress(ipAddress: "::1", port: 2240))

// MARK: - Stellar

let stellar = try makeStellar()  // defined in StellarSetup.swift
let stellarAddress = try SocketAddress(ipAddress: "::1", port: 7000)
let stellarServer = try await Nebula.server(with: stellar).bind(on: stellarAddress)

// Register with Galaxy
try await galaxy.register(namespace: stellar.namespace, stellarEndpoint: stellarAddress)

// MARK: - Run all services

let logger = Logger(label: "nebula-demo")

let serviceGroup = ServiceGroup(
    services: [
        galaxyServer,
        stellarServer,
    ],
    gracefulShutdownSignals: [.sigterm, .sigint],
    logger: logger
)

print("Starting Nebula demo (Ctrl+C to stop)...")
try await serviceGroup.run()
