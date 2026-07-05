# xiom-redis Specification

## Overview
Redis client bindings for XIOM via hiredis. Provides safe, contract-enforced key-value operations, pub/sub messaging, and data structure commands (lists, hashes, sets).

## Architecture

### Layers
```
┌──────────────────────────────────────┐
│  src/client.xi   (Safe XIOM API)     │
│  RedisConn with contracts            │
├──────────────────────────────────────┤
│  redis.xi        (Raw FFI decls)     │
│  Client, RedisValue, command         │
├──────────────────────────────────────┤
│  hiredis.xiom-bind (C ABI mapping)   │
│  redisConnect, redisCommand, etc.    │
└──────────────────────────────────────┘
```

### Design Decisions
- `RedisConn` wraps the raw hiredis context pointer with connection metadata.
- All responses are parsed into the `RedisValue` algebraic type.
- Commands are sent via hiredis blocking API; pipelining uses `redisAppendCommand` + `redisGetReply`.
- Pub/sub requires a dedicated connection (hiredis limitation).

## Type System

### RedisConn
```
pub type RedisConn = { handle: Int; host: Str; port: Int; }
```

### RedisValue
```
pub enum RedisValue {
  Nil,
  Integer(value: Int),
  String(value: Str),
  Array(items: Vec[RedisValue]),
  Error(message: Str),
}
```

### Reply Type Constants
| Constant | Value | hiredis Enum |
|----------|-------|--------------|
| `REPLY_STRING` | 1 | `REDIS_REPLY_STRING` |
| `REPLY_ARRAY` | 2 | `REDIS_REPLY_ARRAY` |
| `REPLY_INTEGER` | 3 | `REDIS_REPLY_INTEGER` |
| `REPLY_NIL` | 4 | `REDIS_REPLY_NIL` |
| `REPLY_ERROR` | 6 | `REDIS_REPLY_ERROR` |

## API Surface

### Connection
| Function | Contract |
|----------|----------|
| `redis_connect(host, port)` | `requires: port > 0, host.len() > 0` |
| `redis_connect_timeout(host, port, timeout)` | `requires: port > 0` |
| `redis_disconnect(conn)` | `requires: conn.handle != 0` |
| `redis_ping(conn)` | `requires: conn.handle != 0` |

### Key-Value
| Function | Contract |
|----------|----------|
| `redis_get(conn, key)` | `requires: conn.handle != 0, key.len() > 0` |
| `redis_set(conn, key, value)` | `requires: conn.handle != 0, key.len() > 0` |
| `redis_set_ex(conn, key, value, ttl)` | `requires: conn.handle != 0, key.len() > 0` |
| `redis_del(conn, keys)` | `requires: conn.handle != 0` |
| `redis_exists(conn, keys)` | `requires: conn.handle != 0` |
| `redis_expire(conn, key, ttl)` | `requires: conn.handle != 0, key.len() > 0` |
| `redis_keys(conn, pattern)` | `requires: conn.handle != 0` |
| `redis_incr(conn, key)` | `requires: conn.handle != 0, key.len() > 0` |
| `redis_decr(conn, key)` | `requires: conn.handle != 0, key.len() > 0` |

### Hashes
| Function | Contract |
|----------|----------|
| `redis_hset(conn, hash, field, value)` | `requires: conn.handle != 0` |
| `redis_hget(conn, hash, field)` | `requires: conn.handle != 0` |
| `redis_hgetall(conn, hash)` | `requires: conn.handle != 0` |

### Lists
| Function | Description |
|----------|-------------|
| `redis_lpush(conn, key, values)` | Push to head |
| `redis_rpop(conn, key)` | Pop from tail |
| `redis_lrange(conn, key, start, stop)` | Range query |

### Pub/Sub
| Function | Description |
|----------|-------------|
| `redis_publish(conn, channel, message)` | Publish message |

### Generic
| Function | Description |
|----------|-------------|
| `redis_command(conn, cmd)` | Raw Redis command string |
| `redis_command_args(conn, args)` | Formatted command args |

## Safety Contracts
1. All functions require `conn.handle != 0` — connection must be alive.
2. `key.len() > 0` enforced on all key-based operations.
3. `port > 0` enforced on connect.
4. After `redis_disconnect`, `RedisConn.handle` is zeroed.
5. hiredis `freeReplyObject` is called automatically after every command.
6. Memory for `RedisValue` strings is copied into XIOM-managed memory.

## External Dependencies
- **Runtime:** hiredis — `hiredis.dll` / `libhiredis.so` / `libhiredis.dylib`
- **Install:** `apt install libhiredis-dev` (Linux), `brew install hiredis` (macOS), vcpkg (Windows)
- **Link flags:** `-l hiredis`
- **Compatibility:** Redis >= 5.0, Redis Stack (all modules)

## Error Handling
1. Connection failures: `Err(conn.error_message)`.
2. Command errors: `Err(RedisValue::Error.message)`.
3. Type mismatches (e.g., `GET` on a list key) return Redis error string.
4. Network timeouts during blocking operations return `Err("timeout")`.
5. NULL replies from `GET` on missing keys return `Ok(None)` — not an error.
