# xiom.brotli -- Roadmap

**Version**: v0.1.0 | **Compiler**: xiom v0.64.5 | **Last updated**: 2026-10-16

## Current state

| Criterion | Status |
|-----------|--------|
| Vendored upstream (G2 pinned) | Done -- google/brotli v1.2.0 = `028fb5a2`; 107-file tree, digest `C3D54D20...`; 24-line documented include rewrite |
| FFI core (single confined module) | Done -- 16/16 declared C functions wrapped |
| One-shot encode/decode | Done -- literal `BrotliEncoderCompress`/`BrotliDecoderDecompress` bound and wrapped |
| Streaming encode/decode | Done -- sessions with chunked push/collect; `TakeOutput` + `IsFinished` drain path |
| Quality/lgwin/mode parameters | Done -- `brotli_compress` args + `brotli_encoder_set_parameter` (all 10 `BROTLI_PARAM_*` constants) |
| Upstream golden vectors | Done -- 8 pairs from the pinned clone decode byte-identically |
| RFC 9110 HTTP helpers | Done -- `Content-Encoding: br` token helpers |
| Custom dictionaries | Phase 2 |
| Decoder parameters (ring buffer, large window) | Phase 2 |
| Large-Window Brotli (lgwin > 24) | Phase 2 |
| Decoder `TakeOutput` / `HasMoreOutput` / `IsUsed` | Phase 2 |
| Metadata blocks (encoder EMIT_METADATA + decoder callbacks) | Phase 2 |

## Phase 2 (next touches)

1. Dictionaries: bind `BrotliDecoderAttachDictionary`,
   `BrotliEncoderPrepareDictionary`, `BrotliEncoderAttachPreparedDictionary`,
   `BrotliEncoderDestroyPreparedDictionary`,
   `BrotliEncoderGetPreparedDictionarySize`,
   `BrotliSharedDictionaryType` constants; prove with a raw-prefix-dictionary
   round trip.
2. Decoder tuning: `BrotliDecoderSetParameter`
   (`BROTLI_DECODER_PARAM_DISABLE_RING_BUFFER_REALLOCATION`,
   `..._LARGE_WINDOW`) + Large-Window encode/decode pair (lgwin up to 30,
   encode-side already reachable via `brotli_encoder_set_parameter`).
3. Decoder pull interface: `BrotliDecoderTakeOutput`,
   `BrotliDecoderHasMoreOutput`, `BrotliDecoderIsUsed`,
   `BrotliDecoderIsFinished` (source-side output-drain parity with the
   encoder).
4. Metadata blocks: `BROTLI_OPERATION_EMIT_METADATA` round trip through a
   decoder-side metadata capture (requires the callback ABI lift).
5. Consumer check-ins: HTTP middleware (relay accepts `Content-Encoding:
   br` payloads), XVECTOR/ORBITDB store segments, PULSE artifact packing;
   keep the one-shot API stable for them.
6. Re-pin cadence: track upstream releases (brotli is slow-moving: 1.2.0 is
   the 2025 stable); re-carve per `SPEC.md` section 2.
