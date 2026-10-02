# Silent exit `-1` (expat/nbt) -- exact harness and environment notes

Supplement to README section 2. Written 2026-10-02 after the compiler lane
reported the issue "not reproducible" from a source-built v0.62.2 driver.
These are the precise conditions of every observation, so the same
environment can be reconstructed.

## Platform and binaries (the likely differentiator)

- **OS:** Windows x64 (the packages lane runs only on Windows, PowerShell 5.1).
  A Linux run cannot reproduce a Windows exit/flush path difference.
- **Toolchain:** `scripts/xiom.ps1` resolved **"0.62.2 (installed)"** --
  the deployed copy in `%LOCALAPPDATA%\xiom.new\bin` (exe + wasm dll), NOT a
  source-built driver. The deploy came from the repo release at the pin bump
  (2026-09-30, `COMPILER_VERSION` = `v0.62.2`).
- **Stdlib:** `E:\xiom-lang\stdlib` (checkout `stdlib-perf1`, `06d0ee7`).
- **Packages repo:** `E:\xiom-packages\packages` (the sweep ran on the
  2026-09-30 wave-44/45 era tree; both packages have been untouched since).

## Exact invocation (why `scripts/port.ps1` was not found elsewhere)

`scripts/port.ps1` lives in the **packages** repo:
`E:\xiom-packages\packages\scripts\port.ps1`. It is not shipped with the
compiler. The sweep ran, from the repo root:

```powershell
& .\scripts\port.ps1 -Package xiom.expat -TimeoutSec 60   # and xiom.nbt
```

What the harness does for a package with a suite (port.ps1 lines 143-197):

```powershell
Push-Location $packageDir          # cwd = the package directory
$proc = Start-Process -FilePath $tool.Xiom `
    -ArgumentList @("--run", "tests/test_conformance.xi") `
    -NoNewWindow -PassThru `
    -RedirectStandardOutput $outFile -RedirectStandardError $errFile
# ... waits with a watchdog, then:
$output = Get-Content $outFile -Raw
$programExit = [regex]::Match($output, "exit code:\s*(-?\d+)")   # driver summary
```

The critical detail: **the compiler + child program run with stdout/stderr
wired to FILES** (`Start-Process -NoNewWindow -RedirectStandardOutput`), not
to a console and not to a pipe. Direct console runs do not exercise the same
stdio path.

## Observed output (preserved logs)

`%TEMP%\kilo\sweep-v0622\xiom-expat.log` (original sweep) and
`%TEMP%\kilo\sweep-v0622-rerun\xiom-expat.log` (serial re-run) are byte-for-byte
the same shape; xiom.nbt likewise:

```
port: xiom.expat
  dir:      E:\xiom-packages\packages\packages\xiom-expat
  compiler: 0.62.2 (installed)
  stdlib:   E:\xiom-lang\stdlib
namespace-check: stdlib E:\xiom-lang\stdlib (1657 module namespaces)
  xiom.expat               OK (1 module(s))
namespace-check: 1 package(s), 1 module(s), 0 conflict(s)
  suite:    tests/test_conformance.xi
  compiled: a.exe
  exit code: -1

port: FAIL (passed=0 failed=0 program_exit=-1 exit=1)
```

Zero suite stdout (not even the banner `=== xiom.expat conformance tests ===`).
`compiled: a.exe` means the driver's compile stage succeeded; the `-1` is the
driver's own reported program exit code. Re-running identically reproduced it
twice.

## Flushed variant (the decisive control)

Copy the suite, insert `io.flush_stdout();` immediately after every
`io.println`, run the same harness:

- `xiom-expat`: prints normally -> **25/25 [PASS], "all tests passed", exit 0**
  (`%TEMP%\kilo\expat-inst.log`, 27 lines, preserved).
- `xiom-nbt`: prints -> **25/26**, the single `[FAIL]` is t5
  "strings: u16 length prefix, UTF-8 bytes, UTF-8 names" (a genuine assertion
  failure, likely independent of the exit/flush shape);
  `%TEMP%\kilo\nbt-inst2.log` preserved.

So the source executes fine; only the un-flushed, file-redirected run loses
all output and reports `-1`.

## Requested checks on the compiler side

1. Reproduce on **Windows x64** with the deployed `%LOCALAPPDATA%\xiom.new\bin`
   v0.62.2 (or deploy a source build there) and run the two suites through
   `scripts/port.ps1 -Package xiom.expat -TimeoutSec 60` (and `xiom.nbt`).
2. If still green, run the identical command manually with the same stdio
   shape: `Start-Process ... -NoNewWindow -RedirectStandardOutput out.txt
   -RedirectStandardError err.txt`, cwd = package dir.
3. Try direct `.\a.exe > out.txt 2> err.txt; $LASTEXITCODE` from the package
   dir (the sweep's "direct a.exe reproduces" observation was under the same
   file-redirection capture).
4. If the exit path turns out to be buffer/atexit related, a minimal probe is
   a suite-sized stream of `io.println` output (~2-4 KB) with and without
   `io.flush_stdout()`, stdout redirected to a file, on Windows.
5. `xiom.nbt` t5 is a separate real failure once output survives: high-byte
   `Vec[UInt8]` compares were probed correct on v0.62.2, so reduce it inside
   nbt's string encode/decode + name lookup.

Artifacts referenced here are on the packages machine; the committed suite
sources and the registry artifacts in README section 2 are the portable
reproduction input.
