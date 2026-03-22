import Foundation
import Nebula
import NebulaServiceLifecycle
import NIO
import ServiceLifecycle
import Logging

// MARK: - Discovery

let galaxyAddress = try SocketAddress(ipAddress: "::1", port: 9000)
await Nebula.discovery.register("production", at: galaxyAddress)

// MARK: - Galaxy

let galaxy = StandardGalaxy(name: "nebula")
let galaxyServer = try await Nebula.server(with: galaxy).bind(on: galaxyAddress)

// MARK: - Stellar

let stellar = makeStellar()  // defined in StellarSetup.swift
let stellarAddress = try SocketAddress(ipAddress: "::1", port: 7000)
let stellarServer = try await Nebula.server(with: stellar).bind(on: stellarAddress)

// Register with Galaxy — LoadBalanceAmas is created automatically
try await galaxy.register(namespace: stellar.namespace, stellarEndpoint: stellarAddress)

// MARK: - Run all services

let logger = Logger(label: "nebula-demo")

let serviceGroup = ServiceGroup(
    services: [
        galaxyServer,
        stellarServer,
        DemoTask(),
    ],
    gracefulShutdownSignals: [.sigterm, .sigint],
    logger: logger
)

print("Starting Nebula demo (Ctrl+C to stop)...")
try await serviceGroup.run()
