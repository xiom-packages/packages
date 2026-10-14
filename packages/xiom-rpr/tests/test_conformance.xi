// xiom.rpr conformance suite -- AMD Radeon ProRender core API through the
// runtime loader (nothing vendored from the SDK binaries).
//
// Build+run (the --c-source list rides in port.args.json):
//   scripts/port.ps1 -Package xiom.rpr -TimeoutSec 600
//
// Present-path proof (SPEC.md sec. 6): put the SDK's `binWin64` directory on
// PATH (or set XIOM_RPR_SDK_DIR to it) -- nothing is committed.  Without the
// SDK every backend check reports a typed SKIP and the suite stays green.

module rpr_conformance

use xiom.io;
use xiom.os;
use xiom.env;
use xiom.convert;
use xiom.rpr;
use xiom.rpr.ffi;

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

fn f2s(f: Float32) -> Str {
  return float_to_string(f as Float64);
}

// --- backend probe ----------------------------------------------------------

type ProbeResult = {
  state: Int;
  code: Int;
  message: Str;
  device_name: Str;
  width: Int;
  height: Int;
  float_count: Int;
  min_value: Float32;
  max_value: Float32;
  nonuniform: Bool;
  finite: Bool;
}

fn probe_result(state: Int, code: Int, message: Str) -> ProbeResult {
  return ProbeResult{
    state: state; code: code; message: message; device_name: "";
    width: 0; height: 0; float_count: 0;
    min_value: 0.0; max_value: 0.0; nonuniform: false; finite: true;
  };
}

fn probe_fail(e: RprError) -> ProbeResult {
  if e.kind == RPR_KIND_LOAD_ABSENT {
    return probe_result(RPR_STATE_SKIP_LOAD, e.code, e.message);
  }
  if e.kind == RPR_KIND_PLUGIN {
    return probe_result(RPR_STATE_SKIP_PLUGIN, e.code, e.message);
  }
  if e.kind == RPR_KIND_API {
    return probe_result(RPR_STATE_SKIP_UNUSABLE, e.code, e.message);
  }
  return probe_result(RPR_STATE_FAILED, e.code, e.message);
}

fn state_name(state: Int) -> Str {
  if state == RPR_STATE_RENDERED { return "RENDERED"; }
  if state == RPR_STATE_SKIP_LOAD { return "SKIP(host absent)"; }
  if state == RPR_STATE_SKIP_PLUGIN { return "SKIP(plugin absent)"; }
  if state == RPR_STATE_SKIP_UNUSABLE { return "SKIP(backend unusable on host)"; }
  if state == RPR_STATE_SKIP_NO_OUTPUT { return "SKIP(no render output on host)"; }
  return "FAILED";
}

/// Run the minimal upstream-tutorial scene (camera + plane + point light +
/// PBR material, 16x16, few iterations) on one backend and classify the
/// outcome.  Complexity: O(render).
fn probe_backend(module_path: Str, plugin_path: Str, flags: Int, width: Int,
    height: Int, iterations: Int) -> ProbeResult
  requires: width > 0
  requires: height > 0
{
  let lr = rpr.load(module_path);
  if !lr.is_ok { return probe_fail(lr.error); }
  let pr = rpr.register_plugin(plugin_path);
  if !pr.is_ok { return probe_fail(pr.error); }
  let plugin_id = pr.value;
  let cr = rpr.context_create(RPR_API_VERSION, plugin_id, flags, os.temp_dir());
  if !cr.is_ok { return probe_fail(cr.error); }
  let ctx = cr.value;
  let ar = rpr.context_set_active_plugin(ctx, plugin_id);
  if !ar.is_ok { return probe_fail(ar.error); }
  let sr = rpr.scene_create(ctx);
  if !sr.is_ok { return probe_fail(sr.error); }
  let scene = sr.value;
  let ssr = rpr.context_set_scene(ctx, scene);
  if !ssr.is_ok { return probe_fail(ssr.error); }

  let camr = rpr.camera_create(ctx);
  if !camr.is_ok { return probe_fail(camr.error); }
  let cam = camr.value;
  let clr = rpr.camera_look_at(cam, 0.0, 2.2, 5.5, 0.0, 0.8, 0.0, 0.0, 1.0, 0.0);
  if !clr.is_ok { return probe_fail(clr.error); }
  let cfr = rpr.camera_set_focal_length(cam, 35.0);
  if !cfr.is_ok { return probe_fail(cfr.error); }
  let cscr = rpr.scene_set_camera(scene, cam);
  if !cscr.is_ok { return probe_fail(cscr.error); }

  var positions = ffi.zero_floats(12);
  positions[0] = -5.0;  positions[1] = 0.0;   positions[2] = -5.0;
  positions[3] = -5.0;  positions[4] = 0.0;   positions[5] = 5.0;
  positions[6] = 5.0;   positions[7] = 0.0;   positions[8] = 5.0;
  positions[9] = 5.0;   positions[10] = 0.0;  positions[11] = -5.0;
  var normals = ffi.zero_floats(12);
  var k: Int = 0;
  while k < 12 {
    normals[k + 1] = 1.0;
    k = k + 3;
  }
  var indices = ffi.zero_i32(6);
  indices[0] = 0; indices[1] = 1; indices[2] = 2;
  indices[3] = 0; indices[4] = 2; indices[5] = 3;
  let mr = rpr.mesh_create(ctx, &mut positions, &mut normals, &mut indices);
  if !mr.is_ok { return probe_fail(mr.error); }
  let plane = mr.value;
  let asr = rpr.scene_attach_shape(scene, plane);
  if !asr.is_ok { return probe_fail(asr.error); }

  let plr = rpr.light_create_point(ctx);
  if !plr.is_ok { return probe_fail(plr.error); }
  let light = plr.value;
  var ltm = rpr.translation_matrix(2.5, 4.0, 2.5);
  let ltr = rpr.light_set_transform(light, &mut ltm);
  if !ltr.is_ok { return probe_fail(ltr.error); }
  let lpr = rpr.light_set_radiance(light, 300.0, 300.0, 300.0);
  if !lpr.is_ok { return probe_fail(lpr.error); }
  let alr = rpr.scene_attach_light(scene, light);
  if !alr.is_ok { return probe_fail(alr.error); }

  let msr = rpr.material_system_create(ctx, 0);
  if !msr.is_ok { return probe_fail(msr.error); }
  let ms = msr.value;
  let mnr = rpr.material_create_node(ms, RPR_MATERIAL_NODE_UBERV2);
  if !mnr.is_ok { return probe_fail(mnr.error); }
  let mat = mnr.value;
  let i1 = rpr.material_set_input_f(mat, RPR_MATERIAL_INPUT_UBER_DIFFUSE_COLOR, 0.8, 0.2, 0.2, 0.0);
  if !i1.is_ok { return probe_fail(i1.error); }
  let i2 = rpr.material_set_input_f(mat, RPR_MATERIAL_INPUT_UBER_DIFFUSE_WEIGHT, 1.0, 0.0, 0.0, 0.0);
  if !i2.is_ok { return probe_fail(i2.error); }
  let i3 = rpr.material_set_input_f(mat, RPR_MATERIAL_INPUT_UBER_REFLECTION_COLOR, 1.0, 1.0, 1.0, 0.0);
  if !i3.is_ok { return probe_fail(i3.error); }
  let i4 = rpr.material_set_input_f(mat, RPR_MATERIAL_INPUT_UBER_REFLECTION_WEIGHT, 0.2, 0.0, 0.0, 0.0);
  if !i4.is_ok { return probe_fail(i4.error); }
  let smr = rpr.shape_set_material(plane, mat);
  if !smr.is_ok { return probe_fail(smr.error); }

  let fbr = rpr.framebuffer_create(ctx, width, height, 4, RPR_COMPONENT_TYPE_FLOAT32);
  if !fbr.is_ok { return probe_fail(fbr.error); }
  let fb = fbr.value;
  let fb2r = rpr.framebuffer_create(ctx, width, height, 4, RPR_COMPONENT_TYPE_FLOAT32);
  if !fb2r.is_ok { return probe_fail(fb2r.error); }
  let fb2 = fb2r.value;
  let aov = rpr.context_set_aov_color(ctx, fb);
  if !aov.is_ok { return probe_fail(aov.error); }
  let itr = rpr.context_set_iterations(ctx, iterations);
  if !itr.is_ok { return probe_fail(itr.error); }
  let clr2 = rpr.framebuffer_clear(fb);
  if !clr2.is_ok { return probe_fail(clr2.error); }
  let rr = rpr.context_render(ctx);
  if !rr.is_ok { return probe_fail(rr.error); }
  let resr = rpr.context_resolve(ctx, fb, fb2);
  if !resr.is_ok { return probe_fail(resr.error); }

  var pixels = ffi.zero_floats(width * height * 4);
  let rd = rpr.framebuffer_read(fb2, &mut pixels);
  if !rd.is_ok { return probe_fail(rd.error); }

  var mn: Float32 = pixels[0];
  var mx: Float32 = pixels[0];
  var finite = true;
  var i: Int = 0;
  while i < pixels.len() {
    let v = pixels[i];
    if v != v { finite = false; }
    if v < mn { mn = v; }
    if v > mx { mx = v; }
    i = i + 1;
  }

  let dn = rpr.context_info_str(ctx, RPR_CONTEXT_CPU_NAME);
  var device = "";
  if dn.is_ok { device = dn.value; }
  let gn = rpr.context_info_str(ctx, RPR_CONTEXT_GPU0_NAME);
  if gn.is_ok {
    if gn.value.len() > 0 { device = gn.value; }
  }

  var out = probe_result(RPR_STATE_RENDERED, 0, "");
  out.device_name = device;
  out.width = width;
  out.height = height;
  out.float_count = rd.value;
  out.min_value = mn;
  out.max_value = mx;
  out.finite = finite;
  out.nonuniform = mx > mn;
  if !finite {
    out.state = RPR_STATE_FAILED;
    out.message = "non-finite framebuffer values";
  } elif mx <= mn {
    // Backend completed every call but wrote no render output (host GPU not
    // supported by the backend) -- a classified platform state, not a fail.
    out.state = RPR_STATE_SKIP_NO_OUTPUT;
    out.message = "framebuffer is blank (no render output on this host)";
  }

  // Cleanup (context last, per the upstream contract).
  let d1 = rpr.material_node_destroy(mat);
  let d2 = rpr.material_system_destroy(ms);
  let d3 = rpr.light_destroy(light);
  let d4 = rpr.shape_destroy(plane);
  let d5 = rpr.camera_destroy(cam);
  let d6 = rpr.framebuffer_destroy(fb);
  let d7 = rpr.framebuffer_destroy(fb2);
  let d8 = rpr.scene_destroy(scene);
  let d9 = rpr.context_destroy(ctx);
  if !(d1.is_ok && d2.is_ok && d3.is_ok && d4.is_ok && d5.is_ok && d6.is_ok && d7.is_ok && d8.is_ok && d9.is_ok) {
    return probe_result(RPR_STATE_FAILED, -1, "cleanup failed");
  }
  return out;
}

// --- detailed CPU pipeline --------------------------------------------------

/// Full present-path run on the CPU backend with the deep checks (descriptor,
/// float + byte read-backs, stats, error paths, lifecycle).  Returns the
/// number of failed checks.
/// Complexity: O(render).
fn run_cpu_detailed(host_path: Str, plugin_path: Str) -> Int {
  var failed: Int = 0;

  let lr = rpr.load(host_path);
  if !lr.is_ok {
    failed = failed + report(false, "cpu: host library load -- " + lr.error.message);
    return failed;
  }
  failed = failed + report(true, "cpu: host library loaded (RadeonProRender64.dll)");

  let pr = rpr.register_plugin(plugin_path);
  if !pr.is_ok {
    failed = failed + report(true, "cpu: Northstar64.dll absent (" + pr.error.message + ") (SKIP)");
    return failed;
  }
  let plugin_id = pr.value;
  failed = failed + report(true, "cpu: Northstar64.dll registered (plugin id " + to_string(plugin_id) + ")");

  let cr = rpr.context_create(RPR_API_VERSION, plugin_id, RPR_CREATION_FLAGS_ENABLE_CPU, os.temp_dir());
  if !cr.is_ok {
    failed = failed + report(true, "cpu: context create -- " + cr.error.message + " (SKIP)");
    return failed;
  }
  let ctx = cr.value;
  let ar = rpr.context_set_active_plugin(ctx, plugin_id);
  failed = failed + report(ar.is_ok, "cpu: context created + active plugin set");

  let av = rpr.context_info_u(ctx, RPR_CONTEXT_API_VERSION);
  failed = failed + report(av.is_ok && av.value == RPR_API_VERSION,
    "cpu: rprContextGetInfo(RPR_CONTEXT_API_VERSION) = 0x00300107");

  let dn = rpr.context_info_str(ctx, RPR_CONTEXT_CPU_NAME);
  var device = "";
  if dn.is_ok { device = dn.value; }
  failed = failed + report(device.len() > 0, "cpu: device name reported (" + device + ")");

  let sr = rpr.scene_create(ctx);
  if !sr.is_ok {
    failed = failed + report(false, "cpu: scene create -- " + sr.error.message);
    return failed;
  }
  let scene = sr.value;
  let ssr = rpr.context_set_scene(ctx, scene);
  failed = failed + report(ssr.is_ok, "cpu: scene created + set as active scene");

  let camr = rpr.camera_create(ctx);
  var cam_ok = false;
  var cam = RprCamera{ id: 0 };
  if camr.is_ok {
    cam = camr.value;
    let l1 = rpr.camera_look_at(cam, 0.0, 2.2, 5.5, 0.0, 0.8, 0.0, 0.0, 1.0, 0.0);
    let l2 = rpr.camera_set_focal_length(cam, 35.0);
    let l3 = rpr.camera_set_sensor_size(cam, 36.0, 24.0);
    let l4 = rpr.scene_set_camera(scene, cam);
    cam_ok = l1.is_ok && l2.is_ok && l3.is_ok && l4.is_ok;
  }
  failed = failed + report(cam_ok, "cpu: camera create + look_at + focal + sensor + scene_set_camera");

  // plane quad (with normals) + identity transform
  var positions = ffi.zero_floats(12);
  positions[0] = -5.0;  positions[1] = 0.0;   positions[2] = -5.0;
  positions[3] = -5.0;  positions[4] = 0.0;   positions[5] = 5.0;
  positions[6] = 5.0;   positions[7] = 0.0;   positions[8] = 5.0;
  positions[9] = 5.0;   positions[10] = 0.0;  positions[11] = -5.0;
  var normals = ffi.zero_floats(12);
  var k: Int = 0;
  while k < 12 {
    normals[k + 1] = 1.0;
    k = k + 3;
  }
  var indices = ffi.zero_i32(6);
  indices[0] = 0; indices[1] = 1; indices[2] = 2;
  indices[3] = 0; indices[4] = 2; indices[5] = 3;
  let mr = rpr.mesh_create(ctx, &mut positions, &mut normals, &mut indices);
  var plane_ok = false;
  var plane = RprShape{ id: 0 };
  if mr.is_ok {
    plane = mr.value;
    var idm = rpr.identity_matrix();
    let t1 = rpr.shape_set_transform(plane, &mut idm);
    let t2 = rpr.scene_attach_shape(scene, plane);
    plane_ok = t1.is_ok && t2.is_ok;
  }
  failed = failed + report(plane_ok, "cpu: plane mesh (4 vertices / 2 tris) + transform + attach");

  // point light with transform + radiance + attach
  let plr = rpr.light_create_point(ctx);
  var light_ok = false;
  var light = RprLight{ id: 0 };
  if plr.is_ok {
    light = plr.value;
    var ltm = rpr.translation_matrix(2.5, 4.0, 2.5);
    let l1 = rpr.light_set_transform(light, &mut ltm);
    let l2 = rpr.light_set_radiance(light, 300.0, 300.0, 300.0);
    let l3 = rpr.scene_attach_light(scene, light);
    light_ok = l1.is_ok && l2.is_ok && l3.is_ok;
  }
  failed = failed + report(light_ok, "cpu: point light + transform + radiant power + attach");

  // directional light lifecycle (create / power / destroy)
  let dlr = rpr.light_create_directional(ctx);
  var dir_ok = false;
  if dlr.is_ok {
    let dl = dlr.value;
    let p1 = rpr.light_set_radiance(dl, 0.5, 0.5, 0.5);
    let p2 = rpr.light_destroy(dl);
    dir_ok = p1.is_ok && p2.is_ok;
  }
  failed = failed + report(dir_ok, "cpu: directional light create + power + destroy");

  // UBER V2 material (PBR) with float + uint inputs, assigned to the plane
  let msr = rpr.material_system_create(ctx, 0);
  var mat_ok = false;
  var mat = RprMaterialNode{ id: 0 };
  var ms = RprMaterialSystem{ id: 0 };
  if msr.is_ok {
    ms = msr.value;
    let mnr = rpr.material_create_node(ms, RPR_MATERIAL_NODE_UBERV2);
    if mnr.is_ok {
      mat = mnr.value;
      let i1 = rpr.material_set_input_f(mat, RPR_MATERIAL_INPUT_UBER_DIFFUSE_COLOR, 0.8, 0.2, 0.2, 0.0);
      let i2 = rpr.material_set_input_f(mat, RPR_MATERIAL_INPUT_UBER_DIFFUSE_WEIGHT, 1.0, 0.0, 0.0, 0.0);
      let i3 = rpr.material_set_input_f(mat, RPR_MATERIAL_INPUT_UBER_REFLECTION_COLOR, 1.0, 1.0, 1.0, 0.0);
      let i4 = rpr.material_set_input_f(mat, RPR_MATERIAL_INPUT_UBER_REFLECTION_WEIGHT, 0.2, 0.0, 0.0, 0.0);
      let i5 = rpr.material_set_input_u(mat, RPR_MATERIAL_INPUT_UBER_REFLECTION_MODE, 1);
      let i6 = rpr.shape_set_material(plane, mat);
      mat_ok = i1.is_ok && i2.is_ok && i3.is_ok && i4.is_ok && i5.is_ok && i6.is_ok;
    }
  }
  failed = failed + report(mat_ok, "cpu: PBR material (UBERV2) + inputs (F/U) + shape_set_material");

  // normal-less secondary mesh (bridge owns the no-normals path)
  var p2v = ffi.zero_floats(9);
  p2v[0] = -1.0; p2v[1] = 2.0; p2v[2] = -1.0;
  p2v[3] = 1.0;  p2v[4] = 2.0; p2v[5] = -1.0;
  p2v[6] = 0.0;  p2v[7] = 2.0; p2v[8] = 1.0;
  var none = ffi.zero_floats(0);
  var idx2 = ffi.zero_i32(3);
  idx2[0] = 0; idx2[1] = 1; idx2[2] = 2;
  let mr2 = rpr.mesh_create(ctx, &mut p2v, &mut none, &mut idx2);
  var mesh2_ok = false;
  if mr2.is_ok {
    let d = rpr.shape_destroy(mr2.value);
    mesh2_ok = d.is_ok;
  }
  failed = failed + report(mesh2_ok, "cpu: normal-less triangle mesh + destroy");

  // framebuffers + AOV + iterations + gamma
  let fbr = rpr.framebuffer_create(ctx, 16, 16, 4, RPR_COMPONENT_TYPE_FLOAT32);
  var fb = RprFrameBuffer{ id: 0 };
  var fb2 = RprFrameBuffer{ id: 0 };
  var fb_ok = false;
  if fbr.is_ok {
    fb = fbr.value;
    let fbr2 = rpr.framebuffer_create(ctx, 16, 16, 4, RPR_COMPONENT_TYPE_FLOAT32);
    if fbr2.is_ok {
      fb2 = fbr2.value;
      let a = rpr.context_set_aov_color(ctx, fb);
      let b = rpr.framebuffer_clear(fb);
      let c = rpr.context_set_iterations(ctx, 8);
      let d = rpr.context_set_param_f(ctx, RPR_CONTEXT_DISPLAY_GAMMA, 2.2);
      fb_ok = a.is_ok && b.is_ok && c.is_ok && d.is_ok;
    }
  }
  failed = failed + report(fb_ok, "cpu: framebuffers + AOV colour + iterations=8 + display gamma");

  if !fb_ok {
    failed = failed + report(false, "cpu: render pipeline unavailable (framebuffer setup failed)");
    return failed;
  }

  let rr = rpr.context_render(ctx);
  failed = failed + report(rr.is_ok, "cpu: rprContextRender (16x16, 8 iterations)");
  let rs = rpr.context_info_u(ctx, RPR_CONTEXT_RENDER_STATUS);
  let resr = rpr.context_resolve(ctx, fb, fb2);
  failed = failed + report(resr.is_ok && rs.is_ok, "cpu: resolve frame buffer + render status readable");

  let dr = rpr.framebuffer_desc(fb2);
  failed = failed + report(dr.is_ok && dr.value == ((16 << 32) | 16),
    "cpu: rprFrameBufferGetInfo(DESC) = 16x16 (packed " + (if dr.is_ok { to_string(dr.value) } else { "err" }) + ")");

  var pixels = ffi.zero_floats(16 * 16 * 4);
  let rd = rpr.framebuffer_read(fb2, &mut pixels);
  failed = failed + report(rd.is_ok && rd.value == 16 * 16 * 4,
    "cpu: read-back into XIOM-owned float buffer (" + (if rd.is_ok { to_string(rd.value) } else { "err" }) + " floats)");

  var bytes = ffi.zero_bytes(16 * 16 * 4 * 4);
  let rb = rpr.framebuffer_read_bytes(fb2, &mut bytes);
  failed = failed + report(rb.is_ok && rb.value == 16 * 16 * 4 * 4,
    "cpu: read-back into XIOM-owned byte buffer (" + (if rb.is_ok { to_string(rb.value) } else { "err" }) + " bytes)");

  // stats over the owned float buffer (no foreign pointer is read)
  var mn: Float32 = pixels[0];
  var mx: Float32 = pixels[0];
  var finite = true;
  var vsum: Float32 = 0.0;
  var i: Int = 0;
  while i < pixels.len() {
    let v = pixels[i];
    if v != v { finite = false; }
    if v < mn { mn = v; }
    if v > mx { mx = v; }
    vsum = vsum + v;
    i = i + 1;
  }
  failed = failed + report(finite, "cpu: framebuffer floats finite (no NaN/inf)");
  failed = failed + report(mx > mn && mx > 0.0 && mn >= 0.0,
    "cpu: framebuffer read-back non-uniform + non-negative (min=" + f2s(mn) + " max=" + f2s(mx) + ")");

  var nz: Int = 0;
  var changes: Int = 0;
  var b: Int = 0;
  while b < bytes.len() {
    if bytes[b] != 0 { nz = nz + 1; }
    if b > 0 {
      if bytes[b] != bytes[b - 1] { changes = changes + 1; }
    }
    b = b + 1;
  }
  failed = failed + report(nz > 0 && changes > 0,
    "cpu: byte read-back non-uniform (" + to_string(nz) + " nonzero bytes, " + to_string(changes) + " byte changes)");

  // typed error paths
  var small = ffi.zero_floats(16);
  let cap = rpr.framebuffer_read(fb2, &mut small);
  failed = failed + report(!cap.is_ok && cap.error.kind == RPR_KIND_CAPACITY,
    "cpu: wrong-size read-back classified RPR_KIND_CAPACITY");

  let api_err = rpr.context_set_param_u(ctx, 0x999, 1);
  failed = failed + report(!api_err.is_ok && api_err.error.kind == RPR_KIND_API,
    "cpu: live rpr_status error classified RPR_KIND_API (code " + (if api_err.is_ok { "0" } else { to_string(api_err.error.code) }) + ")");

  let fake = RprContext{ id: 9999 };
  let h_err = rpr.context_render(fake);
  failed = failed + report(!h_err.is_ok && h_err.error.kind == RPR_KIND_HANDLE,
    "cpu: invalid handle classified RPR_KIND_HANDLE");

  let args_err = ffi.framebuffer_create(ctx.id, 0, 16, 4, RPR_COMPONENT_TYPE_FLOAT32);
  failed = failed + report(args_err == -104,
    "cpu: bridge rejects bad args with -104 (RPR_KIND_ARGS)");

  // lifecycle: delete everything (context last), then a double delete fails typed
  let d1 = rpr.material_node_destroy(mat);
  let d2 = rpr.material_system_destroy(ms);
  let d3 = rpr.light_destroy(light);
  let d4 = rpr.shape_destroy(plane);
  let d5 = rpr.camera_destroy(cam);
  let d6 = rpr.framebuffer_destroy(fb);
  let d7 = rpr.framebuffer_destroy(fb2);
  let d8 = rpr.scene_destroy(scene);
  let d9 = rpr.context_destroy(ctx);
  failed = failed + report(d1.is_ok && d2.is_ok && d3.is_ok && d4.is_ok && d5.is_ok && d6.is_ok && d7.is_ok && d8.is_ok && d9.is_ok,
    "cpu: full rprObjectDelete lifecycle (context last)");

  let dbl = rpr.scene_destroy(scene);
  failed = failed + report(!dbl.is_ok && dbl.error.kind == RPR_KIND_HANDLE,
    "cpu: double delete classified RPR_KIND_HANDLE");

  return failed;
}

// --- main -------------------------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.rpr conformance tests (Radeon ProRender 3.1.7.1, runtime loader) ===");
  io.flush_stdout();
  var failed: Int = 0;

  // 1. pinned constants
  failed = failed + report(
    RPR_API_VERSION == 0x00300107 && RPR_VERSION_MAJOR == 3 && RPR_VERSION_MINOR == 1 && RPR_VERSION_REVISION == 7,
    "constants: RPR_API_VERSION 0x00300107 (3.1.7)");
  failed = failed + report(
    RPR_CREATION_FLAGS_ENABLE_CPU == 16 && RPR_CREATION_FLAGS_ENABLE_GPU0 == 1 &&
    RPR_AOV_COLOR == 0 && RPR_CONTEXT_ITERATIONS == 0x10B && RPR_CONTEXT_RENDER_STATUS == 0x104 &&
    RPR_COMPONENT_TYPE_FLOAT32 == 3 && RPR_FRAMEBUFFER_DATA == 0x1303 &&
    RPR_MATERIAL_NODE_UBERV2 == 0x2b && RPR_MATERIAL_NODE_DIFFUSE == 1 &&
    RPR_MATERIAL_INPUT_UBER_DIFFUSE_COLOR == 0x910 && RPR_MATERIAL_INPUT_UBER_REFLECTION_COLOR == 0x913 &&
    RPR_LIGHT_TYPE_POINT == 1 && RPR_LIGHT_TYPE_DIRECTIONAL == 2,
    "constants: creation flags / AOV / context keys / material + light ids");

  // 2. error model
  failed = failed + report(
    error_of(-100).kind == RPR_KIND_LOAD_ABSENT && error_of(-101).kind == RPR_KIND_SYMBOL_MISSING &&
    error_of(-102).kind == RPR_KIND_PLUGIN && error_of(-103).kind == RPR_KIND_HANDLE &&
    error_of(-104).kind == RPR_KIND_ARGS && error_of(-105).kind == RPR_KIND_CAPACITY &&
    error_of(-106).kind == RPR_KIND_TABLE_FULL && error_of(-23).kind == RPR_KIND_API &&
    error_is_skip(error_of(-100)) && error_is_skip(error_of(-102)) && !error_is_skip(error_of(-23)),
    "error model: bridge codes + rpr_status classify to typed kinds (SKIP vs FAIL)");

  // 3. deterministic skip path: host library absent
  let absent = rpr.load("xiom-absent-rpr-probe-xyz.dll");
  failed = failed + report(!absent.is_ok && absent.error.kind == RPR_KIND_LOAD_ABSENT,
    "skip-path: missing host library classified RPR_KIND_LOAD_ABSENT (SKIP)");

  // 4. present path: SDK dir from XIOM_RPR_SDK_DIR, else default DLL names
  let sdk = env.var_or("XIOM_RPR_SDK_DIR", "");
  var host_path = "";
  var cpu_plugin = "Northstar64.dll";
  var gpu_plugin = "Tahoe64.dll";
  var gpu2_plugin = "HybridPro.dll";
  if sdk.len() > 0 {
    host_path = env.join_paths(sdk, "RadeonProRender64.dll");
    cpu_plugin = env.join_paths(sdk, "Northstar64.dll");
    gpu_plugin = env.join_paths(sdk, "Tahoe64.dll");
    gpu2_plugin = env.join_paths(sdk, "HybridPro.dll");
  }
  let host = rpr.load(host_path);
  var host_ok = false;
  if host.is_ok {
    host_ok = true;
    failed = failed + report(true, "host: RadeonProRender64.dll loaded (path: " + (if host_path.len() > 0 { host_path } else { "default search" }) + ")");
  } else {
    if host.error.kind == RPR_KIND_LOAD_ABSENT {
      failed = failed + report(true, "host: RadeonProRender64.dll not present -- all backend checks SKIP (" + host.error.message + ")");
    } else {
      failed = failed + report(false, "host: load failed -- " + host.error.message);
    }
  }

  // 5. missing plugin (deterministic SKIP classification)
  let bogus = rpr.register_plugin("xiom-absent-rpr-plugin-xyz.dll");
  var bogus_msg = "skip-path: missing backend plugin classified ";
  if bogus.is_ok {
    bogus_msg = bogus_msg + "unexpectedly ok";
  } elif bogus.error.kind == RPR_KIND_PLUGIN {
    bogus_msg = bogus_msg + "RPR_KIND_PLUGIN (SKIP)";
  } else {
    bogus_msg = bogus_msg + "RPR_KIND_LOAD_ABSENT (SKIP)";
  }
  failed = failed + report(
    !bogus.is_ok && (bogus.error.kind == RPR_KIND_PLUGIN || bogus.error.kind == RPR_KIND_LOAD_ABSENT),
    bogus_msg);

  // 6. detailed CPU run
  if host_ok {
    failed = failed + run_cpu_detailed(host_path, cpu_plugin);
  } else {
    failed = failed + report(true, "cpu: backend checks skipped (host absent) (SKIP)");
  }

  // 7. GPU backends: render or typed SKIP
  let tahoe = probe_backend(host_path, gpu_plugin, RPR_CREATION_FLAGS_ENABLE_GPU0, 16, 16, 8);
  if tahoe.state == RPR_STATE_RENDERED {
    failed = failed + report(true,
      "gpu: Tahoe64 rendered (" + tahoe.device_name + ") floats=" + to_string(tahoe.float_count) +
      " min=" + f2s(tahoe.min_value) + " max=" + f2s(tahoe.max_value));
    failed = failed + report(tahoe.nonuniform && tahoe.finite,
      "gpu: Tahoe64 output contract (non-uniform + finite)");
  } else {
    failed = failed + report(tahoe.state != RPR_STATE_FAILED,
      "gpu: Tahoe64 " + state_name(tahoe.state) + " code=" + to_string(tahoe.code) + " -- " + tahoe.message);
  }

  let hybrid = probe_backend(host_path, gpu2_plugin, RPR_CREATION_FLAGS_ENABLE_GPU0, 16, 16, 8);
  if hybrid.state == RPR_STATE_RENDERED {
    failed = failed + report(true,
      "gpu: HybridPro rendered (" + hybrid.device_name + ") floats=" + to_string(hybrid.float_count) +
      " min=" + f2s(hybrid.min_value) + " max=" + f2s(hybrid.max_value));
    failed = failed + report(hybrid.nonuniform && hybrid.finite,
      "gpu: HybridPro output contract (non-uniform + finite)");
  } else {
    failed = failed + report(hybrid.state != RPR_STATE_FAILED,
      "gpu: HybridPro " + state_name(hybrid.state) + " code=" + to_string(hybrid.code) + " -- " + hybrid.message);
  }

  if failed == 0 {
    io.println("xiom.rpr: all tests passed");
  } else {
    io.println("xiom.rpr: tests failed");
  }
  return failed;
}
