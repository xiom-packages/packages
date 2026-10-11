# ROADMAP: xiom.spirv-tools

## 0.1.0 (current) -- generated dynamic-loader binding, 100% of the declared C surface

- [x] Committed generator `tools/gen_spirv_tools.py` parsing the header's
      `extern "C"` `spv*` declarations (67 functions) + 11 enums; emits the
      symbol struct, resolver, name tables, family-split typed wrappers,
      constants; cross-checks the committed DLL export dump.
- [x] Hand-written loader entry (`spirv_tools_load` / `spirv_tools_close`)
      with ABSENT/ABI error split; SKIP-green when the DLL is absent.
- [x] Runtime resolve proof: `resolved=55/67`; every exported name resolves;
      12 documented shipping gaps proven absent.
- [x] Functional probes: context, assemble (+options), validate (+options /
      raw words), binary parse, disassemble + round trip, diagnostics
      (copy-out text), opcode string, validator/optimizer/reducer/fuzzer
      option objects; gated optimizer-run probe (SKIP at this pin).
- [x] Copy-out readout module + two-function C bridge (B-20 shape).
- [x] `docs/COVERAGE.md`, SPEC pin + re-pin procedure, AUDIT with discipline
      matrix, suite x2 in both PATH configurations.

## Next (candidates, in priority order)

1. **Pass/optimization surface when the SDK exports it**: re-run the
   generator after an SDK bump; if `spvOptimizer*` becomes exported, the
   gated optimizer-run probe in the suite activates automatically (no code
   change) -- add a `spvOptimizerRegisterSizePasses` variant probe then.
2. **Callback-based `spvBinaryParse`**: the wrapper passes callback
   addresses as `Int` (0 = none).  When the compiler's fn-param marshaling
   fixes (B-13 family) are in the pinned release, add owned-slot callback
   dispatchers and a parse-with-callbacks probe (instruction count > 0).
3. **`spvDiagnosticPrint` consumer routing**: currently prints to stderr;
   add an `spvOptimizerSetMessageConsumer`-style owned consumer dispatcher
   for the optimizer path once that surface is exported.
4. **Multi-platform soname**: parameterize `SPIRV_TOOLS_SONAME` (or add a
   `spirv_tools_load_named(soname)`) for `libSPIRV-Tools-shared.so` so the
   package SKIPs/starts on Linux runners.
5. **Consumer examples**: an `examples/` probe that assembles a shader
   from a file and validates it (the vulkan package's `src/tri_*.spv`
   fixtures are the natural input).
