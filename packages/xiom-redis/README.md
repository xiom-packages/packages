# xiom-redis — Redis Client

hiredis FFI bindings for XIOM. Full Redis client with key-value ops, pub/sub, lists, hashes, and pipelining.

## Install

```powershell
xiom pkg install xiom-redis
```

## Requirements

- **hiredis** (Redis C client library)
  - Linux: `apt install libhiredis-dev`
  - macOS: `brew install hiredis`
  - Windows: vcpkg (`vcpkg install hiredis`)

## Link Flags

```
-l hiredis
```

## Quick Start

```xiom
use xiom.redis;

fn main() -> Int {
  let conn = redis_connect("localhost", 6379)?;

  redis_set(&conn, "greeting", "Hello, XIOM!")?;
  let val = redis_get(&conn, "greeting")?;

  disconnect(conn);
  return 0;
}
```

## API Overview

| Module | File | Purpose |
|--------|------|---------|
| `xiom.redis` | `redis.xi` | FFI declarations |
| `xiom.redis.client` | `src/client.xi` | Safe typed wrappers with contracts |

### Connection

```xiom
let conn = redis_connect("127.0.0.1", 6379)?;
redis_ping(&conn)?;              // "PONG"
redis_disconnect(&conn);
```

### Key-Value Operations

```xiom
redis_set(&conn, "key", "value")?;
redis_get(&conn, "key")?;                  // Some("value")
redis_get(&conn, "missing")?;              // None
redis_set_ex(&conn, "session", "data", 3600)?;  // TTL 1 hour
redis_del(&conn, vec!["key1", "key2"])?;
redis_exists(&conn, vec!["key1"])?;
redis_incr(&conn, "counter")?;
redis_decr(&conn, "counter")?;
```

### Hashes

```xiom
redis_hset(&conn, "user:1", "name", "Alice")?;
redis_hget(&conn, "user:1", "name")?;      // Some("Alice")
let all = redis_hgetall(&conn, "user:1")?; // Map[Str, Str]
```

### Lists

```xiom
redis_lpush(&conn, "queue", vec!["task1", "task2"])?;
redis_rpop(&conn, "queue")?;               // Some("task1")
let range = redis_lrange(&conn, "queue", 0, -1)?;
```

### Pub/Sub

```xiom
redis_publish(&conn, "channel", "Hello subscribers!")?;
```

## Contracts

- `requires: port > 0, host.len() > 0` on connect
- `requires: conn.handle != 0` — connection must be alive
- `requires: key.len() > 0` — no empty keys
- NULL replies from GET on missing keys return `Ok(None)` — not an error

## License

MIT or Apache-2.0, at your option.
