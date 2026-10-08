# SPEC: xiom.zstd -- Zstandard bindings (vendored amalgamation)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.zstd` |
| Version | 0.2.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | Zstandard -- https://github.com/facebook/zstd |
| Upstream version pinned | **v1.5.7** |
| Upstream license | BSD-3-Clause (chosen from the dual BSD-3/GPLv2; `vendor/LICENSE`) |
| Package license | MIT OR Apache-2.0 (everything outside `vendor/`) |
| Platform | Windows x64 (no platform-specific XIOM code) |
| Compiler pin | v0.64.1 |

## 2. Vendored path (G2 pin)

The official **single-file amalgamation** is vendored into `vendor/` and
compiled into the test binary via `--c-source` (no system library, no runtime
DLL). Generated from the pinned release with the upstream tool:

```
python combine.py -r ../../lib -x legacy/zstd_legacy.h -o zstd.c zstd-in.c
```

run from `build/single_file_libs/` of `zstd-1.5.7`.

| File | Bytes | SHA256 |
|------|-------|--------|
| `vendor/zstd.c` (generated) | 2,227,176 | `EFD2063214B7EB797919386A39833AD0954B08182F89EB01D5F4150415A815EE` |
| `vendor/zstd.h` (from `lib/`) | 181,748 | `9B4BC8245565C98CCFC61C07749928B57E7C0F6FDDB0530C4F6AA1971893D88B` |
| `vendor/LICENSE` (BSD-3-Clause) | 1,549 | `7055266497633C9025B777C78EB7235AF13922117480ED5C674677ADC381C9D8` |

### Source archive provenance

| Artifact | Value |
|----------|-------|
| Download | https://github.com/facebook/zstd/releases/download/v1.5.7/zstd-1.5.7.tar.gz |
| SHA256 (verified against the published `.sha256` asset) | `eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3` |

### Build shim

`src/zstd_all.c` (our code) sets `#define STATIC_BMI2 0` and includes the
vendored `zstd.c`: the xiom link line compiles C sources with baseline
x86-64 features, and zstd's `bits.h` would otherwise take the BMI2
intrinsics path (`_bzhi_u64`) without a `-mbmi2` target. The vendored file is
unmodified; properly `target("bmi2")`-attributed paths in the decompressor
remain available.

### Re-pin procedure

1. Download the new official release; verify its published SHA256.
2. Regenerate the amalgamation with the upstream `combine.py` command above.
3. Replace `vendor/zstd.c`, `vendor/zstd.h`, `vendor/LICENSE`; recompute the
   table; update version rows in `README.md`/`AUDIT.md` in the same commit.
4. Re-run `scripts/port.ps1 -Package xiom.zstd` (x2) and record the matrix.

## 3. Design and safe boundary (G5)

| Module | File | Role |
|--------|------|------|
| `xiom.zstd` | `zstd.xi` | The only module with `extern "C"`: raw declarations + safe wrappers (version, bound, compress, decompress, frame size, error detection/naming) |
| shim | `src/zstd_all.c` | Compiles the vendored amalgamation with the intrinsics pin |

API returns owned `Vec[UInt8]` results and `Result[_, Str]` errors carrying
`ZSTD_getErrorName` text; inputs are `&mut Vec[UInt8]` (the confined module
needs `as_mut_ptr`). Error sentinels `ZSTD_CONTENTSIZE_UNKNOWN/-ERROR` are
exposed for `zstd_frame_content_size`.

Call convention note: for a resource-owning API on this pin, `&mut` input
buffers mirror the proven `as_mut_ptr` idiom (see the sqlite/glfw/sdl3
packages). Streaming contexts with reusable buffers are Phase 2.

## 4. Test matrix (recorded 2026-10-08, compiler v0.64.1)

| Configuration | Command | Result |
|---------------|---------|--------|
| Vendored amalgamation | `scripts/port.ps1 -Package xiom.zstd` | **PASS 8/8 x2** -- version 1.5.7, `compressBound` sanity, 8192 -> 34 bytes at level 3, frame content size 8192, round-trip identity, auto-size decompress identity, incompressible 2048-byte round-trip identity, invalid frame rejected |

No SKIP path exists (the library is compiled in). `port.args.json` passes the
shim; the packages runner resolves `${PACKAGE_DIR}` and the 240 s watchdog
covers the amalgamation compile (~40-60 s).

## 5. Scope

One-shot compress/decompress, frame-size queries and error reporting. The
pre-pilot module was a null-pointer stub ("blocked on compiler *UInt8
dereference support" -- since disproven) and is preserved in git history.
Streaming (`ZSTD_CCtx`/`ZSTD_DCtx`), dictionaries, checksum control, long
mode and multi-frame handling are Phase 2 (`ROADMAP.md`).
