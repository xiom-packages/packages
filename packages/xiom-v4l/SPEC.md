# xiom.v4l -- SPEC

Video4Linux2 (V4L2) camera capture bindings, 0.1.0.  V4L2 is a Linux-only
`ioctl(2)` UAPI: there is **no runtime library**.  The "surface" is the
`#include <linux/videodev2.h>` translation unit -- an ioctl/const set plus
struct layouts -- and the functional head over those ioctls.

## Oracle

| Oracle | Path at the pin |
|---|---|
| Primary header | `include/uapi/linux/videodev2.h` (2841 lines) |
| Transitive | `include/uapi/linux/v4l2-common.h` (71), `include/uapi/linux/v4l2-controls.h` (3523) |
| Support | `include/uapi/linux/bits.h`, `linux/types.h`, `linux/ioctl.h` (pinned tree) |
| Pin | `torvalds/linux` **v6.19** = `05f7e89ab9731565d8a62e3b5d1ec206485eeb0b`, light sparse clone (`--filter=blob:none`, UAPI files only) |
| Evaluation | gcc (WSL Ubuntu, x86_64 LP64) against the pinned text; dump = `docs/repro/gen/v4l2_consts_dump.txt`; hard gate = `docs/repro/gen/v4l2_const_asserts.h` (3107 assertions, compiled by `docs/repro/v4l2_abi_probe.c` and by the bridge itself under `-DXV_USE_REAL_UAPI`) |

Every declared number was produced by the compiler from the pinned header
text (macros expanded, `v4l2_fourcc(...)` evaluated, ioctl encodings
resolved with the ABI's struct sizes); no hand transcription is involved.
`docs/repro/gen-v4l2-consts.ps1` regenerates the modules, the dump, the
coverage table and the assert gate from the clone.

## Declared surface (100% declared == 100% evaluated == 100% gated)

| Cluster | Module | Count | Gate |
|---|---|---|---|
| `VIDIOC_*` ioctl numbers | `xiom.v4l.consts` | 83 | dump + assert + suite spots (functional 9 + enumeration/negotiation/control families) |
| `V4L2_PIX_FMT_*` FOURCCs | `xiom.v4l.consts` | 254 | dump + assert + suite spots + `v4l2_fourcc` round-trip |
| `V4L2_CAP_*` capability bits | `xiom.v4l.consts` | 32 | dump + assert + suite spots |
| `V4L2_STD_*` / `V4L2_TUNER_*` | `xiom.v4l.consts` | 46 + 32 | dump + assert |
| buffer types/memory/field/flags | `xiom.v4l.consts` | 15 + 5 + 10 + 22 + 9 | dump + assert + suite spots |
| colorspace machinery (`COLORSPACE`/`XFER_FUNC`/`YCBCR_ENC`/`QUANTIZATION`/`HSV_ENC`) | `xiom.v4l.consts` | 14 + 9 + 9 + 3 + 2 | dump + assert + suite spots |
| control classes/flags/types (header-owned) | `xiom.v4l.consts` | 15 + 38 + 5 | dump + assert + suite spots |
| event / DV / selection / sliced-VBI / meta / other small families | `xiom.v4l.consts` | remainder of 841 | dump + assert |
| string-valued defines (`V4L2_MPEG_VBI_IVTV_MAGIC0/1`) | `xiom.v4l.consts` | 2 | pinned-text literal + suite |
| `V4L2_CID_*` control-ID universe | `xiom.v4l.cids` | 492 | dump + assert + suite spots |
| decoder/encoder control sets (`V4L2_MPEG_*` 297, `V4L2_AV1_*` 111, `V4L2_HEVC_*` 61, `V4L2_VP9_*` 44, `V4L2_H264_*` 42, ...) | `xiom.v4l.cids` | remainder of 1238 | dump + assert |
| struct layouts (`v4l2_*`) | `xiom.v4l.layout` | 1028 facts / 122 structs | dump + assert + suite spots |
| function-like macros | `xiom.v4l` | 29 | transcribed from the pinned text + repro build |

Totals: **2079 constants** (2077 integer + 2 string) + **1028 layout
facts** + **29 macro mirrors**.  Family/count table:
`docs/repro/gen/v4l2_coverage.tsv`.

Two `v4l2-controls.h` macros (`V4L2_FWHT_FL_COMPONENTS_NUM_MSK`,
`V4L2_FWHT_FL_PIXENC_MSK`) are `GENMASK(...)` expressions; the pinned UAPI
tree provides `__GENMASK` in `include/uapi/linux/bits.h`, and the
evaluation pre-defines `GENMASK(h,l) = __GENMASK(h,l)` exactly as the
pinned `include/linux/bits.h` does for its assembler branch -- recorded in
the dumper and PROVENANCE.md.

## Functional head (module `xiom.v4l` over `src/v4l2_bridge.c`)

| Capability | Calls | ioctls |
|---|---|---|
| Probe/enumerate | `v4l_probe`, `v4l_probe_named`, `v4l_device_count`, `v4l_device_path` | `VIDIOC_QUERYCAP` per `/dev/videoN` (0..63) |
| Identity | `v4l_open`, `v4l_open_path`, `v4l_querycap`, `v4l_close`, `v4l_close_all`, `v4l_effective_caps`, `v4l_supports_capture`, `v4l_version_*` | `VIDIOC_QUERYCAP` |
| Format negotiation | `v4l_get_format`, `v4l_set_format`, `v4l_format` | `VIDIOC_G_FMT`, `VIDIOC_S_FMT` (single-planar `V4L2_BUF_TYPE_VIDEO_CAPTURE`) |
| Buffer I/O | `v4l_request_buffers`, `v4l_query_buffer`, `v4l_mmap_buffer`, `v4l_munmap_buffers`, `v4l_queue_buffer`, `v4l_dequeue_buffer`, `v4l_read_frame`, `v4l_grab_frame` | `VIDIOC_REQBUFS` (MMAP), `VIDIOC_QUERYBUF`, `mmap(2)`, `VIDIOC_QBUF`, `poll(2)`+`VIDIOC_DQBUF` |
| Streaming | `v4l_stream_on`, `v4l_stream_off` | `VIDIOC_STREAMON`, `VIDIOC_STREAMOFF` |
| Diagnostics | `v4l_abi_check`, `v4l_error`, `v4l_last_errno`, `v4l_errno_name`, `v4l_platform_supported` | -- |

Typed errors: `V4lError { kind, errno_code, message }` with
`V4L_LOAD_ABSENT` (SKIP leg) / `V4L_LOAD_ABI` (FAIL leg) / `V4L_CALL`
(errno-carrying).  DQBUF timeouts surface as `V4L_CALL` with `EAGAIN`
(11) via the bridge's `-3` sentinel.

Explicit non-goals of 0.1.0 (all constants declared; functional coverage
follows on the roadmap): multi-planar buffer flow (`*_MPLANE`), format
enumeration (`VIDIOC_ENUM_FMT`/framesizes), controls get/set, events
(`VIDIOC_SUBSCRIBE_EVENT`), DMABUF (`V4L2_MEMORY_DMABUF`), output/overlay/
SDR/VBI streams, media-controller graphs.

## ABI strategy (three layers)

1. **Generated one-shot gate**: `gen/v4l2_const_asserts.h` -- all 3107
   facts as `_Static_assert` against the pinned headers (compiled by
   `docs/repro/v4l2_abi_probe.c`; evidence recorded in
   `gen/v4l2-linux-abi-probe.txt`).
2. **Bridge-local gate**: `src/v4l2_bridge.c` `_Static_assert`s pin the
   ioctl numbers and the struct definitions it actually uses; the Linux
   repro build adds layer 1 through `-DXV_USE_REAL_UAPI`.
3. **Runtime self-check**: `v4l_abi_check()` re-derives every pinned ioctl
   encoding (dir/type/nr/size quadruples), struct size and key field offset
   at run time on every host; any drift fails the suite
   (`V4L_LOAD_ABI`), never a silent SKIP.

## Classification and the SKIP leg

`probe -> Ok(devices>0)` runs the live path; `-> Err(V4L_LOAD_ABSENT)`
records SKIP; `-> Err(V4L_LOAD_ABI)` fails.  Deterministic SKIP evidence on
both hosts:

- Windows (this host): probe classifies ABSENT by construction; suite
  records the SKIP leg (see the recorded port runs in STATUS.json).
- Linux (WSL x86_64): `docs/repro/run-linux-abi-probe.sh` builds the
  bridge against the pinned UAPI headers, all 3107 asserts compile, the
  runtime self-check is green, and `/dev` classifies ABSENT (no video
  nodes) -- recorded in `gen/v4l2-linux-abi-probe.txt`.
- Raspberry Pi (arm64): same recipe with aarch64 gcc; when a camera node
  exists the suite's live path (G_FMT -> S_FMT -> REQBUFS -> mmap ->
  STREAMON -> DQBUF -> frame copy -> STREAMOFF) runs instead of the SKIP
  leg.  The bridge's pinned layouts are LP64 (x86_64 == aarch64 for every
  struct in the declared surface); see ROADMAP.md for the drill plan.
