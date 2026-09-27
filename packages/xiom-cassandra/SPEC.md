# xiom.cassandra -- wire format specification

Copyright (c) 2026 Eleftherios Notas and The XIOM Authors.
SPDX-License-Identifier: MIT OR Apache-2.0

This document describes the byte-level layouts **actually implemented** by
`src/cassandra.xi`. It is a structural subset of the Apache Cassandra
native protocol v4; only the parts listed here are encoded or decoded.

## 1. Conventions

- All fixed-width integers are **big-endian** (network byte order), with no
  padding and no alignment.
- `[int]` = 4 bytes, signed two's complement (read back sign-extended).
- `[long]` = 8 bytes, signed two's complement (read back sign-extended via a
  63-bit accumulation plus a sign step, so every Int64 pattern round-trips).
- `[byte]` = 1 byte, returned as an **unsigned** 0..255 value. The v4 spec
  says a `[byte]`'s signedness does not matter; here it carries flags,
  opcodes and booleans.
- `[short]` = 2 bytes, unsigned 0..65535.
- Reading past the end of the buffer is always an error carrying the byte
  offset at which the failing read started. A negative length is always an
  error. A `u16` count that cannot fit the remaining bytes (see the per-type
  guards below) is an `oversized collection` error.
- Error strings are deterministic: `cassandra: <what>` plus, where useful,
  ` at offset N`. See section 11 for the complete catalog.

## 2. Frame header (9 bytes)

| Offset | Size | Field |
|---|---|---|
| 0 | 1 | version byte |
| 1 | 1 | flags byte |
| 2 | 2 | stream id, signed int16 |
| 4 | 1 | opcode byte |
| 5 | 4 | body length, signed int32 |
| 9 | `length` | body bytes |

- `cql_frame_header_len()` = 9.
- One frame occupies `9 + length` bytes: `cql_frame_consumed(f)`.
- `cql_read_frame` consumes exactly one frame from the reader; a short
  header is `truncated input at offset <frame start>`, a negative length is
  `bad length N at offset <start+5>`, and a body that overruns the buffer is
  `truncated body at offset <start+9>: need N bytes, have M`.
- Unknown flags and opcodes do not fail the parse; they are preserved raw.

### 2.1 Version byte

| Value | Meaning |
|---|---|
| `0x03` | v3 request (recognized, reported; v4 is the target) |
| `0x83` | v3 response (bit 0x80 = direction) |
| `0x04` | v4 request |
| `0x84` | v4 response |

- `cql_version_protocol(v)` = `v & 0x7F` (3 or 4).
- `cql_version_is_response(v)` = `(v & 0x80) != 0`.
- Any other byte once the full 9-byte header is present is
  `unsupported protocol version N at offset <frame start>`.

### 2.2 Flags byte

| Bit | Name | Meaning |
|---|---|---|
| `0x01` | COMPRESSION | body is compressed (not decoded here) |
| `0x02` | TRACING | tracing requested; response carries a tracing id |
| `0x04` | CUSTOM_PAYLOAD | a custom payload section is present |
| `0x08` | WARNING | response carries warning strings |
| `0x10` | USE_BETA | request opted into beta features |

`cql_flags_known(f)` = `(f & 0x1F) == f`. Undefined bits are preserved raw.
The tracing id, custom payload and warning sections are **not** decoded.

### 2.3 Opcode table

| Opcode | Name | Opcode | Name |
|---|---|---|---|
| `0x00` | ERROR | `0x09` | PREPARE |
| `0x01` | STARTUP | `0x0A` | EXECUTE |
| `0x02` | READY | `0x0B` | REGISTER |
| `0x03` | AUTHENTICATE | `0x0C` | EVENT |
| `0x04` | (unused) | `0x0D` | BATCH |
| `0x05` | OPTIONS | `0x0E` | AUTH_CHALLENGE |
| `0x06` | SUPPORTED | `0x0F` | AUTH_RESPONSE |
| `0x07` | QUERY | `0x10` | AUTH_SUCCESS |
| `0x08` | RESULT | | |

`cql_opcode_known` is true for the sixteen entries above;
`cql_opcode_name` returns the name or `"UNKNOWN"`.

## 3. Primitive encodings

| Type | Layout |
|---|---|
| `[int]` | 4 bytes signed |
| `[long]` | 8 bytes signed |
| `[byte]` | 1 byte, 0..255 |
| `[short]` | 2 bytes unsigned |
| `[string]` | `[short]` byte length + that many UTF-8 bytes |
| `[long string]` | `[int]` byte length + that many UTF-8 bytes |
| `[bytes]` | `[int]` length `n`; `n >= 0`: `n` raw bytes; `n = -1`: null; `n < -1`: bad length |
| `[value]` | `[int]` length `n`; `n >= 0`: `n` raw bytes; `n = -1`: null; `n = -2`: not set; `n < -2`: bad length |
| `[short bytes]` | `[short]` byte length + raw bytes |

- `[string]` and `[long string]` payloads must be valid UTF-8 (RFC 3629,
  strict: overlong forms, surrogate halves and truncated sequences are
  rejected) and must contain no `0x00` byte, because v0.61.3's `sb_to_str`
  aborts on a NUL. Errors: `string contains nul`, `invalid utf-8`.
- `cql_read_bytes` rejects null (`-1`) with
  `cassandra: null bytes value at offset N`; use `cql_read_value` where
  null/not-set must be represented. `CqlValue.kind` is 0 (bytes),
  1 (null) or 2 (not set); `data` is empty for 1 and 2.
- Writers never validate: `cql_write_string` writes the low 16 bits of the
  byte length and all bytes, so callers must keep `[string]` payloads
  <= 65535 bytes (use `cql_write_long_string` above that).

## 4. Container encodings

| Type | Layout | Guard on read |
|---|---|---|
| `[string list]` | `[short]` n + n `[string]` | `n > remaining/2` -> oversized |
| `[string map]` | `[short]` n + n (`[string]` key, `[string]` value) | `n > remaining/4` -> oversized |
| `[string multimap]` | `[short]` n + n (`[string]` key, `[string list]` values) | `n > remaining/4` -> oversized |
| `[bytes map]` | `[short]` n + n (`[string]` key, `[bytes]` value) | `n > remaining/6` -> oversized |

- The guard offset is the offset of the count field.
- The multimap is exposed in a **flat** form: `keys`, a flat `values`
  vector and an `offsets` vector of length `keys.len() + 1`; the values of
  key `i` are `values[offsets[i] .. offsets[i+1])`.
- Null `[bytes]` values inside a `[bytes map]` are rejected like every
  other null `[bytes]`.
- Writers write the low 16 bits of each count (callers keep counts
  <= 65535) and never validate offset well-formedness.

## 5. STARTUP body (`0x01`)

```
[string map] options
```

Typically carries `CQL_VERSION` (mandatory in practice) and optionally
`COMPRESSION`, `NO_COMPRESSION`, `DRIVER_NAME`, `DRIVER_VERSION`,
`THROW_ON_OVERLOAD`. `cql_startup_has_cql_version(m)` checks the first.

## 6. QUERY body (`0x07`)

```
[long string] query
[short]       consistency
[byte]        flags
[optional sections, in this wire order]
```

| Flag | Name | Optional section |
|---|---|---|
| `0x01` | VALUES | `[short]` n, then n values (see below) |
| `0x02` | SKIP_METADATA | no bytes |
| `0x04` | PAGE_SIZE | `[int]` page size |
| `0x08` | WITH_PAGING_STATE | `[bytes]` paging state |
| `0x10` | WITH_SERIAL_CONSISTENCY | `[short]` serial consistency |
| `0x20` | WITH_DEFAULT_TIMESTAMP | `[long]` microseconds timestamp |
| `0x40` | WITH_NAMES_FOR_VALUES | values are `[string]` name + `[value]` |
| `0x80` | KEYSPACE | v5 only; exposed as a constant, **not** interpreted |

- Wire order of the optional sections: page size, paging state, serial
  consistency, timestamp, then values. `cql_query_flags_known(f)` accepts
  `0x01..0x40` and reports `0x80` as unknown for v4.
- Values: when `0x01` is set, `[short]` n then n entries; when `0x40` is
  also set each entry is `[string]` name + `[value]`, otherwise each entry
  is a bare `[value]`. `value_names` always has n entries (`""` for
  positional values). A count that cannot fit the remaining bytes
  (4 per value) is `oversized collection at offset <count offset>`.
- A negative page size is `bad page size N at offset M`; a value length
  below `-2` is `bad length N at offset M`.
- `cql_write_query` fails with `query page size flag mismatch`,
  `query paging state flag mismatch`,
  `query serial consistency flag mismatch`,
  `query timestamp flag mismatch`,
  `query value count mismatch` (count disagrees with the parallel vectors,
  or non-zero without the values flag) or
  `query value count exceeds 65535`.

### 6.1 Consistency levels

| Value | Name | Value | Name |
|---|---|---|---|
| `0x00` | ANY | `0x06` | LOCAL_QUORUM |
| `0x01` | ONE | `0x07` | EACH_QUORUM |
| `0x02` | TWO | `0x08` | SERIAL |
| `0x03` | THREE | `0x09` | LOCAL_SERIAL |
| `0x04` | QUORUM | `0x0A` | LOCAL_ONE |
| `0x05` | ALL | | |

`cql_consistency_known(c)` = `0 <= c <= 10`; unknown values are preserved
raw by the parser and named `"UNKNOWN"` by `cql_consistency_name`.

## 7. RESULT body (`0x08`)

```
[int] kind
```

| Kind | Name | Payload |
|---|---|---|
| `0x01` | VOID | (nothing) |
| `0x02` | ROWS | `[metadata]`, `[int]` row count, then row-major cells |
| `0x03` | SET_KEYSPACE | `[string]` keyspace |
| `0x04` | PREPARED | `[short bytes]` id, `[metadata]` prepared, `[metadata]` result |
| `0x05` | SCHEMA_CHANGE | change type, target, target-specific fields |

- ROWS: the row count is checked non-negative (`bad row count N at offset
  M`); each cell is a `[value]`. `-1` decodes as a null cell (kind 1);
  `-2` is rejected with
  `cassandra: not-set value in result row at offset N` because the server
  must not send it. Cells are stored row-major: cell `r * column_count + c`.
- PREPARED always carries both metadata blocks in v4; the result metadata
  has column count 0 for non-SELECT statements.
- SCHEMA_CHANGE:
  - `[string]` change type: `CREATED`, `UPDATED` or `DROPPED`;
  - `[string]` target: `KEYSPACE`, `TABLE`, `TYPE`, `FUNCTION` or
    `AGGREGATE`;
  - `KEYSPACE`: `[string]` keyspace;
  - `TABLE`, `TYPE`: `[string]` keyspace, `[string]` name;
  - `FUNCTION`, `AGGREGATE`: `[string]` keyspace, `[string]` name,
    `[string list]` argument types.
  - Any other target string is
    `cassandra: unknown schema change target T at offset M` (offset of the
    target length field).
- An unknown kind is `cassandra: unknown result kind N at offset M`.

### 7.1 `[metadata]`

```
[int]  flags
[int]  column count
if flags & 0x0002: [bytes] paging state
if !(flags & 0x0004):
    if flags & 0x0001 and column count > 0:
        [string] global keyspace
        [string] global table
        for each column: [string] name, [option] type
    else
        for each column: [string] keyspace, [string] table,
                          [string] name, [option] type
```

| Flag | Name |
|---|---|
| `0x0001` | GLOBAL_TABLES_SPEC |
| `0x0002` | HAS_MORE_PAGES |
| `0x0004` | NO_METADATA |

- A negative flags word is `bad metadata flags N at offset M`; a negative
  column count is `bad column count N at offset M`.
- With NO_METADATA only the column count is recorded and the five parallel
  column vectors are empty; with GLOBAL_TABLES_SPEC a single
  keyspace/table pair covers every column. A null paging state is the
  usual `null bytes value` error.
- When metadata is present the column count is guarded against the
  remaining bytes (`oversized collection`).
- Column spec vectors (`keyspaces`, `tables`, `names`, `type_codes`,
  `type_names`) are always parallel and have `column_count` entries.

### 7.2 Type `[option]`

```
[short] code
```

| Code | Type | Payload |
|---|---|---|
| `0x0000` | custom | `[string]` class name |
| `0x0001` | ascii | -- |
| `0x0002` | bigint | -- |
| `0x0003` | blob | -- |
| `0x0004` | boolean | -- |
| `0x0005` | counter | -- |
| `0x0006` | decimal | -- |
| `0x0007` | double | -- |
| `0x0008` | float | -- |
| `0x0009` | int | -- |
| `0x000A` | timestamp | -- |
| `0x000B` | uuid | -- |
| `0x000C` | varchar (`text` on the wire) | -- |
| `0x000D` | varint | -- |
| `0x000E` | timeuuid | -- |
| `0x000F` | inet | -- |
| `0x0010` | date | -- |
| `0x0011` | time | -- |
| `0x0012` | smallint | -- |
| `0x0013` | tinyint | -- |
| `0x0014` | duration | -- |
| `0x0020` | list | one `[option]` element |
| `0x0021` | map | two `[option]`s (key, value) |
| `0x0022` | set | one `[option]` element |
| `0x0030` | udt | `[string]` keyspace, `[string]` name, `[short]` n, then n x (`[string]` field name, `[option]` field type) |
| `0x0031` | tuple | `[short]` n, then n `[option]`s |

- `cql_read_type` returns the top-level code plus a display rendering:
  `int`, `list<varchar>`, `map<varchar, int>`, `tuple<int, varchar>`,
  `udt(ks.addr)`, `custom(com.example.T)`. UDT field definitions are
  consumed (guarded at 4 bytes per field, 2 per tuple element) but not
  retained.
- Nesting is capped at depth 32: a call at depth 33 is
  `cassandra: type nesting depth exceeds limit of 32`.
- An unknown code is `cassandra: unknown type option N at offset M`.

## 8. ERROR body (`0x00`)

```
[int]    code
[string] message
[extras per code]
```

| Code | Name | Extras after the message |
|---|---|---|
| `0x0000` | SERVER_ERROR | -- |
| `0x000A` | PROTOCOL_ERROR | -- |
| `0x0100` | BAD_CREDENTIALS | -- |
| `0x1000` | UNAVAILABLE | `[short]` consistency, `[int]` required, `[int]` alive |
| `0x1001` | OVERLOADED | -- |
| `0x1002` | IS_BOOTSTRAPPING | -- |
| `0x1003` | TRUNCATE_ERROR | -- |
| `0x1100` | WRITE_TIMEOUT | `[short]` consistency, `[int]` received, `[int]` blockfor, `[string]` write type |
| `0x1200` | READ_TIMEOUT | `[short]` consistency, `[int]` received, `[int]` blockfor, `[byte]` data present |
| `0x1300` | READ_FAILURE | `[short]` consistency, `[int]` received, `[int]` blockfor, `[int]` failures, `[byte]` data present |
| `0x1400` | FUNCTION_FAILURE | `[string]` keyspace, `[string]` function, `[string list]` argument types |
| `0x1500` | WRITE_FAILURE | `[short]` consistency, `[int]` received, `[int]` blockfor, `[int]` failures, `[string]` write type |
| `0x2000` | SYNTAX_ERROR | -- |
| `0x2100` | UNAUTHORIZED | -- |
| `0x2200` | INVALID | -- |
| `0x2300` | CONFIG_ERROR | -- |
| `0x2400` | ALREADY_EXISTS | `[string]` keyspace, `[string]` table |
| `0x2500` | UNPREPARED | `[short bytes]` statement id |

- Unknown codes are preserved raw: the code and message are decoded, no
  extras are read, and `cql_error_code_known` reports false.
- `data present` reads one byte and is true when non-zero.
- `cql_error_body_*` accessors return the defaults (0 / false / `""` /
  empty) for extras the code does not define.

## 9. Round-trip example (STARTUP)

`CQL_VERSION=3.0.0` and `COMPRESSION=lz4` as a request:

```
04 00 0000 01 00000028
00 02
00 0B 43 51 4C 5F 56 45 52 53 49 4F 4E   "CQL_VERSION"
00 05 33 2E 30 2E 30                        "3.0.0"
00 0B 43 4F 4D 50 52 45 53 53 49 4F 4E      "COMPRESSION"
00 03 6C 7A 34                              "lz4"
```

Total: 9 header + 40 body = 49 bytes; `cql_frame_consumed` = 49.

## 10. Limits

| Limit | Value |
|---|---|
| Frame header | 9 bytes |
| Body length | signed int32, non-negative |
| Type option nesting | 32 |
| `[string]` byte length | u16; writers mask, callers keep <= 65535 |
| Collection counts | u16; rejected when they cannot fit the remaining bytes |
| Counts written | low 16 bits (callers stay <= 65535) |

## 11. Error catalog

All errors are `Str` values. `N`/`M` are decimal integers, `T` an
offending string, and offsets are byte offsets into the buffer the reader
was created over.

| Message | Raised by |
|---|---|
| `cassandra: truncated input at offset N` | every reader |
| `cassandra: truncated body at offset N: need K bytes, have M` | `cql_read_frame` |
| `cassandra: bad length N at offset M` | `[long string]`, `[bytes]`, `[value]`, `_read_n` |
| `cassandra: bad page size N at offset M` | `cql_read_query` |
| `cassandra: bad metadata flags N at offset M` | `cql_read_rows_metadata` |
| `cassandra: bad column count N at offset M` | `cql_read_rows_metadata` |
| `cassandra: bad row count N at offset M` | `cql_read_result_body` |
| `cassandra: oversized collection at offset N` | all container readers, metadata, QUERY values |
| `cassandra: unsupported protocol version N at offset M` | `cql_read_frame` |
| `cassandra: null bytes value at offset N` | `cql_read_bytes` (and paging state) |
| `cassandra: string contains nul` | `[string]`, `[long string]` |
| `cassandra: invalid utf-8` | `[string]`, `[long string]` |
| `cassandra: unknown type option N at offset M` | `cql_read_type` |
| `cassandra: type nesting depth exceeds limit of 32` | `cql_read_type` |
| `cassandra: unknown result kind N at offset M` | `cql_read_result_body` |
| `cassandra: not-set value in result row at offset N` | `cql_read_result_body` |
| `cassandra: unknown schema change target T at offset M` | `cql_read_result_body` |
| `cassandra: query page size flag mismatch` | `cql_write_query` |
| `cassandra: query paging state flag mismatch` | `cql_write_query` |
| `cassandra: query serial consistency flag mismatch` | `cql_write_query` |
| `cassandra: query timestamp flag mismatch` | `cql_write_query` |
| `cassandra: query value count mismatch` | `cql_write_query` |
| `cassandra: query value count exceeds 65535` | `cql_write_query` |

## 12. Non-goals (not implemented)

- Transport: sockets, TLS, DNS, framing across buffers, multi-frame
  read-ahead.
- Compression: lz4/snappy bodies are never inflated; the flag is reported
  raw.
- Tracing id, custom payload and warning sections of flagged frames.
- AUTHENTICATE / AUTH_CHALLENGE / AUTH_RESPONSE / AUTH_SUCCESS bodies,
  PREPARE / EXECUTE / BATCH / REGISTER / EVENT bodies, and
  OPTIONS / SUPPORTED bodies.
- CQL text parsing, prepared-statement binding, token-aware routing,
  server-side behavior.
- v5 layouts: the v5 keyspace flag bit is defined as a constant but not
  interpreted; v5's "0x0005 result metadata changed" and beta flag
  semantics are out of scope.
