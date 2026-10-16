# xiom.v4l -- PROVENANCE

## Oracle (pinned upstream)

- Repository: `https://github.com/torvalds/linux`
- Tag / commit: **v6.19** = `05f7e89ab9731565d8a62e3b5d1ec206485eeb0b`
  (tagged 2026-02-08; resolved 2026-10-16)
- Clone: **light sparse clone, no history blobs, exactly the needed UAPI
  files** (`E:\repos\linux-uapi-v6.19`; registered in `E:\repos\CLEANUP.md`):

  ```
  git clone --depth 1 --branch v6.19 --filter=blob:none --sparse \
      https://github.com/torvalds/linux E:\repos\linux-uapi-v6.19
  git sparse-checkout set --no-cone \
      /include/uapi/linux/videodev2.h /include/uapi/linux/v4l2-common.h \
      /include/uapi/linux/v4l2-controls.h /include/uapi/linux/bits.h \
      /include/uapi/linux/types.h /include/uapi/linux/ioctl.h \
      /include/uapi/linux/stddef.h /include/uapi/linux/const.h \
      /include/uapi/asm-generic/ /arch/x86/include/uapi/asm/
  ```

- Declared surface = the userspace view of `#include <linux/videodev2.h>`
  at the pin, including its transitive includes `v4l2-common.h` and
  `v4l2-controls.h` (header line counts in SPEC.md).

## License: UAPI syscall exception

The V4L2 UAPI headers are `GPL-2.0 WITH Linux-syscall-note`
(`include/uapi/linux/videodev2.h` SPDX: `GPL-2.0 WITH Linux-syscall-note`).
The syscall note permits use of these UAPI headers by programs without
infecting them with the GPL:

> "NOTE! This copyright does *not* cover user programs that use kernel
> services by normal system calls - this is merely considered normal use of
> the kernel, and does *not* fall under the heading of 'derived work'."

`xiom.v4l` contains **no vendored runtime library and no copied upstream
header text in the package sources**.  What it contains:

- compiler-evaluated numeric facts (constant values, struct sizes/offsets)
  -- interface facts, derived via the generator (see below), and
- `src/v4l2_bridge.c`, an original XIOM-authored C unit that implements the
  ABI (ioctl numbers, LP64 layouts) and the syscall path.  It is a
  clean-room interface implementation written from the same pinned header
  text, licensed `MIT OR Apache-2.0` like the rest of the package.
- `docs/repro/uapi-shim/linux/compiler.h` -- an original 3-line overlay
  (defines `__user` empty) needed to parse the pinned header verbatim; see
  below.

## Evaluation methodology (no hand transcription)

1. **Name universe** -- `gcc -E -dM` on a probe including
   `<linux/videodev2.h>` yields every macro visible to userspace;
   `V4L2_*`/`VIDIOC_*` names are taken (function-like macros recorded
   separately, 29).  Enum members come from the preprocessed text.
2. **Values** -- a generated C dumper prints every constant
   (`(long long)(NAME)`) and every `sizeof`/`offsetof` fact;
   the raw output is committed as `docs/repro/gen/v4l2_consts_dump.txt`
   (3105 lines: 2077 integer constants + 1028 layout facts).
3. **Gate** -- the same facts become `_Static_assert`s
   (`gen/v4l2_const_asserts.h`, 3107 assertions incl. the 2 string
   constants) that are compiled against the pinned headers by
   `docs/repro/v4l2_abi_probe.c`; the recorded run
   (`gen/v4l2-linux-abi-probe.txt`) shows the whole gate compiling and the
   runtime classification on Linux.
4. **Ownership split** -- names defined in `videodev2.h`/`v4l2-common.h` go
   to `xiom.v4l.consts`; names owned by `v4l2-controls.h` go to
   `xiom.v4l.cids`; struct facts to `xiom.v4l.layout`.  The generator
   asserts 100% coverage against the evaluated name set (it throws on any
   name it cannot place).

### Upstream quirks handled (recorded, minimal, principled)

- **`#include <linux/compiler.h>`**: the pinned `videodev2.h` (line 63)
  includes `linux/compiler.h`, which is **not** in the UAPI tree at the
  pin (`git ls-tree v6.19 include/uapi/linux/compiler.h` is empty).
  Upstream userspace never sees this line: `scripts/headers_install.sh`
  strips kernel-internal includes and the `__user` annotation (Ubuntu's
  installed header has neither).  `docs/repro/uapi-shim/linux/compiler.h`
  is an original overlay that provides the same empty surface, so the
  pinned header parses **verbatim** in the repro toolchain.
- **`GENMASK`**: `V4L2_FWHT_FL_COMPONENTS_NUM_MSK` and
  `V4L2_FWHT_FL_PIXENC_MSK` are `GENMASK(...)` expressions in
  `v4l2-controls.h`; the pinned `include/uapi/linux/bits.h` provides
  `__GENMASK`, and the kernel's `include/linux/bits.h` defines
  `GENMASK(h,l) = __GENMASK(h,l)` (its `__ASSEMBLY__` branch; the C branch
  computes the identical value for the two literal argument pairs).  The
  dumper and assert gate pre-define the same equivalence -- from the same
  pinned commit.
- **String-valued defines**: `V4L2_MPEG_VBI_IVTV_MAGIC0/1` are string
  literals; they are declared as XIOM `Str` constants taken from the
  pinned text and gated by `sizeof` comparison (never cast to integers).

## Recorded evidence

| Evidence | File |
|---|---|
| Raw evaluated dump (3105 facts) | `docs/repro/gen/v4l2_consts_dump.txt` |
| 3107-assert gate source | `docs/repro/gen/v4l2_const_asserts.h` |
| Family/count coverage table | `docs/repro/gen/v4l2_coverage.tsv` |
| Generated dumper source | `docs/repro/gen/v4l2_values_dumper.c` |
| Linux repro probe + recorded run (ABI green; `/dev` ABSENT SKIP) | `docs/repro/v4l2_abi_probe.c`, `gen/v4l2-linux-abi-probe.txt` |
| Windows suite runs (SKIP leg live-recorded) | STATUS.json (tests block, two consecutive runs) |
| Generator | `docs/repro/gen-v4l2-consts.ps1` |

Reproduce: run `docs/repro/gen-v4l2-consts.ps1` (needs the clone above +
WSL gcc) for the dump/modules/asserts; run
`docs/repro/run-linux-abi-probe.sh` for the Linux gate; run
`scripts/port.ps1 -Package xiom.v4l` for the suite.

## Runtime story

- **No runtime library**: the device layer is the kernel itself
  (`/dev/videoN` + ioctl).  Nothing is vendored, nothing is dlopen'd.
- **Windows host**: no V4L2 device layer exists; the probe classifies
  `V4L_LOAD_ABSENT` by construction and the suite takes the recorded SKIP
  leg (standing policy).
- **Linux (incl. Raspberry Pi arm64)**: the same bridge drives the real
  pipeline.  The pinned layouts are LP64 and identical between x86_64 and
  aarch64 for every struct in the declared surface; the Pi drill (arm64
  gcc build of the bridge, live capture against the Pi camera stack) is the
  0.2.0 roadmap item -- the Windows-side suite and the WSL probe both
  record the SKIP classification until such a node exists.
