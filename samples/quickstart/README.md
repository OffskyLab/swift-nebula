# Nebula Quickstart

A minimal end-to-end example of the standard Nebula connection model: a Stellar actively registers its services with a Galaxy, clients discover and call it via Ingress.

## Architecture

```
Client (Planet)
  │
  │  nmtp://host:6224/production/ml/embedding
  ▼
Ingress (:6224)          ← entry point; routes find/call to the right Galaxy
  │
  │  find(namespace: "production.ml.embedding")
  ▼
Galaxy (:62200)          ← service registry; maps namespace → Stellar address
  │
  └── Cluster              ← load balancer (auto-managed by Galaxy)
        │
        ▼
      Stellar (:62300)   ← service host; registers itself on startup
        └── Service "w2v"
              └── Method "wordVector"
```

**Startup order:** Ingress → Galaxy → Stellar → Client

Each node is a separate process. Galaxy registers with Ingress on startup; Stellar registers with Galaxy on startup. The client discovers everything through Ingress at call time.

## Running

Open four terminals, all from the repo root.

### Terminal 1 — Ingress

```bash
cd samples/quickstart
swift run Ingress
```

Ingress is the entry point for all clients. Start it first.

```
Ingress listening on 0.0.0.0:6224
```

### Terminal 2 — Galaxy

```bash
cd samples/quickstart
swift run Galaxy
```

Galaxy is the service registry. It binds on port 62200 and registers itself with Ingress so clients can route namespace lookups through it.

```
Galaxy 'production' listening on 0.0.0.0:62200, registered with Ingress
```

### Terminal 3 — Stellar

```bash
cd samples/quickstart
swift run Stellar
```

Stellar hosts the actual service. It binds on port 62300 and registers its namespace (`production.ml.embedding`) with Galaxy.

```
Stellar 'Embedding' (production.ml.embedding) listening on 0.0.0.0:62300, registered with Galaxy
```

### Terminal 4 — Client

```bash
cd samples/quickstart
swift run Client
```

The client connects to Ingress, discovers the Stellar, and calls the `wordVector` method directly.

```
[Client] Connecting to Ingress 127.0.0.1:6224 ...
[Client] Connected. Calling wordVector ...
Result: [0.1, 0.2, 0.3]
```

## How it works

### Connection URI

The client uses a URI to describe the full path to the service:

```
nmtp://127.0.0.1:6224/production/ml/embedding
       └───────────┘  └────────────────────────┘
       Ingress addr    namespace (Galaxy/Cluster/Stellar)
```

### Call flow

1. `planet.call(method:arguments:)` → Planet checks its connection cache
2. Cache miss: Planet asks Ingress `find("production.ml.embedding")` → Ingress forwards to Galaxy → returns Stellar address
3. Planet connects **directly** to Stellar and caches the connection
4. Subsequent calls skip Ingress and Galaxy entirely (direct fast path)

### Environment variables

All nodes are configurable via environment variables — useful for Docker or remote deployments:

| Variable | Default | Description |
|----------|---------|-------------|
| `INGRESS_HOST` | `0.0.0.0` / `127.0.0.1` | Bind address (server) or connect address (client/Galaxy/Stellar) |
| `INGRESS_PORT` | `6224` | Ingress port |
| `GALAXY_HOST` | `0.0.0.0` | Galaxy bind address |
| `GALAXY_ADVERTISE_HOST` | same as `GALAXY_HOST` | Address Ingress uses to reach Galaxy (set to Docker service name in compose) |
| `GALAXY_PORT` | `62200` | Galaxy port |
| `STELLAR_HOST` | `0.0.0.0` | Stellar bind address |
| `STELLAR_PORT` | `62300` | Stellar port |
| `STELLAR_NAMESPACE` | `production.ml.embedding` | Namespace this Stellar serves |

## Docker Compose

To run all four nodes in containers:

```bash
cd samples/quickstart
docker compose up
```
