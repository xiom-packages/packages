# xiom.v4l -- README

Video4Linux2 (V4L2) camera capture bindings for XIOM -- the Raspberry Pi
camera leg of the bindings program.  0.1.0 declares the **full UAPI surface
of the pinned kernel header** `include/uapi/linux/videodev2.h` and its
transitive include chain (`v4l2-common.h` + `v4l2-controls.h`) and ships a
self-contained ioctl bridge that drives a real V4L2 capture pipeline on
Linux.

- **2079 constants** -- every `VIDIOC_*` ioctl number (83) and every
  public `V4L2_*` value from the pinned `videodev2.h` + `v4l2-common.h`
  (`xiom.v4l.consts`, 841) and the entire `v4l2-controls.h` control-ID
  universe (`xiom.v4l.cids`, 1238: `V4L2_CID_*` 492, decoder/encoder
  control sets, `V4L2_CTRL_*` classes/flags, AV1/HEVC/VP9/H264 stateless
  codec structs' companion constants).
- **1028 struct-layout facts** over **122 `v4l2_*` structs**
  (`xiom.v4l.layout`): every `sizeof` and every field `offsetof`, LP64.
- **29 function-like UAPI macros** mirrored as pure XIOM functions
  (`v4l2_fourcc`, `V4L2_TYPE_IS_*`, `V4L2_FIELD_*`, `V4L2_MAP_*`,
  `V4L2_CTRL_ID2*`, `V4L2_DV_BT_*`, H264/VP8/VP9/AV1 helpers).
- **Functional capture head** (`xiom.v4l`): probe/QUERYCAP enumeration,
  G_FMT/S_FMT negotiation, REQBUFS/QUERYBUF/mmap/QBUF/DQBUF streaming,
  STREAMON/OFF, frame copy, typed errors.

Every value and layout is **evaluated by gcc against the pinned kernel
text** -- nothing is transcribed by hand.  See PROVENANCE.md for the pin
(`torvalds/linux` v6.19, light sparse clone; UAPI syscall-exception
license note) and `docs/repro/` for the generator, the raw dump, the
3107-fact `_Static_assert` gate and the recorded probe runs.

## Platform

| Platform | Device layer | Suite result |
|---|---|---|
| Linux (x86_64, aarch64/Pi) | `/dev/videoN` + kernel ioctls | live path when a camera is present; ABSENT (SKIP) when not |
| Windows (host) | none by construction | SKIP (`V4L_LOAD_ABSENT`; recorded) |

V4L2 is a Linux-only ioctl UAPI: there is **no runtime library and no
vendored code**.  On Windows the probe classifies `V4L_LOAD_ABSENT` and the
suite takes the recorded SKIP path; the declared surface (constants,
layouts, macro mirrors, ABI self-check) is still fully exercised there.

## Quick start

```xiom
use xiom.v4l;
use xiom.v4l.consts;
use xiom.v4l.layout;

fn main() -> Int {
    let rt = v4l_probe();                    // Result[V4lRuntime, V4lError]
    if rt.is_err {
        io.println("no camera: " + rt.error.message);
        return 0;                            // V4L_LOAD_ABSENT == SKIP leg
    }
    let dev = v4l_open(0);                   // first probed node
    if dev.is_err { return 1; }
    let caps = v4l_querycap(&dev.value);
    if caps.is_ok {
        io.println("driver=" + caps.value.driver + " card=" + caps.value.card
                 + " caps=0x" + to_string(caps.value.capabilities));
    }
    let fmt = v4l_get_format(&dev.value);    // driver's current G_FMT
    if fmt.is_ok {
        io.println("default " + to_string(fmt.value.width) + "x"
                 + to_string(fmt.value.height)
                 + " " + v4l_fourcc_str(fmt.value.pixelformat));
    }
    // negotiation + streaming
    let sf = v4l_set_format(&dev.value, 640, 480, V4L2_PIX_FMT_YUYV, V4L2_FIELD_ANY);
    if sf.is_err { v4l_close(&dev.value); return 2; }
    let n = v4l_request_buffers(&dev.value, 4, V4L2_BUF_TYPE_VIDEO_CAPTURE, V4L2_MEMORY_MMAP);
    if n.is_err { v4l_close(&dev.value); return 3; }
    var i = 0;
    while i < n.value {
        let q = v4l_query_buffer(&dev.value, i);
        if q.is_ok { let m = v4l_mmap_buffer(&dev.value, i); if m.is_err { return 4; } }
        let w = v4l_queue_buffer(&dev.value, i);
        if w.is_err { return 5; }
        i = i + 1;
    }
    let on = v4l_stream_on(&dev.value, V4L2_BUF_TYPE_VIDEO_CAPTURE);
    if on.is_ok {
        let frame = v4l_grab_frame(&dev.value, 5000);   // DQBUF + copy + QBUF
        if frame.is_ok { io.println("frame bytes: " + to_string(frame.value.len())); }
        let off = v4l_stream_off(&dev.value, V4L2_BUF_TYPE_VIDEO_CAPTURE);
    }
    v4l_munmap_buffers(&dev.value);
    v4l_close(&dev.value);
    return 0;
}
```

## Model

- **Classification** (mirrors the bindings-lane policy):
  `V4L_LOAD_ABSENT` = no device layer -- the suite records SKIP;
  `V4L_LOAD_ABI` = pinned ABI facts broken -- FAIL, never a silent SKIP;
  `V4L_CALL` = a live ioctl failed, `errno` captured and named
  (`v4l_last_errno`, `v4l_errno_name`).
- **Pointers never cross the boundary** (B-25): devices are opaque `Int`
  handles, mmap addresses stay C-side, frame bytes move through
  caller-owned `Vec[UInt8]` (`v4l_read_frame` / `v4l_grab_frame`).
- **ABI strategy**: the bridge pins every ioctl number and struct layout
  from the generated dump and re-derives them at runtime
  (`v4l_abi_check()`); on Linux the same bridge compiles against the real
  pinned headers under the 3107-fact `_Static_assert` gate
  (`docs/repro/`).

## Suite

```powershell
$env:XIOM_COMPILER = "$env:LOCALAPPDATA\xiom.new\bin\xiom.exe"
.\scripts\port.ps1 -Package xiom.v4l -TimeoutSec 300
```

14 checks: ioctl/caps/FOURCC/CID/string constants, layout facts, all 29
macro mirrors, errno naming, the ABI self-check, the two deterministic
SKIP-path probes, the `/dev` probe classification (live path on a camera
host), and teardown.  On the Windows host the device runtimes are absent by
construction and the suite records the SKIP leg; on Linux
(`docs/repro/run-linux-abi-probe.sh`) the bridge builds against the pinned
UAPI headers and the recorded classification output is the same SKIP leg
until a camera node exists -- the Pi arm64 story is documented in
ROADMAP.md.

## Layout

```
package.xi                  package manifest (modules: xiom.v4l + 3 const/layout modules)
v4l.xi                      module xiom.v4l -- functional head + macro mirrors
src/v4l2_bridge.c           portable ioctl bridge (pinned ABI, Linux live path, Windows ABSENT)
src/consts.xi               GENERATED: videodev2.h + v4l2-common.h constants (841)
src/cids.xi                 GENERATED: v4l2-controls.h constants (1238)
src/layout.xi               GENERATED: struct sizes + field offsets (1028 facts / 122 structs)
tests/test_conformance.xi   the suite (14 checks)
docs/repro/gen-v4l2-consts.ps1        the generator (pinned header -> modules)
docs/repro/uapi-shim/                 headers_install-equivalent parse overlay
docs/repro/gen/                       dump + coverage table + 3107-assert gate (evidence)
docs/repro/v4l2_abi_probe.c           Linux repro probe (real pinned headers)
docs/repro/run-linux-abi-probe.sh     build + run the probe (WSL/CI/Pi)
```
