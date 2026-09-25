# xiom.radiotap -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.radiotap`, version `0.1.0`).
Module: `src/radiotap.xi` (`module xiom.radiotap`).
Depends on `xiom.std`; the library module imports nothing (the tests import
`xiom.test`, `xiom.io` and `xiom.string.compare`).

## Scope

A pure-XIOM (no FFI) codec for the IEEE 802.11 radiotap capture header that
precedes a monitor-mode frame:

- `radiotap_parse`: base header, present bitmap word 0, the optional second
  word, and the fixed-size data fields selected by bits 0..19;
- `radiotap_emit`: canonical re-encoding of a parsed header, byte-for-byte;
- `radiotap_length` / `radiotap_present_count` / `radiotap_present_word` /
  `radiotap_field_count` / `radiotap_field_bit` / `radiotap_field_value_at` /
  `radiotap_find` / `radiotap_value`: infallible index accessors;
- `radiotap_channel_freq` / `radiotap_channel_flags`: CHANNEL convenience
  accessors;
- `radiotap_frame_offset` / `radiotap_frame_length` / `radiotap_frame`: the
  span of the 802.11 frame bytes after the header.

## Non-goals

- 802.11 frame parsing of any kind: the bytes after the header are an opaque
  span and their 802.11 structure is left to the caller.
- Vendor namespaces: bit 30 is not decoded and stops the parse with
  `radiotap: unsupported field`, so vendor TLVs cannot be skipped.
- More than two present words: a third word (bit 31 of word 1) is rejected
  as `radiotap: too many present words`.
- Any field in the second present word: the documented table covers
  absolute bits 0..19 only, so a set field bit in word 1 (absolute
  32..62) is `radiotap: unsupported field`. Word 1 is accepted when its
  field bits are all clear (the chain flag itself is the only valid bit).
- Radiotap namespace bits 20..29 (undefined in the supported table).
- Non-canonical layouts: the declared length must equal the encoded size and
  alignment padding must be zero bytes; trailing slack is
  `radiotap: length mismatch`.
- FCS computation or 802.11 validation: the bit-14 byte is read verbatim as
  an opaque value.
- Streaming/incremental parsing; whole headers are in-memory
  `Vec[UInt8]` buffers.

## Byte-level layout

### Base header (8 bytes minimum, offsets from the start of the header)

| Offset | Size | Field | Encoding |
|---|---|---|---|
| 0 | 1 | version | unsigned byte, must be 0 |
| 1 | 1 | pad | skipped (not validated) |
| 2 | 2 | length | unsigned 16-bit little-endian |
| 4 | 4 | present word 0 | unsigned 32-bit little-endian |
| 8 | 4 | present word 1 | unsigned 32-bit little-endian, present only when bit 31 of word 0 is set |

Every field of the base header and of every data field is little-endian.

### Present chain

Bit 31 of a present word means "another present word follows". The codec
accepts at most two words:

| Condition | Result |
|---|---|
| word 0 bit 31 clear | 1 present word (8-byte base header) |
| word 0 bit 31 set, declared `length >= 12` | read word 1 at offset 8 |
| word 0 bit 31 set, declared `length < 12` | `radiotap: bad present chain` |
| word 1 bit 31 set | `radiotap: too many present words` |
| word 1 has any other bit set | `radiotap: unsupported field` |
| word 1 = 0 | valid: a two-word header with an empty second word |

### Field table (present bits 0..19 of word 0)

`Size` is the encoded byte count on the wire; `Align` is the required
alignment relative to the start of the radiotap header. `Stored value` is
what `radiotap_value` returns (every field is one `Int` in the pool).

| Bit | Name | Wire layout | Size | Align | Signed | Stored value |
|---|---|---|---|---|---|---|
| 0 | TSFT | u64 LE | 8 | 8 | no | raw value (0 .. 2^63-1) |
| 1 | FLAGS | u8 | 1 | 1 | no | raw value |
| 2 | RATE | u8 | 1 | 1 | no | raw value |
| 3 | CHANNEL | u16 freq LE + u16 flags LE | 4 | 2 | no | `freq + flags * 65536` |
| 4 | FHSS | u8 hop set + u8 hop pattern | 2 | 1 | no | `set + pattern * 256` |
| 5 | DBM_ANTSIGNAL | i8 | 1 | 1 | yes | sign-extended (-128 .. 127) |
| 6 | DBM_ANTNOISE | i8 | 1 | 1 | yes | sign-extended (-128 .. 127) |
| 7 | LOCK_QUALITY | u16 LE | 2 | 2 | no | raw value |
| 8 | TX_ATTENUATION | u16 LE | 2 | 2 | no | raw value |
| 9 | DB_TX_ATTENUATION | u16 LE | 2 | 2 | no | raw value |
| 10 | DBM_TX_POWER | i8 | 1 | 1 | yes | sign-extended (-128 .. 127) |
| 11 | ANTENNA | u8 | 1 | 1 | no | raw value |
| 12 | DBM_ANTSIGNAL_2 | u8 | 1 | 1 | no | raw value |
| 13 | DB_ANTSIGNAL_3 | u8 | 1 | 1 | no | raw value |
| 14 | FCS | u8 | 1 | 1 | no | raw value |
| 15 | RX_FLAGS | u16 LE | 2 | 2 | no | raw value |
| 16 | TX_FLAGS | u16 LE | 2 | 2 | no | raw value |
| 17 | RTS_RETRIES | u8 | 1 | 1 | no | raw value |
| 18 | DATA_RETRIES | u8 | 1 | 1 | no | raw value |
| 19 | XCHANNEL | u32 LE | 4 | 4 | no | raw value |

Any other set bit stops parsing: bits 20..29 (undefined), bit 30 (vendor
namespace) and every field bit of word 1 (absolute 32..62) are
`radiotap: unsupported field`. The scan visits bits in ascending order, so
the first offending bit in bit order is reported.

### Alignment and padding

Fields are packed in ascending bit order starting after the base header
(offset 8, or 12 with two present words). Before each field the offset is
rounded up to the field's alignment; the skipped bytes are alignment
padding. On parse, every padding byte must be 0, otherwise
`radiotap: bad alignment padding`; on emit, zeros are written. A field
whose aligned span crosses `length` is `radiotap: truncated field`.

Worked example (the canonical fixture): two present words end at 12; TSFT
aligns at 16 (4 padding bytes), FLAGS/RATE at 24/25, CHANNEL at 26, DBM at
30, ANTENNA at 31, FCS at 32, XCHANNEL aligns at 36 (3 padding bytes) and
ends at 40, so `length = 40` and the frame starts at offset 40.

## Storage model

`pub type RadiotapHeader` holds:

| Field | Meaning |
|---|---|
| `version` | version byte (0 for every accepted header) |
| `length` | declared header length; offset of the frame |
| `present_words` | 1, or 2 when word 0 chained |
| `present0` / `present1` | the present bitmap words as read (`present1` = 0 for one word) |
| `bits` | present bit of each parsed field, ascending |
| `values` | parallel values (`bits.len() == values.len()`) |
| `frame_off` | absolute offset of the first frame byte (= `length`) |
| `frame_len` | frame bytes remaining in the parsed buffer |

Fields are implementation details; callers should use the accessors.

## API signatures

All functions are free functions in module `xiom.radiotap` (no self methods):

```xi
pub type RadiotapHeader = {
  version: Int;
  length: Int;
  present_words: Int;
  present0: Int;
  present1: Int;
  bits: Vec[Int];
  values: Vec[Int];
  frame_off: Int;
  frame_len: Int;
}

pub fn radiotap_parse(data: &Vec[UInt8]) -> Result[RadiotapHeader, Str]
pub fn radiotap_emit(h: &RadiotapHeader) -> Result[Vec[UInt8], Str]
pub fn radiotap_version(h: &RadiotapHeader) -> Int
pub fn radiotap_length(h: &RadiotapHeader) -> Int
pub fn radiotap_present_count(h: &RadiotapHeader) -> Int
pub fn radiotap_present_word(h: &RadiotapHeader, i: Int) -> Int
pub fn radiotap_field_count(h: &RadiotapHeader) -> Int
pub fn radiotap_field_bit(h: &RadiotapHeader, i: Int) -> Int
pub fn radiotap_field_value_at(h: &RadiotapHeader, i: Int) -> Result[Int, Str]
pub fn radiotap_find(h: &RadiotapHeader, bit: Int) -> Int
pub fn radiotap_value(h: &RadiotapHeader, bit: Int) -> Result[Int, Str]
pub fn radiotap_channel_freq(h: &RadiotapHeader) -> Int
pub fn radiotap_channel_flags(h: &RadiotapHeader) -> Int
pub fn radiotap_frame_offset(h: &RadiotapHeader) -> Int
pub fn radiotap_frame_length(h: &RadiotapHeader) -> Int
pub fn radiotap_frame(data: &Vec[UInt8], h: &RadiotapHeader) -> Result[Vec[UInt8], Str]
```

## Semantics

`radiotap_parse(data)`
: Validates in this order:

  1. `data.len() >= 8`, else `radiotap: truncated header`;
  2. version byte 0, else `radiotap: bad version`;
  3. `8 <= length <= data.len()`, else `radiotap: bad length`;
  4. present chain (table above), else `radiotap: bad present chain` /
     `radiotap: too many present words` / `radiotap: unsupported field`
     for a nonzero word 1;
  5. bits 0..30 of word 0 in ascending order: an unknown set bit is
     `radiotap: unsupported field` (checked before the field's span, so an
     unknown bit wins over truncation); then `radiotap: truncated field` if
     the aligned span crosses `length`; then `radiotap: bad alignment
     padding` if a padding byte is nonzero; TSFT additionally requires its
     top byte below 128, else `radiotap: tsft out of range`;
  6. the aligned end of the last field must equal `length`, else
     `radiotap: length mismatch`.

  On success `frame_off = length` and `frame_len = data.len() - length`;
  `data` is never copied, so the returned header is an index into the
  caller's buffer.

`radiotap_emit(h)`
: Validates `version == 0`, then `h.bits.len() == h.values.len()`, then
  `present_words` in 1..2, then each pool entry in order: strictly ascending
  bits, bit in the table, value within the field's representable range
  (signed i8: -128..127; unsigned: 0..2^(8*size)-1, with TSFT capped at
  2^63-1). It then requires the stored present words to agree with the pool
  (`present1` must be 0). Only after all checks does it write: base header,
  present words, each field in pool (= ascending bit) order with zero
  padding, and the recomputed little-endian `length`. `h.length`,
  `h.frame_off` and `h.frame_len` are ignored. On `Err` nothing is
  returned, so a failed emit has no partial output.

`radiotap_present_word(h, i)`
: Returns word `i` (0 or 1), or `-1` when `i < 0` or
  `i >= radiotap_present_count(h)`. Word 1 of a two-word header may
  legitimately be 0, so `-1` is the only out-of-range marker.

`radiotap_field_bit(h, i)` / `radiotap_field_value_at(h, i)`
: Positional access to the pool. `radiotap_field_bit` returns `-1` out of
  range; `radiotap_field_value_at` returns
  `Err("radiotap: field index out of range")`.

`radiotap_find(h, bit)` / `radiotap_value(h, bit)`
: First match in pool order (ascending bits). Parse never records a bit
  twice, so the first match is the only match for parsed headers; for a
  hand-built header with duplicates the lowest index wins. `radiotap_find`
  returns `-1` when absent; `radiotap_value` returns
  `Err("radiotap: field absent")`.

`radiotap_channel_freq` / `radiotap_channel_flags(h)`
: Low / high 16 bits of the CHANNEL stored value, or `-1` when the header
  has no CHANNEL field.

`radiotap_frame(data, h)`
: `Ok` with a fresh copy of the `frame_len` bytes at `frame_off` in `data`;
  an empty vector when the header has no trailing frame.
  `Err("radiotap: frame out of bounds")` when the recorded span does not
  fit in the passed `data` (for example when a shorter buffer is passed).

## Error string catalog

| Condition | Error text |
|---|---|
| `data.len() < 8` | `radiotap: truncated header` |
| version byte != 0 (parse or emit) | `radiotap: bad version` |
| `length < 8` or `length > data.len()` | `radiotap: bad length` |
| word 0 chains but `length < 12` | `radiotap: bad present chain` |
| word 1 bit 31 set (third word) | `radiotap: too many present words` |
| first set bit outside 0..19 (incl. bit 30, second-word field bits) | `radiotap: unsupported field` |
| aligned field crosses `length` | `radiotap: truncated field` |
| a padding byte before an aligned field is nonzero | `radiotap: bad alignment padding` |
| TSFT top byte >= 128 (bit 63 set) | `radiotap: tsft out of range` |
| last field ends before `length` | `radiotap: length mismatch` |
| emit: `bits.len() != values.len()` | `radiotap: field pool mismatch` |
| emit: `present_words` not 1/2, or stored words disagree with the pool | `radiotap: present words mismatch` |
| emit: a bit repeats or decreases | `radiotap: fields out of order` |
| emit: value outside the field's representable range | `radiotap: field value out of range` |
| `radiotap_field_value_at`: index negative or >= count | `radiotap: field index out of range` |
| `radiotap_value`: no field has the bit | `radiotap: field absent` |
| `radiotap_frame`: recorded span does not fit `data` | `radiotap: frame out of bounds` |

All seventeen strings are stable API.

## Complexity

| Operation | Complexity |
|---|---|
| `radiotap_parse` | O(fields + length) time, O(fields) space |
| `radiotap_emit` | O(fields + encoded size) time/space |
| `radiotap_version` / `radiotap_length` / `radiotap_present_count` / `radiotap_field_count` | O(1) |
| `radiotap_present_word` / `radiotap_field_bit` / `radiotap_field_value_at` | O(1) |
| `radiotap_find` / `radiotap_value` / `radiotap_channel_*` | O(fields) |
| `radiotap_frame` | O(frame_len) |

## Test plan

`tests/test_conformance.xi` (`module radiotap_tests`, 19 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Fixtures are assembled byte by byte in the test
file:

- **canonical fixture** (43 bytes): present word 0 `0x8008482F` (bits
  0,1,2,3,5,11,14,19 + chain), word 1 = 0, `length = 40`, TSFT
  `0x0102030405060708`, FLAGS 16, RATE 108, CHANNEL (2412 MHz, flags 160),
  DBM_ANTSIGNAL -42, ANTENNA 1, FCS 1, XCHANNEL 7, frame `AA BB CC`;
- **empty two-word header**: word 0 `0x80000000`, word 1 = 0,
  `length = 12`;
- small hand-built headers for the error paths and emit.

Coverage:

1. canonical fixture: length 43, version 0, `length` 40, 2 present words
   (`0x8008482F`, 0), 8 fields with ascending bits `0,1,2,3,5,11,14,19`,
   `radiotap_field_bit` guards;
2. canonical values: TSFT, FLAGS, RATE, CHANNEL `2412 + 160*65536`,
   DBM_ANTSIGNAL -42 (sign-extended), ANTENNA, FCS, XCHANNEL, channel
   accessors, positional value at index 4;
3. `radiotap_find` first-match and `-1`; `radiotap_value` /
   `radiotap_field_value_at` error catalog;
4. frame span 40/3 and slice `{170,187,204}`; a 40-byte header yields an
   empty frame; a 41-byte buffer is `radiotap: frame out of bounds`;
5. `radiotap_emit` reproduces the canonical 40-byte header byte-for-byte,
   re-parses to the same pool, and is idempotent;
6. inputs of 0, 1 and 7 bytes are `radiotap: truncated header`;
7. version 1 and 255 are `radiotap: bad version`;
8. `length` 7, `length` 44 (buffer 43) and a 39-byte prefix of the fixture
   are `radiotap: bad length`; `length` 41 and 42 are
   `radiotap: length mismatch`; the minimal 8-byte header parses;
9. chain with `length` 8 is `radiotap: bad present chain`; a third word is
   `radiotap: too many present words`; a second zero word parses with frame
   offset 12; a word-1 field bit is `radiotap: unsupported field`;
10. bit 20, bit 30 (vendor) and an unknown bit after a known one are
    `radiotap: unsupported field`;
11. TSFT/CHANNEL/FLAGS crossing `length` are `radiotap: truncated field`;
    the exact fit parses;
12. a nonzero TSFT padding byte (offset 12) and a nonzero XCHANNEL padding
    byte (offset 35) are `radiotap: bad alignment padding`; zero padding
    parses;
13. TSFT round-trips 2^63-1 as an unsigned u64 and is little-endian; a top
    byte of 128 is `radiotap: tsft out of range`;
14. hand-built emit pins the alignment layout: bits `0,3,19` with a
    `length = 24` byte sequence and re-parse;
15. emit rejects bad version, out-of-order/duplicate bits, out-of-range
    values (unsigned 256/-1, signed -129/128), unknown bits, present-word
    mismatches and pool drift; `-128` still emits;
16. present-word accessor guards (1-word and 2-word headers);
17. zero-field header: empty pool, frame span 8/2 and 8-byte emit;
18. signed i8 emit bytes (`D6 80 7F`) and round-trip;
19. two-word empty header round-trips through emit and parse.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.radiotap
```

Last verified: compiler 0.61.3,
`port: PASS (passed=19 failed=0 program_exit=0 exit=0)`.

## Known limitations

- The field table is fixed to bits 0..19; radiotap namespace bits 20..29,
  the vendor namespace (bit 30) and every second-word field bit are
  unsupported and stop the parse.
- Vendor TLVs cannot be skipped, so captures that use them (many modern
  drivers) are rejected even though their known fields would parse.
- At most two present words; a declared third word is an error.
- Parse is strict: declared length must exactly match the encoded fields,
  and alignment padding must be zero. Real-world headers that carry
  trailing slack or nonzero padding are rejected.
- TSFT is returned as a signed `Int`; values with bit 63 set do not fit and
  are `radiotap: tsft out of range`.
- No 802.11 frame decoding, no FCS verification, no protocol validation of
  CHANNEL flags, RATE values or retry counters.
- `radiotap_frame` copies the frame bytes on every call.
- Not thread-safe; `RadiotapHeader` is a plain value type borrowing nothing
  but indexing the buffer passed to `radiotap_parse`.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_header`/`_err_header`/`_ok_bytes`/`_err_bytes`/`_ok_int`/`_err_int`
  (constructing Results directly in other functions miscompiles in this
  compiler).
- Present-word bit tests avoid `&` masks entirely: masking miscompiles on
  operands with bit 31 set, and word 0 of a two-word header has bit 31 set.
  Bits are tested by repeated division (`v / 2^k % 2`) and the parse scan
  halves `q` once per bit.
- Every `Vec[UInt8]` byte read is widened with `(b as Int) & 0xFF` before
  entering Int arithmetic; 16/32/64-bit reads and writes are pure
  arithmetic (`+ - * / %`), exact for unsigned values with the high bit
  set.
- Emit backfills the length field with indexed `Vec[UInt8]` writes
  (`v[pos] = ...`), which work on v0.61.3.
- `RadiotapHeader` (two scalar words plus two `Vec[Int]` pools) is
  constructed inside `radiotap_parse` and crosses function boundaries only
  by reference or through `_ok_header`, following the `xiom.pcap`
  `PcapFile` precedent; no `Vec[StructType]`.
- Str values in the tests are compared through
  `xiom.string.compare.str_compare` (BUG 17: `==` on a Str read from a
  `Vec` lowers to a pointer comparison).
- Note for reviewers: a previous revision of `_push_field` used
  `Vec<UInt8>` (angle brackets) in a parameter type; v0.61.3 accepted it
  silently, so the whole package is grep-audited for `Vec<`/`Result<`
  instead of relying on the compiler.
- The package declares no `extern "C"` blocks (no FFI).
