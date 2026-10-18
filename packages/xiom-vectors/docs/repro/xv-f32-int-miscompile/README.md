<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->


Status: **FIXED in v0.64.1** (2026-10-08 re-test): Windows 3/3 and WSL 9/9 fresh builds exact, including --sequential.

**Maintenance 2026-10-12 (v0.64.4):** the probe and the six diagnostic
copies had their imports refreshed to `use xiom.vectors;` -- the pre-swap
`xiom.vector.types.*` paths died in the 60th-pass package swap, and v0.64.4
makes unresolved imports hard errors (m266). Re-run on v0.64.4:
`probe_failing.xi` exits 0.

# XVC-C-05 repro: Float32 ops lowered as integer bit-pattern arithmetic

Compiler: **v0.64.0**. In `probe_failing.xi` (imports `xiom.vector.engine` via
`xiom.toml` source-roots), `vector_dot` over `Vec[Float32]` computes INTEGER
multiplication of the IEEE-754 bit patterns and reinterprets the result as a
float. No diagnostic.

Observed on a red build (`diag` lines printed by the probe):

```
diag p2 bits=4742205965124763648,4741980785148428288,0    # 1063675494.0, ... : the INTEGER of 0x3F666666 (f32 0.9)
diag p2 dot=4877244244697284608                           # 1.13319008125164e+18
diag local dot=4877244244697284608
diag before len=2 id0=1 id1=2 d0_bits=0 d1_bits=4598786180790616064
```

Decode:
- `4742205965124763648` is the double of `1063675494`; `1063675494 = 0x3F666666`
  is the **f32 bit pattern of 0.9**.
- `4877244244697284608` (dot) is the double of `1063675494 x 1065353216`;
  `1065353216 = 0x3F800000` is the **f32 bit pattern of 1.0**.
- The search distance `0.283915...` follows from those integer products.

Platform matrix (same logical program; observed 2026-10-08, v0.64.0):

| Platform / flag | Observations (`diag p2 dot` bits) |
|---|---|
| Windows default, batch 1 | red, green, green (comment-renumbered bytes) |
| Windows default, batch 2 (earlier bytes) | red, green, red |
| Windows `--sequential` (earlier bytes) | green, green, green |
| Windows `--sequential` (later bytes) | red, green, red |
| WSL Ubuntu default (earlier bytes) | red, red, red |
| WSL Ubuntu default (later bytes, comment-only change) | green, green, green |
| WSL Ubuntu `--sequential` (later bytes) | red, red, red |

Correct = `4606281698659794944` (0.9); red = `4877244244697284608`
(1.13319008125164e+18 = integer product of the f32 bit patterns).

Conclusion: **correctness flips per compilation build; no flag or byte-stability
rule predicts it.** Irrelevant byte changes (a comment in a *different* file
region, the module name) flip it in both directions. Green controls (same
engine module calls, smaller units): `evidence_debug_cosine.xi`,
`evidence_debug_copy.xi`, `evidence_bisect_a/b/c.xi`,
`evidence_debug_search.xi` -- all exit 0 with the correct bits.
`control_selfcontained_min.xi` (no engine import) is green. The 136-check
suite compiled green 5/5.

Mitigation: treat a red numeric check as a build rejection. Every evidence
build must run its own numeric assertions (the suite and the critical probe
do); rebuild and re-verify rather than trusting a binary. `--sequential` is
an A/B diagnostic switch, not a fix.

Reproduce (Windows, 3x -- expect at least one red):

```powershell
. .\scripts\dev-env.ps1
1..3 | % { & $env:XIOM_COMPILER -o "out\pf$_.exe" docs\repro\xv-f32-int-miscompile\probe_failing.xi; & "out\pf$_.exe" | Select-String "diag p2 dot" }
# workaround A/B:
& $env:XIOM_COMPILER --sequential -o out\pf_seq.exe docs\repro\xv-f32-int-miscompile\probe_failing.xi
& out\pf_seq.exe
```

WSL matrix (repeatable helper, prints the per-build bits):

```bash
cd /mnt/e/xiom-projects/xiom-xvector
bash docs/repro/xv-f32-int-miscompile/linux_matrix.sh 3
```
