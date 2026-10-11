# AUDIT: xiom.shaderc 0.1.0

Package review for the Vulkan-SDK-100 binding lane (slice A3). Scope: the
public C API of `shaderc.h` (45 entry points) over a generated dynamic
loader. Nothing is vendored; no link-time dependency.

## 1. Coverage audit

| Claim | Evidence |
|-------|----------|
| Oracle = 45 functions | generator parse of the pinned headers; `SHADERC_SYMBOL_COUNT` |
| DLL exports exactly the 45 oracle names | `llvm-readobj --coff-exports shaderc_shared.dll` -> 45 `shaderc_*`, name set == oracle set |
| Bound = 45 typed wrappers | `shaderc.xi` (one per declaration) |
| Constants = 191 | `SHADERC_CONSTANT_COUNT`; every enumerator of 11 enums incl. aliases and expression-valued entries |
| Runtime resolved = 45/45 | suite line `resolve: resolved=45/45` (per-name `dl.dl_sym` loop over the symbol table) |
| Functional probes | 17 suite checks, every wrapper exercised; log lines carry statuses/lengths/magic bytes |

Header-declared but not exported by the shipped DLL: **none**. Exported but
not header-declared: **none** (checked 2026-10-11, SDK 1.4.350.0).

## 2. Confined-call boundary (the one non-obvious design point)

`shaderc_shared.dll` is a large C++ library (glslang + SPIRV-Tools inside).
On compiler v0.64.3 the confined-block fault machinery
(`xiom_trampoline_call` / guard arena / guard page) is not safe around
foreign C++ calls that raise and handle exceptions internally: builds whose
wrapper blocks were trampolined crashed nondeterministically
(STATUS_HEAP_CORRUPTION 0xC0000374, and 0xC0000005 in another build) BEFORE
the first line of suite output -- the same binary passing 10/10 in one build
and 0/10 in the next, layout-dependent.  The package therefore annotates the
generated wrappers `#[unsafe_direct]` (the compiler's documented trusted
escape hatch -- "no trampoline, no arena, no guard page") and passes
`--enable-unsafe-direct` via `port.args.json`.  With direct blocks the
binary is deterministic: 10/10 same-binary runs, `port.ps1` x2 PASS 17/17.
This is a deliberate, audited trust decision for one binding module
(50 blocks, under the compiler's 64-block cap); a compiler-side fix for
foreign-exception interception is the long-term resolution.

## 3. `Vec.with_len` finding (root cause of the pre-fix flakiness)

While diagnosing the crashes above, ASAN narrowed a second, independent
defect: `Vec[UInt8].with_len(n)` is a heap-buffer-overflow on v0.64.3.  The
stdlib contract says with_len zero-fills `n` elements with 8 bytes per slot
(`n * 8` bytes), but `Vec.reserve`'s growth loop under-allocates for the
sized-buffer path; ASAN report (minimal pure-XIOM repro, no DLL):

```
WRITE of size 128 at 0x... past a 16-byte region allocated by Vec.with_len_UInt8
SUMMARY: AddressSanitizer: heap-buffer-overflow in __unsafe_block_5
```

(`Vec[UInt8].with_len(16)` -> 128-byte zero-fill into a 16-byte allocation.)
Any slot built with with_len (4-byte slots included: 32-byte zero-fill) can
corrupt the heap; that is the ASLR-dependent STATUS_HEAP_CORRUPTION class the
lane has seen around slot traffic.  Package-side fix: ALL sized buffers use
push loops (`shaderc_slot4`, `shaderc_result_copy_bytes`), never with_len --
matching the sdl3 template's proven slot idiom.  Compiler-lane follow-up:
fix `Vec.reserve` (or the with_len lowering) and re-test the repro; the
`xiom.ffi.dl` out-param recipe comment recommending with_len should be
updated until then.

## 4. Secrets / hygiene

- No secrets, no environment reads beyond the loader soname.
- `port.args.json` is pure JSON (`["--enable-unsafe-direct"]`), the
  sanctioned per-package hook.
- Suite cleans up: every result released, options released, compiler
  released, library handle closed; no files written; SKIP path allocates
  nothing.
- Worktree hygiene: generated modules are committed; the generator is
  deterministic; `tools/gen_shaderc.py` is the only writer.
