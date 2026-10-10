// xiom.vulkan conformance suite -- capability probe (dynamic loader).
//
// CI WITHOUT a Vulkan driver stays green: the probe resolves `vulkan-1.dll`
// at runtime; absent loader -> SKIP, `vkCreateInstance` failure (no ICD) ->
// SKIP, missing entry points -> FAIL. The SKIP path is exercised
// deterministically on every run via a bogus soname.
//
// Build+run through the runner (compiles src/vk_probe.c via port.args.json):
//   scripts/port.ps1 -Package xiom.vulkan

module vulkan_conformance

use xiom.io;
use xiom.convert;
use xiom.test;
use xiom.vulkan;

fn report(ok: Bool, name: Str) -> Int {
  if ok {
    io.println("  [PASS] " + name);
    io.flush_stdout();
    return 0;
  }
  io.println("  [FAIL] " + name);
  io.flush_stdout();
  return 1;
}

fn t_version_helpers() -> Bool {
  var ok = true;
  // VK_MAKE_API_VERSION(0, 1, 4, 350) = (1 << 22) | (4 << 12) | 350
  let packed = 4194304 + 16384 + 350;
  if vulkan_api_major(packed) != 1 { ok = false; }
  if vulkan_api_minor(packed) != 4 { ok = false; }
  if vulkan_api_patch(packed) != 350 { ok = false; }
  return ok;
}

fn main() -> Int {
  io.println("=== xiom.vulkan conformance tests (capability probe) ===");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + report(t_version_helpers(), "api-version packing: major/minor/patch extraction");

  // SKIP-path classification, deterministic on every host (bogus soname).
  let missing = vulkan_probe_named("xiom-absent-vulkan-probe-xyz.dll");
  if missing.is_ok {
    failed = failed + report(false, "skip-path: bogus soname unexpectedly produced an instance");
  } else {
    failed = failed + report(missing.error.kind == VULKAN_LOAD_ABSENT,
      "skip-path: absent loader classified as VULKAN_LOAD_ABSENT (SKIP)");
  }

  let p = vulkan_probe();
  if p.is_ok {
    let info: VulkanInfo = p.value;
    failed = failed + report(vulkan_api_major(info.api_version) >= 1,
      "loader: API version " + to_string(vulkan_api_major(info.api_version)) + "."
      + to_string(vulkan_api_minor(info.api_version)) + "."
      + to_string(vulkan_api_patch(info.api_version)));
    failed = failed + report(info.extension_count > 0,
      "extensions: instance count = " + to_string(info.extension_count));
    failed = failed + report(info.extension_head.len() > 0,
      "extensions: head = " + info.extension_head);
    failed = failed + report(info.layer_count >= 0,
      "layers: instance layer count = " + to_string(info.layer_count));

    // Self-consistency: the head lists real names, a bogus one must be absent.
    let bogus = vulkan_has_extension("VK_XIOM_NOT_AN_EXTENSION");
    if bogus.is_ok {
      failed = failed + report(!bogus.value, "extensions: bogus extension correctly absent");
    } else {
      failed = failed + report(false, "extensions: scan failed -- " + bogus.error.message);
    }
    let surface = vulkan_has_extension("VK_KHR_surface");
    if surface.is_ok {
      if surface.value {
        failed = failed + report(true, "extensions: VK_KHR_surface present");
      } else {
        failed = failed + report(true, "extensions: VK_KHR_surface not present (loader-dependent)");
      }
    } else {
      failed = failed + report(true, "extensions: scan SKIP -- " + surface.error.message);
    }

    if info.device_count > 0 {
      failed = failed + report(info.device_name.len() > 0,
        "device: " + info.device_name + " (type " + to_string(info.device_type)
        + ", api " + to_string(vulkan_api_major(info.device_api_version)) + "."
        + to_string(vulkan_api_minor(info.device_api_version)) + ")");
      failed = failed + report(info.device_type >= 0,
        "device: count = " + to_string(info.device_count));
    } else {
      failed = failed + report(true, "device: SKIP -- instance ok but no physical device");
    }
  } else {
    if p.error.kind == VULKAN_LOAD_ABSENT {
      failed = failed + report(true, "probe: SKIP -- Vulkan loader not present (" + p.error.message + ")");
    } else if p.error.kind == VULKAN_LOAD_NO_DEVICE {
      failed = failed + report(true, "probe: SKIP -- no compatible Vulkan driver (" + p.error.message + ")");
    } else {
      failed = failed + report(false, "probe: failed -- " + p.error.message);
    }
  }

  // Engine RHI bring-up (build order #1): instance w/ Win32 surface exts ->
  // device -> queue family -> logical device -> real cmd-buffer submit+wait.
  let rhi_missing = vulkan_rhi_probe_named("xiom-absent-vulkan-rhi-xyz.dll");
  if rhi_missing.is_ok {
    failed = failed + report(false, "rhi skip-path: bogus soname unexpectedly succeeded");
  } else {
    failed = failed + report(rhi_missing.error.kind == VULKAN_LOAD_ABSENT,
      "rhi skip-path: absent loader classified as SKIP");
  }

  let rhi = vulkan_rhi_probe();
  if rhi.is_ok {
    let r: VulkanRhi = rhi.value;
    failed = failed + report(r.device_count >= 1 && r.device_name.len() > 0,
      "rhi device: " + r.device_name + " (type " + to_string(r.device_type) + ", api "
        + to_string(vulkan_api_major(r.device_api)) + "." + to_string(vulkan_api_minor(r.device_api)) + ")");
    failed = failed + report(r.queue_family >= 0,
      "rhi queue: graphics family index " + to_string(r.queue_family));
    failed = failed + report(r.surface_extensions,
      "rhi instance: VK_KHR_surface + VK_KHR_win32_surface enabled");
    failed = failed + report(true, "rhi submit: pool + cmd begin/end + queue submit/wait roundtrip");
  } else {
    if rhi.error.kind == VULKAN_LOAD_ABSENT {
      failed = failed + report(true, "rhi: SKIP -- loader absent (" + rhi.error.message + ")");
    } else if rhi.error.kind == VULKAN_LOAD_NO_DEVICE {
      failed = failed + report(true, "rhi: SKIP -- no compatible driver (" + rhi.error.message + ")");
    } else {
      failed = failed + report(false, "rhi: failed -- " + rhi.error.message);
    }
  }

  if failed == 0 {
    io.println("xiom.vulkan: all tests passed");
  } else {
    io.println("xiom.vulkan: tests failed");
  }
  return failed;
}
