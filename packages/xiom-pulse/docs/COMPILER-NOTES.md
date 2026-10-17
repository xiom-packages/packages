# Compiler notes -- fn-value defects hit by the hook seam

Toolchain: XIOM v0.64.6 (installed), stdlib `E:\xiom-lang\stdlib`.

The `xiom.pulse.app` hook seam stores consumer-supplied non-capturing fn
values. Three compiler defects surfaced while building it. Each is minimized
into a runnable probe in this directory; all three were reproduced on the
pinned compiler.

## 1. Module-global fn-typed variable (`probe_fn_global.xi`)

```xi
fn inc(x: Int) -> Int { return x + 1; }
var hook: fn(Int) -> Int = inc;
pub fn main() -> Int { return hook(1); }
```

Type-checks, then codegen fails (`use of undefined value '@__fnwrap_1'` or a
malformed top-level IR entity). Consequence: hooks cannot live in a
process-wide global registry; `HookSet` is an explicit value passed to
`dispatch_with` / `handle_connection_with` / `serve_with`.

## 2. Adjacent fn-typed struct fields (`probe_two_hooks.xi`)

A struct with `pre: fn(Int) -> R` immediately followed by
`after: fn(Int) -> Int` miscompiles field layout: assigning `after`
overwrites the `pre` slot, so the pre call returns garbage at runtime (the
probe exits 10). Consequence: `HookSet` keeps its hook values in
one-element `Vec` slots, which probe as stable, instead of two adjacent fn
fields. Nested single-fn boxes also crash; do not reintroduce them.

## 3. fn-typed alias as a callable parameter (`probe_fn_alias.xi`)

```xi
pub type F = fn(Int) -> Int;
fn install(v: &mut Vec[fn(Int) -> Int], f: F) { v.push(f); }
```

Type-checks and compiles, then crashes at the indirect call (access
violation) when the stored value is invoked. The same function with the
direct fn type in the signature works. Consequence: the public seam uses
direct fn types everywhere; no `PreHook` / `AfterHook` aliases are exposed.

Workaround summary for consumers: use the direct signatures shown in
`SPEC.md` section 2.6 and treat `HookSet` as a value, not a global.
