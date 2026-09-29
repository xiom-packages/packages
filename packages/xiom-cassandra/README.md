# xiom.cassandra

> **Status:** `incubating` -- conformance-tested (24/24); published at `v0.1.1` on the XIOM registry.
> **Scope:** the 9-byte frame header, the protocol primitives and
> containers, and the request/response bodies of STARTUP, QUERY, RESULT and
> ERROR. No sockets, no TLS, no compression, no authentication exchange,
> no CQL text analysis, no server.
> **Deps:** `xiom.std` only (the library module imports `xiom.string`,
> `xiom.string.builder`, `xiom.string.compare` and `xiom.convert`; the
> tests additionally use `xiom.test`, `xiom.io` and `xiom.encoding.hex`).

## What it is

`xiom.cassandra` is a pure-XIOM, dependency-free **structural** codec for
the Apache Cassandra native protocol, version 4. It turns the bytes a
transport would carry into typed XIOM values and back: it never performs
I/O, never fragments frames across buffers, and never looks inside a CQL
statement. Callers supply and receive byte vectors.

Implemented layers:

- **Frame header** (9 bytes): version byte (`0x04` request / `0x84`
  response; the v3 pair `0x03`/`0x83` is recognized and reported), flags
  byte (compression `0x01`, tracing `0x02`, custom payload `0x04`,
  warning `0x08`, use beta `0x10`), signed int16 stream id, opcode byte
  and int32 body length. Unknown opcodes are preserved raw and named
  `"UNKNOWN"`.
- **Opcode table** (16 entries): ERROR, STARTUP, READY, AUTHENTICATE,
  OPTIONS, SUPPORTED, QUERY, RESULT, PREPARE, EXECUTE, REGISTER, EVENT,
  BATCH, AUTH_CHALLENGE, AUTH_RESPONSE, AUTH_SUCCESS (`0x04` is unused).
- **Primitives**: `[int]`, `[long]`, `[byte]` (unsigned 0..255), `[short]`,
  `[string]` (u16 length + UTF-8), `[long string]`, `[bytes]`, `[value]`
  (null `-1`, not set `-2`), `[short bytes]`, `[string list]`,
  `[string map]`, `[string multimap]`, `[bytes map]`.
- **STARTUP**: `[string map]`.
- **QUERY**: `[long string]` + consistency `[short]` + flags `[byte]`,
  with the optional value, page-size, paging-state, serial-consistency and
  timestamp sections; consistency values and flag bits are preserved raw.
- **RESULT**: kinds VOID, ROWS (metadata + row-major cells), SET_KEYSPACE,
  PREPARED (id + prepared metadata + result metadata) and SCHEMA_CHANGE
  (KEYSPACE / TABLE / TYPE / FUNCTION / AGGREGATE), including the column
  type-option renderer (simple types, `list<T>`, `set<T>`, `map<K, V>`,
  `tuple<...>`, `udt(ks.name)`, `custom(class)`).
- **ERROR**: code + message + the extras each code defines (UNAVAILABLE,
  WRITE_TIMEOUT, READ_TIMEOUT, READ_FAILURE, FUNCTION_FAILURE,
  WRITE_FAILURE, ALREADY_EXISTS, UNPREPARED), with the full
  `0x0000`..`0x2500` code table.

Every reader is bounds-checked and reports the **byte offset** of the
failing read. Negative lengths, truncated input and hostile
oversized counts are rejected with deterministic messages (see SPEC.md).

## Quick start

Parse one frame, then decode its STARTUP body:

```xi
use xiom.cassandra;

var r = cql_reader_new(bytes_from_transport);
let fr = cql_read_frame(&mut r);
if fr.is_ok {
  let f: CqlFrame = fr.value;
  let body: Vec[UInt8] = cql_frame_body(&f);
  var br = cql_reader_new(body);
  let sm = cql_read_startup(&mut br);
  if sm.is_ok {
    let m: CqlStringMap = sm.value;
    if cql_startup_has_cql_version(&m) { /* ... */ }
  }
  // cql_frame_consumed(&f) == 9 + body length
}
```

Build a QUERY body and wrap it in a request frame:

```xi
var w = cql_writer_new();
cql_write_long_string(&mut w, "SELECT * FROM ks.t WHERE id = ?");
cql_write_short(&mut w, cql_consistency_one());
cql_write_byte(&mut w, cql_query_flag_values());
cql_write_short(&mut w, 1);
let value: Vec[UInt8] = encoded_id;
cql_write_value(&mut w, cql_value_kind_bytes(), &value);
let body: Vec[UInt8] = cql_writer_bytes(&w);

var fw = cql_writer_new();
cql_write_frame(&mut fw, cql_version_request_v4(), 0, 0, cql_opcode_query(), &body);
```

Read a RESULT ROWS body:

```xi
var r = cql_reader_new(result_body_bytes);
let rr = cql_read_result_body(&mut r);
if rr.is_ok {
  let res: CqlResult = rr.value;
  // cql_result_rows_count, cql_result_column_count, cql_result_column_name,
  // cql_result_column_type_name, cql_result_cell_count, cql_result_cell_kind,
  // cql_result_cell
}
```

## API map

The module exposes 248 public functions, all prefixed `cql_`; the full
byte-level tables live in `SPEC.md`.

| Group | Representative functions |
|---|---|
| Versions / direction | `cql_protocol_version`, `cql_version_request_v4`, `cql_version_known`, `cql_version_is_response`, `cql_version_protocol` |
| Frame | `cql_read_frame`, `cql_parse_frame`, `cql_write_frame`, `cql_write_frame_header`, `cql_frame_consumed`, `cql_frame_body`, `cql_frame_opcode` |
| Flags / opcodes | `cql_flag_*`, `cql_flags_known`, `cql_opcode_*`, `cql_opcode_known`, `cql_opcode_name` |
| Consistency | `cql_consistency_*`, `cql_consistency_known`, `cql_consistency_name` |
| Reader / writer | `cql_reader_new`, `cql_reader_pos`, `cql_reader_pos_mut`, `cql_reader_remaining`, `cql_writer_new`, `cql_writer_len`, `cql_writer_bytes` |
| Primitives (read) | `cql_read_int`, `cql_read_long`, `cql_read_byte`, `cql_read_short`, `cql_read_string`, `cql_read_long_string`, `cql_read_bytes`, `cql_read_value`, `cql_read_short_bytes` |
| Containers (read) | `cql_read_string_list`, `cql_read_string_map`, `cql_read_string_multimap`, `cql_read_bytes_map` |
| Primitives (write) | `cql_write_int`, `cql_write_long`, `cql_write_byte`, `cql_write_short`, `cql_write_string`, `cql_write_long_string`, `cql_write_bytes`, `cql_write_value`, `cql_write_short_bytes` |
| Containers (write) | `cql_write_string_list`, `cql_write_string_map`, `cql_write_string_multimap`, `cql_write_bytes_map` |
| STARTUP | `cql_read_startup`, `cql_write_startup`, `cql_startup_has_cql_version` |
| QUERY | `cql_read_query`, `cql_write_query`, `cql_query_flag_*`, `cql_query_text`, `cql_query_value_count`, `cql_query_value_name`, `cql_query_value_kind`, `cql_query_value_data` |
| RESULT | `cql_read_result_body`, `cql_result_kind`, `cql_result_*` accessors, `cql_read_rows_metadata`, `cql_meta_*` accessors, `cql_read_type`, `cql_type_info_*` |
| ERROR | `cql_read_error_body`, `cql_error_body_*` accessors, `cql_error_code_*`, `cql_error_code_known`, `cql_error_code_name` |

Types: `CqlWriter`, `CqlReader`, `CqlFrame`, `CqlValue`, `CqlStringList`,
`CqlStringMap`, `CqlStringMultiMap`, `CqlBytesMap`, `CqlQuery`,
`CqlTypeInfo`, `CqlRowsMetadata`, `CqlResult`, `CqlErrorBody`.

## Error model

Every fallible function returns `Result[T, Str]`; errors are deterministic
strings of the form `cassandra: <what> at offset N`:

- `cassandra: truncated input at offset N` -- a read ran past the end;
- `cassandra: truncated body at offset N: need K bytes, have M`;
- `cassandra: bad length N at offset M` -- negative wire length;
- `cassandra: bad metadata flags N at offset M` / `bad column count` /
  `bad row count` / `bad page size`;
- `cassandra: oversized collection at offset N` -- a hostile count that
  cannot fit the remaining bytes;
- `cassandra: string contains nul` / `cassandra: invalid utf-8`;
- `cassandra: null bytes value at offset N` -- a null `[bytes]` where the
  reader needs a payload (use `cql_read_value` for null/not-set);
- `cassandra: unsupported protocol version N at offset 0`;
- `cassandra: unknown result kind N at offset M` /
  `cassandra: unknown schema change target T at offset M` /
  `cassandra: unknown type option N at offset M`;
- `cassandra: type nesting depth exceeds limit of 32`;
- `cassandra: query page size flag mismatch` and the other QUERY
  writer flag/value-count mismatches.

## Tests

```
xiom --run tests/test_conformance.xi
```

24 checks, all synthetic buffers built in-test (hex literals plus the
package's own writers). Expected: 24 `[PASS]` lines, then
`xiom.cassandra: all tests passed`, exit 0. The port harness reports:

```
port: PASS (passed=24 failed=0 program_exit=0 exit=0)
```

## Boundaries and non-goals

- No transport: bytes in, bytes out. Frame segmentation across buffers is
  the caller's job (`cql_read_frame` consumes exactly one frame).
- No compression codec: the compression flag is reported, bodies are never
  inflated, and the `[string map]`/`[bytes map]` custom-payload and warning
  sections of flagged frames are not decoded.
- No AUTHENTICATE/AUTH_CHALLENGE/AUTH_RESPONSE/AUTH_SUCCESS bodies, no
  PREPARE/EXECUTE/BATCH/REGISTER/EVENT bodies, no OPTIONS/SUPPORTED bodies.
- No CQL parser and no server-side behavior.
- `[string]` values must be valid UTF-8 and NUL-free; v0.61.3's
  `sb_to_str` aborts on a `0x00`, so NUL bytes are rejected at the
  boundary. Use the `[bytes]` readers for arbitrary byte payloads.
- UDT type options are consumed and rendered as `udt(keyspace.name)`;
  individual field definitions are not retained.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
