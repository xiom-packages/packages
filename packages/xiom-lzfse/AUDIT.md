# AUDIT: xiom.lzfse

## Status (2026-10-08)

Real vendored implementation at 0.2.0. The pre-pilot files (root `lzfse.xi`
placeholder + `src/lzfse_safe.xi` + demo) were wrappers over undeclared or
system-link assumptions; they are preserved in git history only as reference.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.1 |
| Upstream | tag `lzfse-1.0` (archive SHA256 verified; per-file hashes in SPEC §2) |
| Link model | `--c-source` x7 (upstream library source list) |
| FFI confinement | all `extern "C"` in the root module `lzfse.xi` (G5) |
| Suite | `tests/test_conformance.xi` |
| Runs | **PASS 7/7 x2** via `scripts/port.ps1` (4096 -> 182 bytes; identical round-trips incl. 64 KB and incompressible; invalid stream rejected) |

## Design notes

- The seven sources match upstream's `add_library` list; `lzfse_main.c` (CLI)
  is excluded.
- Scratch buffers are allocated per call (encode scratch is 684,384 bytes on
  this build) -- correctness over allocation efficiency; scratch reuse is a
  Phase 2 roadmap item.
- `lzfse_decode` returns 0 for both invalid streams and too-small capacity;
  the error message says both possibilities (the API cannot distinguish).
- Wrapper names use `_required` to avoid shadowing the externs
  (`lzfse_encode_scratch_size`), which would self-recurse.
- `.gitattributes` (`vendor/** -text`) pins the vendored bytes against
  autocrlf (same convention as `xiom.sqlite` / `xiom.zstd`).

## Known limitations

- No streaming/chunked decode and no way to size the output without knowing
  the original length (LZFSE frames do not record it in the API).
- No LZVN-only or raw-LZVN entry points exposed (the base decoders are
  compiled in via the standard sources).
- One-shot API only; no scratch reuse across calls yet.
