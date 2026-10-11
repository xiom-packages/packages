# AUDIT: xiom.spirv-tools

## Status (2026-10-11 UTC)

Generated dynamic-loader binding at **0.1.0** (SDK-100 slice A1). The oracle
is the `extern "C"` `spv*` surface of `libspirv.h`: 67 declared functions;
the shipped DLL exports 55; 12 are a documented shipping gap (name-level
resolve proof in the suite). All 67 are bound; the suite resolves every
exported name at runtime and runs functional probes for assembly,
validation, disassembly, diagnostics, and the option-object families.

| Item | State |
|------|-------|
| Compiler | v0.64.3 |
| Upstream pin | Vulkan SDK 1.4.350.0; header sha256 `F4B0A230...ACAC`; DLL sha256 `06C7CAE2...41DB` |
| Link model | none at build time; runtime `LoadLibraryA`/`GetProcAddress` via `xiom.ffi.dl` |
| FFI confinement | one `unsafe` block per generated wrapper (family modules), `src/st_readout.xi` copy-out helpers, resolver via `xiom.ffi.dl` |
| Generator | `tools/gen_spirv_tools.py` (committed; `--check` drift mode clean; deterministic output) |
| Suite (present) | `tests/test_conformance.xi`, 39 checks -- PASS 39/39 x2 (SDK DLL on PATH) |
| Suite (absent) | PASS 3/3 x2 (SDK `Bin` filtered out of PATH -- SKIP-green) |
| Runtime resolve proof | `resolved=55/67` (name-driven `dl_sym` over the oracle table); 55/55 exported resolve; 12/12 gap names absent; typed resolver agrees (`st_resolved_count` = 55) |
| Constants | 222 generated values (11 enums + `kDefaultMaxIdBound`), sampled by the suite |

## Discipline compliance (B-11..B-20)

- **B-11 / B-16 / B-17 (slot writes, pointer arithmetic)**: every out-param
  gets its own owned zeroed `Vec[UInt8]` slot; all slot writes are
  byte-indexed (`st_slot_write_u64`); no `as_mut_ptr() + N` anywhere; no
  `ffi.ptr_write_*`. `spv_const_binary_t` is built byte-wise in an owned
  16-byte slot and C reads that owned memory (C-reads-our-memory direction).
- **B-20 (foreign-pointer reads)**: C-owned structs are copied out through
  `xst_copy` (C bridge) into owned slots and read byte-wise; `xst_strlen`
  measures foreign C strings from C. XIOM never dereferences a foreign
  pointer. The copy directions are: C writes into our owned slot
  (out-params), C copies foreign -> owned (struct/string copy-out), C reads
  our owned struct (`spv_const_binary_t` in-param).
- **B-19 (arg width)**: return widths are declared to match the C ABI
  (`UInt8` for `bool`, `Int32` for enums, `Int` for pointer returns --
  `spv_diagnostic`/`spv_context` etc. are pointer typedefs, not 32-bit ints;
  the generator maps all non-scalar returns to a 64-bit handle).
- **B-10 (name-keyed guard rewrite)**: all cast-call locals use the `f_`
  prefix (`f_call`); no local is named `alloc`/`free`/`malloc`.
- **B-05 (alloc/free in confined blocks)**: no `ffi.alloc`/`ffi.free`
  anywhere in the package; all buffers are XIOM-owned Vecs.
- **One owned slot per out-param**: `spvTextToBinary` gets separate
  binary/diagnostic slots; the validate path uses a fresh diagnostic slot per
  call; no slot is shared across calls.

## Findings discovered while building this package (candidates for the lane ledger)

1. **Int -> pointer cast does not survive a function return** (v0.64.3):
   `fn f(a: Int) -> *UInt8 { unsafe { return a as *UInt8; } }` returns a
   pointer that the C side rejects (`spvValidateBinary` -> -4
   SPV_ERROR_INVALID_BINARY), while the same cast performed inline on the
   call expression inside one confined block passes the real address. Same
   int-to-ptr sanitization family as B-20, but this is the *outbound*
   direction (XIOM -> C), previously unrecorded. The generator therefore
   keeps raw addresses as `Int` in the public wrapper signature and casts on
   the call expression. Minimal shape (run against the SDK DLL):

   ```xiom
   // helper shape: BROKEN (-4 = SPV_ERROR_INVALID_BINARY)
   fn addr_to_ptr(addr: Int) -> *UInt8 requires: addr != 0 {
     unsafe { return addr as *UInt8; }
   }
   let rc_helper = f_vbin(ctx, addr_to_ptr(code), wc, diag);
   // inline shape in the same confined block: CORRECT (0 = SPV_SUCCESS)
   let rc_inline = f_vbin(ctx, code as *UInt8, wc, diag);
   ```
   Observed: `vbin_inline=0` vs `vbin_helper=4294967292`, same process,
   same address.
2. **`Vec[Str]` element read from a temporary, concatenated with `+`**:
   `acc = acc + f()[i]` prints the raw element pointer as an integer string,
   while `let v = f(); let x = v[i]; acc = acc + x;` prints the string.
   Element reads passed directly as function arguments (e.g. `dl.dl_sym(h,
   names[i])`) are correct -- the defect is specific to the temporary +
   concat shape. Worked around in the suite with bound locals; noted here
   for the compiler lane.

## Evidence pointers

- Suite output: `docs/COVERAGE.md` §4 (both PATH configurations, x2).
- Export dump: `tools/dll_exports_SPIRV-Tools-shared.txt` (55 names).
- Oracle inventory: `tools/oracle_inventory.txt` (67 declared + per-family
  class + exported/not-exported).
- Drift check: `python tools/gen_spirv_tools.py --check` -> exit 0.
