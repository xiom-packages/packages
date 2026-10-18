<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# XVC-C-09 -- WSL segfault: nested-field mutation across modules

**Status: repro GREEN on compiler v0.64.2** (2026-10-09 re-test: the probe runs
green on WSL + Windows; v0.64.2's release notes state mutating methods through
nested fields write through, which is the suspected root cause). The lane
keeps the local-assign pattern (clean code); the revision-pinned red remains
`bca8b7f`'s compiled `engine_set_index` -- a full revert of the workaround was
not re-attempted, so this is a weaker re-test than C-07/C-08.

**Maintenance 2026-10-12 (v0.64.4):** the probe's imports were refreshed to
`use xiom.vectors;` -- the pre-swap `xiom.vector.types.*` paths died in the
60th-pass package swap, and v0.64.4 makes unresolved imports hard errors
(m266). Re-run on v0.64.4: exit 0 (Windows).

## Summary

After the `HNSWGraph` id-map fields landed, calling
`engine_set_index(&mut eng, Hnsw, params)` (module
`xiom.vector.engine.core`) segfaulted **on WSL/Linux** while the Windows
build of the same revision was green (probe stress 6/6). The crash is in
the compiled function: the identical steps inlined in the probe unit are
green, and the loops alone (raw store) are green. On WSL the process dies
right after the call starts (no output past the caller's previous line).

Failing shape (WSL, commit `bca8b7f`): a dependency-module function that
repeatedly (a) assigns a whole nested struct field,
`eng.graph = hnsw_new(...)`, and (b) loops mutating it through *another*
module's function, `hnsw_insert_ref(&mut eng.graph, ...)`, while reading
sibling fields (`eng.store`, `eng.metric`).

Workaround (adopted in the fix commit): build the graph in a LOCAL variable
and assign the field once at the end. Verified green on WSL + Windows.

## Repro (revision-pinned)

`probe.xi` is the engine-path probe used to isolate the crash:

```powershell
# at commit bca8b7f (pre-workaround), Windows: green
. .\scripts\dev-env.ps1
.\scripts\build.ps1 docs\repro\xv-wsl-nested-field\probe.xi -Name wsl_nested
.\out\wsl_nested.exe

# WSL: segfault at "step 6: engine_set_index" (steps 1-5 inline are green)
wsl.exe -d Ubuntu --exec /bin/bash -lc "cd /mnt/e/xiom-projects/xiom-xvector && . scripts/dev-env.sh && bash scripts/build.sh docs/repro/xv-wsl-nested-field/probe.xi wsl_nested && ./out/wsl_nested"
```

At the fix commit and later the same probe runs green everywhere.

## Evidence

- WSL `run-probe.sh tests/probes/probe_engine_hnsw.xi` -> segfault 3/3
  runs (same binary), immediately after `set_index` is called.
- Windows: `probe_engine_hnsw` x2 + 6/6 stress builds green.
- Inlined steps in the probe (fresh graph assignment, ef setter, 150
  inserts via `hnsw_insert_ref`, param validation, field writes) all green
  on WSL; the crash is specifically the compiled `engine_set_index` call.
- WSL `probe_hnsw_recall` (n=200 + n=800, id-map checks) and
  `probe_hnsw_codec` (duplicate-id rejection, map rebuild) were green with
  the same id-map code -- context-sensitive, same family as XVC-C-08.

## Impact

Silent platform divergence: a revision that passes on Windows can crash on
Linux/WSL without a compiler diagnostic. Any function that mutates a nested
struct field through another module in a loop is a candidate shape.

## Workaround

Build into a local value and assign the nested field once; re-verify on WSL
(the WSL spot check is part of every XVECTOR wrap).
