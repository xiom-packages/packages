# PROVENANCE: xiom.shaderc

## Upstream

| Field | Value |
|-------|-------|
| Project | shaderc (Google) -- https://github.com/google/shaderc |
| Pinned ref | tag `v2026.4`; commit `b64fd42c4a2a9d501c47aca5d3571f7673a5e9cc` |
| Clone | `E:\repos\shaderc` (shallow, `--branch v2026.4 --depth 1`), cloned 2026-10-11 |
| License | Apache-2.0 (nothing vendored; no code copied) |
| Oracle | the pinned headers `libshaderc/include/shaderc/{shaderc,env,status,visibility}.h` (500-line C API + enums) |

Version identification: the Vulkan SDK 1.4.350.0 copies of those four
headers are **git-blob-identical** to the v2026.4 tag (`git hash-object` on
the SDK files == `git rev-parse v2026.4:...` for all four), and the shipped
`shaderc_shared.dll` exports exactly the 45 names those headers declare.

## Derived vs independent

- **Independent implementation**: everything in this package. The generator
  parses the C declarations (a mechanical oracle read) and emits XIOM code;
  no shaderc source is copied. The wrapper signatures, the loader, the
  owned-slot decode helpers and the suite are ours.
- **Derived facts** (recorded as pins, not code): function names/parameter
  lists, enum values (evaluated with C enum semantics incl. aliases and
  `(1u << 22) | ...` initializers), and the export matrix.
- **Test vectors**: none imported from upstream; the functional probes are
  our own (trivial GLSL that uses `gl_Position`, SPIR-V magic check, error
  message non-emptiness, assembly round trip via the DLL's own assembler).

## Re-carve procedure

1. `git -C E:\repos\shaderc fetch --depth 1 origin tag <new-tag>` and check
   out the commit; re-run `python tools/gen_shaderc.py` (the generator
   defaults to the SDK header dir; pass a header dir as argv[1] to parse a
   clone).  Compare the emitted oracle counts and update SPEC.md pins.
2. Verify the SDK/upstream blob equality again and re-hash
   `shaderc_shared.dll`.
3. Re-run the suite matrix (present + absent) and re-record STATUS.json.

## Cleanup ledger row (for the shared `E:\repos\CLEANUP.md`)

`| shaderc | https://github.com/google/shaderc (Apache-2.0) | 2026-10-11 | bindings (xiom.shaderc) | 2026-12-01 | active |`
