<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# XIOM ORBITDB -> stdlib lane: wishlist

> **Bus (2026-10-10):** open rows migrated to `xiom-relays` as separate
> items: fsync `REL-20261010-1550-orbitdb-3`, append handle `-4`, truncate
> `-5`, byte-IO random access `-6`, append+repair `-7`, tail check `-8`.
> Track them there (pull + `relay.py view --lane stdlib`); this file keeps
> the resolved history below.

**Relay:** hand this file to the stdlib-lane session. ORBITDB is a consumer
lane; it never edits `E:\xiom-lang\stdlib`. Evidence paths are from
`E:\xiom-projects\xiom-orbitdb` (app context) or exact stdlib `file:line` on
the pin below.

**Pin (2026-10-09):** compiler **v0.64.2**, stdlib `E:\xiom-lang\stdlib` @
`e7896ff` (wave 97 + the lane's own wishlist sweep + relay consumption;
linear-split/CR fixes in the code state since `82ac2f3`), `XIOM_RUNTIME_DIR`
retired (env-free).

**Context:** ORBITDB is a durable embedded database: append-only WAL segment
with hard-kill crash/reopen and torn-tail healing, incremental
generation-committed checkpoints, buffer-until-commit transactions, a
snapshot page log, a clock buffer-pool, a deterministic fuzz harness, and a
120-test conformance suite -- green x2 on Windows + WSL (v0.64.2, workarounds
reverted). The rows below are what still stands between the probe and a
byte-level, power-loss-honest storage engine.

## Resolved on the current stdlib (your wave 96/97 sweep)

| Was | Evidence now | Result |
|---|---|---|
| **`str_split` / `io.read_file_lines` O(n^2)** (the old headline row): 5 MB / 20k lines took ~44 s. | `xiom/string/split.xi` documents `O(\|s\|)`; `xiom/io/io.xi:1072-1075` documents `read_file_lines` `O(n)`. ORBITDB bench on v0.64.2: WAL replay of 20k records **61.6 s -> 9.9 s** (`scripts/bench.ps1 -N 20000`, `wal_replay`). | **RESOLVED** -- every line-oriented consumer is linear now; thank you. |
| **`io.read_file_lines` CRLF handling**: Windows files carried `"10\r"` into `parse_int`, silently dropping records. | `xiom/io/io.xi:1072-1073` explicitly strips a trailing CR per line ("ORBITDB relay 2026-10-08"). | **RESOLVED** -- the per-line `trim.str_trim` is still harmless belt-and-braces in ORBITDB. |

## Open items

| Need | Evidence (file:line or app path) | Workaround | Blocks |
|---|---|---|---|
| **Durable flush: real `fsync`/`FlushFileBuffers`/`_commit`.** The stub surface now exists but does nothing: `xiom/os/fs_ffi.xi:238 fsync(fd)` and `xiom/os/sync_io.xi:80 sync_fd(fd)` both return `Err("... fsync not available in the pure stdlib")`; `io.xi` has no path-to-fd open and only `flush_stdout`. | ORBITDB `tests/probes/probe_wal_file.xi` + `scripts/crash_test.{ps1,sh}`: correct vs a simulated process kill; power-loss tail loss unmitigated; `docs/wal-and-recovery.md` states the honest limit. | torn-tail healing + accept write-back; document honesty | Phase 2 durability claims; `db_close` checkpoint; "durable" in README/SPEC. (The stdlib lane's own sweep labels this "io.fsync wal dependency" -- confirming the same seam.) |
| **Append file handle: `io.open_append(path) -> Handle` / `write_line` / `sync` / `close`.** `io.append_line` opens+closes per call; v0.64.2 bench `wal_append` 20k = **5.7 s (3 524 ops/s)** -- still open/close-bound. A held handle is also the natural fsync seam. | ORBITDB `probe_bench` case `wal_append`; `scripts/bench.ps1 -N 20000` | none (batching is unsafe for WAL semantics) | WAL commit-path throughput; fsync wiring |
| **File truncate / atomic checkpoint primitive** (`io.truncate_file(path, size)` or fd-based). `io.rename` exists; nothing truncates in place. | ROADMAP Phase 2 checkpointing; ORBITDB truncation is implemented as "write a fresh segment + rename" (`wal_file_truncate`), which is O(segment) per checkpoint. | rewrite + rename (compaction pattern) | WAL checkpoint/segment recycling beyond the rewrite pattern; bounded disk growth at scale |
| **Byte-level file IO: `io.read_bytes(path) -> Result[Vec[UInt8], IOError]` / `io.write_bytes` / append-bytes.** Today only `Str`-based file APIs exist. | ROADMAP Phase 1 byte-packed tuple/page codecs; `storage/tuple.xi`/`storage/page.xi` ship `Vec[Int]` text stand-ins. | keep `Vec[Int]` codec (not byte-true, not portable) | real page format; feeding `xiom.hash.crc.crc32c(&Vec[UInt8])` from disk |
| **Append with tail repair + flush in one call** (`io.append_line_sync(path, line)`). Every durable-log consumer hand-rolls this. | ORBITDB tracks tail state in the `WALFile` handle (`wal_file_heal_tail`); the first append after a torn tail needs the repair or the new record merges onto the torn line (reproduced historically; crash harness covers it now). | ORBITDB handle state (one rescan after reopen; append O(1)) | crash-safe appends without per-append rescans; part of the fsync row |
| **Tail check without reading the whole file** (`io.file_last_byte` / `io.ends_with_newline(path)`). `io.file_size` exists; no seek/random access. | ORBITDB `wal_file_open` / `page_log_heal_tail` read the whole file once per open to detect a missing final newline. | open-time detection + handle state | O(1) healed appends with no full read on large segments |

## Positive confirmations (please keep)

- **`io.sleep(ms)`** is load-bearing for crash-test hang loops (empty spin
  loops are optimized away; `io.sleep` keeps the writer alive and killable).
- **`io.append_line` creates the file and appends newline-terminated records**;
  `io.read_file_lines` returns `Result[Vec[Str], IOError]` including a
  trailing empty line for a final newline (ORBITDB skips empties).
- **`xiom.os.env.var_or`** is exactly the right probe/script seam; all ORBITDB
  probe modes are env-driven.
- **`xiom.hash.crc.crc32c(data: &Vec[UInt8]) -> UInt32`** exists and is ready
  for the byte codec; ORBITDB ships a bitwise CRC32C meanwhile (KAT-locked).
- **String kit**: `str_split`, `str_trim`, `str_ends_with`, `parse_int`
  cover the record codecs; with the linear `str_split` the whole kit is now
  production-shaped.
- **`io.list_dir`** (resolved m211 per your sweep) fits the future page-file
  directory/database listing.
- **Compiler-side bonus that helps consumers:** deep container equality
  (v0.64.2/m239) -- `Vec[Int] == Vec[Int]` and `Str == Str` compare by
  content (verified 2026-10-09); ORBITDB can retire hand-written `vec_eq`
  helpers over time.

## Notes for the stdlib lane's own coverage

- `probe_wal_file.xi` is a ready-made consumer fixture for the fsync and
  append-repair rows (write -> hard kill -> torn tail -> replay -> heal on
  both platforms; `scripts/crash_test.sh` runs in WSL).
- Your wishlist sweep at `bbf48fa3` (v0.64.2 statuses) is acknowledged; the
  new rows you recorded there (empty-read clause, `to_string_char(Char(0))`,
  whole-body cast miscompile) are tracked on your side and are not ORBITDB
  blockers today.
