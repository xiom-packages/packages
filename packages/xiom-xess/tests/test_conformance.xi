// xiom.xess conformance suite -- dynamic-loader path (Intel XeSS runtime).
//
// CI WITHOUT the XeSS runtime stays green: no libxess.dll resolves -> the
// probe reports SKIP, and the SKIP classification is exercised
// deterministically every run (bogus sonames -> ABSENT).  The loader's
// resolvability machinery is exercised on every host too: loading a real DLL
// that lacks XESS symbols (kernel32.dll) must fail closed as XESS_LOAD_ABI.
//
// Host-independent checks (no DLL needed): the pinned enum constants, the
// byte-slot helpers, the pure-arithmetic f32 codec (exact bit patterns incl.
// RNE rounding, subnormals, overflow), the pinned struct serializers (D3D12 /
// Vulkan / D3D11 init + execute params, dump parameters) and the declared
// entry-surface accounting (37 core + 4 D3D11 = 41).
//
// Present path (runtime image on PATH; nothing committed -- SPEC.md section
// 5): core module loads -> all 37 core entry points resolve; optional
// libxess_dx11.dll companion -> all 4 D3D11 entries; the full declared name
// list re-resolves through dl_sym as direct surface evidence; xessGetVersion
// runs and its packed 16-bit version fields are read out of the owned slot;
// a companion-absent named load returns the typed CANT_LOAD_LIBRARY outcome
// from the D3D11 wrappers without ever calling through a null pointer.
//
// Run: scripts/port.ps1 -Package xiom.xess

module xess_conformance

use xiom.io;
use xiom.convert;
use xiom.ffi.dl;
use xiom.xess;

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

/// Exact f32 bit patterns (independently computed constants).
fn check_f32_values() -> Bool {
  let ok1 = xess_f32_bits_from_f64(1.0) == 1065353216;       // 0x3F800000
  let ok2 = xess_f32_bits_from_f64(-2.0) == 3221225472;      // 0xC0000000
  let ok3 = xess_f32_bits_from_f64(0.5) == 1056964608;       // 0x3F000000
  let ok4 = xess_f32_bits_from_f64(0.1) == 1036831949;       // 0x3DCCCCCD
  let ok5 = xess_f32_bits_from_f64(1.5) == 1069547520;       // 0x3FC00000
  return ok1 && ok2 && ok3 && ok4 && ok5;
}

fn check_f32_extremes() -> Bool {
  let ok1 = xess_f32_bits_from_f64(3.4028234663852886e38) == 2139095039;  // f32 max 0x7F7FFFFF
  let ok2 = xess_f32_bits_from_f64(1.0e39) == 2139095040;                 // +Inf 0x7F800000
  let ok3 = xess_f32_bits_from_f64(-1.0e39) == 4286578688;                // -Inf 0xFF800000
  let ok4 = xess_f32_bits_from_f64(-0.0) == 2147483648;                   // -0.0 0x80000000
  let ok5 = xess_f32_bits_from_f64(1.401298464324817e-45) == 1;           // min subnormal 2^-149
  let ok6 = xess_f32_bits_from_f64(7.006492321624085e-46) == 0;           // 2^-150: RNE tie -> 0
  let ok7 = xess_f32_bits_from_f64(3.5032461608120425e-45) == 2;          // 1.5 * 2^-149 -> 2
  return ok1 && ok2 && ok3 && ok4 && ok5 && ok6 && ok7;
}

fn check_f32_decode() -> Bool {
  let ok1 = xess_f32_from_bits(1069547520) == 1.5;      // 0x3FC00000
  let ok2 = xess_f32_from_bits(3221225472) == -2.0;     // 0xC0000000
  let ok3 = xess_f32_from_bits(0) == 0.0;
  let ok4 = xess_f32_from_bits(2147483648) == 0.0;      // -0.0 decodes to 0.0 (sign lost)
  let ok5 = xess_f32_from_bits(1) * xess_f32_from_bits(1) > 0.0;  // 2^-149 * 2^-149 > 0
  return ok1 && ok2 && ok3 && ok4 && ok5;
}

fn check_f32_roundtrip() -> Bool {
  let v = xess_f32_from_bits(xess_f32_bits_from_f64(1.5));
  let ok1 = v == 1.5;
  let w = xess_f32_from_bits(xess_f32_bits_from_f64(-0.25));
  let ok2 = w == -0.25;
  return ok1 && ok2;
}

fn check_d3d12_init_params() -> Bool {
  let p = XessD3D12InitParams{
    output_width: 1920;
    output_height: 1080;
    quality: XESS_QUALITY_SETTING_BALANCED;
    init_flags: XESS_INIT_FLAG_INVERTED_DEPTH;
    creation_node_mask: 1;
    visible_node_mask: 3;
    temp_buffer_heap: 4096;
    buffer_heap_offset: 1024;
    temp_texture_heap: 8192;
    texture_heap_offset: 2048;
    pipeline_library: 17179869184;
  };
  let s = xess_d3d12_init_params_build(&p);
  let q = xess_d3d12_init_params_read(&s);
  return s.len() == 64
    && q.output_width == 1920 && q.output_height == 1080
    && q.quality == 102 && q.init_flags == 2
    && q.creation_node_mask == 1 && q.visible_node_mask == 3
    && q.temp_buffer_heap == 4096 && q.buffer_heap_offset == 1024
    && q.temp_texture_heap == 8192 && q.texture_heap_offset == 2048
    && q.pipeline_library == 17179869184;
}

fn check_d3d12_execute_params() -> Bool {
  let p = XessD3D12ExecuteParams{
    color_texture: 1001;
    velocity_texture: 1002;
    depth_texture: 1003;
    exposure_scale_texture: 1004;
    responsive_pixel_mask_texture: 1005;
    output_texture: 1006;
    jitter_offset_x: 0.5;
    jitter_offset_y: -0.5;
    exposure_scale: 1.0;
    reset_history: 1;
    input_width: 1280;
    input_height: 720;
    input_color_base_x: 4;
    input_color_base_y: 5;
    input_motion_vector_base_x: 6;
    input_motion_vector_base_y: 7;
    input_depth_base_x: 8;
    input_depth_base_y: 9;
    input_responsive_mask_base_x: 10;
    input_responsive_mask_base_y: 11;
    output_color_base_x: 12;
    output_color_base_y: 13;
    descriptor_heap: 2001;
    descriptor_heap_offset: 256;
  };
  let s = xess_d3d12_execute_params_build(&p);
  return s.len() == 136
    && xess_rd_u64(&s, 0) == 1001
    && xess_rd_u64(&s, 40) == 1006
    && xess_rd_u32(&s, 48) == 1056964608      // jitterOffsetX 0.5 -> 0x3F000000
    && xess_rd_u32(&s, 52) == 3204448256      // jitterOffsetY -0.5 -> 0xBF000000
    && xess_rd_u32(&s, 56) == 1065353216      // exposureScale 1.0
    && xess_rd_u32(&s, 60) == 1
    && xess_rd_u32(&s, 64) == 1280
    && xess_rd_u32(&s, 68) == 720
    && xess_rd_u32(&s, 72) == 4
    && xess_rd_u32(&s, 116) == 13
    && xess_rd_u32(&s, 104) == 0 && xess_rd_u32(&s, 108) == 0
    && xess_rd_u64(&s, 120) == 2001
    && xess_rd_u32(&s, 128) == 256;
}

/// A fresh image-view info value (separate instances per struct field).
fn mk_vk_info() -> XessVkImageViewInfo {
  return XessVkImageViewInfo{
    image_view: 501;
    image: 502;
    aspect_mask: 1;
    base_mip_level: 0;
    level_count: 1;
    base_array_layer: 0;
    layer_count: 1;
    format: 37;
    width: 1920;
    height: 1080;
  };
}

fn check_vk_params() -> Bool {
  let ip = XessVkInitParams{
    output_width: 2560;
    output_height: 1440;
    quality: XESS_QUALITY_SETTING_QUALITY;
    init_flags: 0;
    creation_node_mask: 1;
    visible_node_mask: 1;
    temp_buffer_heap: 111;
    buffer_heap_offset: 222;
    temp_texture_heap: 333;
    texture_heap_offset: 444;
    pipeline_cache: 555;
  };
  let isbuf = xess_vk_init_params_build(&ip);
  let ip2 = xess_vk_init_params_read(&isbuf);
  let ok_init = isbuf.len() == 64 && ip2.output_width == 2560 && ip2.quality == 103
    && ip2.temp_buffer_heap == 111 && ip2.texture_heap_offset == 444 && ip2.pipeline_cache == 555;

  let ep = XessVkExecuteParams{
    color_texture: mk_vk_info();
    velocity_texture: mk_vk_info();
    depth_texture: mk_vk_info();
    exposure_scale_texture: mk_vk_info();
    responsive_pixel_mask_texture: mk_vk_info();
    output_texture: mk_vk_info();
    jitter_offset_x: 0.25;
    jitter_offset_y: -0.25;
    exposure_scale: 2.0;
    reset_history: 1;
    input_width: 1706;
    input_height: 960;
    input_color_base_x: 1;
    input_color_base_y: 2;
    input_motion_vector_base_x: 3;
    input_motion_vector_base_y: 4;
    input_depth_base_x: 5;
    input_depth_base_y: 6;
    input_responsive_mask_base_x: 7;
    input_responsive_mask_base_y: 8;
    output_color_base_x: 9;
    output_color_base_y: 10;
  };
  let es = xess_vk_execute_params_build(&ep);
  let ok_exec = es.len() == 360
    && xess_rd_u64(&es, 0) == 501
    && xess_rd_u64(&es, 8) == 502
    && xess_rd_u32(&es, 16) == 1
    && xess_rd_u32(&es, 36) == 37
    && xess_rd_u32(&es, 40) == 1920
    && xess_rd_u32(&es, 44) == 1080
    && xess_rd_u64(&es, 240) == 501               // output texture info @240
    && xess_rd_u32(&es, 288) == 1048576000        // 0.25 -> 0x3E800000
    && xess_rd_u32(&es, 292) == 3196059648        // -0.25 -> 0xBE800000
    && xess_rd_u32(&es, 296) == 1073741824        // 2.0
    && xess_rd_u32(&es, 304) == 1706
    && xess_rd_u32(&es, 312) == 1
    && xess_rd_u32(&es, 356) == 10;
  return ok_init && ok_exec;
}

fn check_d3d11_params() -> Bool {
  let ip = XessD3D11InitParams{
    output_width: 1280;
    output_height: 720;
    quality: XESS_QUALITY_SETTING_PERFORMANCE;
    init_flags: XESS_INIT_FLAG_HIGH_RES_MV;
  };
  let isbuf = xess_d3d11_init_params_build(&ip);
  let ip2 = xess_d3d11_init_params_read(&isbuf);
  let ok_init = isbuf.len() == 16 && ip2.output_width == 1280 && ip2.output_height == 720
    && ip2.quality == 101 && ip2.init_flags == 1;

  let ep = XessD3D11ExecuteParams{
    color_texture: 11;
    velocity_texture: 12;
    depth_texture: 13;
    exposure_scale_texture: 14;
    responsive_pixel_mask_texture: 15;
    output_texture: 16;
    jitter_offset_x: 0.0;
    jitter_offset_y: 0.0;
    exposure_scale: 1.0;
    reset_history: 0;
    input_width: 1280;
    input_height: 720;
    input_color_base_x: 0;
    input_color_base_y: 0;
    input_motion_vector_base_x: 0;
    input_motion_vector_base_y: 0;
    input_depth_base_x: 0;
    input_depth_base_y: 0;
    input_responsive_mask_base_x: 0;
    input_responsive_mask_base_y: 0;
    output_color_base_x: 0;
    output_color_base_y: 0;
  };
  let es = xess_d3d11_execute_params_build(&ep);
  let ok_exec = es.len() == 120
    && xess_rd_u64(&es, 0) == 11
    && xess_rd_u64(&es, 40) == 16
    && xess_rd_u32(&es, 48) == 0
    && xess_rd_u32(&es, 56) == 1065353216
    && xess_rd_u32(&es, 64) == 1280
    && xess_rd_u32(&es, 116) == 0;
  return ok_init && ok_exec;
}

fn check_dump_params() -> Bool {
  let p = XessDumpParameters{
    path: "dump";
    frame_idx: 7;
    frame_count: 50;
    dump_elements_mask: XESS_DUMP_ALL_INPUTS;
  };
  let s = xess_dump_parameters_build(&p);
  return s.len() == 24
    && xess_rd_u64(&s, 0) != 0
    && xess_rd_u32(&s, 8) == 7
    && xess_rd_u32(&s, 12) == 50
    && xess_rd_u32(&s, 16) == 159;
}

/// Count how many of `names` resolve in a loaded module via dl_sym.
/// Complexity: O(names).
fn surface_sweep(h: Int, names: &Vec[Str]) -> Int {
  var n = 0;
  var i = 0;
  while i < names.len() {
    let s = dl.dl_sym(h, names[i]);
    if s.is_ok { n = n + 1; }
    i = i + 1;
  }
  return n;
}

fn main() -> Int {
  io.println("=== xiom.xess conformance tests (dynamic loader) ===");
  io.flush_stdout();
  var failed: Int = 0;

  // ---- pinned constants (xess.h + debug headers) --------------------------
  failed = failed + report(
    XESS_QUALITY_SETTING_ULTRA_PERFORMANCE == 100
      && XESS_QUALITY_SETTING_PERFORMANCE == 101
      && XESS_QUALITY_SETTING_BALANCED == 102
      && XESS_QUALITY_SETTING_QUALITY == 103
      && XESS_QUALITY_SETTING_ULTRA_QUALITY == 104
      && XESS_QUALITY_SETTING_ULTRA_QUALITY_PLUS == 105
      && XESS_QUALITY_SETTING_AA == 106,
    "const: quality settings 100..106");

  failed = failed + report(
    XESS_INIT_FLAG_NONE == 0 && XESS_INIT_FLAG_HIGH_RES_MV == 1
      && XESS_INIT_FLAG_INVERTED_DEPTH == 2 && XESS_INIT_FLAG_EXPOSURE_SCALE_TEXTURE == 4
      && XESS_INIT_FLAG_RESPONSIVE_PIXEL_MASK == 8 && XESS_INIT_FLAG_USE_NDC_VELOCITY == 16
      && XESS_INIT_FLAG_EXTERNAL_DESCRIPTOR_HEAP == 32 && XESS_INIT_FLAG_LDR_INPUT_COLOR == 64
      && XESS_INIT_FLAG_JITTERED_MV == 128 && XESS_INIT_FLAG_ENABLE_AUTOEXPOSURE == 256,
    "const: init flags");

  failed = failed + report(
    XESS_RESULT_SUCCESS == 0 && XESS_RESULT_WARNING_OLD_DRIVER == 2
      && XESS_RESULT_ERROR_UNSUPPORTED_DEVICE == -1 && XESS_RESULT_ERROR_UNSUPPORTED_DRIVER == -2
      && XESS_RESULT_ERROR_UNINITIALIZED == -3 && XESS_RESULT_ERROR_INVALID_ARGUMENT == -4
      && XESS_RESULT_ERROR_UNSUPPORTED == -10 && XESS_RESULT_ERROR_CANT_LOAD_LIBRARY == -11
      && XESS_RESULT_ERROR_WRONG_CALL_ORDER == -12 && XESS_RESULT_ERROR_UNKNOWN == -1000,
    "const: result codes");

  failed = failed + report(
    XESS_DEBUG_ENABLE_PROFILING == 1073741824
      && XESS_DUMP_ALL_INPUTS == 159 && XESS_DUMP_ALL == 2147483647
      && XESS_NETWORK_MODEL_SPLAT == 1 && XESS_NETWORK_MODEL_UNKNOWN == 2147483647
      && XESS_LOGGING_LEVEL_ERROR == 3,
    "const: profiling/dump/network/logging enums");

  // ---- slot helpers -------------------------------------------------------
  var s32 = xess_slot(8);
  xess_wr_u32(&mut s32, 4, 3735928559);
  failed = failed + report(xess_rd_u32(&s32, 4) == 3735928559, "slot: u32 round trip");

  var s64 = xess_slot(8);
  xess_wr_u64(&mut s64, 0, 140694697425568);
  failed = failed + report(xess_rd_u64(&s64, 0) == 140694697425568, "slot: u64 round trip");

  var s16 = xess_slot(4);
  xess_wr_u16(&mut s16, 2, 4660);
  failed = failed + report(xess_rd_u16(&s16, 2) == 4660, "slot: u16 round trip");

  var sf = xess_slot(4);
  xess_wr_f32(&mut sf, 0, 1.5);
  failed = failed + report(xess_rd_u32(&sf, 0) == 1069547520, "slot: f32 store bits (1.5)");

  // ---- f32 codec (pure arithmetic, B-12 discipline) -----------------------
  failed = failed + report(check_f32_values(), "f32: encode exact patterns (1.0/-2.0/0.5/0.1/1.5)");
  failed = failed + report(check_f32_extremes(), "f32: encode extremes (max/inf/-0.0/subnormal/RNE ties)");
  failed = failed + report(check_f32_decode(), "f32: decode (1.5/-2.0/zero/min-subnormal)");
  failed = failed + report(check_f32_roundtrip(), "f32: bits -> f64 -> bits round trip");

  // ---- pinned struct layouts ---------------------------------------------
  failed = failed + report(check_d3d12_init_params(), "layout: d3d12 init params (64B) round trip");
  failed = failed + report(check_d3d12_execute_params(), "layout: d3d12 execute params (136B) offsets");
  failed = failed + report(check_vk_params(), "layout: vk init (64B) + execute (360B) params");
  failed = failed + report(check_d3d11_params(), "layout: d3d11 init (16B) + execute (120B) params");
  failed = failed + report(check_dump_params(), "layout: dump parameters (24B)");

  // ---- declared surface accounting ---------------------------------------
  let core_names = xess_entry_names_core();
  let dx11_names = xess_entry_names_dx11();
  failed = failed + report(
    core_names.len() == 37 && dx11_names.len() == 4
      && core_names.len() + dx11_names.len() == XESS_ENTRY_COUNT
      && XESS_CORE_ENTRY_COUNT == 37 && XESS_DX11_ENTRY_COUNT == 4,
    "surface: declared entry accounting 37 + 4 = 41");

  // ---- loader typed error paths (deterministic on every host) -------------
  let absent = xess_load_named("xiom-absent-xess-core-xyz.dll", "xiom-absent-xess-dx11-xyz.dll");
  if absent.is_ok {
    failed = failed + report(false, "skip-path: bogus sonames unexpectedly loaded");
  } else {
    failed = failed + report(absent.error.kind == XESS_LOAD_ABSENT,
      "skip-path: absent runtime classified as XESS_LOAD_ABSENT (SKIP)");
  }

  let wronglib = xess_load_named("kernel32.dll", "");
  if wronglib.is_ok {
    failed = failed + report(false, "abi-path: kernel32.dll unexpectedly carried XESS entry points");
  } else {
    failed = failed + report(wronglib.error.kind == XESS_LOAD_ABI,
      "abi-path: non-XESS DLL fails closed as XESS_LOAD_ABI (resolvability)");
  }

  // ---- probe: SKIP on a box without the runtime ---------------------------
  let probe = xess_probe_default();
  if !probe.is_ok {
    if probe.error.kind == XESS_LOAD_ABSENT {
      failed = failed + report(true, "probe: SKIP -- no XeSS runtime present (" + probe.error.message + ")");
    } else {
      failed = failed + report(false, "probe: failed -- " + probe.error.message);
    }
  } else {
    let v: XessVersion = probe.value;
    failed = failed + report(v.major > 0,
      "probe: xessGetVersion " + convert.int_to_string(v.major)
        + "." + convert.int_to_string(v.minor) + "." + convert.int_to_string(v.patch));
  }

  // ---- present path (runtime image on the search path; nothing committed) --
  let l = xess_load();
  if !l.is_ok {
    if l.error.kind == XESS_LOAD_ABSENT {
      failed = failed + report(true, "loader: SKIP -- libxess.dll not on the search path");
      failed = failed + report(true, "surface: SKIP -- present-path sweep needs the runtime");
      failed = failed + report(true, "d3d11: SKIP -- companion check needs the runtime");
    } else {
      failed = failed + report(false, "loader: failed -- " + l.error.message);
    }
  } else {
    let lib: XessLibrary = l.value;
    let core_ok = lib.p_get_version != 0 && lib.p_get_intel_xefx_version != 0
      && lib.p_get_properties != 0 && lib.p_get_input_resolution != 0
      && lib.p_get_optimal_input_resolution != 0 && lib.p_get_jitter_scale != 0
      && lib.p_get_velocity_scale != 0 && lib.p_destroy_context != 0
      && lib.p_set_jitter_scale != 0 && lib.p_set_velocity_scale != 0
      && lib.p_set_exposure_multiplier != 0 && lib.p_get_exposure_multiplier != 0
      && lib.p_set_max_responsive_mask_value != 0 && lib.p_get_max_responsive_mask_value != 0
      && lib.p_set_logging_callback != 0 && lib.p_is_optimal_driver != 0
      && lib.p_force_legacy_scale_factors != 0 && lib.p_get_pipeline_build_status != 0
      && lib.p_d3d12_create_context != 0 && lib.p_d3d12_build_pipelines != 0
      && lib.p_d3d12_init != 0 && lib.p_d3d12_get_init_params != 0
      && lib.p_d3d12_execute != 0 && lib.p_d3d12_get_resources_to_dump != 0
      && lib.p_d3d12_get_profiling_data != 0 && lib.p_vk_get_required_instance_extensions != 0
      && lib.p_vk_get_required_device_extensions != 0 && lib.p_vk_get_required_device_features != 0
      && lib.p_vk_create_context != 0 && lib.p_vk_build_pipelines != 0
      && lib.p_vk_init != 0 && lib.p_vk_get_init_params != 0
      && lib.p_vk_execute != 0 && lib.p_vk_get_resources_to_dump != 0
      && lib.p_select_network_model != 0 && lib.p_start_dump != 0
      && lib.p_get_profiling_data != 0;
    failed = failed + report(core_ok, "loader: libxess.dll loaded, 37/37 core entries resolved");

    let core_hits = surface_sweep(lib.h_core, &core_names);
    failed = failed + report(core_hits == 37,
      "surface: dl_sym sweep " + convert.int_to_string(core_hits) + "/37 core names");

    if !lib.has_dx11 {
      failed = failed + report(true,
        "d3d11: SKIP-companion -- libxess_dx11.dll absent (4 entries unavailable; typed CANT_LOAD_LIBRARY)");
    } else {
      let d_ok = lib.p_d3d11_create_context != 0 && lib.p_d3d11_init != 0
        && lib.p_d3d11_get_init_params != 0 && lib.p_d3d11_execute != 0;
      let dx_hits = surface_sweep(lib.h_dx11, &dx11_names);
      failed = failed + report(d_ok && dx_hits == 4,
        "d3d11: libxess_dx11.dll loaded, " + convert.int_to_string(dx_hits) + "/4 D3D11 entries resolved");
    }

    let v = xess_get_version(&lib);
    failed = failed + report(v.ok && v.version.major > 0,
      "version: xessGetVersion rc=" + convert.int_to_string(v.rc) + " -> "
        + convert.int_to_string(v.version.major) + "." + convert.int_to_string(v.version.minor)
        + "." + convert.int_to_string(v.version.patch));

    let vk = xess_vk_get_required_instance_extensions(&lib);
    failed = failed + report(vk.ok && vk.min_vk_api_version > 0,
      "vk: required instance extensions rc=" + convert.int_to_string(vk.rc)
        + " count=" + convert.int_to_string(vk.count)
        + " minVkApiVersion=" + convert.int_to_string(vk.min_vk_api_version));

    let c = xess_close(&lib);
    failed = failed + report(c.is_ok, "loader: runtime handles closed");

    // typed companion-absent path: core resolves, D3D11 companion does not
    let l2 = xess_load_named(XESS_SONAME, "xiom-absent-xess-dx11-xyz.dll");
    if l2.is_ok {
      let lib2: XessLibrary = l2.value;
      let d = xess_d3d11_create_context(&lib2, 0);
      failed = failed + report(!d.ok && d.rc == XESS_RESULT_ERROR_CANT_LOAD_LIBRARY && !lib2.has_dx11,
        "d3d11: companion-absent load yields typed CANT_LOAD_LIBRARY (no null call-through)");
      let c2 = xess_close(&lib2);
      failed = failed + report(c2.is_ok, "loader: companion-absent handles closed");
    } else {
      failed = failed + report(false, "d3d11: companion-absent named load failed -- " + l2.error.message);
    }
  }

  if failed == 0 {
    io.println("xiom.xess: all tests passed");
  } else {
    io.println("xiom.xess: tests failed");
  }
  return failed;
}
