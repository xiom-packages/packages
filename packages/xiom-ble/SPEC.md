# xiom.ble -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.ble`, version `0.1.0`).
Module: `src/ble.xi` (`module xiom.ble`).
Depends on `xiom.std`; the library module uses `xiom.string` only (tests add
`xiom.test`, `xiom.io`, `xiom.string.compare` and `xiom.encoding.hex`).

## Scope

A pure-XIOM (no FFI) codec for the legacy Bluetooth Low Energy
advertising-data payload:

- `ble_parse` walks a buffer of concatenated AD structures until it ends and
  returns an `AdList` index (AD types plus absolute data offsets/lengths);
  unknown AD types are preserved verbatim;
- typed builders produce one complete AD structure each with the length byte
  recomputed (`ble_ad`, `ble_ad_flags`, `ble_ad_name_short`,
  `ble_ad_name_complete`, `ble_ad_tx_power`, `ble_ad_service_uuid16/32/128`,
  `ble_ad_slave_interval`, `ble_ad_service_data16`, `ble_ad_manufacturer`);
- typed decoders read the payload bytes of the supported AD types
  (`ble_decode_flags`, `ble_decode_tx_power`, `ble_decode_uuid16`,
  `ble_decode_uuid32`, `ble_decode_manufacturer_id`,
  `ble_decode_slave_interval`);
- `ble_append_structure` / `ble_append_ad` / `ble_build_from` concatenate
  structures with per-AD validation;
- `ble_validate` enforces the 31-byte legacy advertising limit on a parsed
  payload;
- deterministic `Err(Str)` messages for malformed input and invalid values.

## Non-goals

- **No HCI / sockets / radios.** The package has no `extern "C"` blocks; it
  never touches a controller or a file descriptor.
- **No extended advertising, periodic advertising or advertising sets.** Only
  the classic legacy payload layout is modeled; the 31-byte cap is validated
  but the codec does not build extended headers.
- **No scanning logic, no connection management, no GATT, no pairing, no
  security.** Bytes in, structures out (and back).
- **No zero-length padding.** A zero length byte is an error; per the BLE
  spec such bytes can act as padding in some containers, which this codec
  does not model.
- **No UTF-8 validation or `Str` reconstruction for names.** Names are raw
  bytes; the caller decides the encoding.
- **No duplicate-type merging, canonical ordering or de-duplication.**
  Structures are preserved in wire order.
- **No streaming/incremental parsing.** The whole payload is an in-memory
  `Vec[UInt8]`.
- **No typed error enum.** Errors are fixed `Str` messages.

## AD wire layout

One AD structure:

| Field | Width | Encoding |
|---|---|---|
| length | 1 byte | unsigned, counts the type byte plus the data bytes (`1 + data.len()`) |
| type | 1 byte | AD type (0x01, 0x09, 0xFF, ...) |
| data | `length - 1` bytes | verbatim |

The structure occupies `length + 1` bytes. A payload is structures
concatenated with no padding, terminator or count field. `ble_parse` walks
from offset 0: it reads the length byte, rejects 0, bounds-checks the rest of
the structure against the buffer, records
`data_offsets[i] = position of the first data byte` and
`data_lengths[i] = length - 1`, then continues after the structure. Parsing
stops exactly when the buffer ends.

Multi-byte AD fields are **little-endian** on the air:

| AD type | Field | Encoding |
|---|---|---|
| 0x02 / 0x03 | 16-bit service UUID | 2 bytes LE |
| 0x04 / 0x05 | 32-bit service UUID | 4 bytes LE |
| 0x06 / 0x07 | 128-bit UUID | 16 bytes, on-air order |
| 0x12 | connection interval range | min u16 LE, max u16 LE (units of 1.25 ms) |
| 0x16 | service data 16-bit UUID | UUID u16 LE, then data |
| 0xFF | manufacturer data | company id u16 LE, then data |

### Supported AD types and helpers

| AD type | Name | Builder | Decoder |
|---|---|---|---|
| 0x01 | Flags | `ble_ad_flags` | `ble_decode_flags` |
| 0x02 | Incomplete List of 16-bit Service UUIDs | `ble_ad_service_uuid16(..., false)` | `ble_decode_uuid16` |
| 0x03 | Complete List of 16-bit Service UUIDs | `ble_ad_service_uuid16(..., true)` | `ble_decode_uuid16` |
| 0x04 | Incomplete List of 32-bit Service UUIDs | `ble_ad_service_uuid32(..., false)` | `ble_decode_uuid32` |
| 0x05 | Complete List of 32-bit Service UUIDs | `ble_ad_service_uuid32(..., true)` | `ble_decode_uuid32` |
| 0x06 | Incomplete List of 128-bit UUIDs | `ble_ad_service_uuid128(..., false)` | raw data |
| 0x07 | Complete List of 128-bit UUIDs | `ble_ad_service_uuid128(..., true)` | raw data |
| 0x08 | Shortened Local Name | `ble_ad_name_short` | raw data |
| 0x09 | Complete Local Name | `ble_ad_name_complete` | raw data |
| 0x0A | TX Power Level | `ble_ad_tx_power` | `ble_decode_tx_power` |
| 0x12 | Slave Connection Interval Range | `ble_ad_slave_interval` | `ble_decode_slave_interval` |
| 0x16 | Service Data -- 16-bit UUID | `ble_ad_service_data16` | `ble_decode_uuid16` + raw data |
| 0xFF | Manufacturer Specific Data | `ble_ad_manufacturer` | `ble_decode_manufacturer_id` + raw data |

Any other type byte can be carried with the generic `ble_ad(ad_type, payload)`
and is preserved by `ble_parse`.

## API signatures

All functions are free functions in module `xiom.ble` (no self methods):

```xi
pub type AdList = {
  ad_types: Vec[Int];
  data_offsets: Vec[Int];
  data_lengths: Vec[Int];
}

pub fn ble_parse(data: &Vec[UInt8]) -> Result[AdList, Str]
pub fn ble_count(l: &AdList) -> Int
pub fn ble_type(l: &AdList, i: Int) -> Int
pub fn ble_find(l: &AdList, ad_type: Int) -> Int
pub fn ble_has(l: &AdList, ad_type: Int) -> Bool
pub fn ble_data(data: &Vec[UInt8], l: &AdList, i: Int) -> Result[Vec[UInt8], Str]
pub fn ble_ad_size(l: &AdList, i: Int) -> Int
pub fn ble_total_length(l: &AdList) -> Int

pub fn ble_decode_flags(payload: &Vec[UInt8]) -> Result[Int, Str]
pub fn ble_decode_tx_power(payload: &Vec[UInt8]) -> Result[Int, Str]
pub fn ble_decode_uuid16(payload: &Vec[UInt8]) -> Result[Int, Str]
pub fn ble_decode_uuid32(payload: &Vec[UInt8]) -> Result[Int, Str]
pub fn ble_decode_manufacturer_id(payload: &Vec[UInt8]) -> Result[Int, Str]
pub fn ble_decode_slave_interval(payload: &Vec[UInt8]) -> Result[Vec[Int], Str]

pub fn ble_ad(ad_type: Int, payload: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
pub fn ble_ad_flags(flags: Int) -> Result[Vec[UInt8], Str]
pub fn ble_ad_name_short(name: Str) -> Result[Vec[UInt8], Str]
pub fn ble_ad_name_complete(name: Str) -> Result[Vec[UInt8], Str]
pub fn ble_ad_tx_power(dbm: Int) -> Result[Vec[UInt8], Str]
pub fn ble_ad_service_uuid16(uuid: Int, complete: Bool) -> Result[Vec[UInt8], Str]
pub fn ble_ad_service_uuid32(uuid: Int, complete: Bool) -> Result[Vec[UInt8], Str]
pub fn ble_ad_service_uuid128(uuid: &Vec[UInt8], complete: Bool) -> Result[Vec[UInt8], Str]
pub fn ble_ad_slave_interval(min_units: Int, max_units: Int) -> Result[Vec[UInt8], Str]
pub fn ble_ad_service_data16(uuid: Int, payload: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
pub fn ble_ad_manufacturer(id: Int, payload: &Vec[UInt8]) -> Result[Vec[UInt8], Str]

pub fn ble_append_structure(out: &mut Vec[UInt8], ad: &Vec[UInt8])
pub fn ble_append_ad(out: &mut Vec[UInt8], ad_type: Int, payload: &Vec[UInt8]) -> Result[Unit, Str]
pub fn ble_build_from(types: &Vec[Int], payloads: &Vec[Vec[UInt8]]) -> Result[Vec[UInt8], Str]
pub fn ble_legacy_limit() -> Int
pub fn ble_validate(data: &Vec[UInt8]) -> Result[Unit, Str]
```

## Semantics

`ble_parse(data)`
: Walks structures in wire order. An empty buffer yields `Ok` with zero
  entries. A `length` byte of 0 fails with `ble: zero-length AD structure`.
  When the bytes after the length byte are fewer than `length`, the result is
  `ble: truncated AD structure` if zero bytes remain (the type byte itself is
  missing) and `ble: AD length overruns buffer` if at least the type byte is
  present. `length == 1` is valid and yields an entry with empty data. On
  `Err`, no partial list is returned.

`ble_type(l, i)` / `ble_ad_size(l, i)`
: Return `-1` for `i < 0` or `i >= ble_count(l)`; no error channel.
  `ble_ad_size` is `data_lengths[i] + 2`.

`ble_find(l, ad_type)` / `ble_has(l, ad_type)`
: Linear scan in stream order; the first matching index wins. `ble_find`
  returns `-1` when no entry matches (including an empty list and negative
  `ad_type`); `ble_has` is `ble_find(...) >= 0`.

`ble_data(data, l, i)`
: `Err("ble: index out of range")` for a bad `i`; otherwise the recorded
  span is bounds-checked against `data` and the bytes are copied into a fresh
  vector (`Err("ble: data out of bounds")` when it does not fit).

`ble_total_length(l)`
: Sum of `ble_ad_size(l, i)` over all entries: the byte length of the
  payload those entries describe (`0` for an empty list).

`ble_decode_*`
: Fixed-width decoders validate the payload length first
  (`ble: wrong data length`), then read little-endian (except
  `ble_decode_tx_power`, which sign-extends a single byte).
  `ble_decode_slave_interval` additionally rejects `min > max` with
  `ble: connection interval min above max`. `ble_decode_manufacturer_id`
  accepts 2 or more bytes and reads the first two.

`ble_ad(ad_type, payload)`
: Validates `ad_type` in 0..255 and `payload.len() <= 254` (the length byte
  counts the type byte), then writes `payload.len() + 1`, the type byte and
  the payload.

Typed builders
: All validate their arguments before emitting bytes, then delegate to
  `ble_ad` with the appropriate type. Names are copied byte-for-byte from the
  `Str` (no UTF-8 validation). `complete` selects the complete (odd) or
  incomplete (even) UUID-list AD type. Range checks: flags 0..255, TX power
  -128..127, 16-bit UUID/company id 0..65535, 32-bit UUID 0..4294967295,
  128-bit UUID exactly 16 bytes, name 1..254 bytes, connection interval
  units 6..3200 with `min <= max`, service/manufacturer payload <= 252 bytes.

`ble_append_structure(out, ad)`
: Copies a complete structure (e.g. a builder result) verbatim into `out`.
  It performs no validation and has no error channel; validate the assembled
  payload with `ble_validate`.

`ble_append_ad(out, ad_type, payload)`
: Builds with `ble_ad` first and copies only on success, so `out` is
  byte-for-byte unchanged on `Err` (atomic failure).

`ble_build_from(types, payloads)`
: Validates `types.len() == payloads.len()` first, then appends each entry
  with `ble_append_ad`; the first failing entry surfaces its error unchanged.
  An empty pair of vectors yields `Ok(empty)`. The 31-byte limit is not
  enforced here.

`ble_legacy_limit()`
: Returns 31, the maximum legacy advertising payload size.

`ble_validate(data)`
: Parses with `ble_parse` first (structural errors win), then rejects a
  structurally valid payload longer than 31 bytes with
  `ble: payload exceeds 31-byte legacy limit`. An empty buffer is `Ok`.

## Error string catalog

| Condition | Error text |
|---|---|
| `ble_parse`: length byte is 0 | `ble: zero-length AD structure` |
| `ble_parse`: length byte present, buffer ends before the type byte | `ble: truncated AD structure` |
| `ble_parse`: type byte present, fewer than `length - 1` data bytes remain | `ble: AD length overruns buffer` |
| `ble_data`: `i < 0` or `i >= ble_count(l)` | `ble: index out of range` |
| `ble_data`: recorded span negative or beyond `data.len()` | `ble: data out of bounds` |
| `ble_ad` / `ble_append_ad` / `ble_build_from`: `ad_type` outside 0..255 | `ble: AD type out of range` |
| `ble_ad`: `payload.len() > 254` | `ble: payload too large` |
| `ble_ad_flags`: flags outside 0..255 | `ble: flags out of range` |
| `ble_ad_name_short` / `ble_ad_name_complete`: empty name | `ble: empty local name` |
| `ble_ad_name_short` / `ble_ad_name_complete`: name > 254 bytes | `ble: name too long` |
| `ble_ad_tx_power`: dbm outside -128..127 | `ble: TX power out of range` |
| `ble_ad_service_uuid16` / `ble_ad_service_data16`: uuid outside 0..65535 | `ble: UUID out of range` |
| `ble_ad_service_uuid32`: uuid outside 0..4294967295 | `ble: UUID out of range` |
| `ble_ad_service_uuid128`: `uuid.len() != 16` | `ble: 128-bit UUID must be 16 bytes` |
| `ble_ad_slave_interval`: a unit outside 6..3200 | `ble: connection interval out of range` |
| `ble_ad_slave_interval` / `ble_decode_slave_interval`: `min > max` | `ble: connection interval min above max` |
| `ble_ad_service_data16` / `ble_ad_manufacturer`: `payload.len() > 252` | `ble: payload too large` |
| `ble_ad_manufacturer`: id outside 0..65535 | `ble: manufacturer ID out of range` |
| `ble_build_from`: `types.len() != payloads.len()` | `ble: types/payloads length mismatch` |
| `ble_decode_*`: payload width mismatch | `ble: wrong data length` |
| `ble_validate`: parses OK but `data.len() > 31` | `ble: payload exceeds 31-byte legacy limit` |

Check ordering is fixed and documented:

- `ble_ad`: type range, then payload size.
- name builders: empty, then too long.
- `ble_ad_slave_interval`: `min` range, then `max` range, then `min <= max`.
- `ble_build_from`: vector-length mismatch, then per-entry errors in order.
- `ble_validate`: parse errors (wire order), then the 31-byte limit.
- `ble_type` / `ble_ad_size` have no error channel and return `-1`.

## Boundary values

| Quantity | Limit | Behavior at the edge |
|---|---|---|
| AD data length | 254 bytes | `ble_ad` accepts 254 (length byte 255); 255 is `payload too large` |
| Service/manufacturer payload | 252 bytes | length byte 255 at 252; 253 is `payload too large` |
| Local name | 254 bytes | accepted (structure size 256); 255 is `name too long` |
| TX power | -128..127 | both accepted; outside is `TX power out of range` |
| Connection interval | 6..3200 units | both accepted; outside is `connection interval out of range` |
| Legacy payload | 31 bytes | `ble_validate` accepts 31; 32 is `payload exceeds 31-byte legacy limit` |
| AD length >= 1 | 1 | valid structure with empty data |

## Complexity

| Operation | Complexity |
|---|---|
| `ble_parse` / `ble_validate` | O(data.len()) |
| `ble_count` / `ble_type` / `ble_ad_size` / `ble_legacy_limit` | O(1) |
| `ble_find` / `ble_has` / `ble_total_length` | O(entries) |
| `ble_data` | O(data length) |
| `ble_ad` / typed builders | O(payload length) |
| `ble_append_structure` / `ble_append_ad` | O(structure length) |
| `ble_build_from` | O(total payload bytes) |

## Test plan

`tests/test_conformance.xi` (`module ble_tests`, 20 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Coverage:

1. four-entry hand-built payload (`flags`, complete name, TX power, complete
   16-bit UUID): pinned types, data offsets, data lengths, exact data slices,
   per-entry sizes and total length;
2. unknown AD types (0x55, 0xAA, 0x3D) are preserved, searchable and
   `ble_find`/`ble_has` report first match and absence;
3. empty buffer parses to zero entries; accessors return `-1` / `Err` out of
   range; `ble_total_length` is 0;
4. a zero length byte is `ble: zero-length AD structure`, alone and after a
   valid entry;
5. declared lengths that exceed the remaining bytes are
   `ble: AD length overruns buffer`, including after a valid entry;
6. a dangling length byte is `ble: truncated AD structure`; a length byte
   followed only by a type byte is `ble: AD length overruns buffer`;
7. a length-1 structure is valid with empty data (size 2);
8. flags: exact bytes for 0/6/255, range errors, decode round-trip;
9. names: 0x08/0x09 bytes, empty-name error, 254-byte acceptance and 255-byte
   `name too long` at the length-byte boundary;
10. TX power: `-4`, `127`, `-128` bytes, sign-extended decode, range and
    width errors;
11. 16-bit UUIDs: complete/incomplete types, LE bytes, decode, boundaries
    0/65535, range and width errors;
12. 32-bit UUIDs: complete/incomplete types, LE bytes, decode, boundary
    4294967295, range and width errors;
13. 128-bit UUIDs: 16 verbatim bytes with types 0x06/0x07, exact-length
    errors for 15/17 bytes, parse round-trip;
14. slave connection interval range: `6/12` and `3200/3200` bytes, decode of
    `[min, max]`, range and `min > max` errors on both encode and decode;
15. service data 16: UUID + payload bytes, decode split (UUID vs tail),
    252-byte acceptance and 253-byte rejection;
16. manufacturer data: company id LE + payload, id-only payload, decode,
    range and 253-byte errors;
17. generic `ble_ad` bytes/errors and 254-byte boundary, structure append,
    `ble_append_ad` atomic failure, `ble_build_from` bytes, mismatch, empty
    and per-entry failure;
18. `ble_validate`: 31-byte payload accepted, 32-byte rejected, empty
    accepted, structurally invalid buffer reports the structural error first,
    `ble_legacy_limit` is 31;
19. accessor bounds: `-1` returns, `index out of range`, and
    `data out of bounds` against a short source buffer;
20. build -> parse -> rebuild: six structures (28 bytes) survive
    `ble_build_from` reconstruction byte-for-byte, with `ble_find` indices and
    `ble_validate` verified.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.ble
```

Last verified: compiler 0.61.3,
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Legacy advertising only: no extended/periodic advertising headers, and the
  31-byte cap is enforced by `ble_validate` rather than by the builders.
- Zero length bytes are errors (no padding semantics).
- Codec only: no HCI, sockets, scanning, connections, GATT, pairing or
  security; no device state is modeled.
- Names and UUIDs are raw bytes: no UTF-8 validation, no `Str`
  reconstruction, no 128-bit UUID reordering (on-air order is the caller's).
- Connection intervals are integer units of 1.25 ms (spec range 6..3200);
  no millisecond conversion and no finer rounding.
- Structures keep wire order; duplicate AD types are not merged or
  de-duplicated.
- `AdList` stores offsets into the parse buffer; `ble_data` needs a buffer
  that still holds the recorded spans.
- Errors are fixed `Str` messages; there is no typed error enum.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_list`/`_err_list`/`_ok_bytes`/`_err_bytes`/`_ok_ints`/`_err_ints`/
  `_ok_int`/`_err_int`/`_ok_unit`/`_err_unit` (constructing Results directly
  in other functions miscompiles in this compiler).
- Multi-byte fields are little-endian; extraction and packing are arithmetic
  (modulo/division with a negative-remainder correction), never shifts.
- Every `Vec[UInt8]` byte read is widened with `(b as Int) & 0xFF` before
  entering Int arithmetic, so no UInt8 is compared against a literal >= 128
  (BUG family in v0.61.3).
- Every `Vec[Int]` read is bound to a typed local before use
  (`let n: Int = l.data_lengths[i];`), avoiding the untyped-read lowering
  trap.
- Byte vectors are bound to locals before being passed by reference; no
  `&struct.field` reference is passed to a `&Vec[UInt8]` parameter.
- Str values are compared with `xiom.string.compare.str_compare` in the
  tests (BUG 17: `==` on a Str read from a `Vec` lowers to a pointer
  comparison).
- No `Vec[StructType]`, no `Vec[Float64]`, no methods, no lambdas, no
  indexed `Vec[fn]` dispatch; tests call their functions directly.
- The package declares no `extern "C"` blocks (no FFI) and no new
  dependencies; the only dependency is `xiom.std`.
