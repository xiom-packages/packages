// xiom.rpr.ffi -- confined FFI core for xiom.rpr (G5: the ONLY module in the
// package with `extern "C"` declarations; every foreign call is wrapped here).
//
// Bridge: src/rpr_bridge.c (our code, MIT OR Apache-2.0) -- a runtime loader
// over the Radeon ProRender host API (`RadeonProRender64.dll`), resolved with
// GetProcAddress; nothing from the SDK binaries is vendored (SPEC.md sec. 3).
//
// Toolchain v0.64.4 discipline:
//   * object handles cross as plain `Int` ids into a bridge-owned registry
//     (B-25: `Int as *UInt8` is not value-preserving -- no pointer casts);
//   * no out-param slots for driver-heavy calls: handles and sizes are packed
//     scalar returns (B-11); the only foreign writes land in XIOM-owned
//     buffers (mesh input, framebuffer read-back), indexed on the XIOM side;
//   * `null` never crosses from XIOM (B-23): the bridge owns every nullable
//     argument (empty path bytes mean "default name").
//
// Code table (keep in sync with src/rpr_bridge.c):
//   >= 0 success value; -1..-29 rpr_status; -100 loader missing;
//   -101 entry point missing; -102 plugin registration failed;
//   -103 invalid handle; -104 invalid args; -105 capacity mismatch;
//   -106 object table full.

module xiom.rpr.ffi

/// NUL-terminated byte copy of `s` for C path arguments.
/// Complexity: O(len).
pub fn cpath(s: Str) -> Vec[UInt8]
  requires: true
{
  var v: Vec[UInt8] = Vec[UInt8].new();
  let n = s.len();
  var i: Int = 0;
  while i < n {
    v.push(s.byte_at(i));
    i = i + 1;
  }
  v.push(0 as UInt8);
  return v;
}

/// Zero-filled byte vector (`n` elements) owned by XIOM.
/// Complexity: O(n).
pub fn zero_bytes(n: Int) -> Vec[UInt8]
  requires: n >= 0
{
  var v: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < n {
    v.push(0 as UInt8);
    i = i + 1;
  }
  return v;
}

/// Zero-filled float vector (`n` elements) owned by XIOM.
/// Complexity: O(n).
pub fn zero_floats(n: Int) -> Vec[Float32]
  requires: n >= 0
{
  var v: Vec[Float32] = Vec[Float32].new();
  var i: Int = 0;
  while i < n {
    v.push(0.0);
    i = i + 1;
  }
  return v;
}

/// Zero-filled int32 vector (`n` elements) owned by XIOM.
/// Complexity: O(n).
pub fn zero_i32(n: Int) -> Vec[Int32]
  requires: n >= 0
{
  var v: Vec[Int32] = Vec[Int32].new();
  var i: Int = 0;
  while i < n {
    v.push(0 as Int32);
    i = i + 1;
  }
  return v;
}

extern "C" {
  fn rprx_load(path: *UInt8) -> Int32;
  fn rprx_last_bridge_error() -> *UInt8;

  fn rprx_register_plugin(path: *UInt8) -> Int32;
  fn rprx_context_create(api_version: Int, plugin_id: Int, flags: Int,
    cache_path: *UInt8) -> Int;
  fn rprx_context_set_active_plugin(ctx: Int, plugin_id: Int) -> Int32;
  fn rprx_context_set_scene(ctx: Int, scene: Int) -> Int32;
  fn rprx_context_set_param_u(ctx: Int, key: Int, value: Int) -> Int32;
  fn rprx_context_set_param_f(ctx: Int, key: Int, value: Float32) -> Int32;
  fn rprx_context_set_aov_color(ctx: Int, fb: Int) -> Int32;
  fn rprx_context_render(ctx: Int) -> Int32;
  fn rprx_context_resolve(ctx: Int, src: Int, dst: Int) -> Int32;
  fn rprx_context_info_str(ctx: Int, key: Int) -> Int32;
  fn rprx_context_info_u(ctx: Int, key: Int) -> Int;

  fn rprx_scene_create(ctx: Int) -> Int;
  fn rprx_scene_attach_shape(scene: Int, shape: Int) -> Int32;
  fn rprx_scene_attach_light(scene: Int, light: Int) -> Int32;
  fn rprx_scene_set_camera(scene: Int, camera: Int) -> Int32;

  fn rprx_camera_create(ctx: Int) -> Int;
  fn rprx_camera_look_at(cam: Int, px: Float32, py: Float32, pz: Float32,
    ax: Float32, ay: Float32, az: Float32, ux: Float32, uy: Float32,
    uz: Float32) -> Int32;
  fn rprx_camera_set_focal_length(cam: Int, mm: Float32) -> Int32;
  fn rprx_camera_set_sensor_size(cam: Int, w: Float32, h: Float32) -> Int32;

  fn rprx_light_create_point(ctx: Int) -> Int;
  fn rprx_light_create_directional(ctx: Int) -> Int;
  fn rprx_light_set_transform(light: Int, m: *Float32, count: Int) -> Int32;
  fn rprx_light_set_power(light: Int, r: Float32, g: Float32, b: Float32) -> Int32;

  fn rprx_material_system_create(ctx: Int, ms_type: Int) -> Int;
  fn rprx_material_create_node(ms: Int, node_type: Int) -> Int;
  fn rprx_material_set_input_f(node: Int, input: Int, x: Float32, y: Float32,
    z: Float32, w: Float32) -> Int32;
  fn rprx_material_set_input_u(node: Int, input: Int, value: Int) -> Int32;
  fn rprx_shape_set_material(shape: Int, node: Int) -> Int32;

  fn rprx_shape_set_transform(shape: Int, m: *Float32, count: Int) -> Int32;
  fn rprx_mesh_create(ctx: Int, positions: *Float32, pos_count: Int,
    normals: *Float32, norm_count: Int, indices: *Int32,
    index_count: Int) -> Int;

  fn rprx_framebuffer_create(ctx: Int, width: Int, height: Int,
    num_components: Int, comp_type: Int) -> Int;
  fn rprx_framebuffer_clear(fb: Int) -> Int32;
  fn rprx_framebuffer_desc(fb: Int) -> Int;
  fn rprx_framebuffer_read(fb: Int, out: *Float32, out_count: Int) -> Int;
  fn rprx_framebuffer_read_bytes(fb: Int, out: *UInt8, out_count: Int) -> Int;

  fn rprx_object_delete(handle: Int) -> Int32;
}

// ---------------------------------------------------------------------------
// confined wrappers (small unsafe blocks; scalars and owned buffers only)
// ---------------------------------------------------------------------------

/// Load the host API library (`path` empty -> default name). Complexity: O(1).
pub fn load(path: &mut Vec[UInt8]) -> Int32
  requires: path.len() >= 1
{
  unsafe { return rprx_load(path.as_mut_ptr()); }
}

/// Last bridge message (loader diagnostics) as an owned `Str`.
/// Complexity: O(len).
pub fn last_bridge_error() -> Str
  requires: true
{
  unsafe {
    let p = rprx_last_bridge_error();
    if (p as Int) != 0 {
      return Str::from_c_str(p);
    }
    return "";
  }
}

/// rprRegisterPlugin; returns the plugin id (>= 0) or a negative code.
/// Complexity: O(1).
pub fn register_plugin(path: &mut Vec[UInt8]) -> Int32
  requires: path.len() >= 1
{
  unsafe { return rprx_register_plugin(path.as_mut_ptr()); }
}

/// rprCreateContext; returns an object id or a negative code. Complexity: O(1).
pub fn context_create(api_version: Int, plugin_id: Int, flags: Int,
    cache_path: &mut Vec[UInt8]) -> Int
  requires: cache_path.len() >= 1
{
  unsafe {
    return rprx_context_create(api_version, plugin_id, flags, cache_path.as_mut_ptr());
  }
}

pub fn context_set_active_plugin(ctx: Int, plugin_id: Int) -> Int32
  requires: true
{
  unsafe { return rprx_context_set_active_plugin(ctx, plugin_id); }
}

pub fn context_set_scene(ctx: Int, scene: Int) -> Int32
  requires: true
{
  unsafe { return rprx_context_set_scene(ctx, scene); }
}

pub fn context_set_param_u(ctx: Int, key: Int, value: Int) -> Int32
  requires: true
{
  unsafe { return rprx_context_set_param_u(ctx, key, value); }
}

pub fn context_set_param_f(ctx: Int, key: Int, value: Float32) -> Int32
  requires: true
{
  unsafe { return rprx_context_set_param_f(ctx, key, value); }
}

pub fn context_set_aov_color(ctx: Int, fb: Int) -> Int32
  requires: true
{
  unsafe { return rprx_context_set_aov_color(ctx, fb); }
}

pub fn context_render(ctx: Int) -> Int32
  requires: true
{
  unsafe { return rprx_context_render(ctx); }
}

pub fn context_resolve(ctx: Int, src: Int, dst: Int) -> Int32
  requires: true
{
  unsafe { return rprx_context_resolve(ctx, src, dst); }
}

/// rprContextGetInfo string read into the bridge buffer; returns the status.
/// Complexity: O(1).
pub fn context_info_str(ctx: Int, key: Int) -> Int32
  requires: true
{
  unsafe { return rprx_context_info_str(ctx, key); }
}

/// rprContextGetInfo uint read as a scalar; negative is an error code.
/// Complexity: O(1).
pub fn context_info_u(ctx: Int, key: Int) -> Int
  requires: true
{
  unsafe { return rprx_context_info_u(ctx, key); }
}

pub fn scene_create(ctx: Int) -> Int
  requires: true
{
  unsafe { return rprx_scene_create(ctx); }
}

pub fn scene_attach_shape(scene: Int, shape: Int) -> Int32
  requires: true
{
  unsafe { return rprx_scene_attach_shape(scene, shape); }
}

pub fn scene_attach_light(scene: Int, light: Int) -> Int32
  requires: true
{
  unsafe { return rprx_scene_attach_light(scene, light); }
}

pub fn scene_set_camera(scene: Int, camera: Int) -> Int32
  requires: true
{
  unsafe { return rprx_scene_set_camera(scene, camera); }
}

pub fn camera_create(ctx: Int) -> Int
  requires: true
{
  unsafe { return rprx_camera_create(ctx); }
}

pub fn camera_look_at(cam: Int, px: Float32, py: Float32, pz: Float32,
    ax: Float32, ay: Float32, az: Float32, ux: Float32, uy: Float32,
    uz: Float32) -> Int32
  requires: true
{
  unsafe { return rprx_camera_look_at(cam, px, py, pz, ax, ay, az, ux, uy, uz); }
}

pub fn camera_set_focal_length(cam: Int, mm: Float32) -> Int32
  requires: true
{
  unsafe { return rprx_camera_set_focal_length(cam, mm); }
}

pub fn camera_set_sensor_size(cam: Int, w: Float32, h: Float32) -> Int32
  requires: true
{
  unsafe { return rprx_camera_set_sensor_size(cam, w, h); }
}

pub fn light_create_point(ctx: Int) -> Int
  requires: true
{
  unsafe { return rprx_light_create_point(ctx); }
}

pub fn light_create_directional(ctx: Int) -> Int
  requires: true
{
  unsafe { return rprx_light_create_directional(ctx); }
}

/// 16-float row-major transform (bridge transposes for RPR). Complexity: O(1).
pub fn light_set_transform(light: Int, m: &mut Vec[Float32]) -> Int32
  requires: m.len() == 16
{
  unsafe { return rprx_light_set_transform(light, m.as_mut_ptr(), 16); }
}

pub fn light_set_power(light: Int, r: Float32, g: Float32, b: Float32) -> Int32
  requires: true
{
  unsafe { return rprx_light_set_power(light, r, g, b); }
}

pub fn material_system_create(ctx: Int, ms_type: Int) -> Int
  requires: true
{
  unsafe { return rprx_material_system_create(ctx, ms_type); }
}

pub fn material_create_node(ms: Int, node_type: Int) -> Int
  requires: true
{
  unsafe { return rprx_material_create_node(ms, node_type); }
}

pub fn material_set_input_f(node: Int, input: Int, x: Float32, y: Float32,
    z: Float32, w: Float32) -> Int32
  requires: true
{
  unsafe { return rprx_material_set_input_f(node, input, x, y, z, w); }
}

pub fn material_set_input_u(node: Int, input: Int, value: Int) -> Int32
  requires: true
{
  unsafe { return rprx_material_set_input_u(node, input, value); }
}

pub fn shape_set_material(shape: Int, node: Int) -> Int32
  requires: true
{
  unsafe { return rprx_shape_set_material(shape, node); }
}

/// 16-float row-major transform (bridge transposes for RPR). Complexity: O(1).
pub fn shape_set_transform(shape: Int, m: &mut Vec[Float32]) -> Int32
  requires: m.len() == 16
{
  unsafe { return rprx_shape_set_transform(shape, m.as_mut_ptr(), 16); }
}

/// Triangle mesh from owned flat streams; returns a shape id or negative.
/// Complexity: O(vertices + indices).
pub fn mesh_create(ctx: Int, positions: &mut Vec[Float32],
    normals: &mut Vec[Float32], indices: &mut Vec[Int32]) -> Int
  requires: positions.len() % 3 == 0
{
  unsafe {
    return rprx_mesh_create(ctx, positions.as_mut_ptr(), positions.len(),
      normals.as_mut_ptr(), normals.len(), indices.as_mut_ptr(), indices.len());
  }
}

pub fn framebuffer_create(ctx: Int, width: Int, height: Int, num_components: Int,
    comp_type: Int) -> Int
  requires: true
{
  unsafe {
    return rprx_framebuffer_create(ctx, width, height, num_components, comp_type);
  }
}

pub fn framebuffer_clear(fb: Int) -> Int32
  requires: true
{
  unsafe { return rprx_framebuffer_clear(fb); }
}

/// Packed (width << 32) | height, or a negative code. Complexity: O(1).
pub fn framebuffer_desc(fb: Int) -> Int
  requires: true
{
  unsafe { return rprx_framebuffer_desc(fb); }
}

/// Copy framebuffer data into an XIOM-owned float buffer; returns the float
/// count written (or negative). Complexity: O(out len).
pub fn framebuffer_read(fb: Int, out: &mut Vec[Float32]) -> Int
  requires: out.len() >= 1
{
  unsafe { return rprx_framebuffer_read(fb, out.as_mut_ptr(), out.len()); }
}

/// Copy framebuffer data into an XIOM-owned byte buffer (byte-indexed path);
/// returns the byte count written (or negative). Complexity: O(out len).
pub fn framebuffer_read_bytes(fb: Int, out: &mut Vec[UInt8]) -> Int
  requires: out.len() >= 1
{
  unsafe { return rprx_framebuffer_read_bytes(fb, out.as_mut_ptr(), out.len()); }
}

pub fn object_delete(handle: Int) -> Int32
  requires: true
{
  unsafe { return rprx_object_delete(handle); }
}
