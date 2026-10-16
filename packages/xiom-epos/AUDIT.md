# xiom.epos -- audit (0.1.0)

Scope: FFI discipline (v0.64.4/v0.64.5 B-series findings + BINDINGS-LANE
gates), safety containment, and the lane's verification battery.

## Discipline checklist

| Gate | Rule | Status |
|---|---|---|
| B-10/B-25 | library handles and all C pointers cross as `Int`; pointer -> Int conversions only (`vp as Int`); **no `Int as *UInt8`** anywhere | PASS -- grep-audit: the only `as fn(` casts are fn-pointer calls; `as *UInt8` appears only in `0 as *UInt8`-free code (none) and fn signatures |
| B-12 | no `f32` **returns** | PASS -- the declared EPOS surface has no float returns; the only `float` in play is the `Scaling` in-arg (`as Float32`) |
| B-17/B-24 | out-params in XIOM-owned `Vec[UInt8]` slots, byte-indexed; slots push-loop built (never `Vec.with_len`); no foreign reads, no pointer arithmetic | PASS -- `epos_slot` push-loop; every read via `epos_rd_*` with `buf.len()` contracts; `epos_str_from_slot`/`epos_slot_copy` are the only consumers of `as_ptr()` |
| B-20/B-21 | Str equality only through `string.str_compare`; no ad-hoc string ops | PASS -- wrappers compare nothing; the suite uses `compare.str_compare` / `string.str_starts_with` |
| B-23 | no callbacks to route (nothing to keep alive) | N/A -- declared surface has no callbacks |
| B-26 | flat outcome structs; no `Result[Option[T]]` nesting | PASS -- `EposRc`/`EposValueOut`/... all flat `{ok, rc, error_code, ...}` |
| G5 | `unsafe` confined to the package's own module tree; typed wrappers; consumers stay safe | PASS -- `unsafe {}` appears only in the six `src/` modules (same shape as `xiom.android`/`xiom.gles`); the suite writes no `unsafe` |

Hardening notes:

* Every wrapper carries `requires` contracts (handle non-zero, buffer
  lengths, argument ranges); `lib.h != 0` on all.
* The loader fails **closed**: any missing declared entry closes the handle
  and returns `Err(EPOS_LOAD_ABI)` with the missing symbol name; the two
  Linux-layer helpers resolve opportunistically and their wrappers return
  the typed `EPOS_NOT_AVAILABLE` sentinel when absent (no null call-through,
  no silent failure).
* No `console.log`/debug prints in the modules; the suite prints only its
  report lines.

## Verification battery (2026-10-16, v0.64.5)

1. `--emit-ir` on each of the 6 modules -> exit 0.
2. `scripts/namespace-check.ps1` -> `xiom.epos OK (6 module(s))`, 0 conflicts.
3. `scripts/port.ps1 -Package xiom.epos -TimeoutSec 300` (SKIP path) x2 ->
   29/29 PASS x2 (`all tests passed (SKIP path -- no runtime)`).
4. Same with the public `EposCmd64.dll` sample on `PATH` x2 -> 29/29 PASS x2
   (`present path exercised`): 177/177 table, 177/177 `GetProcAddress` sweep,
   live `VCS_GetDriverInfo` / `VCS_GetErrorInfo`, typed helper
   `NOT_AVAILABLE`, clean close.
5. Deterministic classification on every host: bogus sonames x2 -> ABSENT;
   `kernel32.dll` / `ntdll.dll` x2 -> ABI (fail-closed on missing symbols).
6. Dead-code-free compile coverage: the suite's coverage function calls all
   179 wrappers; it is lowered into `a.exe` on every run (never executed).

## Findings recorded by this lane (compiler-side; not fixed here)

1. **`src/` root-resolution quirk**: with a `src/` directory present, the
   project-graph source roots become `[<pkg>/src]` only -- a root module file
   at the package root is never indexed for `tests/` compiles, yielding
   "unresolved import" for the package's own module.  Worked around by
   keeping all module files under `src/` (SPEC sec. 5).  Same shape observed
   on `xiom.android` in this worktree today (root `android.xi` unresolved,
   src modules failing on its types).
2. **UTF-8 BOM blinding**: `read_module_header` rejects a BOM as an
   unexpected token, so BOM-prefixed `.xi` files are invisible to the module
   index (and to the persistent `~/.xiom/catidx.txt` cache) -> "unresolved
   import".  PowerShell 5.1 `Set-Content -Encoding UTF8` writes BOMs; package
   tooling must not.
3. **Shared-stdlib transients**: mid-wave stdlib edits cause compile runs to
   fail nondeterministically (observed: one zero-output exit `-1`, one
   collision flood from unrelated workspace copies).  Retries minutes later
   were clean; none of this is package-attributable.

## Present-path finding (closed DLL)

`VCS_GetDeviceNameSelection` poisons process teardown on the 6.6 sample
(`exit 0xC0000409` after `main`, 4/4 reproductions, independent of
`dl_close`; correct data returned; PowerShell host exited clean).  Recorded
in SPEC sec. 4 / PROVENANCE sec. 4; the suite therefore does not call it
live.  Not a wrapper defect: the call's data, ABI shape and slot handling
are verified; only the artifact's post-call teardown state is at issue.

## Residual risks

* The `long`-typed fields follow the **win-x64 LLP64** ABI (D1); a Linux
  `libEposCmd.so` consumer needs the LP64 variant -- do not reuse this
  wrapper set on LP64 without a second binding.
* Unverified against a real controller (no hardware on this host); all
  present-path evidence is against the library itself
  (`VCS_GetDriverInfo` etc., no device I/O).  Hardware bring-up is a
  ROADMAP item.
