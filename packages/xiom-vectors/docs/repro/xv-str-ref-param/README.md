<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

Status: **OPEN -- re-tested unchanged on v0.64.3 (Win 71 / WSL 127) and
v0.64.4 (2026-10-12: Win 167 / WSL 63; expect 65)** (found 2026-10-09, M-D2
slice; relayed via `docs/RELAY-COMPILER.md` Addendum 9).

# XVC-C-13 repro: `&Str` parameters are unknown to the type checker (i64 fallback)

Found on **v0.64.2** (Windows + WSL) while adding the manifest-file registry
(`src/durability/manifest_file.xi`): `manifest_name_valid(name: &Str)`
compiled with

```
xiom: warning: unknown type '&Str' -- defaulting to i64. This may produce incorrect code.
```

and took the i64 fallback path: every name validated as INVALID
(`slice.str_bytes` on the i64 produced zero/garbage bytes), so
`manifest_persist` refused every registry. The lane switched the parameter
to `Str` **by value** (the codebase convention: every Str parameter in the
stdlib and this lane is by value); with the value form the same logic is
green.

Minimal repro (`probe.xi`):

```xiom
fn first_byte(s: &Str) -> Int {
  var b = slice.str_bytes(s);
  if b.len() == 0 { return -1; }
  return b[0] as Int;
}
...
var n = first_byte("A");   // expect 65
```

Observed:

| Platform | Result | Build |
|---|---|---|
| Windows | `first_byte(A)=71`, exit 1 | warning `unknown type '&Str' -- defaulting to i64`; build OK |
| WSL | `first_byte(A)=127`, nonzero exit | same warning; build OK |

The warning is loud; the wrong value is silent. No crash observed.

Reproduce:

```powershell
.\scripts\build.ps1 docs\repro\xv-str-ref-param\probe.xi -Name strref
.\out\strref.exe; "exit=$LASTEXITCODE"        # v0.64.2: prints 71, exit 1
```

```bash
bash scripts/build.sh docs/repro/xv-str-ref-param/probe.xi strref
./out/strref                                    # v0.64.2: prints 127
```

Workaround: pass `Str` by value (never `&Str`). All XVECTOR Str parameters
are by value; the stdlib follows the same convention, so this shape had
never been exercised until the manifest codec.
