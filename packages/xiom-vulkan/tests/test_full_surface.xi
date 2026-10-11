// xiom.vulkan SDK100 full-surface loadability suite (generated loader).
//
// Proves the generated surface resolves EVERY Windows-relevant vk.xml command
// on a real loader: 845 desktop commands (740 real + 105 alias; 7 vulkansc
// twins excluded at generation) of which N are platform-foreign by loader
// design (platform attr != win32 or Vulkan SC-only, generated exclusion set).
// The instance/device are created with EVERY loader/driver-supported extension
// enabled so every extension command resolves through
// vkGetInstanceProcAddr / vkGetDeviceProcAddr (with an instance fallback).
// SKIP (green) when the loader or an instance/device is absent.
//
// Run (repo root):
//   . scripts\xiom.ps1; $t=Resolve-XiomToolchain; $env:XIOM_STDLIB=$t.Stdlib
//   & $t.Xiom --run <this file abs path> [port.args.json args]
// (The package runner compiles src/vk_probe.c + src/vk_rhi.c via port.args.json.)

module vulkan_full_surface

use xiom.io;
use xiom.convert;
use xiom.dl;
use xiom.vulkan;
use xiom.vulkan.api;
use xiom.vulkan.names;
use xiom.vulkan.cmds_01;

fn main() -> Int {
  let rc = unsafe { xr_load("vulkan-1.dll".c_str()) as Int };
  if rc != 0 {
    io.println("full-surface: SKIP (loader absent, code=" + to_string(rc) + ")");
    return 0;
  }
  let ir = unsafe { xr_instance_all_ext() as Int };
  if ir != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    io.println("full-surface: SKIP (no instance/ICD: " + msg + ")");
    return 0;
  }
  let pr = unsafe { xr_pick_device() as Int };
  if pr != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    io.println("full-surface: SKIP (no device/ICD: " + msg + ")");
    return 0;
  }
  let dr = unsafe { xr_create_device_all_ext() as Int };
  if dr != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    io.println("full-surface: FAIL (device create all-ext: " + msg + ")");
    return 1;
  }

  var ih: Int = 0;
  var dh: Int = 0;
  unsafe {
    ih = xr_instance_handle() as Int;
    dh = xr_device_handle() as Int;
  }
  let at = vk_api_load_full("vulkan-1.dll", ih, dh);
  if !at.is_ok {
    io.println("full-surface: FAIL (vk_api_load_full: " + at.error + ")");
    unsafe { xr_destroy(); xr_unload(); }
    return 1;
  }
  let api = at.value;

  let cmd_names = vk_cmd_names();
  let cmd_classes = vk_cmd_classes();
  let cmd_excl = vk_cmd_excluded();
  let cmd_groups = vk_cmd_groups();
  var i = 0;
  var n_g = 0;
  var n_i = 0;
  var n_d = 0;
  var n_excl = 0;
  var n_excl_hit = 0;
  var n_unavail = 0;
  var miss = 0;
  while i < cmd_names.len() {
    let cls = cmd_classes[i];
    let ex = cmd_excl[i];
    if ex == 1 { n_excl = n_excl + 1; }
    var p = 0;
    unsafe {
      if cls == VK_CLASS_GLOBAL {
        p = vk_api_resolve_global(&api, cmd_names[i].c_str());
        if p == 0 {
          let r = dl.dl_sym(api.loader, cmd_names[i]);
          if r.is_ok { p = r.value; }
        }
      }
      if cls == VK_CLASS_INSTANCE { p = vk_api_resolve_instance(&api, cmd_names[i].c_str()); }
      if cls == VK_CLASS_DEVICE {
        p = vk_api_resolve_device(&api, cmd_names[i].c_str());
        if p == 0 { p = vk_api_resolve_instance(&api, cmd_names[i].c_str()); }
      }
    }
    if p == 0 {
      if ex == 1 {
        n_excl_hit = n_excl_hit + 1;
      } else {
        let grp = cmd_groups[i];
        let adv_i = unsafe { xr_ext_present(grp.c_str()) as Int };
        let adv_d = unsafe { xr_dev_ext_present(grp.c_str()) as Int };
        if adv_i == 0 && adv_d == 0 {
          n_unavail = n_unavail + 1;
          if n_unavail < 25 { io.println("  loader-unavailable: " + cmd_names[i] + " (ext " + grp + " not advertised)"); }
        } else {
          if miss < 40 { io.println("  unresolved: " + cmd_names[i] + " (ext " + grp + " advertised)"); }
          miss = miss + 1;
        }
      }
    }
    if cls == VK_CLASS_GLOBAL { n_g = n_g + 1; }
    if cls == VK_CLASS_INSTANCE { n_i = n_i + 1; }
    if cls == VK_CLASS_DEVICE { n_d = n_d + 1; }
    i = i + 1;
  }
  let total = cmd_names.len();
  let relevant = total - n_excl;
  io.println("commands=" + to_string(total)
    + " excluded=" + to_string(n_excl) + " (platform-foreign/SC)"
    + " loader_unavailable=" + to_string(n_unavail) + " (ext not advertised)"
    + " relevant=" + to_string(relevant)
    + " unresolved_relevant=" + to_string(miss)
    + " excluded_unresolved=" + to_string(n_excl_hit)
    + " globals=" + to_string(n_g) + " instance=" + to_string(n_i) + " device=" + to_string(n_d));
  io.println("resolved=" + to_string(total - miss - n_excl_hit - n_unavail) + "/" + to_string(total));

  var vrcd: Int = 0;
  var ver: Int = 0;
  unsafe {
    var slot: Vec[UInt8] = Vec[UInt8].new();
    var k = 0;
    while k < 4 { slot.push(0 as UInt8); k = k + 1; }
    vrcd = vk_enumerate_instance_version(&api, slot.as_mut_ptr()) as Int;
    ver = (slot[0] as Int) | ((slot[1] as Int) << 8) | ((slot[2] as Int) << 16) | ((slot[3] as Int) << 24);
  }
  io.println("vk_enumerate_instance_version rc=" + to_string(vrcd) + " apiVersion=" + to_string(ver));

  vk_api_unload(&api);
  unsafe { xr_destroy(); xr_unload(); }

  if miss != 0 { return 1; }
  if vrcd != 0 { return 1; }
  if ver == 0 { return 1; }
  io.println("full-surface: PASS (all " + to_string(relevant - n_unavail - miss) + " advertised-surface commands resolved; " + to_string(n_excl) + " platform-foreign excluded by design; " + to_string(n_unavail) + " extensions not advertised by this loader)");
  return 0;
}
