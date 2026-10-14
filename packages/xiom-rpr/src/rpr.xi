// XIOM -- xiom.rpr: AMD Radeon ProRender SDK core-API bindings.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Public safe API over the Radeon ProRender 3.1.7.1 core C API.  This module
// contains no `unsafe`: every foreign call goes through the confined FFI core
// in `xiom.rpr.ffi` (G5), which talks to the runtime-loader bridge
// `src/rpr_bridge.c`.  Nothing from the SDK binaries is vendored; the host
// library `RadeonProRender64.dll` is loaded at runtime and the suite reports
// a typed SKIP when it (or a backend plugin) is absent (SPEC.md sec. 3/5).
//
// Object model: RPR objects are opaque handles; they cross this boundary as
// nominal XIOM types wrapping a small integer id (the pointer lives only in
// the bridge registry -- B-25/B-20 discipline).  Every fallible call returns
// `Result[_, RprError]` with a typed kind and the raw code.
//
// Error kinds: RPR_KIND_API is the rpr_status of the underlying call;
// RPR_KIND_LOAD_ABSENT / RPR_KIND_PLUGIN are the SKIP-class states
// (host library / backend plugin absent); the remaining kinds are bridge
// argument/handle errors.

module xiom.rpr

use xiom.convert;
use xiom.rpr.ffi;

// --- pinned constants (vendor/rpr/RadeonProRender.h, v3.1.7.1) --------------

pub const RPR_VERSION_MAJOR: Int = 3;
pub const RPR_VERSION_MINOR: Int = 1;
pub const RPR_VERSION_REVISION: Int = 7;
// RPR_API_VERSION is the header alias of RPR_VERSION_MAJOR_MINOR_REVISION;
// both stay literals (B-02/B-03: const aliases stay out of the confined
// resolution path).
pub const RPR_VERSION_MAJOR_MINOR_REVISION: Int = 0x00300107;
pub const RPR_API_VERSION: Int = 0x00300107;
pub const RPR_SUCCESS: Int = 0;

pub const RPR_CREATION_FLAGS_ENABLE_GPU0: Int = 1;
pub const RPR_CREATION_FLAGS_ENABLE_CPU: Int = 16;

pub const RPR_AOV_COLOR: Int = 0x0;
pub const RPR_CONTEXT_ITERATIONS: Int = 0x10B;
pub const RPR_CONTEXT_RENDER_STATUS: Int = 0x104;
pub const RPR_CONTEXT_DEVICE_COUNT: Int = 0x106;
pub const RPR_CONTEXT_DISPLAY_GAMMA: Int = 0x124;
pub const RPR_CONTEXT_CPU_NAME: Int = 0x12B;
pub const RPR_CONTEXT_GPU0_NAME: Int = 0x127;
pub const RPR_CONTEXT_LAST_ERROR_MESSAGE: Int = 0x137;
pub const RPR_CONTEXT_API_VERSION: Int = 0x141;

pub const RPR_COMPONENT_TYPE_FLOAT32: Int = 0x3;
pub const RPR_FRAMEBUFFER_FORMAT: Int = 0x1301;
pub const RPR_FRAMEBUFFER_DESC: Int = 0x1302;
pub const RPR_FRAMEBUFFER_DATA: Int = 0x1303;

pub const RPR_MATERIAL_NODE_DIFFUSE: Int = 0x1;
pub const RPR_MATERIAL_NODE_EMISSIVE: Int = 0x7;
pub const RPR_MATERIAL_NODE_UBERV2: Int = 0x2b;
pub const RPR_MATERIAL_INPUT_COLOR: Int = 0x0;
pub const RPR_MATERIAL_INPUT_UBER_DIFFUSE_COLOR: Int = 0x910;
pub const RPR_MATERIAL_INPUT_UBER_DIFFUSE_WEIGHT: Int = 0x927;
pub const RPR_MATERIAL_INPUT_UBER_REFLECTION_COLOR: Int = 0x913;
pub const RPR_MATERIAL_INPUT_UBER_REFLECTION_WEIGHT: Int = 0x928;
pub const RPR_MATERIAL_INPUT_UBER_REFLECTION_MODE: Int = 0x917;

pub const RPR_LIGHT_TYPE_POINT: Int = 0x1;
pub const RPR_LIGHT_TYPE_DIRECTIONAL: Int = 0x2;

// --- error model ------------------------------------------------------------

pub const RPR_KIND_API: Int = 1;          // rpr_status returned by the call
pub const RPR_KIND_LOAD_ABSENT: Int = 2;  // host library missing -> SKIP
pub const RPR_KIND_SYMBOL_MISSING: Int = 3;
pub const RPR_KIND_PLUGIN: Int = 4;       // backend plugin not loadable -> SKIP
pub const RPR_KIND_HANDLE: Int = 5;       // invalid object id
pub const RPR_KIND_ARGS: Int = 6;         // invalid argument at the bridge
pub const RPR_KIND_CAPACITY: Int = 7;     // framebuffer read-back size mismatch
pub const RPR_KIND_TABLE_FULL: Int = 8;   // bridge object table exhausted

// --- backend probe states (SKIP-class platform states, never failures) ------

pub const RPR_STATE_RENDERED: Int = 0;
pub const RPR_STATE_SKIP_LOAD: Int = 1;       // host library absent -> SKIP
pub const RPR_STATE_SKIP_PLUGIN: Int = 2;     // backend plugin absent -> SKIP
pub const RPR_STATE_SKIP_UNUSABLE: Int = 3;   // backend present but unusable on host -> SKIP
pub const RPR_STATE_SKIP_NO_OUTPUT: Int = 4;  // backend loaded, blank frame (host GPU) -> SKIP
pub const RPR_STATE_FAILED: Int = 5;          // contract violation -> FAIL

pub type RprError = {
  kind: Int;
  code: Int;
  message: Str;
}

/// Classify a bridge/API return code into a typed error (flat record; the
/// message carries the bridge diagnostics when one applies).
/// Complexity: O(1).
pub fn error_of(code: Int) -> RprError {
  if code == -100 {
    return RprError{ kind: RPR_KIND_LOAD_ABSENT; code: code;
      message: "host library not loaded: " + ffi.last_bridge_error() };
  }
  if code == -101 {
    return RprError{ kind: RPR_KIND_SYMBOL_MISSING; code: code;
      message: ffi.last_bridge_error() };
  }
  if code == -102 {
    return RprError{ kind: RPR_KIND_PLUGIN; code: code;
      message: "backend plugin not loadable: " + ffi.last_bridge_error() };
  }
  if code == -103 {
    return RprError{ kind: RPR_KIND_HANDLE; code: code;
      message: "invalid object handle" };
  }
  if code == -104 {
    return RprError{ kind: RPR_KIND_ARGS; code: code;
      message: "invalid argument" };
  }
  if code == -105 {
    return RprError{ kind: RPR_KIND_CAPACITY; code: code;
      message: "framebuffer read-back capacity mismatch" };
  }
  if code == -106 {
    return RprError{ kind: RPR_KIND_TABLE_FULL; code: code;
      message: "bridge object table full" };
  }
  return RprError{ kind: RPR_KIND_API; code: code;
    message: "rpr_status " + to_string(code) };
}

/// True when the error is a SKIP-class state (absent library/plugin/backend),
/// never a failure.
/// Complexity: O(1).
pub fn error_is_skip(e: RprError) -> Bool {
  return e.kind == RPR_KIND_LOAD_ABSENT || e.kind == RPR_KIND_PLUGIN;
}

fn ok_unit() -> Result[Unit, RprError] {
  return Ok(());
}

// --- handle types -----------------------------------------------------------

pub type RprContext = { id: Int; }
pub type RprScene = { id: Int; }
pub type RprCamera = { id: Int; }
pub type RprShape = { id: Int; }
pub type RprLight = { id: Int; }
pub type RprFrameBuffer = { id: Int; }
pub type RprMaterialSystem = { id: Int; }
pub type RprMaterialNode = { id: Int; }

// --- loader / plugin --------------------------------------------------------

/// Load the host API library; empty `module_path` means the default name
/// (`RadeonProRender64.dll` through the standard DLL search order).
/// Complexity: O(1).
pub fn load(module_path: Str) -> Result[Unit, RprError]
  requires: true
{
  var p = ffi.cpath(module_path);
  let rc = ffi.load(&mut p);
  if rc != 0 { return Err(error_of(rc as Int)); }
  return ok_unit();
}

/// rprRegisterPlugin: returns the plugin id (>= 0) or a typed error
/// (RPR_KIND_PLUGIN when the plugin DLL cannot be loaded -> SKIP).
/// Complexity: O(1).
pub fn register_plugin(plugin_path: Str) -> Result[Int, RprError]
  requires: plugin_path.len() > 0
{
  var p = ffi.cpath(plugin_path);
  let id = ffi.register_plugin(&mut p);
  if id < 0 { return Err(error_of(id as Int)); }
  return Ok(id as Int);
}

// --- context ----------------------------------------------------------------

/// rprCreateContext with a single registered plugin (the tutorial flow).
/// Complexity: O(1).
pub fn context_create(api_version: Int, plugin_id: Int, flags: Int,
    cache_dir: Str) -> Result[RprContext, RprError]
  requires: api_version > 0
  requires: plugin_id >= 0
{
  var cache = ffi.cpath(cache_dir);
  let id = ffi.context_create(api_version, plugin_id, flags, &mut cache);
  if id < 0 { return Err(error_of(id)); }
  return Ok(RprContext{ id: id });
}

/// rprContextSetActivePlugin. Complexity: O(1).
pub fn context_set_active_plugin(ctx: RprContext, plugin_id: Int) -> Result[Unit, RprError]
  requires: plugin_id >= 0
{
  let rc = ffi.context_set_active_plugin(ctx.id, plugin_id);
  if rc != 0 { return Err(error_of(rc as Int)); }
  return ok_unit();
}

/// rprContextSetScene. Complexity: O(1).
pub fn context_set_scene(ctx: RprContext, scene: RprScene) -> Result[Unit, RprError]
  requires: true
{
  let rc = ffi.context_set_scene(ctx.id, scene.id);
  if rc != 0 { return Err(error_of(rc as Int)); }
  return ok_unit();
}

/// rprContextSetParameterByKey1u (raw key). Complexity: O(1).
pub fn context_set_param_u(ctx: RprContext, key: Int, value: Int) -> Result[Unit, RprError]
  requires: true
{
  let rc = ffi.context_set_param_u(ctx.id, key, value);
  if rc != 0 { return Err(error_of(rc as Int)); }
  return ok_unit();
}

/// rprContextSetParameterByKey1f (raw key). Complexity: O(1).
pub fn context_set_param_f(ctx: RprContext, key: Int, value: Float32) -> Result[Unit, RprError]
  requires: true
{
  let rc = ffi.context_set_param_f(ctx.id, key, value);
  if rc != 0 { return Err(error_of(rc as Int)); }
  return ok_unit();
}

/// rprContextSetParameterByKey1u(RPR_CONTEXT_ITERATIONS, n).
/// Complexity: O(1).
pub fn context_set_iterations(ctx: RprContext, iterations: Int) -> Result[Unit, RprError]
  requires: iterations > 0
{
  let rc = ffi.context_set_param_u(ctx.id, RPR_CONTEXT_ITERATIONS, iterations);
  if rc != 0 { return Err(error_of(rc as Int)); }
  return ok_unit();
}

/// rprContextGetInfo string read (raw key) into an owned `Str`.
/// Complexity: O(len).
pub fn context_info_str(ctx: RprContext, key: Int) -> Result[Str, RprError]
  requires: true
{
  let rc = ffi.context_info_str(ctx.id, key);
  if rc != 0 { return Err(error_of(rc as Int)); }
  return Ok(ffi.last_bridge_error());
}

/// rprContextGetInfo unsigned-int read (raw key) as a scalar.
/// Complexity: O(1).
pub fn context_info_u(ctx: RprContext, key: Int) -> Result[Int, RprError]
  requires: true
{
  let v = ffi.context_info_u(ctx.id, key);
  if v < 0 { return Err(error_of(v)); }
  return Ok(v);
}

/// rprContextGetInfo(RPR_CONTEXT_LAST_ERROR_MESSAGE) convenience.
/// Complexity: O(len).
pub fn context_last_error(ctx: RprContext) -> Str
  requires: true
{
  let rc = ffi.context_info_str(ctx.id, RPR_CONTEXT_LAST_ERROR_MESSAGE);
  if rc != 0 { return ""; }
  return ffi.last_bridge_error();
}

// --- scene ------------------------------------------------------------------

/// rprContextCreateScene. Complexity: O(1).
pub fn scene_create(ctx: RprContext) -> Result[RprScene, RprError]
  requires: true
{
  let id = ffi.scene_create(ctx.id);
  if id < 0 { return Err(error_of(id)); }
  return Ok(RprScene{ id: id });
}

/// rprSceneAttachShape. Complexity: O(1).
pub fn scene_attach_shape(scene: RprScene, shape: RprShape) -> Result[Unit, RprError]
  requires: true
{
  let rc = ffi.scene_attach_shape(scene.id, shape.id);
  if rc != 0 { return Err(error_of(rc as Int)); }
  return ok_unit();
}

/// rprSceneAttachLight. Complexity: O(1).
pub fn scene_attach_light(scene: RprScene, light: RprLight) -> Result[Unit, RprError]
  requires: true
{
  let rc = ffi.scene_attach_light(scene.id, light.id);
  if rc != 0 { return Err(error_of(rc as Int)); }
  return ok_unit();
}

/// rprSceneSetCamera. Complexity: O(1).
pub fn scene_set_camera(scene: RprScene, camera: RprCamera) -> Result[Unit, RprError]
  requires: true
{
  let rc = ffi.scene_set_camera(scene.id, camera.id);
  if rc != 0 { return Err(error_of(rc as Int)); }
  return ok_unit();
}

// --- camera -----------------------------------------------------------------

/// rprContextCreateCamera. Complexity: O(1).
pub fn camera_create(ctx: RprContext) -> Result[RprCamera, RprError]
  requires: true
{
  let id = ffi.camera_create(ctx.id);
  if id < 0 { return Err(error_of(id)); }
  return Ok(RprCamera{ id: id });
}

/// rprCameraLookAt(pos, at, up). Complexity: O(1).
pub fn camera_look_at(camera: RprCamera, px: Float32, py: Float32, pz: Float32,
    ax: Float32, ay: Float32, az: Float32, ux: Float32, uy: Float32,
    uz: Float32) -> Result[Unit, RprError]
  requires: true
{
  let rc = ffi.camera_look_at(camera.id, px, py, pz, ax, ay, az, ux, uy, uz);
  if rc != 0 { return Err(error_of(rc as Int)); }
  return ok_unit();
}

/// rprCameraSetFocalLength (mm). Complexity: O(1).
pub fn camera_set_focal_length(camera: RprCamera, mm: Float32) -> Result[Unit, RprError]
  requires: mm > 0.0
{
  let rc = ffi.camera_set_focal_length(camera.id, mm);
  if rc != 0 { return Err(error_of(rc as Int)); }
  return ok_unit();
}

/// rprCameraSetSensorSize (mm x mm). Complexity: O(1).
pub fn camera_set_sensor_size(camera: RprCamera, width: Float32,
    height: Float32) -> Result[Unit, RprError]
  requires: width > 0.0
  requires: height > 0.0
{
  let rc = ffi.camera_set_sensor_size(camera.id, width, height);
  if rc != 0 { return Err(error_of(rc as Int)); }
  return ok_unit();
}

// --- lights -----------------------------------------------------------------

/// rprContextCreatePointLight. Complexity: O(1).
pub fn light_create_point(ctx: RprContext) -> Result[RprLight, RprError]
  requires: true
{
  let id = ffi.light_create_point(ctx.id);
  if id < 0 { return Err(error_of(id)); }
  return Ok(RprLight{ id: id });
}

/// rprContextCreateDirectionalLight. Complexity: O(1).
pub fn light_create_directional(ctx: RprContext) -> Result[RprLight, RprError]
  requires: true
{
  let id = ffi.light_create_directional(ctx.id);
  if id < 0 { return Err(error_of(id)); }
  return Ok(RprLight{ id: id });
}

/// rprLightSetTransform (row-major 4x4, transposed by the bridge).
/// Complexity: O(1).
pub fn light_set_transform(light: RprLight, m: &mut Vec[Float32]) -> Result[Unit, RprError]
  requires: m.len() == 16
{
  let rc = ffi.light_set_transform(light.id, m);
  if rc != 0 { return Err(error_of(rc as Int)); }
  return ok_unit();
}

/// rprPointLightSetRadiantPower3f / rprDirectionalLightSetRadiantPower3f.
/// Complexity: O(1).
pub fn light_set_radiance(light: RprLight, r: Float32, g: Float32,
    b: Float32) -> Result[Unit, RprError]
  requires: true
{
  let rc = ffi.light_set_power(light.id, r, g, b);
  if rc != 0 { return Err(error_of(rc as Int)); }
  return ok_unit();
}

// --- materials --------------------------------------------------------------

/// rprContextCreateMaterialSystem (ms_type = 0 in every upstream tutorial).
/// Complexity: O(1).
pub fn material_system_create(ctx: RprContext, ms_type: Int) -> Result[RprMaterialSystem, RprError]
  requires: true
{
  let id = ffi.material_system_create(ctx.id, ms_type);
  if id < 0 { return Err(error_of(id)); }
  return Ok(RprMaterialSystem{ id: id });
}

/// rprMaterialSystemCreateNode (node_type = RPR_MATERIAL_NODE_*).
/// Complexity: O(1).
pub fn material_create_node(ms: RprMaterialSystem, node_type: Int) -> Result[RprMaterialNode, RprError]
  requires: true
{
  let id = ffi.material_create_node(ms.id, node_type);
  if id < 0 { return Err(error_of(id)); }
  return Ok(RprMaterialNode{ id: id });
}

/// rprMaterialNodeSetInputFByKey. Complexity: O(1).
pub fn material_set_input_f(node: RprMaterialNode, input: Int, x: Float32,
    y: Float32, z: Float32, w: Float32) -> Result[Unit, RprError]
  requires: true
{
  let rc = ffi.material_set_input_f(node.id, input, x, y, z, w);
  if rc != 0 { return Err(error_of(rc as Int)); }
  return ok_unit();
}

/// rprMaterialNodeSetInputUByKey. Complexity: O(1).
pub fn material_set_input_u(node: RprMaterialNode, input: Int,
    value: Int) -> Result[Unit, RprError]
  requires: true
{
  let rc = ffi.material_set_input_u(node.id, input, value);
  if rc != 0 { return Err(error_of(rc as Int)); }
  return ok_unit();
}

/// rprShapeSetMaterial. Complexity: O(1).
pub fn shape_set_material(shape: RprShape, node: RprMaterialNode) -> Result[Unit, RprError]
  requires: true
{
  let rc = ffi.shape_set_material(shape.id, node.id);
  if rc != 0 { return Err(error_of(rc as Int)); }
  return ok_unit();
}

// --- mesh / transforms ------------------------------------------------------

/// rprShapeSetTransform (row-major 4x4, transposed by the bridge).
/// Complexity: O(1).
pub fn shape_set_transform(shape: RprShape, m: &mut Vec[Float32]) -> Result[Unit, RprError]
  requires: m.len() == 16
{
  let rc = ffi.shape_set_transform(shape.id, m);
  if rc != 0 { return Err(error_of(rc as Int)); }
  return ok_unit();
}

/// rprContextCreateMesh for triangle meshes: `positions`/`normals` are flat
/// 3-float-per-vertex streams, `indices` flat triples.
/// Complexity: O(vertices + indices).
pub fn mesh_create(ctx: RprContext, positions: &mut Vec[Float32],
    normals: &mut Vec[Float32], indices: &mut Vec[Int32]) -> Result[RprShape, RprError]
  requires: positions.len() > 0
  requires: positions.len() % 3 == 0
  requires: indices.len() >= 3
  requires: indices.len() % 3 == 0
{
  let id = ffi.mesh_create(ctx.id, positions, normals, indices);
  if id < 0 { return Err(error_of(id)); }
  return Ok(RprShape{ id: id });
}

// --- framebuffer / render ---------------------------------------------------

/// rprContextCreateFrameBuffer (RGBA float by default in the suite).
/// Complexity: O(1).
pub fn framebuffer_create(ctx: RprContext, width: Int, height: Int,
    num_components: Int, component_type: Int) -> Result[RprFrameBuffer, RprError]
  requires: width > 0
  requires: height > 0
  requires: num_components > 0
{
  let id = ffi.framebuffer_create(ctx.id, width, height, num_components, component_type);
  if id < 0 { return Err(error_of(id)); }
  return Ok(RprFrameBuffer{ id: id });
}

/// rprFrameBufferClear. Complexity: O(1).
pub fn framebuffer_clear(fb: RprFrameBuffer) -> Result[Unit, RprError]
  requires: true
{
  let rc = ffi.framebuffer_clear(fb.id);
  if rc != 0 { return Err(error_of(rc as Int)); }
  return ok_unit();
}

/// rprContextSetAOV(context, RPR_AOV_COLOR, fb). Complexity: O(1).
pub fn context_set_aov_color(ctx: RprContext, fb: RprFrameBuffer) -> Result[Unit, RprError]
  requires: true
{
  let rc = ffi.context_set_aov_color(ctx.id, fb.id);
  if rc != 0 { return Err(error_of(rc as Int)); }
  return ok_unit();
}

/// rprContextRender (synchronous). Complexity: O(iterations x pixels).
pub fn context_render(ctx: RprContext) -> Result[Unit, RprError]
  requires: true
{
  let rc = ffi.context_render(ctx.id);
  if rc != 0 { return Err(error_of(rc as Int)); }
  return ok_unit();
}

/// rprContextResolveFrameBuffer(src -> dst, display gamma applied).
/// Complexity: O(pixels).
pub fn context_resolve(ctx: RprContext, src: RprFrameBuffer,
    dst: RprFrameBuffer) -> Result[Unit, RprError]
  requires: true
{
  let rc = ffi.context_resolve(ctx.id, src.id, dst.id);
  if rc != 0 { return Err(error_of(rc as Int)); }
  return ok_unit();
}

/// rprFrameBufferGetInfo(RPR_FRAMEBUFFER_DESC) as packed (width << 32) | height.
/// Complexity: O(1).
pub fn framebuffer_desc(fb: RprFrameBuffer) -> Result[Int, RprError]
  requires: true
{
  let v = ffi.framebuffer_desc(fb.id);
  if v < 0 { return Err(error_of(v)); }
  return Ok(v);
}

/// rprFrameBufferGetInfo(RPR_FRAMEBUFFER_DATA) into an XIOM-owned float
/// buffer (the bridge copies; no foreign pointer is read -- B-20).
/// Returns the float count written. Complexity: O(len).
pub fn framebuffer_read(fb: RprFrameBuffer, out: &mut Vec[Float32]) -> Result[Int, RprError]
  requires: out.len() > 0
{
  let n = ffi.framebuffer_read(fb.id, out);
  if n < 0 { return Err(error_of(n)); }
  return Ok(n);
}

/// rprFrameBufferGetInfo(RPR_FRAMEBUFFER_DATA) into an XIOM-owned byte
/// buffer (byte-indexed proof path).  Returns the byte count written.
/// Complexity: O(len).
pub fn framebuffer_read_bytes(fb: RprFrameBuffer, out: &mut Vec[UInt8]) -> Result[Int, RprError]
  requires: out.len() > 0
{
  let n = ffi.framebuffer_read_bytes(fb.id, out);
  if n < 0 { return Err(error_of(n)); }
  return Ok(n);
}

// --- destruction ------------------------------------------------------------

/// rprObjectDelete for any object. Complexity: O(1).
pub fn context_destroy(ctx: RprContext) -> Result[Unit, RprError]
  requires: true
{
  let rc = ffi.object_delete(ctx.id);
  if rc != 0 { return Err(error_of(rc as Int)); }
  return ok_unit();
}

/// rprObjectDelete for a scene. Complexity: O(1).
pub fn scene_destroy(scene: RprScene) -> Result[Unit, RprError]
  requires: true
{
  let rc = ffi.object_delete(scene.id);
  if rc != 0 { return Err(error_of(rc as Int)); }
  return ok_unit();
}

/// rprObjectDelete for a camera. Complexity: O(1).
pub fn camera_destroy(camera: RprCamera) -> Result[Unit, RprError]
  requires: true
{
  let rc = ffi.object_delete(camera.id);
  if rc != 0 { return Err(error_of(rc as Int)); }
  return ok_unit();
}

/// rprObjectDelete for a shape. Complexity: O(1).
pub fn shape_destroy(shape: RprShape) -> Result[Unit, RprError]
  requires: true
{
  let rc = ffi.object_delete(shape.id);
  if rc != 0 { return Err(error_of(rc as Int)); }
  return ok_unit();
}

/// rprObjectDelete for a light. Complexity: O(1).
pub fn light_destroy(light: RprLight) -> Result[Unit, RprError]
  requires: true
{
  let rc = ffi.object_delete(light.id);
  if rc != 0 { return Err(error_of(rc as Int)); }
  return ok_unit();
}

/// rprObjectDelete for a framebuffer. Complexity: O(1).
pub fn framebuffer_destroy(fb: RprFrameBuffer) -> Result[Unit, RprError]
  requires: true
{
  let rc = ffi.object_delete(fb.id);
  if rc != 0 { return Err(error_of(rc as Int)); }
  return ok_unit();
}

/// rprObjectDelete for a material system. Complexity: O(1).
pub fn material_system_destroy(ms: RprMaterialSystem) -> Result[Unit, RprError]
  requires: true
{
  let rc = ffi.object_delete(ms.id);
  if rc != 0 { return Err(error_of(rc as Int)); }
  return ok_unit();
}

/// rprObjectDelete for a material node. Complexity: O(1).
pub fn material_node_destroy(node: RprMaterialNode) -> Result[Unit, RprError]
  requires: true
{
  let rc = ffi.object_delete(node.id);
  if rc != 0 { return Err(error_of(rc as Int)); }
  return ok_unit();
}

// --- pure helpers -----------------------------------------------------------

/// Row-major 4x4 translation matrix (16 floats) for the transform setters.
/// Complexity: O(1).
pub fn translation_matrix(x: Float32, y: Float32, z: Float32) -> Vec[Float32]
  requires: true
{
  var m: Vec[Float32] = Vec[Float32].new();
  m.push(1.0); m.push(0.0); m.push(0.0); m.push(x);
  m.push(0.0); m.push(1.0); m.push(0.0); m.push(y);
  m.push(0.0); m.push(0.0); m.push(1.0); m.push(z);
  m.push(0.0); m.push(0.0); m.push(0.0); m.push(1.0);
  return m;
}

/// Row-major identity 4x4 matrix (16 floats). Complexity: O(1).
pub fn identity_matrix() -> Vec[Float32]
  requires: true
{
  return translation_matrix(0.0, 0.0, 0.0);
}
