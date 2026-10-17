<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Checklist -- byte-page format v2 (M1.2)

> Companion to `docs/BYTE-PAGE-FORMAT-V2.md` (the frozen design). Convention:
> `[x]` done with committed evidence; `[~]` in progress/blocked with a named
> dependency; `[ ]` not started. Every code slice keeps the full evidence
> matrix: suite x2 + affected crash harness x2 + fuzz, Windows + WSL.

## S1 -- pure codec (DONE 2026-10-10)

- [x] `src/storage/block.xi`: `block_encode_page/decode_page`,
      `block_encode_header/decode_header`, `block_kind_is_free`
- [x] Strict decode: length 4096, magic/version/kind, `len <= 4056`, CRC32C,
      zero padding; every failure is `None` (no partial blocks)
- [x] Layout KATs in the suite: header bytes, LE slot bytes, CRC slot,
      padding (one page block, one header slot)
- [x] Boundary matrix: `len` 0 / 4056 accepted, 4057 rejected; empty-vector
      encode signal for invalid bytes
- [x] Corruption matrix: magic/version/kind/reserved/length/CRC/padding flips
      all reject; header `committed_generation` cross-check rejects even with
      a re-sealed CRC
- [x] Fuzz extension (DONE 2026-10-10): section (e) in `probe_fuzz.xi` --
      random page/header roundtrips + single-byte mutations (decode must
      reject or reflect the mutation); fuzz x2 Win + WSL
- [x] Evidence: suite **128/128 x2 Windows + WSL** (block v2 section: 4 tests)

## S2 -- block store over the shim (DONE 2026-10-10)

- [x] `src/storage/byte_io.xi`: the six shim functions (`read_at`,
      `write_at`, `append`, `file_size`, `truncate`, `sync`) with documented
      O(file) fallbacks; no `io.*` block IO anywhere else in the store
- [x] `src/storage/block_store.xi`: open (header-slot pick + full scan) /
      put / commit (first commit mirrors both slots, then alternates; only
      the inactive slot is written) / compact (temp+rename) / read / has /
      pages / blocks / sync; generation-monotonic commits
- [x] Page directory rebuilt at open: valid blocks only, `gen <= committed`
      filter, latest generation per page_id wins, free/malformed skipped;
      any IO error leaves the store empty rather than half-built
- [x] Probe `tests/probes/probe_block_store.xi`: 26 functional checks
      (own-writes-visible vs uncommitted-hidden-on-reopen, latest-wins,
      torn tail block, torn active slot -> previous-slot fallback, both
      slots corrupt -> empty then restored by the next commit, surviving
      pages re-committed by a later generation, compaction, capacity) plus
      writer/verify modes for the crash harness
- [x] Crash harness `scripts/block_crash_test.{ps1,sh}`: hard kill at four
      named quiescent states (pages2 / full2 / midheader / compacted), torn
      tail block appended, reopen + committed-view checks + recovery append;
      **GREEN x2 Windows + WSL** (kill only at quiescent states: the O(file)
      shim writes are not atomic until S4 -- noted in the probe header)
- [x] Fuzz: section (f) in `probe_fuzz.xi` -- block store vs model (random
      put generations, probabilistic commits, open+compare per commit);
      fuzz x2 both platforms

## S3 -- DBFile integration (INTEGRATION DONE 2026-10-10; default flip deferred to S4)

- [x] Snapshot-format knob on open: `db_file_open_cfg` /
      `db_file_open_checked_cfg` with `page_format` 1 (v1, default) | 2 (v2).
      (The `DatabaseConfig` struct field arrives with the Database-layer file
      path; the file API is the knob today.)
- [x] Reads auto-detect the on-disk format (`snap_load_auto`, first byte);
      `snap_load_v2` enforces the same strictness as v1
- [x] `snap_flush_v2`: dirty-only append + header commit at gen+1; a v1 (or
      absent) file is rewritten whole via `v2_rewrite_all` (temp+rename) =
      migration-on-write; crashed partial generations are overwritten by
      same-gen rewrites
- [x] v1 handle on a v2 file rewrites whole via `snap_compact` (format stays
      authoritative on disk)
- [x] `db_file_migrate_snapshot(path)`: idempotent in-place v1 -> v2
- [x] Probe: `ORBITDB_DB_FORMAT=v2` routes every open/write in
      `probe_db_file.xi`; **db_crash matrix 25/25 x2 Windows + WSL in v2**
      plus suite x2 both (130/130)
- [ ] Flip the default to v2: DEFERRED to S4 -- a single first full
      checkpoint at N=2000 is minutes-scale on the O(file) shim (v2 441 s
      measured; the v1 control hit the 600 s watchdog in that run; both
      shapes are dominated by per-page file IO). Default stays v1 until the
      real fixed-size IO lands, then flip + fresh bench.
- [ ] FORMATS.md "3v2" full tables: land with the default flip at S4 (the
      wire format itself is frozen in `docs/BYTE-PAGE-FORMAT-V2.md`; a
      pointer section is in FORMATS.md now)

## S4 -- stdlib byte IO + fsync swap

- [ ] Swap the shim to real `read_at`/`write_at`/`append_file_bytes`/
      `truncate`/`fsync` when the stdlib rows land (STDLIB-WISHLIST rows 1/4/5)
- [ ] Re-run the S2/S3 matrix; record before/after bench numbers (G1)
- [ ] Unblocks: M1.1b lazy node load, C3 pager seam, M2.1 fault injection
