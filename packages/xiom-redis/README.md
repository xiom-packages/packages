# xiom.redis

> **Status:** `incubating` -- conformance-tested (19/19), recorded x2 green
> on XIOM v0.64.5; not yet published (registry/allowlist gate).
> **Scope:** Redis client, pure XIOM: RESP2 wire codec, TCP transport over
> `xiom.net.socket`, typed command wrappers, pipelines and pub/sub basics.
> No FFI, no bridge C, no hiredis.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.net.socket`,
> `xiom.string.compare`; the tests use `xiom.test` and `xiom.io`).

## What it is

`xiom.redis` is a dependency-free Redis RESP2 client and protocol codec:

- **Codec** (`xiom.redis.resp`): encodes a command as an array of bulk
  strings (exact wire bytes) and decodes every RESP2 reply type -- simple
  string, error, integer, bulk string (including `$-1` null), array
  (including `*-1` null array) and nested arrays -- with hard caps on
  nesting depth (32), bulk size (64 MiB), array length (1048576) and the
  assembled reply (128 MiB). Every failure is a typed `RedisError` with a
  numeric `RESP_ERR_*` code (catalogs in `SPEC.md`).
- **Client** (`xiom.redis.client`, `xiom.redis.verbs`): connect /
  disconnect over a real TCP socket, a buffered reply reader that applies
  per-connection read deadlines, raw and server-error-checked commands,
  pipelines (N commands, N ordered replies), and pub/sub basics
  (`subscribe` / `unsubscribe` / `publish` / `read_push`). Server errors
  preserve the server's message verbatim; wrong-type accessor use,
  timeouts, truncation and refused connections are separate typed kinds.
- **Values** (`xiom.redis.value`): `RedisValue`, `RedisText` (optional
  text for GET/MGET/RPOP-style replies) and typed accessors
  (`value_kind`, `value_text`, `value_int`, `value_maybe_text`,
  `value_array`, `value_at`, ...). Nothing is guessed: an accessor applied
  to the wrong kind is `Err(kind REDIS_ERR_TYPE)`.

There is no global state, no internal wall clock and no hidden handshake:
timeouts are socket poll deadlines, the reader is explicitly buffered, and
the corpus of unit-bytes assertions in the suite pins the wire format.

## Install / use

Until the package is published to the registry, build against this
checkout with the repo harness:

```
.\scripts\port.ps1 -Package xiom.redis
```

Once published:

```
xiom pkg install xiom.redis@0.1.0
```

## Quick start

```xi
use xiom.io;
use xiom.redis;         // connect, command, get, set, pipeline, ...
use xiom.redis.value;   // RedisValue, RedisText, value_* accessors
use xiom.redis.client;  // RedisConn and RedisError

fn main() -> Int {
  let cr = connect("127.0.0.1", 6379);
  match cr {
    Ok(conn0) => {
      var conn: RedisConn = conn0;
      let sr = set(&mut conn, "greeting", "hello");
      match sr {
        Ok(_) => {},
        Err(e) => { io.println("SET failed: " + e.message); },
      }
      let got = get(&mut conn, "greeting");
      match got {
        Ok(t) => {
          match t {
            Missing => { io.println("(nil)"); },
            Text(v) => { io.println(v); },   // hello
          }
        },
        Err(e) => { io.println("GET failed: " + e.message); },
      }
      // Raw command escape hatch (any verb, exact wire form):
      var args: Vec[Str] = Vec[Str].new();
      args.push("TTL");
      args.push("greeting");
      let ttl = command(&mut conn, &args);
      match ttl {
        Ok(v) => { io.println("ttl kind: " + value_kind(&v).to_str()); },
        Err(e) => { io.println(e.message); },
      }
      disconnect(&mut conn);
    },
    Err(e) => { io.println("connect failed: " + e.message); },
  }
  return 0;
}
```

## Boundaries

See `SPEC.md` for the exact wire format, the error taxonomy, the declared
surface and the non-goals (RESP3, TLS, cluster, scripting, streams);
`PROVENANCE.md` records the independent-declaration basis (the published
Redis protocol specification; no upstream code consulted); `AUDIT.md`
carries the verification record and known runtime deviations.
