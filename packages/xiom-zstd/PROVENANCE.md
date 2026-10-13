# PROVENANCE -- xiom.zstd

Owner policy: docs/UPSTREAM-FIRST.md (upstream-first, 100% of the declared
surface). This package is an FFI binding (lane gate G6/G7): it compiles the
upstream implementation unmodified and wraps it -- no upstream code is copied
into the XIOM modules.

## 1. Upstream + pin

| Field | Value |
|-------|-------|
| Project | Zstandard -- `https://github.com/facebook/zstd` |
| License | BSD-3-Clause (chosen from the dual BSD-3/GPLv2; `vendor/LICENSE`) |
| Delivered pin | tag `v1.5.7` -- commit `f8745da6ff1ad1e7bab384bd1f9d742439278e99` (annotated tag object `ac66b19e6bd6b83238bf008eecc1298105298532`) |
| Source archive | `https://github.com/facebook/zstd/releases/download/v1.5.7/zstd-1.5.7.tar.gz`, SHA256 `eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3` (verified against the published `.sha256` asset) |
| Study clone | `E:\repos\zstd` (shallow, tag `v1.5.7`, commit `f8745da6`; registered in `E:\repos\CLEANUP.md`, review-after 2026-12-01) |

Header parity check (2026-10-13, this touch): the clone's `lib/zstd.h` and the
vendored `vendor/zstd.h` are byte-identical (SHA256
`9B4BC8245565C98CCFC61C07749928B57E7C0F6FDDB0530C4F6AA1971893D88B`), so the
declaration oracle matches the delivered pin exactly.

## 2. Vendored artifact (G2 pin)

The official **single-file amalgamation** generated from the pinned release
(upstream `build/single_file_libs/combine.py`, command + normalization note in
`SPEC.md` section 2) is vendored byte-for-byte and compiled into the test
binary; `vendor/zstd.c` is LF-normalized before the pin is taken. Full byte
table (bytes + SHA256) for `vendor/zstd.c`, `vendor/zstd.h` and
`vendor/LICENSE`: `SPEC.md` section 2. Re-pin procedure: `SPEC.md` section 2.

## 3. What was studied; derived vs independent

**Upstream code (vendored, unmodified):** the amalgamated zstd 1.5.7
implementation (`vendor/zstd.c`) and its public header (`vendor/zstd.h`),
compiled through the 4-line `src/zstd_all.c` shim (`STATIC_BMI2 0`; the shim
is ours and the vendored file is unchanged).

**Independent (XIOM-authored, MIT OR Apache-2.0):** `zstd.xi` -- every
`extern "C"` declaration (7 functions, transcribed from the pinned header)
and every safe wrapper, the int-to-string helper, and the entire ZSTC
container framing surface (writer, builder, reader, seek, `frame_at`) added
in 0.3.0. The ZSTC container format is **original to this package**: a small
own format (16-byte header + raw frames + per-frame offset/size index,
documented in `SPEC.md` section 5). It is not the upstream "seekable format"
plugin and no upstream container code or layout was copied; only the
one-shot `ZSTD_compress`/`ZSTD_decompress`/`ZSTD_getFrameContentSize` entry
points are used, through the wrappers.

## 4. Test vectors / golden data

No upstream vectors were imported. Verification is against the live vendored
library: the version assertion pins 1.5.7 at run time, and every codec check
is a round-trip through the real amalgamation (real ratios, byte-identical
restores, invalid frames rejected with real `ZSTD_getErrorName` text). The
container checks build on frames produced by that same library and add
byte-exact layout checks, out-of-order random access, typed corrupt/truncated
rejection and the empty-container/empty-frame edges.

## 5. Declared surface (100% implemented)

FFI-exposed C subset (declared in `zstd.xi`, transcribed from
`vendor/zstd.h`): `ZSTD_versionNumber`, `ZSTD_compressBound`,
`ZSTD_compress`, `ZSTD_decompress`, `ZSTD_getFrameContentSize`,
`ZSTD_isError`, `ZSTD_getErrorName`. Every declared extern has a public safe
wrapper (7/7; 0 skips). The rest of the zstd C API is explicitly out of the
declared surface (`SPEC.md` section 5), not a silent gap.

Public XIOM surface (all implemented, no stubs): version/`compressBound`/error
helpers, one-shot compress/decompress/auto, frame content size, the ZSTC
constants + `ZstdContainer`/`ZstdContainerBuilder` types, writer, builder
(new/count/append/finalize), reader (open/frame_count/total_size/
index_offset), frame accessors (offset/size/out_size), seek-by-index and
`frame_at`.

## 6. Link model

Static: `port.args.json` passes `--c-source ${PACKAGE_DIR}/src/zstd_all.c` at
port time. No system libzstd, no runtime DLL, no dl-load, no soname probe.
License split: `vendor/` is BSD-3-Clause; everything outside `vendor/` is
MIT OR Apache-2.0.

## 7. Evidence

`tests/test_conformance.xi` (24 checks) run through
`scripts/port.ps1 -Package xiom.zstd -TimeoutSec 240`; the recorded x2 run
(toolchain `v0.64.4`, counts + commit) lives in `STATUS.json`.
