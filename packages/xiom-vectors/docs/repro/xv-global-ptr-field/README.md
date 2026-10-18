<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# XVC-C-17 repro: imported-type module-level var stores drop pointer fields

Found 2026-10-15 while building the G-1 thread + sync smoke (the first
cross-thread shared-state pattern after the thread gate went green).

## Symptom

A module-level `var` whose declared type is a struct from an **imported
module** loses pointer fields on whole-struct assignment; the value reads
back as `null` in every function (scalar fields persist). A **local** type
with the same shapes works.

The natural lock-sharing pattern therefore breaks silently:

```xiom
var G_M: mutex.SyncMutex = mutex.SyncMutex{ locked: null };

fn main() -> Int {
  G_M = mutex.mutex_new();      // pointer field dropped
  ...
}
// G_M.locked reads null afterwards -> stdlib requires abort
// ("contract violated: requires at line 52") or, where checks are
// complied out, an UNGUARDED lock -> data race on shared state.
```

## Evidence (v0.64.5, Windows + WSL identical)

| # | shape | result |
|---|---|---|
| A | `GA = mutex.SyncMutex{ locked: hptr() }` (imported type, const ptr) | **pointer DROPPED** |
| B | `GB = mutex.mutex_new()` (imported type, cross-module call-return) | **pointer DROPPED** |
| C | `GM = Mixed{ p: hptr(); v: 9 }` (local type, same shapes) | pointer kept, `v=9` |
| D | local-local copy of the same struct | pointer kept |

Additional variants tested during localization (all green, ruling them
out): pointer value magnitude (small const / big const / heap ptr /
fn-returned struct into a **local** type), local-local copies, reads via
helper fns, and mixed scalar+pointer fields on local types. The trigger is
the imported-type global declaration + whole-struct store.

## Run

```powershell
. .\scripts\dev-env.ps1
.\scripts\build.ps1 docs\repro\xv-global-ptr-field\probe.xi -Name repro_global_ptr
.\out\repro_global_ptr.exe      # v0.64.5: exit 1 (2 failed checks)
```

```bash
cd /mnt/e/xiom-projects/xiom-xvector
. scripts/dev-env.sh
bash scripts/build.sh docs/repro/xv-global-ptr-field/probe.xi repro_global_ptr
./out/repro_global_ptr          # v0.64.5: exit 1 (2 failed checks)
```

## Workaround (used by the G-1 smoke)

Store the pointer as an `Int` global and reconstruct a local handle:

```xiom
var G_LOCKP: Int = 0;
// main: var m = mutex.mutex_new(); unsafe { G_LOCKP = m.locked as Int; }
fn bump() -> Int {
  var p: *Int = null;
  unsafe { p = G_LOCKP as *Int; }
  var m = mutex.SyncMutex{ locked: p };   // local type instance, local fn
  mutex.mutex_lock(&mut m); ...; mutex.mutex_unlock(&mut m);
}
```

Validated working (spinlock shares correctly across real threads).

## Provenance

Reproduced on v0.64.5 Windows + WSL. A v0.64.4 A/B was not possible: the
v0.64.4 compiler cannot compile the current stdlib tree, and its bundled
lib predates `xiom.sync.mutex.SyncMutex` (`unknown type`). Compiler lane
to bisect.

## Hypothesis

The global's declared type (imported module) and the store's struct
instance appear to use different layouts/field offsets at emission (the
XVC-C-14 same-name/layout class), or the imported-type global store path
drops non-scalar field stores. Cross-ref: the engine lane's W2 finding
("&mut struct FIELD writes miscompile"; `REL-20261015-1538-engine`).

## Filing

Bus item `REL-20261015-…-xvector` (to compiler, high), filed 2026-10-16
with the table above; xvector workaround shipped in
`tests/probes/probe_thread_sync.xi` (G-1).
