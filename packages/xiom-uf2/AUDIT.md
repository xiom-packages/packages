# xiom.uf2 -- Lane audit (build, evidence)

> Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
> SPDX-License-Identifier: MIT OR Apache-2.0

Toolchain: compiler pin **v0.64.7**
(`E:\xiom-lang\xiom\target\release\xiom.exe`, `COMPILER_VERSION` v0.64.7),
stdlib `E:\xiom-lang\stdlib`, worktree
`feat-uf2-2` (Agent Manager `feat-uf2-2-0c0839062914ac13`), branch base
`origin/bindings` @ `5eaf3d0d`.  Date: 2026-10-19.  The mission's first
step was `git fetch origin` and restart from `origin/bindings`; the branch
was reset to that tip before any package file was written.

## 1. Upstream oracle

- Light clone: `git clone --depth 1 https://github.com/microsoft/uf2 E:\repos\uf2`.
- Pin: `90e9741f217f5a40c98ba74d663e408041037578` (2026-02-08).
- License verified first: `LICENSE.txt`, MIT, Microsoft Corporation.
- Consulted: `uf2.h` (layout/magics/flags), `README.md` (block semantics,
  payload sizes, family rules), `utils/uf2conv.py` (256-byte default,
  `is_uf2`, family flag), `utils/uf2families.json` (family IDs).
- No code, no fixtures, no runtime data copied.  Table + citations in
  `PROVENANCE.md`; contract in `SPEC.md`.

## 2. Pre-implementation probes

The host-side format leg needs no ABI probes: it is pure byte arithmetic
over `Vec[UInt8]` and the stdlib `xiom.serialize.endian` helpers.  The
flash leg was prototyped against the stdlib filesystem surface:

| Probe | Result |
|---|---|
| `fs_size` + `fs_read_range` on a binary UF2 fixture | roundtrip exact (no text translation) |
| `fs_write` + `fs_size` + `fs_read_range` read-back | exact byte match; the path used by the flash verification |
| `fs_copy` on binary data | **not used** -- stdlib `fs_copy` delegates to `io.read_file`/`io.write_file` (text mode), so the package uses `fs_write` (binary `wb`) instead |
| `io.create_dir` / `io.remove_dir` / `fs_temp_dir` | temp "mount" setup/cleanup green |
| `io.time_now` / `io.sleep` | completion-wait timing used by `uf2_flash_wait_complete` |

## 3. Suite evidence

Command:

```
.\scripts\port.ps1 -Package xiom.uf2 -TimeoutSec 300
```

Result: **62 passed / 0 failed / program exit 0**, twice (x2) on v0.64.7.
`STATUS.json` records the tested commit.  Coverage map:
`docs/COVERAGE.md`.

Highlights:

- block golden asserts every header offset, the zero padding and the end
  magic byte-exactly;
- 700-byte payload -> 3 blocks -> exact payload/address roundtrip;
- 476-byte chunking -> 476 + 224, last-block remainder preserved;
- every rejection class (size/magic/payload/index/flags/family/arg/verify)
  has at least one named check;
- out-of-order file blocks are accepted and normalized by block number;
- comment (NOFLASH) and file-container images are parsed with the right
  payload/contiguity behavior;
- flash SKIP (absent mount), IO/SIZE/MAGIC source failures, a real binary
  copy to a temp "mount" with read-back verification, and both completion
  states (COMPLETE for a vanished dest, COPIED for a still-mounted volume).

## 4. Compiler notes

- The module compiles as a library with `xiom --emit-ir src/uf2.xi`
  (exit 0) and as the suite with `--run`.
- No `unsafe` blocks; no FFI; no platform libraries.  All I/O goes through
  the stdlib (`xiom.io`, `xiom.io.fs`).
- Str comparisons go through `string.compare.str_compare`; byte reads that
  enter Int arithmetic are masked with `& 255`; locals are initialized.
- `Vec[UInt8]` indexing and `Vec[Int].with_len(n)` are used for the
  seen/order arrays; no tuple or struct-vector patterns that trip the older
  compiler findings.

## 5. Deliberate limits

Documented in `SPEC.md` sec. 9: last-block payload is the actual remainder
(upstream converter declares 256), reserved flag bits are rejected,
mixed-family files are rejected, MD5/extension tags are decoded but not
verified/parsed, no volume auto-discovery and no picotool orchestration in
0.1.0.
