# xiom.redis -- Specification

Version: 0.1.0 (incubating).
Pure XIOM, no FFI, no bridge C, no hiredis: the transport is the stdlib TCP
socket (`xiom.net.socket`, a platform dependency) and the codec is
implemented from the published Redis protocol specification (see
`PROVENANCE.md`).
Dependencies: `xiom.std >=0.60.0 <1.0.0` (uses `xiom.net.socket`,
`xiom.string.compare`; the tests additionally use `xiom.test` and `xiom.io`).

## 1. Scope

A Redis RESP2 client and protocol codec:

- `xiom.redis.value` (`src/value.xi`) -- `RedisValue`, `RedisText`,
  `RedisError`, the `REDIS_*` / `RESP_*` constants, the documented caps and
  the typed value accessors.
- `xiom.redis.resp` (`src/resp.xi`) -- RESP2 encoder/decoder, streaming
  decode outcome (`Done` / `NeedMore` / `Bad`) with consumed byte counts.
- `xiom.redis.client` (`src/client.xi`) -- `RedisConn` session over a real
  TCP socket: connect/disconnect, read deadlines, buffered reply reading,
  `command` / `command_checked`, pipelines.
- `xiom.redis.verbs` (`src/verbs.xi`) -- typed verb wrappers and pub/sub.
- `xiom.redis` (`redis.xi`) -- the public plain-name surface re-exporting
  the client and verb functions (`connect`, `command`, `get`, `set`,
  `pipeline`, `subscribe`, ...).

## 2. Wire format (RESP2)

### 2.1 Commands (encode)

A command is an array of bulk strings. `resp_encode_command(&Vec[Str])`
returns the exact wire bytes as a byte-exact `Str`;
`resp_encode_command_bytes` returns `Vec[UInt8]` for the transport:

```
*<n>\r\n                        n >= 1, decimal, no '+' sign
$<len>\r\n<arg>\r\n             len = arg.len() in bytes, decimal
```

Framing is length-prefixed, so CRLF bytes inside an argument are safe.
An empty argument list is `Err` (kind `REDIS_ERR_PROTOCOL`, code
`RESP_ERR_EMPTY`); an argument longer than `RESP_MAX_BULK` is `Err`
(code `RESP_ERR_SIZE`). No other validation is performed (the server
validates command names and arity).

### 2.2 Replies (decode)

`resp_decode(buf, off)` decodes exactly one reply; `resp_decode_at(buf, off)`
is the streaming form returning `RespOutcome`:

| Marker | Type | Value | Consumed |
|---|---|---|---|
| `+` | simple string | `Simple(text)` | through CRLF |
| `-` | error | `Error(message)` (verbatim) | through CRLF |
| `:` | integer | `Integer(v)` (`-`/`+` sign accepted) | through CRLF |
| `$` | bulk string | `Bulk(text)`; `$-1` -> `Nil` | through payload CRLF |
| `*` | array | `Array(items)`; `*-1` -> `NullArray` | through all children |

- `RespOutcome::Done(done)` reports `done.consumed` = the number of bytes
  the value occupies **relative to `off`** (end_offset - off).
- `RespOutcome::NeedMore` means the buffer ends inside a value: read more
  bytes and retry from the same offset. `resp_decode` maps this to
  `Err(kind REDIS_ERR_PROTOCOL, code RESP_ERR_TRUNCATED)`.
- `RespOutcome::Bad(error)` is a typed decode error.

### 2.3 Hard caps (all typed `RESP_ERR_SIZE` / `RESP_ERR_DEPTH`)

| Constant | Value | Meaning |
|---|---|---|
| `RESP_MAX_DEPTH` | 32 | maximum array nesting |
| `RESP_MAX_BULK` | 67108864 | maximum declared bulk payload (64 MiB) |
| `RESP_MAX_ARRAY` | 1048576 | maximum declared array length |
| `RESP_MAX_REPLY` | 134217728 | maximum assembled session buffer (128 MiB) |

A declared length above a cap is rejected before any allocation; the
session buffer cap is enforced while reading (client-side).

### 2.4 Decode policy notes

- A lone LF (without a preceding CR) inside a header line or a bulk
  payload terminator is a terminator violation (`RESP_ERR_TERMINATOR`),
  not silently tolerated.
- Unknown markers are `RESP_ERR_TYPE`; malformed / out-of-range decimal
  fields are `RESP_ERR_INTEGER`; `$-2` / `*-2`-style negative lengths
  other than the `-1` null forms are `RESP_ERR_LENGTH`; a negative decode
  offset is `RESP_ERR_OFFSET`.
- Payload text is carried as byte-length-preserving `Str` values; no
  UTF-8 validation or interpretation is applied.

## 3. Client semantics

### 3.1 Connection

- `connect(host, port)`: empty host and out-of-range port are typed
  `REDIS_ERR_CONNECT` failures before any socket work; otherwise a real
  TCP connect via `socket_tcp` + `socket_connect`.
- `connect_timeout(host, port, timeout_sec)`: connect, then apply
  `timeout_sec` (truncated to milliseconds) as the session read deadline.
  `0.0` blocks. **The TCP handshake itself is bounded by the operating
  system's connect timeout** -- the runtime exposes no connect deadline,
  and the library has no internal wall clock by design.
- `disconnect` closes the fd and is safe to call twice.

**Runtime deviation (evidence in `AUDIT.md`).** On XIOM v0.64.4/v0.64.5
for Windows, `socket_connect` reports success for a refused loopback
handshake (the runtime shim discards the `connect()` error). The client
therefore classifies a **first-command send failure before any byte has
ever been sent** as `REDIS_ERR_CONNECT` ("refused or reset before first
command"), giving the refused-connection taxonomy on platforms where the
connect error is observable and on those where it is not. The conformance
suite accepts the classified error at either point.

### 3.2 Reads and timeouts

- Replies are read with a per-connection buffer; partial reads are kept
  between calls and decoded with `resp_decode_at`.
- A read deadline (`set_read_timeout`, milliseconds) is applied per read
  through `socket_poll_read` before `socket_recv`; an expired deadline is
  `Err(kind REDIS_ERR_TIMEOUT)`. There is no clock inside the library.
- EOF with a partial reply buffered is `Err(kind REDIS_ERR_PROTOCOL, code
  RESP_ERR_TRUNCATED)`; EOF with an empty buffer is
  `Err(kind REDIS_ERR_CLOSED)`. Socket failures after establishment are
  `REDIS_ERR_CLOSED`.

### 3.3 Commands, pipelines, pub/sub

- `command(conn, args)` returns the raw decoded reply; a server error
  reply is `Ok(Error(message))` (protocol fidelity).
- `command_checked` and every verb wrapper map a server error reply to
  `Err(kind REDIS_ERR_SERVER, message preserved verbatim)`.
- `pipeline(conn, commands)` writes all commands first, then reads N
  replies in order; error replies stay `Error` values (raw pipeline
  semantics).
- Pub/sub: `subscribe(conn, channel)` validates the confirmation array
  and returns the subscription count; afterwards the connection is in
  subscribed mode (the server accepts only the pub/sub subset) and
  `read_push(conn, timeout_ms)` consumes one push array at a time with a
  per-call deadline (kind `REDIS_ERR_TIMEOUT` on expiry).
  `unsubscribe` and `publish` complete the basics.

## 4. Error taxonomy

`RedisError = { kind: Int; code: Int; message: Str; }`

| Kind | Constant | Raised for |
|---|---|---|
| 1 | `REDIS_ERR_CONNECT` | socket create/connect failures, bad host/port, first-send failure |
| 2 | `REDIS_ERR_PROTOCOL` | decode errors, local argument validation, mid-reply truncation |
| 3 | `REDIS_ERR_TIMEOUT` | an expired read/deadline (poll-based, typed) |
| 4 | `REDIS_ERR_SERVER` | a server error reply, message verbatim |
| 5 | `REDIS_ERR_CLOSED` | peer closed / socket failed after establishment |
| 6 | `REDIS_ERR_TYPE` | a typed accessor applied to the wrong value kind |

`code` is a `RESP_ERR_*` protocol code for kind 2 (0 otherwise):

| Code | Constant | Raised for |
|---|---|---|
| 1 | `RESP_ERR_TYPE` | unknown reply marker |
| 2 | `RESP_ERR_LENGTH` | invalid declared length (`<-1`) |
| 3 | `RESP_ERR_TRUNCATED` | incomplete buffer / EOF mid-reply |
| 4 | `RESP_ERR_DEPTH` | nesting past 32 |
| 5 | `RESP_ERR_SIZE` | cap exceeded (bulk/array/assembled) |
| 6 | `RESP_ERR_TERMINATOR` | LF without CR / bad bulk terminator |
| 7 | `RESP_ERR_INTEGER` | malformed or out-of-range integer field |
| 8 | `RESP_ERR_EMPTY` | empty command / empty pipeline |
| 9 | `RESP_ERR_OFFSET` | negative decode offset |

## 5. Value model

- `RedisValue`: `Nil` (`$-1`), `NullArray` (`*-1`), `Simple(text)`,
  `Error(message)`, `Integer(v)`, `Bulk(text)`, `Array(items)` (nested).
- `RedisText`: `Missing` (RESP null) / `Text(value)` -- for GET, MGET
  elements and similar optional replies (avoids `Result[Option[T]]`, which
  this toolchain miscompiles; see section 8).
- Accessors (kind-indexed, never coercing):
  `value_kind` (`REDIS_VALUE_*`), `value_is_nil`, `value_is_null`,
  `value_error_message`, `value_text` (simple/bulk),
  `value_int` (integer only), `value_maybe_text` (null -> Missing),
  `value_array_len`, `value_array`, `value_at`.
  Wrong-kind use is `Err(kind REDIS_ERR_TYPE)`.

## 6. Declared surface

Types: `RedisError`, `RedisValue`, `RedisText`, `RedisConn`, `RespDone`,
`RespOutcome`.

Client functions (module `xiom.redis`): `connect`, `connect_timeout`,
`disconnect`, `set_read_timeout`, `read_timeout`, `command`,
`command_checked`, `pipeline`, `read_value`, `ping`, `echo`, `get`, `set`,
`set_ex`, `del`, `exists`, `incr`, `decr`, `expire`, `ttl`, `mget`, `mset`,
`subscribe`, `unsubscribe`, `publish`, `read_push`.

Implementation modules export the same functions with a `redis_` prefix
(`xiom.redis.client`, `xiom.redis.verbs`) plus the codec
(`resp_encode_command`, `resp_encode_command_bytes`, `resp_decode_at`,
`resp_decode` in `xiom.redis.resp`) and the accessors/constants
(`xiom.redis.value`).

Constants: 7 `REDIS_ERR_*`, 9 `RESP_ERR_*`, 7 `REDIS_VALUE_*`, 4 caps.

## 7. Test plan (`tests/test_conformance.xi`, 19 checks)

The declared suite is the driver; the checks live in `tests/suite_codec.xi`
(7), `tests/suite_net.xi` (9) and `tests/suite_live.xi` (3). Run with:

```
.\scripts\port.ps1 -Package xiom.redis -TimeoutSec 300
```

1. **Codec goldens** -- exact wire bytes for PING / SET / ECHO (incl. an
   empty argument and an argument containing CRLF) / DEL / empty-command
   error (c1); decode of every reply type incl. nulls with consumed counts
   and non-zero offsets (c2); nested and mixed arrays (c3); the truncated
   path (c4); garbage codes (c5); caps and depth (c6); typed/accessor
   behavior incl. wrong-type errors (c7).
2. **Offline client over loopback** -- the suite starts a scripted
   in-process RESP server on a fixed candidate port (no threads: the
   server pre-sends scripted replies; after the client runs, the suite
   reads the socket and asserts the exact request bytes): PING roundtrip
   (n8), SET/GET/ECHO (n9), null bulk -> Missing (n10), INCR/TTL + MGET
   array with a null element (n11), server error reply raw + checked + via
   the verb wrapper (n12), pipeline of 4 ordered replies incl. an error
   value (n13), SUBSCRIBE + read_push + push-deadline timeout (n14), a
   stalled server producing a typed TIMEOUT (n15), and a peer closing
   mid-reply producing `PROTOCOL/TRUNCATED` (n16, sent as a clean FIN).
3. **Refused-connection taxonomy** (n17, in `suite_live`): a closed
   loopback port must produce `REDIS_ERR_CONNECT` (at connect or at the
   first command, per the runtime deviation in section 3.1); an invalid
   port is typed too.
4. **Live tests** (n18, n19, in `suite_live`): PING/SET/GET/EXISTS/INCR/
   TTL/EXPIRE/DEL and a SUBSCRIBE/PUBLISH/read_push/UNSUBSCRIBE roundtrip
   against 127.0.0.1:6379. When no server is reachable the checks print an
   explicit `SKIP -- no live Redis at 127.0.0.1:6379` line; a SKIP is a
   printed honest state, never a fake pass.

Recorded x2 green (19/19) on XIOM v0.64.5 -- see `AUDIT.md` for the run
records. Every check prints one `[PASS]`/`[FAIL]` line and the process
exit code is the failure count.

## 8. Toolchain discipline (XIOM v0.64.5)

- No `?` operator: error propagation is explicit match/rewrap (the
  recorded v0.64.x defect that corrupts error payloads across differing
  `Result` payload types).
- No `Result[Option[T]]` nesting: optional text uses the dedicated
  `RedisText` enum.
- Ok/Err and outcome/value construction is confined to small leaf
  helpers; array decode accumulates into a `Vec[RedisValue]` with typed
  local reads.
- `RespOutcome` keeps the streaming contract: `consumed` is relative to
  the decode offset (regression-guarded by the c2 offset check).
- No `&mut` of struct-return temporaries; connection values are bound to
  `var` locals before `&mut` use (the README quick start does the same).
- Str equality in the suite goes through `compare.str_compare`; the codec
  itself never compares Str payloads.
- Direct compiler invocations must pass an **absolute** entry path:
  module resolution for `use xiom.redis...` fails with a relative suite
  path in v0.64.4/v0.64.5 (the repo harness `port.ps1` always passes an
  absolute path). Found while building this package; recorded in AUDIT.md.

## 9. Non-goals (declared, not silently missing)

- **RESP3**: only RESP2 markers are decoded (`+ - : $ *`); the `HELLO`
  command can be sent but RESP3 types (maps, sets, doubles, push
  attribute forms) are not decoded.
- **TLS** and any transport beyond plain TCP (`xiom.net.tls` is not
  wired in); UNIX domain sockets.
- **Cluster / Sentinel / MOVED-ASK redirection**, topology discovery,
  sharding, pipelining auto-batching.
- **Scripting** (`EVAL`), `MULTI`/`EXEC` transaction helpers, blocking
  commands (`BLPOP`/`BRPOP`/`WAIT`), keyspace notifications handling.
- **Authentication helpers** (`AUTH`, ACL) and `SELECT` database
  helpers: any such command can be sent through `command`, but no typed
  wrapper exists.
- **Streams** (`XADD` and friends) beyond generic `command`/`pipeline`.
- Connection pooling, auto-reconnect, retries and metrics; one
  `RedisConn` is a plain single-task session.
- Payload types beyond text: replies are carried as byte-preserving
  `Str`; there is no typed serializer for binary blobs.
