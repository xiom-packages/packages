<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# `ptr as Int` cast combined with a second statement in one `unsafe` block (v0.64.4, B-30)

Minimal shape found shipping `xiom.phonon` 0.3.0 (owned planar audio buffers built
in XIOM memory). Pure XIOM -- no C source, no DLL.

## Failure (v0.64.4, compiler `%LOCALAPPDATA%\xiom.new\bin\xiom.exe`)

`probe.xi`: a function that

1. takes the address of a local `Vec[Float32]` in its own `unsafe` block
   (`base = data.as_mut_ptr() as Int`) -- this part is fine;
2. later opens another `unsafe` block that **combines** a pointer-to-Int cast of a
   second local (`let pa = ptrs.as_mut_ptr() as Int;`) with a call that mutates a
   third local (`s_w64(&mut slot, 8, pa);`);
3. returns a struct with several `Vec` fields.

fails codegen:

```
error: clang failed with exit code 1
stderr: xiominput.ll:1731:45: error: use of undefined value '%tmp42'
   %tmp1018 = load %struct.Vec, %struct.Vec* %tmp42
```

No XIOM-level diagnostic; the failure is in the lowered IR. `--emit-ir` alone
succeeds (the IR contains the undefined value); `--run` fails when clang
rejects it.

## Fix / workaround (shipped in `xiom.phonon` 0.3.0)

Isolate **every** `ptr as Int` cast in its own `unsafe` block; never combine a cast
with another statement:

```xiom
  var pa = 0;
  unsafe {
    pa = ptrs.as_mut_ptr() as Int;
  }
  s_w64(&mut slot, 8, pa);          // call moved outside the cast block
```

`probe_fixed.xi` is the same function with the split blocks; it compiles and runs
(`ch=2 first=0`). Bisect evidence (same probe, one edit each):

| Variant | Edit | Result |
|---------|------|--------|
| `probe.xi` | cast + `s_w64(&mut slot, ...)` in one block | **codegen failure** |
| `probe_fixed.xi` | cast alone in its own block, call outside | green |
| k2 | second block deleted entirely | green |
| m1 | first (data) cast block kept, failing block kept | **codegen failure** |
| u1/u2/u3 | cast + plain assignment / direct byte write / call not using the casted value | green |

Related: B-21 (`&mut` of struct-return temps), B-17 (pointer arithmetic) -- same
family of confined-block SSA/lifetime lowering issues.

## Run

```powershell
& .\scripts\xiom.ps1 --run docs\repro\bindings-pilot\owned-slot-cast\probe.xi        # expect: clang failed / undefined value
& .\scripts\xiom.ps1 --run docs\repro\bindings-pilot\owned-slot-cast\probe_fixed.xi  # expect: ch=2 first=0
```
