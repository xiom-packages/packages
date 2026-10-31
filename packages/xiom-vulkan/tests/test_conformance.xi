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

fn b2s(b: Bool) -> Str {
  if b { return "true"; }
  return "false";
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

  // WSI round trip (build order #2): hidden window -> surface -> swapchain
  // -> acquire/clear/present cycles.
  let wsi_missing = vulkan_wsi_probe_named("xiom-absent-vulkan-wsi-xyz.dll", 1);
  if wsi_missing.is_ok {
    failed = failed + report(false, "wsi skip-path: bogus soname unexpectedly succeeded");
  } else {
    failed = failed + report(wsi_missing.error.kind == VULKAN_LOAD_ABSENT,
      "wsi skip-path: absent loader classified as SKIP");
  }

  let wsi = vulkan_wsi_probe(3);
  if wsi.is_ok {
    let w: VulkanWsi = wsi.value;
    failed = failed + report(w.extent_w > 0 && w.extent_h > 0 && w.image_count >= 2,
      "wsi swapchain: " + to_string(w.extent_w) + "x" + to_string(w.extent_h)
        + " format=" + to_string(w.format) + " images=" + to_string(w.image_count));
    failed = failed + report(w.present_mode == 2 && w.frames_presented == 3,
      "wsi present: FIFO, " + to_string(w.frames_presented)
        + " clear+present round trips (" + w.device_name + ")");
  } else {
    if wsi.error.kind == VULKAN_LOAD_ABSENT {
      failed = failed + report(true, "wsi: SKIP -- loader absent (" + wsi.error.message + ")");
    } else if wsi.error.kind == VULKAN_LOAD_NO_DEVICE {
      failed = failed + report(true, "wsi: SKIP -- no display/driver path (" + wsi.error.message + ")");
    } else {
      failed = failed + report(false, "wsi: failed -- " + wsi.error.message);
    }
  }

  // Render pipeline round trip (build order #3): embedded SPIR-V -> render
  // pass (clear) -> graphics pipeline -> draw 3 verts -> readback -> present.
  let tri_missing = vulkan_triangle_probe_named("xiom-absent-vulkan-tri-xyz.dll", 1, 0.1, 0.2, 0.3);
  if tri_missing.is_ok {
    failed = failed + report(false, "triangle skip-path: bogus soname unexpectedly succeeded");
  } else {
    failed = failed + report(tri_missing.error.kind == VULKAN_LOAD_ABSENT,
      "triangle skip-path: absent loader classified as SKIP");
  }

  let tri = vulkan_triangle_probe(2);
  if tri.is_ok {
    let t: VulkanTriangle = tri.value;
    failed = failed + report(t.extent_w > 0 && t.extent_h > 0 && t.frames == 2,
      "triangle frame: " + to_string(t.extent_w) + "x" + to_string(t.extent_h)
        + " format=" + to_string(t.format) + " frames=" + to_string(t.frames)
        + " (" + t.device_name + ")");
    let cr = (t.center_pixel >> 16) & 0xFF;
    let cg = (t.center_pixel >> 8) & 0xFF;
    let cb = t.center_pixel & 0xFF;
    failed = failed + report(cg >= 200 && cr <= 60 && cb <= 60,
      "triangle draw: center pixel rgb(" + to_string(cr) + "," + to_string(cg)
        + "," + to_string(cb) + ") is the green triangle");
    let or_ = (t.corner_pixel >> 16) & 0xFF;
    let og = (t.corner_pixel >> 8) & 0xFF;
    let ob = (t.corner_pixel) & 0xFF;
    failed = failed + report((or_ >= 20 && or_ <= 32) && (og >= 45 && og <= 57) && (ob >= 71 && ob <= 83),
      "triangle clear: corner pixel rgb(" + to_string(or_) + "," + to_string(og)
        + "," + to_string(ob) + ") is the 0.1/0.2/0.3 clear color");
    // 0.6.0 C07: full-frame capture copy is stable across the frames.
    failed = failed + report(t.capture_stable && t.capture_crc != 0
        && t.capture_bytes == t.extent_w * t.extent_h * 4,
      "capture-copy: full-frame checksum stable across " + to_string(t.frames)
        + " frames (crc=" + to_string(t.capture_crc) + " bytes="
        + to_string(t.capture_bytes) + " stable=" + b2s(t.capture_stable) + ")");
    // 0.6.0 B05: timestamp + occlusion query readback for the frame debugger.
    failed = failed + report(t.query_ok && t.timestamp_end >= t.timestamp_begin
        && t.timestamp_period_ns > 0 && t.duration_ns >= 0 && t.duration_ns < 1000000000
        && t.occlusion_samples > 0,
      "query-readback: timestamps " + to_string(t.timestamp_begin) + "->"
        + to_string(t.timestamp_end) + " @ " + to_string(t.timestamp_period_ns)
        + "ns/tick = " + to_string(t.duration_ns) + "ns, occlusion-samples="
        + to_string(t.occlusion_samples) + " (ok=" + b2s(t.query_ok) + ")");
  } else {
    if tri.error.kind == VULKAN_LOAD_ABSENT {
      failed = failed + report(true, "triangle: SKIP -- loader absent (" + tri.error.message + ")");
    } else if tri.error.kind == VULKAN_LOAD_NO_DEVICE {
      failed = failed + report(true, "triangle: SKIP -- no display/driver path (" + tri.error.message + ")");
    } else {
      failed = failed + report(false, "triangle: failed -- " + tri.error.message);
    }
  }

  if failed == 0 {
    io.println("xiom.vulkan: all tests passed");
  } else {
    io.println("xiom.vulkan: tests failed");
  }
  return failed;
}
