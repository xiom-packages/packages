# C-ORBIT-15: a UTF-8 BOM on a module file breaks catalog discovery

> **Status:** FIXED on compiler main `18415ede2` (2026-10-21); v0.64.8
> predates the fix. The fixture stays as-is (BOM included) to re-test on the
> next archive: `main.xi` should print `v=7` unchanged.

Found 2026-10-21 while adding the Station `station/src/protocol.xi` module on
**v0.64.8** (Windows exe `ee3ee902...`). The compiler reported
`T001: unresolved import 'xiom.station.protocol'` even though the file and its
manifest were correct. Stripping the UTF-8 BOM made the same file compile.

A BOM is harmless when the module is imported from the entry file's own
directory and the module name matches the file name (the path-based lookup
wins). It breaks the **catalog header index** when the module path does not
match the file name, which is the normal layout for composed source roots
(`station/src/protocol.xi` declares `xiom.station.protocol`).

## Minimal repro

```
docs/repro/utf8-bom-module/
  main.xi               module repro.bom_main; use repro.bom_impl;
  sub/impl.xi           <UTF-8 BOM> module repro.bom_impl; pub fn bom_value() -> Int { return 7; }
```

`main.xi`:

```xi
module repro.bom_main

use xiom.io;
use repro.bom_impl;

pub fn main() -> Int {
  io.println("v=" + bom_value().to_str());
  return 0;
}
```

`sub/impl.xi` (bytes `EF BB BF` before `module`):

```xi
module repro.bom_impl

pub fn bom_value() -> Int {
  return 7;
}
```

Observed on v0.64.8 (exit 1):

```
error[T001]: 6:5: unresolved import 'repro.bom_impl'
  = note: Unresolved names prevent the compiler from generating correct code.
  = help: The identifier is not in scope. Add a `use` import or define it.
```

There is no BOM diagnostic. Stripping the three BOM bytes (and leaving the
rest identical) makes the same tree print `v=7`, exit 0.

## Why it matters

PowerShell 5.1 `Set-Content -Encoding UTF8` writes a BOM by default on
Windows; editors and generators also emit them. A BOM is valid UTF-8 and
common, so a silent "unresolved import" is a costly, misleading failure mode
for consumers. The compiler should either strip a leading BOM before
tokenization or emit a specific "file starts with a UTF-8 BOM" diagnostic.

## Workaround used by ORBITDB

Save all `.xi` sources as UTF-8 **without** a BOM. The lane's `.gitattributes`
keeps `*.xi` LF; the BOM is not line-ending metadata, so it survives checkout.
To strip one from PowerShell:

```powershell
$p = 'path\to\file.xi'
$t = [System.IO.File]::ReadAllText($p)
if ($t.Length -gt 0 -and $t[0] -eq [char]0xFEFF) { $t = $t.Substring(1) }
[System.IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($false)))
```

## Repro command

```powershell
.\scripts\run.ps1 docs\repro\utf8-bom-module\main.xi
```

WSL: `scripts/run.sh docs/repro/utf8-bom-module/main.xi`. The `sub/impl.xi`
fixture is committed with the BOM intentionally; do not "fix" it without
re-testing the finding.
