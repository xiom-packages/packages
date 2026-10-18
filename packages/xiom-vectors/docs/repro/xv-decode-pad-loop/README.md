<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# XVC-C-10 -- `hnsw_decode` segfaults on large pad volume (inline loop)

**Status: FIXED on compiler v0.64.2** (2026-10-09 re-test: the pre-fix shape
in `probe.xi` no longer segfaults; decode returns cleanly, exit 0). Found
2026-10-08 on v0.64.1 by the XVECTOR fuzz probe; kept as a regression repro.
The lane keeps the `pad_adj_slots` function boundary and the strict-decode
bounds (the bounds are strictness, not a workaround).

**Maintenance 2026-10-12 (v0.64.4):** the probe's imports were refreshed to
`use xiom.vectors;` -- the pre-swap `xiom.vector.types.*` paths died in the
60th-pass package swap, and v0.64.4 makes unresolved imports hard errors
(m266). Re-run on v0.64.4: exit 0.

## Summary

The deterministic fuzz probe (`tests/probes/probe_fuzz_codecs.xi`) crashed
while decoding a mutated graph-codec stream. Isolation showed the trigger is
the **pad step inside `hnsw_decode`**: after decoding each layer row, the
function pushed `m - degree` zero slots into `g.adj` with an inline
`while pad < m` loop. With a header `m` in the hundreds (512 was enough; the
mutated fuzz case hit 7422) decode segfaulted **inside the function**, on
both Windows and WSL, even when the input was otherwise a pristine valid
stream and even when a trailing-junk word forced a `None` return *after* the
pushes (so it is not the struct-return path).

Control experiments (all green): a standalone `Vec[Int]` push loop of
712,000 zeros; the same pad-loop shape alone (nested loops, runtime bound,
96,000 pushes); interleaved pushes into two `Vec` fields of one struct. The
crash only appears for the pad loop **inside `hnsw_decode`'s body** -- the
same context-sensitive lowering family as XVC-C-08/C-09.

## Workaround (adopted)

1. Move the pad step behind a function boundary:
   `pad_adj_slots(g, m - dg)` (see `src/index/hnsw.xi`). Verified: decode
   with `m=512` returns cleanly (`Some` for a pristine stream, `None` with
   trailing junk).
2. Strict-decode bounds: `m > 512` or `count > words.len()` -> `None`
   (512 matches the sanctioned `AnnParams` max graph degree).

## Repro (revision-pinned)

`probe.xi` encodes a 12-node graph, sets `m = 512` (and, since the 2026-10-11
P-a codec revision, the level-0 cap word `m0 = 1024` -- codec v3), appends a
junk word and decodes:

```powershell
. .\scripts\dev-env.ps1
.\scripts\build.ps1 docs\repro\xv-decode-pad-loop\probe.xi -Name padloop
.\out\padloop.exe        # pre-fix: segfault after "decode start"; post-fix: exit 0
```

- **Pre-fix shape (inline `while pad < m` in `hnsw_decode`)**: v0.64.1
  segfaulted (`0xC0000005`) after "decode start"; on v0.64.2 the same shape
  in `probe.xi` returns cleanly (exit 0) -- the compiler fix landed (loop
  temporaries no longer reserve stack per iteration).
- **Post-fix**: exits 0 with "decode -> None (correct: trailing junk)".

## Impact

Silent crash on malformed graph-codec input (and potentially on very large
legitimate graphs at decode time). Any decoder loop that pushes a large,
`m`-dependent number of slots inline is a candidate shape.

## Notes

- The fuzz probe is the general gate: it exercises random/mutated/truncated
  streams against `payload_decode`, `hnsw_decode` and WAL replay on every
  build.
- WSL behaves like Windows here (crash reproduced on both).
