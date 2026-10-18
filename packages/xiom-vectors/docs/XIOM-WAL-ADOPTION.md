<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xiom.wal adoption -- first consumption + alignment (2026-10-10)

The lane's declared ecosystem intent: **`xiom.wal` is the single WAL home**
(`docs/PACKAGE-WISHLIST-XVECTOR.md`). This record documents the first
adoption slice: the registry package is now consumed from this project,
gated by `probe_package_wal`, with the registry signing key pinned.

## Status

- **Consumed:** `xiom.wal` **0.1.0** installed from
  `https://registry.xiom-lang.org` on Windows (`XIOM_HOME/packages/
  xiom-wal-0.1.0`) and WSL (`~/.local/share/xiom/packages/xiom-wal-0.1.0`);
  sha256 `c727fb43...a9ab4` verified, ed25519 signature verified and the
  key pinned with `xiom pkg trust` (fingerprint
  `4f:3b:47:f3:ae:17:b1:3c`) on both platforms.
- **Wired:** `xiom.toml` gained `[dependencies] xiom.wal = "0.1.0"`.
  C-PULSE-02 is **resolved in v0.64.2**: the dependency-root resolver reads
  `xiom.toml [dependencies]` and adds installed package roots to the
  catalog -- the legacy `package.xi deps:` block is not consumed for source
  roots (confirmed by the xiom.durable lane's manifest comment and by our
  own file-mode build of a `use xiom.wal;` unit).
- **Gated:** `tests/probes/probe_package_wal.xi` (9 checks) -- op-code
  alignment, tagged roundtrip (lsn/op/key/value/payload/timestamp), LSN
  resume, torn-tail skip + heal-on-open, missing-path open; wired into both
  CI batteries.

## Alignment findings (why this is the single home)

| Axis | Lane codec (`durability.wal`/`wal_file`) | `xiom.wal` 0.1.0 | Status |
|---|---|---|---|
| Op codes | Insert 1, Update 2, Delete 3, SegmentSeal 4, ManifestUpdate 5, Checkpoint 6, SnapshotMarker 7 | identical 1..7, plus BeginTxn 8 / CommitTxn 9 / AbortTxn 10 | **byte-identical** (reconciled; pinned by the probe) |
| Record shape | `{ lsn; op; key; value; payload: Vec[Int] }` | `{ lsn; op; key; value; payload: Vec[Int]; timestamp }` | payload carrier identical; theirs adds `timestamp` |
| LSN semantics | 1-based, monotonic, checkpoint-resumed | 1-based, `wal_open` resumes at last+1 | identical |
| Torn tail | reader keeps the longest complete prefix; recovery skips malformed | `wal_replay` skips malformed lines; `wal_open` heals the file (temp+rename truncate) | equivalent outcomes, gated on both sides |
| Disk segment | whole-file text checkpoint (`xvector-wal 1` header + `lsn op key value payload` lines), temp+rename | append-only lines `lsn|op|key|value|timestamp[|payload-csv]`, `io.append_line`, state-tracked heal | **different framing** -- the migration target for D5 |
| Flush | in-memory no-op | `wal_flush` honest no-op returning true (same stdlib fsync seam) | same gate; one-line swap when fsync lands |

## Migration plan (slices, not this pass)

1. **D5 (delta append) prep:** when the stdlib fsync chain lands, migrate
   the lane's disk path to the `xiom.wal` segment format (append-only +
   heal-on-open) and keep our whole-file checkpoint only as the compaction
   output (either format can be re-encoded). The engine's in-memory
   `WalWriter` stays as the write-buffering layer; its records map 1:1
   (`timestamp` defaults to 0 until the engine carries wall time).
2. **Recovery stays lane-owned:** routed multi-collection replay,
   ManifestUpdate v1/v2/v3 families and checkpoints are engine concerns;
   `xiom.wal` provides the record vocabulary + disk segment, not the
   collection registry semantics.
3. **Format migration:** `xvector-wal 1` files remain readable by the lane
   loader; the D5 slice will document the one-way migration (old checkpoint
   -> new segment) and gate it with prefix-equality probes.
4. **fsync seam:** adopt `xiom.wal`'s `wal_flush` call-site discipline so
   the stdlib fsync landing is a one-line change on both sides.

## Other registry primitives discovered (scheduled follow-ups)

`xiom pkg install` surfaced packages already installed on this machine that
the lane previously listed as "later phase":

| Package | Version | Relevance | Planned triage |
|---|---|---|---|
| `xiom.metrics` | 0.2.0 | counters/gauges/histograms for M-O | replace `observability.metrics` internals behind the same surface (H upgrade) |
| `xiom.rate` | 0.2.0 | rate limiting for S3 | replace the token-bucket `RateLimiter` internals behind the same API |
| `xiom.router` | 0.1.0 | HTTP routing | evaluate for `http_service` route dispatch (keep the byte-level pipeline) |
| `xiom.http` | 0.1.4 | HTTP utilities | evaluate for parsing/serialization helpers; sockets stay stdlib-gated |
| `xiom.kv` | 0.1.0 | key-value store | gated on fsync (as before) |

Each adoption will be a gated slice in the same style as this one
(install + trust + dependency + probe + migration note). None of them
changes engine behavior until its slice lands.
