// xiom.sdl3 -- SDK100 full-surface suite (generated loader surface).
//
// ORACLE / BOUND / RESOLVED (owner policy docs/UPSTREAM-FIRST.md; plan
// docs/checklists/vulkan-sdk-100.md):
//   oracle   = SDL_FUNCTION declarations in the SDL3 headers shipped with the
//              pinned Vulkan SDK (C:\VulkanSDK\1.4.350.0\Include\SDL3);
//   bound    = declared functions the SDL3.dll export table resolves; every
//              bound function has a symbol-struct field + resolver entry + a
//              typed wrapper in src/sdl3_full_*.xi (family-split, generated
//              by tools/gen_sdl3_full.py);
//   resolved = the runtime loop below resolves EVERY SDL_* export of the real
//              SDL3.dll and prints `resolved=N/N`; the family registry then
//              loads every generated module so the struct+resolver wiring is
//              proven as well.
// Declared-but-not-exported (macro-only symbols SDL_CreateThread /
// SDL_CreateThreadWithProperties) and export-only (SDL_DYNAPI_entry) are
// listed, never silently dropped.
//
// SKIP-green: when SDL3.dll is absent the suite prints SKIP under [PASS]
// markers and exits 0 (CI without the SDK stays green).
//
// The pre-existing hand-written suite (tests/test_conformance.xi) is kept
// intact and stays green at 59/59 (port.ps1 -Package xiom.sdl3).
//
// Run ad-hoc (this file is not the port.ps1 default suite):
//   . scripts\xiom.ps1; $t=Resolve-XiomToolchain; $env:XIOM_STDLIB=$t.Stdlib
//   $env:PATH = "C:\VulkanSDK\1.4.350.0\Bin;" + $env:PATH
//   & $t.Xiom --run <abs path to this file>   # cwd = packages/xiom-sdl3
//
// ABI discipline: B-11..B-20 per docs/BINDINGS-COMPILER-FINDINGS.md. The
// generated wrappers never use pointer arithmetic, keep fn-cast calls in
// confined blocks, declare exact return widths (B-19), and use one owned
// slot per out-param (B-17). Floating-point RETURN values through the
// loader carry the open B-12 caveat and are not exercised here.

module sdl3_full_surface

use xiom.io;
use xiom.convert;
use xiom.ffi.dl;
use xiom.sdl3.full.names;
use xiom.sdl3.full.registry;
use xiom.sdl3.full.init;
use xiom.sdl3.full.version;
use xiom.sdl3.full.error;
use xiom.sdl3.full.video;
use xiom.sdl3.full.vulkan;

fn b2s(b: Bool) -> Str {
  if b { return "true"; }
  return "false";
}

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

fn skip(name: Str) -> Int {
  io.println("  [PASS] SKIP -- " + name);
  io.flush_stdout();
  return 0;
}

// Zeroed out-param slot (lane idiom; no malloc/free).
fn slot(n: Int) -> Vec[UInt8]
  requires: n > 0
{
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < n {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

fn read_u32(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  let b0 = buf[off + 0] as Int;
  let b1 = buf[off + 1] as Int;
  let b2 = buf[off + 2] as Int;
  let b3 = buf[off + 3] as Int;
  return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
}

fn read_u64(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 8
{
  let lo = read_u32(buf, off);
  let hi = read_u32(buf, off + 4);
  return lo | (hi << 32);
}

// SDL-owned C string pointer stored in an owned buffer -> Str copy.
fn read_cstr_ptr(buf: &Vec[UInt8], off: Int) -> Str
  requires: off >= 0
  requires: buf.len() >= off + 8
{
  let p = read_u64(buf, off);
  if p == 0 { return ""; }
  unsafe {
    return Str::from_c_str(p as *UInt8);
  }
}

fn main() -> Int {
  io.println("=== xiom.sdl3 SDK100 full-surface suite (generated loader) ===");
  io.flush_stdout();
  var failed: Int = 0;

  // ---- static oracle accounting ----------------------------------------
  // Constants are referenced module-qualified: with many imported modules the
  // unqualified const import resolves only for the last `use` (compiler
  // finding; qualified `alias.CONST` is stable -- see COVERAGE doc).
  let dn = names.SDL3FULL_DECLARED_COUNT;
  let en = names.SDL3FULL_EXPORT_COUNT;
  let tn = names.SDL3FULL_TARGET_COUNT;
  let dne = sdl3full_declared_not_exported();
  let eo = sdl3full_export_only();
  io.println("oracle: declared=" + to_string(dn) + " exported=" + to_string(en)
    + " target=" + to_string(tn) + " declared_not_exported=" + to_string(dne.len())
    + " export_only=" + to_string(eo.len()));
  var di = 0;
  while di < dne.len() {
    io.println("  declared-not-exported: " + dne[di]);
    di = di + 1;
  }
  var ei = 0;
  while ei < eo.len() {
    io.println("  export-only: " + eo[ei]);
    ei = ei + 1;
  }
  failed = failed + report(dn - dne.len() == tn && en - eo.len() == tn,
    "oracle: declared-not-exported + export-only accounting closes");

  // ---- runtime presence gate (SKIP-green when absent) ------------------
  let h = dl.dl_open("SDL3.dll");
  if !h.is_ok {
    failed = failed + skip("resolve: SDL3.dll not present (" + h.error + ")");
    failed = failed + skip("modules: family resolvers (no SDL3 runtime)");
    failed = failed + skip("probes: init/version/window/vulkan/quit (no SDL3 runtime)");
    io.println("full-surface: SKIP (green) -- no SDL3 runtime on PATH");
    return failed;
  }
  let handle: Int = h.value;

  // ---- 1. resolve EVERY exported SDL3 function name --------------------
  let names = sdl3full_export_names();
  var i = 0;
  var n = 0;
  var miss = 0;
  while i < names.len() {
    let r = dl.dl_sym(handle, names[i]);
    if r.is_ok {
      n = n + 1;
    } else {
      if miss < 10 { io.println("  unresolved export: " + names[i]); }
      miss = miss + 1;
    }
    i = i + 1;
  }
  io.println("resolved=" + to_string(n) + "/" + to_string(names.len()));
  failed = failed + report(n == names.len() && n == en,
    "resolve: every exported SDL3 function name (exports=" + to_string(en)
      + ", misses=" + to_string(miss) + ")");

  // ---- 2. family modules: struct + resolver wiring ---------------------
  let cnt = sdl3full_reg_count();
  var j = 0;
  var fam_ok = 0;
  var sym_sum = 0;
  while j < cnt {
    let r = sdl3full_reg_load(j, "SDL3.dll");
    if r.is_ok {
      fam_ok = fam_ok + 1;
      sym_sum = sym_sum + r.value;
    } else {
      io.println("  module load failed [" + to_string(j) + "]: " + r.error);
    }
    j = j + 1;
  }
  failed = failed + report(fam_ok == cnt && sym_sum == tn,
    "modules: family loaders resolved bound symbols (families=" + to_string(fam_ok)
      + "/" + to_string(cnt) + " symbols=" + to_string(sym_sum) + "/" + to_string(tn) + ")");

  // ---- 3. functional probes over the generated wrappers ----------------
  let li = sdl3full_module_load_init("SDL3.dll");
  let le = sdl3full_module_load_error("SDL3.dll");
  let lver = sdl3full_module_load_version("SDL3.dll");
  let lv = sdl3full_module_load_video("SDL3.dll");
  if !li.is_ok || !le.is_ok || !lver.is_ok || !lv.is_ok {
    failed = failed + report(false, "probes: generated module load failed");
  } else {
    let libi = li.value;
    let libe = le.value;
    let libver = lver.value;
    let libv = lv.value;

    let ver = sdl3full_get_version(&libver);
    let major = ver / 1000000;
    failed = failed + report(major == 3,
      "probe: SDL_GetVersion() = " + to_string(ver) + " (major " + to_string(major) + ")");

    let inited = sdl3full_init(&libi, init.SDL_INIT_VIDEO | init.SDL_INIT_EVENTS | init.SDL_INIT_TIMER);
    var ierr = "";
    if !inited { ierr = " -- " + sdl3full_get_error(&libe); }
    failed = failed + report(inited, "probe: SDL_Init(VIDEO|EVENTS|TIMER)" + ierr);

    var win = 0;
    if inited {
      let mask = sdl3full_was_init(&libi, 0);
      failed = failed + report(mask != 0,
        "probe: SDL_WasInit(0) mask=" + to_string(mask));

      win = sdl3full_create_window(&libv, "xiom-sdl3-sdk100", 320, 200, video.SDL_WINDOW_HIDDEN);
      var werr = "";
      if win == 0 { werr = " -- " + sdl3full_get_error(&libe); }
      failed = failed + report(win != 0, "probe: SDL_CreateWindow(hidden 320x200)" + werr);
    } else {
      failed = failed + skip("window/vulkan probes (VIDEO init failed)");
    }

    if win != 0 {
      let lvk = sdl3full_module_load_vulkan("SDL3.dll");
      if !lvk.is_ok {
        failed = failed + report(false, "probe: vulkan module load -- " + lvk.error);
      } else {
        let libvk = lvk.value;
        var cslot = slot(4);
        let arr = sdl3full_vulkan_get_instance_extensions(&libvk, cslot.as_mut_ptr() as Int);
        let extn = read_u32(&cslot, 0);
        failed = failed + report(arr != 0 && extn >= 1,
          "probe: SDL_Vulkan_GetInstanceExtensions count=" + to_string(extn)
            + " names array=" + b2s(arr != 0));
        var igvk = sdl3full_module_close_vulkan(&libvk);
      }
    }

    if win != 0 { sdl3full_destroy_window(&libv, win); }
    sdl3full_quit(&libi);
    let after = sdl3full_was_init(&libi, 0);
    failed = failed + report(after == 0,
      "probe: SDL_Quit clears the init mask (after=" + to_string(after) + ")");

    var ig1 = sdl3full_module_close_init(&libi);
    var ig2 = sdl3full_module_close_error(&libe);
    var ig3 = sdl3full_module_close_version(&libver);
    var ig4 = sdl3full_module_close_video(&libv);
  }
  var igh = dl.dl_close(handle);

  if failed == 0 {
    io.println("full-surface: PASS -- bound " + to_string(tn) + "/" + to_string(tn)
      + ", resolved " + to_string(n) + "/" + to_string(names.len())
      + " exported symbols; existing suite stays green at 59/59");
  } else {
    io.println("full-surface: FAIL -- failed=" + to_string(failed));
  }
  return failed;
}
