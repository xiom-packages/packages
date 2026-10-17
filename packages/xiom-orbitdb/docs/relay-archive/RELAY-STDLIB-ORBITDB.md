# Relay: ORBITDB -> stdlib lane (paste-ready)

**From:** ORBITDB lane (`E:\xiom-projects\xiom-orbitdb`, embedded database
engine: B-Tree, WAL, crash recovery). **Pin (current 2026-10-09):** compiler
v0.64.2, stdlib `e7896ff`. The body below was written on v0.64.0; a status
footer records what has landed since. Full table:
`docs/STDLIB-WISHLIST-ORBITDB.md`.

Hi stdlib lane -- ORBITDB bootstrapped a real durable-WAL probe this
session: append records -> hard kill -> torn tail -> reopen/replay -> heal,
GREEN on Windows and WSL, plus a 200-record soak
(`tests/probes/probe_wal_file.xi`, `scripts/crash_test.{ps1,sh}`). The WAL
wishlist rows, in priority order for a database:

1. **fsync/durability**: no `fsync`/`FlushFileBuffers`/`_commit` wrapper
   anywhere in the runtime -- WAL "durable" today means OS write-back. This
   is the row between ORBITDB and an honest Phase-2 durability claim
   (`docs/wal-and-recovery.md` states the limit). PULSE filed it first;
   ORBITDB re-confirms with a storage-engine use case.
2. **`io.read_file_lines` should normalize a trailing `\r`** (or document
   the requirement). On Windows-produced CRLF segments, `parse_int` gets
   `"10\r"`, records are silently dropped, replay count goes wrong
   (reproduced: applied=0 until every line went through `trim.str_trim`).
3. **Append with tail repair + flush**: `io.append_line_sync(path, line)`
   that ensures a newline boundary before writing and flushes. Every durable
   log consumer hand-rolls this (ORBITDB `heal_tail`, PULSE store); our
   crash test failed (`applied=3` vs 4) until tail repair landed.
4. **Truncate / checkpoint primitive**: `io.rename` exists, nothing
   truncates in place -> WAL checkpoint/segmentation has no primitive yet
   (ROADMAP Phase 2).
5. **Byte-level IO**: `io.read_bytes`/`write_bytes`/append-bytes. Phase 1
   needs a byte-packed page codec; today everything is `Str`-based, and
   `xiom.hash.crc.crc32c(&Vec[UInt8])` cannot be fed from disk without it.
6. **Tail check without reading the whole file**: `io.file_last_byte` /
   `ends_with_newline`; our heal currently reads the full segment per
   append (quadratic).

Positives to keep: `io.sleep(ms)` is load-bearing for killable hang loops
(an empty spin loop is optimized away), `io.append_line`/`read_file_lines`
are workable, `env.var_or` is the right probe seam, and `xiom.hash.crc.crc32c`
is ready for the Phase-1 page checksum the moment byte IO lands. Also: the
old `xiom.test` `TestCase` type is gone (`assert` returns `TestResult`) --
a doc note would help consumers; ORBITDB migrated its 93-test suite.

Happy to be the acceptance harness for rows 1-3: the crash test is a
ready-made consumer fixture for fsync + append-repair + replay.

**Update 2026-10-08 (v0.64.1 benchmarks) -- two sharp findings, in priority
order:**

1. **`str_split` is O(n^2), and `io.read_file_lines` inherits it.** Measured
   on a 5 MB / 20k-line WAL segment: `io.read_file` alone 2 ms;
   `io.read_file + str_split(content, "\n")` 44.7 s; `io.read_file_lines`
   44.1 s; scaling 10k -> 20k lines 10.5 s -> 44.1 s. This makes WAL
   replay/open quadratic (61.6 s for 20k records) and stalls every
   `read_file_lines` consumer (PULSE's JSONL store too). A one-pass scan in
   the splitter fixes all of it. Reproduce: `scripts/bench.ps1` /
   `bench.sh` (cases in `tests/probes/probe_bench.xi`).
2. **Append handle needed:** `io.append_line` opens+closes per call; our WAL
   append is 2,061 ops/s at best and the rest is open/close churn.
   `io.open_append(path) -> Handle` (write/sync/close) would fix throughput
   and give the fsync row its natural home.

ORBITDB worked around what it can in-lane (heal-state tracked in the WAL
handle: append 626 -> 2,061 ops/s) but cannot fix either of the above
without runtime support.

**Status 2026-10-09 (v0.64.2):** two rows above are RESOLVED --
`str_split`/`read_file_lines` are linear now (WAL replay of 20k records:
61.6 s -> 9.9 s) and a trailing CR is stripped per line
(`xiom/io/io.xi:1072-1073`, citing this relay). Still open: real fsync (the
new `os/fs_ffi.fsync` + `os/sync_io.sync_fd` are documented stubs), append
handle, truncate, byte IO, and the tail check. Current numbers and paths:
`docs/STDLIB-WISHLIST-ORBITDB.md`.
