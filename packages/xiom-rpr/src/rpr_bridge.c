// xiom.rpr -- Radeon ProRender core-API bridge (runtime loader, flat ABI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN (SPEC.md sec. 3): "vendored headers + runtime DLL loader".  Nothing
// from the SDK binaries is committed; `RadeonProRender64.dll` (the host API)
// is loaded at runtime with LoadLibraryA and every entry point is resolved
// with GetProcAddress.  The backend plugins (Northstar64.dll / Tahoe64.dll /
// HybridPro.dll) are registered by path with rprRegisterPlugin.
//
// Handle discipline (toolchain v0.64.4): RPR objects are opaque pointers and
// NEVER cross the XIOM boundary (B-25: `Int as *UInt8` is not
// value-preserving).  The bridge keeps a small static object registry; XIOM
// sees packed integer ids (slot+1).  Scalar/packed returns avoid out-param
// slots (B-11); the only foreign writes land in XIOM-owned buffers (mesh
// input, framebuffer read-back), read byte/element-indexed on the XIOM side
// (B-24).  `null` never crosses from XIOM (B-23): the bridge owns every
// nullable argument.
//
// The declarations below mirror the pinned public header
// `vendor/rpr/RadeonProRender.h` (v3.1.7.1, Apache-2.0); the coverage oracle
// (tools/surface_rpr.py) checks every bridged symbol against that header.
//
// Return convention (int64/int32 unless the function returns a handle):
//     >= 0     success (value)
//     -1..-29  the rpr_status returned by the underlying call (negated by the
//              API itself; RPR errors are negative)
//     -100     host module not loaded (rprx_load not called / failed)
//     -101     a required entry point is missing (name in g_err)
//     -102     rprRegisterPlugin failed (-1: plugin absent/not loadable)
//     -103     invalid object handle
//     -104     invalid arguments (null buffer, size/count mismatch, OOM)
//     -105     framebuffer read-back capacity mismatch (out_count != fb size)
//     -106     object table full

#include <windows.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

// --- rpr core typedefs (mirror of vendor/rpr/RadeonProRender.h) -------------

typedef char rpr_char;
typedef int rpr_int;
typedef unsigned int rpr_uint;
typedef float rpr_float;
typedef int rpr_bool;
typedef int rpr_status;
typedef void* rpr_context;
typedef void* rpr_camera;
typedef void* rpr_shape;
typedef void* rpr_light;
typedef void* rpr_scene;
typedef void* rpr_framebuffer;
typedef void* rpr_material_system;
typedef void* rpr_material_node;

typedef struct { rpr_uint num_components; rpr_uint type; } rpr_framebuffer_format;
typedef struct { rpr_uint fb_width; rpr_uint fb_height; } rpr_framebuffer_desc;

#define RPR_API_VERSION 0x00300107

// --- bridge state -----------------------------------------------------------

#define RPRX_MAX_OBJECTS 96
#define RPRX_ERR_CAP 2048

// Object kinds (only lights need dispatch; the rest is bookkeeping).
#define RPRX_K_CONTEXT 1
#define RPRX_K_SCENE 2
#define RPRX_K_CAMERA 3
#define RPRX_K_SHAPE 4
#define RPRX_K_LIGHT_POINT 5
#define RPRX_K_LIGHT_DIRECTIONAL 6
#define RPRX_K_FB 7
#define RPRX_K_MATSYS 8
#define RPRX_K_MATNODE 9

static void* g_objects[RPRX_MAX_OBJECTS];
static unsigned char g_kind[RPRX_MAX_OBJECTS];
static char g_err[RPRX_ERR_CAP];

static void set_err(const char* msg) {
  if (!msg) { g_err[0] = 0; return; }
  strncpy(g_err, msg, RPRX_ERR_CAP - 1);
  g_err[RPRX_ERR_CAP - 1] = 0;
}

static int64_t put_obj(unsigned char kind, void* p) {
  if (!p) return -104;
  for (int i = 0; i < RPRX_MAX_OBJECTS; i++) {
    if (g_objects[i] == 0) { g_objects[i] = p; g_kind[i] = kind; return (int64_t)(i + 1); }
  }
  set_err("object table full");
  return -106;
}

static void* get_obj(int64_t handle) {
  if (handle < 1 || handle > RPRX_MAX_OBJECTS) return 0;
  return g_objects[handle - 1];
}

static unsigned char get_kind(int64_t handle) {
  if (handle < 1 || handle > RPRX_MAX_OBJECTS) return 0;
  return g_kind[handle - 1];
}

static void clear_obj(int64_t handle) {
  if (handle >= 1 && handle <= RPRX_MAX_OBJECTS) {
    g_objects[handle - 1] = 0;
    g_kind[handle - 1] = 0;
  }
}

// --- entry points -----------------------------------------------------------

typedef rpr_int (*PFN_register_plugin)(const char*);
typedef rpr_status (*PFN_create_context)(rpr_uint, const rpr_int*, size_t, rpr_uint,
                                         const void*, const char*, rpr_context*);
typedef rpr_status (*PFN_set_active_plugin)(rpr_context, rpr_int);
typedef rpr_status (*PFN_context_get_info)(rpr_context, rpr_uint, size_t, void*, size_t*);
typedef rpr_status (*PFN_context_set_scene)(rpr_context, rpr_scene);
typedef rpr_status (*PFN_context_set_param_u)(rpr_context, rpr_uint, rpr_uint);
typedef rpr_status (*PFN_context_set_param_f)(rpr_context, rpr_uint, rpr_float);
typedef rpr_status (*PFN_context_set_aov)(rpr_context, rpr_uint, rpr_framebuffer);
typedef rpr_status (*PFN_context_render)(rpr_context);
typedef rpr_status (*PFN_context_resolve)(rpr_context, rpr_framebuffer, rpr_framebuffer, rpr_bool);
typedef rpr_status (*PFN_create_scene)(rpr_context, rpr_scene*);
typedef rpr_status (*PFN_scene_attach_shape)(rpr_scene, rpr_shape);
typedef rpr_status (*PFN_scene_attach_light)(rpr_scene, rpr_light);
typedef rpr_status (*PFN_scene_set_camera)(rpr_scene, rpr_camera);
typedef rpr_status (*PFN_create_camera)(rpr_context, rpr_camera*);
typedef rpr_status (*PFN_camera_look_at)(rpr_camera, rpr_float, rpr_float, rpr_float,
                                         rpr_float, rpr_float, rpr_float,
                                         rpr_float, rpr_float, rpr_float);
typedef rpr_status (*PFN_camera_set_focal)(rpr_camera, rpr_float);
typedef rpr_status (*PFN_camera_set_sensor)(rpr_camera, rpr_float, rpr_float);
typedef rpr_status (*PFN_create_point_light)(rpr_context, rpr_light*);
typedef rpr_status (*PFN_create_directional_light)(rpr_context, rpr_light*);
typedef rpr_status (*PFN_light_set_transform)(rpr_light, rpr_bool, const rpr_float*);
typedef rpr_status (*PFN_light_set_power)(rpr_light, rpr_float, rpr_float, rpr_float);
typedef rpr_status (*PFN_create_matsys)(rpr_context, rpr_uint, rpr_material_system*);
typedef rpr_status (*PFN_matsys_create_node)(rpr_material_system, rpr_uint, rpr_material_node*);
typedef rpr_status (*PFN_node_set_input_f)(rpr_material_node, rpr_uint,
                                           rpr_float, rpr_float, rpr_float, rpr_float);
typedef rpr_status (*PFN_node_set_input_u)(rpr_material_node, rpr_uint, rpr_uint);
typedef rpr_status (*PFN_shape_set_material)(rpr_shape, rpr_material_node);
typedef rpr_status (*PFN_shape_set_transform)(rpr_shape, rpr_bool, const rpr_float*);
typedef rpr_status (*PFN_create_mesh)(rpr_context, const rpr_float*, size_t, rpr_int,
                                      const rpr_float*, size_t, rpr_int,
                                      const rpr_float*, size_t, rpr_int,
                                      const rpr_int*, rpr_int, const rpr_int*, rpr_int,
                                      const rpr_int*, rpr_int, const rpr_int*, size_t,
                                      rpr_shape*);
typedef rpr_status (*PFN_create_fb)(rpr_context, rpr_framebuffer_format,
                                    const rpr_framebuffer_desc*, rpr_framebuffer*);
typedef rpr_status (*PFN_fb_clear)(rpr_framebuffer);
typedef rpr_status (*PFN_fb_get_info)(rpr_framebuffer, rpr_uint, size_t, void*, size_t*);
typedef rpr_status (*PFN_object_delete)(void*);

static struct {
  HMODULE mod;
  PFN_register_plugin register_plugin;
  PFN_create_context create_context;
  PFN_set_active_plugin set_active_plugin;
  PFN_context_get_info context_get_info;
  PFN_context_set_scene context_set_scene;
  PFN_context_set_param_u context_set_param_u;
  PFN_context_set_param_f context_set_param_f;
  PFN_context_set_aov context_set_aov;
  PFN_context_render context_render;
  PFN_context_resolve context_resolve;
  PFN_create_scene create_scene;
  PFN_scene_attach_shape scene_attach_shape;
  PFN_scene_attach_light scene_attach_light;
  PFN_scene_set_camera scene_set_camera;
  PFN_create_camera create_camera;
  PFN_camera_look_at camera_look_at;
  PFN_camera_set_focal camera_set_focal;
  PFN_camera_set_sensor camera_set_sensor;
  PFN_create_point_light create_point_light;
  PFN_create_directional_light create_directional_light;
  PFN_light_set_transform light_set_transform;
  PFN_light_set_power point_light_set_power;
  PFN_light_set_power directional_light_set_power;
  PFN_create_matsys create_matsys;
  PFN_matsys_create_node matsys_create_node;
  PFN_node_set_input_f node_set_input_f;
  PFN_node_set_input_u node_set_input_u;
  PFN_shape_set_material shape_set_material;
  PFN_shape_set_transform shape_set_transform;
  PFN_create_mesh create_mesh;
  PFN_create_fb create_fb;
  PFN_fb_clear fb_clear;
  PFN_fb_get_info fb_get_info;
  PFN_object_delete object_delete;
} g_api;

#define RPRX_ENTRY(field, name)                                                   \
  do {                                                                            \
    g_api.field = (void*)GetProcAddress(g_api.mod, name);                         \
    if (g_api.field == 0) {                                                       \
      set_err("missing entry point: " name);                                      \
      return -101;                                                                \
    }                                                                             \
  } while (0)

// ---------------------------------------------------------------------------
// loader
// ---------------------------------------------------------------------------

/// Load the host API library.  `path` is a NUL-terminated UTF-8 path or an
/// empty string for the default name ("RadeonProRender64.dll", standard
/// search order).  Returns 0, or -100 (module not found) / -101 (missing
/// entry point, name in rprx_last_bridge_error()).  Idempotent: when a host
/// library is already loaded the call succeeds without reloading (live
/// objects stay valid).
int32_t rprx_load(const char* path) {
  if (g_api.mod) return 0;
  const char* name = (path && path[0]) ? path : "RadeonProRender64.dll";
  memset(&g_api, 0, sizeof(g_api));
  set_err("");
  int has_sep = (strchr(name, '\\') != 0) || (strchr(name, '/') != 0);
  g_api.mod = has_sep ? LoadLibraryExA(name, 0, LOAD_WITH_ALTERED_SEARCH_PATH)
                      : LoadLibraryA(name);
  if (!g_api.mod) {
    set_err(name);
    return -100;
  }
  RPRX_ENTRY(register_plugin, "rprRegisterPlugin");
  RPRX_ENTRY(create_context, "rprCreateContext");
  RPRX_ENTRY(set_active_plugin, "rprContextSetActivePlugin");
  RPRX_ENTRY(context_get_info, "rprContextGetInfo");
  RPRX_ENTRY(context_set_scene, "rprContextSetScene");
  RPRX_ENTRY(context_set_param_u, "rprContextSetParameterByKey1u");
  RPRX_ENTRY(context_set_param_f, "rprContextSetParameterByKey1f");
  RPRX_ENTRY(context_set_aov, "rprContextSetAOV");
  RPRX_ENTRY(context_render, "rprContextRender");
  RPRX_ENTRY(context_resolve, "rprContextResolveFrameBuffer");
  RPRX_ENTRY(create_scene, "rprContextCreateScene");
  RPRX_ENTRY(scene_attach_shape, "rprSceneAttachShape");
  RPRX_ENTRY(scene_attach_light, "rprSceneAttachLight");
  RPRX_ENTRY(scene_set_camera, "rprSceneSetCamera");
  RPRX_ENTRY(create_camera, "rprContextCreateCamera");
  RPRX_ENTRY(camera_look_at, "rprCameraLookAt");
  RPRX_ENTRY(camera_set_focal, "rprCameraSetFocalLength");
  RPRX_ENTRY(camera_set_sensor, "rprCameraSetSensorSize");
  RPRX_ENTRY(create_point_light, "rprContextCreatePointLight");
  RPRX_ENTRY(create_directional_light, "rprContextCreateDirectionalLight");
  RPRX_ENTRY(light_set_transform, "rprLightSetTransform");
  RPRX_ENTRY(point_light_set_power, "rprPointLightSetRadiantPower3f");
  RPRX_ENTRY(directional_light_set_power, "rprDirectionalLightSetRadiantPower3f");
  RPRX_ENTRY(create_matsys, "rprContextCreateMaterialSystem");
  RPRX_ENTRY(matsys_create_node, "rprMaterialSystemCreateNode");
  RPRX_ENTRY(node_set_input_f, "rprMaterialNodeSetInputFByKey");
  RPRX_ENTRY(node_set_input_u, "rprMaterialNodeSetInputUByKey");
  RPRX_ENTRY(shape_set_material, "rprShapeSetMaterial");
  RPRX_ENTRY(shape_set_transform, "rprShapeSetTransform");
  RPRX_ENTRY(create_mesh, "rprContextCreateMesh");
  RPRX_ENTRY(create_fb, "rprContextCreateFrameBuffer");
  RPRX_ENTRY(fb_clear, "rprFrameBufferClear");
  RPRX_ENTRY(fb_get_info, "rprFrameBufferGetInfo");
  RPRX_ENTRY(object_delete, "rprObjectDelete");
  return 0;
}

/// Last bridge message (loader diagnostics / rprContextGetInfo string reads)
/// as a NUL-terminated static C string (read with Str::from_c_str).
const char* rprx_last_bridge_error(void) {
  return g_err;
}

// ---------------------------------------------------------------------------
// plugin + context
// ---------------------------------------------------------------------------

/// rprRegisterPlugin(path) -> plugin id (>= 0), or -100/-102.
int32_t rprx_register_plugin(const char* path) {
  if (!g_api.mod) return -100;
  if (!path || !path[0]) return -104;
  rpr_int id = g_api.register_plugin(path);
  if (id < 0) { set_err(path); return -102; }
  return (int32_t)id;
}

/// rprCreateContext(api_version, {plugin_id}, flags, cache_path) -> handle.
int64_t rprx_context_create(int64_t api_version, int64_t plugin_id, int64_t flags,
                            const char* cache_path) {
  if (!g_api.mod) return -100;
  if (plugin_id < 0) return -104;
  rpr_int ids[1];
  ids[0] = (rpr_int)plugin_id;
  rpr_context ctx = 0;
  rpr_status st = g_api.create_context((rpr_uint)api_version, ids, 1, (rpr_uint)flags,
                                       0, (cache_path && cache_path[0]) ? cache_path : 0,
                                       &ctx);
  if (st != 0) return (int64_t)st;
  if (!ctx) { set_err("rprCreateContext returned success with a null context"); return -104; }
  return put_obj(RPRX_K_CONTEXT, ctx);
}

/// rprContextSetActivePlugin(context, plugin_id).
int32_t rprx_context_set_active_plugin(int64_t ctx_h, int64_t plugin_id) {
  rpr_context ctx = get_obj(ctx_h);
  if (!ctx) return -103;
  if (plugin_id < 0) return -104;
  return g_api.set_active_plugin(ctx, (rpr_int)plugin_id);
}

/// rprContextSetScene(context, scene).
int32_t rprx_context_set_scene(int64_t ctx_h, int64_t scene_h) {
  rpr_context ctx = get_obj(ctx_h);
  rpr_scene scene = get_obj(scene_h);
  if (!ctx || !scene) return -103;
  return g_api.context_set_scene(ctx, scene);
}

/// rprContextSetParameterByKey1u(context, key, value).
int32_t rprx_context_set_param_u(int64_t ctx_h, int64_t key, int64_t value) {
  rpr_context ctx = get_obj(ctx_h);
  if (!ctx) return -103;
  return g_api.context_set_param_u(ctx, (rpr_uint)key, (rpr_uint)value);
}

/// rprContextSetParameterByKey1f(context, key, value).
int32_t rprx_context_set_param_f(int64_t ctx_h, int64_t key, float value) {
  rpr_context ctx = get_obj(ctx_h);
  if (!ctx) return -103;
  return g_api.context_set_param_f(ctx, (rpr_uint)key, value);
}

/// rprContextSetAOV(context, RPR_AOV_COLOR, framebuffer).
int32_t rprx_context_set_aov_color(int64_t ctx_h, int64_t fb_h) {
  rpr_context ctx = get_obj(ctx_h);
  rpr_framebuffer fb = get_obj(fb_h);
  if (!ctx || !fb) return -103;
  return g_api.context_set_aov(ctx, 0 /* RPR_AOV_COLOR */, fb);
}

/// rprContextRender(context).
int32_t rprx_context_render(int64_t ctx_h) {
  rpr_context ctx = get_obj(ctx_h);
  if (!ctx) return -103;
  return g_api.context_render(ctx);
}

/// rprContextResolveFrameBuffer(context, src, dst, noDisplayGamma=false).
int32_t rprx_context_resolve(int64_t ctx_h, int64_t src_h, int64_t dst_h) {
  rpr_context ctx = get_obj(ctx_h);
  rpr_framebuffer src = get_obj(src_h);
  rpr_framebuffer dst = get_obj(dst_h);
  if (!ctx || !src || !dst) return -103;
  return g_api.context_resolve(ctx, src, dst, 0);
}

/// rprContextGetInfo(context, key, ...) as a string; fills the bridge
/// message buffer (read with rprx_last_bridge_error).  Returns the status.
int32_t rprx_context_info_str(int64_t ctx_h, int64_t key) {
  rpr_context ctx = get_obj(ctx_h);
  if (!ctx) return -103;
  g_err[0] = 0;
  rpr_status st = g_api.context_get_info(ctx, (rpr_uint)key, RPRX_ERR_CAP, g_err, 0);
  g_err[RPRX_ERR_CAP - 1] = 0;
  return st;
}

/// rprContextGetInfo(context, key, ...) as an unsigned int (packed returns).
int64_t rprx_context_info_u(int64_t ctx_h, int64_t key) {
  rpr_context ctx = get_obj(ctx_h);
  if (!ctx) return -103;
  rpr_uint v = 0;
  size_t sz = 0;
  rpr_status st = g_api.context_get_info(ctx, (rpr_uint)key, sizeof(v), &v, &sz);
  if (st != 0) return (int64_t)st;
  return (int64_t)v;
}

// ---------------------------------------------------------------------------
// scene / camera / light
// ---------------------------------------------------------------------------

/// rprContextCreateScene(context) -> scene handle.
int64_t rprx_scene_create(int64_t ctx_h) {
  rpr_context ctx = get_obj(ctx_h);
  if (!ctx) return -103;
  rpr_scene scene = 0;
  rpr_status st = g_api.create_scene(ctx, &scene);
  if (st != 0) return (int64_t)st;
  return put_obj(RPRX_K_SCENE, scene);
}

/// rprSceneAttachShape(scene, shape).
int32_t rprx_scene_attach_shape(int64_t scene_h, int64_t shape_h) {
  rpr_scene scene = get_obj(scene_h);
  rpr_shape shape = get_obj(shape_h);
  if (!scene || !shape) return -103;
  return g_api.scene_attach_shape(scene, shape);
}

/// rprSceneAttachLight(scene, light).
int32_t rprx_scene_attach_light(int64_t scene_h, int64_t light_h) {
  rpr_scene scene = get_obj(scene_h);
  rpr_light light = get_obj(light_h);
  if (!scene || !light) return -103;
  return g_api.scene_attach_light(scene, light);
}

/// rprSceneSetCamera(scene, camera).
int32_t rprx_scene_set_camera(int64_t scene_h, int64_t camera_h) {
  rpr_scene scene = get_obj(scene_h);
  rpr_camera camera = get_obj(camera_h);
  if (!scene || !camera) return -103;
  return g_api.scene_set_camera(scene, camera);
}

/// rprContextCreateCamera(context) -> camera handle.
int64_t rprx_camera_create(int64_t ctx_h) {
  rpr_context ctx = get_obj(ctx_h);
  if (!ctx) return -103;
  rpr_camera camera = 0;
  rpr_status st = g_api.create_camera(ctx, &camera);
  if (st != 0) return (int64_t)st;
  return put_obj(RPRX_K_CAMERA, camera);
}

/// rprCameraLookAt(camera, pos, at, up).
int32_t rprx_camera_look_at(int64_t cam_h, float px, float py, float pz,
                            float ax, float ay, float az,
                            float ux, float uy, float uz) {
  rpr_camera cam = get_obj(cam_h);
  if (!cam) return -103;
  return g_api.camera_look_at(cam, px, py, pz, ax, ay, az, ux, uy, uz);
}

/// rprCameraSetFocalLength(camera, mm).
int32_t rprx_camera_set_focal_length(int64_t cam_h, float mm) {
  rpr_camera cam = get_obj(cam_h);
  if (!cam) return -103;
  if (!(mm > 0.0f)) return -104;
  return g_api.camera_set_focal(cam, mm);
}

/// rprCameraSetSensorSize(camera, width, height).
int32_t rprx_camera_set_sensor_size(int64_t cam_h, float w, float h) {
  rpr_camera cam = get_obj(cam_h);
  if (!cam) return -103;
  if (!(w > 0.0f) || !(h > 0.0f)) return -104;
  return g_api.camera_set_sensor(cam, w, h);
}

/// rprContextCreatePointLight(context) -> light handle.
int64_t rprx_light_create_point(int64_t ctx_h) {
  rpr_context ctx = get_obj(ctx_h);
  if (!ctx) return -103;
  rpr_light light = 0;
  rpr_status st = g_api.create_point_light(ctx, &light);
  if (st != 0) return (int64_t)st;
  return put_obj(RPRX_K_LIGHT_POINT, light);
}

/// rprContextCreateDirectionalLight(context) -> light handle.
int64_t rprx_light_create_directional(int64_t ctx_h) {
  rpr_context ctx = get_obj(ctx_h);
  if (!ctx) return -103;
  rpr_light light = 0;
  rpr_status st = g_api.create_directional_light(ctx, &light);
  if (st != 0) return (int64_t)st;
  return put_obj(RPRX_K_LIGHT_DIRECTIONAL, light);
}

/// rprLightSetTransform(light, transpose=true, matrix[16] row-major).
int32_t rprx_light_set_transform(int64_t light_h, const float* m, int64_t count) {
  rpr_light light = get_obj(light_h);
  if (!light) return -103;
  if (!m || count != 16) return -104;
  return g_api.light_set_transform(light, 1, m);
}

/// rprPointLightSetRadiantPower3f / rprDirectionalLightSetRadiantPower3f --
/// one wrapper dispatching on the light kind recorded at creation.
int32_t rprx_light_set_power(int64_t light_h, float r, float g, float b) {
  rpr_light light = get_obj(light_h);
  if (!light) return -103;
  unsigned char kind = get_kind(light_h);
  if (kind == RPRX_K_LIGHT_POINT) {
    return g_api.point_light_set_power(light, r, g, b);
  }
  if (kind == RPRX_K_LIGHT_DIRECTIONAL) {
    return g_api.directional_light_set_power(light, r, g, b);
  }
  return -103;
}

// ---------------------------------------------------------------------------
// materials
// ---------------------------------------------------------------------------

/// rprContextCreateMaterialSystem(context, type) -> material-system handle.
int64_t rprx_material_system_create(int64_t ctx_h, int64_t ms_type) {
  rpr_context ctx = get_obj(ctx_h);
  if (!ctx) return -103;
  rpr_material_system ms = 0;
  rpr_status st = g_api.create_matsys(ctx, (rpr_uint)ms_type, &ms);
  if (st != 0) return (int64_t)st;
  return put_obj(RPRX_K_MATSYS, ms);
}

/// rprMaterialSystemCreateNode(matsys, node_type) -> material-node handle.
int64_t rprx_material_create_node(int64_t ms_h, int64_t node_type) {
  rpr_material_system ms = get_obj(ms_h);
  if (!ms) return -103;
  rpr_material_node node = 0;
  rpr_status st = g_api.matsys_create_node(ms, (rpr_uint)node_type, &node);
  if (st != 0) return (int64_t)st;
  return put_obj(RPRX_K_MATNODE, node);
}

/// rprMaterialNodeSetInputFByKey(node, input, x, y, z, w).
int32_t rprx_material_set_input_f(int64_t node_h, int64_t input,
                                  float x, float y, float z, float w) {
  rpr_material_node node = get_obj(node_h);
  if (!node) return -103;
  return g_api.node_set_input_f(node, (rpr_uint)input, x, y, z, w);
}

/// rprMaterialNodeSetInputUByKey(node, input, value).
int32_t rprx_material_set_input_u(int64_t node_h, int64_t input, int64_t value) {
  rpr_material_node node = get_obj(node_h);
  if (!node) return -103;
  return g_api.node_set_input_u(node, (rpr_uint)input, (rpr_uint)value);
}

/// rprShapeSetMaterial(shape, node).
int32_t rprx_shape_set_material(int64_t shape_h, int64_t node_h) {
  rpr_shape shape = get_obj(shape_h);
  rpr_material_node node = get_obj(node_h);
  if (!shape || !node) return -103;
  return g_api.shape_set_material(shape, node);
}

// ---------------------------------------------------------------------------
// mesh / transforms / framebuffer
// ---------------------------------------------------------------------------

/// rprShapeSetTransform(shape, transpose=true, matrix[16] row-major).
int32_t rprx_shape_set_transform(int64_t shape_h, const float* m, int64_t count) {
  rpr_shape shape = get_obj(shape_h);
  if (!shape) return -103;
  if (!m || count != 16) return -104;
  return g_api.shape_set_transform(shape, 1, m);
}

/// rprContextCreateMesh for triangle meshes: positions/normals are flat
/// vertex streams (3 floats per vertex), indices flat triples.  The bridge
/// builds the per-face vertex-count array (all 3).
int64_t rprx_mesh_create(int64_t ctx_h, const float* positions, int64_t pos_count,
                         const float* normals, int64_t norm_count,
                         const int32_t* indices, int64_t index_count) {
  rpr_context ctx = get_obj(ctx_h);
  if (!ctx) return -103;
  if (!positions || pos_count <= 0 || (pos_count % 3) != 0) return -104;
  if (norm_count != 0 && (!normals || norm_count != pos_count)) return -104;
  if (!indices || index_count < 3 || (index_count % 3) != 0) return -104;
  size_t vertex_count = (size_t)(pos_count / 3);
  size_t face_count = (size_t)(index_count / 3);
  int local_fvc[512];
  int* fvc = local_fvc;
  if (face_count > 512) {
    fvc = (int*)malloc(face_count * sizeof(int));
    if (!fvc) return -104;
  }
  for (size_t i = 0; i < face_count; i++) fvc[i] = 3;
  rpr_shape mesh = 0;
  rpr_status st = g_api.create_mesh(ctx, positions, vertex_count, (rpr_int)(3 * sizeof(float)),
                                    (norm_count != 0) ? normals : 0, vertex_count,
                                    (rpr_int)(3 * sizeof(float)),
                                    0, 0, 0,
                                    indices, (rpr_int)sizeof(int32_t),
                                    (norm_count != 0) ? indices : 0, (rpr_int)sizeof(int32_t),
                                    0, 0,
                                    fvc, face_count, &mesh);
  if (fvc != local_fvc) free(fvc);
  if (st != 0) return (int64_t)st;
  return put_obj(RPRX_K_SHAPE, mesh);
}

/// rprContextCreateFrameBuffer(context, {components, type}, {w, h}) -> handle.
int64_t rprx_framebuffer_create(int64_t ctx_h, int64_t width, int64_t height,
                                int64_t num_components, int64_t comp_type) {
  rpr_context ctx = get_obj(ctx_h);
  if (!ctx) return -103;
  if (width <= 0 || height <= 0 || num_components <= 0 || num_components > 8) return -104;
  rpr_framebuffer_format fmt;
  fmt.num_components = (rpr_uint)num_components;
  fmt.type = (rpr_uint)comp_type;
  rpr_framebuffer_desc d;
  d.fb_width = (rpr_uint)width;
  d.fb_height = (rpr_uint)height;
  rpr_framebuffer fb = 0;
  rpr_status st = g_api.create_fb(ctx, fmt, &d, &fb);
  if (st != 0) return (int64_t)st;
  return put_obj(RPRX_K_FB, fb);
}

/// rprFrameBufferClear(framebuffer).
int32_t rprx_framebuffer_clear(int64_t fb_h) {
  rpr_framebuffer fb = get_obj(fb_h);
  if (!fb) return -103;
  return g_api.fb_clear(fb);
}

/// rprFrameBufferGetInfo(framebuffer, RPR_FRAMEBUFFER_DESC) -> packed
/// (width << 32) | height, or a negative code.
int64_t rprx_framebuffer_desc(int64_t fb_h) {
  rpr_framebuffer fb = get_obj(fb_h);
  if (!fb) return -103;
  rpr_framebuffer_desc d;
  d.fb_width = 0;
  d.fb_height = 0;
  rpr_status st = g_api.fb_get_info(fb, 0x1302 /* RPR_FRAMEBUFFER_DESC */,
                                    sizeof(d), &d, 0);
  if (st != 0) return (int64_t)st;
  return ((int64_t)d.fb_width << 32) | (int64_t)d.fb_height;
}

/// rprFrameBufferGetInfo(framebuffer, RPR_FRAMEBUFFER_DATA) into an
/// XIOM-owned float buffer; returns the float count written, or -105 when
/// `out_count` does not match the framebuffer size.
int64_t rprx_framebuffer_read(int64_t fb_h, float* out, int64_t out_count) {
  rpr_framebuffer fb = get_obj(fb_h);
  if (!fb) return -103;
  if (!out || out_count <= 0) return -104;
  size_t sz = 0;
  rpr_status st = g_api.fb_get_info(fb, 0x1303 /* RPR_FRAMEBUFFER_DATA */, 0, 0, &sz);
  if (st != 0) return (int64_t)st;
  if (sz == 0 || (int64_t)sz != out_count * 4) return -105;
  st = g_api.fb_get_info(fb, 0x1303 /* RPR_FRAMEBUFFER_DATA */, sz, out, 0);
  if (st != 0) return (int64_t)st;
  return (int64_t)(sz / sizeof(float));
}

/// Same read-back into an XIOM-owned BYTE buffer; returns the byte count
/// written, or -105 when `out_count` does not match the framebuffer size.
int64_t rprx_framebuffer_read_bytes(int64_t fb_h, unsigned char* out, int64_t out_count) {
  rpr_framebuffer fb = get_obj(fb_h);
  if (!fb) return -103;
  if (!out || out_count <= 0) return -104;
  size_t sz = 0;
  rpr_status st = g_api.fb_get_info(fb, 0x1303 /* RPR_FRAMEBUFFER_DATA */, 0, 0, &sz);
  if (st != 0) return (int64_t)st;
  if (sz == 0 || (int64_t)sz != out_count) return -105;
  st = g_api.fb_get_info(fb, 0x1303 /* RPR_FRAMEBUFFER_DATA */, sz, out, 0);
  if (st != 0) return (int64_t)st;
  return (int64_t)sz;
}

/// rprObjectDelete(object) for any registered object; clears the slot.
int32_t rprx_object_delete(int64_t handle) {
  void* p = get_obj(handle);
  if (!p) return -103;
  rpr_status st = g_api.object_delete(p);
  if (st != 0) return st;
  clear_obj(handle);
  return 0;
}
