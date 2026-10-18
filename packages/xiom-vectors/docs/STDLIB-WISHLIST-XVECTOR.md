<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Stdlib wishlist from the XVECTOR lane

## Lattice-tier asks (2026-10-16, top-tier directive)

> **LIVE BLOCKER (2026-10-16):** the wave-146 POSIX runtime has a build
> break -- `runtime/xiom_runtime.c:5616` uses `TCP_NODELAY` without
> `#include <netinet/tcp.h>` in the POSIX include block, so EVERY
> WSL/Linux consumer build fails (`REL-20261016-1143-xvector`, high;
> the xvector WSL gates are held on it). Windows unaffected.
> Also confirmed landed while checking: `xiom.os.event.poll` (real
> poll/WSAPoll readiness) -- the old fd-readiness ask is SATISFIED.

For the `xvector-lattice` scale-out tier (`docs/PRODUCT-ARCHITECTURE.md`;
owners: L-3 router, L-4 replica, L-5 ops). **Status refresh first
(stdlib at wave 144, re-checked 2026-10-16) -- LANDED since the
2026-10-12 re-check:** fsync/fdatasync + `sync_fd`/`fsync_dir` +
`write_all` fd path + `append_file_bytes` (wave 115; bus `-2/-3/-4`
closed), fd truncate (`truncate_fd` real, wave 117), the **mmap family**
(wave 120 `fbf4bc0`: file/anon/unmap/msync/madvise/protect/lock,
probe 297), **signals** (wave 123: `signal_install`/`signal_wait`/
`signal_pending` -- sigaction + self-pipe POSIX, console events Windows;
the graceful-drain primitive), net polish **NODELAY/SO_KEEPALIVE/
listener backlog** + refused-connect fix (wave 143), directory
**watch** (Windows-first, real), `read_at`/`write_at`, `copy_file`,
`walk_dir`, `remove_dir`. The fsync trio + fd path were verified
in-lane 2026-10-12; mmap/signals/watch land at adoption.

Open asks:

| Need | Why (lattice slice) | Priority | Workaround until then |
|---|---|---|---|
| **POSIX directory watch (inotify/kqueue)** -- `xiom.os.watch` is a documented Err on POSIX (Windows ReadDirectoryChangesW is real) | L-4 replica WAL tailing + L-5 ops on Linux/WSL; polling works but adds lag and burns cycles | medium | poll the WAL file (`read_at` + size checks) at an interval |
| **Advisory file lock (`flock`/`LockFileEx`)** -- no lock primitive exists in the tree | single-writer-per-home enforcement: a shard fails fast when a second process opens the same home (the documented OUT-OF-CONTRACT case in `docs/PRODUCT-ARCHITECTURE.md` sec. 7) | medium | operational discipline + manifest checks (no hard guard) |
| **TLS/ALPN primitives** (via the `docs/TLS_DECISION.md` binding route; PULSE filed `REL-20261015-2202-pulse` ask 1 -- XVECTOR adds itself as a requester) | direct enterprise serving for lattice: native HTTPS without an edge proxy; also shard-to-shard auth | high (ecosystem) | edge proxy terminates TLS (architecture plan sec. 11) |
| ~~fd readiness (`poll`/`select` on sockets)~~ **LANDED** (`xiom.os.event.poll`; runtime poll/WSAPoll real) | single-threaded router with many connections (L-3) | done | -- |
| ~~`f32_bits`/`bits_to_f32` (old row `-6`)~~ **LANDED** (wave 147 `80bad18`, runtime-backed; probe p_wave147) | Float32 bitcast hot path | done | -- |
| path-level `truncate`/`ftruncate` wrappers (old row `-5`; the fd path landed wave 117) | parity only | low | the real fd truncate (`truncate_fd`) |

> **Coordination bus (2026-10-10):** the open rows below are migrated to
> the private `xiom-lang/xiom-relays` repo (one item per row; `--to stdlib
> --kind wishlist`): fsync/fdatasync = **REL-20261010-1550-xvector-2**, fd
> write path = **-3**, append_file_bytes = **-4**, truncate/ftruncate =
> **-5**, f32_bits = **-6**, bounded-depth json_parse = **-7**,
> flush_stdout = **-8**; **mmap family = REL-20261012-1945-xvector-2**
> (2026-10-12, owner-requested production relay). This file keeps the
> closed history; new rows go to the bus.

Needs collected while building the xiom-xvector durable vector store with the
latest stdlib (`E:\xiom-lang\stdlib`, `/mnt/e/xiom-lang/stdlib` in WSL).
**Re-checked 2026-10-11 (closure pass) on stdlib lane HEAD `9a2b5ab`
(wave 111, committed): the durability/fd/mmap rows below are STILL OPEN;
the `str_bytes`/`json_parse` quadratic is **FIXED + verified on the
committed pin** (both xvector repros exit 0 on Windows + WSL; bus
`REL-20261011-1453-xvector` / `-1543-xvector` closed; see
`docs/repro/xv-json-parse-quadratic/`); the bounded-depth `json_parse`
row is FIXED (wave 102 `5b7bf8f`). `str_chars`/`str_code_points` were
fixed at **wave 113 (`a996f7b`)** -- the str-family is fully closed and
re-verified at that HEAD (2026-10-11).** Format:
`| Need | Evidence | Workaround | Blocks |`.

**Status detail (2026-10-12, wave 115 `c65acb5`):** the durability trio
**LANDED and is verified in-lane** (compiler v0.64.4 + stdlib checkout):
`fsync`/`fdatasync` (`fs_ffi`), `sync_fd`/`fsync_dir` (`sync_io`),
`write_all` (`sync_io`, exact partial-count loop), `io.append_file_bytes`
-- all green in `out/xv_durable_io_smoke.xi` (Windows); bus
`REL-20261010-1550-xvector-2/-3/-4` **verified + closed**. Caveat: new
runtime symbols reach released-archive consumers at the next compiler pin
that re-vendors stdlib/runtime; the lane builds against the checkout.
`truncate`/`ftruncate` (`-5`) is still `acked` (segment rotation covers D5
until it lands). The mmap family is queued in the runtime bundle after the
durable-IO core (`REL-20261012-1945-xvector-2` acked).

- **History (2026-10-11, pre-wave-115; superseded by the 2026-10-12 block
  above):** fsync/fdatasync + the whole `sync_io` fd path were documented
  stubs; there was no `append_file_bytes`; `truncate`/`ftruncate` stubs.
- The mmap family is still stubbed (P5 gate): `xiom/os/mmap.xi`
  (12 documented stubs) + `fs_ffi.mmap`/`munmap`/`msync`/`madvise`/
  `mlock`, all "not available in the pure stdlib". Re-checked 2026-10-12 on
  `cd281b7` (`mmap_anonymous` Err); **queued as
  `REL-20261012-1945-xvector-2` (acked; runtime bundle, after durable IO).**
- `truncate` / `ftruncate` are still stubs (`fs_ffi.xi`); bus `-5` acked.
  (D5 uses segment rotation; truncate-based retention stays D6-gated.)
- `f32_bits` / `bits_to_f32` are absent (`float.xi` has only the Float64 pair
  at `:43` / `:52`); bus `-6` acked (compiler bitcast dependency).
- `flush_stdout` (`io.xi:906`) is still an empty body; bus `-8` acked.
- **`slice.str_bytes` / `json_parse` quadratic: FIXED + verified on
  stdlib main `9a2b5ab` (wave 111)** (`json.xi` sha256 `E69E0275...`,
  `slice.xi` `874A8F67...`, `string.xi` `36D1F4FF...`; both repro probes
  exit 0 on Windows + WSL; full xvector batteries green on the committed
  pin; bus `-1453`/`-1543` closed). The lane keeps the byte-level fast
  scanner as the canonical hot path regardless (`src/api/json_fast.xi`,
  `probe_json_fast`).
- The byte-file APIs XVECTOR depends on work and are byte-exact/CRLF-clean
  since 0.64.2: `write_file_bytes` (`io.xi:918`), `read_file_bytes`
  (`io.xi:946`), `file_size` (`io.xi:977`).
- The 2026-10-09 `io.read_file` Str-content and tiny-read defects
  (XVC-C-11/C-12) were **compiler lowering bugs, fixed in compiler v0.64.2**
  -- no stdlib action needed.

Already available and adopted by XVECTOR (no row needed): `io.read_file_bytes`
/ `io.write_file_bytes`, `io.file_size`, `io.rename` (atomic temp+rename is
possible today -- a candidate hardening for `wal_file` checkpoints; noted in
SESSION), `io.create_dir(_all)` / `remove_file`, `xiom.hash.crc32_ieee` /
`crc32c` / `crc64_ecma` (WAL record checksums), `xiom.num.float.float_bits` /
`bits_to_float` (exact Float64 bitcast since v0.64.0/m194), `xiom.crypto`
SHA-256/HMAC (env-free since v0.64.0), `slice.str_bytes`.

| Need | Evidence (file:line or app path) | Workaround | Blocks |
|---|---|---|---|
| **`fsync`/`fdatasync` on a file (or fd)** -- the single highest-impact durability primitive for a WAL. `xiom.os.fs_ffi.fsync/fdatasync` and `xiom.os.sync_io.sync_fd/fsync_dir` are documented-Err stubs ("fsync syscall not available in the pure stdlib"). | `stdlib\xiom\os\fs_ffi.xi:238` (`fsync`), `:246` (`fdatasync`); `stdlib\xiom\os\sync_io.xi:80` (`sync_fd`), `:88` (`fsync_dir`). XVECTOR ROADMAP Phase 2 "fsync on commit" is [STOP] on exactly this gap; `wal_writer_flush` today is an in-memory no-op (`src\engine.xi`); the packages lane's new `xiom.wal` ships `wal_flush` as an honest no-op on the same gap. | none in-process; documented as not-durable until fixed (ROADMAP Phase 2). PULSE filed the same need earlier; XVECTOR + `xiom.wal` are requesters. | crash-safe acknowledged writes (Phase 2 exit criterion); any real database; M2 delta append log |
| **A byte-level fd write path: `write_all(fd, &Vec[UInt8])` actually implemented** (open an fd via `io.open`, append/write bytes, then sync). Every `xiom.os.sync_io` fd helper is a documented stub: `read_exact`, `write_all`, `read_until_eof`, `read_line_buffered`, `copy_fd`, ... | `stdlib\xiom\os\sync_io.xi:28` (`write_all`), module header: "All require raw fd syscalls ... every function is a documented stub"; `io.open` (`stdlib\xiom\io\io.xi:502`) returns an fd that has no write API to pair with. | whole-file `read_file_bytes`/`write_file_bytes` (O(file) per WAL append -- unusable for a log); XVECTOR keeps the WAL in memory + whole-file checkpoints (`durability.wal_file`). | append-only WAL segments, segment files, any durable log |
| **`io.append_file_bytes(path, &Vec[UInt8])`** -- `append_file` is `Str`-only and `write_file_bytes` rewrites the file; a WAL appender needs byte append without a full rewrite. | `stdlib\xiom\io\io.xi:268` (`append_file(path, content: Str)`), `:918` (`write_file_bytes` whole-file), `:946` (`read_file_bytes`). | read-modify-write via the byte APIs (O(file) growth) or in-memory WAL (current); `xiom.wal` uses line appends via the Str path. | same as above (WAL segments) |
| **`f32_bits(Float32) -> Int` / `bits_to_f32(Int) -> Float32`** -- direct IEEE-754 bitcast for 32-bit floats; today only the Float64 pair exists. | `stdlib\xiom\num\float.xi:43` (`float_bits(Float64)`), `:52` (`bits_to_float(Float64)`); XVECTOR's WAL codec goes `f as Float64` -> `float_bits` -> store, and back on decode (exact, but two conversions per dimension). | `float_bits(v as Float64)` / `bits_to_float(b) as Float32` in `src\payload\payload.xi` `vector_encode`/`vector_decode` -- exact, just indirect. | efficiency only (hot path once fsync lands) |
| **`truncate`/`ftruncate` on a path/fd** -- needed to truncate a WAL segment after a checkpoint, and to repair a torn tail in place. | `stdlib\xiom\os\fs_ffi.xi:151` (`truncate`), `:160` (`ftruncate`) -- documented stubs. | none; XVECTOR recovery skips torn records instead of repairing the file (`wal_load` returns the longest valid prefix); `xiom.wal` heals by temp+rename truncate. | WAL checkpoint/compaction file lifecycle (Phase 2/5) |
| **Durable `io.flush_stdout`** (PULSE row; XVECTOR adds itself as requester): redirected long-running process logs are lost on abnormal exit because `flush_stdout` is an empty body. | `stdlib\xiom\io\io.xi:906` (`flush_stdout` empty; comment says stdio is line-buffered -- false for redirected output). XVECTOR probe runners capture output to files; evidence can be lost on crash/abort. | write evidence to files explicitly (scripts), or keep runs short. | observability of long-running servers/probes |
| **Bounded-depth `json_parse` (recursion guard)** -- `xiom.serialize.json.json_parse` recurses per nesting level; a ~60 KB run of `[` (well under typical body limits) overflows the process stack: **access violation 0xC0000005, exit -1073741819** (found by `probe_http_fuzz`, M-S4). Balanced nesting is fine to ~4 k depth; unbalanced 60 k depth crashes before any error path. **FIXED 2026-10-10 (wave 102 `5b7bf8f`); bus item -7 verified + closed.** | `stdlib\xiom\serialize\json.xi` (`json_parse`); repro: the `probe_http_fuzz` `t-unbalanced` case (pre-guard the probe died at that mark). | XVECTOR pre-scans request bodies with `json_depth_ok(body, 64)` at the HTTP edge (`src\api\http_service.xi`) and rejects deeper payloads with 400 before the parser sees them; the stdlib should add an internal depth cap returning `Err`. | DoS-safety of any service parsing untrusted JSON |
