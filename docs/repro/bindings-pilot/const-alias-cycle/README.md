<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Const alias across modules with the same name (v0.64.4, B-28)

Found shipping `xiom.phonon` 0.3.0. The binding generator emitted
`src/phonon_abi.xi` with the canonical `IPL_*` constants and the root module
re-declared a convenience alias per constant, e.g.

```xiom
// phonon.xi
pub const IPL_STATUS_SUCCESS: Int = abi.IPL_STATUS_SUCCESS;   // alias, same name
```

Compiling any consumer that referenced `abi.IPL_STATUS_SUCCESS` overflowed the
compiler (no XIOM diagnostic):

```
thread '<unknown>' has overflowed its stack
```

## Minimal repro (this directory)

```
part.xi   module cyc_part;  pub const K: Int = 9;
cyc.xi    module cyc;       use cyc_part;  pub const K: Int = cyc_part.K;
probe.xi  module cyc_probe; use cyc; use cyc_part;
                            fn f() -> Int { let x = cyc_part.K; return x + cyc.K; }
```

```powershell
& .\scripts\xiom.ps1 --emit-ir docs\repro\bindings-pilot\const-alias-cycle\probe.xi
# expect: thread '<unknown>' has overflowed its stack
```

The recursion needs **both** modules in the compilation unit: with `probe.xi`
importing only `cyc_part` (so `cyc.xi` is never loaded) the same program
compiles. In the package this happened for exactly the names that existed in
both modules (references to `abi.PHONON_HEADER_SHA256` or
`abi.IPL_HRTFTYPE_DEFAULT`, which had no alias, were green).

## Fix / workaround (shipped in `xiom.phonon` 0.3.0)

One canonical home per constant name across the package: the root module
declares no aliases; every constant lives only in `xiom.phonon.abi` (generated)
or `xiom.phonon.exports`, and code refers to `abi.X` / `exports.X` directly.
Prefix-only helpers in the root (`PHONON_LOAD_*`, `PHONON_SONAME`) are unique
names.

## Run

```powershell
& .\scripts\xiom.ps1 --emit-ir docs\repro\bindings-pilot\const-alias-cycle\part.xi   # green
& .\scripts\xiom.ps1 --emit-ir docs\repro\bindings-pilot\const-alias-cycle\probe.xi  # overflow
```
