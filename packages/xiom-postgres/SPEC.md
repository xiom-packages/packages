# xiom.postgres -- Specification

Version: 0.1.0 (incubating).
Modules: `xiom.postgres` (`src/postgres.xi`), `xiom.postgres.wire`
(`src/wire.xi`), `xiom.postgres.auth` (`src/auth.xi`). Pure XIOM, no FFI.
Dependencies: `xiom.std >=0.60.0 <1.0.0` (uses `xiom.net.socket`,
`xiom.string`, `xiom.convert`, `xiom.crypto`, `xiom.encoding`, `xiom.rand`;
the tests additionally use `xiom.test` and `xiom.io`).

## 1. Scope

A phase-1 PostgreSQL wire-protocol (v3) client: TCP transport, startup,
three authentication methods, the simple query protocol, typed results and
typed errors. The libpq FFI placeholder path of the 0.0.x stub is removed
(no `libpq.xiom-bind`, no bridge C); nothing in the package links a C
library beyond the XIOM runtime itself.

## 2. Name and module choice

The package keeps the stub's manifest name `xiom.postgres` and its 0.1.0
version. The stub's two self-contained files are replaced by three cohesive
modules:

| Module | File | Role |
|---|---|---|
| `xiom.postgres` | `src/postgres.xi` | connection lifecycle, startup loop, query loop, quoting helpers |
| `xiom.postgres.wire` | `src/wire.xi` | shared types, typed errors, byte encode/decode primitives, frontend builders, backend decoder (`wire_decode`) |
| `xiom.postgres.auth` | `src/auth.xi` | MD5 (RFC 1321) and SCRAM-SHA-256 (RFC 5802/7677) computations |

Namespace audit: no module collides with a stdlib namespace
(`scripts/namespace-check.ps1` runs in the harness and reports
`xiom.postgres OK (3 module(s))`).

## 3. Declared surface

### 3.1 Types (module `xiom.postgres`)

| Type | Fields | Notes |
|---|---|---|
| `PgConn` | `fd, host, port, user, database, pid, secret, timeout_ms, params: Vec[PgParam], notices: Vec[PgNotice], rbuf: Vec[UInt8]` | `fd == -1` means released; `rbuf` is the receive reassembly buffer |
| `PgParam` | `name, value` | one ParameterStatus ('S') entry |
| `PgNotice` | `severity, code, message` | summary of a NoticeResponse ('N') |
| `QueryResult` | `columns: Vec[Str], fields: Vec[PgField], rows: Vec[Vec[Option[Str]]], row_count, col_count, tag, affected, notices` | NULL is `None`; rows are text format |

### 3.2 Types (module `xiom.postgres.wire`)

| Type | Notes |
|---|---|
| `PgError` | `kind, message, code, severity, detail, hint, position, offset, fields` |
| `PgField` | RowDescription field: `name, table_oid, column_id, type_oid, type_size (signed), type_mod (signed), format` |
| `PgErrField` | one raw 'E'/'N' field: `code` (one letter), `value` |
| `PgMsg` | one decoded backend message; only the fields relevant to `msg_type` are populated |
| `PgCStr` | `value, next` -- a NUL-terminated string read and its end offset |

### 3.3 Functions

| Function | Contract |
|---|---|
| `connect(host, port, user, password, database) -> Result[PgConn, PgError]` | TCP + startup + auth through ReadyForQuery; default 10000 ms receive timeout |
| `connect_with_timeout(..., timeout_ms) -> Result[PgConn, PgError]` | same, explicit timeout |
| `connect_with_options(..., timeout_ms, client_nonce) -> Result[PgConn, PgError]` | `client_nonce == ""` generates a CSPRNG nonce; a non-empty value pins the SCRAM client nonce (testability/determinism) |
| `attach(fd, host, port, user, password, database, timeout_ms, client_nonce) -> Result[PgConn, PgError]` | run the startup handshake on an already-connected fd; on success the PgConn owns the fd, on failure the fd is closed |
| `disconnect(conn: &mut PgConn)` | Terminate + close; idempotent (guards `fd >= 0`) |
| `query(conn: &mut PgConn, text) -> Result[QueryResult, PgError]` | one simple Query round trip (empty text is allowed: the server answers EmptyQueryResponse) |
| `exec(conn: &mut PgConn, text) -> Result[QueryResult, PgError]` | alias of `query`, statement intent |
| `pg_is_connected(conn: &PgConn) -> Bool` | `fd >= 0` |
| `pg_conn_param(conn: &PgConn, name) -> Str` | ParameterStatus lookup; `""` when absent |
| `pg_quote_literal(value) -> Str` | see section 8 |
| `pg_quote_identifier(name) -> Str` | see section 8 |

Module `xiom.postgres.wire` additionally exports: `wire_decode(buf, start)`,
`read_i32/read_i16/read_u8/read_cstr/read_bytes`, the builders
(`build_startup`, `build_password`, `build_sasl_initial`,
`build_sasl_response`, `build_query`, `build_terminate`), error
constructors (`err_connection`, `err_timeout`, `err_auth`,
`err_unsupported_auth`, `err_protocol`, `server_error_from`),
`pg_tag_affected`, the `PG_*`/`AUTH_*` constants.

Module `xiom.postgres.auth` exports: `md5_digest`, `md5_hex`,
`pg_md5_password`, `scram_client_nonce`, `scram_client_first_bare`,
`scram_client_first`, `scram_parse_server_first`, `scram_client_final`,
`scram_verify_server_final`, `scram_verify_proof_b64`,
`scram_server_signature_b64`, and the `ScramServerFirst` /
`ScramClientFinal` types.

`xiom.postgres.PG_DEFAULT_TIMEOUT_MS` is 10000 ms.

## 4. Wire messages

### 4.1 Frontend (client -> server), exact layouts

| Message | Bytes |
|---|---|
| StartupMessage | `Int32 len` (self-inclusive) `Int32 196608` (`user\0<user>\0database\0<db>\0`) `\0` -- no type byte |
| PasswordMessage ('p', 0x70) | `Int32 len` `password\0` (cleartext and MD5 forms) |
| SASLInitialResponse ('p') | `Int32 len` `mechanism\0` `Int32 len(initial)` `<initial bytes>` (raw, **no** NUL) |
| SASLResponse ('p') | `Int32 len` `<client-final bytes>` (raw, **no** NUL) |
| Query ('Q', 0x51) | `Int32 len` `sql\0` |
| Terminate ('X', 0x58) | `Int32 len == 4` |

The suite pins the exact bytes for all of these (goldens computed by hand
from this table; two length bugs in draft code -- an off-by-NUL in the
StartupMessage golden and a wrongly NUL-terminated SASLInitialResponse --
were caught by these goldens and the scripted loopback).

### 4.2 Backend (server -> client), decoded kinds

| Type | Decoded into |
|---|---|
| 'R' 0/3/5/10/11/12 | `auth_code`, `salt` (MD5), `mechanisms` (SASL), `sasl_data` (continue/final) |
| 'S' | `param_name`, `param_value` |
| 'K' | `pid`, `secret` |
| 'Z' | `status` ('I'/'T'/'E'; any other byte is a protocol error at that offset) |
| 'T' | `fields: Vec[PgField]` (name, table OID, column id, type OID, signed type size, signed type modifier, format) |
| 'D' | `values: Vec[Option[Str]]`; `-1` length is NULL; a NUL byte inside a text value is a protocol error at that exact offset |
| 'C' | `tag` plus `affected` (trailing decimal word of the tag) |
| 'I' | empty body |
| 'E' / 'N' | `err_fields` verbatim + decoded `severity`, `code`, `message`, `detail`, `hint`, `position` (field letters S/V/C/M/D/H/P) |
| 'A' | `pid`, `channel`, `payload` |

Decode rules: every read is bounded by the declared message length that was
itself validated against the buffer; a declared length `< 4` or above
`PG_MAX_MESSAGE_BYTES` (16 MiB) is a typed protocol error; `wire_decode(buf,
start)` returns `next = start + 1 + length` so callers can walk multiple
messages in one buffer. Message boundaries are hard: nested fields cannot
read into the next message.

### 4.3 Query semantics

For a single statement the result is exactly that statement's column set,
rows, tag and affected count. For a multi-statement query string, rows of
every result set are concatenated, `columns`/`fields` come from the first
RowDescription, and `tag`/`affected` reflect the last CommandComplete;
one statement per call is the documented well-defined use.

## 5. Authentication matrix

| Method | Wire flow | Status |
|---|---|---|
| Trust (`R` code 0) | `R0` -> ReadyForQuery | implemented |
| Cleartext (`R` code 3) | `R3` -> 'p' password -> `R0` | implemented; empty password refused client-side with `PG_ERR_AUTH` |
| MD5 (`R` code 5) | `R5`+4-byte salt -> 'p' `md5<hex>` -> `R0`; challenge = `md5_hex(md5_hex(pw+user) || salt)` (own RFC 1321 MD5; `xiom.crypto.md5` v0.64.5 is defective, see `AUDIT.md`) | implemented |
| SCRAM-SHA-256 (`R` code 10/11/12) | `R10` mechanism list -> SASLInitialResponse (`n,,n=user,r=<nonce>`) -> `R11` server-first -> SASLResponse (client-final, proof) -> `R12` server-final (`v=`) verified against the locally computed server signature -> `R0`; PBKDF2-HMAC-SHA256 (stdlib), server nonce must extend the client nonce (RFC 5802 check) | implemented; RFC 7677 published vector pinned in the suite |
| GSS/SSPI, SASL other (`R` 7/8/9) | -- | typed `PG_ERR_UNSUPPORTED_AUTH` |

Nonce generation is CSPRNG (`xiom.rand.random_bytes_crypto`), base64 with
padding stripped. SASLprep (RFC 4013) is **not** applied to usernames or
passwords (0.2 roadmap); ASCII credentials are unaffected.

## 6. Error taxonomy

`PgError.kind`:

| Constant | Value | Meaning |
|---|---|---|
| `PG_ERR_CONNECTION` | 1 | socket create/connect failed; send failed; server closed; closed connection use. On this toolchain a refused connect may surface at `connect()` or at the first send -- both map here |
| `PG_ERR_PROTOCOL` | 2 | decode/validation failure; `offset` is always set (see below); unknown message type; NUL in a text value; length out of bounds; startup/query received an unexpected message kind |
| `PG_ERR_AUTH` | 3 | missing password, malformed SCRAM messages, nonce/signature mismatch, server-completed-startup-without-AuthenticationOk |
| `PG_ERR_SERVER` | 4 | server ErrorResponse; `code` holds the SQLSTATE, `severity/detail/hint/position` are decoded, `fields` preserves every raw field |
| `PG_ERR_TIMEOUT` | 5 | receive timed out or failed mid-flight (socket receive errors are reported here; the message names the ambiguity) |
| `PG_ERR_UNSUPPORTED_AUTH` | 6 | GSS/SSPI or SASL mechanisms other than SCRAM-SHA-256 |

`offset` semantics: the absolute byte offset where decoding could not
continue -- the offending byte for an invalid value (status byte, message
type, NUL inside a value), the first missing byte for a truncation, the
message end when a nested field overruns its declared length, and the
position after a completed message start when the offset itself is past the
end of input. `-1` when the error has no wire offset.

## 7. Test surface (conformance suite)

`tests/test_conformance.xi` (38 tests; the harness's exact `[PASS]`/`[FAIL]`
contract):

1. **Codec goldens** -- literal-byte frontend builders; literal-byte decode
   goldens for every backend kind; truncated/garbage inputs asserting the
   typed kind and exact offset; message chaining; embedded start offsets;
   NUL-in-value rejection.
2. **Authentication KATs** -- MD5: RFC 1321 vectors (`abc`, empty, fox) and
   a PostgreSQL challenge vector computed independently with .NET MD5
   (`md549a34335002b87ce9bfd06e813246528`); SCRAM: the RFC 7677 published
   vector (client-final `...p=dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ=`,
   server signature `6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=`), plus
   saslname escaping, nonce properties and the parse/verify error paths.
3. **Offline loopback** -- a scripted in-process server (bind/listen/accept
   on a free port in 45440-45499; `socket_local_addr` is not exposed by the
   stdlib so an OS-assigned ephemeral port is not reachable -- see
   `AUDIT.md`) pre-writes its full reply script; the client runs over a real
   TCP loopback connection via `attach`; the server then reads the client's
   bytes back. Covered: happy path (typed columns/rows/NULLs/tag/affected,
   exact startup/query/Terminate bytes), cleartext, MD5 (server checks the
   answer against the oracle), SCRAM end to end (server verifies the client
   proof with `scram_verify_proof_b64`), auth failure, query error, notices.
4. **Error taxonomy and quoting** -- refused connection, argument guards,
   closed-connection guard, unsupported auth, protocol violation, silent
   server timeout, quote KATs.
5. **Live path** -- probes 127.0.0.1:5432; unreachable prints the explicit
   SKIP marker; reachable-and-usable runs `SELECT 1` and
   `SELECT current_database()`; reachable-but-unusable SKIPs with the reason.

## 8. Quoting helpers and the injection caveat

- `pg_quote_literal(value)` returns `'...'` with embedded `'` doubled and
  embedded `\` doubled (safe under both `standard_conforming_strings`
  settings). It is a **value-literal** helper only.
- `pg_quote_identifier(name)` returns `"..."` with embedded `"` doubled.

Neither makes arbitrary untrusted fragments safe: literals only protect
values in value positions. Server-side parameters (`$1`) via the extended
protocol are the real fix and are declared for 0.2.0; until then the
documented pattern is: quote values with `pg_quote_literal`, never
interpolate identifiers except through `pg_quote_identifier`, and never
interpolate raw text into SQL.

## 9. Deliberate non-goals (0.1.0)

TLS/SSL negotiation; the extended query protocol and `$1` parameters
(Parse/Bind/Execute, portals, prepared statements); COPY; async
notification delivery APIs (`LISTEN`); cancellation requests; connection
strings (`key=value`/`postgres://`); multi-host/failover; SASLprep;
SCRAM channel binding (`SCRAM-SHA-256-PLUS`); binary result formats; large
objects. `ROADMAP.md` carries the 0.2.0 ordering.

## 10. Toolchain notes (XIOM v0.64.5)

- `xiom.crypto.md5` does not produce RFC 1321 digests (md5("abc") =
  `5aac66a4e204752757366266cfad9c14`); the package carries its own MD5 with
  RFC 1321 vectors as tests.
- A codegen defect (clang tuple-type collision) is triggered by
  tuple-returning helpers in this program shape; the package uses small
  structs instead of tuples at module boundaries.
- `xiom.thread.spawn` is simulated (runs the closure inline), so the
  scripted server cannot run on a separate thread; the loopback harness
  therefore uses the pre-written-script + `attach` design.
- `socket_local_addr` is not exposed; port 0 cannot be bound
  (`socket_bind` rejects it), hence the candidate-port scan.
