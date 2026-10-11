# ROADMAP: xiom.glslang

Current: 0.1.0 -- 100% of the shipped glslang C surface (61/61 C entry
points resolved; 290 generated constants; GLSL->SPIR-V compile proof
through the C interface).

## Next

1. **ShCompile end-to-end probe** (legacy path): drive `ShCompile` with a
   `TBuiltInResource` built from `glslang_decode_resource_limits` and one
   source string, then `ShGetInfoLog`/`ShDestruct`.  The wrappers and the
   string-array slot shape exist; the suite needs a deterministic
   expectation for the legacy compile (research the EShMsg inputs).
2. **Full resource-field decode check**: extend the decode probe from
   MaxLights/MaxClipPlanes to a sweep over several fields at their pinned
   offsets (documents the 420-byte layout for consumers).
3. **Include-callback trampoline** (`glsl_include_callbacks_t`): drive
   `#include` through C callbacks back into XIOM.  Blocked-by-lane: C
   callbacks into XIOM require the fixed-dispatcher pattern (finding B-13)
   and the callback ABI work; revisit when the engine needs multi-file
   shaders.
4. **SPIR-V disassembly in the suite**: pipe generated SPIR-V through
   `xiom.spirv-tools` (separate package) to assert opcode names -- only if
   that package lands in the same lane.
5. **Re-pin workflow**: on the next SDK bump, follow `SPEC.md` §2 (hash
   refresh + regenerate + `-Action verify`).
