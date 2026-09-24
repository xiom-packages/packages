# xiom.pcap -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.pcap`, version `0.1.0`).
Module: `src/pcap.xi` (`module xiom.pcap`).
Depends on `xiom.std`; the library module imports nothing (the tests import
`xiom.test`, `xiom.io` and `xiom.string.compare`).

## Scope

A pure-XIOM (no FFI) reader for classic libpcap capture files:

- `pcap_is_file`: cheap magic + length sniff;
- `pcap_parse`: global header plus a full index of packet records with
  endianness detected from the magic;
- `pcap_packet`: on-demand payload slice out of the source buffer;
- `pcap_packet_count` / `pcap_caplen` / `pcap_origlen` / `pcap_ts_sec` /
  `pcap_linktype`: infallible index accessors.

## Non-goals

- pcapng (the section header block magic `0x0A0D0D0A` is not accepted) and
  the obsolete modified magic (`0xA1B2CD34`).
- Writing, appending or repairing capture files.
- Protocol decoding of any kind (Ethernet, IP, TCP, ...); payloads are
  opaque bytes and `linktype` is simply reported.
- Microsecond timestamp precision (only `ts_sec` is indexed).
- Streaming/incremental parsing or zero-copy views into the buffer:
  payload slices are freshly allocated `Vec[UInt8]` copies.
- Byte-order conversion or re-encoding: the source bytes are returned
  unchanged.
- Validation of `snaplen`, version numbers or the `origlen`/`caplen`
  relation.

## File layout

### Global header (24 bytes, offsets from the file start)

| Offset | Size | Field | Encoding | Indexed |
|---|---|---|---|---|
| 0 | 4 | magic | byte sequence, see below | yes (`magic`) |
| 4 | 2 | version_major | unsigned 16-bit, detected order | yes |
| 6 | 2 | version_minor | unsigned 16-bit, detected order | yes |
| 8 | 4 | thiszone | signed 32-bit | no (skipped) |
| 12 | 4 | sigfigs | unsigned 32-bit | no (skipped) |
| 16 | 4 | snaplen | unsigned 32-bit | yes |
| 20 | 4 | linktype (`network`) | unsigned 32-bit | yes |

### Packet record (16-byte header, then `incl_len` payload bytes)

| Offset | Size | Field | Encoding | Indexed |
|---|---|---|---|---|
| 0 | 4 | ts_sec | unsigned 32-bit, detected order | yes (`ts_secs`) |
| 4 | 4 | ts_usec | unsigned 32-bit, detected order | no (skipped) |
| 8 | 4 | incl_len | unsigned 32-bit, detected order | yes (`caplens`) |
| 12 | 4 | orig_len | unsigned 32-bit, detected order | yes (`origlens`) |
| 16 | `incl_len` | packet bytes | verbatim | via `offsets` |

Records are contiguous: the next record header starts at
`record_start + 16 + incl_len`. There is no padding, alignment or
terminator. Trailing bytes shorter than a record header (1..15) are an
error (`pcap: truncated record`).

## Endianness rules

The first four bytes select the file byte order before any other field is
read:

| Bytes 0..3 | Big-endian u32 reading | Interpretation | `little_endian` |
|---|---|---|---|
| `D4 C3 B2 A1` | `0xD4C3B2A1` | classic magic `0xA1B2C3D4` stored little-endian | `true` |
| `A1 B2 C3 D4` | `0xA1B2C3D4` | byte-swapped magic `0xD4C3B2A1` stored big-endian | `false` |

Any other first four bytes are `pcap: bad magic` (once the input is at
least 24 bytes long). All u16/u32 fields -- version, snaplen, linktype,
ts_sec, ts_usec, incl_len, orig_len -- are then read with the detected
order. Because `magic` is read with that same order, a successfully parsed
`PcapFile.magic` is always `0xA1B2C3D4` (2712847316).

## API signatures

All functions are free functions in module `xiom.pcap`:

```xi
pub type PcapFile = {
  magic: Int;
  little_endian: Bool;
  version_major: Int;
  version_minor: Int;
  snaplen: Int;
  linktype: Int;
  ts_secs: Vec[Int];
  caplens: Vec[Int];
  origlens: Vec[Int];
  offsets: Vec[Int];
}

pub fn pcap_is_file(data: &Vec[UInt8]) -> Bool
pub fn pcap_parse(data: &Vec[UInt8]) -> Result[PcapFile, Str]
pub fn pcap_packet_count(p: &PcapFile) -> Int
pub fn pcap_packet(data: &Vec[UInt8], p: &PcapFile, i: Int) -> Result[Vec[UInt8], Str]
pub fn pcap_caplen(p: &PcapFile, i: Int) -> Int
pub fn pcap_origlen(p: &PcapFile, i: Int) -> Int
pub fn pcap_ts_sec(p: &PcapFile, i: Int) -> Int
pub fn pcap_linktype(p: &PcapFile) -> Int
```

## Semantics

`pcap_is_file(data)`
: `true` iff `data.len() >= 24` and the first four bytes are `D4 C3 B2 A1`
  or `A1 B2 C3 D4`. Record bytes are not inspected; a 24-byte global header
  with no records is a valid file (`PcapFile` index with zero records).

`pcap_parse(data)`
: Validates the length and magic, reads the global header, then walks
  records from offset 24:

  1. fewer than 16 bytes left -> `pcap: truncated record`;
  2. `incl_len` = the u32 at offset 8 of the record header; if
     `16 + incl_len` does not fit in the remaining buffer ->
     `pcap: truncated packet`;
  3. otherwise append `ts_sec`, `incl_len`, `orig_len` and
     `record_start + 16` to the four index vectors and continue past the
     payload.

  `incl_len == 0` is valid (an empty packet): the offset is still recorded
  and the next record starts immediately at the same payload position.
  On success all parallel vectors have equal length; the whole call is Err
  on the first malformed record (no partial index).

`pcap_packet(data, p, i)`
: `Ok` with the `caplens[i]` bytes at `offsets[i]` in `data`; an empty
  vector for a zero-length record. `Err("pcap: packet out of range")` when
  `i < 0` or `i >= pcap_packet_count(p)`; `Err("pcap: truncated packet")`
  when the recorded range does not fit in the passed `data` (for example
  when a shorter buffer is passed). The `data` passed here should be the
  same buffer that was parsed, since offsets are absolute.

`pcap_caplen`, `pcap_origlen`, `pcap_ts_sec`
: Return the recorded value for `i`, or `-1` when `i < 0` or
  `i >= pcap_packet_count(p)`. Regular values are non-negative (u32
  fields); a `-1` result therefore always means "out of range".

`pcap_linktype(p)`
: The global header `network` field (same for every record in the file).

`PcapFile` fields
: `magic` and `little_endian` describe the detected magic/order;
  `version_major`/`version_minor`, `snaplen` and `linktype` are the
  remaining global-header values; `ts_secs`, `caplens`, `origlens` and
  `offsets` are parallel vectors, one entry per record in file order.

## Error string catalog

| Condition | Error text |
|---|---|
| `data.len() < 24` | `pcap: truncated header` |
| `data.len() >= 24` but neither magic byte sequence | `pcap: bad magic` |
| 1..15 trailing bytes after the last complete record | `pcap: truncated record` |
| `16 + incl_len` exceeds the remaining buffer | `pcap: truncated packet` |
| `pcap_packet` with `i < 0` or `i >= count` | `pcap: packet out of range` |
| `pcap_packet` with a source buffer shorter than `offsets[i] + caplens[i]` | `pcap: truncated packet` |

All six strings are stable API. `pcap_is_file` never errors. The
`pcap: truncated header` check precedes the magic check: an input shorter
than 24 bytes is never reported as bad magic.

## Complexity

| Operation | Complexity |
|---|---|
| `pcap_is_file` | O(1) |
| `pcap_parse` | O(records + total payload) time, O(records) space (payloads stay in `data`) |
| `pcap_packet_count` | O(1) |
| `pcap_packet` | O(caplen) time/space |
| `pcap_caplen` / `pcap_origlen` / `pcap_ts_sec` | O(1) |
| `pcap_linktype` | O(1) |

## Test plan

`tests/test_conformance.xi` (`module pcap_tests`, 17 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). The fixtures are assembled byte by byte in the
test file, not via the library:

- **LE fixture** (62 bytes): `D4 C3 B2 A1`, version 2.4, snaplen 65535,
  linktype 1; record 1 `(ts_sec 1600000000, ts_usec 123456, incl 4,
  orig 6, payload 01 02 03 04)`; record 2 `(ts_sec 1600000001, ts_usec 7,
  incl 2, orig 2, payload AA BB)`.
- **BE fixture** (43 bytes): `A1 B2 C3 D4`, version 2.4, snaplen 262144,
  linktype 1; one record `(ts_sec 1600000000, ts_usec 0, incl 3, orig 3,
  payload DE AD BE)`.

Coverage:

1. LE fixture: length, `is_file`, magic 2712847316, `little_endian`,
   version 2/4, snaplen 65535, linktype 1, count 2;
2. LE fixture: packet slices exactly `{1,2,3,4}` and `{170,187}`;
3. LE fixture: `ts_sec` 1600000000/1600000001, caplen 4/2, origlen 6/2,
   offsets 40/60, linktype 1;
4. 24-byte header: empty record list, accessors guarded, packet 0
   out of range;
5. byte-swapped magic: fields, `little_endian == false`, slice
   `{222,173,190}`;
6. inputs shorter than 24 bytes (empty, 23-byte prefix, 4-byte magic) ->
   `pcap: truncated header` and `is_file == false`;
7. unrecognized magic (24 zeros, flipped first byte, pcapng magic) ->
   `pcap: bad magic`;
8. 8 or 15 trailing bytes after a complete record ->
   `pcap: truncated record`;
9. declared `incl_len` 10 with 4 or 3 payload bytes ->
   `pcap: truncated packet`; the exact-fit control parses;
10. packet index -1, count and 99 -> `pcap: packet out of range`;
11. accessors -1 out of range for caplen/origlen/ts_sec;
12. `is_file` matrix: both magics and both 24-byte headers true; empty,
    23 bytes, 4 bytes, 24 zeros and pcapng junk false;
13. zero-length record advances to the next record; offsets 40/56/74 and
    slices `{}`, `{9,8}`, `{7}`;
14. `pcap_packet` with a short source buffer -> `pcap: truncated packet`,
    while packet 0 still slices;
15. unsigned 32-bit fields keep their high bits (ts_sec 4294967295,
    origlen 2147483648, payload 255);
16. the truncated-header check precedes the magic check;
17. snaplen 96 / linktype 101 are read, not hardcoded.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.pcap
```

Last verified: compiler 0.61.3,
`port: PASS (passed=17 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Classic pcap only (magic `0xA1B2C3D4` / byte swap `0xD4C3B2A1`); pcapng
  and the modified `0xA1B2CD34` magic are rejected.
- No protocol decoding; `linktype` is reported but payload structure is
  left to the caller.
- Parse-only; no writer.
- In-memory `Vec[UInt8]` buffers only; no streaming parser.
- `pcap_packet` copies the payload on every call; repeated access is
  O(caplen) each time.
- `ts_usec`, `thiszone` and `sigfigs` are skipped.
- Version, snaplen and the `caplen`/`origlen` relationship are not
  validated.
- `pcap_parse` is all-or-nothing on a malformed record (no valid prefix).
- Not thread-safe; `PcapFile` is a plain value type over shared source
  bytes.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_file`/`_err_file`/`_ok_bytes`/`_err_bytes` (constructing `Result`
  values directly inside other functions miscompiles in this compiler).
- Every byte read widens with `(data[pos] as Int) & 0xFF`; `UInt8` values
  are never compared with `Int` constants without widening.
- `PcapFile` (ten fields) is constructed inside `pcap_parse` only and
  crosses function boundaries by reference or through `_ok_file`,
  following the `xiom.tar` `TarArchive` and `xiom.bmp` `BmpInfo`
  precedents.
- Vec reads are bound to typed locals (`let caplen: Int = ...`) before use;
  all four index vectors are `Vec[Int]`.
- The module has no `Str` fields and never compares `Str` values, so the
  BUG 17 pointer-comparison pitfall does not arise inside it; the tests
  route every error-string check through `str_compare`.
- 16/32-bit reads are pure arithmetic (`+`, `*`, `/`, `%`), which avoids
  the v0.61.3 mask/bit-set miscompiles seen in bit-manipulating modules.
- The package declares no `extern "C"` blocks (no FFI).
