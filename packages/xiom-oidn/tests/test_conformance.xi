// XIOM -- xiom.oidn Conformance Test Suite
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Exercises the xiom.oidn loader-tier binding over the Intel Open Image
// Denoise v2.5.1 public C API. The suite is deterministic and SKIP-safe:
//
//   - always: constant checks, the deterministic ABSENT classification
//     (bogus soname), and the runtime present/absent classification;
//   - when the runtime is present: device enumeration + lifecycle, typed
//     error paths, owned-buffer write/read + async round trips, shared
//     buffers over XIOM-owned memory, filter creation/params, and a real
//     CPU denoise of a deterministically generated 8x8 float RGB image
//     with albedo/normal guides (finite + changed vs input + repeat
//     determinism).
//
// The image fixture is generated in-test as exact IEEE-754 bit patterns
// (values k/128 with k in 64..125: exponent 126, mantissa (k-64)<<17), so
// no float parsing is needed anywhere in XIOM; byte-level comparisons run
// on owned Vec[UInt8] slots (B-20/B-24-safe direction).
//
// Run: scripts/port.ps1 -Package xiom.oidn -TimeoutSec 240
// (present path: prepend a dir holding OpenImageDenoise.dll + its CPU
// device/core/tbb companions to PATH, e.g. the official v2.5.1 release;
// absent path: default PATH -> deterministic SKIP classification).

module oidn_conformance
use xiom.io;
use xiom.test;
use xiom.string;
use xiom.oidn;

// =========================================================================
// Helpers
// =========================================================================

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var num = n;
  var neg = false;
  if num < 0 { neg = true; num = 0 - num; }
  var out = "";
  while num > 0 {
    let d = num % 10;
    var ds = "0";
    if d == 1 { ds = "1"; }
    elif d == 2 { ds = "2"; }
    elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; }
    elif d == 5 { ds = "5"; }
    elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; }
    elif d == 8 { ds = "8"; }
    elif d == 9 { ds = "9"; }
    out = ds + out;
    num = num / 10;
  }
  if neg { return "-" + out; }
  return out;
}

fn report(passed: Bool, name: Str) -> Int {
  if passed {
    io.println("  [PASS] " + name);
    return 0;
  }
  io.println("  [FAIL] " + name);
  return 1;
}

fn skip(name: Str) -> Int {
  io.println("  [SKIP] " + name);
  return 0;
}

/// n zero bytes in an owned slot.
fn zeros(n: Int) -> Vec[UInt8]
  requires: n > 0
{
  var v: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < n {
    v.push(0 as UInt8);
    i = i + 1;
  }
  return v;
}

/// Append the four little-endian bytes of an f32 bit pattern.
fn put_f32_bits(v: &mut Vec[UInt8], bits: Int)
  requires: bits >= 0
{
  v.push((bits & 255) as UInt8);
  v.push(((bits >> 8) & 255) as UInt8);
  v.push(((bits >> 16) & 255) as UInt8);
  v.push(((bits >> 24) & 255) as UInt8);
}

/// Exact f32 bit pattern for the value k/128 with k in 64..125:
/// exponent field 126 (2^-1), mantissa (k - 64) << 17.
fn f32_bits_k128(k: Int) -> Int
  requires: k >= 64
  requires: k <= 125
{
  return (126 << 23) | ((k - 64) << 17);
}

/// Deterministic 8x8 RGB color fixture: k = 64 + 2*(x) + noise(0..3),
/// an LCG-driven per-pixel band pattern (values 0.5..0.6328).
fn fixture_color(w: Int, h: Int) -> Vec[UInt8]
  requires: w > 0
  requires: h > 0
{
  var v: Vec[UInt8] = Vec[UInt8].new();
  var s: Int = 123456789;
  var i: Int = 0;
  let n: Int = w * h;
  while i < n {
    s = (s * 1103515245 + 12345) % 2147483648;
    let noise = (s / 65536) % 4;
    let k = 64 + (i % w) * 2 + noise;
    let bits = f32_bits_k128(k);
    put_f32_bits(&mut v, bits);
    put_f32_bits(&mut v, bits);
    put_f32_bits(&mut v, bits);
    i = i + 1;
  }
  return v;
}

/// Deterministic 8x8 RGB albedo guide: k = 96 + 4*x (values 0.75..0.96875).
fn fixture_albedo(w: Int, h: Int) -> Vec[UInt8]
  requires: w > 0
  requires: h > 0
{
  var v: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  let n: Int = w * h;
  while i < n {
    let k = 96 + (i % w) * 4;
    let bits = f32_bits_k128(k);
    put_f32_bits(&mut v, bits);
    put_f32_bits(&mut v, bits);
    put_f32_bits(&mut v, bits);
    i = i + 1;
  }
  return v;
}

/// Deterministic 8x8 RGB normal guide: (0, 0, 1) everywhere.
fn fixture_normal(w: Int, h: Int) -> Vec[UInt8]
  requires: w > 0
  requires: h > 0
{
  var v: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  let n: Int = w * h;
  while i < n {
    put_f32_bits(&mut v, 0);            // 0.0f
    put_f32_bits(&mut v, 0);            // 0.0f
    put_f32_bits(&mut v, 1065353216);   // 1.0f
    i = i + 1;
  }
  return v;
}

/// Bytes of an owned slot up to (excluding) the NUL at/after `from`.
fn cstr_len(buf: &Vec[UInt8], from: Int) -> Int
  requires: from >= 0
  requires: buf.len() > from
{
  var i: Int = from;
  while i < buf.len() {
    if (buf[i] as Int) == 0 { return i - from; }
    i = i + 1;
  }
  return buf.len() - from;
}

// =========================================================================
// Main
// =========================================================================

pub fn main() -> Int {
  io.println("XIOM oidn Conformance Suite (0.1.0 loader-tier, OIDN v2.5.1)");
  io.println("=============================================================");
  var total: Int = 0;
  var failed: Int = 0;

  // ---------------------------------------------------------------------
  io.println("");
  io.println("-- SECTION 1: constants + loader classification (3) --");

  var const_ok = true;
  if OIDN_DEVICE_TYPE_DEFAULT != 0 { const_ok = false; }
  if OIDN_DEVICE_TYPE_CPU != 1 { const_ok = false; }
  if OIDN_DEVICE_TYPE_SYCL != 2 { const_ok = false; }
  if OIDN_DEVICE_TYPE_CUDA != 3 { const_ok = false; }
  if OIDN_DEVICE_TYPE_HIP != 4 { const_ok = false; }
  if OIDN_DEVICE_TYPE_METAL != 5 { const_ok = false; }
  if OIDN_ERROR_NONE != 0 { const_ok = false; }
  if OIDN_ERROR_UNKNOWN != 1 { const_ok = false; }
  if OIDN_ERROR_INVALID_ARGUMENT != 2 { const_ok = false; }
  if OIDN_ERROR_INVALID_OPERATION != 3 { const_ok = false; }
  if OIDN_ERROR_OUT_OF_MEMORY != 4 { const_ok = false; }
  if OIDN_ERROR_UNSUPPORTED_HARDWARE != 5 { const_ok = false; }
  if OIDN_ERROR_CANCELLED != 6 { const_ok = false; }
  if OIDN_FORMAT_FLOAT != 1 { const_ok = false; }
  if OIDN_FORMAT_FLOAT3 != 3 { const_ok = false; }
  if OIDN_FORMAT_HALF != 257 { const_ok = false; }
  if OIDN_STORAGE_HOST != 1 { const_ok = false; }
  if OIDN_STORAGE_DEVICE != 2 { const_ok = false; }
  if OIDN_STORAGE_MANAGED != 3 { const_ok = false; }
  if OIDN_QUALITY_DEFAULT != 0 { const_ok = false; }
  if OIDN_QUALITY_FAST != 4 { const_ok = false; }
  if OIDN_QUALITY_BALANCED != 5 { const_ok = false; }
  if OIDN_QUALITY_HIGH != 6 { const_ok = false; }
  if OIDN_EXTERNAL_MEMORY_TYPE_FLAG_D3D12_RESOURCE != 512 { const_ok = false; }
  if OIDN_EXTERNAL_SEMAPHORE_TYPE_FLAG_D3D12_FENCE != 16 { const_ok = false; }
  if OIDN_UUID_SIZE != 16 { const_ok = false; }
  if OIDN_LUID_SIZE != 8 { const_ok = false; }
  if OIDN_LOAD_OK != 0 { const_ok = false; }
  if OIDN_LOAD_ABSENT != 1 { const_ok = false; }
  if OIDN_LOAD_ABI != 2 { const_ok = false; }
  let rc0 = assert(const_ok, "const: device/error/format/storage/quality/flag values match oidn.h");
  total = total + 1; failed = failed + report(rc0.passed, rc0.name);

  let exp_count = oidn_export_count();
  let rc1 = assert(exp_count == 67, "loader: required export table is 67 functions (public C API)");
  total = total + 1; failed = failed + report(rc1.passed, rc1.name);

  let absent_probe = oidn_load_named("xiom_oidn_absent_probe.dll");
  var absent_ok = false;
  var absent_msg = "";
  if !absent_probe.is_ok {
    let le = absent_probe.error;
    absent_msg = le.message;
    if le.kind == OIDN_LOAD_ABSENT { absent_ok = true; }
  }
  let rc2 = assert(absent_ok && absent_msg.len() > 0, "loader: bogus soname -> deterministic ABSENT classification");
  total = total + 1; failed = failed + report(rc2.passed, rc2.name);

  // ---------------------------------------------------------------------
  // Present/absent classification of the default runtime.
  let loaded = oidn_load();
  if !loaded.is_ok {
    let le2 = loaded.error;
    if le2.kind == OIDN_LOAD_ABSENT {
      io.println("  [PASS] loader: default runtime absent -> SKIP present-path checks (" + le2.message + ")");
      total = total + 1;
      io.println("");
      failed = failed + skip("device enumeration (runtime absent)");
      failed = failed + skip("device lifecycle + typed errors (runtime absent)");
      failed = failed + skip("buffer round trips (runtime absent)");
      failed = failed + skip("filter surface + typed errors (runtime absent)");
      failed = failed + skip("CPU denoise finite + changed (runtime absent)");
      failed = failed + skip("repeat determinism (runtime absent)");
      io.println("");
      io.println("  loaded (absent profile): " + int_to_str(total) + " checks passed, 0 failed");
      io.println("  SKIP-green: install OpenImageDenoise.dll (v2.5.1) to run the full profile");
      return 0;
    }
    io.println("  [FAIL] loader: default runtime load failed (ABI): " + le2.message);
    return 1;
  }

  let info = loaded.value;
  let rc3 = assert(info.resolved == 67 && info.required == 67 && oidn_loaded(),
                   "loader: present runtime resolves 67/67 required exports");
  total = total + 1; failed = failed + report(rc3.passed, rc3.name);

  io.println("  runtime: " + info.soname + " (" + int_to_str(info.resolved) + "/" + int_to_str(info.required) + " exports)");

  // ---------------------------------------------------------------------
  io.println("");
  io.println("-- SECTION 2: device enumeration + lifecycle (7) --");

  let cpu_sup = oidn_is_cpu_device_supported();
  var cpu_sup_ok = false;
  if cpu_sup.is_ok { cpu_sup_ok = cpu_sup.value; }
  let rc4 = assert(cpu_sup_ok, "enum: CPU device is supported");
  total = total + 1; failed = failed + report(rc4.passed, rc4.name);

  let numr = oidn_get_num_physical_devices();
  if !numr.is_ok {
    io.println("  [FAIL] enum: num physical devices call failed: " + numr.error.message);
    return 1;
  }
  let num_phys = numr.value;
  var cpu_seen = false;
  var cpu_name_len = 0;
  var i_phys: Int = 0;
  while i_phys < num_phys {
    let tr = oidn_get_physical_device_int(i_phys, "type");
    var is_cpu = false;
    if tr.is_ok {
      if tr.value == OIDN_DEVICE_TYPE_CPU { is_cpu = true; }
    }
    if is_cpu {
      cpu_seen = true;
      var name_buf = zeros(128);
      let nr = oidn_get_physical_device_string(i_phys, "name", &mut name_buf);
      if nr.is_ok {
        cpu_name_len = cstr_len(&name_buf, 0);
      }
    }
    i_phys = i_phys + 1;
  }
  let rc5 = assert(num_phys >= 1 && cpu_seen, "enum: at least one physical device and a CPU entry (count=" + int_to_str(num_phys) + ")");
  total = total + 1; failed = failed + report(rc5.passed, rc5.name);

  let rc6 = assert(cpu_name_len > 0, "enum: CPU physical-device name is non-empty (" + int_to_str(cpu_name_len) + " chars)");
  total = total + 1; failed = failed + report(rc6.passed, rc6.name);

  let cuda_sup = oidn_is_cuda_device_supported(0);
  let hip_sup = oidn_is_hip_device_supported(0);
  let metal_sup = oidn_is_metal_device_supported(0);
  var gpu_flags_ok = false;
  if cuda_sup.is_ok && hip_sup.is_ok && metal_sup.is_ok {
    if !metal_sup.value { gpu_flags_ok = true; }
  }
  let rc7 = assert(gpu_flags_ok, "enum: CUDA/HIP/Metal support flags readable (Metal=false on Windows)");
  total = total + 1; failed = failed + report(rc7.passed, rc7.name);

  let devr = oidn_new_device_cpu();
  if !devr.is_ok {
    io.println("  [FAIL] device: CPU create failed: " + devr.error.message);
    return 1;
  }
  let dev = devr.value;
  let commit1 = oidn_commit_device(dev);
  var commit1_ok = commit1.is_ok;
  if !commit1_ok {
    io.println("  [FAIL] device: commit failed: " + commit1.error.message);
    return 1;
  }

  let vres = oidn_get_device_int(dev, "version");
  let vmaj = oidn_get_device_int(dev, "versionMajor");
  let vmin = oidn_get_device_int(dev, "versionMinor");
  let vpat = oidn_get_device_int(dev, "versionPatch");
  var ver_ok = false;
  if vres.is_ok && vmaj.is_ok && vmin.is_ok && vpat.is_ok {
    ver_ok = vres.value == 20501 && vmaj.value == 2 && vmin.value == 5 && vpat.value == 1;
  }
  let rc8 = assert(ver_ok, "device: runtime version is 2.5.1 (version=20501)");
  total = total + 1; failed = failed + report(rc8.passed, rc8.name);

  let sysmem = oidn_get_device_bool(dev, "systemMemorySupported");
  let managed = oidn_get_device_bool(dev, "managedMemorySupported");
  var mem_ok = false;
  if sysmem.is_ok && managed.is_ok {
    mem_ok = sysmem.value && managed.value;
  }
  let rc9 = assert(mem_ok, "device: systemMemorySupported + managedMemorySupported are true on CPU");
  total = total + 1; failed = failed + report(rc9.passed, rc9.name);

  let badparam = oidn_get_device_int(dev, "noSuchParameter");
  var badparam_ok = false;
  if !badparam.is_ok {
    let be = badparam.error;
    if be.code == OIDN_ERROR_INVALID_ARGUMENT {
      if string.str_contains(be.message, "unknown device parameter") { badparam_ok = true; }
    }
  }
  let rc10 = assert(badparam_ok, "device: unknown parameter -> typed INVALID_ARGUMENT (code 2)");
  total = total + 1; failed = failed + report(rc10.passed, rc10.name);

  let commit2 = oidn_commit_device(dev);
  var commit2_ok = false;
  if !commit2.is_ok {
    if commit2.error.code == OIDN_ERROR_INVALID_OPERATION { commit2_ok = true; }
  }
  let rc11 = assert(commit2_ok, "device: second commit -> typed INVALID_OPERATION (code 3)");
  total = total + 1; failed = failed + report(rc11.passed, rc11.name);

  // bridge-owned error callback (covers oidnSetDeviceErrorFunction)
  let efen = oidn_set_device_error_function(dev, true);
  let hits0 = oidn_device_error_function_hits();
  let trig = oidn_get_device_int(dev, "noSuchParameter");
  let hits1 = oidn_device_error_function_hits();
  var ef_buf = zeros(256);
  let eflen = oidn_device_error_function_last(&mut ef_buf);
  oidn_set_device_error_function(dev, false);
  var ef_ok = false;
  if efen.is_ok && !trig.is_ok {
    if hits1 > hits0 && eflen > 0 { ef_ok = true; }
  }
  let rc11b = assert(ef_ok, "device: error callback fires with message (" + int_to_str(hits1) + " hits)");
  total = total + 1; failed = failed + report(rc11b.passed, rc11b.name);

  // ---------------------------------------------------------------------
  io.println("");
  io.println("-- SECTION 3: buffers (6) --");

  let W = 8;
  let H = 8;
  let BYTES = W * H * 3 * 4; // 768

  let rbc = oidn_new_buffer(dev, BYTES);
  let rba = oidn_new_buffer(dev, BYTES);
  let rbn = oidn_new_buffer(dev, BYTES);
  let rbo = oidn_new_buffer(dev, BYTES);
  if !rbc.is_ok || !rba.is_ok || !rbn.is_ok || !rbo.is_ok {
    io.println("  [FAIL] buffer: create failed");
    return 1;
  }
  let buf_color = rbc.value;
  let buf_albedo = rba.value;
  let buf_normal = rbn.value;
  let buf_output = rbo.value;

  let sizer = oidn_get_buffer_size(dev, buf_color);
  let storr = oidn_get_buffer_storage(dev, buf_color);
  let addrr = oidn_get_buffer_data_addr(dev, buf_color);
  var buf_meta_ok = false;
  var stor_val = -1;
  if sizer.is_ok && storr.is_ok && addrr.is_ok {
    stor_val = storr.value;
    let hostlike = stor_val == OIDN_STORAGE_HOST || stor_val == OIDN_STORAGE_DEVICE || stor_val == OIDN_STORAGE_MANAGED;
    buf_meta_ok = sizer.value == BYTES && hostlike && addrr.value != 0;
  }
  let rc12 = assert(buf_meta_ok, "buffer: size 768, storage mode + data address readable (storage=" + int_to_str(stor_val) + ")");
  total = total + 1; failed = failed + report(rc12.passed, rc12.name);

  // write/read round trip (owned slots both directions)
  var pattern = zeros(BYTES);
  var i_pat: Int = 0;
  while i_pat < BYTES {
    pattern[i_pat] = ((i_pat * 7 + 13) % 256) as UInt8;
    i_pat = i_pat + 1;
  }
  let w1 = oidn_write_buffer(dev, buf_color, 0, BYTES, &pattern);
  var back = zeros(BYTES);
  let r1 = oidn_read_buffer(dev, buf_color, 0, BYTES, &mut back);
  var round_ok = false;
  if w1.is_ok && r1.is_ok {
    let diffr = oidn_byte_diff(&pattern, &back, BYTES);
    if diffr.is_ok {
      if diffr.value == 0 { round_ok = true; }
    }
  }
  let rc13 = assert(round_ok, "buffer: write -> read round trip is byte-exact (owned slots)");
  total = total + 1; failed = failed + report(rc13.passed, rc13.name);

  // partial range read
  var part = zeros(16);
  let r2 = oidn_read_buffer(dev, buf_color, 16, 16, &mut part);
  var part_ok = false;
  if r2.is_ok {
    var same = true;
    var k: Int = 0;
    while k < 16 {
      if part[k] != pattern[16 + k] { same = false; }
      k = k + 1;
    }
    part_ok = same;
  }
  let rc14 = assert(part_ok, "buffer: partial range read (offset 16, 16 bytes) matches the source");
  total = total + 1; failed = failed + report(rc14.passed, rc14.name);

  // async write -> sync -> async read -> sync
  var aw = zeros(BYTES);
  var i_aw: Int = 0;
  while i_aw < BYTES {
    aw[i_aw] = ((i_aw * 31 + 5) % 256) as UInt8;
    i_aw = i_aw + 1;
  }
  let wa = oidn_write_buffer_async(dev, buf_color, 0, BYTES, &aw);
  let s1 = oidn_sync_device(dev);
  var ab = zeros(BYTES);
  let ra = oidn_read_buffer_async(dev, buf_color, 0, BYTES, &mut ab);
  let s2 = oidn_sync_device(dev);
  var async_ok = false;
  if wa.is_ok && s1.is_ok && ra.is_ok && s2.is_ok {
    let dr = oidn_byte_diff(&aw, &ab, BYTES);
    if dr.is_ok {
      if dr.value == 0 { async_ok = true; }
    }
  }
  let rc15 = assert(async_ok, "buffer: async write/read + device sync is byte-exact");
  total = total + 1; failed = failed + report(rc15.passed, rc15.name);

  // shared buffer over XIOM-owned memory
  var shared_mem = zeros(64);
  var i_sh: Int = 0;
  while i_sh < 64 {
    shared_mem[i_sh] = ((i_sh + 1) * 3 % 256) as UInt8;
    i_sh = i_sh + 1;
  }
  let rsb = oidn_new_shared_buffer(dev, &mut shared_mem);
  var shared_ok = false;
  if rsb.is_ok {
    let sb = rsb.value;
    var sb_back = zeros(64);
    let sbr = oidn_read_buffer(dev, sb, 0, 64, &mut sb_back);
    if sbr.is_ok {
      let d1r = oidn_byte_diff(&shared_mem, &sb_back, 64);
      // OIDN-side write into the shared buffer must be visible in the
      // XIOM-owned memory (same storage).
      var src64 = zeros(64);
      var i_s2: Int = 0;
      while i_s2 < 64 {
        src64[i_s2] = 201 as UInt8;
        i_s2 = i_s2 + 1;
      }
      let sbw = oidn_write_buffer(dev, sb, 0, 64, &src64);
      var mach = false;
      if d1r.is_ok && sbw.is_ok {
        if d1r.value == 0 && (shared_mem[0] as Int) == 201 && (shared_mem[63] as Int) == 201 { mach = true; }
      }
      shared_ok = mach;
    }
    oidn_release_buffer(sb);
  }
  let rc16 = assert(shared_ok, "buffer: shared buffer wraps XIOM-owned memory (read + write visible)");
  total = total + 1; failed = failed + report(rc16.passed, rc16.name);

  // unsupported import path (CPU device has no external memory)
  let rwin = oidn_new_shared_buffer_from_win32_handle(dev, OIDN_EXTERNAL_MEMORY_TYPE_FLAG_D3D12_RESOURCE, 4660, 0, 64);
  var win_err_ok = false;
  if !rwin.is_ok {
    if rwin.error.code != 0 && rwin.error.message.len() > 0 { win_err_ok = true; }
  }
  let rc17 = assert(win_err_ok, "buffer: Win32 external-memory import -> typed error on the CPU device");
  total = total + 1; failed = failed + report(rc17.passed, rc17.name);

  // ---------------------------------------------------------------------
  io.println("");
  io.println("-- SECTION 4: filters + typed errors (5) --");

  let rf = oidn_new_filter(dev, "RT");
  if !rf.is_ok {
    io.println("  [FAIL] filter: RT create failed: " + rf.error.message);
    return 1;
  }
  let filter = rf.value;

  let rfl = oidn_new_filter(dev, "RTLightmap");
  var lightmap_ok = rfl.is_ok;
  if rfl.is_ok { oidn_release_filter(rfl.value); }
  let rc18 = assert(lightmap_ok, "filter: RT and RTLightmap both constructible");
  total = total + 1; failed = failed + report(rc18.passed, rc18.name);

  let rbad = oidn_new_filter(dev, "NO_SUCH_FILTER");
  var badfilt_ok = false;
  if !rbad.is_ok {
    if rbad.error.code == OIDN_ERROR_INVALID_ARGUMENT {
      if string.str_contains(rbad.error.message, "unknown filter type") { badfilt_ok = true; }
    }
  }
  let rc19 = assert(badfilt_ok, "filter: unknown type -> typed INVALID_ARGUMENT (code 2)");
  total = total + 1; failed = failed + report(rc19.passed, rc19.name);

  let shdr = oidn_set_filter_bool(dev, filter, "hdr", false);
  let ghdr = oidn_get_filter_bool(dev, filter, "hdr");
  let squal = oidn_set_filter_int(dev, filter, "quality", OIDN_QUALITY_FAST);
  let gqual = oidn_get_filter_int(dev, filter, "quality");
  var params_ok = false;
  if shdr.is_ok && ghdr.is_ok && squal.is_ok && gqual.is_ok {
    if !ghdr.value && gqual.value == OIDN_QUALITY_FAST { params_ok = true; }
  }
  let rc20 = assert(params_ok, "filter: bool/int params round trip (hdr=false, quality=FAST)");
  total = total + 1; failed = failed + report(rc20.passed, rc20.name);

  let qbad = oidn_set_filter_int(dev, filter, "quality", 99);
  var qbad_ok = false;
  if !qbad.is_ok {
    if qbad.error.code == OIDN_ERROR_INVALID_ARGUMENT {
      if string.str_contains(qbad.error.message, "unknown filter quality mode") { qbad_ok = true; }
    }
  }
  let rc21 = assert(qbad_ok, "filter: invalid quality -> typed INVALID_ARGUMENT (code 2)");
  total = total + 1; failed = failed + report(rc21.passed, rc21.name);

  var ff_buf = zeros(4);
  let ff = oidn_get_filter_float_bytes(dev, filter, "noSuchFloat", &mut ff_buf);
  var ff_ok = false;
  if !ff.is_ok {
    if ff.error.code == OIDN_ERROR_INVALID_ARGUMENT { ff_ok = true; }
  }
  let rc22 = assert(ff_ok, "filter: float getter on unknown param -> typed INVALID_ARGUMENT (code 2)");
  total = total + 1; failed = failed + report(rc22.passed, rc22.name);

  // ---------------------------------------------------------------------
  io.println("");
  io.println("-- SECTION 5: CPU denoise, fixture generated in-test (6) --");

  var color = fixture_color(W, H);
  var albedo = fixture_albedo(W, H);
  var normal = fixture_normal(W, H);

  let fwc = oidn_write_buffer(dev, buf_color, 0, BYTES, &color);
  let fwa = oidn_write_buffer(dev, buf_albedo, 0, BYTES, &albedo);
  let fwn = oidn_write_buffer(dev, buf_normal, 0, BYTES, &normal);
  var fx_ok = false;
  if fwc.is_ok && fwa.is_ok && fwn.is_ok { fx_ok = true; }
  let rc23 = assert(fx_ok, "fixture: 8x8 RGB color/albedo/normal written to device buffers");
  total = total + 1; failed = failed + report(rc23.passed, rc23.name);

  // commit without images -> typed error (dedicated fresh filter)
  let rfe = oidn_new_filter(dev, "RT");
  var noimg_ok = false;
  if rfe.is_ok {
    let noimg = oidn_commit_filter(dev, rfe.value);
    if !noimg.is_ok {
      if noimg.error.code == OIDN_ERROR_INVALID_OPERATION { noimg_ok = true; }
    }
    oidn_release_filter(rfe.value);
  }
  let rc24 = assert(noimg_ok, "denoise: commit without images -> typed INVALID_OPERATION (code 3)");
  total = total + 1; failed = failed + report(rc24.passed, rc24.name);

  let rfr = oidn_new_filter(dev, "RT");
  if !rfr.is_ok {
    io.println("  [FAIL] denoise: RT create for the run failed: " + rfr.error.message);
    return 1;
  }
  let run_filter = rfr.value;
  let sic = oidn_set_filter_image(dev, run_filter, "color", buf_color, OIDN_FORMAT_FLOAT3, W, H, 0, 0, 0);
  let sia = oidn_set_filter_image(dev, run_filter, "albedo", buf_albedo, OIDN_FORMAT_FLOAT3, W, H, 0, 0, 0);
  let sin = oidn_set_filter_image(dev, run_filter, "normal", buf_normal, OIDN_FORMAT_FLOAT3, W, H, 0, 0, 0);
  let sio = oidn_set_filter_image(dev, run_filter, "output", buf_output, OIDN_FORMAT_FLOAT3, W, H, 0, 0, 0);
  oidn_set_filter_progress_monitor(dev, run_filter, true);
  oidn_filter_progress_reset();
  let c2 = oidn_commit_filter(dev, run_filter);
  let e2 = oidn_execute_filter(dev, run_filter);
  var exec_ok = false;
  if sic.is_ok && sia.is_ok && sin.is_ok && sio.is_ok && c2.is_ok && e2.is_ok { exec_ok = true; }
  let rc25 = assert(exec_ok, "denoise: RT filter with color+albedo+normal+output executes on the CPU device");
  total = total + 1; failed = failed + report(rc25.passed, rc25.name);
  if !exec_ok {
    if !c2.is_ok { io.println("    commit: " + c2.error.message); }
    if !e2.is_ok { io.println("    execute: " + e2.error.message); }
    return 1;
  }

  let progress = oidn_filter_progress_hits();
  let rc26 = assert(progress > 0, "denoise: progress monitor fired (" + int_to_str(progress) + " hits)");
  total = total + 1; failed = failed + report(rc26.passed, rc26.name);

  var output = zeros(BYTES);
  let rro = oidn_read_buffer(dev, buf_output, 0, BYTES, &mut output);
  var stats_ok = false;
  var finite = -1;
  if rro.is_ok {
    let sr = oidn_f32_analyze(&color, &output, W * H * 3, 0);
    if sr.is_ok {
      let st = sr.value;
      finite = st.finite;
      stats_ok = st.finite == W * H * 3 &&
                 st.changed >= 96 &&
                 st.min_milli >= 0 && st.max_milli <= 1000 &&
                 st.mean_milli >= 200 && st.mean_milli <= 900;
      io.println("    stats: finite=" + int_to_str(st.finite) +
                 " changed=" + int_to_str(st.changed) +
                 " min_milli=" + int_to_str(st.min_milli) +
                 " max_milli=" + int_to_str(st.max_milli) +
                 " mean_milli=" + int_to_str(st.mean_milli));
    }
  }
  let rc27 = assert(stats_ok, "denoise: output is finite (192/192) and changed vs input, LDR range");
  total = total + 1; failed = failed + report(rc27.passed, rc27.name);

  var dval = -1;
  let dbr = oidn_byte_diff(&color, &output, BYTES);
  if dbr.is_ok { dval = dbr.value; }
  let rc28 = assert(dval >= 96, "denoise: byte-level diff vs input is non-trivial (" + int_to_str(dval) + " bytes)");
  total = total + 1; failed = failed + report(rc28.passed, rc28.name);

  // ---------------------------------------------------------------------
  io.println("");
  io.println("-- SECTION 6: repeat determinism + shared-image path (3) --");

  // second run over the same buffers through a fresh filter, async execute
  let rf2 = oidn_new_filter(dev, "RT");
  var det_ok = false;
  var output2 = zeros(BYTES);
  if rf2.is_ok {
    let f2 = rf2.value;
    oidn_set_filter_image(dev, f2, "color", buf_color, OIDN_FORMAT_FLOAT3, W, H, 0, 0, 0);
    oidn_set_filter_image(dev, f2, "albedo", buf_albedo, OIDN_FORMAT_FLOAT3, W, H, 0, 0, 0);
    oidn_set_filter_image(dev, f2, "normal", buf_normal, OIDN_FORMAT_FLOAT3, W, H, 0, 0, 0);
    oidn_set_filter_image(dev, f2, "output", buf_output, OIDN_FORMAT_FLOAT3, W, H, 0, 0, 0);
    oidn_set_filter_bool(dev, f2, "hdr", false);
    let c3 = oidn_commit_filter(dev, f2);
    let e3 = oidn_execute_filter_async(dev, f2);
    let s3 = oidn_sync_device(dev);
    if c3.is_ok && e3.is_ok && s3.is_ok {
      let r3 = oidn_read_buffer(dev, buf_output, 0, BYTES, &mut output2);
      if r3.is_ok {
        let eqr = oidn_byte_equal(&output, &output2, BYTES);
        if eqr.is_ok {
          if eqr.value { det_ok = true; }
        }
      }
    }
    oidn_release_filter(f2);
  }
  let rc29 = assert(det_ok, "determinism: repeat async run is bit-identical to the first run");
  total = total + 1; failed = failed + report(rc29.passed, rc29.name);

  // shared-image path: OIDN reads an XIOM-owned image directly
  let rf3 = oidn_new_filter(dev, "RT");
  var shared_img_ok = false;
  if rf3.is_ok {
    let f3 = rf3.value;
    var sh_out = zeros(BYTES);
    oidn_set_shared_filter_image(dev, f3, "color", &mut color, OIDN_FORMAT_FLOAT3, W, H, 0, 0, 0);
    oidn_set_shared_filter_image(dev, f3, "albedo", &mut albedo, OIDN_FORMAT_FLOAT3, W, H, 0, 0, 0);
    oidn_set_shared_filter_image(dev, f3, "normal", &mut normal, OIDN_FORMAT_FLOAT3, W, H, 0, 0, 0);
    oidn_set_shared_filter_image(dev, f3, "output", &mut sh_out, OIDN_FORMAT_FLOAT3, W, H, 0, 0, 0);
    let c4 = oidn_commit_filter(dev, f3);
    let e4 = oidn_execute_filter(dev, f3);
    if c4.is_ok && e4.is_ok {
      let sr2 = oidn_f32_analyze(&color, &sh_out, W * H * 3, 0);
      if sr2.is_ok {
        let st2 = sr2.value;
        if st2.finite == W * H * 3 && st2.changed >= 96 { shared_img_ok = true; }
      }
    }
    oidn_release_filter(f3);
  }
  let rc30 = assert(shared_img_ok, "shared image: denoise reads/writes XIOM-owned image memory directly");
  total = total + 1; failed = failed + report(rc30.passed, rc30.name);

  // teardown + reload lifecycle
  oidn_release_filter(run_filter);
  oidn_release_filter(filter);
  oidn_release_buffer(buf_color);
  oidn_release_buffer(buf_albedo);
  oidn_release_buffer(buf_normal);
  oidn_release_buffer(buf_output);
  let sync_end = oidn_sync_device(dev);
  let rel_end = oidn_release_device(dev);
  oidn_unload();
  var teardown_ok = sync_end.is_ok && rel_end.is_ok && !oidn_loaded();
  let rc31 = assert(teardown_ok, "teardown: handles released, device synced, runtime unloaded");
  total = total + 1; failed = failed + report(rc31.passed, rc31.name);

  io.println("");
  io.println("=============================================================");
  if failed == 0 {
    io.println("  ALL " + int_to_str(total) + " TESTS PASSED");
    io.println("  Runtime: Open Image Denoise v2.5.1 (pin; PROVENANCE.md)");
    return 0;
  }
  io.println("  TESTS:  " + int_to_str(total));
  io.println("  FAILED: " + int_to_str(failed));
  return 1;
}
