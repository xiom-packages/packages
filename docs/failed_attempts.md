<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Failed attempts log

Circuit-breaker record per `00-core-protocols` (stop after 3 failed attempts on a
specific issue, log here, escalate).

## 2026-09-25 — xiom.gguf port: 3 consecutive silent subagent aborts

**Issue:** three separate porter workers for `packages/xiom-gguf/` terminated with
empty results and left **no files at all** (no `package.xi`, no directory). All
other wave-27 packages completed normally; this is specific to gguf.

| Attempt | Executor | Session ID | Result |
|---|---|---|---|
| 1 | Agent Manager local (wave 27 batch) | `ses_f258975e8ffeUokkSYbqp76R4X` | idle afterwards, zero files anywhere |
| 2 | background `general` task (skeleton-first not yet applied) | `ses_f25757fecffeR0eOx7NFjXFxrT` | empty task result, zero files |
| 3 | background `general` task with skeleton-first instruction | `ses_f2571292affeCvAExPY0TBHjNA` | empty task result, zero files |

**Checks performed:** `Get-ChildItem packages\xiom-gguf -Recurse -Force` and the
repo root both empty after each attempt; `port.ps1 -Package xiom.gguf` reports
`package not found (no package.xi)`.

**Not the cause:** the prompt/spec is otherwise similar to sibling containers
(`xiom.safetensors` 21/21, `xiom.marc` 22/22, `xiom.fix` 20/20 completed in the
same wave with the same trap list); the compiler and stdlib are green for every
other package; no git/STATUS/publish instructions were violated (nothing was
created to violate them with).

**Escalated:** wave-27 report to the owner/orchestrator; board INFO to `main`.
**Status:** STOPPED per circuit breaker. Suggested options for the next session
(owner decision): (a) coordinator implements `xiom.gguf` directly, (b) split the
scope into `xiom.gguf` header/KV + tensor-info indexing as two smaller packages,
(c) retry a delegate after the compiler pin bump when the subagent runtime is
restarted. Namespace is reserved and stays unallocated until then.
