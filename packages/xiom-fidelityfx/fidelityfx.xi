// XIOM -- xiom.fidelityfx: AMD FidelityFX SDK (FSR upscaler / post family)
// bindings, pinned at SDK v2.3.0.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Surface model (SPEC.md section 3):
//   * unified API (ffx_api.h): ffxCreateContext / ffxDestroyContext /
//     ffxConfigure / ffxQuery / ffxDispatch -- resolved at runtime from the
//     signed effect DLLs (loader / upscaler / framegeneration) or any other
//     binary exporting the same five entry points; absent -> typed SKIP.
//   * the SDK's own loader helper (ffx_api_loader.h: ffxLoadFunctions) bound
//     over the vendored header and compiled into the bridge.
//   * CPU constant/config helpers compiled from the pinned GPU headers:
//     FSR1 EASU/RCAS constant setup and SPD dispatch setup. These are the
//     engine-side data-plumbing entry points (constant-buffer values land in
//     caller-owned XIOM buffers).
//   * the vendored compiled shader blobs (frame-generation swapchain DXIL
//     byte payloads) as a read/query registry with SHA256 evidence.
//   * the complete header-declared per-effect host APIs (FSR2, FSR3
//     upscaler, frame interpolation, optical flow, SPD) as introspectable
//     surface records with a deterministic typed runtime classification:
//     the signed 2.3.0 binaries export the provider-based unified API only.
//
// Discipline (v0.64.4 findings B-20/B-23/B-24/B-25/B-26):
//   * handles cross as `Int`; pointers are only ever produced by
//     `Vec[UInt8]....as_mut_ptr()` (owned slots) -- never `Int as *UInt8`;
//   * nullable C pointer args are the `Int` literal 0 (never bare `null`);
//   * no foreign-pointer reads: every out-param is copied by the bridge into
//     an owned slot and read byte-indexed / via ffi helpers;
//   * flat outcome structs -- no `Result[Option[T]]`.

module xiom.fidelityfx

use xiom.convert;
use xiom.ffi;
use xiom.ffi.dl;
use xiom.string;
use xiom.fidelityfx.gen_types;
use xiom.fidelityfx.gen_structs;
use xiom.fidelityfx.gen_surface;

// =========================================================================
// Classification and typed errors
// =========================================================================

/// No candidate effect DLL resolved -> SKIP (CI without the SDK stays green).
pub const FFX_CLASS_OK: Int = 0;
pub const FFX_CLASS_ABSENT: Int = 1;      // no DLL -> SKIP
pub const FFX_CLASS_ABI: Int = 2;         // DLL present, entry points missing -> FAIL
pub const FFX_CLASS_API_ERROR: Int = 3;   // API returned a non-zero code -> FAIL
pub const FFX_CLASS_NO_DEVICE: Int = 4;   // typed headless no-device classification -> SKIP

/// Bridge-local typed errors (mirrored in src/ffx_bridge.cpp).
pub const FFX_BRIDGE_OK: Int = 0;
pub const FFX_BRIDGE_NULL: Int = -1;
pub const FFX_BRIDGE_RANGE: Int = -2;
pub const FFX_BRIDGE_ARG: Int = -3;

/// Flat load error (never `Result[Option[T]]`).
pub type FfxLoadError = {
  kind: Int;
  message: Str;
}

/// Flat probe outcome for one API call.
pub type FfxProbe = {
  ok: Bool;
  class: Int;
  code: Int;
  message: Str;
}

/// Flat context outcome: `handle != 0` only when create succeeded.
pub type FfxContextOutcome = {
  ok: Bool;
  class: Int;
  code: Int;
  handle: Int;
  message: Str;
}

/// One loaded effect module: the dl handle plus the five resolved unified
/// entry points. Owned by the caller; release with `ffx_engine_close`.
pub type FfxEngine = {
  handle: Int;
  soname: Str;
  p_create: Int;
  p_destroy: Int;
  p_configure: Int;
  p_query: Int;
  p_dispatch: Int;
  fns_mask: Int;
}

/// Flat versions-enumeration outcome (ffxQuery + ffxQueryDescGetVersions).
pub type FfxVersions = {
  ok: Bool;
  class: Int;
  code: Int;
  count: Int;
  first_id: Int;
  first_name: Str;
  message: Str;
}

/// Flat summary of the declared surface census.
pub type FfxSurfaceSummary = {
  ok: Bool;
  total: Int;
  callable: Int;
  metadata: Int;
  runtime_exports: Int;
  malformed: Int;
}

/// Flat host-API resolution report over a loaded engine.
pub type FfxHostReport = {
  ok: Bool;
  attempted: Int;
  resolved: Int;
  absent: Int;
  message: Str;
}

// =========================================================================
// Runtime loader (unified API)
// =========================================================================

/// The candidate shipped modules, in probe order: the loader first (it can
/// host any effect), then the upscaler and frame-generation effect DLLs.
/// Present-path proof: put the SDK `Kits/FidelityFX/signedbin` directory on
/// PATH (or set XIOM_FIDELITYFX_DIR) -- nothing is committed.
pub fn ffx_engine_load_named(soname: Str) -> Result[FfxEngine, FfxLoadError]
  requires: soname.len() > 0
{
  let r = dl.dl_open(soname);
  if !r.is_ok {
    return Err(FfxLoadError{ kind: FFX_CLASS_ABSENT; message: soname + ": " + r.error });
  }
  let h: Int = r.value;

  let s1 = dl.dl_sym(h, "ffxCreateContext");
  if !s1.is_ok { var c = dl.dl_close(h); return Err(FfxLoadError{ kind: FFX_CLASS_ABI; message: soname + ": ffxCreateContext: " + s1.error }); }
  let s2 = dl.dl_sym(h, "ffxDestroyContext");
  if !s2.is_ok { var c = dl.dl_close(h); return Err(FfxLoadError{ kind: FFX_CLASS_ABI; message: soname + ": ffxDestroyContext: " + s2.error }); }
  let s3 = dl.dl_sym(h, "ffxConfigure");
  if !s3.is_ok { var c = dl.dl_close(h); return Err(FfxLoadError{ kind: FFX_CLASS_ABI; message: soname + ": ffxConfigure: " + s3.error }); }
  let s4 = dl.dl_sym(h, "ffxQuery");
  if !s4.is_ok { var c = dl.dl_close(h); return Err(FfxLoadError{ kind: FFX_CLASS_ABI; message: soname + ": ffxQuery: " + s4.error }); }
  let s5 = dl.dl_sym(h, "ffxDispatch");
  if !s5.is_ok { var c = dl.dl_close(h); return Err(FfxLoadError{ kind: FFX_CLASS_ABI; message: soname + ": ffxDispatch: " + s5.error }); }

  return Ok(FfxEngine{
    handle: h;
    soname: soname;
    p_create: s1.value;
    p_destroy: s2.value;
    p_configure: s3.value;
    p_query: s4.value;
    p_dispatch: s5.value;
    fns_mask: 31;
  });
}

/// Load the first shipped module that resolves. All candidates absent ->
/// Err(FFX_CLASS_ABSENT) -> SKIP.
pub fn ffx_engine_load() -> Result[FfxEngine, FfxLoadError]
  requires: true
{
  let r1 = ffx_engine_load_named("amd_fidelityfx_loader_dx12.dll");
  if r1.is_ok { return Ok(r1.value); }
  if r1.error.kind == FFX_CLASS_ABI { return Err(r1.error); }

  let r2 = ffx_engine_load_named("amd_fidelityfx_upscaler_dx12.dll");
  if r2.is_ok { return Ok(r2.value); }
  if r2.error.kind == FFX_CLASS_ABI { return Err(r2.error); }

  let r3 = ffx_engine_load_named("amd_fidelityfx_framegeneration_dx12.dll");
  if r3.is_ok { return Ok(r3.value); }
  if r3.error.kind == FFX_CLASS_ABI { return Err(r3.error); }

  return Err(FfxLoadError{
    kind: FFX_CLASS_ABSENT;
    message: "fidelityfx: no effect module resolved (tried loader/upscaler/framegeneration)",
  });
}

/// Release the module handle. Idempotent for 0.
pub fn ffx_engine_close(engine: &FfxEngine) -> Result[Unit, Str]
  requires: true
{
  if engine.handle == 0 { return Ok(()); }
  let r = dl.dl_close(engine.handle);
  if !r.is_ok { return Err(r.error); }
  return Ok(());
}

// =========================================================================
// Unified API calls (five entry points)
// =========================================================================

/// ffxConfigure(NULL, {GLOBALDEBUG, level}) -- context-free global debug
/// configuration; succeeds headless (no device involved).
pub fn ffx_configure_global_debug(engine: &FfxEngine, debug_level: Int) -> FfxProbe
  requires: engine.p_configure != 0
  requires: debug_level >= 0
{
  var desc: Vec[UInt8] = owned_bytes(FFX_SIZEOF_ffxConfigureDescGlobalDebug);
  desc_set_u64(&desc, FFX_OFFSET_ffxConfigureDescGlobalDebug_header_type, FFX_API_CONFIGURE_DESC_TYPE_GLOBALDEBUG);
  desc_set_u64(&desc, FFX_OFFSET_ffxConfigureDescGlobalDebug_effectId, 0);
  desc_set_u64(&desc, FFX_OFFSET_ffxConfigureDescGlobalDebug_fpMessage, 0);
  desc_set_u32(&desc, FFX_OFFSET_ffxConfigureDescGlobalDebug_debugLevel, debug_level);
  unsafe {
    let f = engine.p_configure as fn(Int, *UInt8) -> Int32;
    let rc = f(0, desc.as_mut_ptr()) as Int;
    return ffx_classify(rc, "ffxConfigure(GLOBALDEBUG)");
  }
}

/// ffxCreateContext(&ctx, desc, NULL): `desc` is a caller-owned, pre-filled
/// descriptor buffer (see the descriptor builders). The context handle is
/// read from an owned 8-byte slot; `handle == 0` on failure.
pub fn ffx_create_context(engine: &FfxEngine, desc: &Vec[UInt8]) -> FfxContextOutcome
  requires: engine.p_create != 0
  requires: desc.len() >= 16
{
  var slot: Vec[UInt8] = owned_bytes(8);
  unsafe {
    let f = engine.p_create as fn(*UInt8, *UInt8, Int) -> Int32;
    let rc = f(slot.as_mut_ptr(), desc.as_mut_ptr(), 0) as Int;
    let handle = ffi.ptr_read_u64_le(slot.as_mut_ptr());
    if rc == 0 {
      return FfxContextOutcome{ ok: true; class: FFX_CLASS_OK; code: rc; handle: handle; message: "" };
    }
    let desc_type = desc_get_u64(desc, 0);
    let cls = ffx_class_for_create(rc, desc_type);
    return FfxContextOutcome{
      ok: false;
      class: cls;
      code: rc;
      handle: 0;
      message: "ffxCreateContext: " + str_from_code(rc),
    };
  }
}

/// Create-context classification: NO_PROVIDER on a device-requiring effect
/// descriptor is the typed headless no-device signal; NO_PROVIDER on any
/// other descriptor type is a plain API error.
fn ffx_class_for_create(rc: Int, desc_type: Int) -> Int
  requires: true
{
  let effect = desc_type & FFX_API_EFFECT_MASK;
  let device_requiring = effect == FFX_API_EFFECT_ID_UPSCALE
    || effect == FFX_API_EFFECT_ID_FRAMEGENERATION
    || effect == FFX_API_EFFECT_ID_FRAMEGENERATIONSWAPCHAIN;
  if device_requiring {
    // No provider served the create on this host: either the effect module
    // has no provider for the descriptor (NO_PROVIDER) or its provider
    // rejected context creation without a backend device (generic ERROR,
    // observed on the signed 2.3.0 upscaler/loader modules). Both are the
    // typed headless no-device signal.
    if rc == FFX_API_RETURN_NO_PROVIDER || rc == FFX_API_RETURN_ERROR {
      return FFX_CLASS_NO_DEVICE;
    }
  }
  return FFX_CLASS_API_ERROR;
}

/// ffxDestroyContext(&ctx, NULL). `handle` must come from a successful
/// create on this engine.
pub fn ffx_destroy_context(engine: &FfxEngine, handle: Int) -> FfxProbe
  requires: engine.p_destroy != 0
  requires: handle != 0
{
  var slot: Vec[UInt8] = owned_bytes(8);
  buf_write_u64(&slot, 0, handle);
  unsafe {
    let f = engine.p_destroy as fn(*UInt8, Int) -> Int32;
    let rc = f(slot.as_mut_ptr(), 0) as Int;
    return ffx_classify(rc, "ffxDestroyContext");
  }
}

/// ffxQuery(NULL, desc): context-free query (e.g. descriptor builders for
/// ffxQueryDescUpscaleGetUpscaleRatioFromQualityMode). Outputs are written
/// into the caller-owned `desc` buffer.
pub fn ffx_query(engine: &FfxEngine, desc: &Vec[UInt8]) -> FfxProbe
  requires: engine.p_query != 0
  requires: desc.len() >= 8
{
  unsafe {
    let f = engine.p_query as fn(Int, *UInt8) -> Int32;
    let rc = f(0, desc.as_mut_ptr()) as Int;
    return ffx_classify(rc, "ffxQuery");
  }
}

/// ffxDispatch(ctx, desc). Device-dependent: on a headless host the
/// classification is typed (NO_DEVICE / API_ERROR), never a crash.
pub fn ffx_dispatch(engine: &FfxEngine, handle: Int, desc: &Vec[UInt8]) -> FfxProbe
  requires: engine.p_dispatch != 0
  requires: handle != 0
  requires: desc.len() >= 8
{
  var slot: Vec[UInt8] = owned_bytes(8);
  buf_write_u64(&slot, 0, handle);
  unsafe {
    let f = engine.p_dispatch as fn(*UInt8, *UInt8) -> Int32;
    let rc = f(slot.as_mut_ptr(), desc.as_mut_ptr()) as Int;
    return ffx_classify(rc, "ffxDispatch");
  }
}

/// Enumerate provider versions for a create-descriptor type
/// (ffxQuery + ffxQueryDescGetVersions). `device` is `Int 0` on a headless
/// host. Returns the provider count and, when available, the first
/// version id/name.
pub fn ffx_query_versions(engine: &FfxEngine, create_desc_type: Int, device: Int) -> FfxVersions
  requires: engine.p_query != 0
{
  var desc: Vec[UInt8] = owned_bytes(FFX_SIZEOF_ffxQueryDescGetVersions);
  var ids: Vec[UInt8] = owned_bytes(8);
  var names: Vec[UInt8] = owned_bytes(8);
  desc_set_u64(&desc, FFX_OFFSET_ffxQueryDescGetVersions_header_type, FFX_API_QUERY_DESC_TYPE_GET_VERSIONS);
  desc_set_u64(&desc, FFX_OFFSET_ffxQueryDescGetVersions_createDescType, create_desc_type);
  desc_set_u64(&desc, FFX_OFFSET_ffxQueryDescGetVersions_device, device);
  unsafe {
    let f = engine.p_query as fn(Int, *UInt8) -> Int32;
    // first call: capacity 0 -> report the provider count into ids[0..8)
    buf_write_u64(&ids, 0, 0);
    desc_set_u64(&desc, FFX_OFFSET_ffxQueryDescGetVersions_outputCount, ids.as_mut_ptr() as Int);
    desc_set_u64(&desc, FFX_OFFSET_ffxQueryDescGetVersions_versionIds, 0);
    desc_set_u64(&desc, FFX_OFFSET_ffxQueryDescGetVersions_versionNames, 0);
    let rc = f(0, desc.as_mut_ptr()) as Int;
    if rc != 0 {
      return FfxVersions{ ok: false; class: ffx_class_for_code(rc); code: rc; count: 0; first_id: 0; first_name: ""; message: str_from_code(rc) };
    }
    let count = ffi.ptr_read_u64_le(ids.as_mut_ptr());
    if count == 0 {
      return FfxVersions{ ok: true; class: FFX_CLASS_OK; code: 0; count: 0; first_id: 0; first_name: ""; message: "" };
    }
    // second call: capacity 1 -> first version id + name
    buf_write_u64(&ids, 0, 1);
    buf_write_u64(&names, 0, 0);
    desc_set_u64(&desc, FFX_OFFSET_ffxQueryDescGetVersions_outputCount, ids.as_mut_ptr() as Int);
    desc_set_u64(&desc, FFX_OFFSET_ffxQueryDescGetVersions_versionIds, ids.as_mut_ptr() as Int);
    desc_set_u64(&desc, FFX_OFFSET_ffxQueryDescGetVersions_versionNames, names.as_mut_ptr() as Int);
    let rc2 = f(0, desc.as_mut_ptr()) as Int;
    if rc2 != 0 {
      // count is still valid evidence; only details failed
      return FfxVersions{ ok: true; class: FFX_CLASS_OK; code: 0; count: count; first_id: 0; first_name: ""; message: "details: " + str_from_code(rc2) };
    }
    let first_id = ffi.ptr_read_u64_le(ids.as_mut_ptr());
    let name_ptr = ffi.ptr_read_u64_le(names.as_mut_ptr());
    var name = "";
    if name_ptr != 0 {
      name = Str::from_c_str(name_ptr as *UInt8);
    }
    return FfxVersions{ ok: true; class: FFX_CLASS_OK; code: 0; count: count; first_id: first_id; first_name: name; message: "" };
  }
}

/// Classify a raw ffxReturnCode_t.
fn ffx_classify(rc: Int, what: Str) -> FfxProbe
  requires: true
{
  if rc == 0 {
    return FfxProbe{ ok: true; class: FFX_CLASS_OK; code: 0; message: "" };
  }
  return FfxProbe{
    ok: false;
    class: ffx_class_for_code(rc);
    code: rc;
    message: what + ": " + str_from_code(rc),
  };
}

/// The typed class for a non-zero return code. FFX_API_RETURN_NO_PROVIDER on
/// a device-requiring description is the headless no-device signal.
fn ffx_class_for_code(rc: Int) -> Int
  requires: true
{
  if rc == FFX_API_RETURN_NO_PROVIDER { return FFX_CLASS_NO_DEVICE; }
  if rc == FFX_API_RETURN_ERROR_PARAMETER { return FFX_CLASS_API_ERROR; }
  return FFX_CLASS_API_ERROR;
}

fn str_from_code(rc: Int) -> Str
  requires: true
{
  unsafe {
    let p = ffx_bridge_return_code_name(rc as Int32);
    if (p as Int) != 0 {
      return Str::from_c_str(p) + "(" + convert.int_to_string(rc) + ")";
    }
  }
  return "code " + convert.int_to_string(rc);
}

// =========================================================================
// Descriptor builders (owned buffers; offsets from gen_structs)
// =========================================================================

/// Zeroed, owned byte storage of exactly `size` readable bytes.
///
/// Deliberately NOT `Vec[UInt8].with_len`: stdlib 0.64.4 `Vec.reserve`
/// mishandles `cap == 0` (the "cap 0 -> 4" fix runs after the doubling loop),
/// so `with_len` can under-allocate and then zero `n * 8` bytes -- a heap
/// overflow (exposed by ASan, reproduced on this toolchain). `Vec.push`
/// grows correctly, so this helper fills the buffer one byte at a time.
pub fn owned_bytes(size: Int) -> Vec[UInt8]
  requires: size > 0
{
  var v: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < size {
    v.push(0 as UInt8);
    i = i + 1;
  }
  return v;
}

/// A zeroed, owned descriptor buffer of `size` bytes.
pub fn desc_new(size: Int) -> Vec[UInt8]
  requires: size > 0
{
  return owned_bytes(size);
}

// Owned-buffer little-endian writers. These intentionally do not use
// xiom.ffi.write_u32_at / write_u64_at: in stdlib 0.64.4 those helpers ignore
// their `offset` argument (write at 0), so descriptor field writes must go
// through byte stores on the owned slot pointer instead. Bounds are enforced
// by the callers' `requires` clauses.
fn buf_write_u32(buf: &Vec[UInt8], off: Int, v: Int)
  requires: off >= 0
  requires: off + 4 <= buf.len()
{
  unsafe {
    let p = buf.as_mut_ptr();
    p[off] = (v & 0xFF) as UInt8;
    p[off + 1] = ((v >> 8) & 0xFF) as UInt8;
    p[off + 2] = ((v >> 16) & 0xFF) as UInt8;
    p[off + 3] = ((v >> 24) & 0xFF) as UInt8;
  }
}

fn buf_write_u64(buf: &Vec[UInt8], off: Int, v: Int)
  requires: off >= 0
  requires: off + 8 <= buf.len()
{
  unsafe {
    let p = buf.as_mut_ptr();
    p[off] = (v & 0xFF) as UInt8;
    p[off + 1] = ((v >> 8) & 0xFF) as UInt8;
    p[off + 2] = ((v >> 16) & 0xFF) as UInt8;
    p[off + 3] = ((v >> 24) & 0xFF) as UInt8;
    p[off + 4] = ((v >> 32) & 0xFF) as UInt8;
    p[off + 5] = ((v >> 40) & 0xFF) as UInt8;
    p[off + 6] = ((v >> 48) & 0xFF) as UInt8;
    p[off + 7] = ((v >> 56) & 0xFF) as UInt8;
  }
}

/// Write the mandatory header (type + null pNext).
pub fn desc_set_header(desc: &Vec[UInt8], desc_type: Int)
  requires: desc.len() >= 16
{
  buf_write_u64(desc, 0, desc_type);
  buf_write_u64(desc, 8, 0);
}

pub fn desc_set_u32(desc: &Vec[UInt8], offset: Int, value: Int)
  requires: offset >= 0
  requires: offset + 4 <= desc.len()
{
  buf_write_u32(desc, offset, value);
}

pub fn desc_set_u64(desc: &Vec[UInt8], offset: Int, value: Int)
  requires: offset >= 0
  requires: offset + 8 <= desc.len()
{
  buf_write_u64(desc, offset, value);
}

pub fn desc_set_f32(desc: &Vec[UInt8], offset: Int, value: Float32)
  requires: offset >= 0
  requires: offset + 4 <= desc.len()
{
  ffi.write_f32_at(desc.as_mut_ptr() as Int, offset, value);
}

pub fn desc_get_u32(desc: &Vec[UInt8], offset: Int) -> Int
  requires: offset >= 0
  requires: offset + 4 <= desc.len()
{
  let b0 = desc[offset] as Int;
  let b1 = desc[offset + 1] as Int;
  let b2 = desc[offset + 2] as Int;
  let b3 = desc[offset + 3] as Int;
  return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
}

pub fn desc_get_u64(desc: &Vec[UInt8], offset: Int) -> Int
  requires: offset >= 0
  requires: offset + 8 <= desc.len()
{
  let lo = desc_get_u32(desc, offset);
  let hi = desc_get_u32(desc, offset + 4);
  return lo | (hi << 32);
}

/// Build an upscale create descriptor (ffxCreateContextDescUpscale).
pub fn desc_upscale_create(flags: Int, render_w: Int, render_h: Int, upscale_w: Int, upscale_h: Int) -> Vec[UInt8]
  requires: render_w > 0
  requires: render_h > 0
  requires: upscale_w > 0
  requires: upscale_h > 0
{
  var d: Vec[UInt8] = owned_bytes(FFX_SIZEOF_ffxCreateContextDescUpscale);
  desc_set_header(&d, FFX_API_CREATE_CONTEXT_DESC_TYPE_UPSCALE);
  desc_set_u32(&d, FFX_OFFSET_ffxCreateContextDescUpscale_flags, flags);
  desc_set_u32(&d, FFX_OFFSET_ffxCreateContextDescUpscale_maxRenderSize, render_w);
  desc_set_u32(&d, FFX_OFFSET_ffxCreateContextDescUpscale_maxRenderSize + 4, render_h);
  desc_set_u32(&d, FFX_OFFSET_ffxCreateContextDescUpscale_maxUpscaleSize, upscale_w);
  desc_set_u32(&d, FFX_OFFSET_ffxCreateContextDescUpscale_maxUpscaleSize + 4, upscale_h);
  return d;
}

/// Build an upscale dispatch descriptor (ffxDispatchDescUpscale) with the
/// scalar fields a headless data-plumbing check exercises.
pub fn desc_upscale_dispatch(render_w: Int, render_h: Int, upscale_w: Int, upscale_h: Int,
                             jitter_x: Float32, jitter_y: Float32,
                             mv_scale_x: Float32, mv_scale_y: Float32,
                             sharpness: Float32, frame_time_ms: Float32, reset: Bool) -> Vec[UInt8]
  requires: render_w > 0
  requires: render_h > 0
{
  var d: Vec[UInt8] = owned_bytes(FFX_SIZEOF_ffxDispatchDescUpscale);
  desc_set_header(&d, FFX_API_DISPATCH_DESC_TYPE_UPSCALE);
  desc_set_u32(&d, FFX_OFFSET_ffxDispatchDescUpscale_renderSize, render_w);
  desc_set_u32(&d, FFX_OFFSET_ffxDispatchDescUpscale_renderSize + 4, render_h);
  desc_set_u32(&d, FFX_OFFSET_ffxDispatchDescUpscale_upscaleSize, upscale_w);
  desc_set_u32(&d, FFX_OFFSET_ffxDispatchDescUpscale_upscaleSize + 4, upscale_h);
  desc_set_f32(&d, FFX_OFFSET_ffxDispatchDescUpscale_jitterOffset, jitter_x);
  desc_set_f32(&d, FFX_OFFSET_ffxDispatchDescUpscale_jitterOffset + 4, jitter_y);
  desc_set_f32(&d, FFX_OFFSET_ffxDispatchDescUpscale_motionVectorScale, mv_scale_x);
  desc_set_f32(&d, FFX_OFFSET_ffxDispatchDescUpscale_motionVectorScale + 4, mv_scale_y);
  desc_set_f32(&d, FFX_OFFSET_ffxDispatchDescUpscale_sharpness, sharpness);
  desc_set_f32(&d, FFX_OFFSET_ffxDispatchDescUpscale_frameTimeDelta, frame_time_ms);
  if reset {
    desc_set_u32(&d, FFX_OFFSET_ffxDispatchDescUpscale_reset, 1);
  } else {
    desc_set_u32(&d, FFX_OFFSET_ffxDispatchDescUpscale_reset, 0);
  }
  return d;
}

// =========================================================================
// CPU constant/config helpers (bridge-compiled pinned headers)
// =========================================================================

/// FSR1 EASU constants (ffxFsrPopulateEasuConstants): 4 x uint32x4 written
/// into the caller-owned 64-byte buffer, con0 first.
pub fn fsr1_easu_constants(out: &Vec[UInt8], viewport_x: Float32, viewport_y: Float32,
                           input_x: Float32, input_y: Float32,
                           output_x: Float32, output_y: Float32) -> FfxProbe
  requires: out.len() >= 64
{
  let rc = unsafe {
    ffx_bridge_fsr1_easu_constants(out.as_mut_ptr(),
                                   viewport_x, viewport_y, input_x, input_y, output_x, output_y) as Int
  };
  return ffx_bridge_probe(rc, "fsr1_easu_constants");
}

/// FSR1 EASU constants with a dynamic-resolution input offset.
pub fn fsr1_easu_constants_offset(out: &Vec[UInt8], viewport_x: Float32, viewport_y: Float32,
                                  input_x: Float32, input_y: Float32,
                                  output_x: Float32, output_y: Float32,
                                  offset_x: Float32, offset_y: Float32) -> FfxProbe
  requires: out.len() >= 64
{
  let rc = unsafe {
    ffx_bridge_fsr1_easu_constants_offset(out.as_mut_ptr(),
                                          viewport_x, viewport_y, input_x, input_y, output_x, output_y,
                                          offset_x, offset_y) as Int
  };
  return ffx_bridge_probe(rc, "fsr1_easu_constants_offset");
}

/// FSR1 RCAS constants (FsrRcasCon): one uint32x4 into a 16-byte slot.
pub fn fsr1_rcas_constants(out: &Vec[UInt8], sharpness: Float32) -> FfxProbe
  requires: out.len() >= 16
{
  let rc = unsafe { ffx_bridge_fsr1_rcas_constants(out.as_mut_ptr(), sharpness) as Int };
  return ffx_bridge_probe(rc, "fsr1_rcas_constants");
}

/// SPD dispatch setup (ffxSpdSetup, CPU path): dispatchThreadGroupCountXY(8) +
/// workGroupOffset(8) + numWorkGroupsAndMips(8) into a 24-byte buffer.
pub fn spd_setup(out: &Vec[UInt8], left: Int, top: Int, width: Int, height: Int, mips: Int) -> FfxProbe
  requires: out.len() >= 24
  requires: left >= 0
  requires: top >= 0
  requires: width >= 0
  requires: height >= 0
  requires: mips >= -1
{
  let rc = unsafe {
    ffx_bridge_spd_setup(out.as_mut_ptr(), left as Int32, top as Int32, width as Int32, height as Int32, mips as Int32) as Int
  };
  return ffx_bridge_probe(rc, "spd_setup");
}

fn ffx_bridge_probe(rc: Int, what: Str) -> FfxProbe
  requires: true
{
  if rc == FFX_BRIDGE_OK {
    return FfxProbe{ ok: true; class: FFX_CLASS_OK; code: 0; message: "" };
  }
  unsafe {
    let p = ffx_bridge_bridge_error_name(rc as Int32);
    var name = "bridge";
    if (p as Int) != 0 { name = Str::from_c_str(p); }
    return FfxProbe{ ok: false; class: FFX_CLASS_API_ERROR; code: rc; message: what + ": " + name };
  }
}

// =========================================================================
// Version probes (compiled from the pinned headers)
// =========================================================================

/// SDK version packed major<<16 | minor<<8 | patch (2.3.0 at this pin).
pub fn ffx_sdk_version() -> Int
  requires: true
{
  return unsafe { ffx_bridge_sdk_version() as Int };
}

/// Component version: 0 fsr2, 1 fsr3upscaler, 2 frameinterpolation,
/// 3 spd, 4 upscaler-api, 5 framegeneration-api; -1 unknown.
pub fn ffx_component_version(id: Int) -> Int
  requires: id >= 0
{
  return unsafe { ffx_bridge_effect_version(id as Int32) as Int };
}

/// The SDK's own loader helper (ffxLoadFunctions) bound from the vendored
/// header: fills five pointers into the caller-owned >= 40-byte slot and
/// returns a bitmask of the ones that resolved.
pub fn ffx_load_functions(out: &Vec[UInt8], module_handle: Int) -> Int
  requires: out.len() >= 40
  requires: module_handle != 0
{
  return unsafe { ffx_bridge_load_functions(out.as_mut_ptr() as Int, module_handle) as Int };
}

pub fn ffx_functions_size() -> Int
  requires: true
{
  return unsafe { ffx_bridge_functions_size() as Int };
}

// =========================================================================
// Vendored compiled shader blobs (registry)
// =========================================================================

pub fn ffx_blob_count() -> Int
  requires: true
{
  return unsafe { ffx_bridge_blob_count() as Int };
}

pub fn ffx_blob_size(i: Int) -> Int
  requires: i >= 0
{
  return unsafe { ffx_bridge_blob_size(i as Int32) as Int };
}

pub fn ffx_blob_name(i: Int) -> Str
  requires: i >= 0
{
  unsafe {
    let p = ffx_bridge_blob_name(i as Int32);
    if (p as Int) != 0 { return Str::from_c_str(p); }
  }
  return "";
}

pub fn ffx_blob_kind(i: Int) -> Str
  requires: i >= 0
{
  unsafe {
    let p = ffx_bridge_blob_kind(i as Int32);
    if (p as Int) != 0 { return Str::from_c_str(p); }
  }
  return "";
}

pub fn ffx_blob_file(i: Int) -> Str
  requires: i >= 0
{
  unsafe {
    let p = ffx_bridge_blob_file(i as Int32);
    if (p as Int) != 0 { return Str::from_c_str(p); }
  }
  return "";
}

/// Copy blob `i`'s payload into the caller-owned buffer (`out.len()` must be
/// >= the blob size). Returns the payload size or a negative typed error.
pub fn ffx_blob_read(i: Int, out: &Vec[UInt8]) -> Int
  requires: i >= 0
{
  return unsafe { ffx_bridge_blob_read(i as Int32, out.as_mut_ptr(), out.len() as Int64) as Int };
}

// =========================================================================
// Declared-surface census and runtime host-API classification
// =========================================================================

/// Census summary over the generated surface records.
pub fn surface_summary() -> FfxSurfaceSummary
  requires: true
{
  let n = surface_count();
  var callable = 0;
  var metadata = 0;
  var exports = 0;
  var malformed = 0;
  var i = 0;
  while i < n {
    let nm = surface_name(i);
    let comp = surface_component(i);
    let kind = surface_kind(i);
    let hdr = surface_header(i);
    let sig = surface_signature(i);
    if nm.len() == 0 || comp.len() == 0 || kind.len() == 0 || hdr.len() == 0 || sig.len() == 0 {
      malformed = malformed + 1;
    }
    if surface_callable(i) {
      callable = callable + 1;
    } else {
      metadata = metadata + 1;
    }
    if surface_runtime_export(i) {
      exports = exports + 1;
    }
    i = i + 1;
  }
  return FfxSurfaceSummary{
    ok: malformed == 0 && callable + metadata == n;
    total: n;
    callable: callable;
    metadata: metadata;
    runtime_exports: exports;
    malformed: malformed;
  };
}

/// Resolve every declared host-API / inline-helper record by name against
/// the loaded module. The signed 2.3.0 binaries export the five unified
/// entry points only, so every host record classifies ABSENT -- a typed,
/// deterministic result (never a silent gap). A source-built module that
/// exports legacy names flips the count honestly.
pub fn host_api_resolve_report(engine: &FfxEngine) -> FfxHostReport
  requires: engine.handle != 0
{
  let n = surface_count();
  var attempted = 0;
  var resolved = 0;
  var i = 0;
  while i < n {
    let kind = surface_kind(i);
    if str_compare(kind, "hostapi") == 0 || str_compare(kind, "inline") == 0 {
      attempted = attempted + 1;
      let nm = surface_name(i);
      let s = dl.dl_sym(engine.handle, nm);
      if s.is_ok {
        resolved = resolved + 1;
      }
    }
    i = i + 1;
  }
  return FfxHostReport{
    ok: true;
    attempted: attempted;
    resolved: resolved;
    absent: attempted - resolved;
    message: "";
  };
}

// =========================================================================
// Bridge externs
// =========================================================================

extern "C" {
  fn ffx_bridge_sdk_version() -> Int32;
  fn ffx_bridge_effect_version(id: Int32) -> Int32;
  fn ffx_bridge_functions_size() -> Int32;
  fn ffx_bridge_load_functions(out_slot: Int64, module_handle: Int64) -> Int32;
  fn ffx_bridge_return_code_name(code: Int32) -> *UInt8;
  fn ffx_bridge_bridge_error_name(code: Int32) -> *UInt8;
  fn ffx_bridge_fsr1_easu_constants(out64: *UInt8,
                                    viewport_x: Float32, viewport_y: Float32,
                                    input_x: Float32, input_y: Float32,
                                    output_x: Float32, output_y: Float32) -> Int32;
  fn ffx_bridge_fsr1_easu_constants_offset(out64: *UInt8,
                                           viewport_x: Float32, viewport_y: Float32,
                                           input_x: Float32, input_y: Float32,
                                           output_x: Float32, output_y: Float32,
                                           offset_x: Float32, offset_y: Float32) -> Int32;
  fn ffx_bridge_fsr1_rcas_constants(con: *UInt8, sharpness: Float32) -> Int32;
  fn ffx_bridge_spd_setup(out24: *UInt8,
                          left: Int32, top: Int32, width: Int32, height: Int32, mips: Int32) -> Int32;
  fn ffx_bridge_blob_count() -> Int32;
  fn ffx_bridge_blob_size(i: Int32) -> Int64;
  fn ffx_bridge_blob_read(i: Int32, out: *UInt8, cap: Int64) -> Int32;
  fn ffx_bridge_blob_name(i: Int32) -> *UInt8;
  fn ffx_bridge_blob_kind(i: Int32) -> *UInt8;
  fn ffx_bridge_blob_file(i: Int32) -> *UInt8;
}
