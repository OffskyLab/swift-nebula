# Remove @unchecked Sendable — Design Spec

**Date:** 2026-04-06
**Repos affected:** `swift-nmtp`, `swift-nebula`

---

## Context

Swift 6.0 strict concurrency enforces data-race safety at compile time. `@unchecked Sendable`
bypasses this check entirely — it is equivalent to telling the compiler "trust me". In a project
built from Swift 6.0+, any occurrence of `@unchecked Sendable` in `Sources/` indicates a design
problem that should be fixed at the root, not suppressed.

Six occurrences were found across two repos:

| Repo | File | Root cause |
|------|------|-----------|
| swift-nmtp | `PendingRequests` | mutable dict + NSLock (manual sync) |
| swift-nmtp | `NMTClient` | depends on `@unchecked` `PendingRequests` |
| swift-nmtp | `NMTClientInboundHandler` | depends on `@unchecked` `PendingRequests` |
| swift-nmtp | `NMTServerInboundHandler` | all-`let` properties — `@unchecked` unnecessary |
| swift-nebula | `Service` | mutable `methods` dict on `class` |
| swift-nebula | `ServiceStellar` | mutable state on `open class` (open unnecessary) |

---

## Design Decisions

### PendingRequests → Mutex

`PendingRequests` is called synchronously from NIO's `channelRead` callback. NIO runs handlers
on its event loop thread and `channelRead` is not `async`. This makes `actor` unsuitable:

- Actor-isolated methods require `await`, which is not available in a sync function.
- Wrapping in `Task { await ... }` introduces non-deterministic scheduling on a
  request/reply path that should be FIFO.

**Fix:** Replace `NSLock` + mutable dict with `Synchronization.Mutex<[UUID: CheckedContinuation<Matter, Error>]>`.
`Mutex` is `Sendable`, synchronous, and available on Swift 6.0+ (macOS 13+ is satisfied).
`resume()` is called **outside** the lock to avoid scheduling operations while the lock is held.

### NMTClient / Inbound Handlers → Sendable (no @unchecked)

All stored properties are `let`. Once `PendingRequests` is properly `Sendable`, the compiler
can verify these types automatically. Only the annotation changes — no logic changes.

### Service → actor

`Service` has mutable `methods: [String: any Method]` with no synchronization. The existing
`perform(method:with:)` is already `async`, so there is no sync-path constraint.

- `public class Service` → `public actor Service`
- `add(method:)` variants: remove `@discardableResult -> Self` builder return.
  Callers already hold the reference; actor does not need `Self`-chaining.
- Call sites add `await` to `add()` calls.

### ServiceStellar → actor

`ServiceStellar` is `open class` but is never subclassed anywhere. In Swift's
protocol-oriented design, an abstract base class should be expressed as a protocol.
Since `ServiceStellar` is a concrete implementation with no subclasses, the correct
fix is to convert it to `actor` and drop `open`.

- `open class ServiceStellar` → `public actor ServiceStellar`
- `NMTHandler.handle(matter:channel:)` is `async throws` — actor-isolated async method
  satisfies the protocol requirement without any special annotation.
- `use(_:)` and `add(service:)`: remove `@discardableResult -> Self`, call sites add `await`.
- `chain: NMTMiddlewareNext?` and `availableServices` become actor-isolated state —
  no additional synchronization needed.

---

## Affected Files

### swift-nmtp

| File | Change |
|------|--------|
| `Sources/NMTP/NMT/PendingRequests.swift` | Replace NSLock with `Mutex`; conform to `Sendable` |
| `Sources/NMTP/NMT/NMTClient.swift` | Change `@unchecked Sendable` → `Sendable` |
| `Tests/NMTPTests/NMTIntegrationTests.swift` | Add concurrent-fulfill unit test for `PendingRequests` |

### swift-nebula

| File | Change |
|------|--------|
| `Sources/Nebula/Resource/Service.swift` | `class` → `actor`; remove `-> Self` on `add()` |
| `Sources/Nebula/Astral/Stellar/Stellar.swift` | `open class` → `actor`; remove `-> Self` on `use()`/`add()` |
| `Sources/Nebula/Auth/NMTMiddleware.swift` | Update docstring reference (no logic change) |
| `Tests/NebulaTests/NebulaTests.swift` | Add `await` to `add()`/`use()` calls; add actor concurrency tests |
| `samples/demo/Sources/Stellar/main.swift` | Add `await` to setup calls |

---

## TDD Strategy

1. **Baseline** — run existing tests; all must pass before any changes.
2. **Per-change cycle** — for each type:
   a. Write a failing test that exercises the concurrent/async behaviour.
   b. Make the change.
   c. Confirm the new test passes and existing tests still pass.
3. **New tests to write:**
   - `PendingRequests`: concurrent `register` + `fulfill` from multiple threads (data race under TSAN).
   - `Service` actor: concurrent `add` + `perform` issued from separate `Task`s.
   - `ServiceStellar` actor: existing middleware chain tests updated for `await` call sites.
4. **Final validation** — `NMTIntegrationTests` and `IngressRoutingTests` green with Thread Sanitizer enabled.

---

## Non-Goals

- No changes to the wire protocol or `Matter` types.
- No changes to `swift-nebula-client`.
- No API changes beyond adding `await` to `Service.add()` and `ServiceStellar.use()`/`add()` call sites.
