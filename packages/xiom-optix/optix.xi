// XIOM -- xiom.optix: NVIDIA OptiX ray-tracing engine bindings.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: reference-only dynamic loader -- **nothing is vendored**.
// `nvoptix.dll` is the OptiX runtime shipped with the user's NVIDIA display
// driver (the full SDK is registration-gated and user-supplied; see
// PROVENANCE.md).  The bridge (src/optix_bridge.c) loads the module at run
// time, resolves the single export `optixQueryFunctionTable`, and queries the
// pinned ABI 118 function table.  No OptiX header, import library, sample or
// binary is committed or linked at build time.
//
// Declared essentials (0.1.0): device-context create/destroy/validate with
// options, PTX module load, raygen/miss/hitgroup program groups, SBT build,
// pipeline create, launch-params buffer, and launch.  Typed errors carry the
// native OptixResult; the suite classifies a missing runtime / no CUDA device
// as SKIP and an ABI mismatch as FAIL.
//
// All `unsafe`/`extern "C"` live in this single module (G5).  Handles cross
// as `Int` (B-25); owned Vec[UInt8] slots are the only byte buffers the
// bridge writes; nullable C pointers are represented by empty strings or the
// handle-0 sentinel, never a bare `null` (B-23).

module xiom.optix

extern "C" {
  fn optixp_probe_named(dll: *UInt8, live: Int32) -> Int;
  fn optixp_probe() -> Int;
  fn optixp_last_error() -> *UInt8;
  fn optixp_last_native() -> Int;
  fn optixp_abi_version() -> Int32;
  fn optixp_rtcore_version() -> Int32;
  fn optixp_max_trace_depth() -> Int32;
  fn optixp_cache_enabled() -> Int32;
  fn optixp_device_name() -> *UInt8;
  fn optixp_abi_pin() -> Int32;

  fn optixp_ctx_create(validation: Int32, log_level: Int32, cache: Int32,
                       cache_location: *UInt8) -> Int;
  fn optixp_ctx_validate(ctx: Int) -> Int32;
  fn optixp_ctx_destroy(ctx: Int) -> Int32;

  fn optixp_module_load(ctx: Int, ptx: *UInt8, ptx_size: Int64,
                        params_name: *UInt8, params_size: Int64) -> Int;
  fn optixp_module_destroy(mod_handle: Int) -> Int32;

  fn optixp_pg_create(ctx: Int, mod_handle: Int, entry: *UInt8, kind: Int32) -> Int;
  fn optixp_pg_destroy(pg: Int) -> Int32;

  fn optixp_sbt_build(ctx: Int, raygen: Int, miss: Int, hit: Int,
                      record_size: Int32) -> Int;
  fn optixp_sbt_destroy(sbt: Int) -> Int32;
  fn optixp_sbt_record_size(sbt: Int) -> Int32;
  fn optixp_sbt_record_count(sbt: Int) -> Int32;
  fn optixp_sbt_read_record(sbt: Int, index: Int32, out: *UInt8,
                            out_size: Int64) -> Int32;

  fn optixp_pipeline_create(ctx: Int, raygen: Int, miss: Int, hit: Int,
                            params_name: *UInt8, params_size: Int64,
                            max_trace_depth: Int32) -> Int;
  fn optixp_pipeline_destroy(pipeline: Int) -> Int32;

  fn optixp_params_create(ctx: Int, size: Int64) -> Int;
  fn optixp_params_write(params: Int, data: *UInt8, size: Int64) -> Int32;
  fn optixp_params_read(params: Int, out: *UInt8, size: Int64) -> Int32;
  fn optixp_params_destroy(params: Int) -> Int32;

  fn optixp_launch(pipeline: Int, params: Int, sbt: Int, width: Int32,
                   height: Int32, depth: Int32) -> Int32;
}

// =========================================================================
// Identity, ABI pin, and classification
// =========================================================================

/// Pinned OptiX ABI (OptiX 9.1, OPTIX_ABI_VERSION 118).
pub const OPTIX_ABI_PIN: Int = 118;

/// Pinned SBT record header size and alignment (optix_types.h @ 9.1).
pub const OPTIX_SBT_RECORD_HEADER_SIZE: Int = 32;
pub const OPTIX_SBT_RECORD_ALIGNMENT: Int = 16;

/// Program-group kinds understood by the 0.1.0 essentials surface.
pub const OPTIX_PROGRAM_GROUP_RAYGEN: Int = 0;
pub const OPTIX_PROGRAM_GROUP_MISS: Int = 1;
pub const OPTIX_PROGRAM_GROUP_HITGROUP: Int = 2;

/// Typed error kinds (mirrored by src/optix_bridge.c).
pub const OPTIX_ERR_LOADER_ABSENT: Int = 0;  // no nvoptix.dll -> SKIP
pub const OPTIX_ERR_NO_DEVICE: Int = 1;      // no CUDA device -> SKIP
pub const OPTIX_ERR_ABI: Int = 2;            // runtime present, ABI mismatch -> FAIL
pub const OPTIX_ERR_ARG: Int = 3;
pub const OPTIX_ERR_CONTEXT: Int = 4;
pub const OPTIX_ERR_MODULE: Int = 5;
pub const OPTIX_ERR_PROGRAM_GROUP: Int = 6;
pub const OPTIX_ERR_PIPELINE: Int = 7;
pub const OPTIX_ERR_SBT: Int = 8;
pub const OPTIX_ERR_LAUNCH_PARAMS: Int = 9;
pub const OPTIX_ERR_LAUNCH: Int = 10;
pub const OPTIX_ERR_OUT_OF_MEMORY: Int = 11;
pub const OPTIX_ERR_RUNTIME: Int = 12;

pub type OptixError = {
  kind: Int;
  code: Int;      // native OptixResult (0 for bridge-local errors)
  message: Str;
}

pub type OptixInfo = {
  abi_version: Int;      // pinned ABI (118)
  rtcore_version: Int;   // e.g. 20 = RT core 2.0
  max_trace_depth: Int;  // device limit (typically 31)
  cache_enabled: Bool;   // OptiX disk cache state
  device_name: Str;      // CUDA device 0
}

pub type OptixContextOptions = {
  validation_mode: Bool;
  log_level: Int;        // 0..4, passed to OptixDeviceContextOptions
  cache_enabled: Bool;
  cache_location: Str;   // "" = driver default
}

pub type OptixContext = { handle: Int; }
pub type OptixModule = { handle: Int; }
pub type OptixProgramGroup = { handle: Int; }
pub type OptixSbt = { handle: Int; }
pub type OptixPipeline = { handle: Int; }
pub type OptixParams = { handle: Int; }

/// The absent/null program-group sentinel for optional SBT slots
/// (raygen is mandatory; miss/hit may be omitted).
/// Complexity: O(1).
pub fn optix_program_group_none() -> OptixProgramGroup
  requires: true
{
  return OptixProgramGroup{ handle: 0 };
}

/// Human name for a typed error kind.
/// Complexity: O(1).
pub fn optix_error_kind_name(kind: Int) -> Str
  requires: kind >= 0
{
  if kind == OPTIX_ERR_LOADER_ABSENT { return "loader-absent"; }
  if kind == OPTIX_ERR_NO_DEVICE { return "no-device"; }
  if kind == OPTIX_ERR_ABI { return "abi"; }
  if kind == OPTIX_ERR_ARG { return "argument"; }
  if kind == OPTIX_ERR_CONTEXT { return "context"; }
  if kind == OPTIX_ERR_MODULE { return "module"; }
  if kind == OPTIX_ERR_PROGRAM_GROUP { return "program-group"; }
  if kind == OPTIX_ERR_PIPELINE { return "pipeline"; }
  if kind == OPTIX_ERR_SBT { return "sbt"; }
  if kind == OPTIX_ERR_LAUNCH_PARAMS { return "launch-params"; }
  if kind == OPTIX_ERR_LAUNCH { return "launch"; }
  if kind == OPTIX_ERR_OUT_OF_MEMORY { return "out-of-memory"; }
  if kind == OPTIX_ERR_RUNTIME { return "runtime"; }
  return "unknown";
}

/// True when the typed error is the SKIP classification (runtime absent or
/// no CUDA device).  ABI mismatches are not SKIPs.
/// Complexity: O(1).
pub fn optix_error_is_skip(error: OptixError) -> Bool
  requires: true
{
  return error.kind == OPTIX_ERR_LOADER_ABSENT || error.kind == OPTIX_ERR_NO_DEVICE;
}

/// Round a requested SBT record size up to the header minimum and the
/// 16-byte OPTIX_SBT_RECORD_ALIGNMENT (the bridge performs the same math).
/// Complexity: O(1).
pub fn optix_sbt_record_size_for(requested: Int) -> Int
  requires: requested > 0
{
  var size = requested;
  if size < OPTIX_SBT_RECORD_HEADER_SIZE {
    size = OPTIX_SBT_RECORD_HEADER_SIZE;
  }
  let remainder = size % OPTIX_SBT_RECORD_ALIGNMENT;
  if remainder != 0 {
    size = size + (OPTIX_SBT_RECORD_ALIGNMENT - remainder);
  }
  return size;
}

/// The bridge's last human-readable error message (diagnostics for failed
/// destroy/Bool calls).  Complexity: O(1).
pub fn optix_last_error_message() -> Str
  requires: true
{
  return unsafe { Str::from_c_str(optixp_last_error()) };
}

/// The bridge's last native OptixResult.  Complexity: O(1).
pub fn optix_last_native_code() -> Int
  requires: true
{
  return unsafe { optixp_last_native() as Int };
}

// =========================================================================
// Probe
// =========================================================================

/// Probe the default runtime: auto-discover nvoptix.dll (XIOM_OPTIX_DLL,
/// module search path, Program Files, System32, DriverStore), query ABI 118,
/// create a CUDA + OptiX device context, query RTCore/max-trace-depth, set
/// the cache, then tear everything down.  Runtime absent / no CUDA device ->
/// typed SKIP error; ABI mismatch -> typed FAIL error.
/// Complexity: O(load + context bring-up).
pub fn optix_probe() -> Result[OptixInfo, OptixError]
  requires: true
{
  let rc = unsafe { optixp_probe() as Int };
  if rc != 0 {
    return Err(optix_error_from(rc));
  }
  return Ok(optix_info());
}

/// Same probe against an explicitly named runtime path.  A bogus path
/// exercises the deterministic LOADER_ABSENT/SKIP classification on any host.
/// `live = false` performs only the load + ABI query (no CUDA context).
/// Complexity: O(load + context bring-up).
pub fn optix_probe_named(dll_path: Str, live: Bool) -> Result[OptixInfo, OptixError]
  requires: dll_path.len() > 0
{
  let rc = unsafe { optixp_probe_named(dll_path.c_str(), optix_bool(live) as Int32) as Int };
  if rc != 0 {
    return Err(optix_error_from(rc));
  }
  return Ok(optix_info());
}

// =========================================================================
// Device context
// =========================================================================

/// Create a CUDA context on device 0 plus an OptiX device context with the
/// requested options.  The OptiX disk cache is configured before return.
/// Complexity: O(context bring-up).
pub fn optix_context_create(options: OptixContextOptions) -> Result[OptixContext, OptixError]
  requires: options.log_level >= 0 && options.log_level <= 4
{
  let handle = unsafe {
    optixp_ctx_create(optix_bool(options.validation_mode) as Int32,
                      options.log_level as Int32,
                      optix_bool(options.cache_enabled) as Int32,
                      options.cache_location.c_str()) as Int
  };
  if handle < 0 {
    return Err(optix_error_from(handle));
  }
  if handle == 0 {
    return Err(optix_bridge_error(OPTIX_ERR_CONTEXT, "context create returned null"));
  }
  return Ok(OptixContext{ handle: handle });
}

/// Validate a live context by querying its device properties and cache state.
/// Complexity: O(1).
pub fn optix_context_validate(ctx: OptixContext) -> Result[OptixInfo, OptixError]
  requires: ctx.handle > 0
{
  let rc = unsafe { optixp_ctx_validate(ctx.handle) as Int };
  if rc != 0 {
    return Err(optix_error_from(rc));
  }
  return Ok(optix_info());
}

/// Destroy the OptiX context and its CUDA context.  All modules, program
/// groups, SBTs, pipelines and params buffers must be destroyed first.
/// Complexity: O(context teardown).
pub fn optix_context_destroy(ctx: OptixContext) -> Bool
  requires: ctx.handle > 0
{
  let rc = unsafe { optixp_ctx_destroy(ctx.handle) as Int };
  return rc == 0;
}

// =========================================================================
// Module
// =========================================================================

/// Load a PTX module.  The launch-params variable name and size must match
/// the PTX (`params_size = 0` declares no launch params).  Returns a typed
/// module error carrying the compiler log on failure.
/// Complexity: O(PTX compile).
pub fn optix_module_load(ctx: OptixContext, ptx: Str, params_name: Str,
                         params_size: Int) -> Result[OptixModule, OptixError]
  requires: ctx.handle > 0
  requires: ptx.len() > 0
  requires: params_size >= 0
  requires: params_size == 0 || params_name.len() > 0
{
  let handle = unsafe {
    optixp_module_load(ctx.handle, ptx.c_str(), ptx.len() as Int64,
                       params_name.c_str(), params_size as Int64) as Int
  };
  if handle < 0 {
    return Err(optix_error_from(handle));
  }
  if handle == 0 {
    return Err(optix_bridge_error(OPTIX_ERR_MODULE, "module load returned null"));
  }
  return Ok(OptixModule{ handle: handle });
}

/// Destroy a module.  Complexity: O(1).
pub fn optix_module_destroy(mod: OptixModule) -> Bool
  requires: mod.handle > 0
{
  let rc = unsafe { optixp_module_destroy(mod.handle) as Int };
  return rc == 0;
}

// =========================================================================
// Program groups
// =========================================================================

/// Create a raygen, miss, or hitgroup (closest-hit) program group.
/// A miss group may be created with the zero module handle and an empty
/// entry string (the OptiX "null miss" form); raygen/hitgroup need both.
/// Complexity: O(program-group create).
pub fn optix_program_group_create(ctx: OptixContext, program_module: OptixModule,
                                  entry: Str, kind: Int) -> Result[OptixProgramGroup, OptixError]
  requires: ctx.handle > 0
  requires: kind >= 0 && kind <= 2
  requires: kind == 1 || (program_module.handle > 0 && entry.len() > 0)
{
  let handle = unsafe {
    optixp_pg_create(ctx.handle, program_module.handle, entry.c_str(), kind as Int32) as Int
  };
  if handle < 0 {
    return Err(optix_error_from(handle));
  }
  if handle == 0 {
    return Err(optix_bridge_error(OPTIX_ERR_PROGRAM_GROUP, "program group create returned null"));
  }
  return Ok(OptixProgramGroup{ handle: handle });
}

/// Destroy a program group.  Complexity: O(1).
pub fn optix_program_group_destroy(group: OptixProgramGroup) -> Bool
  requires: group.handle > 0
{
  let rc = unsafe { optixp_pg_destroy(group.handle) as Int };
  return rc == 0;
}

// =========================================================================
// Shader binding table
// =========================================================================

/// Build a one-record-per-kind SBT (raygen/miss/hitgroup).  The record size
/// is the header (32 B) plus caller data, rounded to 16 B.  Pass
/// optix_program_group_none() for an omitted kind; at least one group is
/// required.  Complexity: O(records + device copy).
pub fn optix_sbt_build(ctx: OptixContext, raygen: OptixProgramGroup,
                       miss: OptixProgramGroup, hitgroup: OptixProgramGroup,
                       record_size: Int) -> Result[OptixSbt, OptixError]
  requires: ctx.handle > 0
  requires: record_size > 0
{
  let handle = unsafe {
    optixp_sbt_build(ctx.handle, raygen.handle, miss.handle, hitgroup.handle,
                     record_size as Int32) as Int
  };
  if handle < 0 {
    return Err(optix_error_from(handle));
  }
  if handle == 0 {
    return Err(optix_bridge_error(OPTIX_ERR_SBT, "SBT build returned null"));
  }
  return Ok(OptixSbt{ handle: handle });
}

/// The aligned record size the bridge used.  Complexity: O(1).
pub fn optix_sbt_get_record_size(sbt: OptixSbt) -> Int
  requires: sbt.handle > 0
{
  return unsafe { optixp_sbt_record_size(sbt.handle) as Int };
}

/// Number of records in the SBT (0 when the handle is invalid).  Complexity: O(1).
pub fn optix_sbt_get_record_count(sbt: OptixSbt) -> Int
  requires: sbt.handle > 0
{
  return unsafe { optixp_sbt_record_count(sbt.handle) as Int };
}

/// Read `out.len()` bytes of a device-resident SBT record into an owned
/// XIOM slot (device -> host copy).  Complexity: O(copy).
pub fn optix_sbt_read_record(sbt: OptixSbt, index: Int,
                             out: &mut Vec[UInt8]) -> Result[Bool, OptixError]
  requires: sbt.handle > 0
  requires: index >= 0
  requires: out.len() > 0
{
  let rc = unsafe {
    optixp_sbt_read_record(sbt.handle, index as Int32, out.as_mut_ptr(),
                           out.len() as Int64) as Int
  };
  if rc != 0 {
    return Err(optix_error_from(rc));
  }
  return Ok(true);
}

/// Destroy the SBT and its device buffer.  Complexity: O(1).
pub fn optix_sbt_destroy(sbt: OptixSbt) -> Bool
  requires: sbt.handle > 0
{
  let rc = unsafe { optixp_sbt_destroy(sbt.handle) as Int };
  return rc == 0;
}

// =========================================================================
// Pipeline
// =========================================================================

/// Create and link a pipeline from the supplied program groups.  `params_name`
/// and `params_size` must match the module's launch-params declaration.  The
/// runtime validates the link and returns a typed pipeline error with its log
/// when, for example, no raygen group is present.
/// Complexity: O(pipeline link).
pub fn optix_pipeline_create(ctx: OptixContext, raygen: OptixProgramGroup,
                             miss: OptixProgramGroup, hitgroup: OptixProgramGroup,
                             params_name: Str, params_size: Int,
                             max_trace_depth: Int) -> Result[OptixPipeline, OptixError]
  requires: ctx.handle > 0
  requires: params_size >= 0
  requires: params_size == 0 || params_name.len() > 0
  requires: max_trace_depth >= 0 && max_trace_depth <= 31
{
  let handle = unsafe {
    optixp_pipeline_create(ctx.handle, raygen.handle, miss.handle,
                           hitgroup.handle, params_name.c_str(),
                           params_size as Int64, max_trace_depth as Int32) as Int
  };
  if handle < 0 {
    return Err(optix_error_from(handle));
  }
  if handle == 0 {
    return Err(optix_bridge_error(OPTIX_ERR_PIPELINE, "pipeline create returned null"));
  }
  return Ok(OptixPipeline{ handle: handle });
}

/// Destroy a pipeline.  Complexity: O(1).
pub fn optix_pipeline_destroy(pipeline: OptixPipeline) -> Bool
  requires: pipeline.handle > 0
{
  let rc = unsafe { optixp_pipeline_destroy(pipeline.handle) as Int };
  return rc == 0;
}

// =========================================================================
// Launch params buffer
// =========================================================================

/// Allocate a device-resident launch-params buffer of `size` bytes.
/// Complexity: O(alloc).
pub fn optix_params_create(ctx: OptixContext, size: Int) -> Result[OptixParams, OptixError]
  requires: ctx.handle > 0
  requires: size > 0
{
  let handle = unsafe { optixp_params_create(ctx.handle, size as Int64) as Int };
  if handle < 0 {
    return Err(optix_error_from(handle));
  }
  if handle == 0 {
    return Err(optix_bridge_error(OPTIX_ERR_LAUNCH_PARAMS, "params create returned null"));
  }
  return Ok(OptixParams{ handle: handle });
}

/// Upload `data.len()` bytes from an owned XIOM slot to the device buffer
/// (host -> device copy).  Complexity: O(copy).
pub fn optix_params_write(params: OptixParams, data: &Vec[UInt8]) -> Result[Bool, OptixError]
  requires: params.handle > 0
  requires: data.len() > 0
{
  let rc = unsafe {
    optixp_params_write(params.handle, data.as_ptr(), data.len() as Int64) as Int
  };
  if rc != 0 {
    return Err(optix_error_from(rc));
  }
  return Ok(true);
}

/// Download `out.len()` bytes from the device buffer into an owned XIOM slot
/// (device -> host copy; useful for verification).  Complexity: O(copy).
pub fn optix_params_read(params: OptixParams, out: &mut Vec[UInt8]) -> Result[Bool, OptixError]
  requires: params.handle > 0
  requires: out.len() > 0
{
  let rc = unsafe {
    optixp_params_read(params.handle, out.as_mut_ptr(), out.len() as Int64) as Int
  };
  if rc != 0 {
    return Err(optix_error_from(rc));
  }
  return Ok(true);
}

/// Free the launch-params device buffer.  Complexity: O(1).
pub fn optix_params_destroy(params: OptixParams) -> Bool
  requires: params.handle > 0
{
  let rc = unsafe { optixp_params_destroy(params.handle) as Int };
  return rc == 0;
}

// =========================================================================
// Launch
// =========================================================================

/// Launch the pipeline on the default CUDA stream and synchronize before
/// returning, so runtime launch failures become typed errors.  The params
/// buffer size must match the pipeline's declared launch-params size.
/// Complexity: O(launch + sync).
pub fn optix_launch(pipeline: OptixPipeline, params: OptixParams,
                    sbt: OptixSbt, width: Int, height: Int,
                    depth: Int) -> Result[Bool, OptixError]
  requires: pipeline.handle > 0
  requires: params.handle > 0
  requires: sbt.handle > 0
  requires: width > 0 && height > 0 && depth > 0
{
  let rc = unsafe {
    optixp_launch(pipeline.handle, params.handle, sbt.handle, width as Int32,
                  height as Int32, depth as Int32) as Int
  };
  if rc != 0 {
    return Err(optix_error_from(rc));
  }
  return Ok(true);
}

// =========================================================================
// Internals
// =========================================================================

fn optix_bool(value: Bool) -> Int
  requires: true
{
  if value { return 1; }
  return 0;
}

fn optix_bridge_error(kind: Int, message: Str) -> OptixError
  requires: kind >= 0 && kind <= 12
{
  return OptixError{ kind: kind; code: 0; message: message };
}

fn optix_error_from(rc: Int) -> OptixError
  requires: rc < 0
{
  var kind = (0 - rc) - 100;
  if kind < 0 || kind > 12 {
    kind = OPTIX_ERR_RUNTIME;
  }
  let native = unsafe { optixp_last_native() as Int };
  let message = unsafe { Str::from_c_str(optixp_last_error()) };
  return OptixError{ kind: kind; code: native; message: message };
}

fn optix_info() -> OptixInfo
  requires: true
{
  return OptixInfo{
    abi_version: unsafe { optixp_abi_version() as Int };
    rtcore_version: unsafe { optixp_rtcore_version() as Int };
    max_trace_depth: unsafe { optixp_max_trace_depth() as Int };
    cache_enabled: unsafe { optixp_cache_enabled() as Int } != 0;
    device_name: unsafe { Str::from_c_str(optixp_device_name()) };
  };
}


