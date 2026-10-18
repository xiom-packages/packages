<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# RELAY -> STDLIB (from XVECTOR, 2026-10-08)

**From:** XVECTOR lane, `E:\xiom-projects\xiom-xvector` (private; owner relays).
**Toolchain:** compiler v0.64.0; stdlib lane worktree `E:\xiom-lang\stdlib`
(`/mnt/e/xiom-lang/stdlib` in WSL), HEAD `9e64302`.

**Please read:** `docs/STDLIB-WISHLIST-XVECTOR.md` in the xvector repo. Six
rows; the top three block the file-backed WAL (ROADMAP Phase 2):

1. **`fsync`/`fdatasync`** — `xiom/os/fs_ffi.xi:238` and
   `xiom/os/sync_io.xi:80` (`sync_fd`) are documented-Err stubs
   ("fsync syscall not available in the pure stdlib"). This is the single
   highest-impact durability primitive for a WAL; `wal_writer_flush` is an
   in-memory no-op until it exists.
2. **A working fd write path** — `xiom/os/sync_io.xi:28` (`write_all`) and the
   whole module are documented stubs; `io.open` returns an fd with no write
   API to pair with.
3. **`io.append_file_bytes(path, &Vec[UInt8])`** — `append_file` is
   `Str`-only (`io/io.xi:265`) and `write_file_bytes` rewrites the file;
   an append-only log needs byte append without a full rewrite.
4. `num.float.f32_bits(Float32)->Int` / `bits_to_f32(Int)->Float32` (direct
   32-bit bitcast; today only the Float64 pair).
5. `truncate`/`ftruncate` (`os/fs_ffi.xi:151,155`, stubs) — WAL checkpoint
   truncation and torn-tail repair.
6. Durable `flush_stdout` — `io/io.xi:903` is an empty body; add XVECTOR as a
   requester of the existing PULSE row (evidence lost on abnormal exit).

**Positive confirmations:** `xiom.hash.crc32_ieee` / `crc32c` / `crc64_ecma`
exist and are adopted for WAL framing; `read_file_bytes`/`write_file_bytes`
work; `num.float.float_bits`/`bits_to_float` are exact (true bitcast,
v0.64.0/m194); SHA-256/HMAC usable env-free.

**Ask:** confirm the fd/fsync surface shape you plan (fd-based vs path-based)
so XVECTOR can target it; the lane will re-test and re-pin as soon as any of
rows 1–3 land.

**Addendum (2026-10-09): re-check on stdlib 0.64.3 -- all six rows still open.**

Re-checked the lane at HEAD `82ac2f3` (release 0.64.3, pinned to compiler
v0.64.2): `fsync`/`fdatasync` (`os/fs_ffi.xi:238/:246`), the fd path
(`sync_io.xi:28/:80/:88`), `append_file_bytes` (absent; `append_file` is
Str-only at `io/io.xi:268`), `truncate`/`ftruncate` (`fs_ffi.xi:151/:160`),
`f32_bits`/`bits_to_f32` (absent), and `flush_stdout` (`io/io.xi:906`,
empty) are unchanged. Row 1 remains the top blocker (the M2 delta log).

Notes for the lane: (a) the 2026-10-09 `io.read_file` Str-content and
tiny-read defects were compiler lowering bugs, fixed in compiler v0.64.2 --
no stdlib action needed; (b) byte-exact writes / CRLF-clean reads since
0.64.2 confirmed on our side; (c) `io.rename` exists -- XVECTOR will use
temp+rename for atomic WAL checkpoints while fsync is pending (so the ask
is narrower than before: fsync + append-bytes are the critical pair).
The `xiom.wal` package (packages lane) is gated on the same fsync row --
one primitive unblocks three consumers.
