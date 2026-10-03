<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Child->parent module calls: visibility re-verification (v0.62.2)

**Supersedes the blanket 2026-10-02 finding** ("a package child module
cannot import or call its direct parent module"). Re-verified on
2026-10-03 on the installed v0.62.2 with a throwaway two-module package
(`xiom.probe-cp`, staged under `packages/`, run with
`scripts/port.ps1 -Package xiom.probe-cp -TimeoutSec 60`, then deleted;
the sources are reproduced below).

## Result

The boundary is **`pub` visibility**, not the parent/child relation:

| Variant | Shape | v0.62.2 result |
|---|---|---|
| 1 | parent `fn helper` (non-pub); child `use xiom.probe_cp;` + `return helper();` | **FAIL**: `error[T001]: catalog body [xiom.probe_cp.child] ... undefined variable 'helper'` |
| 2 | parent `pub fn helper`; child `fn child_call` (non-pub); test module calls `child_call()` | parent call resolves; test call **FAILS** T001 -- same visibility rule one level down |
| 3 | both functions `pub` | **PASS**: prints `child_call=7`, program exit 0 |
| 4 | cycle: parent adds `use xiom.probe_cp.child;` + `pub fn parent_uses_child()` calling `child_call()` | **PASS**: prints `child_call=7`, exit 0 |
| 5 | alias: `use xiom.probe_cp as p;` + `p.helper()` | **PASS**: prints `alias helper=7`, exit 0 |

Production corroboration (published, green on v0.62.2):
`xiom.training` re-ran **26/26 PASS** on 2026-10-03 -- its children
`checkpoint`/`logger`/`schedules` call `pub` helpers (`_ok_ints`,
`_tr_div_round`, ...) defined in the direct parent `xiom.training`, with
no local copies; the parent does not import the children (acyclic).
`xiom.data/src/batch.xi` calls parent `pub dataset_num_samples`;
`xiom.video` children call parent `pub video_rescale`/`video_sniff`;
`xiom.serverless` children import the parent. All published at `0.1.0`.

The wave-49 refactors (`helm`, `docker`, `vault`; "siblings only") were
most plausibly reacting to the non-pub visibility error; their original
probes are not in `docs/repro`, so the exact construction is not
re-checked here. The siblings-only workaround can be narrowed to
"declare cross-module helpers `pub`" at Tier-2.

## Minimal sources (stage as `packages/xiom-probe-cp/`)

`package.xi`:

```xi
package xiom_probe_cp {
  name: "xiom.probe-cp";
  version: "0.1.0";
  description: "throwaway child->parent probe";
  license: "MIT OR Apache-2.0";
  modules: ["xiom.probe_cp", "xiom.probe_cp.child"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
```

`src/probe_cp.xi` (variant 4 adds the `use` + `parent_uses_child`):

```xi
module xiom.probe_cp

pub fn helper() -> Int {
  return 7;
}
```

`src/child.xi`:

```xi
module xiom.probe_cp.child

use xiom.probe_cp;

pub fn child_call() -> Int {
  return helper();
}
```

`tests/test_conformance.xi` (variant 5 swaps the import for the alias):

```xi
module probe_cp_tests

use xiom.io;
use xiom.convert;
use xiom.probe_cp.child;

fn main() -> Int {
  let v = child_call();
  io.println("child_call=" + int_to_string(v));
  if v == 7 { return 0; }
  return 1;
}
```

Note: `port.ps1` reports `FAIL (passed=0 ...)` for this suite because the
probe has no `[PASS]` lines for its parser to count; the compiled program
itself prints `child_call=7` and exits 0 -- read the program output, not
the wrapper summary, for this probe.
