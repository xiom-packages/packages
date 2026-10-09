# BINDINGS-SESSION -- xiom-packages bindings lane

Handoff file for the native session. Read the relay block first; the ledger
below records evidence and open asks.

**STATUS: BATCH 23 RELAYED (merge-ready)** -- `xiom.box2d` 0.2.0 (vendored
v3.1.1 C; 5/5 x2) and `xiom.imgui` 0.2.0 (vendored v1.92.9b headless; 4/4
x2); `xiom.jolt` is pinned + generator-validated but blocked on a link-line
C++ standard passthrough (ask relayed); batches 21+22 are PUBLISHED
(`eco-v0.1.122`). Nothing else pending in-lane.

## Relay (bindings -> native, per BINDINGS-LANE.md §6)

```
BINDINGS BATCH 23: head=2b3f4a66 + this handoff commit; packages=xiom.box2d 0.2.0 +
xiom.imgui 0.2.0; tests=box2d 5/5 x2 (vendored Box2D v3.1.1 C API via flat multi-source,
integer bridge: version 3.1.1, gravity (0,-10000) milli, resting drop settles at 499 milli
on a ground top at 0, impulse vx=5000 milli, drop determinism) and imgui 4/4 x2 (vendored
ImGui v1.92.9b core + upstream null backends; headless two-frame probe: version
1.92.9b/19291, steady frame 76 vtx/240 idx/1 cmd, empty frame 0, determinism);
licenses=MIT vendored (box2d + imgui only) + package MIT OR Apache-2.0;
pins=box2d v3.1.1 tarball sha256 FB6EF914... + per-file table (SPEC 2); imgui v1.92.9b
tarball sha256 21D8A0A5... + per-file table; gate=G0..G5 OK; needs=NONE (both
grandfathered/allowlisted); port.args.json present (flat multi-source; no -I, no generator).
BLOCKED ASK -- xiom.jolt v5.6.0 (pin 6E069EE0..., generator emits 25 per-directory TUs
with angle->quote include rewriting; the full library compiles under -std=c++17): the xiom
link line passes no standard flag and clang 22 defaults to C++14 (verified in
crates/xiom/src/lib.rs + a live probe), so C++17 libraries cannot build via --c-source.
Request: a --cxx-standard passthrough (or a default-standard bump). No jolt
module/tests committed until unblocked; the validated generator is staged at
packages/xiom-jolt/tools/combine.py.
```

```
BINDINGS BATCH 22: head=4e4d556a + this handoff commit; packages=xiom.sqlite 0.3.0
(B-01 workaround RETIRED: `SqliteValue` wraps the restored user enum `SqliteValueKind`
with payloads; same constructors/accessors for callers; obsolete `VALUE_*` constants
removed -- public type representation changed); tests=16/16 x6 fresh build cycles (the
B-01 signature was build-dependent; 2/6 bad on v0.64.0/v0.64.1) + full pin matrix x1
19/19 green on the official v0.64.2 (sqlite 16, zstd 8, lzfse 7, ozz 4, miniaudio 4,
sdl3 21, glfw 3, raylib 3, opengl 13, vulkan 10, dxc 3, directx11 5, directx12 5,
libpq 2, odbc 5, portaudio 2, phonon 3, openssl 4, ffmpeg 2); licenses=vendored SQLite
3.53.4 public domain + package MIT OR Apache-2.0 (unchanged); pins=SQLite amalgamation
hashes unchanged (SPEC §2) + compiler pin v0.64.2; gate=G0..G5 OK; needs=NONE
(allowlisted); NO port.args.json change. NOTE: 0.2.0 -> 0.3.0 bump of a live package --
publish is the native lane's call.
```

```
BINDINGS SWEEP v0.64.2: head=224e5c49 + this handoff commit; compiler=v0.64.2 (port.ps1 matrix used
the installed slot %LOCALAPPDATA%\xiom.new; direct probes used the repo-release build
E:\xiom-lang\xiom\target\release; repo pin still v0.64.1 -- native repin pending); matrix=19/19
binding suites green x1 via port.ps1 (sqlite 16, zstd 8, lzfse 7, ozz 4, miniaudio 4, sdl3 21,
glfw 3, raylib 3, opengl 13, vulkan 10, dxc 3, directx11 5, directx12 5, libpq 2, odbc 5,
portaudio 2, phonon 3, openssl 4, ffmpeg 2; absent/SKIP shapes where no DLL is on PATH);
findings=B-01 FIXED (6/6 enum-payload rebuilds all-true, m231; sqlite tagged-struct workaround
droppable once the official archive is installed/pinned), B-08 FIXED (program code 5 now printed
and exits 5, m228; new repro docs/repro/bindings-pilot/run-exit/), B-06 + B-09 still fixed
(up=1 down=1; win32-gl q1/q2 green, real GL 4.6.0), B-05 STILL OPEN (alloc-guard-spin: 10 s
watchdog kill, 8.7 CPU-s, flat 4.5 MB -- runtime side), B-10 STILL OPEN (odbc 3-way scratch
control: f_alloc 5/5 + my_alloc 5/5 green, alloc FAIL -- name-keyed redirect persists; f_ prefix
rule stays); B-02/B-03/B-04/B-07 not re-tested (no live trigger); workarounds kept (B-05, B-10,
sqlite enum until the repin); docs=BINDINGS-COMPILER-FINDINGS.md rows + repro README updated;
needs=NONE.
```

```
BINDINGS BATCH 21: head=224e5c49 + this handoff commit; packages=xiom.ffmpeg 0.2.0 (system-lib
generation loader replacing the pre-pilot 27-static-extern module; native decision BINDINGS-LANE
§11 followed: SKIP path only, nothing vendored); tests=default PATH SKIP 2/2 x2 (skip
classification via bogus sonames + probe SKIP) and Cascadeur 6.0 LGPL set on PATH 4/4 x2
(version FFmpeg 6.0; avcodec 60.3.100 / avformat 60.3.100 / avutil 58.2.100 / swresample 4.10.100;
license 'LGPL version 2.1 or later', gpl-configured false), plus Blender 7.1.1 GPL set 4/4
(second generation exercised; license 'GPL version 2 or later' reported as data, consistency
check) and partial-generation SKIP 2/2 each (OneDrive 8.x no swresample-6; DaVinci 6.x no
swresample-4 -- a generation must resolve all four libraries, never mixed across ABI generations);
licenses=LGPL-2.1+ upstream (nothing vendored or committed) + package MIT OR Apache-2.0;
pins=generation table (8.x 62/62/60/6, 7.x 61/61/59/5, 6.x 60/60/58/4, 5.x 59/59/57/4, 4.x
58/58/56/3) + 7 LGPL-safe entry points (av_version_info, avutil_version,
avcodec_version/configuration/license, avformat_version, swresample_version) + local sample
hashes (Cascadeur set 094CF53C/978F36BF/2FFE865E/43FF1854; Blender avcodec-61 1377146F; OneDrive
avcodec-62 6A194B53; DaVinci avcodec-60 83A94AD3 -- SPEC §3); gate=G0..G5 OK (ABSENT -> SKIP;
ABI/PROBE_FAILED -> FAIL; all unsafe in the single module); needs=NONE (allowlisted + baseline;
namespace-check OK, 0 conflicts); NO port.args.json (pure-XIOM loader).
```

```
BINDINGS BATCH 20: head=80d3e0a0 + this handoff commit; packages=xiom.openssl 0.2.0 (system-lib
multi-soname dynamic loader replacing the pre-pilot static-extern module); tests=default PATH
4/4 x2 (LibreSSL 3.8.2 via C:\Windows\System32\libcrypto.dll: version string, byte-exact
SHA-256("abc") digest check, RAND_bytes(16)) and Git for Windows on PATH 4/4 (OpenSSL 3.2.4,
num 807403584); deterministic SKIP classification per run; licenses=Apache-2.0 (OpenSSL) /
ISC-style (LibreSSL); nothing vendored + package MIT OR Apache-2.0; pins=candidate sonames
(libcrypto-3-x64.dll, libcrypto-1_1-x64.dll, libcrypto-1_1.dll, libcrypto.dll) + entry points
(OpenSSL_version, OpenSSL_version_num, SHA256, RAND_bytes) + local samples (Git 3.2.4 sha256
9C069DEC...; System32 libcrypto.dll sha256 7CEA4AC1...; DaVinci 1.1.1n C4202179...; Python 1.1.1g
594303E2...); gate=G0..G5 OK; needs=NONE (allowlisted + baseline); NO port.args.json.
DECISION RECORD -- openssl: SYSTEM path (OpenSSL source is too large/configuration-heavy to
vendor; libcrypto builds are ubiquitous on Windows; SKIP keeps CI green; present proof is real).
RECOMMENDATION -- ffmpeg (needs native approval before start): (1) LGPL-compatible
configuration ONLY (no GPL codecs, no --enable-gpl); (2) prefer the system-lib SKIP pattern
first (multi-soname avcodec/avformat/avutil/swresample), since ffmpeg DLL sets are rarely on
PATH and vendoring a prebuilt LGPL shared build is the fallback (license text + build config
recorded as the G2 pin); (3) until approved, the crypto/media sector is paused after openssl.
```

```
BINDINGS BATCH 16: head=76bc9556 + this handoff commit; packages=xiom.libpq 0.2.0 (dynamic
loader replacing static-extern stub wrappers); tests=present 4/4 x2 (DaVinci Resolve libpq
13.11 prepended to PATH: PQlibVersion 130011, closed-port connect -> CONNECTION_BAD + error
text 'timeout expired') and absent 2/2 x2 (default PATH: SKIP classification + SKIP probe),
all via scripts/port.ps1 on v0.64.1; licenses=PostgreSQL License (libpq not vendored; nothing
committed) + package MIT OR Apache-2.0; pins=soname libpq.dll + 13-entry-point set
(PQlibVersion/PQconnectdb/PQstatus/PQerrorMessage/PQfinish/PQexec/PQresultStatus/PQntuples/
PQnfields/PQfname/PQgetvalue/PQgetisnull/PQclear) + constants (CONNECTION_OK/BAD, PGRES_*) +
local samples: DaVinci 13.11 sha256 B43D05F89AC004934D8771F21D8BB0F3C80CD5C183221DFA6CB58BAFCE9F621E,
Reallusion 10.7 sha256 7D4A589E45ED04756DE72C8A94932EC94F88B9874E0AE9234AA88467255C002E (SPEC.md §2);
gate=G0..G5 OK (ABSENT -> SKIP; ABI/PROBE_FAILED -> FAIL; all unsafe in the single module);
needs=ALLOWLIST APPEND still pending for xiom.odbc (batch 15) -- xiom.libpq is already
allowlisted; NO port.args.json (pure-XIOM loader).
SECTOR STATUS: data/drivers complete (odbc + libpq). Next per proposal: audio --
xiom.miniaudio (single-header vendored C), then portaudio/phonon.
```

**STATUS: BATCH 19 RELAYED** -- `xiom.phonon` 0.2.0 green on the SKIP path
(3/3 x2); **present path deliberately unexercised** (no `phonon.dll` available
locally -- options recorded in `AUDIT.md`, probe ABI-verified against the
exact v4.8.1 headers and activates automatically when the DLL is on PATH).
**Audio sector COMPLETE** (miniaudio, portaudio, phonon). Awaiting native
merge/verify/publish.

## Relay (bindings -> native, per BINDINGS-LANE.md §6)

```
BINDINGS BATCH 19: head=f70eb9a1 + this handoff commit; packages=xiom.phonon 0.2.0 (dynamic
loader replacing the pre-pilot 125-static-extern module); tests=SKIP path 3/3 x2 via
scripts/port.ps1 on v0.64.1 (default PATH: version/SIMD/status constants, deterministic SKIP
classification via bogus soname, probe SKIP code 126). PRESENT PATH NOT EXERCISED (honest):
no phonon.dll on this host -- local SDK tree (E:\repos\steam-audio) is source+headers only,
integration release zips (wwise 52MB, downloaded+inspected) are source+docs, main SDK zip is
181MB (not fetched), core cmake build needs flatbuffers/pffft/zlib/mysofa fetches.
AUDIT.md records the three follow-up options; the suite needs no changes. licenses=Apache-2.0
(Steam Audio; nothing vendored) + package MIT OR Apache-2.0; pins=soname phonon.dll + tag
v4.8.1 + entry points (iplContextCreate/Retain/Release) + IPLContextSettings 40-byte layout
(version 0x040801 at 0, SIMD/status enums) + local header hashes (phonon.h CFAB6768...,
phonon_version.h ED3A14DA..., phonon_interfaces.h 90C9AE80...); gate=G0..G5 OK
(ABSENT -> SKIP, ABI/PROBE_FAILED -> FAIL; all unsafe in the single module); needs=NONE
(allowlisted + baseline); NO port.args.json. ASK/OPTION: if the native lane wants full
present-path evidence, fetching the 181MB SDK zip or running on a phonon.dll host completes
it with zero package changes.
SECTOR STATUS: audio complete (miniaudio, portaudio, phonon). Next per proposal:
accelerators (GATED on XVECTOR freezing xiom.vectors) or crypto/media (openssl needs a
vendored-vs-system decision; ffmpeg needs an LGPL/GPL configuration decision first).
```

```
BINDINGS BATCH 18: head=282754b0 + this handoff commit; packages=xiom.portaudio 0.2.0
(dynamic loader replacing static externs); tests=present 5/5 x2 (Audacity portaudio_x64.dll
V19.7.0 on PATH: version text 'PortAudio V19.7.0-devel, revision unknown' int 1246976,
52 devices, default output 'Speakers (Realtek(R) Audio)', default input Razer mic) and
absent 2/2 x2 (default PATH: SKIP classification + SKIP probe), all via scripts/port.ps1 on
v0.64.1; licenses=MIT (PortAudio not vendored) + package MIT OR Apache-2.0; pins=soname
portaudio_x64.dll + 8-entry-point set + PaDeviceInfo prefix (name pointer at offset 8) +
local samples: Audacity 221,696 B sha256
370E0FD6A9793EDBD0D0FA7F2CC7CDAA4EED86D3A747D765CAFC1DDB0E5968EF (used), DaVinci 102,400 B
sha256 12E0C6AE447F5C72F4EABD8CAFD6A036AEB33FAD392973FE46BEDF17A628D3AB (SPEC.md §2);
gate=G0..G5 OK; needs=NONE (allowlisted + baseline); NO port.args.json (pure-XIOM loader).
```

```
BINDINGS BATCH 17: head=89dccfae + this handoff commit; packages=xiom.miniaudio 0.2.0
(vendored single header replacing the pre-pilot bridge whose miniaudio header was never
vendored); tests=4/4 x2 via scripts/port.ps1 on v0.64.1 (2026-10-09: version 0.11.25,
context playback=9 capture=4, in-memory WAV decode 16 frames / 1 channel / 8000 Hz / s16
with sample spot-checks); licenses=Unlicense (public domain) OR MIT-0 (vendored miniaudio)
+ package MIT OR Apache-2.0; pins=tag 0.11.25 vendor/miniaudio.h sha256
AC7AF4DE748B7E26B777F37E01CEE313A308A7296A3EB080E2906B320CC55C89 (4,108,168 B; committed
blob verified) + vendor/LICENSE sha256 457F1B500E0ADF6BC059EDDDFA78A2F62012E7C3BB43476C20E0BD23B25BA0EB;
gate=G0..G5 OK; needs=NONE (allowlisted + baseline); port.args.json present
(--c-source src/miniaudio_all.c: MINIAUDIO_IMPLEMENTATION + probe bridge in one TU, no
--link). No library-absence SKIP path (vendored); a serviceless host reports the context
check as SKIP with the miniaudio result code.
```

## Sector proposal (bindings lane, post tier-3)

Ordered by risk retired per unit of work, each keeping the one-package-per-
relay discipline:

1. **Data/drivers (COMPLETE)**: `xiom.odbc` 0.2.0 + `xiom.libpq` 0.2.0; the
   `xiom.postgres` scope call (facade over libpq vs pure-XIOM wire) is the
   native lane's.
2. **Audio**: `xiom.miniaudio` (single-header vendored C -- fits the proven
   amalgamation path; context + device enumeration + in-memory WAV
   decode/encode as functional proof), then `xiom.portaudio` (system-lib
   SKIP pattern), then `xiom.phonon` (vendored).
3. **Accelerators (XVECTOR-facing)**: `xiom.openblas` / `xiom.eigen` /
   `xiom.blas` behind the portable `xiom.vectors` contract -- GATED on
   XVECTOR freezing that contract; do not start before then.
4. **Crypto/media/heavy**: `xiom.openssl` (vendored or system SKIP),
   `xiom.ffmpeg` (license-conditional: LGPL/GPL config choice needed before
   vendoring), ONNX/OpenCV last.

Next package: `xiom.miniaudio` (audio sector).

## Relay (bindings -> native, per BINDINGS-LANE.md §6)

```
BINDINGS BATCH 15: head=27e38bd3 + this handoff commit; packages=xiom.odbc 0.2.0 (first
implementation; the dir was a manifest-less placeholder, namespace-check OK before
activation); tests=5/5 x2 via scripts/port.ps1 on v0.64.1 (2026-10-08: ODBC manager
03.80.0000, 7 drivers incl. SQL Server / ODBC Driver 11, 3 configured DSNs; deterministic
SKIP classification via bogus soname); licenses=MIT OR Apache-2.0 (odbc32.dll is a system
component; nothing vendored); pins=soname odbc32.dll + entry-point set (SQLAllocHandle,
SQLSetEnvAttr, SQLDrivers, SQLDataSources, SQLGetInfo, SQLFreeHandle) + ODBC constants +
local System32 sample 10.0.26100.9549 sha256 8A120C65049E31B26CF1608E9D9E3253F386D29539A508B345E30390542B88D7
(SPEC.md §2); gate=G0 OK (keywords:["binding"], license), G1 OK, G2 OK, G3 OK (ABSENT ->
SKIP, ABI -> FAIL), G4 OK (5 checks), G5 OK (all unsafe in the single module xiom.odbc);
needs=ALLOWLIST APPEND for xiom.odbc (not in the publish allowlist; native lane does the
append + ops scope). NO port.args.json (pure-XIOM loader).
FINDING B-10 (recorded in docs/BINDINGS-COMPILER-FINDINGS.md): a local fn-pointer variable
named `alloc` inside a confined block has its calls silently rewritten to the guard
allocator (ODBC SQLAllocHandle appeared to succeed while the out-param stayed 0; renaming
to f_alloc fixed it). Guard pass should exclude non-builtin locals.
```

```
BINDINGS BATCH 14: head=f71fb8bf + this handoff commit; packages=xiom.ozz 0.2.0 (vendored
C++ amalgamations replacing the pre-pilot module whose C bridge was never present);
tests=4/4 x2 via scripts/port.ps1 on v0.64.1 (2026-10-08: math dot/cross + 90deg axis
rotation; offline RawSkeleton -> runtime Skeleton (2 joints, parents -1/0); LocalToModelJob
child at (0,1,0) in model space; aggregate green); licenses=MIT (vendored ozz) + package MIT
OR Apache-2.0; pins=tag 0.16.0 archive sha256
A7A34322344E9D839EAF637BBC463404C6AED3F52583DEA95C856FEA580C2693 + generated TUs
vendor/ozz_all.cpp 24117B0FBBAA5E1221C2F8FBEE9CB6A79EB42E28179A29CD5DE75E392C751457 and
vendor/ozz_bridge.cpp 0D2BA8800CADD74381ED907C8A9A35687A18EE014BA54C5D8D9DFFFFCCD6CA76
(LF-normalized, blobs verified against pins) + LICENSE.md; gate=G0..G5 OK; needs=NONE
(allowlisted + baseline); port.args.json present (--c-source x2, no --link).
METHOD NOTE: the xiom link line has no include passthrough, so ozz (C++, no C API) is
vendored as two generated TUs from the upstream-style combine.py (roots include/ + src/);
generator inputs are reviewable at src/ozz-in.cpp and src/ozz-bridge-in.cpp; the full
re-pin procedure is in SPEC.md §2. This method generalizes to any header-heavy C/C++ library.
```

```
BINDINGS BATCH 13: head=a528dfd8 + this handoff commit; packages=xiom.lzfse 0.2.0 (vendored
Apple lzfse-1.0 sources replacing placeholder wrappers); tests=7/7 x2 via scripts/port.ps1
on v0.64.1 (2026-10-08: scratch encode 684,384 B / decode 47,368 B, 4096->182 bytes,
round-trip identity incl. 65,536-byte and 1024-byte incompressible, invalid stream
rejected); licenses=BSD-3-Clause (vendored Apple sources) + package MIT OR Apache-2.0;
pins=tag lzfse-1.0 archive sha256
CF85F373F09E9177C0B21DBFBB427EFAEDC02D035D2AADE65EB58A3CBF9AD267 + per-file SHA256 table
(15 files, SPEC.md §2); gate=G0..G5 OK; needs=NONE (allowlisted + baseline);
port.args.json present (--c-source x7, upstream add_library source list, no --link);
.gitattributes vendor/** -text byte pin; lzfse_main.c (CLI) intentionally not vendored.
```

```
BINDINGS BATCH 12: head=a0f3513e + this handoff commit; packages=xiom.zstd 0.2.0 (vendored
amalgamation replacing the pre-pilot null-pointer stubs); tests=8/8 x2 (+1 post-normalization
re-run) via scripts/port.ps1 on v0.64.1 (2026-10-08: version 1.5.7, compressBound sanity,
8192->34 bytes at level 3, frame content size 8192, round-trip identity incl. auto-size and
2048-byte incompressible, invalid frame rejected); licenses=BSD-3-Clause (vendored zstd,
chosen from the dual BSD-3/GPLv2) + package MIT OR Apache-2.0; pins=release tar.gz sha256
eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3 (verified against the
published .sha256), vendor/zstd.c sha256 208E110A1F052D007242D4EEF6ED20A03AB1DC6E13EB2C4FF8D158112120BA8E
(2,174,920 B, LF-normalized; Windows combine.py wrote CRLF), vendor/zstd.h sha256
9B4BC8245565C98CCFC61C07749928B57E7C0F6FDDB0530C4F6AA1971893D88B; gate=G0..G5 OK; needs=NONE
(allowlisted + baseline); port.args.json present (--c-source src/zstd_all.c; the 4-line shim
pins STATIC_BMI2 0 because the link line has no -mbmi2 -- vendored file itself unmodified).
NOTE: .gitattributes `vendor/** -text` pins the bytes against autocrlf (same as xiom.sqlite).
```

```
BINDINGS BATCH 11: head=4cf630ba + this handoff commit; packages=xiom.directx12 0.2.0 (capability probe replacing the pre-pilot static externs);
tests=5/5 x2 via scripts/port.ps1 on v0.64.1 (2026-10-08: highest accepted feature level 12_2
(49664) by descending D3D12CreateDevice attempts, 3 DXGI adapters, first = NVIDIA GeForce RTX
3070 Ti vendor_id 4318 device_id 9346; deterministic SKIP classification per run);
licenses=MIT OR Apache-2.0 (header-free bridge is our code; nothing vendored); pins=sonames
d3d12.dll + dxgi.dll + Windows SDK 10.0.22621.0 header hashes (um\d3d12.h 82EB3319...,
shared\dxgi.h 4B983AC7..., um\d3dcommon.h 62F7BF1A...) + ABI (IID_ID3D12Device
{189819f1-1db6-4b57-be54-1821339b85f7}; IID_IDXGIFactory1 + DXGI vtables/offsets shared with
directx11; feature levels 11_0..12_2); gate=G0..G5 OK (ABSENT/NO_DEVICE -> SKIP, ABI -> FAIL;
all unsafe in the single module xiom.directx12); needs=NONE (allowlisted + baseline);
port.args.json present (--c-source src/d3d12_probe.c, no --link).
```

```
BINDINGS BATCH 10: head=c7db19b7 (code) + this handoff commit; packages=xiom.directx11 0.2.0
(capability probe replacing the pre-pilot static externs); tests=5/5 x2 via scripts/port.ps1
on v0.64.1 (2026-10-08: hardware device at feature level 11_0 (45056), 3 DXGI adapters, first
= NVIDIA GeForce RTX 3070 Ti vendor_id 4318 device_id 9346; deterministic SKIP classification
per run); licenses=MIT OR Apache-2.0 (header-free bridge is our code; nothing vendored);
pins=sonames d3d11.dll + dxgi.dll + Windows SDK 10.0.22621.0 header hashes (um\d3d11.h
B2C0CAA5..., shared\dxgi.h 4B983AC7..., um\d3dcommon.h 62F7BF1A...) + ABI (IID_IDXGIFactory1
{770aae78-f26f-4dba-a829-253c83d1b387}; IDXGIFactory1 slot 12=EnumAdapters1; IDXGIAdapter
slot 8=GetDesc; DXGI_ADAPTER_DESC offsets 0/256/260; D3D11_SDK_VERSION=7;
DRIVER_TYPE_HARDWARE=1; feature levels 9_3..11_1); local samples System32 d3d11.dll/dxgi.dll
10.0.26100.9549 (sha256 3E6C8932.../023542BB...); gate=G0 OK, G1 OK, G2 OK, G3 OK
(ABSENT/NO_DEVICE -> SKIP, ABI -> FAIL), G4 OK, G5 OK (all unsafe in the single module
xiom.directx11); needs=NONE (allowlisted + baseline); port.args.json present
(--c-source src/d3d11_probe.c, no --link).
```

```
BINDINGS BATCH 9: head=b282cf82 (code) + this handoff commit; packages=xiom.dxc 0.2.0
(capability probe replacing the pre-pilot bridge); tests=3/3 x2 via scripts/port.ps1 on
v0.64.1 (2026-10-08: dxcompiler.dll 1.9.0.5347 from Vulkan SDK 1.4.350.0: ps_6_0 'main'
-> 2532-byte DXIL object, 4-byte aligned; deterministic SKIP classification per run);
licenses=MIT OR Apache-2.0 (header-free bridge is our code; nothing vendored);
pins=soname dxcompiler.dll + dxcapi.h hashes (SDK copy FF3CA20C... + upstream commit
fe2615732 A8D40964...) + COM ABI (CLSID_DxcCompiler 73e22d93..., IID_IDxcCompiler3
228b4687..., IID_IDxcResult 58346cda..., IID_IDxcBlob 8ba5fb08...; compiler slot 3=Compile;
result slots 3=GetStatus,7=GetOutput; blob slot 4=GetBufferSize; DxcBuffer 24B;
DXC_OUT_OBJECT=1); local sample dxcompiler.dll 1.9.0.5347 sha256
6E990D20E53390CDE413CE9A8016A8F43582E325A04CF72ECC706B4BEA504F0C (dxil.dll not present;
unsigned DXIL); gate=G0 OK, G1 OK, G2 OK, G3 OK (ABSENT -> SKIP; ABI/compile failure ->
FAIL), G4 OK, G5 OK (all unsafe in the single module xiom.dxc); needs=NONE (allowlisted +
baseline); port.args.json present (--c-source src/dxc_probe.c, no --link).
```

```
BINDINGS BATCH 8: head=af564de9 (code) + this handoff commit; packages=xiom.vulkan 0.2.0
(capability probe replacing the pre-pilot static bridge); tests=10/10 x2 via scripts/port.ps1
on v0.64.1 (2026-10-08: loader 1.4.350, 20 instance extensions + head, 15 layers, device
NVIDIA GeForce RTX 3070 Ti type 2 api 1.4; deterministic SKIP classification per run);
licenses=MIT OR Apache-2.0 (header-free bridge is our code; Khronos header pinned by hash,
not vendored); pins=soname vulkan-1.dll + Vulkan-Headers tag vulkan-sdk-1.4.350.0
vulkan_core.h sha256 6D2BA4755774B1D129DA6B8E661268B494D2D609DF6217C6B6485ACF7666B6C2 +
entry-point set + ABI details (SPEC.md §2); local sample C:\Windows\System32\vulkan-1.dll
1.4.350.0 sha256 0419974F00E82A3D619077BA414DA265A774F8DB9D45AD93BC1843F44B2C2C1F;
gate=G0 OK, G1 OK, G2 OK, G3 OK (ABSENT/NO_DEVICE -> SKIP, ABI -> FAIL; bogus-soname test
every run), G4 OK (capability suite), G5 OK (all unsafe in the single module xiom.vulkan);
needs=NONE (already allowlisted); port.args.json present (--c-source src/vk_probe.c, no
--link; no Vulkan SDK or headers required).
SCOPE NOTE (native decision requested): the ~1.7MB pre-pilot Vulkan engine bridge
(bridge/xvk_*, stb headers, shaders, build.ps1/build.sh/run.ps1, old wrappers/tests/docs)
was removed in this batch and is preserved in git history only. 0.2.0 replaces it with the
loader-capability path. If you want the bridge material preserved visibly under a
non-compiled legacy/ directory before merge, say so and I will push a follow-up.
```

```
BINDINGS BATCH 7: head=9eb9ef5b (code) + this handoff commit; packages=xiom.opengl 0.3.0;
tests=xiom.opengl 13/13 x2 via scripts/port.ps1 on v0.64.1 (2026-10-08, NVIDIA RTX 3070 Ti:
classic 4.6 context, 3.3 core negotiated, 404 extensions with head + exact-match scan, bogus
extension correctly absent, deterministic SKIP classification); licenses=MIT OR Apache-2.0
(bridge is our code; nothing vendored upstream); pins=opengl G2 extended -- soname opengl32.dll,
symbol set + wglGetProcAddress/glGetIntegerv/glGetStringi (context-scoped via
wglGetProcAddress), WGL core-context attribs (0x2091/0x2092/0x2094/0x9126, core bit 0x1) and
GL query constants (0x821B/0x821C/0x821D) recorded in SPEC.md §2; gate=G0..G5 OK (core probe
keeps ABSENT/NO_CONTEXT -> SKIP, ABI -> FAIL; all unsafe confined to xiom.opengl);
needs=NONE (already allowlisted); port.args.json unchanged (--c-source gl_probe.c).
```

```
BINDINGS BATCH 6: head=bef3e71c (code) + this handoff commit; packages=xiom.raylib 0.2.0;
tests=xiom.raylib present 12/12 x2 (official raylib 5.5.0 win64 DLL on PATH: hidden 320x200
window, size, time/frame-time/FPS, target FPS, begin/clear/end frame, CloseWindow) and absent
3/3 x2 (SKIP), both via scripts/port.ps1 on v0.64.1, 2026-10-08; licenses=MIT OR Apache-2.0
(nothing vendored; raylib zlib untouched); pins=soname raylib.dll + tag-5.5 src/raylib.h
sha256 AFB287ECD313DE61E0000921375190B7E1CC35CD381AD6CAF914489473A3C871 + 15-symbol smoke set
(size functions rename-tolerant: prefers GetWindowWidth/Height, falls back to
GetScreenWidth/Height); local positive-path sample: official raylib-5.5_win64_msvc16.zip
sha256 8D046084D12353183E701EF4C9D276C21FCD3243C2A368091FABFB2769B8507C, lib\raylib.dll
FileVersion 5.5.0 sha256 C8D29FBDA31417B900BB0220CFB6C288544264A93764F5EA7CF5727FEEC76994;
gate=G0 OK (keywords:["binding"], license), G1 OK, G2 OK, G3 OK (ABSENT/NO_WINDOW -> SKIP,
ABI -> FAIL), G4 OK, G5 OK (all unsafe confined to the single module xiom.raylib);
needs=NONE (already allowlisted); NO port.args.json. NOTE: upstream latest is raylib 6.0 --
next re-pin candidate; the loader already tolerates the 5.x/6.x size-function rename.
Pre-pilot static-extern module removed to git history as reference.
```

```
BINDINGS BATCH 5: head=4cbf7079 (code) + this handoff commit; packages=xiom.sdl3 0.3.0;
tests=xiom.sdl3 present 21/21 x2 (SDL 3.4.8: smoke + hidden window / renderer clear+present /
RGBA8888 texture / gamepad enumeration) and absent 3/3 x2 (SKIP), both via scripts/port.ps1,
2026-10-08, COMPILER v0.64.1 (see note below); licenses=MIT OR Apache-2.0 (nothing vendored);
pins=G2 unchanged (soname SDL3.dll + release-3.4.8 header-set manifest
FD61D35102FDAC6FDDB944ED0192DFE4058222FDC531327F74264FF53B0E3023); gate=G0..G5 OK;
needs=NONE (already allowlisted); NO port.args.json.
PIN NOTE: repo COMPILER_VERSION still says v0.64.0 but the installed slot (and scripts/xiom.ps1
-Info) resolve v0.64.1, so all batch-5 runs are v0.64.1. Native lane: repin records/SPEC rows
as per your process; package SPEC rows for sdl3 0.3.0 already state v0.64.1.
V0.64.1 FINDINGS SWEEP (docs/BINDINGS-COMPILER-FINDINGS.md): B-06 FIXED (full-catalog
MigrationManager.up/down shape builds + 16/16), B-09 FIXED (Win32/WGL mega-block runs green
2/2, real GL string); B-01 enum-payload nondeterminism STILL OPEN (2/6 builds), B-05
alloc/free guard spin STILL OPEN (8 s watchdog kill, flat 4.5 MB), B-08 --run exit masking
STILL OPEN (main returning 5 -> exit 0). B-02/B-03/B-04/B-07 not re-tested (pre-fix catalogs
no longer exist); rebuildable from the findings doc.
```

```
BINDINGS BATCH 4: head=34ccd6ba (code) + this handoff commit; packages=xiom.glfw 0.2.0;
tests=xiom.glfw present 9/9 x2 (GLFW 3.4.0 official win64 binary on PATH) and absent 3/3 x2
(SKIP path), both via scripts/port.ps1, v0.64.0, 2026-10-08; licenses=MIT OR Apache-2.0
(nothing vendored; GLFW zlib untouched); pins=soname glfw3.dll + tag-3.4 header
GLFW/glfw3.h sha256 AA370985F6B493BBE0358A36AB49F5780A6397C0209C6D98A62143DEA595B73C +
resolved symbol set (glfwInit/glfwTerminate/glfwGetVersion/glfwGetVersionString/glfwGetTime/
glfwGetError); local positive-path sample: official glfw-3.4.bin.WIN64.zip sha256
54EFA829400F2A0537F742B2B3BDD74E437BB4F2F048E4B7D3C5557D11A611E6, lib-vc2022\glfw3.dll
FileVersion 3.4.0 sha256 4429ADFF...C14BB1, runtime build string "3.4.0 Win32 WGL Null EGL
OSMesa VisualC DLL"; gate=G0 OK (keywords:["binding"], license), G1 OK, G2 OK (soname +
header hash + symbol set + re-pin), G3 OK (ABSENT/NO_PLATFORM -> SKIP, ABI -> FAIL), G4 OK
(loader smoke), G5 OK (all unsafe confined to the single module xiom.glfw); needs=NONE
(already allowlisted); NO port.args.json (pure-XIOM loader). Also fixed the pre-pilot
module-name typo (xiom.glwf -> xiom.glfw) and removed the unlinkable C bridge.
```

```
BINDINGS BATCH 3: head=df8c76aa (code) + this handoff commit; packages=xiom.opengl 0.2.0;
tests=xiom.opengl 8/8 PASS x2 via scripts/port.ps1 (2026-10-08, v0.64.0) on an NVIDIA
RTX 3070 Ti (GL 4.6.0 NVIDIA 616.92); both runs also exercise the deterministic SKIP
classification (bogus soname -> OPENGL_LOAD_ABSENT); licenses=MIT OR Apache-2.0 (nothing
vendored upstream; src/gl_probe.c is our bridge code); pins=soname opengl32.dll + resolved
symbol set (glGetString/wglCreateContext/wglMakeCurrent/wglDeleteContext + user32
CreateWindowExA/DestroyWindow/GetDC/ReleaseDC + gdi32 ChoosePixelFormat/SetPixelFormat) +
PIXELFORMATDESCRIPTOR layout; local sample opengl32.dll FileVersion 10.0.26100.9278
sha256 659BE03C...A5ECE, runtime strings in SPEC.md §2; gate=G0 OK (keywords:["binding"],
license), G1 OK, G2 OK (pin + re-pin procedure), G3 OK (ABSENT/NO_CONTEXT -> SKIP, ABI ->
FAIL; SKIP path deterministically testable on any host), G4 OK (staged probe suite), G5 OK
(all unsafe/extern confined to the root module xiom.opengl); needs=NONE (already
allowlisted). NOTE: this package DOES use port.args.json (--c-source ${PACKAGE_DIR}/
src/gl_probe.c) -- the runner hook compiles the bridge, no --link flags.
```

```
BINDINGS BATCH 2: head=f3553cc3 (code) + this handoff commit; packages=xiom.sdl3 0.2.0;
tests=xiom.sdl3 present 10/10 x2 (SDL 3.4.8 on PATH) and absent 3/3 x2 (SKIP path), both
through scripts/port.ps1, v0.64.0, 2026-10-08; licenses=MIT OR Apache-2.0 (nothing
vendored; SDL3 itself untouched, zlib); pins=soname SDL3.dll + SDL release-3.4.8 header
set manifest sha256 FD61D35102FDAC6FDDB944ED0192DFE4058222FDC531327F74264FF53B0E3023
(7 headers listed in SPEC.md §2; local positive-path sample: Vulkan SDK 1.4.350.0 SDL3.dll
FileVersion 3.4.8.0 sha256 6E2B4B6A...C263, runtime reports 3004008); gate=G0 OK
(keywords:["binding"], license), G1 OK, G2 OK (soname + header manifest pin + re-pin
procedure), G3 OK (SKIP path never FAILs; ABI mismatch is an explicit FAIL kind), G4 OK
(loader smoke: load/version/revision/init/was_init/ticks+delay/perf/pump/poll/quit/release),
G5 OK (all unsafe + fn-pointer casts confined to the single module xiom.sdl3); needs=NONE
(already allowlisted; no ops ask; NO port.args.json required -- the loader needs no C source
or extra compiler flags, which is the design point of the dynamic-loader path).
```

```
BINDINGS BATCH 1: head=dfaa17b2 (+ this handoff commit); packages=xiom.sqlite 0.2.0;
tests=xiom.sqlite 16/16 PASS x6 consecutive build+run cycles (default compiler flags,
2026-10-08, v0.64.0); licenses=package MIT OR Apache-2.0, vendored SQLite 3.53.4
Public Domain (vendor/LICENSE); pins=sqlite3.c sha256
B1DD5D74EC7F29055A6684FA06FB3C2F6821C87DD38F9A458DFD2E8A1DB28189, sqlite3.h sha256
919E7F2E8ED1D8F56AC17B412B8971C76AA5D1A879752CC6058F75E7D5910E1D, sqlite3ext.h sha256
AC9645E5C9FF0CF176EFDD6E75CB5E98F46295D38E02DB5C4D208826A39AB4BE, upstream
sqlite-amalgamation-3530400.zip sha3-256 628a44cf...27934e verified with certutil and
sha256 1E71DDF9...E87D; gate=G0 OK (keywords:["binding"], license), G1 OK (compiles on
the pin), G2 OK (SHA256 over vendored header set + version 3.53.4/libversion_number
3053004 pinned in SPEC.md), G3 n/a vendored path (no SKIP case: the amalgamation is
compiled in), G4 OK (16 functional checks incl. open/exec/prepared/bind/error codes),
G5 OK (all unsafe+extern confined to src/ffi.xi; facade+satellites pure); namespace-check
xiom.sqlite OK (0 conflicts vs 1724 namespaces);
needs=1) allowlist append + ops scope enumeration for xiom.sqlite (native lane);
2) port.ps1 runner hook for per-package extra compiler args, resolved package-relative:
   xiom --run tests/test_conformance.xi --c-source <abs>/vendor/sqlite3.c --opt-level
   default; --c-source needs an ABSOLUTE path (clang cwd is a scratch dir) and the
   suite needs >=180s watchdog (amalgamation compiles at link time, ~25-50s observed);
   same hook will serve the sdl3/opengl SKIP suites.
```

Suggested owner one-liner to forward to the native session:

> Bindings batch 1 (xiom.sqlite) is green on branch `bindings` at dfaa17b2:
> relay in E:\xiom-packages\bindings\BINDINGS-SESSION.md; merge + allowlist
> append for xiom.sqlite + port.ps1 per-package compiler-args hook requested.

## Session ledger

- Worktree: `E:\xiom-packages\bindings`, branch `bindings`, kept fresh
  (merged origin/main at 6fa4f9a6 before starting; relay transport commit
  ceeea349 noted).
- Pilot package 1 of 3: **xiom.sqlite** -- done, pending native merge/publish.
  Per the plan, work on xiom-sdl3 starts after the native session merges and
  publishes this batch.
- Suite command (from `packages/xiom-sqlite`):
  `xiom --run tests/test_conformance.xi --c-source <abs>\vendor\sqlite3.c`
  Evidence: 6 consecutive build+run cycles 16/16 PASS (22-31s each; first cold
  run ~50s). The compile+run is deterministic now -- see enum finding below.
- G2 pin verified from git blobs, not just the worktree:
  `git cat-file -p HEAD:packages/xiom-sqlite/vendor/sqlite3.c` SHA256 ==
  B1DD5D74... and byte length 9,515,341. `vendor/** -text` (package-local
  .gitattributes) prevents core.autocrlf from breaking the pins on fresh
  checkouts.

### Compiler findings (v0.64.0) -- details for docs/COMPILER-FINDINGS.md

1. **Enum payload reads miscompile nondeterministically across BUILDS.**
   `SqliteValue` as a user enum with payloads (`Integer(Int)`, `Text(Str)`,
   ...) made accessors fail in ~50% of rebuilds of the SAME source
   (11/16 vs 16/16 passes; a 4-check micro probe flipped to all-false in 1 of
   6 builds, i.e. the whole enum layout was wrong in that build). Same class
   as the existing `xiom.graphql` enum-payload finding. Fixed by a tagged
   struct (`kind` + plain fields); 8/8 micro builds and 6/6 suite builds
   green after the change. Re-test the enum model at the next pin.
2. **`pub const` references inside confined (`unsafe`) blocks and long
   const-if chains recurse the resolver** -> compiler stack overflow
   (exit 0xC00000FD) in full-catalog builds. Workaround: literals inside
   `src/ffi.xi` bodies and in `error_name`; public consts unchanged.
3. **Cross-module const aliases** (`pub const A: Int = other.B`) recurse the
   resolver when referenced. Facade consts use literal values.
4. **Child modules cannot import their parent** (known: documented in
   `xiom-vault`). FFI core is a sibling (`xiom.sqlite.ffi`); only the parent
   facade imports children.
5. **`xiom.ffi.alloc` inside a confined block + `xiom.ffi.free` spins.**
   The guard pass rewrites `alloc` to `xiom_guard_alloc` inside the block
   while `free` stays libc; the guard heap then loops (flat memory, 100% CPU
   -- watchdog it). Workaround: no malloc/free in confined blocks; C
   out-params write into an XIOM-owned `Vec[UInt8]` slot.
6. **A module exporting an associated fn whose last segment is `up` (or
   `down`) crashes the compiler with `xiom.test` in the catalog.**
   Migration methods renamed `migrate_up`/`migrate_down`.
7. **Unqualified imports from library modules do not resolve** (`use
   xiom.sqlite;` then bare `prepare(...)` -> undefined variable); sibling
   module qualification (`ffi.prepare(...)`) works. Also `use xiom.ffi;` in
   a module named `...ffi` shadows the alias -> avoid the stdlib import there.
8. Note: `xiom --run` returned exit 0 for a suite whose `main` returned 5;
   port.ps1's [PASS]/[FAIL] marker counting is the reliable signal.

### Safety note (owner-facing)

A hung test binary from this lane (the alloc/free guard-heap spin, finding 5,
before it was diagnosed) ran ~21 minutes burning CPU and is the most likely
contributor to the 98 GB memory event / restart at 11:54 on 2026-10-08.
After diagnosis all runs used a memory/time-capped watchdog; the final suite
runs peaked at ~7 MB RSS. No other lane process was touched.

## Inbound context (2026-10-08, after batch 1 merged @ 05a19deb, wrapped 5ea29bb5/2cb3f03a)

- Batch 1 merged and wrapped: `xiom.sqlite` 0.2.0 is on the allowlist (505 names);
  `port.args.json` hook live (`docs/BINDINGS-LANE.md` §10); findings recorded in
  `docs/COMPILER-FINDINGS.md`. **sdl3 starts only after the eco-v0.1.89 publish
  confirmation** (owner/native relay); keep-fresh before starting.
- New project lanes joined the ecosystem (Projects -> packages -> stdlib ->
  compiler): PULSE (web), ORBITDB (embedded DB), XVECTOR (vector DB). Relays were
  addressed to the packages lane; binding-relevant reads:
  - ORBITDB (`docs/RELAY-PACKAGES-ORBITDB.md`): **"No C-FFI/bindings need from
    ORBITDB (pure XIOM target)"** -- acknowledged, nothing for this lane.
  - XVECTOR (`docs/PACKAGE-WISHLIST-XVECTOR.md`): proposes `xiom.vectors`,
    `xiom.wal`, `xiom.ann` (pure-XIOM domain layers, native-lane coordination);
    the accelerator row asks the bindings lane to `Watch` for the Phase 10
    SIMD/kernel path and to say whether a pure-XIOM SIMD kernel package is
    planned before they propose a second kernel package.
- Bindings-lane position (for relay to XVECTOR/native):
  1. `xiom-blas` / `xiom-eigen` / `xiom-openblas` exist in THIS worktree as
     pre-rostered `incubating` placeholders (tests `unknown`; specs describe
     CBLAS/OpenBLAS FFI, current code is stubs -- same pre-pilot state
     `xiom.sqlite` was in). Nothing published; no timeline is promised. When the
     bindings Phase 2 reaches them they will be opt-in accelerators behind the
     portable `xiom.vectors` contract -- the binding API surface should mirror
     the pure-XIOM functions, never define them.
  2. The bindings lane plans **no pure-XIOM SIMD kernel package**; that is
     native/stdlib territory. If `xiom.simd`-class work appears there, bindings
     adopt it as the portable path and keep FFI libs as drop-in accelerators.
  3. Name/scope coordination for `xiom.wal` (ORBITDB vs XVECTOR duplication) is
     a native-lane call; this lane has no storage-format stake.

## Batch 2 notes (xiom.sdl3, 2026-10-08)

- Dynamic loader replaces static externs: `sdl3_load` (via `xiom.ffi.dl`)
  resolves SDL3.dll at runtime. Absent -> `SDL3_LOAD_ABSENT`; the suite prints
  explicit SKIP labels under `[PASS]` markers (green without the SDK).
  Present-but-missing-symbol -> `SDL3_LOAD_ABI` (explicit `[FAIL]`; handle
  closed, no leak).
- The static-extern module `src/sdl3_safe.xi` and the extern tail of the old
  root module were removed: they cannot satisfy G3 and would fail linking
  without SDL3. The full pre-pilot SDL3 3.4.8 constant tables and resource
  wrappers remain in git history (pre-0.2.0) and return in Phase 2
  (`ROADMAP.md`).
- Run matrix through `scripts/port.ps1`: absent 3/3 x2 (PATH without the
  Vulkan SDK dir), present 10/10 x2 (SDL 3.4.8 from the Vulkan SDK on PATH;
  runtime reports 3004008, revision `SDL-3.4.8-release-3.4.8`). The demo was
  run against the same DLL.
- **No `port.args.json`**: the pure-XIOM loader compiles no C source and needs
  no extra flags (contrast `xiom.sqlite`, which needs
  `--c-source vendor/sqlite3.c`). CI runs the suite unchanged.
- G2 pin: soname `SDL3.dll` + `release-3.4.8` header-set manifest
  `FD61D351...E3023` (per-file hashes in `SPEC.md` §2).

## Batch 3 notes (xiom.opengl, 2026-10-08)

- Loader/probe design: vendored `src/gl_probe.c` resolves opengl32/user32/
  gdi32 at runtime and stages symbol -> contextless -> real-context probes;
  classification ABSENT/NO_CONTEXT -> SKIP, ABI -> FAIL. The XIOM module is
  a thin safe wrapper (all `unsafe`/`extern` in one module, G5).
- The pure-XIOM Win32/WGL context path was abandoned first: it poisoned the
  binary pre-output (0xC0000409, deterministic). Bounded repro + control
  preserved in `docs/repro/bindings-pilot/win32-gl-unsafe/`; recorded as
  finding **B-09** (the first lane finding with a deterministic, no-watchdog
  runnable repro).
- `opengl_probe_named("bogus.dll")` gives every host (GPU or not) a
  deterministic SKIP-branch test, so the no-GPU CI shape is exercised even on
  developer machines.
- Run matrix: `port.ps1 -Package xiom.opengl` -> PASS 8/8 x2 (NVIDIA RTX 3070
  Ti, GL 4.6.0 NVIDIA 616.92, GLSL 4.60 NVIDIA; VENDOR/RENDERER strings in
  SPEC.md §2). No-context SKIP path code-reviewed, not force-tested locally.
- `port.args.json` is present (`--c-source ${PACKAGE_DIR}/src/gl_probe.c`);
  no `--link` flags are needed because the bridge loads everything
  dynamically.

## Batch 4 notes (xiom.glfw, 2026-10-08)

- Same system-lib SKIP pattern as xiom.sdl3: `glfw_load` resolves
  `glfw3.dll` via `xiom.ffi.dl`; classification ABSENT / NO_PLATFORM (init
  fails headless) -> SKIP, ABI -> FAIL. All `unsafe` in the single module.
- Pre-pilot defects fixed in passing: the module was declared `xiom.glwf`
  (typo) and the C bridge required GLFW headers/import libs at build time
  (could not satisfy G3). Bridge + stale tests/demos removed; history keeps
  them as reference.
- Run matrix: absent 3/3 x2 (no glfw3.dll on PATH); present 9/9 x2 against
  the official GLFW 3.4 win64 binary (`lib-vc2022`, FileVersion 3.4.0,
  build string `3.4.0 Win32 WGL Null EGL OSMesa VisualC DLL`).
- No `port.args.json`; no new compiler findings (the loader avoids the known
  v0.64.0 classes; out-params use XIOM-owned Vec slots per B-05).

## Batch 5 notes (xiom.sdl3 Phase 2, 2026-10-08)

- Resource stage is a separate loader (`sdl3_load_resources`, 19 symbols) so
  an older SDL3 still gets the smoke SKIP classification; a missing resource
  symbol fails only the resource stage. Window paths SKIP cleanly when the
  platform cannot create a window; gamepad open/close runs only when a
  device is attached (none here -> SKIP line).
- Runs on **v0.64.1** (installed slot; repo pin file still v0.64.0). The
  resolver picks 0.64.1 over the pin, so batch-5 STATUS/green evidence is
  v0.64.1; SPEC rows updated accordingly.
- v0.64.1 sweep of lane findings moved B-06 and B-09 to FIXED with
  reproductions re-run; B-01/B-05/B-08 remain open and their workarounds
  stay in force (tagged-struct value model, no malloc/free in confined
  blocks, marker-based pass/fail checks).

## Batch 6 notes (xiom.raylib, 2026-10-08)

- Same system-lib SKIP pattern: `raylib_load` resolves `raylib.dll` via
  `xiom.ffi.dl`; classification ABSENT / NO_WINDOW (headless) -> SKIP,
  ABI -> FAIL. The smoke sets `FLAG_WINDOW_HIDDEN` before `InitWindow` so a
  desktop session proceeds; `IsWindowReady()` checks the result because
  `InitWindow` is void.
- The 5.5 DLL exports `GetScreenWidth/GetScreenHeight` (not the 6.x
  `GetWindow*` names): the loader prefers the 6.x names and falls back, so
  both generations resolve -- the first present-path run surfaced this as an
  ABI FAIL, which is why the pin table records it.
- Run matrix: absent 3/3 x2 (no raylib.dll on PATH); present 12/12 x2
  against the official raylib 5.5 win64 binary (hidden 320x200 window, size
  320x200, begin/clear/end frame).
- Upstream latest is raylib 6.0 (package pins 5.5, the pre-pilot target);
  flagged as the next re-pin candidate in SPEC/relay.
- No `port.args.json`; no new compiler findings.

## Batch 7 notes (xiom.opengl Phase 2, 2026-10-08)

- Core-profile probe: a temporary classic context obtains
  `wglCreateContextAttribsARB`; the requested core context (3.3 here) is
  created and the negotiated version + extension count/head reported;
  `opengl_has_extension` scans `glGetStringi` with exact match. Probes stay
  atomic (load -> context -> query -> unload); no session state leaks.
- Runs on v0.64.1: 13/13 x2 (classic 4.6 strings, 3.3 core, 404 extensions,
  bogus extension absent, aniso present). The SKIP classification test runs
  in every suite invocation (bogus soname -> ABSENT).
- Bridge refactor kept everything in `src/gl_probe.c` (context helpers);
  `port.args.json` unchanged. All XIOM `unsafe` still in the single module.
- Next options for batch 8: `xiom.vulkan` (GPU tier per the Phase-2 order)
  or the opengl session API (`opengl_session_get_proc` function-table seam)
  -- native lane to pick; the roadmap lists both.

## Batch 8 notes (xiom.vulkan, 2026-10-08)

- Header-free capability bridge: `vkGetInstanceProcAddr` seam; minimal
  instance-create ABI declared locally; loader-written structs received into
  opaque 2048-byte buffers. No Vulkan SDK needed to build or run the probe.
- Two bugs found by the first present-path run and fixed in the bridge:
  (1) enumeration with capacity < count returns `VK_INCOMPLETE`(5), which was
  treated as failure (empty extension head); (2) instance-level functions were
  resolved via `vkGetInstanceProcAddr(NULL, ...)` -- they must use the
  instance handle, otherwise device enumeration silently yields 0 devices.
- Runs: 10/10 x2 (loader 1.4.350; 20 extensions; 15 layers; RTX 3070 Ti
  discrete, api 1.4). SKIP classification runs every suite invocation.
- Scope decision requested from the native lane: the pre-pilot static-bridge
  engine was removed to git history in this batch (same treatment as
  sdl3_safe.xi / glfw_bridge.c / opengl static wrappers).

## Batch 23 notes (physics + UI roster, 2026-10-09)

- `xiom.box2d` 0.2.0: vendored v3.1.1 C via the flat layout (35 sources +
  bridge; the lzfse multi-source pattern): quoted includes resolve against
  each file's own directory, so no generator and no `-I`. Integer-only
  bridge (milli encoding); real simulation proof (drop settles at 499 milli
  = half-extent on the ground; impulse dv = J/m exactly).
- `xiom.imgui` 0.2.0: vendored v1.92.9b core + upstream null backends (the
  supported blind-context flow); headless two-frame probe -- ImGui hides a
  newly created window on frame 1, so the suite reports frame 2 (76 vtx /
  240 idx / 1 cmd). Replaces the pre-pilot precompiled-object + GLFW/Vulkan
  bridge tree (history only). Debug note: without `io.Fonts->Build()` or
  the RendererHasTextures flag the 1.92 font system asserts.
- `xiom.jolt` recon (BLOCKED): tarball v5.6.0 pinned (sha 6E069EE0...,
  19.4 MB); generator (mirror + `<Jolt/` -> `"Jolt/` rewrite + 25
  per-directory TUs) validated to compile the whole library under
  `-std=c++17` in ~30 s with system clang. The link line passes no standard
  flag and clang 22 defaults to C++14 -> cannot build via --c-source yet.
  Ask relayed; no jolt artifacts committed until unblocked.
- Namespace-check OK for both; no new compiler findings.

## Batch 22 notes (xiom.sqlite enum restore, 2026-10-09)

- B-01 workaround retired at the repin per the native rule ("droppable at
  the next touch"): `types.xi` restores the canonical enum model from the
  repro bundle (struct wrapping `SqliteValueKind`); `rows.xi` needed only a
  comment fix (constructors unchanged); `kind_name` kept (match-based).
- Validation: 6 fresh rebuild cycles (the defect was build-dependent;
  original evidence 2/6 bad) + the pin matrix x1 -- 16/16 each time.
- Docs updated: SPEC §1/§5 (0.3.0, v0.64.2 pin, item 1 rewritten as
  FIXED+restored), README status, AUDIT design note; obsolete `VALUE_*`
  constants removed with the struct.
- Version 0.3.0 (public type representation changed); the publish decision
  is the native lane's.

## v0.64.2 sweep notes (2026-10-09)

- Toolchain: v0.64.2 -- the installed slot `%LOCALAPPDATA%\xiom.new`
  (used by `port.ps1`) plus the repo-release build
  `E:\xiom-lang\xiom\target\release` (used by the direct repro probes);
  repo pin still v0.64.1 -- the native repin is pending. The old
  `%LOCALAPPDATA%\xiom.new` slot has been replaced by the shipped release.
- Repro batteries: B-01 6/6 all-true rebuilds (was 2/6 bad); B-08 compiler
  exits 5 for a program returning 5; B-05 spin reproduced under the 10 s
  watchdog (8.7 CPU-s, flat 4.5 MB); B-10 3-way scratch control
  (`f_alloc`/`my_alloc` green, `alloc` fail); B-06/B-09 green.
- Matrix: 19/19 suites x1; no new compiler findings from the sweep.
- Minimal-shape follow-ups (2026-10-09): B-03 + B-04 GREEN, B-07 STILL
  BROKEN (`undefined variable` in a `module ...ffi` + `use xiom.ffi;` shape);
  bundles committed under `docs/repro/bindings-pilot/` (const-alias,
  child-import-parent, ffi-alias-shadow); B-02 not re-tested (no trigger).
- Workaround retirement: B-01 (sqlite tagged-struct) RETIRED in `xiom.sqlite`
  0.3.0; B-05/B-10 workarounds stay; B-06/B-09 bridge/naming
  workarounds are optional-touch only (no drive-by reverts).

## Batch 21 notes (xiom.ffmpeg, 2026-10-09)

- Scope per the native decision (`BINDINGS-LANE.md` §11): system-lib SKIP
  path only, LGPL-safe probe; vendoring NOT approved. Present-path proof
  used the local Cascadeur 6.0 LGPL set placed on PATH at run time (nothing
  committed; hashes in SPEC §3).
- Generation model: one release generation = four libraries
  (avcodec/avformat/avutil/swresample); a partial set is skipped, never
  mixed across ABI generations. 8.x..4.x table in SPEC §3.
- Probe calls 7 LGPL-safe entry points only: version string + four packed
  versions + license/configuration evidence. GPL-configured host builds are
  reported as data (Blender 7.1.1 sample), not failed -- the package never
  depends on a GPL-only feature.
- Extra coverage beyond the required x2: second generation (7.x) exercised
  via Blender; two partial-generation SKIP cases (OneDrive 8.x, DaVinci
  6.x). Pre-pilot 27-static-extern module + 26-test suite preserved in git
  history.
- Namespace-check OK (0 conflicts vs 1758); no new compiler findings.

## Batch 20 notes (xiom.openssl, 2026-10-09)

- System-lib path chosen (decision recorded in SPEC §2 and the relay):
  OpenSSL source is too large/configuration-heavy to vendor; libcrypto
  builds are ubiquitous on Windows; the SKIP classification keeps CI green
  while the present-path proof is real (byte-exact SHA-256("abc") digest +
  RAND_bytes(16) via the resolved `SHA256`/`RAND_bytes` entry points).
- Multi-soname loader candidates: `libcrypto-3-x64.dll`,
  `libcrypto-1_1-x64.dll`, `libcrypto-1_1.dll`, `libcrypto.dll`.
- Run matrix: default PATH (System32 LibreSSL 3.8.2) 4/4 x2; Git for
  Windows on PATH (OpenSSL 3.2.4, num 807403584) 4/4; deterministic SKIP
  classification every run (bogus soname). Sample hashes in SPEC §2.
- Inbound compiler relay v0.64.2 recorded (lane copy under `docs/`):
  B-01 fixed (m231), B-08 fixed (m228); B-05 still open (runtime/stdlib
  side); B-10 (odbc `alloc` name rewrite) re-test queued with the sweep.
  The sweep is gated on the tag -- installed slot is still v0.64.1.
- ffmpeg recommendation sent (LGPL-only, system-lib first); crypto/media
  paused until the native lane decides. NO port.args.json.

## Batch 19 notes (xiom.phonon, 2026-10-09)

- Steam Audio (Valve) 4.8.1: ABI pinned from the exact local SDK headers
  (`phonon.h` + `phonon_version.h` at `E:\repos\steam-audio`); the probe
  builds the 40-byte `IPLContextSettings` (version `0x040801`, SSE2 baseline,
  NULL callbacks) and balances create/retain/release via slots.
- **Present path unexercised** -- exhaustive local search found no
  `phonon.dll`; official integration zips are source-only (wwise zip
  downloaded + inspected), the main SDK zip is 181MB, and a core cmake build
  needs four fetched dependencies. `AUDIT.md` records the options; this is
  the lane's first package whose primary present path is pending rather than
  proven -- flagged prominently in the relay.
- Absent path 3/3 x2 (constants + SKIP classification + SKIP probe).
- Audio sector complete; next sector awaits the XVECTOR gate (accelerators)
  or the openssl/ffmpeg configuration decisions (crypto/media).

## Batch 18 notes (xiom.portaudio, 2026-10-09)

- Dynamic loader replaces the pre-pilot static-extern module; present-path
  proof used the Audacity x64 build (PATH prepend only, nothing committed).
- `PaDeviceInfo` name extraction: `structVersion` + padding then `char* name`
  at offset 8, read via `xiom.ffi.ptr_read_u64_le` and copied with
  `Str::from_c_str` (pure-XIOM; no C bridge needed).
- Real evidence: V19.7.0 (int 1246976), 52 devices, Realtek speakers and
  Razer mic defaults. Matrix present 5/5 x2, absent 2/2 x2.
- Audio sector: package 2 of 3; next `xiom.phonon`.

## Batch 17 notes (xiom.miniaudio, 2026-10-09)

- Vendored single-header pattern proven: one compile unit
  (`src/miniaudio_all.c`) holds `MINIAUDIO_IMPLEMENTATION` plus the probe
  bridge; no include paths, no --link, no separate bridge object.
- Real functional evidence without any audio hardware/backend assumptions:
  context init enumerated 9 playback + 4 capture devices; the in-memory WAV
  decode (8 kHz mono s16, precomputed sine, byte-built header) verified
  frames/channels/rate/format and spot-checked samples.
- Probe bug found and fixed: the EOS read returns `MA_AT_END` on a drained
  decoder (`MA_SUCCESS || MA_AT_END` with zero frames is the correct check).
- Blob pin verified from git; `vendor/** -text` applied. Matrix 4/4 x2.
- Audio sector: package 1 of 3; next `xiom.portaudio`, then `xiom.phonon`.

## Batch 16 notes (xiom.libpq, 2026-10-08/09)

- Dynamic loader replaces the pre-pilot static-extern stub module; no server
  needed: `PQlibVersion` is connection-free and the connect probe targets a
  closed local port, so real `PQconnectdb`/`PQstatus`/`PQerrorMessage` /
  `PQfinish` behaviour is asserted (CONNECTION_BAD + non-empty error).
- Present-path proof used the x64 libpq 13.11 shipped with DaVinci Resolve
  (prepended to PATH for the run; nothing committed). Default PATH has no
  libpq.dll, so the absent/SKIP path is the CI-default shape here.
- Matrix: absent 2/2 x2, present 4/4 x2. Allowlisted + baseline;
  needs= odbc allowlist append only.
- Data/drivers sector complete; next: audio (`xiom.miniaudio`).

## Batch 15 notes (xiom.odbc, 2026-10-08)

- First implementation for a manifest-less placeholder; namespace-check ran
  before activation (OK, 0 conflicts).
- **New compiler finding B-10**: a local fn-pointer named `alloc` in a
  confined block is silently redirected to the guard allocator -- the ODBC
  env handle stayed 0 while every call reported success. A C reference probe
  outside XIOM proved the API call was correct; renaming the local to
  `f_alloc` fixed it. All bridge locals now use the `f_` prefix.
- Pure-XIOM loader (no bridge, no port.args.json): handles via XIOM-owned
  slots; `SQLDrivers`/`SQLDataSources` scans capped to bound misbehaving
  managers.
- Local evidence: manager `03.80.0000`, 7 drivers, 3 DSNs. Run matrix 5/5 x2.
- `xiom.odbc` is NOT allowlisted yet -- the relay carries the append ask.
- Sector proposal added above; next package: `xiom.libpq`.

## Batch 14 notes (xiom.ozz, 2026-10-08)

- **New capability proven: vendored C++ through the link line.** `xiom
  --help` has no include passthrough, so header-path-dependent C++ cannot be
  passed as individual sources; the upstream-style `combine.py` bundles the
  library into one TU (27 sources, first compile green in 2.3 s, no static
  collisions) plus a second TU for our `extern "C"` bridge. Reusable for any
  future header-heavy C/C++ package.
- Bridge API corrections found by compile iteration: quaternion rotation is
  `TransformVector(q, v)` (no `q * Float3`); matrix translation lanes need
  `GetX/GetY/GetZ` (SIMD values are not structs). Wrapper-vs-extern name
  shadowing bit again (lzfse lesson) -- public wrappers use `_ok`.
- The pilot exercises real runtime objects (offline SkeletonBuilder ->
  runtime Skeleton -> LocalToModelJob), not just symbol resolution.
- Generated TUs LF-normalized + pinned; committed blob hashes verified
  against the pins; `.gitattributes` `vendor/** -text`.
- Run matrix: 4/4 x2. Allowlisted + baseline; `port.args.json` passes both TUs.
- Compression/animation tier set complete (zstd, lzfse, ozz); next wave per
  native priority (data drivers / audio / accelerators are the remaining
  Phase-2 sectors).

## Batch 13 notes (xiom.lzfse, 2026-10-08)

- Multi-source vendoring worked without a shim: `port.args.json` passes the
  seven upstream `add_library` sources as separate `--c-source` entries
  (clang compiles them individually -- no cross-TU static collisions).
- Naming trap: a wrapper named like the extern (`lzfse_encode_scratch_size`)
  self-recurses; wrappers now use `_required` suffix. Worth remembering for
  other vendored C APIs whose names we might mirror.
- Scratch is allocated per call at library-reported sizes (684 KB encode) --
  documented; scratch reuse and a size-prefixed container helper are Phase 2
  roadmap items.
- Run matrix: 7/7 x2 first-try; allowlisted + baseline. Pre-pilot
  placeholder files removed to git history.
- Next: `xiom.ozz` (C++ -- expect a stronger shim/args need: C++ sources via
  --c-source will need the C++ frontend; check before committing the
  approach).

## Batch 12 notes (xiom.zstd, 2026-10-08)

- Vendored path proven end-to-end for a multi-file C library: used the
  upstream `combine.py` to generate the official single-file amalgamation
  (v1.5.7), vendored it + `zstd.h` + LICENSE, and compiled it via a 4-line
  shim (`STATIC_BMI2 0`) because the xiom link line has no `-mbmi2` -- the
  first build failed exactly there and the shim fixed it without touching
  the vendored bytes.
- Real functional suite: 8192 -> 34 bytes at level 3, frame content size,
  auto-size decompress, incompressible round-trip, invalid-frame rejection.
- Line-ending trap caught: `combine.py` under Windows Python emits CRLF, so
  the committed (LF) blob differed from the first hash. Pin corrected to the
  stored LF bytes; `vendor/** -text` protects it from autocrlf (same as
  `xiom.sqlite`). Re-pin procedure now says to normalize before hashing.
- Run matrix: 8/8 x2 plus a re-run after normalization. Allowlisted +
  baseline; `port.args.json` compiles the shim; amalgamation compile ~40-60s
  (240 s watchdog headroom).
- Next: `xiom.lzfse` (small vendored C, same path), then `xiom.ozz`.

## Batch 11 notes (xiom.directx12, 2026-10-08)

- Max-level capability probe: descending `D3D12CreateDevice` attempts
  (12_2 -> 11_0); the RTX 3070 Ti accepts 12_2. The DXGI adapter
  vtables/offsets verified for directx11 were reused unchanged; the only new
  ABI is `IID_ID3D12Device` + the `D3D12CreateDevice` signature.
- Run matrix: 5/5 x2 first-try; SKIP classification (bogus sonames) every
  run. Allowlisted + baseline; `port.args.json` compiles the bridge.
- Pre-pilot module (~17 KB static D3D12 externs) removed to git history.
- Next: compression tier -- `xiom.zstd` (vendored C path; the sqlite
  `--c-source` machinery + `port.args.json` are proven, but zstd is many
  translation units: plan a `src/zstd_all.c` shim that #includes the vendored
  `lib/` sources, or vendor the official single-file amalgamation if one is
  published for the pinned release).

## Batch 10 notes (xiom.directx11, 2026-10-08)

- Header-free ABI extraction paid off again: the DXGI vtables were pinned
  from `dxgi.h` before writing the bridge (factory slot 12 = EnumAdapters1,
  adapter slot 8 = GetDesc, desc offsets 0/256/260) -- the first present-path
  run created a hardware device and read the adapter name with no iteration.
- `D3D11CreateDevice` with a NULL feature-level array returns 11_0 on this
  driver; explicit 11_1 needs a requested feature-level list (Phase 2).
- Adapter enumeration returns 3 entries on this host; the first is the
  NVIDIA RTX 3070 Ti (`vendor_id 4318` = 0x10DE, `device_id 9346` = 0x2482).
- Run matrix: 5/5 x2; SKIP classification (bogus sonames) every run.
  Allowlisted + baseline; `port.args.json` compiles the bridge.
- Pre-pilot module (22 KB static `extern "C"` D3D declarations) removed to
  git history.

## Batch 9 notes (xiom.dxc, 2026-10-08)

- Header-free COM bridge: `dxcapi.h` was read from the SDK and used as the
  specification (GUIDs + vtable slot offsets), but the bridge declares the
  ABI locally and drives `IDxcCompiler3`/`IDxcResult`/`IDxcBlob` through raw
  vtable pointers -- no SDK header or import library at build time.
- First present-path run compiled a real `ps_6_0` shader to a 2,532-byte DXIL
  object on the first try (ABI extraction paid off; a wrong slot would have
  crashed rather than failed softly).
- `dxil.dll` is not in the SDK `Bin` here; unsigned DXIL is fine for the
  capability probe (validator seam is a Phase 2 item).
- Run matrix: 3/3 x2; SKIP classification (bogus soname) every run. Already
  allowlisted; `port.args.json` compiles the bridge.
- Pre-pilot bridge (77 KB, SDK headers + import libs) removed to git history.

## Inbound checks (2026-10-08, post-batch-8: project lanes + stdlib)

- **PULSE** (`docs/PACKAGE-WISHLIST-PULSE.md` bindings section): first binding
  request is "a durable database/KV client binding (SQLite/Postgres or
  similar) to back the event store and sessions beyond JSONL". **Already
  served**: `xiom.sqlite` 0.2.0 is published (eco-v0.1.89) and is exactly that
  durable store path; PULSE keeps JSONL as its documented fallback until it
  adopts. Outbound HTTP client is explicitly "not yet needed"; TLS is
  explicitly NOT a binding (front proxy). No new work item for this lane.
- **ORBITDB**: `RELAY-PACKAGES-RESPONSE-ORBITDB.md` and
  `STDLIB-WISHLIST-ORBITDB.md` contain no bindings-lane asks ("No C-FFI
  needs", pure-XIOM target). Nothing to do.
- **XVECTOR**: `RELAY-PACKAGES.md` restates the accelerator watch
  (`xiom-blas`/`eigen`/`openblas` behind the portable `xiom.vectors` API);
  unscheduled here, no new ask.
- **Stdlib response** (`docs/BINDINGS-STDLIB-WISHLIST.md` updated):
  stdlib **0.64.2** delivered W-1 `fs_remove` (also the shared wishlist's
  2026-10-05 row) and corrected the W-4 `dl` cast note; `SafePtr`/`FFIBuffer`
  typed slot helpers pre-existed (W-2 re-scoped to a docs ask); W-3
  (guard-aware `free`) and W-5 (`Vec.with_len`) remain open.
- **Compatibility spot-check on stdlib 0.64.2**: `port.ps1` green for
  `xiom.glfw` (3/3, SKIP path) and `xiom.sqlite` (16/16). No suite changes
  needed.
- **Wave continuation**: batch 9 starts `xiom.dxc` (GPU tier: shader-compiler
  binding over the same runtime-loader + SKIP pattern), then dx11/12.

## Inbound package wishlists (2026-10-09 refresh)

- Fetched the three project-lane package wishlists (fresh, v0.64.2-era):
  `E:\xiom-projects\xiom-pulse\docs\PACKAGE-WISHLIST-PULSE.md`,
  `...\xiom-orbitdb\docs\PACKAGE-WISHLIST-ORBITDB.md`,
  `...\xiom-xvector\docs\PACKAGE-WISHLIST-XVECTOR.md`.
- Consolidated bindings-lane responses: **`docs/BINDINGS-PACKAGE-WISHLIST.md`**.
  - PULSE durable-DB ask **SERVED from the registry** (live-verified
    2026-10-09): `xiom.sqlite` 0.2.0, `xiom.libpq` 0.2.0 and `xiom.odbc`
    0.2.0 are all signed; the 0.3.0 sqlite enum restore is pending batch 22.
    Outbound HTTP is served by `xiom.http` 0.1.4 (libcurl); TLS
    not-a-binding ACKed.
  - ORBITDB: no FFI asks (pure XIOM through Phase 2) -- nothing to do.
  - XVECTOR: accelerators stay **GATED** on the `xiom.vectors` freeze
    (placeholders incubating/`unknown`); no SIMD kernel from this lane.
- Flagged to the packages/native lane: registry consumers of vendored-C
  packages (`xiom.sqlite`) need a `--c-source` build-hook story beyond the
  runner's `port.args.json`.
- Consumer-flow validation (registry installs into a scratch `XIOM_HOME`,
  v0.64.2, checksum+signature verified): `xiom.sqlite` 0.2.0 and
  `xiom.libpq` 0.2.0 both install and resolve via canonical
  `[dependencies]` (no `source-roots`). sqlite needs the explicit
  `--c-source <installed>/vendor/sqlite3.c` (gap confirmed: the shipped
  `port.args.json` is not applied by consumer builds) -- recipe in the
  package wishlist doc + the sqlite README (docs follow-up on batch 22);
  libpq runs plain with the SKIP classification.

## Phase-2 sector order proposal (Phase 1 pilot complete)

Ordered by risk retired per unit of work, stable ABIs first, each slice
proving one lane pattern already established in the pilot:

1. **Window/input tier + reuse**: finish `xiom.sdl3` Phase 2 (window/renderer/
   texture/gamepad over the loader) and add `xiom.glfw` + `xiom.raylib` with
   the same system-lib SKIP pattern. Highest ecosystem pull (the projects
   consume these first); no new lane mechanics.
2. **GPU tier**: `xiom.opengl` Phase 2 (extension loading + context
   attributes + function table) then `xiom.vulkan` (bridge precedent already
   exists in-repo; loader + capabilities first), then `directx11/12` and
   `dxc` (Windows-only, keep the same classification model).
3. **Compression tier**: `xiom.zstd`, `xiom.lzfse`, `xiom.ozz` -- vendored-C
   path (proven by sqlite) with per-package `port.args.json`; smallest
   per-package effort, high publish value.
4. **Data/drivers**: `xiom.libpq`, `xiom.odbc` (system-lib SKIP or vendored
   client), after the sqlite pattern is already published.
5. **Audio tier**: `xiom.miniaudio`, `xiom.portaudio`, `xiom.phonon` --
   system-lib SKIP shape; device paths capability-gated.
6. **Accelerators (XVECTOR/ORBITDB-facing)**: `xiom.openblas`/`xiom.eigen`/
   `xiom.blas` behind a portable pure-XIOM contract (XVECTOR's `xiom.vectors`
   seam), unscheduled until the projects freeze that contract; no pure-XIOM
   SIMD kernel is planned in the bindings lane (position recorded in the
   inbound-context section).
7. **Crypto/media/heavy**: `xiom.openssl`, `xiom.ffmpeg`
   (license-conditional), `onnx`/`opencv` -- last, per the plan's phasing.

Each package keeps: G0-G5 gates, green x2 through `port.ps1`, a relay block
in this file, and any new compiler finding appended to
`docs/BINDINGS-COMPILER-FINDINGS.md` with a bounded repro.

## Next (state at 2026-10-09, batch 23 pushed)

- Batch 23 (`xiom.box2d` 0.2.0 + `xiom.imgui` 0.2.0) is relayed and pushed:
  waiting on the native merge/verify/publish. Batches 21+22 are PUBLISHED
  (`eco-v0.1.122`, main `96e249f2`); `xiom.jolt` v5.6.0 is pinned + its
  generator validated but blocked on the link-line C++ standard passthrough
  ask (see the batch-23 relay).
- Pin matrix re-run done: 19/19 green on the official v0.64.2 pin. The
  B-01 workaround is retired; B-05/B-10 workarounds stay in force; B-08
  probing may trust exit codes from v0.64.2 on (port.ps1 keeps marker
  counting for older pins).
- Physics/UI roster: `box2d` + `imgui` done (batch 23); `jolt` blocked on
  the standard flag; `assimp`/`vma` and the heavy runtimes
  (`xiom.onnx`/`xiom.opencv`) remain -- heavy runtimes need the native
  lane's go-ahead (last per the sector order, separate decision),
  accelerators stay GATED on XVECTOR freezing `xiom.vectors`.
- Lane copy of the compiler relay: `docs/BINDINGS-COMPILER-RELAY-2026-10-09-v0.64.2.md`.
- PULSE/ORBITDB/XVECTOR package wishlists fetched and answered
  (`docs/BINDINGS-PACKAGE-WISHLIST.md`); no new in-lane work items
  (accelerators stay gated on `xiom.vectors`). Registry consumer flow for
  the DB bindings validated end-to-end (sqlite `--c-source` recipe + libpq
  plain); batch-22 docs follow-up adds the sqlite README consumer section.
  Revalidated on the published artifacts: sqlite 0.3.0 PASS, ffmpeg 0.2.0
  SKIP, libpq 0.2.0 SKIP (scratch `XIOM_HOME`, checksums matched).
