# xiom.v4l -- ROADMAP

## 0.1.0 (this wave) -- DONE

- Pinned oracle: `torvalds/linux` v6.19 (`05f7e89a...`), light sparse clone
  (UAPI files only; registered in `E:\repos\CLEANUP.md`).
- Full declared surface: 2079 constants (2077 int + 2 string) + 1028
  struct-layout facts over 122 `v4l2_*` structs + 29 function-like macro
  mirrors, all compiler-evaluated from the pinned text with a 3107-assert
  gate and a committed raw dump + coverage table.
- Functional head: probe/QUERYCAP enumeration; G_FMT/S_FMT negotiation;
  REQBUFS/QUERYBUF/mmap/QBUF/DQBUF(+poll) streaming; STREAMON/OFF; frame
  copy; typed errors; runtime ABI self-check.
- SKIP-leg evidence on both hosts: Windows suite runs (recorded) + Linux
  WSL repro probe against the real pinned headers (recorded).

## 0.2.0 candidates (priority order)

1. **Pi arm64 runtime drill** -- build the bridge with aarch64 gcc on the
   Pi, run the live path against the camera stack, record the run
   (`docs/repro/`), and flip the platform row to the live-recorded state.
   Structure-of-record: `run-linux-abi-probe.sh <pkg> <kernel>` is already
   target-agnostic; the drill adds a `recorded-pi-arm64.txt`.
2. **Multi-planar capture** (`V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE`):
   `v4l2_plane`/`v4l2_pix_format_mplane` value flow + plane-aware
   QBUF/DQBUF; all constants and layouts are already declared and gated.
3. **Format enumeration**: `VIDIOC_ENUM_FMT` (+ `v4l2_fmtdesc`),
   `VIDIOC_ENUM_FRAMESIZES`/`ENUM_FRAMEINTERVALS` (+ `v4l2_frmsizeenum`),
   `VIDIOC_G_PARM` (stream parameters).
4. **Controls**: `VIDIOC_G_CTRL`/`S_CTRL` + `VIDIOC_QUERYCTRL`/
   `QUERY_EXT_CTRL` over the declared 1238-value CID universe
   (`v4l2_ext_control` value transport through the B-25 discipline).
5. **Events**: `VIDIOC_SUBSCRIBE_EVENT`/`DQBUF`(event queue)/`DQEVENT`
   (frame events, source-change), typed event records.
6. **DMABUF import/export** (`V4L2_MEMORY_DMABUF`, `VIDIOC_EXPBUF`) --
   the Pi zero-copy path.
7. **CI camera leg**: v4l2loopback (or vivid) virtual device in a Linux CI
   container so the *live path* itself becomes a recorded suite run --
   turns the SKIP leg into a live gate without hardware.
8. **Platform token**: declare a `linux-arm64` platform row once the token
   exists in `docs/PLATFORM-MATRIX.md` (currently only `linux-x64` is in
   the vocabulary; the Pi runtime story is documented in PROVENANCE.md).

## Explicit non-goals (kept out, documented)

- Media-controller graph (media device enumeration, `MEDIA_IOC_*`) --
  separate UAPI (`media.h`), separate package decision.
- Full codec control syntax helpers (H264/VP9/AV1 stateless parameter
  round-trips): constants and struct facts are declared; value-level
  builders ride a controls wave (item 4).
- libcamera/V4L2 M2M compliance harnesses -- out of binding scope.
