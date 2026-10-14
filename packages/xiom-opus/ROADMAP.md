# xiom.opus -- ROADMAP

## 0.1.0 (landed)

* Vendored libopus v1.6.1 (float build, CUSTOM_MODES, hardening; portable
  C, no RTCD).
* 105/105 public functions bound via the `xo_*` bridge; generated surface
  + coverage ledger; 26-check conformance suite green twice on v0.64.4.

## 0.2.x candidates (consumer-pulled only)

1. **Streaming decode helper**: Ogg-encapsulated Opus (`xiom.ogg` 0.2.0
   packet layer) -> `OpusHead`/`OpusTags` parse -> per-packet
   `decode_float` into vectors, honoring pre-skip/gain; granulepos ->
   sample mapping for seeking. This is the `opusfile` subset the engine
   needs; keep it in `xiom.ogg`/consumer code unless repeated use appears.
2. **RFC 8251 test vectors**: import `opus_testvectors` at port time
   (out-of-git) for bit-exact parity jobs; wire as an optional suite.
3. **RTCD/SIMD build config**: per-file compile flags do not exist in the
   `--c-source` pipeline today; if profile data demands it, propose a
   toolchain `--c-flag` extension (per-TU flags) rather than patching
   vendored sources.
4. **DRED/OSCE/Deep-PLC**: enable + model provisioning (`media.xiph.org`
   tarballs) when a loss-recovery consumer appears; the entry points are
   already bound and stub-tested.
5. **Projection stereo layouts**: family-3 requires order >= 1 (4+
   channels); add 2-channel "nondiegetic" tests (channels=6/11) if a
   spatial-audio consumer needs the full matrix set.
6. **Encoder ctl companions**: `OPUS_SET_DNN_BLOB` currently errors in the
   default build (no weights support); revisit with item 4.
7. **`opus_encoder_init` over caller memory**: current shape requires the
   XIOM-owned Vec to outlive the handle; a small RAII wrapper type in the
   facade could encode the lifetime rule at the type level.
