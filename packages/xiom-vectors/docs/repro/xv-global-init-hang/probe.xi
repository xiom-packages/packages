// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XVC-C-19 repro candidate: module-level `var` initializers that CALL a
// function (or allocate a Vec) hang the compiler on v0.64.7 (no output,
// no exit; >2 minutes for a 15-line file; the watchdog kills it).
//
// Witnesses (all hung on v0.64.7 Windows, 2026-10-18):
//   A. var G_CH: channel.Channel[Int] = channel.channel_new[Int](4);
//   B. var G_V: Vec[Int] = Vec[Int].new();  (+ a non-generic call global)
//   C. the same channel-call shape COMPILED fine inside the much larger
//      probe_thread_sync module (v0.64.7) -- shape-sensitive, which is why
//      the lane's probe uses scalar-only globals today.
// Expected: the compiler exits 0 and the binary prints "main started".
// Run:
//   .\scripts\build.ps1 docs\repro\xv-global-init-hang\probe.xi -Name repro_global_init_hang
//   .\out\repro_global_init_hang.exe
// On v0.64.7 the build step hangs; kill it (the watchdog exits 124 after
// its timeout).

module repro_global_init_hang

use xiom.sync.channel;
use xiom.sync.mutex;
use xiom.io;

// Null-only literal (safe on v0.64.7).
var G_M: mutex.SyncMutex = mutex.SyncMutex{ locked: null };
// Allocating initializer (witness B).
var G_V: Vec[Int] = Vec[Int].new();
// Function-call initializer (witness A).
var G_CH: channel.Channel[Int] = channel.channel_new[Int](4);

fn five() -> Int { return 5; }
// Non-generic call initializer.
var G_CALL: Int = five();

fn main() -> Int {
  io.println("main started");
  G_V.push(7);
  io.println("vec global ok");
  return G_CALL - 5;
}
