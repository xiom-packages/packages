# xiom.ogg -- Specification

Status: `stable` (0.1.x pure layer long green; 0.2.0 adds the vendored
libogg packet layer -- 34/34 x2 on compiler v0.64.4, see STATUS.json).
Manifest: `package.xi` (`xiom.ogg`, version `0.2.0`).
Modules: `src/ogg.xi` (`module xiom.ogg`, pure page layer, unchanged),
`src/ogg_ffi.xi` (`xiom.ogg.ffi`, the only `unsafe` module),
`src/ogg_types.xi` (`xiom.ogg.types`), `src/ogg_mux.xi` (`xiom.ogg.mux`),
`src/ogg_abi.xi` (generated ledger).
Depends on `xiom.std` (declared; the pure module imports nothing from it).
The packet layer vendors libogg v1.3.6 (BSD-3) and compiles it at port
time; see the 0.2.0 addendum below, PROVENANCE.md and docs/COVERAGE.md.

## Scope

A pure-XIOM reader for the Ogg container page layer:

- `ogg_parse_pages` walks pages, validates their structure and returns an
  `OggPages` index (offset, size, header flags, granule, serial, sequence);
- `ogg_crc32` computes the Ogg CRC-32 checksum of a buffer;
- `ogg_page_crc_ok` verifies one indexed page against its stored checksum;
- `ogg_page_count` / `ogg_page_offset` / `ogg_page_serial` are infallible
  accessors.

0.2.0 adds the libogg packet layer next to the pure layer (page building,
packet reassembly, the bitpacker and the mux/demux helpers -- section
"0.2.0 addendum" at the end of this document).

## Non-goals

- Codec payload parsing: Vorbis, Opus, Theora and any other codec, and the
  Ogg packet layer (packet boundaries across continued pages) are out of
  scope. Pages with the "continued packet" flag are indexed but not
  reassembled.
- Page building / checksum setting: there is no writer (the placeholder's
  `pages` writer and `streams`/`seek` inventory items are not part of this
  port).
- Logical bitstream demultiplexing, BOS/EOS pairing, granule ordering:
  `serials`/`sequences`/`flags` are exposed raw.
- Multiplexing, seeking, resync after corruption, Skeleton metadata.
- Streaming over files/sockets; the API works on in-memory `Vec[UInt8]`.

## Byte layout (page header, 27 bytes + segment table + body)

All multi-byte fields are little-endian. Offsets are decimal.

| Offset | Size | Field | Rule |
|---|---|---|---|
| 0 | 4 | capture | ASCII `"OggS"` (`4f 67 67 53`); required. |
| 4 | 1 | version | Must be 0. |
| 5 | 1 | header type | Raw flag byte: `0x01` continued, `0x02` BOS, `0x04` EOS. |
| 6 | 8 | granule position | u64; values >= 2^63 clamp to Int max (see below). |
| 14 | 4 | serial | u32 bitstream serial number (unsigned). |
| 18 | 4 | sequence | u32 page sequence number (unsigned). |
| 22 | 4 | checksum | u32; NOT validated by `ogg_parse_pages`. |
| 26 | 1 | segment count | `nsegs`, 0..255. |
| 27 | `nsegs` | segment table | Lacing values; body size = their sum. |
| 27 + `nsegs` | `sum(lacing)` | body | Not interpreted. |

Page size = 27 + nsegs + sum(lacing values). `sizes[i]` records this total;
`offsets[i]` is the absolute position of the page's byte 0.

## Walk rules (ogg_parse_pages)

1. `data.len() == 0` is `Err("ogg: empty input")`.
2. At each page start `pos`, with `remaining = data.len() - pos`:
   - `remaining < 27`: on the first page (pos == 0) this is
     `Err("ogg: truncated page header")`; afterwards it is
     `Err("ogg: truncated page header")` when `remaining >= 4` and the
     remainder starts with `"OggS"`, and `Err("ogg: trailing garbage")`
     otherwise.
   - capture bytes not `"OggS"`: `Err("ogg: bad capture pattern")` on the
     first page, `Err("ogg: trailing garbage")` afterwards.
   - version byte != 0: `Err("ogg: unsupported version")`.
   - `nsegs > remaining - 27`: `Err("ogg: truncated segment table")`.
   - `sum(lacing) > remaining - 27 - nsegs`: `Err("ogg: truncated page
     data")`.
   - otherwise the page is appended to the index and `pos` advances by the
     page size; the walk finishes successfully when it reaches
     `data.len()` exactly.
3. Trailing bytes that do not form another complete page are an error: the
   parser never silently ignores bytes after the last page.

Granule positions are read as unsigned 64-bit values. Any value with bit 63
set -- including the common `0xFFFFFFFFFFFFFFFF` ("-1") encoding of pages
with no completed packet -- is clamped to Int max (9223372036854775807).
Values below 2^63 (including all realistic granule positions) are returned
exactly.

## CRC-32 parameters

| Parameter | Value |
|---|---|
| Width | 32 bits |
| Polynomial | `0x04C11DB7` |
| Initial value | `0x00000000` |
| Input reflection | No |
| Output reflection | No |
| Final xor | `0x00000000` |
| Processing order | MSB-first (bit 31 of the register first) |
| Return type | non-negative `Int` (0..4294967295) |

Pinned check values (cross-checked with an independent implementation and
against the CRC-32/MPEG-2 known-answer test 0x0376E6E7 for the same
polynomial with init `0xFFFFFFFF`):

| Buffer | CRC |
|---|---|
| `""` | 0 |
| `"123456789"` (ASCII) | 2309065087 (`0x89A1897F`) |
| bytes `0x00..0x0F` | 4233616773 (`0xFC57DD85`) |
| one-page fixture, 29 bytes, checksum field zeroed | 3609392314 (`0xD722F4BA`) |

`ogg_page_crc_ok(data, page_index)` recomputes the CRC over exactly
`[offset, offset + size)` of page `page_index` with the 4 stored checksum
bytes (page-relative offsets 22..25) read as zero, then compares the result
with the stored little-endian u32 at offsets 22..25. It returns
`Ok(true)`/`Ok(false)`; Err carries the `ogg_parse_pages` error for an
invalid walk, or `Err("ogg: page index out of range")` for
`page_index < 0` or `page_index >= ogg_page_count(p)`.

## API signatures

All functions are free functions in module `xiom.ogg`:

```xi
pub type OggPages = {
  offsets: Vec[Int];
  sizes: Vec[Int];
  flags: Vec[Int];
  granules: Vec[Int];
  serials: Vec[Int];
  sequences: Vec[Int];
}

pub fn ogg_parse_pages(data: &Vec[UInt8]) -> Result[OggPages, Str]
pub fn ogg_page_count(p: &OggPages) -> Int
pub fn ogg_page_offset(p: &OggPages, i: Int) -> Int
pub fn ogg_page_serial(p: &OggPages, i: Int) -> Int
pub fn ogg_crc32(data: &Vec[UInt8]) -> Int
pub fn ogg_page_crc_ok(data: &Vec[UInt8], page_index: Int) -> Result[Bool, Str]
```

## Semantics

`ogg_parse_pages(data)`
: Structural walk as described above. Records page offsets/sizes, raw header
  type flags, clamped granule positions, unsigned serials and unsigned
  sequences in stream order. Does not validate checksums.

`ogg_page_count(p)`
: `p.offsets.len()`.

`ogg_page_offset(p, i)`
: Byte offset of page `i`; `-1` when `i < 0` or `i >= ogg_page_count(p)`.

`ogg_page_serial(p, i)`
: Unsigned 32-bit serial of page `i`; `-1` when `i` is out of range.

`ogg_crc32(data)`
: Ogg CRC-32 over every byte of `data` as-is (no byte is masked), returned
  as a non-negative `Int`.

`ogg_page_crc_ok(data, page_index)`
: `ogg_parse_pages(data)`, then range-check `page_index`, then compare the
  stored checksum with the recomputed page CRC (checksum bytes zeroed).

## Error string catalog

| Condition | Error text |
|---|---|
| Zero-length buffer | `ogg: empty input` |
| First page capture != `"OggS"` | `ogg: bad capture pattern` |
| Version byte != 0 | `ogg: unsupported version` |
| First page shorter than 27 bytes, or a later remainder that starts with `"OggS"` and is shorter than 27 bytes | `ogg: truncated page header` |
| Remaining bytes after a complete page that do not start a page header (1..26-byte non-`OggS` remainder, or capture mismatch) | `ogg: trailing garbage` |
| Segment table does not fit in the remaining bytes | `ogg: truncated segment table` |
| Lacing sum does not fit in the remaining bytes | `ogg: truncated page data` |
| `ogg_page_crc_ok` index < 0 or >= page count | `ogg: page index out of range` |

`ogg_page_crc_ok` propagates the `ogg_parse_pages` error (first failure
wins) when the buffer is not a valid walk.

## Complexity

| Operation | Complexity |
|---|---|
| `ogg_parse_pages` | O(data.len()) |
| `ogg_page_count` / `ogg_page_offset` / `ogg_page_serial` | O(1) |
| `ogg_crc32` | O(data.len()) |
| `ogg_page_crc_ok` | O(data.len() + page size) |

## Test plan

`tests/test_conformance.xi` (`module ogg_tests`, 22 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line and
returns the failure count). Fixtures are hand-built byte by byte, an
independent bit-serial reference CRC is implemented in the test file, and
CRC constants are pinned. Coverage:

1. one page (29 bytes): offset/size/flags/granule/serial/sequence pinned;
2. two pages (31 + 32 bytes): offsets `[0, 31]`, sizes, flags `[2, 4]`,
   granules `[960, 1920]`, serials, sequences `[0, 1]` pinned;
3. pinned CRC values: empty -> 0, `"123456789"` -> 2309065087, bytes
   0..15 -> 4233616773;
4. independent bit-serial reference CRC agrees with `ogg_crc32` (including
   the pinned one-page fixture CRC 3609392314);
5. flipping a covered byte changes the CRC (start, end, page body);
6. `crc_ok` true for a correct page, false for a corrupted body and for a
   zeroed stored checksum;
7. `crc_ok` verifies both pages of a two-page stream;
8. version != 0 (1 and 255) is `ogg: unsupported version`, on the first and
   second page, including `crc_ok` propagation;
9. truncated page header (1, 4 and 26 bytes) is Err;
10. truncated segment table (nsegs raised, 27-byte and 59-byte cuts) is Err;
11. truncated page data (28-byte cut, 540/541-byte cut, 62-byte cut) is Err;
12. trailing garbage (`"junk"`, 10 zero bytes, 2 zero bytes, corrupted
    second-page capture) is Err;
13. a partial second page starting with `"OggS"` is a truncated header;
14. empty input is Err, including `crc_ok` propagation;
15. bad capture pattern on the first page (bytes 0 and 3) is Err;
16. out-of-range accessors return -1 and `page_count` tracks pages;
17. `crc_ok` out-of-range indices (-1, 2, 99) are Err;
18. zero-segment page (size 27, flags 6, serial 99, sequence 7) is valid and
    CRC-verifiable; pinned CRC 4017816242;
19. 511-byte body across lacing values 255+255+1 (size 541) parses and
    verifies; pinned CRC 1086650952;
20. granule clamping: `0xFFFFFFFFFFFFFFFF` -> Int max, an 8-byte value
    below 2^63 survives exactly;
21. three multiplexed pages keep order, offsets `[0, 29, 59]`, serials
    `[11, 22, 11]`, sequences `[0, 0, 1]`, flags `[2, 2, 4]`;
22. `crc_ok` on a stream with a corrupted second page: page 0 true, page 1
    false, page 2 true.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.ogg
```

Last verified: compiler 0.61.3,
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Structure + checksum only: no codec payload parsing and no packet layer.
- No writer: pages cannot be built and checksums cannot be set.
- Granule positions >= 2^63 (including `-1`) are clamped to Int max rather
  than exposed as negative values.
- `ogg_parse_pages` never validates the checksum; a page with a bad
  checksum parses successfully unless `ogg_page_crc_ok` is called.
- The parser requires the buffer to contain whole pages only; it does not
  resync after corruption or tolerate a partial final page as a valid walk
  (any incomplete or trailing bytes are Err).
- Serial/sequence grouping into logical streams is not performed; all
  fields are raw.
- Not thread-safe; all values are plain value types.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_pages`/`_err_pages`/`_ok_bool`/`_err_bool` (constructing Results
  directly in other functions miscompiles in this compiler).
- All byte reads go through `(data[pos] as Int) & 0xFF`; UInt8 values are
  never compared against Int constants without widening.
- The CRC register is kept in an `Int` and normalized with
  `crc >= 2147483648` / `crc - 2147483648` instead of `& 0xFF` on values
  with bit 31 set (a form documented to miscompile in v0.61.3); the
  arithmetic form is exact and always yields a non-negative result.
- `OggPages` (six Vec fields) is constructed inside `ogg_parse_pages` and
  crosses function boundaries only by reference or through `_ok_pages`.
- `Str` comparisons in tests go through `xiom.string.compare.str_compare`
  (BUG 17: `==` on Str values read from a Vec lowers to a pointer
  comparison).
- No module-level const arrays and no `use` statements in the library
  module.

## Contracts (hardening pass, 2026-10-05)

Runtime-checked contracts; 18 clauses across the six entry points
(2/2/4/4/2/4). All 18 are enforced by the v0.63.1 runtime evaluator: two
consecutive `.\scripts\port.ps1 -Package xiom.ogg -TimeoutSec 60` runs ended
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)` (6.25 s / 6.20 s)
with no clause trapped, so no clause was dropped. `xiom-verify --check`
(xiom-verify v0.63.1, Z3 4.13.4) result: **0 proven / 0 violated / 13
unknown / 1 error** -- no clause is refuted. The error is the emitter
failing on the private helper `_err_bool (String)` ("unknown constant"); the
unknowns are emitter skips (`operator Lt`/`operator Ge` on non-numeric
operands, `equality with unresolved operand sort`, `unsupported expression
in contract`, `loop without invariant`, `field access '.is_ok'`), so no
clause is machine-discharged on v0.63.1. Classes follow the batch #12
clause plan: **pure scalar** = clause over `Int` parameters and the `Int`
result only (the Z3 family); **runtime** = the clause reads a `Vec` length,
a struct field or a result tag/payload, so it is enforced by the runtime
evaluator only.

| Entry point | Contract | Class |
|---|---|---|
| `ogg_parse_pages` | `ensures: data.len() < 27 => result is Err`; `ensures: result is Ok => data.len() >= 27` | runtime (guard-pair) |
| `ogg_page_count` | `ensures: result == p.offsets.len()`; `ensures: result >= 0` | runtime (field length) + pure scalar (range) |
| `ogg_page_offset` | `ensures: i < 0 => result == -1`; `ensures: i >= p.offsets.len() => result == -1`; `ensures: result >= -1`; `ensures: result != -1 => result >= 0` | pure scalar (sentinel/range) + runtime (field length) |
| `ogg_page_serial` | `ensures: i < 0 => result == -1`; `ensures: i >= p.serials.len() => result == -1`; `ensures: result >= -1`; `ensures: result != -1 => result >= 0 && result <= 4294967295` | pure scalar (sentinel/range) + runtime (field length) |
| `ogg_crc32` | `ensures: data.len() == 0 => result == 0`; `ensures: result >= 0 && result <= 4294967295` | runtime (`Vec` length) + pure scalar (range) |
| `ogg_page_crc_ok` | `ensures: page_index < 0 => result is Err`; `ensures: data.len() < 27 => result is Err`; `ensures: result is Ok => page_index >= 0`; `ensures: result is Ok => data.len() >= 27` | runtime (guard-pair) |

The sentinel clauses are the `pcap_caplen` pattern (`i < 0` and
`i >= len` return the documented `-1`), and the guard pairs mirror
`pcap_parse` (`data.len() < 24` / `result is Ok => data.len() >= 24`); the
scalar bounds record the module invariants that page offsets are
non-negative, serials fit in an unsigned 32-bit word, and every CRC result
is a non-negative 32-bit value, with `ogg_crc32(empty) == 0` pinned.

Unasserted/documented: the exact `"ogg: ..."` error strings and their
precedence order, the page-walk validation rules and the pinned CRC vectors
stay pinned by the 22-check test plan (above). The `Ok` payload of
`ogg_parse_pages` (a six-`Vec` `OggPages` value) and the `Ok(bool)`
checksum verdict of `ogg_page_crc_ok` are deliberately not asserted
(struct-result payload access and payload-truth clauses have no proven
v0.63.1 shape); granule clamping and the stored-checksum comparison stay
documented only, because they need bit-level arithmetic and `Str`
content comparison outside the supported clause grammar.

## 0.2.0 addendum -- vendored libogg packet layer

### Identity and pin

| Field | Value |
|-------|-------|
| Upstream | libogg (Ogg reference implementation, BSD-3-Clause) |
| Pin | tag `v1.3.6` = `be05b13e98b048f0b5a0f5fa8ce514d56db5f822` |
| Vendored tree | `vendor/ogg/` (5 files + `COPYING`), `vendor/MANIFEST.sha256` |
| Coverage | **53/53 declared functions bound, 0 skips** (docs/COVERAGE.md) |
| Companion entries | 7 (owned page/packet/pack struct helpers) |

`src/ogg_bridge.c` exposes one `xo_*` bridge entry point per `extern`
function of the pinned `include/ogg/ogg.h`; `tools/gen_ogg.py` parses the
header, generates `src/ogg_abi_protos.h` + the extern block inside
`src/ogg_ffi.xi` + the ledger/coverage artifacts, and fails on any
unmapped or under-defined symbol.

### ABI shape (discipline)

* state structs (`ogg_sync_state`, `ogg_stream_state`, `oggpack_buffer`,
  `ogg_page`, `ogg_packet`) are bridge-allocated; XIOM holds `Int` handles
  and never casts pointers (B-25);
* payloads cross as XIOM-owned `Vec[UInt8]`: inputs are read, copy-outs go
  into owned buffers, metadata into owned slots (page info 16 bytes,
  packet info 32 bytes; B-11/B-16/B-17/B-20/B-24);
* `ogg_sync_buffer(oy, size)` folds the upstream buffer/memcpy idiom into
  `sync_buffer(h, chunk)`; `sync_wrote(h, n)` remains the separate
  declared function (both bound);
* `oggpack_readinit` copies the owned input into a bridge-owned buffer so
  `pack_writeclear`/`pack_free` are always safe (upstream would free
  foreign memory otherwise);
* `ogg_packet_clear` never frees XIOM-owned bytes (the bridge nulls the
  packet pointer before the upstream call);
* NULL page pointers (`ogg_sync_pageseek`'s unused page out-param) are
  C-side; no bare `null` crosses from XIOM (B-23);
* error mapping: negative upstream codes become `Err("ogg: <context>
  rc=<code>")`; `pack_look`/`pack_read` keep the upstream -1
  "not enough bits" sentinel as a plain `Int` return (documented).

### Surface groups (all bound)

| Group | Functions | Notes |
|-------|----------:|-------|
| sync | 9 | `init/clear/reset/destroy/check/buffer/wrote/pageseek/pageout` |
| stream | 16 | `init/clear/reset/reset_serialno/destroy/check/eos/pagein/packetout/packetpeek/packetin/iovecin/pageout/pageout_fill/flush/flush_fill` |
| page | 9 | accessors + `checksum_set` (patches the owned header bytes) |
| packet | 1 | `ogg_packet_clear` |
| oggpack | 18 | write/read bitpacker incl. `get_buffer` copy-out and trunc/align/copy |

### Facade (`xiom.ogg.mux`)

* `OggMuxer`: `create` -> `add` / `add_iovec` -> `page` /
  `page_fill` / `flush` / `next_page_bytes` / `flush_page_bytes` /
  `eos` / `reset` / `destroy` (packet -> page write path);
* `OggDemuxer`: `create` -> `feed` -> `next_page` -> `reset` / `destroy`
  (byte stream -> pages);
* `demux_all(data, packet_cap)`: whole-buffer demux of one logical
  bitstream into pages + reassembled packets (`Demuxed` flat outcome).

### Fixture (opus-in-ogg)

`tests/fixtures/tone.ogg` (4341 bytes, 3 pages) is generated once by
`tools/make_ogg_fixture.xi` + `tools/gen_fixture.ps1`: a 0.5 s 440 Hz tone
encoded by the sibling `xiom.opus` package, muxed with the OggMuxer
write path (OpusHead + OpusTags + 25 audio packets), and committed as the
mux-side evidence. The suite (`t33`, `t34`) demuxes it back to 27 packets,
checks the OpusHead fields (version 1, mono, pre-skip 312, rate 48000,
family 0) and validates every fixture page against the independent
pure-XIOM page walk + CRC-32 oracle.

Upstream behavior pinned by the suite (verified against a pure-C driver):

* the first (BOS) page granule position is forced to 0 by upstream, even
  when the packet carries a different granulepos;
* `ogg_stream_pagein` assigns the page granule position only to the packet
  that ends the page; other packets on the page report -1;
* `oggpack` counters advance on sentinel (end-of-data) reads.

### Deviations / notes

* the vendored sources carry a four-line include rewrite (`<ogg/ogg.h>`,
  `<ogg/os_types.h>` -> quoted relative form): the `--c-source` pipeline
  has no `-I` support and angle includes are not resolved relative to the
  including file. Both SHA256s are recorded per file in
  `vendor/MANIFEST.sha256` (see PROVENANCE.md);
* `oggpack_readinit` copies (upstream references); the copy is invisible
  except that any pack handle is safe to clear;
* `ogg_stream_iovecin` binds the two-buffer scatter-gather shape (count 1
  or 2); iovecs beyond two are out of scope until a consumer needs them.
