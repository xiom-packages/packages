# B-34 probe: cross-module type-alias in a generic position does not unify

**Status: RED on v0.64.5 AND v0.64.6** (pre-existing; NOT a .6 regression).
Found while landing the v0.64.6 overnight wave (xiom.tensorflow cross-check).

## Symptom

A function parameter spelled with a module-local type alias in a generic
position (`&Vec[Handle]`, where `Handle = Int`) cannot be called from
another module:

    error[T001]: 8:11: argument 1 type mismatch: expected Vec[Handle], found Vec[Int]

The callee's `Vec[Handle]` and the caller's `Vec[d_mod.Handle]` do not
unify even though both resolve to `Vec[Int]` (alias target).  The same
holds with `Vec[Int]`-typed values, typed pushes, fn-returned aliased
values and `as`-casts -- the *declared* generic instantiation keeps the
alias name nominally and never matches.

## Controls (same runs)

- LOCAL alias (both fn and caller in one module): GREEN -- `length=1`,
  no error (the spelling matches inside one module).
- Scalar alias params (non-generic): GREEN in the fleet (fleet-wide).

## Repro

    $env:XIOM_COMPILER=<slot>\bin\xiom.exe
    & $env:XIOM_COMPILER --run docs/repro/bindings-pilot/vec-alias-generic/probe.xi

EXPECTED (fixed): runs, exit 1 (length of one element).
ACTUAL (v0.64.5 + v0.64.6): `error[T001]: 8:11 ... expected Vec[Handle],
found Vec[Int]`; compilation aborted.

## Impact / workaround

Every API declaring `&Vec[Alias]` / `Vec[Alias]` (handle-alias patterns:
`pub type TfTensor = Int` etc.) is uncallable from other modules.  The
fleet workaround: avoid Vec-of-alias in public signatures (pass `Int`
handles singly or use concrete vecs); document in the package SPEC when
forced.

## Asked of the compiler lane

Unify generic instantiations through alias targets (resolve-then-compare,
not name-compare) so `Vec[Alias]` == `Vec[Int]` in argument checks.
Severity: medium (papercut; pre-existing both tracks).  Filed with the
overnight landings (relay item).
