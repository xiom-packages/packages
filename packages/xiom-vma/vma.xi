// XIOM -- xiom.vma: Vulkan Memory Allocator 3.4.0 bindings (vendored header).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: vendored header-only path.  `vendor/vk_mem_alloc.h` (unmodified
// except ONE documented include rewrite: `<vulkan/vulkan.h>` ->
// `"vulkan/vulkan.h"`, see SPEC.md section 2) plus the pinned
// Vulkan-Headers core (vendor/vulkan/) compile into the test binary through
// our bridge (src/vma_bridge.cpp, the only --c-source TU).  The Vulkan
// loader (vulkan-1.dll) is dlopen'd at runtime; no SDK, no import library.
//
// RESULT SHAPE: the bridge returns a PACKED int -- `(heap << 20) |
// (verify << 28) | size`, negative on failure/skip -- instead of writing
// out-param slots.  Rationale: slot memory written by this Vulkan-heavy
// call was observed recycled before XIOM could read it under the v0.64.2
// runtime (finding B-11; the slot variant is kept in the bridge as the
// repro).  All `unsafe`/`extern "C"` live in this single module (G5).
//
// Classification: loader missing / no device / no graphics queue -> SKIP;
// step failures -> FAIL.  The deterministic SKIP path is exercisable on any
// host via `vma_probe_named` with a bogus module name.
//
// G2 pin (SPEC.md): VMA v3.4.0 archive SHA256 + Vulkan-Headers
// vulkan-sdk-1.4.350.0 archive SHA256 + per-file table.

module xiom.vma

extern "C" {
  fn vmaprobe_run_packed() -> Int32;
  fn vmaprobe_run_packed_named(dll: *UInt8) -> Int32;
}

pub const VMA_LOAD_ABSENT: Int = 0;   // loader module missing -> SKIP
pub const VMA_NO_DEVICE: Int = 1;     // no physical device / no queue -> SKIP
pub const VMA_PROBE_FAILED: Int = 2;  // a probe step failed -> FAIL

pub type VmaLoadError = {
  kind: Int;
  message: Str;
}

pub type VmaInfo = {
  heap_count: Int;
  alloc_size: Int;
  verify: Int;   // 1 when the mapped write/read-back pattern verified
}

/// Run the full probe on the default loader (`vulkan-1.dll`): instance ->
/// device -> VMA allocator -> 64 KiB host-visible buffer -> mapped pattern
/// write/read-back -> cleanup.
/// Complexity: O(allocation).
pub fn vma_probe() -> Result[VmaInfo, VmaLoadError]
  requires: true
{
  let packed = unsafe { vmaprobe_run_packed() as Int };
  return vma_decode(packed);
}

/// Same probe against an explicitly named loader module -- the deterministic
/// SKIP classification path (pass a bogus name on any host).
/// Complexity: O(allocation).
pub fn vma_probe_named(dll: Str) -> Result[VmaInfo, VmaLoadError]
  requires: dll.len() > 0
{
  let packed = unsafe { vmaprobe_run_packed_named(dll.c_str()) as Int };
  return vma_decode(packed);
}

// ---- internals -----------------------------------------------------------

fn vma_classify(rc: Int) -> VmaLoadError
  requires: rc != 0
{
  if rc == 100 {
    return VmaLoadError{ kind: VMA_LOAD_ABSENT; message: "vulkan loader module not found"; };
  }
  if rc == 101 {
    return VmaLoadError{ kind: VMA_NO_DEVICE; message: "no Vulkan physical device"; };
  }
  if rc == 102 {
    return VmaLoadError{ kind: VMA_NO_DEVICE; message: "no graphics queue family"; };
  }
  return VmaLoadError{ kind: VMA_PROBE_FAILED; message: "probe step rc=" + vma_i2s(rc); };
}

fn vma_decode(packed: Int) -> Result[VmaInfo, VmaLoadError]
  requires: true
{
  if packed < 0 {
    return Err(vma_classify(0 - packed));
  }
  return Ok(VmaInfo{
    heap_count: (packed >> 20) & 255;
    alloc_size: packed & 1048575;
    verify: (packed >> 28) & 1;
  });
}

fn vma_i2s(n: Int) -> Str
  requires: n >= 0
{
  if n == 0 { return "0"; }
  var val = n;
  var buf = "";
  while val > 0 {
    let digit = val % 10;
    val = val / 10;
    if digit == 0 { buf = "0" + buf; }
    elif digit == 1 { buf = "1" + buf; }
    elif digit == 2 { buf = "2" + buf; }
    elif digit == 3 { buf = "3" + buf; }
    elif digit == 4 { buf = "4" + buf; }
    elif digit == 5 { buf = "5" + buf; }
    elif digit == 6 { buf = "6" + buf; }
    elif digit == 7 { buf = "7" + buf; }
    elif digit == 8 { buf = "8" + buf; }
    elif digit == 9 { buf = "9" + buf; }
  }
  return buf;
}
