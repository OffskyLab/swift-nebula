# Design Spec: mTLS Support for swift-nebula

**Date:** 2026-04-07
**Status:** Approved
**Repos:** `swift-nmtp` (transport abstraction), `swift-nebula` (TLS implementation)

---

## Problem

All NMT communication is currently plaintext TCP. This blocks deployment in any zero-trust, regulated, or cloud-edge environment. Adding mTLS is a P0 requirement for production readiness.

---

## Goals

- Mutual TLS (mTLS) — both server and client present certificates
- Shared CA + independent identity cert per node (standard mTLS model)
- Two config backends: file-based and in-memory/programmatic
- Hot reload: cert rotation without restarting the service
- Backward compatible: TLS is opt-in; `nil` = no TLS (existing behaviour unchanged)

## Non-Goals

- Automatic cert rotation scheduling (callers invoke `reload()` themselves)
- OCSP / CRL revocation checking (NIOSSL supports it; deferred to a later release)
- Per-connection cert selection (SNI-based multi-cert server)

---

## Architecture: Dependency Inversion

```
swift-nmtp          defines:   TLSContext (protocol)  ← abstraction
swift-nebula        provides:  NebulaTLSContext        ← concrete implementation
```

`swift-nmtp` (low-level transport) depends only on the `TLSContext` abstraction.
`swift-nebula` (high-level) depends on `swift-nio-ssl` and implements `TLSContext`.
Neither direction violates DIP: the concrete implementation flows inward, not outward.

---

## Section 1 — swift-nmtp: TLSContext Protocol

### New file: `Sources/NMTP/TLS/TLSContext.swift`

```swift
/// Abstraction over a TLS implementation. swift-nmtp depends only on this protocol —
/// it does not import swift-nio-ssl or any other TLS library.
public protocol TLSContext: Sendable {
    /// Returns a ChannelHandler to insert at the head of a server pipeline.
    func makeServerHandler() async throws -> any ChannelHandler
    /// Returns a ChannelHandler to insert at the head of a client pipeline.
    /// - Parameter serverHostname: SNI hostname sent during handshake. nil = no SNI.
    func makeClientHandler(serverHostname: String?) async throws -> any ChannelHandler
}
```

### Modified: `NMTServer.bind` and `NMTClient.connect`

```swift
// NMTServer
public static func bind(
    on address: SocketAddress,
    handler: any NMTHandler,
    tls: (any TLSContext)? = nil,
    eventLoopGroup: MultiThreadedEventLoopGroup? = nil
) async throws -> NMTServer

// NMTClient
public static func connect(
    to address: SocketAddress,
    tls: (any TLSContext)? = nil,
    eventLoopGroup: MultiThreadedEventLoopGroup? = nil
) async throws -> NMTClient
```

### Pipeline insertion order

```
[TLSHandler]  ←  always outermost when TLS is active
[MatterDecoder / MatterEncoder]
[NMTServerInboundHandler / NMTClientInboundHandler]
```

When `tls == nil`, the pipeline is identical to today's behaviour.

---

## Section 2 — swift-nebula: NebulaTLSContext

### New dependency: `swift-nio-ssl`

Add to `swift-nebula/Package.swift`:

```swift
.package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.26.0"),
```

Add to the `Nebula` target:

```swift
.product(name: "NIOSSL", package: "swift-nio-ssl"),
```

### New files under `Sources/Nebula/TLS/`

#### `TLSConfiguration.swift`

```swift
/// Shared CA + per-node identity cert configuration.
public struct NebulaTLSConfiguration: Sendable {
    public let ca: CACertificateSource
    public let identity: IdentitySource

    public init(ca: CACertificateSource, identity: IdentitySource) {
        self.ca = ca
        self.identity = identity
    }
}

public enum CACertificateSource: Sendable {
    case file(path: String)
    case pem(Data)
}

public enum IdentitySource: Sendable {
    /// Paths to a PEM-encoded certificate and unencrypted private key file.
    case files(cert: String, key: String)
    /// In-memory PEM-encoded certificate and private key bytes.
    case pem(cert: Data, key: Data)
}
```

#### `NebulaTLSContext.swift`

```swift
import NIOSSL

/// Concrete TLSContext implementation using swift-nio-ssl.
///
/// Implements the TLSContext protocol (defined in swift-nmtp) and satisfies DIP:
/// swift-nmtp knows nothing about NIOSSL; swift-nebula owns the dependency.
///
/// Hot reload: call reload(configuration:) to rotate certs.
/// Already-established connections are not interrupted; only new connections
/// use the updated certificate. This matches nginx / Envoy cert rotation behaviour.
public actor NebulaTLSContext: TLSContext {

    private var configuration: NebulaTLSConfiguration
    private var sslContext: NIOSSLContext

    public init(configuration: NebulaTLSConfiguration) throws {
        self.configuration = configuration
        self.sslContext = try NebulaTLSContext.buildSSLContext(from: configuration)
    }

    /// Rotate the certificate without restarting the service.
    /// New connections immediately use the updated cert; existing connections finish normally.
    public func reload(configuration: NebulaTLSConfiguration) throws {
        self.configuration = configuration
        self.sslContext = try NebulaTLSContext.buildSSLContext(from: configuration)
    }

    // MARK: - TLSContext

    /// Returns a server-side TLS handler using the current sslContext snapshot.
    /// Must be called from within actor isolation (i.e. from the actor itself or via await).
    public func makeServerHandler() async throws -> any ChannelHandler {
        try NIOSSLServerHandler(context: sslContext)
    }

    /// Returns a client-side TLS handler using the current sslContext snapshot.
    public func makeClientHandler(serverHostname: String?) async throws -> any ChannelHandler {
        try NIOSSLClientHandler(context: sslContext, serverHostname: serverHostname)
    }

    // MARK: - Private

    private static func buildSSLContext(from config: NebulaTLSConfiguration) throws -> NIOSSLContext {
        var tlsConfig = TLSConfiguration.makeServerConfiguration(
            certificateChain: try loadCerts(from: config.identity),
            privateKey: try loadKey(from: config.identity)
        )
        tlsConfig.trustRoots = .certificates(try loadCA(from: config.ca))
        tlsConfig.clientCertificateVerification = .requireAny   // enforce mTLS
        return try NIOSSLContext(configuration: tlsConfig)
    }

    private static func loadCerts(from source: IdentitySource) throws -> [NIOSSLCertificateSource] { ... }
    private static func loadKey(from source: IdentitySource) throws -> NIOSSLPrivateKeySource { ... }
    private static func loadCA(from source: CACertificateSource) throws -> [NIOSSLCertificate] { ... }
}
```

### Updated `Nebula.swift` facade

```swift
public static func bind(
    _ handler: some NMTServerTarget,
    on address: SocketAddress,
    tls: NebulaTLSContext? = nil,
    eventLoopGroup: MultiThreadedEventLoopGroup? = nil
) async throws -> NMTServer {
    try await NMTServer.bind(on: address, handler: handler, tls: tls, eventLoopGroup: eventLoopGroup)
}
```

---

## Section 3 — Client-Side mTLS

### GalaxyClient / IngressClient

```swift
extension GalaxyClient {
    public static func connect(
        to address: SocketAddress,
        tls: NebulaTLSContext? = nil
    ) async throws -> GalaxyClient {
        let client = try await NMTClient.connect(to: address, tls: tls)
        return GalaxyClient(client: client)
    }
}

extension IngressClient {
    public static func connect(
        to address: SocketAddress,
        tls: NebulaTLSContext? = nil
    ) async throws -> IngressClient { ... }
}
```

### StandardIngress + StandardGalaxy

Both actors gain an optional `tls: NebulaTLSContext?` at init time, which is forwarded when building outbound `GalaxyClient` connections:

```swift
public actor StandardIngress {
    private let tls: NebulaTLSContext?

    public init(name: String = "ingress", tls: NebulaTLSContext? = nil, identifier: UUID = UUID()) {
        self.tls = tls
        ...
    }

    private func galaxyClient(for name: String, at address: SocketAddress) async throws -> GalaxyClient {
        let client = try await GalaxyClient.connect(to: address, tls: tls)
        ...
    }
}
```

### mTLS handshake flow

```
Stellar (server cert signed by CA)
    ←→  Planet / Comet / Satellite (client cert signed by same CA)

1. Server presents its cert → client verifies against CA
2. Client presents its cert → server verifies against CA
3. Handshake complete → NMT matter exchange begins
```

Any node presenting a cert not signed by the shared CA is rejected at the TLS layer before any application code runs.

---

## Section 4 — Testing Strategy

### swift-nmtp (unit)

| Test | What it checks |
|------|---------------|
| `TLSContext_nilMeansNoHandler` | `bind(tls: nil)` pipeline has no TLS handler |
| `TLSContext_serverHandlerInserted` | mock `TLSContext` → handler appears at pipeline head |
| `TLSContext_clientHandlerInserted` | same for client bootstrap |

### swift-nebula (integration)

| Test | What it checks |
|------|---------------|
| `NebulaTLSContext_fileInit` | loads certs from file paths without throwing |
| `NebulaTLSContext_inMemoryInit` | loads certs from `Data` without throwing |
| `NebulaTLSContext_reload` | after `reload()`, `sslContext` reference changes |
| `mTLS_handshake_succeeds` | server + client with same CA complete handshake |
| `mTLS_rejectsUnknownClientCert` | client cert from different CA → connection refused |
| `mTLS_existingConnectionSurvivesReload` | open connection stays alive after `reload()` |

### Test fixtures

- `Tests/Fixtures/` — self-signed CA + server cert + client cert + keys
- Generated with `openssl` script checked into the repo (`scripts/gen-test-certs.sh`)
- Explicitly marked "FOR TESTING ONLY" in file headers

---

## File Change Summary

### swift-nmtp

| Action | File |
|--------|------|
| Add | `Sources/NMTP/TLS/TLSContext.swift` |
| Modify | `Sources/NMTP/NMT/NMTServer.swift` — add `tls` param |
| Modify | `Sources/NMTP/NMT/NMTClient.swift` — add `tls` param |
| Modify | `Package.swift` — no new deps (protocol only) |

### swift-nebula

| Action | File |
|--------|------|
| Add | `Sources/Nebula/TLS/TLSConfiguration.swift` |
| Add | `Sources/Nebula/TLS/NebulaTLSContext.swift` |
| Modify | `Sources/Nebula/Nebula.swift` — add `tls` param |
| Modify | `Sources/Nebula/NMT/NMTClient+Astral.swift` — add `tls` to all clients |
| Modify | `Sources/Nebula/Ingress/StandardIngress.swift` — add `tls` init param |
| Modify | `Sources/Nebula/Astral/Galaxy/StandardGalaxy.swift` — add `tls` init param |
| Modify | `Package.swift` — add `swift-nio-ssl` dependency |
| Add | `Tests/NebulaTests/NebulaTLSContextTests.swift` |
| Add | `Tests/Fixtures/` + `scripts/gen-test-certs.sh` |
