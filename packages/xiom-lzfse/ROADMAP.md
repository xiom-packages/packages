# xiom.lzfse -- Roadmap

**Version**: v0.2.0 | **Compiler**: xiom v0.64.1 | **Last updated**: 2026-10-08

## Current state

| Criterion | Status |
|-----------|--------|
| Vendored sources (G2 pinned) | Done -- lzfse-1.0, per-file hashes |
| FFI core (single confined module) | Done |
| One-shot encode/decode | Done -- 7/7 x2, real ratios |
| Scratch sizes exposed | Done |
| Scratch reuse across calls | Phase 2 |
| Chunked/streaming decode without known size | Phase 2 |
| Size-prefixed container helper | Phase 2 |
| LZVN/raw entry points | Phase 2 |

## Phase 2 (next touches)

1. Scratch reuse: accept a caller-provided scratch buffer (or cache one per
   package user) so repeated encodes do not allocate 684 KB each.
2. Size-prefixed helper: `lzfse_pack(src)`/`lzfse_unpack(src)` writing a
   small header (magic + original size) so decode needs no external size --
   useful for PULSE/XVECTOR-style stored blobs.
3. Chunked decode loop if upstream exposes enough; otherwise document the
   size contract clearly and keep the container helper as the ergonomic path.
4. LZVN-only entry points (`lzvn_encode_buffer`/`lzvn_decode_buffer`) for the
   fast path -- the base sources are already compiled in.
5. Consider a shared compression facade note with `xiom.zstd` (same one-shot
   API shape) so consumers can swap codecs behind one wrapper.
