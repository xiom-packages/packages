# ROADMAP: xiom.shaderc

## Shipped (0.1.0, 2026-10-11)

- [x] Oracle inventory: `tools/gen_shaderc.py` parses the pinned headers
      (45 functions / 191 constants) and emits symbol table + constants +
      typed wrappers; export matrix verified against the shipped DLL.
- [x] Dynamic loader with SKIP-when-absent + ABI-mismatch failure.
- [x] Suite: `resolved=45/45`, functional probes (compile/magic/error/asm
      round trip/preprocess/options/macro/clone/forced profile/version/
      profile parse), x2 green via `port.ps1`, SKIP path green.
- [x] PROVENANCE.md + `E:\repos\shaderc` clone at the pinned tag;
      docs/COVERAGE.md with the oracle vs bound vs resolved counts.

## Next

1. Include callbacks (`shaderc_include_resolve_fn` /
   `shaderc_include_result_release_fn`) end-to-end: a small C bridge module
   (vendored in-package, `port.args.json --c-source`) that exposes the two
   callbacks so `#include` resolution can be driven from XIOM (the setters
   are already bound; the suite exercises them with null callbacks today).
2. SPIR-V binary distribution helpers for the engine path (feed
   `shaderc_result_copy_bytes` output into `xiom.vulkan` shader modules /
   `xiom.spirv-tools` validation) as an example, once the consumer asks.
3. Watch upstream: re-pin on the next shaderc tag or when the drift guard
   flags the header hashes (re-pin = regenerate + re-run matrix).
