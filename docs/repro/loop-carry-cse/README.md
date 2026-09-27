<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Loop-carried CSE repro (v0.61.3)

Reduction attempt for the loop-carried CSE miscompile observed by
`xiom.amqp`'s port. **The reductions here do NOT trigger on the installed
v0.61.3** (all values correct); the exact pre-fix loop is included below for
a targeted retry on the next build.

Run from the repository root:

```powershell
& .\scripts\xiom.ps1 -Stdlib "E:\xiom-lang\stdlib" --run docs\repro\loop-carry-cse\probe_loop_cse.xi
```

## Original report

The amqp port hit a stack decoder where `ends.push(pos + 4 + sub_len)`
reused the previous push's value in the second loop iteration; any two
containers in one parent failed with `bad table`/`bad array` (found by
byte-level bisection). Binding the expression to a local first fixed it, and
the committed workaround decodes nested containers with a recursive
per-container function (comment at `packages/xiom-amqp/src/amqp.xi:1235`).

The pre-fix loop, recovered from the porting session's edit history:

```xi
let sub_len = _read_u32(data, pos);
if sub_len > cur_end - pos - 4 {
  return _err_int("amqp: bad table");
}
_tree_push(t, 7, key, 0, 0, Vec[UInt8].new());
ends.push(pos + 4 + sub_len);
kinds.push(7);
sp = sp + 1;
pos = pos + 4;
```

## Probe results (v0.61.3, 2026-09-27)

```
v1 ends=6,13 pos=13
v2 child_ends=11,19 pos=19
v3 outer=6,13 op=13
bad=0
```

| Variant | Shape | Result |
|---|---|---|
| V1 | flat loop: `ends.push(pos + 4 + sub_len)` + `pos = pos + 4 + sub_len` | correct |
| V2 | per-container walk of two sibling children with the inline push expression | correct |
| V3 | nested loops rebuilding parent end state | correct |

Exit code: `bad` (0 today). If a future build changes behaviour, the probe
exits nonzero and prints which value went stale.

## Next step for the compiler lane

The full failing decoder lived in `packages/xiom-amqp/src/amqp.xi` before
the workaround; its recursive replacement plus the fragment above should be
enough to reconstruct the two-container input (the probe's V2 buffer is the
same layout: root length 15, child tag 7/len 2, child tag 7/len 3).
