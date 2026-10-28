# C-ORBIT-13 -- `&mut` on a >=3-level nested field path copies scalar state

**Found:** 2026-10-19 while landing M1.1b (paged NodeStore in ORBITDB).

## Shape

```
pub type H  = { g: Int; }
pub type BS = { n: Int; h: H; v: Vec[Int]; }
pub type NS = { bs: BS; }
pub type T  = { store: NS; }

fn bump(x: &mut BS) { x.n = x.n + 1; x.h.g = x.h.g + 10; x.v[0] = x.v[0] + 1; }
fn flush(t: &mut T) { bump(&mut t.store.bs); }   // 3-level path
```

`bump(&mut t.store.bs)` compiles but operates on a COPY of the field:

- `n` (Int) and `h` (nested struct) keep their old values in `t`;
- `v[0]` DOES change in `t` (Vec buffers are shared);
- a two-level control (`bump(&mut t.bs)` where `T = { bs }`) updates everything.

Direct assignment (`t.store.bs.n = 7`) and local-copy-then-write-back
(`var bsw = t.store.bs; ...; t.store.bs = bsw`) both work.

## Repro

`repro.xi` (same directory). Commands:

```
# Windows (lane pin v0.64.7, exe sha 592aa125...)
%LOCALAPPDATA%\xiom.new-20261018-1415\bin\xiom.exe --run repro.xi -o repro.exe
# WSL lane pin v0.64.7 (bin sha 302d3192...)
~/.local/share/xiom-0.64.7/bin/xiom --run repro.xi -o repro.exe
```

Expected (both platforms):

```
two-level: n=2 g=10 v=1
two-level: PASS
three-level: n=2 g=10 v=1
three-level: PASS
workaround: n=2 g=10 v=1
workaround: PASS
exit 0
```

Observed on v0.64.7 Windows (2026-10-19):

```
two-level: n=2 g=10 v=1
two-level: PASS
three-level: n=1 g=0 v=1
three-level: FAIL
workaround: n=2 g=10 v=1
workaround: PASS
exit 0 (defect reproduced: the repro returns 0 when the three-level case fails and the two-level/workaround controls pass)
```

## ORBITDB impact and fallback

`snap_flush_v2`'s paged branch spills/commits through `&mut tree.store.bs`
(NodeStore -> BlockStore, 3 levels). The file writes happened at a stale
`block_count` (each call got a fresh copy) and the committed header never
updated the pager's handle: the checkpoint returned success, but only the
last spilled page survived and replayed keys were lost on reopen
(suite typed_mvcc 14/15). Fallback: copy the BlockStore to a local, call
`block_store_put`/`block_store_commit` on the local, then
`tree.store.bs = bsw` (verified green: suite 160/160 x2 Win, keys 1..8 after
the second checkpoint). The workaround stays until the compiler fix ships.

## Resolution (v0.64.8, 2026-10-19)

Fixed on the released v0.64.8 archive (tag `4d040604b`): the three-level
case prints `n=2 g=10 v=1` / `PASS` on Windows and WSL, and the repro now
returns 0 only when all three cases pass. ORBITDB restored the natural
nested `&mut tree.store.bs` checkpoint and `ns_release_pending(&mut
db.tree.store)` call; the helper workarounds were removed. The relay item
`REL-20261019-1209-orbitdb` is verified + closed.

## Compiler-side notes

The failure is specific to taking `&mut` of a path with three or more
struct-field segments; two segments are fine. Vec element writes leaking
through indicates the copy shares the Vec buffers while Int/nested-struct
fields are copied. No warning is emitted.
