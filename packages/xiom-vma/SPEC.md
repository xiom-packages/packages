# SPEC: xiom.vma -- Vulkan Memory Allocator bindings (vendored header + pinned core headers)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.vma` |
| Version | 0.2.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream projects | Vulkan Memory Allocator -- https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator; Vulkan-Headers -- https://github.com/KhronosGroup/Vulkan-Headers |
| Upstream versions | VMA **v3.4.0**; Vulkan-Headers tag **vulkan-sdk-1.4.350.0** |
| Upstream licenses | VMA MIT (`vendor/LICENSE-vma.txt`); Vulkan-Headers Apache-2.0 + MIT files (`vendor/LICENSE-vulkan.md`, `vendor/LICENSES/`) |
| Package license | MIT OR Apache-2.0 (everything outside `vendor/`) |
| Platform | Windows x64 (the loader `vulkan-1.dll` is dlopen'd at runtime) |
| Compiler pin | v0.64.2 |

## 2. Vendored path (G2 pin)

- `vendor/vk_mem_alloc.h` -- VMA v3.4.0 **unmodified except one documented
  rewrite**: `#include <vulkan/vulkan.h>` becomes
  `#include "vulkan/vulkan.h"` (the xiom link line has no `-I` passthrough;
  the quoted form resolves against the header's own directory).
- `vendor/vulkan/{vulkan.h, vulkan_core.h, vk_platform.h}` +
  `vendor/vulkan/vk_video/*.h` -- the pinned Vulkan-Headers **core**; the
  platform headers are not vendored (their `VK_USE_PLATFORM_*` guards stay
  off). `vulkan_core.h` includes `"vk_video/..."` relative to its own
  directory. `vulkan_core.h` is byte-identical to the `xiom.vulkan` pin
  (`6D2BA475...`).
- The only compiled TU is our bridge (`src/vma_bridge.cpp`, defines
  `VMA_IMPLEMENTATION`, `VMA_STATIC_VULKAN_FUNCTIONS 0`,
  `VMA_DYNAMIC_VULKAN_FUNCTIONS 1`) via `port.args.json`. Every Vulkan entry
  point is fetched at runtime via `vkGetInstanceProcAddr` from
  `LoadLibraryA("vulkan-1.dll")`; no SDK, no import library.
- **RESULT SHAPE**: the bridge returns a **packed int**
  (`(heap << 20) | (verify << 28) | size`; negative = `-classification`)
  instead of writing out-param slots. Rationale: slot memory written by this
  Vulkan-heavy call was observed recycled before XIOM could read it
  (finding **B-11**; the slot-call variant is kept in the bridge purely as
  the reproduction, see `docs/repro/bindings-pilot/vulkan-slot-recycle/`).

### Pinned archives

| Artifact | Value |
|----------|-------|
| VMA download | https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator/archive/refs/tags/v3.4.0.tar.gz |
| VMA size / SHA256 | 1,002,168 B / `822AA850C6CE77346AE96A8A1D351D52E77E85929F35363849A0A4E638E0A2A1` |
| Vulkan-Headers download | https://github.com/KhronosGroup/Vulkan-Headers/archive/refs/tags/vulkan-sdk-1.4.350.0.tar.gz |
| Vulkan-Headers size / SHA256 | 3,271,466 B / `70270D10BF2C1E074A06EE37A50B75D332993D1B80A1D9526EEED2DA6D82ED22` |

### Re-pin procedure

1. Download the new tags and record their SHA256; verify before extracting.
2. Re-copy `vk_mem_alloc.h`, the three core headers, and `vk_video/*`.
3. Re-apply the one-line include rewrite (diff will show exactly one line).
4. Recompute the per-file table below; update the version rows in this SPEC,
   `README.md`, `AUDIT.md`, and the version expectation in the suite (none
   is asserted against the header -- the probe reports live values).
5. Re-run `scripts/port.ps1 -Package xiom.vma` x2 and record `STATUS.json`.

### Per-file SHA256 (vendor tree)

```
vendor/LICENSE-vma.txt                                    52DF2C03D6CFC9FFEC13C9D3626C530FC9CE0CBE41D5EA3D10CD46EDEB1AEB38
vendor/LICENSE-vulkan.md                                  AC24E5EA920E4318E4D02C4086AE51F53CFB03FEED06C18DF1019E7ADA1EC7BC
vendor/LICENSES/Apache-2.0.txt                            CFC7749B96F63BD31C3C42B5C471BF756814053E847C10F3EB003417BC523D30
vendor/LICENSES/MIT.txt                                   1CA3502222D967F3BE5751C55F6B7EE735B5383909C3B501495F54B216DBF227
vendor/vk_mem_alloc.h                                     40933E7E7F3FB38F24DFEA921EDD0FDB25738F120E0C7D43F4C89F5C7B68F8FD
vendor/vulkan/vk_platform.h                               949D517BB83E1D88FD4F1CEF02BD3CB9AB50D44E8354CC68227CF2DCCFDD3307
vendor/vulkan/vulkan.h                                    72B952CC6DE70EE12D118D3095E80346B42FF01CFC6F2BBB37EC01800EAB1DA6
vendor/vulkan/vulkan_core.h                               6D2BA4755774B1D129DA6B8E661268B494D2D609DF6217C6B6485ACF7666B6C2
vendor/vulkan/vk_video/vulkan_video_codecs_common.h       BE6D2495D19E96ACA6AA5C11E5C418D1CD72BEAC23FE19EB9169C06E2843F0AF
vendor/vulkan/vk_video/vulkan_video_codec_av1std.h        9B4EBCEF0D6844B226803FA91B4C4C8BF9EB941AA31B19CEA48DED0886A8F9E2
vendor/vulkan/vk_video/vulkan_video_codec_av1std_decode.h F03ABF49FCAF2BD179D48D768164F9494264B58401B98899E8860BA297A1E7AA
vendor/vulkan/vk_video/vulkan_video_codec_av1std_encode.h 40F84C98D0341246EAD3E864E1378DF47D861505C5C139DA5ED85C352D5E2300
vendor/vulkan/vk_video/vulkan_video_codec_h264std.h       F6691F82E4637ADDA20E56D56951C673CC1ECDF2FA77E09CC8EBA4B1F45118C1
vendor/vulkan/vk_video/vulkan_video_codec_h264std_decode.h 8C4682860954D6BFC603E200D9E12586BC57265BD37B73A12B1ECF0C1AD42721
vendor/vulkan/vk_video/vulkan_video_codec_h264std_encode.h 75CC54E489B1EC7E3C635680CABAF7C9C2DDD4071A485440E5368E76EDE30A85
vendor/vulkan/vk_video/vulkan_video_codec_h265std.h       01B5F3D0FD9D273A68ED90F898BA94C05C0305280A753BF95FAB60D60727C22E
vendor/vulkan/vk_video/vulkan_video_codec_h265std_decode.h 926A24D94AFED2B1AB030E81C3B9E2E6730CCA530F7A5A5BD821E7B896B93A41
vendor/vulkan/vk_video/vulkan_video_codec_h265std_encode.h 8A56E0C78496AFFA84ECA39EC0F5636DF681C04623DD0291AEEADD012DF324BE
vendor/vulkan/vk_video/vulkan_video_codec_vp9std.h        E18E20B197945929D5871836BFDE923E38B350B09E1CBE430F1BD802D9EDA34E
vendor/vulkan/vk_video/vulkan_video_codec_vp9std_decode.h C3929BBDD0AB79128C7F9BFB9641C9A017B3983529315B771CAAAFC74FDBB89A
```

## 3. Design and safe boundary (G5)

`vma.xi` is the only module with `unsafe`/`extern "C"`; it calls the
integer-only bridge and decodes the packed result. There are no out-param
slots (finding B-11 workaround; see the repro bundle). Classification:
loader missing / no physical device / no queue -> SKIP; step failures ->
FAIL. `vma_probe_named` with a bogus module name exercises the SKIP path
deterministically on every host. No malloc/free from XIOM (B-05).

## 4. Test contract

Suite: `tests/test_conformance.xi` -- 5 checks: SKIP classification (bogus
module), live probe (or SKIP without a device), allocation size == 65536,
mapped pattern write/read-back verified, heap count > 0.

Command (cwd = this package directory; the runner hook adds the C source):

```
scripts/port.ps1 -Package xiom.vma
```

Watchdog: allow >=180 s (one C++ TU with the VMA implementation; ~5-10 s on
the development machine).

## 5. Scope

Pilot: allocator lifecycle + one host-visible 64 KiB buffer with a mapped
pattern check on the live device. Sub-allocation APIs (`vmaCreateAliasing*`,
pools), defragmentation, device-local streaming, and integration examples
with `xiom.vulkan` are Phase 2 (`ROADMAP.md`). The pre-pilot static-extern
surface is preserved in git history.
