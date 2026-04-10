# Reliability Adoption Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adopt swift-nmtp's reliability sub-system by adding `defaultTimeout`/`timeout` parameters to all typed NMT clients and replacing `closeNow()` with `shutdown()` in test teardown.

**Architecture:** All source changes are in `NMTClient+Astral.swift` — each of the three typed clients (`IngressClient`, `GalaxyClient`, `StellarClient`) gains a stored `defaultTimeout: Duration` set at connect time; every method gains a `timeout: Duration? = nil` that falls back to `defaultTimeout`. Test teardown in `NebulaTLSContextTests.swift` is updated to use `shutdown()` for production-like lifecycle behaviour.

**Prerequisite:** swift-nmtp's reliability sub-system must be merged before running this plan (`NMTClient.request(matter:timeout:)` and `NMTServer.shutdown(gracePeriod:)` must exist).

**Tech Stack:** Swift 6, NMTP module (swift-nmtp), Swift NIO, Swift Testing framework.

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `Sources/Nebula/NMT/NMTClient+Astral.swift` | Modify | Add `defaultTimeout` storage + `timeout` parameter to all methods on all three clients |
| `Tests/NebulaTests/TypedClientTimeoutTests.swift` | **Create** | Compile test (signature check) + runtime timeout behaviour tests |
| `Tests/NebulaTests/NebulaTLSContextTests.swift` | Modify | Replace 4× `closeNow()` with `shutdown()` in defer teardown blocks |

---

## Task 1: Typed client timeout — signatures + compile test

**Files:**
- Modify: `Sources/Nebula/NMT/NMTClient+Astral.swift`
- Create: `Tests/NebulaTests/TypedClientTimeoutTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/NebulaTests/TypedClientTimeoutTests.swift`:

```swift
import Testing
import Foundation
import NIO
import NMTP
@testable import Nebula

@Suite("TypedClient timeout")
struct TypedClientTimeoutTests {

    /// Compile-only test: verifies that connect(defaultTimeout:) exists on all three clients.
    /// The connects are expected to fail at runtime (no server on port 1), so try? is used.
    @Test("connect(defaultTimeout:) parameter exists on all three clients")
    func connectAcceptsDefaultTimeout() async throws {
        let addr = try SocketAddress.makeAddressResolvingHost("127.0.0.1", port: 1)
        _ = try? await GalaxyClient.connect(to: addr, defaultTimeout: .seconds(5))
        _ = try? await IngressClient.connect(to: addr, defaultTimeout: .seconds(5))
        _ = try? await StellarClient.connect(to: addr, defaultTimeout: .seconds(5))
    }
}
```

- [ ] **Step 2: Run — expect FAIL (compile error)**

```bash
swift test --filter NebulaTests/TypedClientTimeoutTests/connectAcceptsDefaultTimeout
```

Expected: compile error — `extra argument 'defaultTimeout' in call`

- [ ] **Step 3: Replace `Sources/Nebula/NMT/NMTClient+Astral.swift`**

Replace the full file with:

```swift
//
//  NMTClient+Astral.swift
//

import Foundation
import NIO
import NMTP

// MARK: - Result Types

public struct FindResult: Sendable {
    /// Direct Stellar endpoint to connect to.
    public let stellarAddress: SocketAddress?
}

public struct UnregisterResult: Sendable {
    /// Next available Stellar endpoint after removing the dead one (nil = pool exhausted).
    public let nextAddress: SocketAddress?
}

// MARK: - IngressClient

/// A typed NMT client connected to an Ingress node.
public struct IngressClient: Sendable {
    public var address: SocketAddress { base.targetAddress }
    internal let base: NMTClient
    private let defaultTimeout: Duration

    private init(base: NMTClient, defaultTimeout: Duration) {
        self.base = base
        self.defaultTimeout = defaultTimeout
    }

    public static func connect(
        to address: SocketAddress,
        tls: NebulaTLSContext? = nil,
        defaultTimeout: Duration = .seconds(30),
        eventLoopGroup: MultiThreadedEventLoopGroup? = nil
    ) async throws -> IngressClient {
        let base = try await NMTClient.connect(to: address, tls: tls, eventLoopGroup: eventLoopGroup)
        return IngressClient(base: base, defaultTimeout: defaultTimeout)
    }

    public var pushes: AsyncStream<Matter> { base.pushes }

    public func close() async throws { try await base.close() }

    /// Find the Stellar address for a namespace via Ingress → Galaxy.
    public func find(namespace: String, timeout: Duration? = nil) async throws -> FindResult {
        let body = FindBody(namespace: namespace)
        let matter = try Matter.make(type: .find, body: body)
        let reply = try await base.request(matter: matter, timeout: timeout ?? defaultTimeout)
        let replyBody = try reply.decodeBody(FindReplyBody.self)
        let stellarAddress: SocketAddress? = try {
            guard let host = replyBody.stellarHost, let port = replyBody.stellarPort else { return nil }
            return try SocketAddress.makeAddressResolvingHost(host, port: port)
        }()
        return FindResult(stellarAddress: stellarAddress)
    }

    /// Register a Galaxy with Ingress (Galaxy name → address).
    public func registerGalaxy(
        name: String,
        address: SocketAddress,
        identifier: UUID,
        timeout: Duration? = nil
    ) async throws {
        let body = RegisterBody(
            namespace: name,
            host: address.ipAddress ?? "0.0.0.0",
            port: address.port ?? 0,
            identifier: identifier.uuidString
        )
        let matter = try Matter.make(type: .register, body: body)
        let reply = try await base.request(matter: matter, timeout: timeout ?? defaultTimeout)
        let replyBody = try reply.decodeBody(RegisterReplyBody.self)
        guard replyBody.status == "ok" else {
            throw NebulaError.fail(message: "Register Galaxy failed: \(replyBody.status)")
        }
    }

    /// Enqueue an async task via Ingress → Galaxy → BrokerCluster.
    public func enqueue(
        namespace: String,
        service: String,
        method: String,
        arguments: [Argument] = [],
        timeout: Duration? = nil
    ) async throws {
        let body = EnqueueBody(
            namespace: namespace,
            service: service,
            method: method,
            arguments: arguments.toEncoded()
        )
        let matter = try Matter.make(type: .enqueue, body: body)
        let reply = try await base.request(matter: matter, timeout: timeout ?? defaultTimeout)
        let replyBody = try reply.decodeBody(RegisterReplyBody.self)
        guard replyBody.status == "queued" else {
            throw NebulaError.fail(message: "Enqueue failed: \(replyBody.status)")
        }
    }

    /// Find the Galaxy address that manages a broker topic via Ingress.
    public func findGalaxy(topic: String, timeout: Duration? = nil) async throws -> SocketAddress? {
        let body = FindGalaxyBody(topic: topic)
        let matter = try Matter.make(type: .findGalaxy, body: body)
        let reply = try await base.request(matter: matter, timeout: timeout ?? defaultTimeout)
        let replyBody = try reply.decodeBody(FindGalaxyReplyBody.self)
        guard let host = replyBody.galaxyHost, let port = replyBody.galaxyPort else { return nil }
        return try SocketAddress.makeAddressResolvingHost(host, port: port)
    }

    /// Notify Ingress that a Stellar is dead (forwarded to Galaxy). Returns next Stellar.
    public func unregister(
        namespace: String,
        host: String,
        port: Int,
        timeout: Duration? = nil
    ) async throws -> UnregisterResult {
        let body = UnregisterBody(namespace: namespace, host: host, port: port)
        let matter = try Matter.make(type: .unregister, body: body)
        let reply = try await base.request(matter: matter, timeout: timeout ?? defaultTimeout)
        let replyBody = try reply.decodeBody(UnregisterReplyBody.self)
        let nextAddress: SocketAddress? = try {
            guard let host = replyBody.nextHost, let port = replyBody.nextPort else { return nil }
            return try SocketAddress.makeAddressResolvingHost(host, port: port)
        }()
        return UnregisterResult(nextAddress: nextAddress)
    }

    /// Fetch the remote node's identity info.
    public func clone(timeout: Duration? = nil) async throws -> CloneReplyBody {
        let matter = try Matter.make(type: .clone, body: CloneBody())
        let reply = try await base.request(matter: matter, timeout: timeout ?? defaultTimeout)
        return try reply.decodeBody(CloneReplyBody.self)
    }
}

// MARK: - GalaxyClient

/// A typed NMT client connected to a Galaxy node.
public struct GalaxyClient: Sendable {
    public var address: SocketAddress { base.targetAddress }
    internal let base: NMTClient
    private let defaultTimeout: Duration

    private init(base: NMTClient, defaultTimeout: Duration) {
        self.base = base
        self.defaultTimeout = defaultTimeout
    }

    public static func connect(
        to address: SocketAddress,
        tls: NebulaTLSContext? = nil,
        defaultTimeout: Duration = .seconds(30),
        eventLoopGroup: MultiThreadedEventLoopGroup? = nil
    ) async throws -> GalaxyClient {
        let base = try await NMTClient.connect(to: address, tls: tls, eventLoopGroup: eventLoopGroup)
        return GalaxyClient(base: base, defaultTimeout: defaultTimeout)
    }

    public var pushes: AsyncStream<Matter> { base.pushes }

    public func close() async throws { try await base.close() }

    /// Forward a raw Matter (used by Ingress for routing).
    public func request(matter: Matter, timeout: Duration? = nil) async throws -> Matter {
        try await base.request(matter: matter, timeout: timeout ?? defaultTimeout)
    }

    /// Find the Stellar address for a namespace.
    public func find(namespace: String, timeout: Duration? = nil) async throws -> FindResult {
        let body = FindBody(namespace: namespace)
        let matter = try Matter.make(type: .find, body: body)
        let reply = try await base.request(matter: matter, timeout: timeout ?? defaultTimeout)
        let replyBody = try reply.decodeBody(FindReplyBody.self)
        let stellarAddress: SocketAddress? = try {
            guard let host = replyBody.stellarHost, let port = replyBody.stellarPort else { return nil }
            return try SocketAddress.makeAddressResolvingHost(host, port: port)
        }()
        return FindResult(stellarAddress: stellarAddress)
    }

    /// Register a namespace → address mapping in Galaxy.
    public func register(
        namespace: String,
        address: SocketAddress,
        identifier: UUID,
        timeout: Duration? = nil
    ) async throws {
        let body = RegisterBody(
            namespace: namespace,
            host: address.ipAddress ?? "::1",
            port: address.port ?? 0,
            identifier: identifier.uuidString
        )
        let matter = try Matter.make(type: .register, body: body)
        let reply = try await base.request(matter: matter, timeout: timeout ?? defaultTimeout)
        let replyBody = try reply.decodeBody(RegisterReplyBody.self)
        guard replyBody.status == "ok" else {
            throw NebulaError.fail(message: "Register failed: \(replyBody.status)")
        }
    }

    /// Register a ServerAstral with Galaxy.
    public func register(
        astral: some Astral,
        listeningOn address: SocketAddress,
        timeout: Duration? = nil
    ) async throws {
        try await register(
            namespace: astral.namespace,
            address: address,
            identifier: astral.identifier,
            timeout: timeout
        )
    }

    /// Notify Galaxy that a Stellar is dead. Returns the next available Stellar address.
    public func unregister(
        namespace: String,
        host: String,
        port: Int,
        timeout: Duration? = nil
    ) async throws -> UnregisterResult {
        let body = UnregisterBody(namespace: namespace, host: host, port: port)
        let matter = try Matter.make(type: .unregister, body: body)
        let reply = try await base.request(matter: matter, timeout: timeout ?? defaultTimeout)
        let replyBody = try reply.decodeBody(UnregisterReplyBody.self)
        let nextAddress: SocketAddress? = try {
            guard let host = replyBody.nextHost, let port = replyBody.nextPort else { return nil }
            return try SocketAddress.makeAddressResolvingHost(host, port: port)
        }()
        return UnregisterResult(nextAddress: nextAddress)
    }

    /// Fetch the remote node's identity info.
    public func clone(timeout: Duration? = nil) async throws -> CloneReplyBody {
        let matter = try Matter.make(type: .clone, body: CloneBody())
        let reply = try await base.request(matter: matter, timeout: timeout ?? defaultTimeout)
        return try reply.decodeBody(CloneReplyBody.self)
    }
}

// MARK: - StellarClient

/// A typed NMT client connected to a Stellar node.
public struct StellarClient: Sendable {
    public var address: SocketAddress { base.targetAddress }
    internal let base: NMTClient
    private let defaultTimeout: Duration

    private init(base: NMTClient, defaultTimeout: Duration) {
        self.base = base
        self.defaultTimeout = defaultTimeout
    }

    public static func connect(
        to address: SocketAddress,
        defaultTimeout: Duration = .seconds(30),
        eventLoopGroup: MultiThreadedEventLoopGroup? = nil
    ) async throws -> StellarClient {
        let base = try await NMTClient.connect(to: address, eventLoopGroup: eventLoopGroup)
        return StellarClient(base: base, defaultTimeout: defaultTimeout)
    }

    public func request(matter: Matter, timeout: Duration? = nil) async throws -> Matter {
        try await base.request(matter: matter, timeout: timeout ?? defaultTimeout)
    }

    public func close() async throws { try await base.close() }

    /// Fetch the remote node's identity info.
    public func clone(timeout: Duration? = nil) async throws -> CloneReplyBody {
        let matter = try Matter.make(type: .clone, body: CloneBody())
        let reply = try await base.request(matter: matter, timeout: timeout ?? defaultTimeout)
        return try reply.decodeBody(CloneReplyBody.self)
    }
}
```

- [ ] **Step 4: Run — expect PASS**

```bash
swift test --filter NebulaTests/TypedClientTimeoutTests/connectAcceptsDefaultTimeout
```

Expected: Test Suite `TypedClientTimeoutTests` passed.

- [ ] **Step 5: Run full suite — expect all pass**

```bash
swift test
```

Expected: All existing tests pass. The `defaultTimeout` parameter has a default value of `.seconds(30)`, so all existing call sites compile unchanged.

- [ ] **Step 6: Commit**

```bash
git add Sources/Nebula/NMT/NMTClient+Astral.swift Tests/NebulaTests/TypedClientTimeoutTests.swift
git commit -m "[ADD] typed clients: defaultTimeout on connect(), timeout on all methods"
```

---

## Task 2: Runtime timeout behaviour tests

**Files:**
- Modify: `Tests/NebulaTests/TypedClientTimeoutTests.swift`

- [ ] **Step 1: Add `NeverReplyHandler` and two runtime tests**

Add the following before the `@Suite` declaration in `Tests/NebulaTests/TypedClientTimeoutTests.swift` (make it file-private, outside the suite struct):

```swift
/// Simulates a hung server: accepts the connection but never sends a reply.
private struct NeverReplyHandler: NMTServerTarget {
    func handle(matter: Matter, channel: any Channel) async throws -> Matter? {
        try await Task.sleep(for: .seconds(60))
        return nil
    }
}
```

Then add the following two tests inside `TypedClientTimeoutTests` (after `connectAcceptsDefaultTimeout`):

```swift
    @Test("GalaxyClient.find throws .timeout when server never replies (defaultTimeout)")
    func galaxyClientDefaultTimeoutFires() async throws {
        let elg = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        defer { try? elg.syncShutdownGracefully() }

        let server = try await NMTServer.bind(
            on: .makeAddressResolvingHost("127.0.0.1", port: 0),
            handler: NeverReplyHandler(),
            eventLoopGroup: elg
        )
        defer { Task { try? await server.shutdown() } }

        let client = try await GalaxyClient.connect(
            to: server.address,
            defaultTimeout: .milliseconds(150),
            eventLoopGroup: elg
        )
        defer { Task { try? await client.close() } }

        await #expect(throws: NMTPError.timeout) {
            try await client.find(namespace: "test.never")
        }
    }

    @Test("per-method timeout overrides defaultTimeout")
    func perMethodTimeoutOverridesDefault() async throws {
        let elg = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        defer { try? elg.syncShutdownGracefully() }

        let server = try await NMTServer.bind(
            on: .makeAddressResolvingHost("127.0.0.1", port: 0),
            handler: NeverReplyHandler(),
            eventLoopGroup: elg
        )
        defer { Task { try? await server.shutdown() } }

        // Long defaultTimeout — method-level override must win.
        let client = try await GalaxyClient.connect(
            to: server.address,
            defaultTimeout: .seconds(30),
            eventLoopGroup: elg
        )
        defer { Task { try? await client.close() } }

        await #expect(throws: NMTPError.timeout) {
            try await client.find(namespace: "test.never", timeout: .milliseconds(150))
        }
    }
```

- [ ] **Step 2: Run — expect PASS**

```bash
swift test --filter NebulaTests/TypedClientTimeoutTests
```

Expected: All three tests in `TypedClientTimeoutTests` pass.

- [ ] **Step 3: Commit**

```bash
git add Tests/NebulaTests/TypedClientTimeoutTests.swift
git commit -m "[TEST] TypedClientTimeoutTests: verify defaultTimeout and per-method timeout fire"
```

---

## Task 3: Test teardown — replace `closeNow()` with `shutdown()`

**Files:**
- Modify: `Tests/NebulaTests/NebulaTLSContextTests.swift`

- [ ] **Step 1: Replace all four `closeNow()` teardown calls**

In `Tests/NebulaTests/NebulaTLSContextTests.swift`, replace every occurrence of:

```swift
defer { server.closeNow() }
```

with:

```swift
defer { Task { try? await server.shutdown() } }
```

There are exactly 4 occurrences: lines 152, 212, 232, 256.

- [ ] **Step 2: Run full test suite — expect all pass**

```bash
swift test
```

Expected: All tests pass including all `NebulaTLSContextTests`.

- [ ] **Step 3: Commit**

```bash
git add Tests/NebulaTests/NebulaTLSContextTests.swift
git commit -m "[FIX] NebulaTLSContextTests: replace closeNow() with shutdown() for production-like teardown"
```
