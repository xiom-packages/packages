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
**Status:** STOPPED per circuit breaker; owner chose option (a).

**RESOLVED (2026-09-25, same session):** the packages-session coordinator
implemented `xiom.gguf` directly (option a). Two compile iterations (a
`Result[Int, Str]` vs `Result[Str, Str]` leaf-helper mismatch in two
branches) and one test-fixture fix (append a payload before parsing the
round-trip buffer; emit an implicit `general.alignment` KV when the builder
pads to a non-default alignment). Result:
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`; integrated as
`674b728` (package) + `631030c` (STATUS record). Lesson recorded for the
next wave: the delegate aborts were environmental, not scope-driven --
direct implementation by the coordinator is a working fallback after the
circuit breaker.

## 2026-09-26 — xiom.rpm port: 2 consecutive silent subagent aborts (resolved on attempt 3)

**Issue:** two porter workers for `packages/xiom-rpm/` terminated with empty
results and left **no files at all** (no `package.xi`, no directory). The
namespace check for `rpm` passed before dispatch; all wave-32 siblings
completed normally.

| Attempt | Executor | Session ID | Result |
|---|---|---|---|
| 1 | Agent Manager local (wave 32 batch) | `ses_f2253eaa8fferajMVUwC4zUSQ6` | idle afterwards, zero files |
| 2 | background `general` task (retry) | `ses_f21e9f553ffeSgTNGlDhlaN60G` | empty task result, zero files |
| 3 | background `general` task with skeleton-first instruction | `ses_f21c84abeffeqLF4EpKpBBXKu7` | 19/19 PASS, all six files delivered |

**Checks performed:** `packages\xiom-rpm` absent after attempts 1-2;
`port.ps1 -Package xiom.rpm` reported package not found.

**RESOLVED (2026-09-26, same session):** attempt 3 succeeded with the
skeleton-first mandate (create all six files with minimal compiling content
first, then iterate in place). Coordinator re-verified on the commit;
integrated as `b7fc365` (package) + `d9f12a2` (STATUS record), `port: PASS
(passed=19 failed=0 program_exit=0 exit=0)`. Fidelity note: the real on-disk
RPM header prefix is a 4-byte magic/version word + 4 reserved bytes, then the
index count and data-store size (16 bytes total), not "magic + 8 reserved";
the implementation follows the real layout.
