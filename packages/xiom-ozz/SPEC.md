# SPEC: xiom.ozz -- Ozz-Animation bindings (vendored C++ amalgamations)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.ozz` |
| Version | 0.2.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | ozz-animation -- https://github.com/guillaumeblanc/ozz-animation |
| Upstream version pinned | tag **0.16.0** (0.17.0 is the next re-pin candidate) |
| Upstream license | MIT (`vendor/LICENSE.md`) |
| Package license | MIT OR Apache-2.0 (everything outside `vendor/`) |
| Platform | Windows x64 (no platform-specific XIOM code) |
| Compiler pin | v0.64.1 |

## 2. Vendored path (G2 pin)

Ozz is a C++ library with no C API, and the xiom link line has **no
include-path passthrough**, so the upstream sources cannot be passed as
individual `--c-source` entries (their `#include "ozz/..."` /
`"animation/..."` paths need `-I`). The package therefore vendors two
**generated translation units** produced with the upstream-style
`combine.py` bundler (roots `include/` + `src/`):

- `vendor/ozz_all.cpp` -- base + math + animation runtime + offline skeleton
  builder concatenated with all quoted includes inlined (one TU).
- `vendor/ozz_bridge.cpp` -- our `extern "C"` bridge with the ozz headers it
  needs inlined (one TU). Bridge source template documented below.

Both are compiled with `--c-source` (port.args.json); no system library, no
separate build step, no SDK. The two generator inputs are vendored as
reviewable sources: `src/ozz-in.cpp` (library entry list) and
`src/ozz-bridge-in.cpp` (our `extern "C"` bridge).

| File | Bytes | SHA256 |
|------|-------|--------|
| `vendor/ozz_all.cpp` | 719,987 | `24117B0FBBAA5E1221C2F8FBEE9CB6A79EB42E28179A29CD5DE75E392C751457` |
| `vendor/ozz_bridge.cpp` | 380,622 | `0D2BA8800CADD74381ED907C8A9A35687A18EE014BA54C5D8D9DFFFFCCD6CA76` |
| `vendor/LICENSE.md` | 1,183 | `3DDD93E9888FE70B9D61675CEB1C4278A579DC67171678F015DE114EFE815852` |

### Archive provenance

| Artifact | Value |
|----------|-------|
| Download | https://github.com/guillaumeblanc/ozz-animation/archive/refs/tags/0.16.0.tar.gz |
| Size / SHA256 | 37,101,794 bytes / `A7A34322344E9D839EAF637BBC463404C6AED3F52583DEA95C856FEA580C2693` |

### Generation procedure (re-pin)

1. Download the new tag archive; verify the SHA256.
2. Build an entry template listing the library sources in dependency order
   (base: memory/allocator, platform, log, containers/string_archive,
   encode/group_varint, io/archive, io/stream, maths/{simd_math,
   math_archive, simd_math_archive, soa_math_archive, box}; runtime: the 13
   `animation/runtime/*.cc`; offline: raw_skeleton.cc, skeleton_builder.cc).
3. Run `python combine.py -r include -r src -o ozz_all.cpp <template>`;
   generate the bridge TU the same way from `src/ozz-bridge-in.cpp`.
4. Normalize CRLF -> LF (Windows Python writes CRLF), update the hash table
   and version rows, re-run `scripts/port.ps1 -Package xiom.ozz` (x2).

`.gitattributes` pins `vendor/** -text`.

## 3. Design and safe boundary (G5)

`ozz.xi` is the only module with `extern "C"`; wrappers are `ozz_math_ok`,
`ozz_skeleton_ok`, `ozz_local_to_model_ok`, `ozz_probe` (aggregate
`Result[Unit, Str]`), plus `OZZ_NO_PARENT`. The C bridge (`extern "C"`)
provides `ozz_probe_math`, `ozz_probe_skeleton`, `ozz_probe_local_to_model`,
`ozz_probe_all` and is compiled inside `vendor/ozz_bridge.cpp`.

Wrapper-name note: a wrapper named like its extern self-recurses (the lzfse
lesson); public names use `_ok` suffixes.

## 4. Test matrix (recorded 2026-10-08, compiler v0.64.1)

| Configuration | Command | Result |
|---------------|---------|--------|
| Vendored amalgamations | `scripts/port.ps1 -Package xiom.ozz` | **PASS 4/4 x2** -- math (dot/cross + 90-degree axis rotation), offline RawSkeleton -> runtime Skeleton (2 joints, parents -1/0), LocalToModelJob (child at (0,1,0) in model space), aggregate green |

No SKIP path exists (the library is compiled in). The two TUs compile in a
few seconds each at the link line's default optimization.

## 5. Scope

Pilot: proves the vendored C++ path end-to-end with real runtime objects
(offline builder -> runtime skeleton -> model-space job). Animation clip
building/sampling with assets, blending jobs, IK jobs, tracks and archive
I/O are Phase 2 (`ROADMAP.md`). The pre-pilot files declared a C bridge that
was never present and are preserved in git history.
