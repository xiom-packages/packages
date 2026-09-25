<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Struct-field / Result-payload `Vec` reference probes (v0.61.3)

Requested by the compiler session (Relay #2): the exact probe for "`&struct.field`
into a `&Vec[UInt8]` parameter reads an empty vector", with field type and
ownership context. Three probes isolate the shape.

Environment: `XIOM Compiler v0.61.3` (`C:\Users\lefte\AppData\Local\xiom\bin\xiom.exe`),
`XIOM_STDLIB=E:\xiom-lang\stdlib`. Run from the repository root (Windows
PowerShell 5.1; note the explicit empty `-Stdlib` so `--run` reaches the
compiler arguments):

```powershell
& .\scripts\xiom.ps1 -Stdlib "" --run docs\repro\struct-field-vec\<file>.xi
```

or directly: `xiom --run <file>` with `XIOM_STDLIB` set.

## Matrix

| File | Shape (ownership context) | v0.61.3 observed | After fix |
|---|---|---|---|
| `probe_struct_field.xi` | local `var` struct; `byte_len(&b.data)`, field type `Vec[UInt8]` | **green**: prints `direct field: 3`, exit 0 | exit 0 |
| `probe_result_value.xi` | local `Result[Vec[UInt8], Str]` returned from a function (Ok leaf helper), `r.is_ok` checked, `byte_len(&r.value)` | **BROKEN**: prints `result payload: 0` (empty vector), exit 10; binding `let v = r.value; byte_len(&v)` prints 3 | exit 0 |
| `probe_result_struct_field.xi` | local `Result[Blob, Str]`, `byte_len(&r.value.data)` (payload struct field) | **green**: prints `result field : 3`, exit 0 | exit 0 |

## Minimal repro statement (Probe B)

```xi
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] { return Ok(v); }

fn make() -> Result[Vec[UInt8], Str] {
  let d = Vec[UInt8].new();
  d.push(11); d.push(22); d.push(33);
  return _ok_bytes(d);
}

pub fn byte_len(v: &Vec[UInt8]) -> Int { return v.len(); }

fn main() -> Int {
  let r = make();
  if !r.is_ok { return 90; }
  let direct = byte_len(&r.value);  // reads 0            <-- defect
  let v = r.value;                  // bound local
  let bound = byte_len(&v);         // reads 3
  return direct == 3 && bound == 3 ? 0 : 10 + direct;
}
```

Field type: `Vec[UInt8]`. Ownership context: `r.value` is the Ok payload field of
a local `Result` value; the reference is taken directly on the field expression.
The same expression bound to a local first behaves correctly, and a struct field
one hop deeper (`&r.value.data`, Probe C) is also correct, so the defect is
specific to the `Result` payload field itself — consistent with the
Vec-handle copy/materialization class the compiler session identified for
by-value receivers.

These probes are what waves 20-24 (e.g. `xiom.aiff`, `xiom.quotedprintable`)
worked around by binding `r.value` to a local before any `&Vec[UInt8]` call;
`SESSION.md` section 7 trap 4 documents the workaround.
