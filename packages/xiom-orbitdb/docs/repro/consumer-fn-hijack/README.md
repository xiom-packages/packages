<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# C-ORBIT-07 repro: a consumer-defined function silently hijacks a module's private same-named call

**Compiler:** v0.64.3 (Windows shadow `%LOCALAPPDATA%\xiom.new.0643\bin\xiom.exe`; WSL `~/.local/bin/xiom`).
**Found by:** the ORBITDB M2.1 fault probe (`tests/probes/probe_fault_sync.xi`,
2026-10-11). The probe defined a helper `arm(Str,Str,Str)` while the imported
`xiom.db.storage.fault` module has a module-private zero-arg `arm()`; calls
inside `fault.xi` (`fault_armed()`, `fault_gate()`) silently invoked the
probe's function with empty-string arguments, which tripped a contract panic
in `env.cstr` (`ensures` at `os/env.xi:29:13`) on `set_var(name, "")`.

## Files

- `mod_svc.xi` -- a service module with a module-PRIVATE zero-arg `arm()`
  that its public `ping()` calls unqualified.
- `probe_hijack.xi` -- consumer module that defines its own
  `arm(Str,Str,Str)` and calls `mod_svc.ping()`.
- `probe_clean.xi` -- control: identical consumer WITHOUT the `arm`
  definition.

## Commands and observed results (v0.64.3, Windows + WSL identical)

```
scripts\run.ps1 docs\repro\consumer-fn-hijack\probe_hijack.xi
  probe: consumer arm(a=[] b=[] c=[])     # expected: svc: private arm() ran
  done
  exit code: 0                            # no error, no warning

scripts\run.ps1 docs\repro\consumer-fn-hijack\probe_clean.xi
  svc: private arm() ran                  # control: correct resolution
  done
  exit code: 0
```

`xiom --check` passes on both files; the misresolution is silent and
surfaces only at run time (here as wrong output; in the ORBITDB probe as a
contract panic, because the hijacked call passed empty strings into
`env.set_var`).

## Mechanism

`mod_svc.call_arm`-style references are compiled as an unqualified call to
`arm`. When the program also contains a function named `arm` (any module,
here the consumer), the call inside the service module binds to the
consumer's definition: the zero-arg call site reaches the 3-arg function
with missing arguments materialized as empty values. No ambiguity
diagnostic is emitted. Same family as the m225 consumer-scope caveat
(C-ORBIT-04 residual note), extended from enum variants / types to
functions.

## Impact

Any module that keeps a private helper whose name collides with a function
in any other module of the program can be silently redirected; in the
ORBITDB case it turned into a synchronous contract panic deep in the
stdlib. A consumer lane cannot see this standalone -- it only appears when
the composing program happens to use the same name.

## Workaround (applied)

Keep consumer helper names distinct from helpers inside imported modules
(ORBITDB renamed the probe helper to `probe_arm`; suite green x2 Win + WSL
afterwards). There is no way to module-qualify an intra-module call as a
defense inside the service module.

## Suggested fix

Prefer the declaring module's own function for unqualified calls (mirror
the m225 fix direction), and emit an ambiguity diagnostic when a
same-named function exists in another module of the program.

## Verdict on v0.64.4 (2026-10-12): FIXED

- `probe_hijack.xi` now prints `svc: private arm() ran` + `done`, rc 0 (the
  consumer's `arm` no longer hijacks).
- `probe_clean.xi` unchanged green.
- NEW `probe_shadow.xi` -- the consumer defines an EXACT same-signature
  zero-arg `arm()`; still `svc: private arm() ran`, rc 0 (the strongest
  variant).
- All three x2 Win + x2 WSL on the official artifacts (Win zip sha256
  `44a41aea...`, WSL linux sha256 `d0a43a5c...`).
- The `probe_arm` workaround in `probe_fault_sync.xi` is REVERTED: the probe
  runs the original collision shape (`arm` + fault.xi's private `arm()`) and
  is GREEN x2 Win + WSL.
- Bus: `REL-20261011-1124-orbitdb` verified + closed (fix ref m261/m262,
  commit 677d65a7).
