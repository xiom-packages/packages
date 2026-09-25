# xiom.can -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.can`, version `0.1.0`).
Module: `src/can.xi` (`module xiom.can`).
Depends on `xiom.std`; the library module imports nothing from it (tests add
`xiom.test`, `xiom.io`, `xiom.string`, `xiom.string.compare`,
`xiom.encoding.hex`).

## Scope

A pure-XIOM (no FFI) codec for one classic CAN 2.0 frame:

- `CanFrame` -- a plain struct with the identifier, its width (standard
  11-bit / extended 29-bit), the RTR flag, the DLC and the payload bytes;
- `can_encode` / `can_encode_into` -- frame to fixed 16-byte container;
- `can_decode` -- container to frame, first 16 bytes only;
- `can_validate`, `can_new`, `can_data_frame`, `can_remote_frame` --
  canonical-frame invariants and construction;
- `can_max_id`, `can_id_ok`, `can_id_word`, `can_encoded_size`,
  `can_is_extended`, `can_is_remote`, `can_payload_len`, `can_data_get` --
  accessors and identifier helpers;
- `can_equal` -- structural frame equality;
- deterministic `Err(Str)` messages for every invalid frame and container.

The container layout follows the classic SocketCAN `can_frame` field order
(ID word, DLC, three reserved bytes, eight data bytes) with multi-byte
fields fixed to big-endian.

## Non-goals

- **CAN-FD.** No 64-byte payloads, no DLC-to-length table for 9..15, no
  bit-rate switching; payloads are exactly their DLC and at most 8 bytes.
- **Bus/socket I/O.** No controller, socket, netlink or file access; the
  codec works on in-memory `Vec[UInt8]`.
- **Bus arbitration, bit timing, CRC, bit stuffing, acknowledgement.** The
  frame content is modeled, not the wire event.
- **Error frames and overload frames.** ID-word bit 29 (SocketCAN error
  flag) is rejected.
- **Timestamps, channel numbers, bus state.**
- **Text formats.** No candump/ASC/BLF parsing or formatting.
- **Streaming decode.** `can_decode` reads the first 16 bytes and ignores
  anything after them; it does not report a frame count or split a buffer
  for the caller.

## Frame model

| Field | Type | Meaning |
|---|---|---|
| `id` | `Int` | 0..2047 for a standard frame, 0..536870911 for an extended frame |
| `extended` | `Bool` | `true` = 29-bit identifier (CAN 2.0B), `false` = 11-bit (CAN 2.0A) |
| `rtr` | `Bool` | `true` = remote transmission request (no payload) |
| `dlc` | `Int` | 0..8; on a remote frame the requested payload length |
| `data` | `Vec[UInt8]` | payload; exactly `dlc` bytes on a data frame, empty on a remote frame |

A canonical (valid) frame satisfies all of:

1. `0 <= id <= can_max_id(extended)`;
2. `data.len() <= 8`;
3. `0 <= dlc <= 8`;
4. if `rtr` then `data.len() == 0`;
5. otherwise `data.len() == dlc`.

## Container layout

One frame is a fixed 16 bytes; there is no count, terminator or padding
beyond the fixed size.

| Offset | Size | Field | Encoding |
|---|---|---|---|
| 0 | 4 | CAN ID word | unsigned big-endian 32-bit |
| 4 | 1 | DLC | raw byte, 0..8 |
| 5 | 3 | reserved | must be `00 00 00` |
| 8 | 8 | data | payload, zero-padded to 8 bytes |

ID-word bit fields (bit 31 = most significant bit of byte 0):

| Bit | Name | Meaning |
|---|---|---|
| 31 | EFF | `1` = extended (29-bit) identifier |
| 30 | RTR | `1` = remote transmission request |
| 29 | ERR | `1` = error-frame flag; always rejected by `can_decode` |
| 28..0 | ID | identifier; a standard frame must have bits 28..11 zero |

Examples:

| Byte string | Frame |
|---|---|
| `0000012302000000dead000000000000` | standard data, id `0x123`, DLC 2, `DE AD` |
| `92345678080000000102030405060708` | extended data, id `0x12345678`, DLC 8 |
| `400007ff080000000000000000000000` | standard RTR, id `0x7FF`, requested DLC 8 |
| `dfffffff000000000000000000000000` | extended RTR, id `0x1FFFFFFF`, requested DLC 0 |

## API contract

All functions are free functions in module `xiom.can` (no self methods):

```xi
pub type CanFrame = {
  id: Int;
  extended: Bool;
  rtr: Bool;
  dlc: Int;
  data: Vec[UInt8];
}

pub fn can_max_id(extended: Bool) -> Int
pub fn can_id_ok(id: Int, extended: Bool) -> Bool
pub fn can_id_word(f: &CanFrame) -> Int
pub fn can_encoded_size() -> Int
pub fn can_validate(f: &CanFrame) -> Result[Unit, Str]
pub fn can_new(id: Int, extended: Bool, rtr: Bool, dlc: Int, data: &Vec[UInt8]) -> Result[CanFrame, Str]
pub fn can_data_frame(id: Int, extended: Bool, data: &Vec[UInt8]) -> Result[CanFrame, Str]
pub fn can_remote_frame(id: Int, extended: Bool, dlc: Int) -> Result[CanFrame, Str]
pub fn can_encode_into(out: &mut Vec[UInt8], f: &CanFrame) -> Result[Unit, Str]
pub fn can_encode(f: &CanFrame) -> Result[Vec[UInt8], Str]
pub fn can_decode(bytes: &Vec[UInt8]) -> Result[CanFrame, Str]
pub fn can_is_extended(f: &CanFrame) -> Bool
pub fn can_is_remote(f: &CanFrame) -> Bool
pub fn can_payload_len(f: &CanFrame) -> Int
pub fn can_data_get(f: &CanFrame, i: Int) -> Int
pub fn can_equal(a: &CanFrame, b: &CanFrame) -> Bool
```

`can_max_id(extended)`
: `2047` for standard, `536870911` for extended.

`can_id_ok(id, extended)`
: `true` when `0 <= id <= can_max_id(extended)`; `false` otherwise
  (including negative ids).

`can_id_word(f)`
: `f.id + 2^31` when `f.extended`, `+ 2^30` when `f.rtr`; no validation,
  meaningful for a canonical frame.

`can_encoded_size()`
: `16`.

`can_validate(f)`
: Applies the five canonical rules in the order below and returns `Ok(())`
  or the first error. No partial state; the frame is not modified.

`can_new(id, extended, rtr, dlc, data)`
: Copies `data`, builds the frame from all five arguments and returns the
  `can_validate` result. The copied payload is always owned by the frame.

`can_data_frame(id, extended, data)`
: `can_new(id, extended, false, data.len(), data)`, so the DLC is derived
  from the payload; a payload longer than 8 bytes is an error.

`can_remote_frame(id, extended, dlc)`
: `can_new(id, extended, true, dlc, empty)`; the payload is always empty.

`can_encode_into(out, f)`
: Validates first. On success appends the ID word (four big-endian bytes),
  the DLC byte, three zero reserved bytes and eight data bytes -- the first
  `dlc` are the payload (zero for a remote frame), the rest zero. On `Err`,
  `out` is byte-for-byte unchanged (atomic failure).

`can_encode(f)`
: `can_encode_into` into a fresh vector; on success the result has length
  16.

`can_decode(bytes)`
: Requires at least 16 bytes; decodes the first 16 in the order below and
  ignores everything after them. A remote frame comes back with an empty
  payload and its DLC preserved.

`can_is_extended(f)` / `can_is_remote(f)`
: `f.extended` / `f.rtr`.

`can_payload_len(f)`
: `f.data.len()` (0 for a canonical remote frame).

`can_data_get(f, i)`
: Payload byte `i` widened to 0..255; `-1` when `i < 0` or
  `i >= f.data.len()` (so every index of a remote frame is `-1`).

`can_equal(a, b)`
: `true` when `id`, `extended`, `rtr`, `dlc` and the payload byte sequence
  all match; `false` otherwise.

## Validation order

`can_validate` (and therefore `can_new`, `can_data_frame`, `can_remote_frame`,
`can_encode`, `can_encode_into`) checks in exactly this order and reports the
first failure:

1. `id < 0` -> `can: negative identifier`;
2. identifier above `can_max_id(extended)` -> `can: identifier exceeds
   standard range` / `can: identifier exceeds extended range`;
3. `data.len() > 8` -> `can: payload exceeds 8 bytes`;
4. `dlc < 0 || dlc > 8` -> `can: invalid dlc`;
5. `rtr && data.len() != 0` -> `can: remote frame carries data`;
6. `!rtr && data.len() != dlc` -> `can: data length does not match dlc`.

## Decode order

`can_decode` reads the four ID-word bytes, extracts EFF, RTR and ERR by
descending-bit subtraction, then checks in exactly this order:

1. `bytes.len() < 16` -> `can: truncated frame`;
2. ID-word bit 29 set -> `can: error frame flag set`;
3. standard frame with `id > 2047` -> `can: identifier exceeds standard
   range`;
4. DLC byte above 8 -> `can: invalid dlc`;
5. byte 5, 6 or 7 nonzero -> `can: nonzero reserved byte`;
6. remote frame with any nonzero byte at offsets 8..15 -> `can: nonzero rtr
   data byte`;
7. data frame with any nonzero byte at offsets `8 + dlc`..15 -> `can:
   nonzero padding byte`.

## Error string catalog

| Condition | Error text |
|---|---|
| `can_validate`: `id < 0` | `can: negative identifier` |
| `can_validate`: standard `id > 2047` | `can: identifier exceeds standard range` |
| `can_validate`: extended `id > 536870911` | `can: identifier exceeds extended range` |
| `can_validate`: `data.len() > 8` | `can: payload exceeds 8 bytes` |
| `can_validate`: `dlc < 0` or `dlc > 8` | `can: invalid dlc` |
| `can_validate`: `rtr` with a nonempty payload | `can: remote frame carries data` |
| `can_validate`: data frame with `data.len() != dlc` | `can: data length does not match dlc` |
| `can_decode`: `bytes.len() < 16` | `can: truncated frame` |
| `can_decode`: ID-word bit 29 set | `can: error frame flag set` |
| `can_decode`: standard frame with bits 28..11 nonzero | `can: identifier exceeds standard range` |
| `can_decode`: DLC byte above 8 | `can: invalid dlc` |
| `can_decode`: reserved byte nonzero | `can: nonzero reserved byte` |
| `can_decode`: data frame, byte past the DLC nonzero | `can: nonzero padding byte` |
| `can_decode`: remote frame, data byte nonzero | `can: nonzero rtr data byte` |

`can_max_id`, `can_id_ok`, `can_id_word`, `can_encoded_size`,
`can_is_extended`, `can_is_remote`, `can_payload_len`, `can_data_get` and
`can_equal` have no error channel; `can_data_get` reports an out-of-range
index as `-1`.

## Complexity

| Operation | Complexity |
|---|---|
| `can_max_id` / `can_id_ok` / `can_id_word` / `can_encoded_size` | O(1) |
| `can_is_extended` / `can_is_remote` / `can_payload_len` / `can_data_get` | O(1) |
| `can_validate` / `can_new` / `can_data_frame` / `can_remote_frame` | O(payload) |
| `can_encode_into` / `can_encode` | O(payload) |
| `can_decode` | O(payload) |
| `can_equal` | O(payload) |

## Test plan

`tests/test_conformance.xi` (`module can_tests`, 22 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line and
returns the failure count). Coverage:

1. standard data frame encodes to the pinned 16 bytes (`00000123 02 ...`);
2. extended data frame with a full 8-byte payload encodes exactly;
3. standard and extended remote frames encode exactly (`0x7FF` DLC 8,
   `0x1FFFFFFF` DLC 0);
4. identifier/DLC boundaries (`0`, `2047`, `536870911`, DLC 0) encode to
   pinned bytes;
5. hand-built standard and extended data containers decode field by field;
6. remote containers decode with an empty payload and kept DLC;
7. nonzero padding beyond the DLC and nonzero RTR data bytes are Err;
8. DLC bytes above 8 (9, 15, 16, 255) are Err; DLC 8 with zero data is
   valid;
9. nonzero reserved bytes 5, 6 and 7 are Err;
10. every buffer shorter than 16 bytes is `can: truncated frame`; 16 bytes
    is not;
11. identifier range, error-flag and flag-bit precedence (bit 29, standard
    frames with high bits, extended boundaries);
12. `can_validate` reports identifier, payload, DLC and data errors in
    order, and accepts canonical frames;
13. constructors (`can_data_frame`, `can_remote_frame`, `can_new`) accept
    canonical frames and surface the catalog;
14. `can_equal` compares id, type, RTR, DLC and payload, and is symmetric;
15. encode -> decode round-trips preserve every field for seven frames;
16. `can_encode_into` appends exactly after existing bytes and leaves the
    buffer untouched on Err;
17. accessors pin identifier words (`291`, `+2^31`, `+2^30`, both), lengths
    and payload bytes;
18. decode -> encode reproduces six canonical containers byte-for-byte;
19. a small identifier marked extended round-trips as a 2.0B frame;
20. bytes after the first 16 are ignored;
21. the 29-bit identifier maximum decodes and re-encodes;
22. extended frames with payload lengths 0..8 all round-trip.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.can
```

Last verified: compiler 0.61.3,
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Classic CAN 2.0 only: no CAN-FD, DLC above 8 is an error.
- Error frames, overload frames, timestamps, channels and bus state are not
  modeled.
- The container is a fixed 16-byte big-endian serialization, not a native
  `struct can_frame` memory image; converting to/from a socket's native
  layout is the caller's responsibility.
- `can_decode` is strict about the canonical form (reserved bytes, unused
  identifier bits, DLC padding, RTR data); uninitialized OS padding must be
  cleared by the caller.
- `can_decode` ignores bytes after the first 16, so a buffer holding several
  containers must be sliced by the caller.
- `can_new` takes `dlc` and `data` independently; a mismatch is reported by
  validation rather than silently corrected.
- `CanFrame` is a plain value type: payload copies are O(payload), and the
  struct is not thread-safe.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers `_ok_frame`,
  `_err_frame`, `_ok_bytes`, `_err_bytes`, `_ok_unit`, `_err_unit`
  (constructing Results directly inside struct-returning functions
  miscompiles in this compiler).
- The 32-bit ID word is assembled by multiplication and split by
  arithmetic (modulo/division with a negative-remainder correction); no
  shift and no bitwise operator is used, because bitwise AND on operands
  with bit 31 set miscompiles (same bug documented in `xiom.bitfield` and
  `xiom.convert.base58`).
- Every `Vec[UInt8]` byte read is widened with `(b as Int) & 0xFF` before
  entering Int arithmetic.
- `&struct.field` is never passed directly to a `&Vec[UInt8]` parameter (it
  lowers to an empty vector); fields are bound to locals first.
- Str values in the tests are compared through
  `xiom.string.compare.str_compare` (BUG 17: `==` on a Str read from a
  `Vec` lowers to a pointer comparison).
- The package declares no `extern "C"` blocks (no FFI).
