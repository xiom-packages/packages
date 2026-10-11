# cb-abi -- C-callback ABI probe (GLFW 0.5.0 gate, v0.64.3)

Proves which XIOM paths can hand a callback to C before binding the GLFW
event-callback setters (xiom.glfw 0.5.0). C host: `cbhost.c` (int(*)(int)
immediate, stored, GLFW key shape, GLFW close shape, recorder + readback).
Probes: `probe.xi`, `probe2_relay.xi`, `probe3_fnparam.xi`,
`probe4_marshal.xi`, `probe5_recover.xi`, `probe6_registry.xi`.

## Run

```
. scripts\xiom.ps1
$tool = Resolve-XiomToolchain; $env:XIOM_STDLIB = $tool.Stdlib
& $tool.Xiom --run <abs>\probe.xi --c-source <abs>\cbhost.c
```
(run from the repo root; pass ABSOLUTE paths -- relative suite paths silently
fail package discovery, and `--c-source` links from a scratch cwd.)

## Results (2026-10-11, v0.64.3, RTX 3070 Ti host)

| Path | Probe | Result |
|------|-------|--------|
| control (pure C callee) | probe | `control=42` |
| top-level fn name `as Int` -> extern Int param | probe | `direct=42` |
| stored `as Int` address, invoked later | probe | `stored=20` |
| GLFW key shape (win + 4x Int32, Unit return) | probe | `calls=1 key=65 sc=33 action=1 mods=5` |
| GLFW close shape (win ptr fidelity 4242) | probe | `close_calls=1 close_win=4242` |
| top-level name -> extern `fn(...)` param | probe3 | `fnparam=42` |
| local fn value -> extern `fn(...)` param | probe4 | `local_to_fnparam=42` |
| **dynamic-loader cast-call with fn-typed param** | probe4 | **`cast_fnparam=42`** (the glfw loader pattern) |
| **fn-typed PARAM `as Int`** | probe2 | **`relay=0` (BROKEN)** |
| fn-typed PARAM -> extern fn-typed param | probe4 | `param_to_fnparam=0` (BROKEN) |
| fn-typed PARAM -> local -> extern fn-typed param | probe5 | `param_to_local=0` (BROKEN) |
| fn-typed PARAM -> local -> `as Int` | probe5 | `param_to_local_cast=0` (BROKEN) |
| fn-typed PARAM -> struct field -> extern | probe5 | `param_to_box=0` (BROKEN) |
| registry: push(param) -> dispatcher calls element | probe6 | `reg_double=42 reg_triple=63` |

## Re-verify on compiler main fde5548e (2026-10-11, m263-m265)

Ran the probes against the rebuilt toolchain (`cargo build --release` at
`E:\xiom-lang\xiom`, HEAD `fde5548e`) on the same host, vs the pinned
v0.64.3 slot:

| Probe | v0.64.3 | fde5548e | Verdict |
|-------|---------|----------|---------|
| probe2 | relay=0 | relay=42 | B-13 FIXED |
| probe4 | param_to_fnparam=0 | 42/42/42 | B-13 FIXED |
| probe5 | all 0 | 42/42/42 | B-13 FIXED |
| probe7 | 2x T001 (compile fail) | compiles; r=1 (element call true + early(0)) | B-14/B-15 FIXED |
| probe3 | fnparam=42 | NO OUTPUT after the call, exit 0 | **B-18 REGRESSION** |
| probe6 | reg_double=42 reg_triple=63 | NO OUTPUT, exit 0 | **B-18 REGRESSION** |
| probe8_name_fnparam (arm 1+2) | full output (42/42, callee r=7) | `before`..`main-after r=0` (calls return 0 early) | **B-18 REGRESSION** |

fp-return (1904/B-12), same builds, `glfw-fp-return` probes: `after_set99_ms`
0 -> **99000**, `advance_ms` 0 -> 311, `opacity_x1000` 262416000 -> **1000**
-- FIXED.

**B-18 (new, regression in fde5548e):** passing a BARE TOP-LEVEL fn NAME as
a fn-typed EXTERN parameter makes the enclosing function return 0 early --
silently, exit code 0 (no diagnostic).  The B-13 fixed shapes (fn-typed
param, local, cast-call) keep working; this was the ONE pre-fix-working
name shape (it was the control for B-13).  Repro:
`probe8_name_fnparam.xi`; control-flow arm shows the callee returns to its
caller with 0 instead of executing `return 7`.

Workarounds stay until the fix ships in a pinned release and is re-verified
(per the relay program); `dispatcher as Int` + Int param and the
local-first routing remain green.

## Findings

1. **B-13 (new, v0.64.3): fn-typed PARAMETER values do not survive any use
   as a C callback.** Cast to Int, re-passed to an extern fn-typed param,
   copied to a local, or boxed in a struct field -- all yield 0. Locals
   initialized directly from a top-level fn name are fine. This matches the
   m219 env-vs-code confusion family: the param holds the closure ENV
   representation and the exit-to-C path does not unwrap field 0 (or reads an
   empty slot).
2. **The GLFW 0.5.0 design is the fixed-dispatcher + registry pattern**
   (probe6): user-facing setters take `fn(...) -> Unit` values and store them
   in module-level `Vec[fn]` storage (m130 element semantics); only a fixed
   top-level dispatcher per event type has its address (`dispatch as Int`)
   handed to the DLL. Callers keep typed handlers with no user-side `unsafe`.
3. **The loader cast-call supports fn-typed params for top-level names**
   (probe4 `cast_fnparam=42`), so the DLL call itself needs no `Int` shim.
4. **B-14/B-15 (`probe7_element_units.xi`, negative compile repro):**
   calling a `Vec[fn]` ELEMENT with >= 2 arguments types the result as `()`
   at use sites (statement position silently discards -- why the glfw
   dispatchers were unaffected); and bare `return;` inside an explicitly
   `-> Unit` fn is a type error. The SDL3 0.5.0 filter/watch dispatchers work
   around both (1-arg handler shapes + structured ifs).
