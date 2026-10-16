# AUDIT: xiom.brotli

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

## Status (2026-10-16)

Real vendored implementation at 0.1.0: the upstream google/brotli v1.2.0 C
codec (MIT) compiled into the test binary via `--c-source`, with the
declared 16-function decoder/encoder surface wrapped and a 26-check
conformance suite (x2 green on the pin, recorded in `STATUS.json`).

| Item | State |
|------|-------|
| Compiler | xiom v0.64.5 |
| Upstream | google/brotli v1.2.0 = `028fb5a2` (2025-10-27); 107-file vendor tree, tree digest `C3D54D20...`; delta vs upstream = the 24-line include rewrite, verified against raw `git archive` blobs |
| Link model | `port.args.json`: `src/brotli_bridge.c` + 35 vendored units, one clang invocation, `--opt-level 0`, `--timeout 1800` |
| FFI confinement | all `extern "C"` in `brotli.xi` (single module, G5); 16/16 declared C functions wrapped |
| Surfaces | one-shot + streaming decode/encode, parameter control, TakeOutput/IsFinished, upstream error codes/strings, HTTP content-coding helpers |
| Suite | `tests/test_conformance.xi` (26 checks) |
| Runs | **PASS 26/26 x2** via `scripts/port.ps1 -TimeoutSec 2400` (feat commit recorded in `STATUS.json`) |

## G2 pin

- Vendor tree digest `C3D54D20A17A3AF26BE29CC4E8EF15AC5CA72C1614173788CBBEE8852E23C642`
  (sorted `relpath:sha256` lines, LF; per-file table via
  `tools/gen_brotli.py --print-tree`).
- Public headers: `port.h` + `types.h` byte-identical to upstream;
  `decode.h`/`encode.h`/`shared_dictionary.h` differ only by the rewrite
  (vendored + raw-blob SHA256 pairs in `SPEC.md` section 2).
- `LICENSE` byte-identical (`3D180008...`). Full re-pin procedure:
  `SPEC.md` section 2; upstream-first record: `PROVENANCE.md`.

## Design notes

- The bridge exists for exactly five expressibility gaps: NULL-allocator
  creation, pointer-to-pointer stream cursors, size_t in/out, foreign
  pointers (`TakeOutput` bytes, `ErrorString` text) and sign-correct
  `GetErrorCode`. Every bridge body is a direct call into upstream.
- Slot discipline: consumed/written/size out-params land in dedicated
  owned 8-byte `Vec[UInt8]` slots, read byte-indexed little-endian (B-11/
  B-16/B-17 family); no pointer crosses back into XIOM.
- `--opt-level 0` is a port-time link-speed choice for the 35 upstream
  units; it does not change codec behavior (the suite exercises real encode/
  decode paths, and streaming output is byte-equal to the one-shot API at
  the same parameters -- asserted in the suite).
- Upstream v1.2.0 stores out-of-range quality/lgwin/mode values without
  complaint (`-- TODO(eustas): Validate/clamp parameters`), so the wrapper
  enforces the pinned headers' documented ranges; a suite check pins the
  typed errors.
- Corrupt-header behavior pinned by the suite:
  `_ERROR_FORMAT_EXUBERANT_NIBBLE` for a first-byte bit flip of a valid
  stream (typed, never a crash); mid-payload corruption surfaces as a typed
  `corrupt`/`truncated` error.
- The HTTP helpers are deliberately minimal (RFC 9110 token equality only,
  case-insensitive); no header parsing is attempted.

## Known limitations

- Declared-surface subset by design (see `SPEC.md` section 7): no custom
  dictionaries, no decoder parameters, no metadata callbacks, no
  Large-Window (>24 lgwin) streams, no `BrotliDecoderTakeOutput`/
  `HasMoreOutput`/`IsUsed`. All are explicit phase-2 items in `ROADMAP.md`.
- `brotli_decompress_oneshot` inherits upstream's one-shot limitation: a
  single typed error for corrupt input or insufficient capacity (the
  detailed-code path is `brotli_decompress_auto`).
- Trailing bytes after a complete stream are ignored (upstream stream
  semantics: no concatenated-stream framing).
- The port-time link compiles 35 upstream units; use `-TimeoutSec 2400` at
  the runner (SPEC test matrix).
