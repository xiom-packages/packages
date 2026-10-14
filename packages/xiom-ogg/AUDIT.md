# xiom.ogg -- AUDIT (0.2.0)

Audit of the libogg packet-layer landing. The 0.1.x pure page layer is
unchanged; its 22 checks keep running unchanged as the independent oracle
for everything the write path produces.

## 1. Surface conformance

* Oracle: every `extern` function of the pinned `include/ogg/ogg.h`
  (libogg v1.3.6).
* `tools/gen_ogg.py` fails the build if a declared function has no ABI
  mapping, if the bridge misses an entry point, or if the bridge defines
  entry points outside the generated set. Regeneration is deterministic.
* Result: **53 declared = 53 bound, 0 skips**; surface groups: sync 9,
  stream 16, page 9, packet 1, oggpack 18; 7 documented companion entries
  (owned page/packet/pack structs) -> 60 bridge entry points.
* The suite asserts the ledger (`abi.DECLARED_FUNCTIONS ==
  BOUND_FUNCTIONS == 53`, companions 7), so drift fails tests.

## 2. Discipline mapping (bindings lane, v0.64.4)

| Rule | Compliance |
|------|-----------|
| B-11/B-16/B-17 | one owned slot per out-param: page info (16 B), packet info (32 B); `xo_page_set`/`xo_packet_set` fill owned structs from caller buffers |
| B-20/B-24 | page/packet copy-out reads only owned buffers; accessors operate on a struct whose pointers are caller-owned; no foreign-pointer reads from XIOM |
| B-23 | no bare null: `ogg_sync_pageseek`'s unused page pointer is NULLed in C; all XIOM calls pass real owned buffers |
| B-25 | handles are `Int` produced by bridge allocations; no XIOM-side casts; `xo_packet_clear` nulls the pointer before the upstream free so XIOM memory is never freed |
| B-26 | flat outcomes (`PageOut`, `PacketOut`, `Demuxed`); no `Result[Option[T]]` |
| G5 | `unsafe` only in `xiom.ogg.ffi`; externs generated inline there (v0.64.4 resolves externs from the calling module) |

## 3. Test evidence (34/34 x2, compiler v0.64.4)

New in 0.2.0 (12 checks): ledger; bitpacker LSB-first write/read round trip
(`FD FF FF` byte-exact, sentinels, trunc/align/copy/reset/clear lifecycle);
muxer->sync->page accessor + stream reassembly round trip (3 packets, flags,
granule, page sequence); muxed pages validated by the pure-XIOM page walk +
CRC-32 oracle; pageseek aligned/skip/recover; page accessor +
`checksum_set` cross-checked against the pure CRC oracle; iovec
scatter-gather packet; `pageout_fill`/`flush_page_bytes`; `packet_clear`
ownership; sync/stream lifecycle entry points; fixture demux (3 pages,
27 packets); fixture OpusHead fields + granule math + all-page CRC.

**Fixture evidence** (`tests/fixtures/tone.ogg`, 4341 bytes): generated
once by `tools/make_ogg_fixture.xi` -- a real 0.5 s/440 Hz encode by the
sibling `xiom.opus` package, muxed by this package's OggMuxer
(OpusHead gp 0 BOS; OpusTags; 25 audio packets at 64 kbps with
granulepos 312 + n*960; EOS on the last). The suite demuxes it, checks the
identification header (version 1, mono, pre-skip 312, rate 48000,
family 0), and re-validates **every page against the pre-existing pure
implementation** -- write path and independent read path agree.

Behavior pinned against a pure-C driver compiled from the same vendored
sources (test expectations corrected to upstream ground truth):

* upstream forces the granule position of the first (BOS) page to 0, even
  when the packet carries another granulepos;
* `ogg_stream_pagein` assigns the page granule position only to the packet
  that ends the page; earlier packets on the page report -1;
* `oggpack` byte/bit counters advance on end-of-data sentinel reads
  (the suite checks exact counters before the sentinel reads);
* `opus`-family packet payloads are never interpreted here; the fixture
  proves container fidelity, and `xiom.opus` owns decoding.

## 4. Compiler/toolchain findings observed (v0.64.4)

1. **`Result[Vec[Struct]]` payloads crash** (0xC000001D) when read:
   `Result[Vec[PacketOut], Str]` `.value` access died; wrapping the Vec in
   a named struct (`Demuxed`) or returning the existing `Result[Demuxed]`
   shape is stable. Recorded for the lane.
2. **`<angle>` includes cannot be resolved** by `--c-source` (no `-I`);
   libogg needed the four-line rewrite (PROVENANCE section 2). The opus
   package needed the flat tree for the same reason.
3. **Module resolution is package-scoped**: the fixture generator must run
   from `packages/` where both package trees are visible (see
   `tools/gen_fixture.ps1`); placing it inside a package hides sibling
   packages.
4. `Str + Bool` concatenation and heavy nested calls inside `println`
   chains crashed on opus-lane tests; this suite formats booleans through
   `b2s()` and binds values to locals (same discipline as xiom.opus).

## 5. Known deviations / risks

* the four rewritten include lines (documented, hash-pinned both ways);
* `oggpack_readinit` copies the input (upstream references the buffer;
  the copy makes `writeclear`/`free` safe on any handle);
* `ogg_stream_iovecin` binds a two-buffer shape (any two-entry iovec
  scatter-gather); more entries are out of scope;
* `packetno` in `PacketOut` is the upstream stream packet counter; page
  granule semantics follow upstream (BOS 0 / page-final packet only).
