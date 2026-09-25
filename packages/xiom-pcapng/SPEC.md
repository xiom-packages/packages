# xiom.pcapng -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.pcapng`, version `0.1.0`).
Module: `src/pcapng.xi` (`module xiom.pcapng`).
Depends on `xiom.std`; the library module imports nothing (the tests import
`xiom.test`, `xiom.io`, `xiom.string` and `xiom.string.compare`).

## Scope

A pure-XIOM (no FFI) reader for PCAP Next Generation (pcapng) capture files:

- `pcapng_is_file`: cheap SHB-type sniff;
- `pcapng_parse`: full flat block index (type, offsets, lengths) plus parsed
  SHB / IDB / EPB / SPB / NRB / ISB pools and an option pool; unknown block
  types are preserved as raw body spans;
- block, section, interface, packet, NRB record/name, ISB and option
  accessors, including on-demand copies of every recorded span.

## Non-goals

- Writing, appending or repairing capture files.
- Packet dissection of any kind (Ethernet, IP, TCP, ...): packet data is an
  opaque byte span.
- Name resolution work beyond NRB record field parsing: this module reports
  the IPv4/IPv6 address and DNS name spans, it does not convert names to
  `Str`, resolve them, or interpret any other NRB record type.
- Compression or replay of compressed block types.
- Streaming/incremental parsing: the whole buffer is indexed in one call.
- Timestamp semantics: the raw 64-bit `high * 2^32 + low` counter is
  reported, without a resolution/offset interpretation.
- Section-length validation or enforcing packet ordering beyond the
  interface-must-precede rule documented below.
- The obsolete Packet Block (type 2) and Decryption Secrets Block (type
  0x0000000A) are not parsed; they are indexed as unknown-type blocks with
  their raw body span.

## File layout

A pcapng file is a sequence of blocks:

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | block type |
| 4 | 4 | total length (>= 12, multiple of 4) |
| 8 | total - 12 | body |
| total - 4 | 4 | trailing total length (must equal the leading copy) |

The type and both length copies are read with the byte order of the current
section. Blocks are contiguous; there is no padding between blocks.

### Byte-order rules

- The first block must be an SHB. Its type bytes are `0A 0D 0D 0A`
  (0x0A0D0D0A); the sequence is a palindrome, so the type test is valid in
  either order.
- The SHB body starts with the byte-order magic `0x1A2B3C4D`:
  `4D 3C 2B 1A` selects little-endian, `1A 2B 3C 4D` selects big-endian.
  Any other four bytes are `pcapng: bad byte-order magic`.
- Every multi-byte field of a section's blocks (including the type and both
  total-length copies) is read with that section's order until the next SHB.

### SHB -- Section Header Block (type 0x0A0D0D0A = 168627466)

| Body offset | Size | Field | Indexed |
|---|---|---|---|
| 0 | 4 | byte-order magic | via `pcapng_section_order` |
| 4 | 2 | major version (must be 1) | `pcapng_section_major` |
| 6 | 2 | minor version (reported, not enforced) | `pcapng_section_minor` |
| 8 | 8 | section length (`0xFFFFFFFFFFFFFFFF` = unspecified) | `pcapng_section_length` |
| 16 | ... | options | option pool |

The section length excludes the SHB itself and is reported, not validated;
the unspecified value is reported as -1.

### IDB -- Interface Description Block (type 1)

| Body offset | Size | Field | Indexed |
|---|---|---|---|
| 0 | 2 | linktype | `pcapng_interface_linktype` |
| 2 | 2 | reserved | no |
| 4 | 4 | snaplen | `pcapng_interface_snaplen` |
| 8 | ... | options | option pool |

Each IDB appends one interface; interfaces are numbered globally in file
order across sections. The section-local interface id of a packet or ISB is
mapped to this global ordinal.

### EPB -- Enhanced Packet Block (type 6)

| Body offset | Size | Field | Indexed |
|---|---|---|---|
| 0 | 4 | interface id (section-local) | `pcapng_packet_interface` (global) |
| 4 | 4 | timestamp high | `pcapng_packet_ts_high` |
| 8 | 4 | timestamp low | `pcapng_packet_ts_low` |
| 12 | 4 | captured length | `pcapng_packet_caplen` |
| 16 | 4 | original length | `pcapng_packet_origlen` |
| 20 | caplen | packet data | `pcapng_packet_data_offset` / `pcapng_packet_data` |
| 20 + pad4(caplen) | ... | options | option pool |

The data region is `pad4(caplen)` bytes; the padding bytes are not validated.

### SPB -- Simple Packet Block (type 3)

| Body offset | Size | Field | Indexed |
|---|---|---|---|
| 0 | 4 | original length | `pcapng_packet_origlen` |
| 4 | body - 4 | packet data | `pcapng_packet_data_offset` / `pcapng_packet_data` |

SPB carries no timestamp and no interface id (accessors report 0 and -1).
Documented policy: the data region must be exactly `origlen` rounded up to a
multiple of 4; then `caplen == origlen`. A region smaller than `origlen` is
`pcapng: truncated packet data`; a larger one is `pcapng: bad packet
padding` (an SPB with a snaplen-truncated payload is therefore rejected).

### NRB -- Name Resolution Block (type 4)

The body is a sequence of records; each record is a 2-byte type, a 2-byte
value length, the value, then zero padding to a 4-byte boundary:

| Record type | Value |
|---|---|
| 1 | 4-byte IPv4 address, then NUL-terminated DNS names |
| 2 | 16-byte IPv6 address, then NUL-terminated DNS names |
| 0 | end of records (remaining body bytes are ignored) |
| other | skipped, not indexed |

Within the name area, runs of NUL bytes are padding and produce no name
entries; a non-empty name must be followed by a NUL or the parse fails with
`pcapng: unterminated name`. Each name is indexed separately, linked to its
record by ordinal.

### ISB -- Interface Statistics Block (type 5)

| Body offset | Size | Field | Indexed |
|---|---|---|---|
| 0 | 4 | interface id (section-local) | `pcapng_isb_interface` (global) |
| 4 | 4 | timestamp high | not indexed |
| 8 | 4 | timestamp low | not indexed |
| 12 | ... | options | option pool |

Option code 6 (`isb_ifrecv`, packets received) and code 7 (`isb_ifdrop`,
packets dropped) are each read as a 64-bit value and exposed by
`pcapng_isb_ifrecv` / `pcapng_isb_ifdrop`; each must have length 8, otherwise
`pcapng: bad statistics counter`. An absent counter is reported as -1.

### Options (SHB / IDB / EPB / ISB)

Options are TLV entries: 2-byte code, 2-byte value length, the value, then
zero padding to the next multiple of 4. A code of 0 ends the option list; the
marker and any bytes after it are not indexed. Padding bytes are not
validated. The option region of a supported block is always a multiple of 4
bytes, so an option header is either fully present or absent; an option whose
padded value does not fit the remaining region is `pcapng: option overruns
block`.

## Validation policies

All of the following are enforced by `pcapng_parse`; the call is Err on the
first violation and no partial index is returned:

1. every block: at least 12 bytes remain at the block start;
2. the first block is an SHB (documented policy; an empty input is also
   `pcapng: section header block must be first`);
3. SHB: byte-order magic must match `0x1A2B3C4D` in one of the two orders;
4. every block: total length >= 12 and a multiple of 4;
5. every block: total length must not run past the buffer;
6. every block: the trailing total-length copy must equal the leading copy;
7. SHB body >= 16 bytes; major version == 1;
8. IDB body >= 8 bytes; EPB body >= 20 bytes; SPB body >= 4 bytes; ISB body
   >= 12 bytes;
9. EPB: caplen <= origlen (documented policy);
10. EPB: the padded data region must fit the body;
11. SPB: the data region must be exactly `origlen` padded to 4 bytes;
12. EPB/ISB interface id: the referenced interface must have been declared by
    an earlier IDB in the same section (documented policy);
13. NRB record value/padding must fit the body; IPv4 records >= 4 bytes,
    IPv6 records >= 16 bytes; names must be NUL-terminated;
14. options: the padded value must fit the remaining option region;
15. every recorded offset/length is derived from the validated buffer, so
    accessor spans cannot point outside the parsed buffer. Copy functions
    re-check the span against the buffer they are given.

## API signatures

All functions are free functions in module `xiom.pcapng`:

```xi
pub type PcapngFile = { ... 39 parallel Vec[Int] pools ... }

pub fn pcapng_is_file(data: &Vec[UInt8]) -> Bool
pub fn pcapng_parse(data: &Vec[UInt8]) -> Result[PcapngFile, Str]

pub fn pcapng_block_count(p: &PcapngFile) -> Int
pub fn pcapng_block_type(p: &PcapngFile, i: Int) -> Int
pub fn pcapng_block_offset(p: &PcapngFile, i: Int) -> Int
pub fn pcapng_block_body_offset(p: &PcapngFile, i: Int) -> Int
pub fn pcapng_block_body_length(p: &PcapngFile, i: Int) -> Int
pub fn pcapng_block_section(p: &PcapngFile, i: Int) -> Int
pub fn pcapng_block_body(data: &Vec[UInt8], p: &PcapngFile, i: Int) -> Result[Vec[UInt8], Str]

pub fn pcapng_section_count(p: &PcapngFile) -> Int
pub fn pcapng_section_order(p: &PcapngFile, s: Int) -> Int
pub fn pcapng_section_major(p: &PcapngFile, s: Int) -> Int
pub fn pcapng_section_minor(p: &PcapngFile, s: Int) -> Int
pub fn pcapng_section_length(p: &PcapngFile, s: Int) -> Int

pub fn pcapng_interface_count(p: &PcapngFile) -> Int
pub fn pcapng_interface_linktype(p: &PcapngFile, i: Int) -> Int
pub fn pcapng_interface_snaplen(p: &PcapngFile, i: Int) -> Int
pub fn pcapng_interface_block(p: &PcapngFile, i: Int) -> Int
pub fn pcapng_interface_section(p: &PcapngFile, i: Int) -> Int

pub fn pcapng_packet_count(p: &PcapngFile) -> Int
pub fn pcapng_packet_kind(p: &PcapngFile, i: Int) -> Int
pub fn pcapng_packet_block(p: &PcapngFile, i: Int) -> Int
pub fn pcapng_packet_section(p: &PcapngFile, i: Int) -> Int
pub fn pcapng_packet_interface(p: &PcapngFile, i: Int) -> Int
pub fn pcapng_packet_ts_high(p: &PcapngFile, i: Int) -> Int
pub fn pcapng_packet_ts_low(p: &PcapngFile, i: Int) -> Int
pub fn pcapng_packet_timestamp(p: &PcapngFile, i: Int) -> Int
pub fn pcapng_packet_caplen(p: &PcapngFile, i: Int) -> Int
pub fn pcapng_packet_origlen(p: &PcapngFile, i: Int) -> Int
pub fn pcapng_packet_data_offset(p: &PcapngFile, i: Int) -> Int
pub fn pcapng_packet_data(data: &Vec[UInt8], p: &PcapngFile, i: Int) -> Result[Vec[UInt8], Str]

pub fn pcapng_record_count(p: &PcapngFile) -> Int
pub fn pcapng_record_type(p: &PcapngFile, r: Int) -> Int
pub fn pcapng_record_block(p: &PcapngFile, r: Int) -> Int
pub fn pcapng_record_name_count(p: &PcapngFile, r: Int) -> Int
pub fn pcapng_record_address(data: &Vec[UInt8], p: &PcapngFile, r: Int) -> Result[Vec[UInt8], Str]
pub fn pcapng_name_count(p: &PcapngFile) -> Int
pub fn pcapng_name_record(p: &PcapngFile, n: Int) -> Int
pub fn pcapng_name_offset(p: &PcapngFile, n: Int) -> Int
pub fn pcapng_name_length(p: &PcapngFile, n: Int) -> Int
pub fn pcapng_name_bytes(data: &Vec[UInt8], p: &PcapngFile, n: Int) -> Result[Vec[UInt8], Str]

pub fn pcapng_isb_count(p: &PcapngFile) -> Int
pub fn pcapng_isb_interface(p: &PcapngFile, i: Int) -> Int
pub fn pcapng_isb_block(p: &PcapngFile, i: Int) -> Int
pub fn pcapng_isb_ifrecv(p: &PcapngFile, i: Int) -> Int
pub fn pcapng_isb_ifdrop(p: &PcapngFile, i: Int) -> Int

pub fn pcapng_option_count(p: &PcapngFile) -> Int
pub fn pcapng_option_block(p: &PcapngFile, i: Int) -> Int
pub fn pcapng_option_code(p: &PcapngFile, i: Int) -> Int
pub fn pcapng_option_offset(p: &PcapngFile, i: Int) -> Int
pub fn pcapng_option_length(p: &PcapngFile, i: Int) -> Int
pub fn pcapng_option_find(p: &PcapngFile, block: Int, code: Int) -> Int
pub fn pcapng_option_value(data: &Vec[UInt8], p: &PcapngFile, i: Int) -> Result[Vec[UInt8], Str]
```

## Semantics

`pcapng_is_file(data)`
: `true` iff `data.len() >= 12` and the first four bytes are `0A 0D 0D 0A`.
  Only the type sniff and the minimum length are checked; malformed bodies
  are not detected here.

`pcapng_parse(data)`
: Walks blocks from offset 0 with the validation policies above and returns a
  `PcapngFile` index. Index vecs are parallel and one entry per item in file
  order; on Err nothing is returned.

`pcapng_option_find(p, block, code)`
: First-match policy: scans the option pool in file order and returns the
  lowest pool index whose block ordinal is `block` and code is `code`;
  returns -1 when `block` is out of range or no such indexed option exists.
  Code 0 and options after the first code-0 marker are never indexed.

`pcapng_packet_interface(p, i)`
: Global interface ordinal (`interface id + number of interfaces declared in
  earlier sections`); -1 for an SPB (which has no interface id) or when `i`
  is out of range. Because a packet may only reference an earlier IDB in the
  same section, a non-negative result always names a parsed interface.

`pcapng_packet_timestamp(p, i)`
: `ts_high * 2^32 + ts_low`; 0 for an SPB; -1 out of range. Correct while
  the composed value fits the Int range (non-standard counters with the top
  bit of the high word set overflow).

`pcapng_packet_data`, `pcapng_block_body`, `pcapng_option_value`,
`pcapng_name_bytes`, `pcapng_record_address`
: Copy the recorded span out of the buffer passed in (which should be the
  one that was parsed, since offsets are absolute). Out-of-range index is a
  range error; a span that does not fit the buffer is `pcapng: span out of
  bounds`.

All other accessors are infallible: they return the recorded value for a
valid index and -1 for an out-of-range index (section/interface/packet/
record/name/ISB/option indices; for section length -1 also means
"unspecified").

## Error string catalog

| Condition | Error text |
|---|---|
| fewer than 12 bytes remain at a block start (including a short tail) | `pcapng: truncated block header` |
| first block is not an SHB, or the input is empty | `pcapng: section header block must be first` |
| SHB byte-order magic is neither byte sequence | `pcapng: bad byte-order magic` |
| total length < 12 or not a multiple of 4 | `pcapng: bad block length` |
| total length runs past the end of the buffer | `pcapng: truncated block` |
| trailing total length != leading total length | `pcapng: total length mismatch` |
| SHB body < 16 bytes | `pcapng: truncated section header` |
| SHB major version != 1 | `pcapng: unsupported version` |
| IDB body < 8 bytes | `pcapng: truncated interface description` |
| EPB body < 20 bytes | `pcapng: truncated enhanced packet` |
| EPB caplen > origlen | `pcapng: captured length exceeds original` |
| EPB data region or SPB data region runs past the block body | `pcapng: truncated packet data` |
| EPB/ISB interface id not declared earlier in the section | `pcapng: packet interface out of range` |
| SPB body < 4 bytes | `pcapng: truncated simple packet` |
| SPB data region != pad4(origlen) | `pcapng: bad packet padding` |
| NRB record header or padded value runs past the body | `pcapng: truncated name record` |
| IPv4 record value < 4 bytes or IPv6 record value < 16 bytes | `pcapng: bad name record` |
| DNS name not NUL-terminated inside its record value | `pcapng: unterminated name` |
| ISB body < 12 bytes | `pcapng: truncated interface statistics` |
| ISB option 6/7 present with length != 8 | `pcapng: bad statistics counter` |
| option padded value does not fit the remaining region | `pcapng: option overruns block` |
| copy/accessor called with an out-of-range block index | `pcapng: block out of range` |
| copy/accessor called with an out-of-range packet index | `pcapng: packet out of range` |
| copy/accessor called with an out-of-range option index | `pcapng: option out of range` |
| copy/accessor called with an out-of-range record index | `pcapng: record out of range` |
| copy/accessor called with an out-of-range name index | `pcapng: name out of range` |
| recorded span does not fit the buffer passed to a copy function | `pcapng: span out of bounds` |

All strings are stable API. The truncated-block-header check precedes the
SHB-first check, and the SHB byte-order magic is read before the block
length, so a short or malformed first block reports the earliest applicable
message above.

## Complexity

| Operation | Complexity |
|---|---|
| `pcapng_is_file` | O(1) |
| `pcapng_parse` | O(data.len()) time, O(blocks + records + names + options) space (payloads stay in `data`) |
| block/section/interface/packet/record/name/ISB index accessors | O(1) |
| `pcapng_option_find` | O(options) |
| copy functions | O(copied span) time/space |

## Test plan

`tests/test_conformance.xi` (`module pcapng_tests`, 19 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). The fixtures are assembled byte by byte in the
test file, not via the library. Because the codec is read-only, the
round-trip is the read-side one: every recorded span copy (block body,
packet data, option value, NRB address, DNS name) is compared byte for byte
with the bytes placed into the canonical capture.

Canonical fixture: a 368-byte two-section capture.

Section 0 (little-endian, blocks 0-5, 232 bytes):

- block 0 SHB at 0 (total 44): minor 0, section length unspecified, one
  `shb_userappl` option (code 4, "xiom-test", value at 28);
- block 1 IDB at 44 (total 28): linktype 1, snaplen 65535, one `if_name`
  option (code 2, "eth0", value at 64);
- block 2 EPB at 72 (total 44): interface 0, ts 0/1600000, caplen 4,
  origlen 6, data at 100 (`01 02 03 04`), one option code 2 (value at 108);
- block 3 SPB at 116 (total 20): origlen 3, data at 128 (`DE AD BE`);
- block 4 NRB at 136 (total 76): IPv4 record (192.0.2.1 at 148, name
  "host1.example" at 152), IPv6 record (2001:db8::1 at 172, name
  "host2.example" at 188), end-of-records;
- block 5 unknown type 65535 at 212 (total 20): body `AA BB CC DD 00 00 00 00`.

Section 1 (big-endian, blocks 6-9, 136 bytes):

- block 6 SHB at 232 (total 28): minor 0, section length 108;
- block 7 IDB at 260 (total 20): linktype 101, snaplen 262144;
- block 8 EPB at 280 (total 36): interface 0, ts 1/2, caplen 3, origlen 3,
  data at 308 (`AA BB CC`);
- block 9 ISB at 316 (total 52): interface 0, ts 0/5, options code 6
  (ifrecv 100, value at 340) and code 7 (ifdrop 2, value at 352).

Coverage:

1. fixture length 368, `is_file`, block count 10, and every block type,
   offset, total length, body length and section ordinal pinned;
2. both sections: order 1/0, lengths -1/108, version 1.0, guarded indices;
3. interfaces: linktype 1/101, snaplen 65535/262144, blocks 1/7, sections
   0/1, guarded indices;
4. packets: kinds EPB/SPB/EPB, global interfaces 0/-1/1, blocks 2/3/8,
   sections 0/0/1, guarded indices;
5. packet timestamps (0/1600000, 0/0, 1/2; composed 1600000, 0,
   4294967298), caplen 4/3/3, origlen 6/3/3, data offsets 100/128/308;
6. packet data copies `01 02 03 04`, `DE AD BE`, `AA BB CC`; out-of-range
   and a 200-byte truncated source buffer (`span out of bounds`);
7. options: count 5, blocks/codes/offsets/lengths pinned, first-match
   `option_find` including absent code and invalid block, value copies for
   "xiom-test", the EPB flag and the BE ifrecv counter, out-of-range index;
8. NRB: record types 1/2, blocks 4/4, one name each, IPv4/IPv6 address
   copies, name spans 152/188 length 13, name copies, guarded indices;
9. ISB: interface 1, block 9, ifrecv 100, ifdrop 2, guarded indices;
10. unknown block type keeps type 65535 and its raw body span;
11. first block must be an SHB (empty input, IDB-first file, 12-byte
    non-SHB block) and a short tail is `truncated block header`;
12. total length 10, 13 and 400 are `bad block length` / `bad block length`
    / `truncated block`;
13. trailing length patched on block 0 and block 2 ->
    `total length mismatch`;
14. option padding overrun and a 4-byte statistics counter -> documented
    errors;
15. EPB caplen 8/origlen 4, caplen 8 with 4 data bytes, and an undeclared
    interface -> documented errors;
16. SHB wrong byte-order magic, major 2, 8-byte body -> documented errors;
17. SPB bad padding, truncated data, empty body -> documented errors;
18. NRB 2-byte IPv4 value, unterminated name, truncated record, and an
    unknown record type plus end-of-records marker being skipped;
19. `is_file` matrix: fixture and 12-byte head true; empty, 11 bytes, zeros
    and byte-swapped magic false.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.pcapng
```

Last verified: compiler 0.61.3,
`port: PASS (passed=19 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Read-only index; there is no writer, builder or repair path.
- Packet payloads are opaque; `linktype` is reported but protocol headers are
  not parsed.
- No name resolution beyond NRB field parsing; names are byte spans, not
  `Str` values, and only record types 1 and 2 are indexed.
- ISB timestamps and option codes 4/5 (start/end time) are not indexed;
  only the ifrecv/ifdrop counters are exposed.
- Section length, snaplen and `caplen <= snaplen` are reported, not
  enforced; `origlen` may exceed the data region only for EPB (caplen is
  checked), while an SPB with a truncated payload is rejected.
- An SPB cannot distinguish data padding from data; the documented policy
  requires `data region == pad4(origlen)`.
- `pcapng_parse` is all-or-nothing on a malformed block (no valid prefix).
- Copy functions allocate a fresh `Vec[UInt8]` per call; repeated access is
  O(span) each time. The source buffer must outlive the index passed back to
  them.
- The 64-bit timestamp/counter composition overflows for values with bit 63
  set (not representable in a signed Int).
- Not thread-safe; `PcapngFile` is a plain value type over shared source
  bytes.

## Compiler / stdlib notes for v0.61.3

- Free functions only, no `self` methods; no Vec[StructType], no Vec[fn]
  dispatch and no `[T, U]` fn-pointer generics. All index pools are
  `Vec[Int]`; every read is bound to a typed local.
- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_file`/`_err_file`/`_ok_bytes`/`_err_bytes`/`_ok_unit`/`_err_unit`
  (constructing `Result` values directly inside other functions miscompiles
  in this compiler).
- Every byte read widens with `(data[pos] as Int) & 0xFF`; the byte-order
  magic and SHB type tests are byte-sequence comparisons, avoiding masked
  constants.
- 16/32/64-bit reads are pure arithmetic (`+`, `*`); `_u64` swaps its two
  32-bit halves for big-endian sections, so `isb_ifrecv`/`isb_ifdrop` read
  correctly in both orders.
- The package declares no `extern "C"` blocks (no FFI) and no dependencies
  beyond `xiom.std`.
