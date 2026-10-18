<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# XVC-C-11 / XVC-C-12 -- unit-context file-read defects on v0.64.1

**Status: re-tested GREEN in the original context unit on compiler v0.64.2**
(2026-10-09: a copy of `probe_wal_file`'s unit read an 11-byte file via
`io.read_file` + `slice.str_bytes` with length 11 and an unguarded 5-byte
`io.read_file_bytes` with length 5 -- both clean; the failing shape is gone).
Both were context-sensitive on v0.64.1, like the XVC-C-08 family: the SAME
stdlib call worked in a minimal unit and broke in another unit. The lane
keeps its byte-wise parser and `file_size < 25` guard as defense in depth
(both are strict-by-design, not solely workarounds).

## What was observed

In `tests/probes/probe_wal_file.xi`'s compilation unit (while building the
file-backed WAL):

- **XVC-C-11:** `io.read_file(path)` returned `Ok` for an 11+/1771-byte file
  written via `io.write_file_bytes`, but the returned Str's content was
  broken: `slice.str_bytes(s)` reported **0 bytes** (silent wrong data).
  `Str::from_utf8` showed the same class of breakage in that unit
  (correct length, element content read back as address-like digits when
  split/printed).
- **XVC-C-12:** `io.read_file_bytes(path)` aborted with
  `contract violated: ensures at 947:12` for files of **<= 8 bytes**
  (zero-byte files included); 9+ bytes read fine. The ensures is
  `result is Ok => result.len() >= 0`, which cannot be false for a
  successful read -- the check misfires and terminates the process.

## Minimal-unit controls (this bundle)

Both probes in this bundle exercise the same APIs on the current compiler
and **pass**:

- `probe_str_content.xi` -- writes 11 bytes, reads via `io.read_file`,
  expects `slice.str_bytes(s).len() == 11`: **green here** (broken in the
  file-WAL unit).
- `probe_tiny_read.xi` -- writes 5 bytes, reads via `io.read_file_bytes`,
  expects length 5: **green here** (aborts in the file-WAL unit).

This contrast (same source shape, different outcome per unit) is the
evidence: both defects are compilation-unit-context-sensitive, the same
class as XVC-C-08/C-09/C-10. Do not trust a minimal-unit green when moving
these calls into a larger unit.

## Workarounds (adopted by `durability.wal_file`)

- Read BYTES via `read_file_bytes` and parse them byte-wise; never handle
  file content as a Str (avoids XVC-C-11).
- Guard by `io.file_size(path)` and skip reads shorter than the shortest
  valid input (the WAL guard is `< 25`, which is also semantically exact: a
  valid WAL cannot be shorter, so nothing is lost) (avoids XVC-C-12).

## Repro recipe (observe the contrast)

```powershell
. .\scripts\dev-env.ps1
# controls: green in their own minimal units
.\scripts\build.ps1 docs\repro\xv-stdlib-file-read-defects\probe_str_content.xi -Name fsr
.\out\fsr.exe; "exit=$LASTEXITCODE"      # 0
.\scripts\build.ps1 docs\repro\xv-stdlib-file-read-defects\probe_tiny_read.xi -Name ftr
.\out\ftr.exe; "exit=$LASTEXITCODE"      # 0
# the failing context: probe_wal_file's unit (see its git history around the
# file-WAL commit; the first revision used read_file + unguarded reads)
```

## Impact

File-backed persistence cannot trust `read_file` (content loss in some
units) and must guard `read_file_bytes` against small files (fatal in some
units). Both make ordinary file I/O unreliable for durable components;
triage together with the C-08..C-10 family.
