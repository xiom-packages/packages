# ROADMAP -- xiom.spirv-cross

## Now (0.1.0, incubating)

- [x] 169/169 `spvc_*` functions bound: symbol table + `dl_sym` resolver +
      typed wrapper per function (10 header families).
- [x] Every enum member (242) + macro (19) exported as constants; struct
      sizeof constants (17); `spvc_make_msl_version` macro math.
- [x] Runtime `resolved=169/169` proof + export-table diff
      (`tools/check_exports.py`, missing=0).
- [x] Functional probe: embedded SPIR-V fragment -> GLSL cross-compile
      ("void main"), resource reflection (3), entry points, full free chain.
- [x] SKIP-green when `spirv-cross-c-shared.dll` is absent; x2 suite green.

## Next

- [ ] Typed enum wrappers: emit `pub enum`-style helpers for the largest
      enums (resource type, basetype, compiler options) so callers can
      pattern-match instead of comparing `Int`.
- [ ] Error-callback functional test once the compiler's XIOM-function-value
      callback marshalling lands (B-13 family), then drop the dispatcher
      constraint note from AUDIT.
- [ ] MSL backend smoke: compile the fixture to MSL and assert `#include
      <metal_stdlib>` appears (needs an MSL-shaped second fixture or an
      option probe).
- [ ] Reflection struct decode helpers: owned-slot readers for
      `spvc_reflected_resource`/`spvc_buffer_range` lists (C-copy into owned
      slots) so callers get name/type ids without foreign reads.
- [ ] Linux `.so` soname variant + 32-bit layout pass.
- [ ] Promote `tools/gen/*.xifrag` families to real modules when the
      compiler's multi-module resolution is fixed (see AUDIT.md).

## Blocked / watched

- Compiler v0.64.3 slot cross-module import regression (blocks multi-module
  packaging; tracked in AUDIT.md).
