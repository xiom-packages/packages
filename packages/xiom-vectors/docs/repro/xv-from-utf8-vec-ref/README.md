<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->


Status: **FIXED on compiler v0.64.2** (2026-10-09 re-test): the
`&Vec[UInt8]` spelling compiles and the probe returns `A` (exit 0, Windows;
WSL same across the full battery). The engine + suite payload codec use the
`&` spelling again. Kept as a regression repro.
# XVC-C-07 repro: `Str::from_utf8(&Vec[UInt8])` emits invalid LLVM IR

Found on **v0.64.0/v0.64.1** (Windows + WSL; fixed in v0.64.2, m222).

Passing a **reference** to `Str::from_utf8` type-checked on v0.64.1 but died
in clang:

```
$ xiom -o out\p.exe docs\repro\xv-from-utf8-vec-ref\probe.xi
error: clang failed with exit code 1
  stderr: xiominput.ll:648:40: error: invalid getelementptr indices
  648 |   %tmp68 = getelementptr %struct.Vec*, %struct.Vec** %tmp67, i32 0, i32 0
```

The stdlib always passes the Vec **by value** (`convert/cstring.xi:47`,
`convert/escape.xi:577`, `compress/compress.xi:526`), and that form was the
workaround:

```xiom
var kb = Vec[UInt8].new();
kb.push(65u8);
var s = Str::from_utf8(&kb);   // v0.64.1: clang exit 1; v0.64.2: green
var t = Str::from_utf8(kb);    // works on both
```

Found while implementing the XVECTOR payload WAL codec
(`src/engine.xi` `payload_decode`); the engine passed by value until the
v0.64.2 fix let the lane revert to the `&` spelling.
No silent-wrong-code path observed -- the compile fails loudly.

Reproduce:

```powershell
. .\scripts\dev-env.ps1
& $env:XIOM_COMPILER -o out\p.exe docs\repro\xv-from-utf8-vec-ref\probe.xi   # v0.64.2: exit 0
.\out\p.exe; "exit=$LASTEXITCODE"                                            # expect 0
```
