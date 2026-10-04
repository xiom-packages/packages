<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# `Vec[(Str, Str)]` read-after-mutation: crash/hang (v0.62.3) -- compiler-lane handoff

Found while restoring `xiom.grpc`. The suite binary crashes
(`0xC0000005`, exit `-1073741819`) or hangs, **before any output**, in a
compact, call-dependent case. Reported to the compiler lane 2026-10-04;
they asked for the smallest failing subset, which this bundle provides.

## Smallest failing subset

`packages/xiom-grpc/tests/probe_suite_min.xi` (stays in-package so the
library imports resolve):

```xi
module tuple_vec_min_probe

use xiom.grpc;
use xiom.grpc.types;
use xiom.io;
use xiom.convert;

fn test_set_new_key() -> Int {
  var payload: Vec[Int] = Vec[Int].new();
  var meta: Vec[(Str, Str)] = Vec[(Str, Str)].new();
  var req = grpc_request_new("svc", "m", payload, meta);
  grpc_metadata_set(&mut req, "grpc-timeout", "5s");
  if req.metadata.len() == 1 && req.metadata[0].0 == "grpc-timeout" { return 0; }
  return 1;
}

fn main() -> Int {
  io.println("start");
  io.flush_stdout();
  let rc = test_set_new_key();
  io.println("rc=" + int_to_string(rc));
  io.flush_stdout();
  return rc;
}
```

Run (from the repo root):

```powershell
& .\scripts\xiom.ps1 -Stdlib "E:\xiom-lang\stdlib" --run packages\xiom-grpc\tests\probe_suite_min.xi
# v0.62.3 + local main m184..m188: crash 0xC0000005, NO output (even 'start')
```

## Evidence matrix (v0.62.3; main m184..m188 same results)

| Variant | Result |
|---|---|
| `probe_suite_min.xi` (test function called from main) | **crash `0xC0000005`** pre-output |
| same file, call replaced by `let rc: Int = 0;` | runs (`start`, `rc=0`, exit 0) -> **call-dependent** |
| `probe_direct.xi` (same ops inline in main, **without** the `metadata[0].0` read) | runs (`start`, `len=1`, exit 0) |
| `probe_direct.xi` **with** `req.metadata[0].0 == "grpc-timeout"` | **hangs** (killed by the 30s watchdog) |
| `probe_tuple_vec_set.xi` (plain `Vec[(Str, Str)]` set helper, len only) | runs |
| `probe_struct_meta.xi` (struct wrapper + exact mutation body, len only) | runs |

**Fault data:** Windows Application Error -- faulting app `a.exe`,
faulting module `ntdll.dll`, exception `0xc0000005`, fault offsets
`0x000000000001ff2a` and `0x00000000000c4a0f` (two runs). The hang variant
produces no fault record (watchdog-killed).

**Lead:** the differentiator is reading a tuple-`Str` element
(`vec[i].0`) **after the vector was mutated through the library path**
(`grpc_metadata_set`, which destructures `let (k, v) = &vec[i]` and
rewrites/pushes elements); the same read pattern without the read or
without the mutation runs.

`xiom.grpc` stays unpublished until this is resolved.
