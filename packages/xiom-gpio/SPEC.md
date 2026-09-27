# xiom.gpio -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3;
21/21 conformance checks; not published).
Manifest: `package.xi` (`xiom.gpio`, version `0.1.0`).
Module: `src/gpio.xi` (`module xiom.gpio`).
Depends on `xiom.std`; the library module imports `xiom.convert`,
`xiom.string` and `xiom.string.builder` from it (tests add `xiom.test`,
`xiom.io`, `xiom.string.compare` and `xiom.encoding.hex`).

## Scope

A pure-XIOM, in-memory structure codec for the Linux GPIO character-device
uAPI version 2 as defined by `include/uapi/linux/gpio.h`:

- `gpiochip_info` -- the 68-byte chip descriptor (name, label, line count);
- `gpio_v2_line_info` -- the 256-byte line descriptor (name, consumer,
  line offset, flag bitmap, attribute array);
- the v2 line flag bits 0..12 and their names, plus the line-changed type
  enum (which carries the uAPI's REQUESTED value);
- `gpio_v2_line_attribute` (16 bytes) and `gpio_v2_line_config`
  (272 bytes) -- the FLAGS, OUTPUT_VALUES and DEBOUNCE attribute kinds;
- `gpio_v2_line_request` (592 bytes) -- offsets, consumer string, embedded
  config, num_lines, event_buffer_size and fd, with encode and decode;
- `gpio_v2_line_event` (48 bytes) -- 64-bit timestamp, event id, line
  offset and both sequence numbers;
- `gpio_v2_line_values` (16 bytes) -- the bits/mask pair used for default
  output values (the v2 equivalent of the v1 `default_values` array).

All decoders require the exact struct size, reject truncated and oversized
buffers, reject nonzero padding, reject names without a NUL inside their
32-byte field, and reject inconsistent `num_attrs` / `num_lines` / offsets
/ OUTPUT_VALUES bitmaps. Errors are deterministic `Err(Str)` messages that
carry the byte offset of the offending field.

### Endianness

The layout is little-endian throughout (`u32` and `u64` fields are composed
with division/multiplication byte by byte, 64-bit values via explicit byte
multiplication and a bit-63 branch). The real ioctl interface passes the
structs in native byte order; this package intentionally fixes one explicit
layout (LE) so buffers can be built and checked on any host. This is the
one deliberate deviation from the kernel wire semantics and it is pinned by
the conformance suite.

## Non-goals

- **Device access.** No `open`, ioctl, `read`, `poll`, file descriptors or
  `/dev/gpiochip*` paths; the `fd` field is data, not a live descriptor.
- **FFI and libgpiod.** No C interop and no dependency on libgpiod; this
  is a self-contained structure codec.
- **ABI v1.** The deprecated `gpiolib`/`gpiohandle`/`gpioevent` v1
  structures are out of scope. Only the v2 structs above are implemented.
- **`gpio_v2_line_info_changed`.** The watch/changed struct is not decoded;
  only its change-type constants are exposed for naming.
- **Timing, edge semantics and electrical behavior.** Timestamps, flags and
  values are decoded as data; no clock source, debounce engine, bias
  behavior or edge filtering is modeled.
- **Request validation against a chip.** `num_lines` is checked against
  1..64 and offsets for uniqueness, but offsets cannot be checked against a
  chip's real line count because no chip is known; the kernel does that at
  ioctl time.
- **Nonzero tail slots.** Unused attribute slots, unused offset slots and
  bytes after a string's NUL are ignored on decode (the kernel zero-fills
  them, but only the documented fields are validated).

## Layouts

Offsets are byte offsets from the start of the struct; all multi-byte
fields are little-endian. Sizes match the 64-bit kernel ABI.

### gpiochip_info (68 bytes)

| Offset | Size | Field | Notes |
|---|---|---|---|
| 0 | 32 | `name` | C string, NUL-padded, trimmed at first NUL |
| 32 | 32 | `label` | C string, NUL-padded, may be empty |
| 64 | 4 | `lines` | u32 line count |

### gpio_v2_line_attribute (16 bytes)

| Offset | Size | Field | Notes |
|---|---|---|---|
| 0 | 4 | `id` | 1 = FLAGS, 2 = OUTPUT_VALUES, 3 = DEBOUNCE |
| 4 | 4 | `padding` | must be zero |
| 8 | 8 | union | `flags`/`values` as u64, or `debounce_period_us` as the low u32 |

For DEBOUNCE the upper four bytes of the union are union space: they are
ignored on decode and written as zero on encode.

### gpio_v2_line_config_attribute (24 bytes)

| Offset | Size | Field |
|---|---|---|
| 0 | 16 | `attr` (`gpio_v2_line_attribute`) |
| 16 | 8 | `mask` (u64 line bitmap) |

### gpio_v2_line_config (272 bytes)

| Offset | Size | Field | Notes |
|---|---|---|---|
| 0 | 8 | `flags` | default flag bitmap for all lines |
| 8 | 4 | `num_attrs` | 0..10 |
| 12 | 20 | `padding[5]` | must be zero |
| 32 | 240 | `attrs[10]` | ten 24-byte config attributes |

### gpio_v2_line_request (592 bytes)

| Offset | Size | Field | Notes |
|---|---|---|---|
| 0 | 256 | `offsets[64]` | u32 line offsets; only the first `num_lines` are read |
| 256 | 32 | `consumer` | C string, NUL-padded, <= 31 bytes plus NUL |
| 288 | 272 | `config` | `gpio_v2_line_config` |
| 560 | 4 | `num_lines` | 1..64 |
| 564 | 4 | `event_buffer_size` | u32 |
| 568 | 20 | `padding[5]` | must be zero |
| 588 | 4 | `fd` | u32 image of the kernel `__s32` descriptor field |

### gpio_v2_line_info (256 bytes)

| Offset | Size | Field | Notes |
|---|---|---|---|
| 0 | 32 | `name` | C string, NUL-padded |
| 32 | 32 | `consumer` | C string, NUL-padded |
| 64 | 4 | `offset` | decoded as `line_offset` |
| 68 | 4 | `num_attrs` | 0..10 |
| 72 | 8 | `flags` | u64 flag bitmap |
| 80 | 160 | `attrs[10]` | ten 16-byte attributes |
| 240 | 16 | `padding[4]` | must be zero |

### gpio_v2_line_event (48 bytes)

| Offset | Size | Field | Notes |
|---|---|---|---|
| 0 | 8 | `timestamp_ns` | u64 little-endian, decoded as `timestamp_ns` |
| 8 | 4 | `id` | 1 = rising, 2 = falling |
| 12 | 4 | `offset` | decoded as `line_offset` |
| 16 | 4 | `seqno` | decoded as `global_seqno` |
| 20 | 4 | `line_seqno` | decoded as `line_seqno` |
| 24 | 24 | `padding[6]` | must be zero |

### gpio_v2_line_values (16 bytes)

| Offset | Size | Field |
|---|---|---|
| 0 | 8 | `bits` (u64) |
| 8 | 8 | `mask` (u64) |

## Flag bit table (`gpio_v2_line_info.flags`, config and attribute flags)

Bit positions are the uAPI enum values; decoding uses `flags / 2^bit % 2`
(division and modulo only, never a sign-bit operation).

| Bit | Constant | Value | Meaning |
|---|---|---|---|
| 0 | `GPIO_V2_LINE_FLAG_USED` | 1 | line is not available for request |
| 1 | `GPIO_V2_LINE_FLAG_ACTIVE_LOW` | 2 | active state is physical low |
| 2 | `GPIO_V2_LINE_FLAG_INPUT` | 4 | line is an input |
| 3 | `GPIO_V2_LINE_FLAG_OUTPUT` | 8 | line is an output |
| 4 | `GPIO_V2_LINE_FLAG_EDGE_RISING` | 16 | detects rising edges |
| 5 | `GPIO_V2_LINE_FLAG_EDGE_FALLING` | 32 | detects falling edges |
| 6 | `GPIO_V2_LINE_FLAG_OPEN_DRAIN` | 64 | open drain output |
| 7 | `GPIO_V2_LINE_FLAG_OPEN_SOURCE` | 128 | open source output |
| 8 | `GPIO_V2_LINE_FLAG_BIAS_PULL_UP` | 256 | pull-up bias |
| 9 | `GPIO_V2_LINE_FLAG_BIAS_PULL_DOWN` | 512 | pull-down bias |
| 10 | `GPIO_V2_LINE_FLAG_BIAS_DISABLED` | 1024 | bias disabled |
| 11 | `GPIO_V2_LINE_FLAG_EVENT_CLOCK_REALTIME` | 2048 | events use CLOCK_REALTIME |
| 12 | `GPIO_V2_LINE_FLAG_EVENT_CLOCK_HTE` | 4096 | events use the HTE clock |

`GPIO_V2_LINE_FLAG_KNOWN_MASK` = 8191 (bits 0..12). `REQUESTED` is **not**
a v2 line flag; the uAPI's REQUESTED value is the line-changed type below.

### Line-changed types

| Value | Constant | Name |
|---|---|---|
| 1 | `GPIO_V2_LINE_CHANGED_REQUESTED` | `"requested"` |
| 2 | `GPIO_V2_LINE_CHANGED_RELEASED` | `"released"` |
| 3 | `GPIO_V2_LINE_CHANGED_CONFIG` | `"config"` |

### Event ids

| Value | Constant | Name |
|---|---|---|
| 1 | `GPIO_V2_LINE_EVENT_RISING_EDGE` | `"rising edge"` |
| 2 | `GPIO_V2_LINE_EVENT_FALLING_EDGE` | `"falling edge"` |

## Attribute ids

| Id | Constant | Union field | Decode |
|---|---|---|---|
| 1 | `GPIO_V2_LINE_ATTR_ID_FLAGS` | u64 `flags` | u64 (bit 63 rejected) |
| 2 | `GPIO_V2_LINE_ATTR_ID_OUTPUT_VALUES` | u64 `values` | u64; `values` must be a subset of `mask` |
| 3 | `GPIO_V2_LINE_ATTR_ID_DEBOUNCE` | u32 `debounce_period_us` | low u32; upper four bytes ignored |

## Validation order

Decoders validate in this fixed order and report the first failure:

1. **gpiochip_info**: size; name; label; lines.
2. **line attribute** (at offset O): bounds (need 16 bytes); id read; padding
   at O+4; id in 1..3; value (bit 63 or DEBOUNCE low half).
3. **line config** (at base B): flags u64; `num_attrs` at B+8; padding at
   B+12; each of `num_attrs` config attributes (attribute then mask then
   OUTPUT_VALUES subset).
4. **line request**: size; `num_lines` at 560; offsets (each u32, duplicate
   check); consumer at 256; config at 288; `event_buffer_size` at 564;
   padding at 568; fd at 588.
5. **line info**: size; name; consumer; `offset`; `num_attrs`; flags; each
   attribute; padding at 240.
6. **line event**: size; timestamp u64; id 1 or 2; offset; seqno;
   line_seqno; padding at 24.
7. **line values**: size; bits; mask.

Encoders validate the entire value first and write only then (atomic
failure): nothing is appended to `out` on `Err`.

## Error catalog

Generic message shapes (all values decimal, all offsets byte offsets):

| Condition | Message |
|---|---|
| buffer shorter than the struct | `gpio: <label>: truncated at offset N: need S bytes, have N` |
| buffer longer than the struct | `gpio: <label>: buffer has N bytes, expected exactly S` |
| nonzero padding byte | `gpio: <label>: bad padding at offset O: expected zero byte, found V` |
| C string without a NUL | `gpio: <label> at offset O has no NUL within 32 bytes` |
| u64 with bit 63 set | `gpio: <label>: 64-bit value at offset O has bit 63 set (not representable as Int)` |
| attribute out of bounds | `gpio: line attribute at offset O: truncated at offset N: need 16 bytes, have H` |
| unknown attribute id (standalone) | `gpio: line attribute at offset O: unknown id N` |
| unknown attribute id (encode) | `gpio: line attribute: unknown id N` |
| negative attribute value (encode) | `gpio: line attribute: value V is negative` |
| debounce above u32 (encode) | `gpio: line attribute: debounce period V does not fit in u32` |
| negative config flags | `gpio: line config: flags V are negative (64-bit fields are unsigned)` |
| attribute arrays not index-aligned | `gpio: line config: attribute arrays out of step (A ids, B values, C masks)` |
| more than ten attributes | `gpio: line config: N attributes exceed the maximum of 10` |
| `num_attrs` above 10 | `gpio: line config: num_attrs N out of range 0..10 at offset O` |
| OUTPUT_VALUES outside mask | `gpio: line config: attr I output values V have bits outside mask M` |
| per-attribute (config/info encode) | `gpio: line config: attr I has unknown id N` / `has a negative value (V)` / `has a negative mask (M)` / `debounce period V does not fit in u32` |
| `num_lines` outside 1..64 | `gpio: line request: num_lines N out of range 1..64` (decode adds `at offset 560`) |
| offsets array/num_lines mismatch | `gpio: line request: offsets length N does not match num_lines M` |
| duplicate offset (decode) | `gpio: line request: duplicate line offset V at offsets entry I (byte offset B)` |
| duplicate offset (encode) | `gpio: line request: duplicate line offset V at offsets entry I` |
| offset above u32 | `gpio: line request: line offset V at offsets entry I does not fit in u32` |
| `event_buffer_size` above u32 | `gpio: line request: event_buffer_size V does not fit in u32` |
| `fd` outside u32 | `gpio: line request: fd V does not fit in u32` |
| name longer than 31 bytes | `gpio: <label> is N bytes, needs at most 31 plus NUL within 32` |
| embedded NUL in a name | `gpio: <label> has an embedded NUL at byte I` |
| line offset above u32 (info) | `gpio: line info: line offset V does not fit in u32` |
| info `num_attrs` mismatch | `gpio: line info: num_attrs N does not match A id / B value entries` |
| info attribute error | `gpio: line info: attr I has unknown id N` etc. |
| info flags negative | `gpio: line info: flags V are negative (64-bit fields are unsigned)` |
| event id not 1/2 (decode) | `gpio: line event: unknown event id N at offset 8` |
| event id not 1/2 (encode) | `gpio: line event: event id N is not 1 (rising) or 2 (falling)` |
| negative timestamp | `gpio: line event: timestamp V is negative` |
| event seqno above u32 | `gpio: line event: <field> V does not fit in u32` |
| negative values bits/mask | `gpio: line values: <field> V are negative (64-bit fields are unsigned)` |
| name field decode out of bounds | `gpio: name at offset O: truncated: need 32 bytes, have H` |

## API contract

All functions are free functions in module `xiom.gpio`. See the README API
table for the complete list; the public types are:

```xi
pub type GpioChipInfo = {
  name: Str;
  label: Str;
  lines: Int;
}

pub type GpioLineAttribute = {
  id: Int;
  value: Int;
}

pub type GpioLineConfig = {
  flags: Int;
  attr_ids: Vec[Int];
  attr_values: Vec[Int];
  attr_masks: Vec[Int];
}

pub type GpioLineRequest = {
  offsets: Vec[Int];
  consumer: Str;
  num_lines: Int;
  event_buffer_size: Int;
  fd: Int;
  config_flags: Int;
  attr_ids: Vec[Int];
  attr_values: Vec[Int];
  attr_masks: Vec[Int];
}

pub type GpioLineInfo = {
  name: Str;
  consumer: Str;
  line_offset: Int;
  num_attrs: Int;
  flags: Int;
  attr_ids: Vec[Int];
  attr_values: Vec[Int];
}

pub type GpioLineEvent = {
  timestamp_ns: Int;
  event_type: Int;
  line_offset: Int;
  global_seqno: Int;
  line_seqno: Int;
}

pub type GpioLineValues = {
  bits: Int;
  mask: Int;
}
```

Notes:

- `GpioLineRequest.fd` is the raw unsigned 32-bit image; use
  `gpio_u32_to_i32` for the signed kernel view (`-1` = unset).
- Variable-length collections are index-aligned `Vec[Int]` arrays; never
  push to one mirror without the others.
- `gpio_line_flag_set(flags, flag)` requires `flag` to be one of the
  single-bit constants; it returns false for a composite value.
- 64-bit fields are represented as non-negative `Int`; a decoded u64 with
  bit 63 set is an error rather than a wrap, since `Int` is signed.

## Complexity

| Operation | Complexity |
|---|---|
| `gpio_chip_info_*`, `gpio_name_*` | O(1) |
| `gpio_line_attribute_*` | O(1) |
| `gpio_line_config_*` | O(attrs) |
| `gpio_line_request_decode` | O(num_lines^2) offset uniqueness check, otherwise O(1) |
| `gpio_line_request_encode_into` | O(num_lines^2) offset uniqueness check, otherwise O(1) |
| `gpio_line_info_*` | O(attrs) |
| `gpio_line_event_*`, `gpio_line_values_*` | O(1) |
| `gpio_line_flags_decode` | O(13) |

## Test plan

`tests/test_conformance.xi` (`module gpio_tests`, 21 named tests). The
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line and
returns the failure count. Coverage:

1. `gpiochip_info` decode trims at NUL, ignores the tail, reads the u32;
2. `gpiochip_info` errors: truncation, oversize, unterminated name/label,
   name field bounds, name-length and line-range encode errors;
3. `gpiochip_info` encode round-trip and `encode_into` atomicity;
4. all 13 flag constants pinned and the per-flag set matrix;
5. flag set decode order, known mask and unknown-bit split;
6. flag/attribute/change/event names, predicates, alignment and signed-fd
   helpers;
7. attribute decode: pinned hex u64, OUTPUT_VALUES and DEBOUNCE top half;
8. attribute padding/id/bit-63 errors and atomic encode;
9. config decode: flags, three attribute kinds, DEBOUNCE top half ignored;
10. config rejections: size, `num_attrs`, padding (config and attribute),
    values-vs-mask, unknown id, mask bit 63;
11. config encode round-trip, builder behavior and rejection catalog;
12. line request decode: offsets, consumer, config, fd, unused tail;
13. line request rejection catalog: sizes, `num_lines`, duplicates,
    padding, encode ranges;
14. line event: 64-bit timestamp, ids, seqnos and pinned LE bytes;
15. line event rejection catalog: size, id, padding, bit 63, encode ranges;
16. line info decode: names, offset, flags and attribute array;
17. line info rejection catalog: size, `num_attrs`, names, padding, encode
    ranges;
18. line values: hex-pinned bits/mask, bit-63 rejection, encode ranges;
19. all-zero buffers classify as documented and decoding is deterministic;
20. request builder pipeline: add/validate/encode/decode round-trip;
21. hex-pinned `gpiochip_info`, zero attribute and values vectors.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.gpio
```

Last verified: compiler 0.61.3,
`port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.

## Known limitations

- The layout is fixed to little-endian; big-endian hosts would need a
  sibling codec (the uAPI itself is native-endian).
- `Int` is signed: u64 fields with bit 63 set are rejected instead of
  wrapped, and `fd` is exposed as its raw u32 image.
- `gpio_v2_line_info_changed` (watch) is not decoded; only its change-type
  constants and names are provided.
- Offset uniqueness is O(num_lines^2) and is enforced on both decode and
  encode; offsets are not checked against a chip's line count.
- Unused attribute/offset slots and bytes after string NULs are ignored,
  not required to be zero.
- `Vec`-typed fields make the structs plain values; copies are O(entries)
  and there is no sharing.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers `_ok_unit`,
  `_err_unit`, `_ok_int`, `_err_int`, `_ok_bool`, `_err_bool`, `_ok_str`,
  `_err_str`, `_ok_bytes`, `_err_bytes`, `_ok_chip`, `_err_chip`,
  `_ok_attr`, `_err_attr`, `_ok_config`, `_err_config`, `_ok_request`,
  `_err_request`, `_ok_info`, `_err_info`, `_ok_event`, `_err_event`,
  `_ok_values`, `_err_values` (constructing Results inside other functions
  miscompiles in this compiler).
- Variable-length collections are index-aligned `Vec[Int]` arrays; no
  `Vec[StructType]` and no `Vec[fn]` dispatch. Every push writes all
  mirrors (ids, values, masks).
- Every `Vec[UInt8]` byte read is widened with `(b as Int) & 0xFF`.
- `&struct.field` is never passed directly to a `&Vec` parameter; fields
  are bound to typed locals first, and `Vec[Int]` element reads go through
  typed locals.
- No `Str` value is compared with `==` and none is read from a `Vec`;
  error messages are compared with `xiom.string.compare.str_compare` in the
  tests. Names are materialized with `xiom.string.builder.sb_to_str` over
  the NUL-free prefix only (`sb_to_str` must never see 0x00).
- Flag decode uses division and modulo by powers of two; bit-63 handling is
  an explicit branch; 64-bit little-endian composition is explicit byte
  multiplication (`_u64_le` / `_put_u64_le`).
- `&mut` appears at call sites explicitly; `&mut StructType` write-through
  is limited to `Vec.push` and field assignment on builders. `&mut Int`
  out-parameters are avoided entirely.
- No function is named `log`; all functions are free functions; unused
  imports are avoided (`xiom.convert`, `xiom.string`,
  `xiom.string.builder` are all used).
