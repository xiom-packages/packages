<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xv-global-init-hang -- compiler hang on module-level initializers (v0.64.7)

**Symptom:** compiling a minimal module whose module-level `var`s have
function-call / allocating initializers HANGS the v0.64.7 compiler (no
output, no exit; >2 minutes for a 15-line file). `build.ps1`'s watchdog
would kill it (exit 124); the shell runs left orphaned `xiom` processes
that had to be killed manually.

**Witnesses (v0.64.7 Windows, 2026-10-18):**

- A: `var G_CH: channel.Channel[Int] = channel.channel_new[Int](4);`
- B: `var G_V: Vec[Int] = Vec[Int].new();` plus a non-generic call
  initializer (`var G_CALL: Int = five();`)
- C: the same channel-call shape COMPILED fine inside the much larger
  `tests/probes/probe_thread_sync.xi` module (which also carries many
  functions and imports) -- shape-sensitive, so the minimal witness and
  the larger module disagree.

**Consequence found in the lane:** the natural cross-thread channel
pattern (a module-level `Channel[Int]`) is unusable: a function-call
global initializer hangs the compiler, and the version that DID build
(the larger probe module) hung at process startup before `main` (the
global initializer appears to run before the runtime/heap is ready).
The lane's G-1 probe now uses scalar-only globals (a single-slot mailbox
under the shared spinlock) and keeps the channel's same-thread contract
checks; the channel's cross-thread leg waits on a handle form (stdlib
wishlist filed).

**Expected:** build exit 0; `main started` / `vec global ok`; exit 0.

**Run:**

```
.\scripts\build.ps1 docs\repro\xv-global-init-hang\probe.xi -Name repro_global_init_hang
.\out\repro_global_init_hang.exe
```

On v0.64.7 the build hangs; kill the orphaned `xiom` process if the
watchdog is bypassed.
