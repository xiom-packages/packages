# xiom.stb -- ROADMAP

## Phase 1 (Done) -- historical
- [x] 0.1.0 declaration-only bindings (allowlist-excluded; preserved in git history)

## Phase 2 (Done) -- 0.2.0 vendored codecs
- [x] Vendored stb_image + stb_image_write (pinned commit + per-header SHA256)
- [x] One TU with both implementations + probe bridge; scalar getters (B-11-safe)
- [x] Real in-memory PNG encode/decode round trip + BMP decode; 5/5 x2
- [x] Allowlist append requested

## Phase 3 (Planned)
- [ ] Typed `Image` decode/encode wrappers over `stb` (bytes + file paths)
- [ ] Error-string surface (`stbi_failure_reason`)
- [ ] PNG/JPG/BMP/TGA write variants (quality/flip parameters)
- [ ] GIF + animated-format notes (stb has no animation API; document the gap)
- [ ] HDR (`.hdr`/`stbi_loadf`) support
- [ ] Composition examples with `xiom.image` conversions
- [ ] Re-pin when the drift guard flags a new stb commit
