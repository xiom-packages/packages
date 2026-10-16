# xiom.v4l -- docs/repro

Everything in `xiom.v4l`'s declared surface is reproduced from the pinned
upstream text by the tooling in this directory.  Nothing here is a runtime
dependency of the package; it is the evidence chain.

## Contents

```
gen-v4l2-consts.ps1        the generator: pinned headers -> src/*.xi modules,
                           raw dump, coverage table, 3107-assert gate
uapi-shim/linux/compiler.h 3-line parse overlay (headers_install-equivalent;
                           the pin's videodev2.h includes <linux/compiler.h>,
                           absent from the UAPI tree at v6.19 -- see PROVENANCE)
v4l2_abi_probe.c           Linux probe: compiles the bridge + the generated
                           assert gate against the REAL pinned headers, then
                           runs the runtime ABI self-check + classification
run-linux-abi-probe.sh     build + run the probe (WSL/CI/Pi recipe)
gen/v4l2_consts_dump.txt    recorded evidence: every evaluated fact (3105 lines)
gen/v4l2_const_asserts.h    generated gate: 3107 _Static_asserts (committed;
                           compiled by the probe build)
gen/v4l2_coverage.tsv       family/count coverage table (feeds SPEC.md)
gen/v4l2_values_dumper.c    the generated dumper source (may be re-emitted)
gen/v4l2-linux-abi-probe.txt recorded probe run (ABI green, /dev ABSENT -> SKIP)
```

## Prereqs

- The pinned light clone at `E:\repos\linux-uapi-v6.19` (clone command in
  PROVENANCE.md; a plain `gcc` + the same sparse set works on any Linux).
- WSL (`Ubuntu`) with gcc for the generator and the Linux probe
  (the suite itself is built by the XIOM toolchain and needs no gcc here --
  port.ps1's `--c-source` uses the toolchain's clang).

## Regenerate everything

```powershell
pwsh packages/xiom-v4l/docs/repro/gen-v4l2-consts.ps1
# rewrites src/consts.xi, src/cids.xi, src/layout.xi and gen/* (dump,
# asserts, coverage, dumper); throws if a name cannot be placed -- the
# 100%-coverage gate.
```

## Linux ABI gate (real pinned headers)

```bash
bash packages/xiom-v4l/docs/repro/run-linux-abi-probe.sh \
     packages/xiom-v4l [ /mnt/e/repos/linux-uapi-v6.19 ]
```

Compiles the bridge with `-DXV_USE_REAL_UAPI` (pulls the pinned UAPI
headers + the 3107-assert gate), runs the runtime ABI self-check and the
probe classification, and records the output.  On a host without
`/dev/videoN` the recorded classification is the ABSENT (SKIP) leg; the
same script on a Pi with a camera exercises the live leg at probe time.

## Notes

- The generator needs `git` + `wsl`; paths are overridable via its
  `-KernelTree` / `-Distro` parameters.
- The dump is the raw `gcc` output; the assert gate is what makes drift
  fail a build.  Both are committed so reviewers can check values without
  re-running anything.
