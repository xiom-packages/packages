<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xiom.thread real-spawn gate -- GREEN on v0.64.5 (2026-10-15); was "compiles green, AVs at the runtime entrypoint" (v0.64.3 + v0.64.4)

Found 2026-10-11 (G-phase groundwork pass) by the xvector lane while
probing the threading primitives for the concurrency phase.

## Question

Can a consumer start REAL OS threads through `xiom.thread`'s
extern-backed `spawn[T]` / `JoinHandle.join`? The `xiom.thread.spawn`
module documents a simulation ("the current toolchain cannot start real
OS threads -- fn-to-pointer casts are rejected and the runtime thread
entrypoint AVs"), so the lane pinned the real path as a gate probe for
the G phase.

## Result on v0.64.3 (installed lane-local)

- **Compile: GREEN** -- `let raw_fn = f as *UInt8;` (thread.xi:46) is
  accepted; the unit builds on Windows and WSL.
- **Run: ACCESS VIOLATION** -- exit `-1073741819` (`0xC0000005`) on
  Windows; `Segmentation fault (core dumped)` on WSL.
- **Fault localization (`probe_marks.xi`)** -- marks rewrite
  `out/thread_abi_mark.txt` at each stage; the last surviving mark is
  **`M2: spawn returned`**: the handle IS created, then `join` (worker
  entry / completion path) never yields `M3`, and the worker's own
  `W0: worker entered` mark never appears. The AV is in the
  worker-entry/join machinery, not in the cast or the spawn call.
- The pure-math variant (`probe.xi`, no marks) crashes identically
  (stdout buffering hides it; the marks variant proves the stages).

## Re-run on v0.64.4 (2026-10-12)

Unchanged: the probe builds green on Windows + WSL, and the run still AVs
at the same point -- Windows exit `-1073741819` (0xC0000005), WSL SIGSEGV;
the marks variant's last surviving mark is still `M2: spawn returned`. The
fn-value ABI batch (m263-m265) fixed the marshal half (verified via the
bindings probes) but the runtime entrypoint needs its own fix. Evidence
re-filed as `REL-20261012-1402-xvector`; the G phase stays gated.

## Result on v0.64.5 (2026-10-15): GREEN -- the gate is CLOSED

Both stacked fixes are in the archive (compiler m282 `d6690868` env-cast
half + stdlib wave-131 spawn-buffer hoist and wave-139 trampoline i64
store, via stdlib-v0.64.5 `092dfa0`), and the acceptance passes on
**Windows AND WSL**:

- `probe.xi` builds green and exits **0** -- all three checks PASS:
  3 workers return exact sums through `JoinHandle.join`; a worker's
  `current_thread_id()` differs from the main thread's id (real OS
  thread, not inline simulation); `available_parallelism() >= 1`.
- `probe_marks.xi` exits 0; the marks file's last line is
  **`M3: join ok 42`** (was `M2: spawn returned` + AV).
- Evidence refs: archive tag `v0.64.5` (`84f761c5`, run 38792051847);
  bus items `REL-20261011-1627-xvector` / `REL-20261012-1402-xvector`
  (acceptance GREEN; closure held until the next full-green archive pass
  -- the v0.64.5 pass carries the unrelated XVC-C-16 linux service
  regression).

This unblocks the G phase per `docs/G-PHASE-PLAN.md`: G-1 (thread + sync
smoke; promote this acceptance into `tests/probes/` + both batteries) is
the next G slice.

## Acceptance (exit 0)

- 3 workers return exact distinct sums through `JoinHandle.join`;
- a worker's `current_thread_id()` differs from the main thread's id
  (real OS thread, not inline simulation);
- `available_parallelism() >= 1`.

## Re-run trigger

CLOSED at v0.64.5 (2026-10-15) -- see the GREEN section above. Kept as a
regression gate: re-run at every archive install (it gates the G phase
and the stdlib's `xiom.thread.spawn` simulation flip). Promote to
`tests/probes/` + both batteries in the G-1 slice.

## Files

- `probe.xi` -- the acceptance probe (exit = failed checks; compiles
  green, AVs at run on v0.64.3; bus witness
  `REL-20261011-1627-xvector`).
- `probe_marks.xi` -- forensics variant writing
  `out/thread_abi_mark.txt` (last mark: `M2: spawn returned`).
