# xiom.opus -- AUDIT (0.1.0)

Audit of the first landing: what was generated, what was verified, how the
bindings-lane discipline maps to this package, and the compiler/behaviors
observed while building it.

## 1. Surface conformance

* Oracle: exported function declarations in the pinned public headers
  (`opus.h`, `opus_defines.h`, `opus_multistream.h`, `opus_custom.h`,
  `opus_projection.h`).
* `tools/gen_opus.py` fails the build if any declared function has no ABI
  mapping or if `src/opus_bridge.c` does not define exactly the generated
  `xo_*` entry points. Regeneration is deterministic (sorted output, LF,
  no timestamps).
* Result: 105 declared = 105 bound, 0 skips; 114 bridge entry points
  (105 + 9 extra `_get`/`_set` companion functions for the variadic ctl
  pairs) + 4 documented pointer-ctl companions; 86 constants exported;
  48 ctl request macros mapped.
* `opus_repacketizer.h` does not exist in v1.6.1 (merged into `opus.h` at
  upstream in 1.4); the repacketizer API is declared in `opus.h` and
  counted there. `opus_types.h` contains types only.
* Suite asserts the ledger (`abi.DECLARED_FUNCTIONS == BOUND_FUNCTIONS ==
  105`) so drift fails tests, not just docs.

## 2. Discipline mapping (bindings lane, v0.64.4)

| Rule | How this package complies |
|------|---------------------------|
| B-11/B-16/B-17 (out-params) | one owned 4-byte slot per scalar out-param, written LE by `put_i32` in C, read byte-indexed in `xiom.opus.ffi`; multi-out functions (packet_parse, surround create) use one slot per out-param |
| B-20/B-24 (no foreign-pointer reads) | XIOM never dereferences C-provided pointers; `opus_strerror`/`opus_get_version_string` copy into owned slots; DRED/decoder handles are C-side casts of `int64_t` |
| B-21 (no `&mut` of Result/struct temps) | buffers are bound to locals in the suite before `&mut`; compile patterns follow the vendored-C precedent |
| B-23 (no bare null to C) | none; the NULL-requiring path (PLC) is an EMPTY packet Vec (upstream `len == 0` PLC branch, verified in `opus_decoder.c`) |
| B-25 (no `x as *UInt8` handles) | handles are `Int` from C; init-over-own-memory returns the caller's `Vec` address as the handle and takes the buffer as a `*UInt8` param (no XIOM-side integer->pointer casts anywhere) |
| B-26 (no `Result[Option[T]]`) | outcomes are flat (`Result[Int, OpusError]`, `Result[PacketFrames, OpusError]`, `Result[EncoderOutcome, OpusError]`) |

Unsafe confinement (G5): `xiom.opus.ffi` is the only module containing
`unsafe` blocks; `xiom.opus` and `xiom.opus.types` are pure; extern
declarations are generated inline in the FFI module (documented reason:
on v0.64.4 the codegen resolves extern symbols from the calling module).
The extern block is marker-generated (`GENERATED-EXTERNS-BEGIN/END`) so
the surface cannot drift from `tools/gen_opus.py`.

## 3. Test evidence

26/26 green twice on v0.64.4 (see STATUS.json for the recorded run).
Highlights: s16 440 Hz tone at 48 kHz mono round-trips at **34.5 dB**
lag-aligned SNR with 68% energy retention (encoder look-ahead ~6.5 ms is
compensated by the suite's lag search); multistream stereo 34.4 dB;
custom mode 9.3 dB; ambisonics FOA 28.8 dB; 24-bit decode matches the s16
decode exactly after `>> 8` (0 mismatches) and `decode_float` energy
matches the s16 path at 100% after a state reset.

Test design notes (verified against a pure-C driver compiled from the same
vendored sources):

* `opus_encode` **fits** tiny `max_data_bytes` (down to 1 byte) instead of
  failing; the deterministic `OPUS_BUFFER_TOO_SMALL` case is
  `opus_repacketizer_out` into a too-small buffer (suite covers it).
* Decoding the same PCM twice through one encoder (24-bit carrier frame,
  then float frame) is a signal discontinuity that upstream itself
  reproduces at ~1 dB; the float-path round trip uses a fresh encoder.
* Variant decodes (s16/24/float) must start from identical decoder state
  (`OPUS_RESET_STATE`) to be comparable.

## 4. Compiler/toolchain findings observed (v0.64.4)

Recorded here because they shaped the package and may affect other lanes:

1. **`Str + Bool` (and nested calls inside concat chains) can crash**
   (0xC0000005) at runtime. The suite formats booleans through `b2s()` and
   binds intermediate values to locals before concatenation.
2. **Extern symbols resolve from the calling module**: externs declared in
   an imported module produced `unresolved function symbol(s)` at codegen
   (`--emit-ir` and link). The extern block is therefore generated inside
   `src/opus_ffi.xi`.
3. **Unity build hazards in vendored multi-file C**: conditional
   declarations in guarded headers depend on per-TU defines
   (`CELT_C`/`CELT_ENCODER_C`/`CELT_DECODER_C` must be set before the
   first header inclusion, and only in the unit that also defines
   `celt_fatal` -- defining them everywhere duplicates the symbol at
   link). Benign macro redefinitions (`QA`) remain warnings.
4. **No `-I`/`-D` per C source** in `--c-source`; vendored trees must be
   flat or self-relative (PROVENANCE section 2).
5. **No source-level float bitcast**: the suite builds exact f32 bit
   patterns arithmetically for PCM generation/verification.

## 5. Known deviations / risks

* Portable C build (no RTCD/SIMD); see SPEC "Build configuration".
* DRED/OSCE/Deep-PLC off: entry points bound, stubs exercised; a
  DRED-enabled re-pin needs model tarballs (out of git, out of scope).
* `PACKAGE_VERSION` is pinned literally to `1.6.1` (matches the CMake
  build of tag v1.6.1).
* Init-over-own-memory handles must not be destroyed and their backing Vec
  must outlive them (SPEC documents the contract; suite exercises the
  happy path and the capacity rejection).
* `.gitattributes` disables text conversion under `vendor/**`; any manual
  edit of vendored files breaks the MANIFEST hashes and the audit chain.
