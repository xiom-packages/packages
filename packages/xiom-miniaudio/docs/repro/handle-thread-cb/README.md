# handle-thread-cb -- foreign-thread callback ABI probe (0.5.0 gate)

Proves the 0.5.0 handle-surface design assumption before shipping it: a
**bare top-level XIOM fn name** handed to C through a `fn`-typed extern
parameter and **invoked from a C thread other than the XIOM main thread**
(the miniaudio audio-thread shape) runs correctly -- marker writes into the
C-owned buffer land, module-level counters advance, and it stays clean while
the main thread concurrently executes XIOM code (the engine's
game-logic-on-main-thread / render-on-audio-thread model).

Shapes exercised (`cbthread.c`):

1. `xtc_set(f)`: store the XIOM render callback (the direct-handoff shape).
2. `xtc_start()`: spawn a worker thread that calls the callback on a 64-byte
   buffer and counts a **hit** when the handler wrote `buf[0]=0xAB`-family
   markers `171` / `205` at offsets 0 / 63 (an offset write -- the B-17
   discipline: Int-address math + byte writes).
3. arm 1: main thread sits in C (`xtc_burn`) while the worker calls back.
4. arm 2: worker runs concurrently with main-thread XIOM execution (a local
   fn + extern calls interleaved) -- the overlap check.

## Run

```
. scripts\xiom.ps1
$tool = Resolve-XiomToolchain; $env:XIOM_STDLIB = $tool.Stdlib
& $tool.Xiom --run <abs>\probe_xthread.xi --c-source <abs>\cbthread.c
```

(Pass absolute paths; `--c-source` links from a scratch cwd.)

## Results (2026-10-17, pre-ship gate for xiom.miniaudio 0.5.0)

| Slot | arm 1 | arm 2 | Verdict |
|------|-------|-------|---------|
| v0.64.5 pin (`xiom.new.0645`) | `calls=20 hits=20 xiom_seq=20 frames=16` | `acc=265100 calls=9 hits=9 xiom_delta=9` | **PASS** |
| v0.64.6 slot (`xiom.new`) | `calls=21 hits=21 xiom_seq=21 frames=16` | `acc=265100 calls=7 hits=7 xiom_delta=7` | **PASS** |

(`frames=16` = the frame-count argument marshalled C -> XIOM intact; the
per-run call counts vary with wall-clock pacing.)

Shipped consequence: `ma_device_handle_set_render` hands an env-free
top-level `fn(*UInt8, Int32) -> Unit` to the bridge once; the C trampoline
invokes it on the device thread (null-backend battery: ~10 ms cadence) and
verifies the two marker bytes the suite's renders write, so "the render's
writes landed" is counted (`marked`) rather than assumed. See
`AUDIT.md` (Design notes) and `PROVENANCE.md` (section 4).
