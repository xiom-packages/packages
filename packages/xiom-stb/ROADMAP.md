# xiom.stb -- ROADMAP

## Phase 1 (Done) -- historical
- [x] 0.1.0 declaration-only bindings (allowlist-excluded; preserved in git history)

## Phase 2 (Done) -- 0.2.0 vendored codecs
- [x] Vendored stb_image + stb_image_write (pinned commit + per-header SHA256)
- [x] One TU with both implementations + probe bridge; scalar getters (B-11-safe)
- [x] Real in-memory PNG encode/decode round trip + BMP decode; 5/5 x2
- [x] Allowlist append requested

## Phase 3 (Done) -- 0.3.0 HDR class surface
- [x] 100% of stb_image's `.hdr`-related public entries bound (12 entries:
      stbi_is_hdr family, stbi_loadf family, hdr_to_ldr/ldr_to_hdr knobs)
- [x] 8-bit remap witness `stbi_load_from_memory` (`stb_load_rgba8_from_memory`)
- [x] Owned-buffer interop (bridge copy-out; B-11/B-20/B-24/B-25/B-26 discipline)
- [x] Typed errors (`StbError{code,message}` + `stb_failure_reason`)
- [x] In-test `.hdr` fixture round trip (exact values) + 3 corrupt typed-error paths
- [x] 18/18 x2 on v0.64.4; `modules:` declared (fleet retro)

## Phase 4 (Planned)
- [ ] General LDR loaders (`stbi_load` family) + `stbi_info` metadata
- [ ] Encoders (`stbi_write_png/jpg/bmp/tga/hdr` + flip/quality parameters)
- [ ] User-callback dispatch for `stbi_io_callbacks` when B-13/B-22 are fixed
- [ ] Typed `Image` composition examples with `xiom.image` conversions
- [ ] Re-pin when the drift guard flags a new stb commit
