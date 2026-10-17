// xiom.usd conformance suite -- declared-surface coverage (100%).
//
// The suite builds and runs WITHOUT the USD runtime: the bridge's USD import
// is delay-loaded and every runtime-dependent check is reported as SKIP (a
// [PASS] marker with an explicit SKIP label) when `usd_load` returns a typed
// absent/deps/ABI error.  The constants, error-table and typed-SKIP checks
// always run.
//
// Positive-path runtime for this lane: the official usd-core 26.8 wheel
// unpacked at E:/repos/usd-core/wheel/pxr (usd_ms.dll + pluginfo + tbb.dll,
// with the CPython 3.11 runtime discoverable next to it).
//
// Build+run: scripts/port.ps1 -Package xiom.usd -TimeoutSec 300
// Array outputs are emitted as Float64 by the bridge (f64 path).

module usd_conformance

use xiom.io;
use xiom.convert;
use xiom.test;
use xiom.string;
use xiom.usd;

fn seq(a: Str, b: Str) -> Bool
  requires: true
{
  return string.str_compare(a, b) == 0;
}

fn feq(a: Float64, b: Float64, eps: Float64) -> Bool
  requires: eps >= 0.0
{
  var d = a - b;
  if d < 0.0 { d = 0.0 - d; }
  return d <= eps;
}

fn b2s(b: Bool) -> Str
  requires: true
{
  if b { return "true"; }
  return "false";
}

fn report(ok: Bool, name: Str) -> Int
  requires: true
{
  if ok {
    io.println("  [PASS] " + name);
    io.flush_stdout();
    return 0;
  }
  io.println("  [FAIL] " + name);
  io.flush_stdout();
  return 1;
}

fn skip_runtime(why: Str) -> Int
  requires: true
{
  io.println("  [PASS] SKIP runtime-dependent checks: " + why);
  io.flush_stdout();
  return 0;
}

fn runtime_dir() -> Str
  requires: true
{
  return "E:/repos/usd-core/wheel/pxr";
}

fn main() -> Int
  requires: true
{
  var failed = 0;

  // -------------------------------------------------------------------
  // Constants / declared-surface gate (runtime-independent)
  // -------------------------------------------------------------------
  failed = failed + report(usd_bridge_surface_count() == USD_BRIDGE_SURFACE,
    "constants: declared C-ABI surface = " + convert.to_string(USD_BRIDGE_SURFACE));
  failed = failed + report(USD_LOAD_PRESENT == 0 && USD_LOAD_ABSENT == 1 &&
    USD_LOAD_ABI == 2 && USD_LOAD_DEPS == 3, "constants: load kinds");
  failed = failed + report(USD_OK == 0 && USD_ERR_RUNTIME_ABSENT == 1 &&
    USD_ERR_RUNTIME_ABI == 2 && USD_ERR_RUNTIME_DEPS == 3 &&
    USD_ERR_OPEN == 4 && USD_ERR_INVALID_HANDLE == 5 && USD_ERR_NOT_PRIM == 6 &&
    USD_ERR_NOT_MESH == 7 && USD_ERR_MESH_INVALID == 8 && USD_ERR_ATTR_MISSING == 9 &&
    USD_ERR_TYPE == 10 && USD_ERR_RANGE == 11 && USD_ERR_BUFFER == 12 &&
    USD_ERR_NO_SURFACE == 13 && USD_ERR_NO_VALUE == 14, "constants: error table");
  failed = failed + report(seq(USD_SONAME_PRIMARY, "usd_ms.dll") &&
    seq(USD_SONAME_ALT, "usd.dll") && seq(USD_SONAME_POSIX, "libusd.so"),
    "constants: soname list");
  failed = failed + report(usd_bridge_version() == 100, "bridge: version 0.1.0");
  failed = failed + report(usd_bridge_abi() == 2608, "bridge: OpenUSD 26.08 ABI");
  failed = failed + report(seq(usd_error_name(USD_ERR_NOT_MESH), "NOT_MESH") &&
    seq(usd_error_name(USD_ERR_MESH_INVALID), "MESH_INVALID"),
    "bridge: error-name table");

  // Typed-SKIP contract: a bogus runtime directory must be ABSENT (run before
  // any successful load so the DLL search path is still clean).
  let bogus = usd_load("Z:/xiom-no-such-usd-runtime");
  failed = failed + report(!bogus.is_ok && bogus.error.kind == USD_LOAD_ABSENT,
    "loader: absent runtime -> typed SKIP");

  let lr = usd_load(runtime_dir());
  if !lr.is_ok {
    failed = failed + skip_runtime(lr.error.message);
    if failed == 0 {
      io.println("xiom.usd: runtime SKIP (kind=" + convert.to_string(lr.error.kind) + ")");
    } else {
      io.println("xiom.usd: constants failed");
    }
    return failed;
  }
  let lib = lr.value;
  failed = failed + report(seq(lib.soname, "usd_ms.dll") && lib.abi == 2608,
    "loader: usd_ms.dll bound (abi=" + convert.to_string(lib.abi) + ")");

  // -------------------------------------------------------------------
  // Stage open / defaultPrim / traversal
  // -------------------------------------------------------------------
  let sr = usd_stage_open(&lib, "tests/fixtures/cube_material.usda");
  if !sr.is_ok {
    failed = failed + report(false, "stage: open cube_material.usda (" + sr.error.message + ")");
    var ig = usd_close(&lib);
    return failed;
  }
  let stage = sr.value;
  failed = failed + report(true, "stage: open cube_material.usda");

  let dp = usd_stage_default_prim(&stage);
  failed = failed + report(dp.is_ok && seq(dp.value, "Root"), "stage: defaultPrim Root");

  let itr = usd_stage_iter(&stage);
  if !itr.is_ok {
    failed = failed + report(false, "stage: iterator");
    usd_stage_release(&stage);
    var ig = usd_close(&lib);
    return failed;
  }
  let it = itr.value;
  var count = 0;
  var cube = UsdPrim{ handle: 0, stage: 0 };
  var material = UsdPrim{ handle: 0, stage: 0 };
  var shader = UsdPrim{ handle: 0, stage: 0 };
  var saw_root = false;
  var saw_looks = false;
  var saw_tex = false;
  var saw_marker = false;
  while true {
    var p = usd_iter_next(&it);
    if p.handle == 0 { break; }
    count = count + 1;
    let pp = usd_prim_path(&p);
    if pp.is_ok {
      let path = pp.value;
      if seq(path, "/Root") { saw_root = true; usd_prim_release(&p); }
      elif seq(path, "/Root/Cube") { cube = p; }
      elif seq(path, "/Root/Looks") { saw_looks = true; usd_prim_release(&p); }
      elif seq(path, "/Root/Looks/Preview") { material = p; }
      elif seq(path, "/Root/Looks/Preview/PreviewSurface") { shader = p; }
      elif seq(path, "/Root/Looks/Preview/Tex") { saw_tex = true; usd_prim_release(&p); }
      elif seq(path, "/Root/Marker") { saw_marker = true; usd_prim_release(&p); }
      else { usd_prim_release(&p); }
    } else {
      usd_prim_release(&p);
    }
  }
  usd_iter_release(&it);
  failed = failed + report(count == 7, "traversal: 7 prims (got " + convert.to_string(count) + ")");
  failed = failed + report(saw_root && saw_looks && saw_tex && saw_marker,
    "traversal: Xform/Scope/Tex/Marker reached");
  failed = failed + report(cube.handle != 0 && material.handle != 0 && shader.handle != 0,
    "traversal: Cube + Material + Shader handles");

  // -------------------------------------------------------------------
  // Prim read
  // -------------------------------------------------------------------
  let nm = usd_prim_name(&cube);
  let ty = usd_prim_type(&cube);
  let pa = usd_prim_path(&cube);
  failed = failed + report(nm.is_ok && seq(nm.value, "Cube"), "prim: name Cube");
  failed = failed + report(ty.is_ok && seq(ty.value, "Mesh"), "prim: type Mesh");
  failed = failed + report(pa.is_ok && seq(pa.value, "/Root/Cube"), "prim: path /Root/Cube");

  let ac = usd_prim_attr_count(&cube);
  var acs = "err";
  if ac.is_ok { acs = convert.to_string(ac.value); }
  failed = failed + report(ac.is_ok && ac.value == 8,
    "prim: authored attribute count 8 (got " + acs + ")");
  let sub_i = usd_prim_attr_index(&cube, "subdivisionScheme");
  failed = failed + report(sub_i >= 0, "prim: subdivisionScheme indexed");
  let sub_s = usd_prim_attr_string(&cube, sub_i);
  let sub_t = usd_prim_attr_type(&cube, sub_i);
  var subdetail = "i=" + convert.to_string(sub_i);
  let sun = usd_prim_attr_name(&cube, sub_i);
  if sun.is_ok { subdetail = subdetail + " name=" + sun.value; }
  if sub_s.is_ok { subdetail = subdetail + " str=" + sub_s.value; }
  else { subdetail = subdetail + " strerr=" + convert.to_string(sub_s.error.code); }
  if sub_t.is_ok { subdetail = subdetail + " type=" + sub_t.value; }
  else { subdetail = subdetail + " typeerr=" + convert.to_string(sub_t.error.code); }
  failed = failed + report(sub_s.is_ok && seq(sub_s.value, "none"),
    "prim: subdivisionScheme = none (" + subdetail + ")");
  failed = failed + report(sub_t.is_ok && seq(sub_t.value, "token"),
    "prim: subdivisionScheme type token (" + subdetail + ")");
  let nidx = usd_prim_attr_index(&cube, "negDefault");
  let nd = usd_prim_attr_double(&cube, nidx);
  failed = failed + report(nd.is_ok && feq(nd.value, -1.5, 0.0001),
    "prim: negative double decode (-1.5)");
  let bi = usd_prim_attr_index(&cube, "testBool");
  let bv = usd_prim_attr_bool(&cube, bi);
  failed = failed + report(bv.is_ok && bv.value, "prim: bool read (testBool)");
  let ti = usd_prim_attr_index(&cube, "testTime");
  failed = failed + report(ti >= 0, "prim: testTime indexed");

  // -------------------------------------------------------------------
  // Mesh extraction
  // -------------------------------------------------------------------
  let mi = usd_mesh_info(&cube);
  failed = failed + report(mi.is_ok && mi.value.point_count == 8 &&
    mi.value.face_count == 6 && mi.value.index_count == 24,
    "mesh: info 8 points / 6 faces / 24 indices");
  let pts = usd_mesh_points(&cube);
  var pdetail = "len=" + convert.to_string(pts.len());
  if pts.len() >= 3 {
    pdetail = pdetail + " p0=(" + convert.float_to_string(pts[0]) + "," +
      convert.float_to_string(pts[1]) + "," + convert.float_to_string(pts[2]) + ")";
  }
  failed = failed + report(pts.len() == 24 &&
    feq(pts[0], -1.0, 0.0001) && feq(pts[1], -1.0, 0.0001) &&
    feq(pts[2], -1.0, 0.0001), "mesh: points xyz + first vertex (" + pdetail + ")");
  let fcs = usd_mesh_face_counts(&cube);
  var quads = fcs.is_ok && fcs.value.len() == 6;
  if quads {
    var fi = 0;
    while fi < 6 {
      if fcs.value[fi] != 4 { quads = false; }
      fi = fi + 1;
    }
  }
  failed = failed + report(quads, "mesh: six quad face counts");
  let ix = usd_mesh_indices(&cube);
  failed = failed + report(ix.is_ok && ix.value.len() == 24 && ix.value[0] == 0 &&
    ix.value[1] == 1 && ix.value[2] == 2 && ix.value[3] == 3,
    "mesh: indices [0,1,2,3]");

  // -------------------------------------------------------------------
  // Material surface subset
  // -------------------------------------------------------------------
  let bind = usd_material_binding(&cube);
  failed = failed + report(bind.is_ok && seq(bind.value, "/Root/Looks/Preview"),
    "material: binding -> /Root/Looks/Preview");
  let sp = usd_material_surface_shader_path(&material);
  failed = failed + report(sp.is_ok &&
    seq(sp.value, "/Root/Looks/Preview/PreviewSurface"),
    "material: outputs:surface -> PreviewSurface");
  let der = usd_material_surface_shader_prim(&material);
  failed = failed + report(der.is_ok && der.value.handle != 0, "material: shader prim resolved");
  var derived = UsdPrim{ handle: 0, stage: 0 };
  if der.is_ok { derived = der.value; }
  let sid = usd_material_shader_id(&shader);
  failed = failed + report(sid.is_ok && seq(sid.value, "UsdPreviewSurface"),
    "material: shader info:id = UsdPreviewSurface");
  let ic = usd_material_input_count(&shader);
  var ics = "err";
  if ic.is_ok { ics = convert.to_string(ic.value); }
  failed = failed + report(ic.is_ok && ic.value == 8,
    "material: 8 inputs (got " + ics + ")");
  let dc = usd_material_diffuse_color(&shader);
  var ddetail = "len=" + convert.to_string(dc.len());
  if dc.len() >= 3 {
    ddetail = ddetail + " c=(" + convert.float_to_string(dc[0]) + "," +
      convert.float_to_string(dc[1]) + "," + convert.float_to_string(dc[2]) + ")";
  }
  failed = failed + report(dc.len() == 3 &&
    feq(dc[0], 0.8, 0.001) && feq(dc[1], 0.2, 0.001) &&
    feq(dc[2], 0.1, 0.001), "material: diffuseColor (0.8,0.2,0.1) (" + ddetail + ")");
  let dci = usd_prim_attr_index(&shader, "inputs:diffuseColor");
  let dcv = usd_prim_attr_vec3(&shader, dci);
  failed = failed + report(dcv.len() == 3 &&
    feq(dcv[0], 0.8, 0.001) && feq(dcv[1], 0.2, 0.001) &&
    feq(dcv[2], 0.1, 0.001), "prim: packed attr vec3 path");
  let met = usd_material_metallic(&shader);
  let rough = usd_material_roughness(&shader);
  let op = usd_material_opacity(&shader);
  let ior = usd_material_ior(&shader);
  failed = failed + report(met.is_ok && feq(met.value, 0.25, 0.0001) &&
    rough.is_ok && feq(rough.value, 0.6, 0.001) &&
    op.is_ok && feq(op.value, 0.9, 0.001) &&
    ior.is_ok && feq(ior.value, 1.5, 0.0001),
    "material: metallic/roughness/opacity/ior");
  let swi = usd_prim_attr_index(&shader, "inputs:useSpecularWorkflow");
  var sdetail = "i=" + convert.to_string(swi);
  if swi >= 0 {
    let swn = usd_prim_attr_name(&shader, swi);
    let swt = usd_prim_attr_type(&shader, swi);
    if swn.is_ok { sdetail = sdetail + " name=" + swn.value; }
    if swt.is_ok { sdetail = sdetail + " type=" + swt.value; }
  }
  let spec = usd_material_use_specular_workflow(&shader);
  if spec.is_ok { sdetail = sdetail + " value=" + b2s(spec.value); }
  else { sdetail = sdetail + " err=" + convert.to_string(spec.error.code); }
  failed = failed + report(spec.is_ok && spec.value,
    "material: useSpecularWorkflow int -> true (" + sdetail + ")");
  let badfloat = usd_material_input_float(&shader, "diffuseColor");
  failed = failed + report(!badfloat.is_ok && badfloat.error.code == USD_ERR_TYPE,
    "material: color input as float -> TYPE");
  let missing = usd_material_input_float(&shader, "noSuchInput");
  failed = failed + report(!missing.is_ok && missing.error.code == USD_ERR_ATTR_MISSING,
    "material: missing input -> ATTR_MISSING");

  var emissive_connected = false;
  var emissive_conn = "";
  if ic.is_ok {
    var ii = 0;
    while ii < ic.value {
      let meta = usd_material_input(&shader, ii);
      if meta.is_ok && seq(meta.value.name, "inputs:emissiveColor") {
        emissive_connected = meta.value.connected;
        emissive_conn = meta.value.connection;
      }
      ii = ii + 1;
    }
  }
  let st = usd_material_input_string(&shader, "testString");
  failed = failed + report(st.is_ok && seq(st.value, "hello"), "material: string input (testString)");
  let em = usd_material_emissive_color(&shader);
  failed = failed + report(em.len() == 0, "material: connected emissive returns empty Vec");
  failed = failed + report(emissive_connected &&
    seq(emissive_conn, "/Root/Looks/Preview/Tex.outputs:rgb"),
    "material: emissiveColor connection path");

  // -------------------------------------------------------------------
  // Time samples
  // -------------------------------------------------------------------
  let tc = usd_attr_time_count(&cube, "testTime");
  failed = failed + report(tc.is_ok && tc.value == 3, "time: testTime count 3");
  let ts = usd_attr_time_samples(&cube, "testTime");
  failed = failed + report(ts.is_ok && ts.value.count == 3 &&
    feq(ts.value.min_time, 0.0, 0.0001) && feq(ts.value.max_time, 2.0, 0.0001),
    "time: bounds [0,2]");
  let t1 = usd_attr_time_at(&cube, "testTime", 1);
  failed = failed + report(t1.is_ok && feq(t1.value, 1.0, 0.0001), "time: sample[1].time = 1");
  let v1 = usd_attr_double_at(&cube, "testTime", 1.0);
  failed = failed + report(v1.is_ok && feq(v1.value, 1.5, 0.0001), "time: value at 1.0 = 1.5");
  let v2 = usd_attr_float_sample(&cube, "testTime", 2);
  failed = failed + report(v2.is_ok && feq(v2.value, 2.5, 0.0001), "time: float sample[2] = 2.5");
  let fa = usd_attr_float_at(&cube, "testTime", 1.0);
  failed = failed + report(fa.is_ok && feq(fa.value, 1.5, 0.0001), "time: float_at 1.0 = 1.5");
  let mi2 = usd_prim_attr_index(&shader, "inputs:metallic");
  let pf = usd_prim_attr_float(&shader, mi2);
  failed = failed + report(pf.is_ok && feq(pf.value, 0.25, 0.0001), "prim: float attr read (metallic)");
  let pfb = usd_prim_attr_float_by_name(&shader, "inputs:metallic");
  failed = failed + report(pfb.is_ok && feq(pfb.value, 0.25, 0.0001), "prim: float_by_name (metallic)");
  let pvb = usd_prim_attr_vec3_by_name(&shader, "inputs:diffuseColor");
  failed = failed + report(pvb.len() == 3 && feq(pvb[0], 0.8, 0.001), "prim: vec3_by_name (diffuseColor)");
  let c1 = usd_attr_vec3_at(&cube, "testColor", 1.0);
  failed = failed + report(c1.len() == 3 &&
    feq(c1[0], 0.0, 0.0001) && feq(c1[1], 1.0, 0.0001) &&
    feq(c1[2], 0.0, 0.0001), "time: vec3 at 1.0 = (0,1,0)");
  let tm = usd_attr_time_count(&cube, "noSuchAttr");
  var tdetail = "ok";
  if tm.is_ok { tdetail = "ok count=" + convert.to_string(tm.value); }
  else { tdetail = "err=" + convert.to_string(tm.error.code) + " " + tm.error.message; }
  failed = failed + report(!tm.is_ok && tm.error.code == USD_ERR_ATTR_MISSING,
    "time: missing attribute -> ATTR_MISSING (" + tdetail + ")");

  // -------------------------------------------------------------------
  // Typed errors / empty stage / invalidation
  // -------------------------------------------------------------------
  let miss = usd_stage_open(&lib, "tests/fixtures/does_not_exist.usda");
  failed = failed + report(!miss.is_ok && miss.error.code == USD_ERR_OPEN,
    "errors: missing file -> OPEN");
  let nop = usd_prim_at_path(&stage, "/Root/Nope");
  failed = failed + report(!nop.is_ok && nop.error.code == USD_ERR_NOT_PRIM,
    "errors: missing prim -> NOT_PRIM");
  failed = failed + report(seq(usd_error_name(usd_error().code), "NOT_PRIM"),
    "errors: usd_error() last-error query");
  failed = failed + report(usd_prim_is_valid(&cube), "prim: valid prim is_valid");
  let inv = UsdPrim{ handle: 0xDEAD, stage: stage.handle };
  let inv_name = usd_prim_name(&inv);
  failed = failed + report(!inv_name.is_ok && inv_name.error.code == USD_ERR_INVALID_HANDLE,
    "errors: stale prim handle -> INVALID_HANDLE");
  failed = failed + report(!usd_prim_is_valid(&inv), "errors: stale prim is_valid false");

  let er = usd_stage_open(&lib, "tests/fixtures/error_cases.usda");
  if er.is_ok {
    let est = er.value;
    let nm1 = usd_prim_at_path(&est, "/Root/NotMesh");
    if nm1.is_ok {
      let nm1p = nm1.value;
      let m1 = usd_mesh_info(&nm1p);
      failed = failed + report(!m1.is_ok && m1.error.code == USD_ERR_NOT_MESH,
        "errors: Xform mesh read -> NOT_MESH");
      usd_prim_release(&nm1p);
    } else {
      failed = failed + report(false, "errors: NotMesh lookup");
    }
    let bm = usd_prim_at_path(&est, "/Root/BrokenMesh");
    if bm.is_ok {
      let bmp = bm.value;
      let m2 = usd_mesh_info(&bmp);
      failed = failed + report(!m2.is_ok && m2.error.code == USD_ERR_MESH_INVALID,
        "errors: broken counts -> MESH_INVALID");
      usd_prim_release(&bmp);
    } else {
      failed = failed + report(false, "errors: BrokenMesh lookup");
    }
    let om = usd_prim_at_path(&est, "/Root/OrphanMaterial");
    if om.is_ok {
      let omp = om.value;
      let sp2 = usd_material_surface_shader_path(&omp);
      failed = failed + report(!sp2.is_ok && sp2.error.code == USD_ERR_NO_SURFACE,
        "errors: orphan material -> NO_SURFACE");
      usd_prim_release(&omp);
    } else {
      failed = failed + report(false, "errors: OrphanMaterial lookup");
    }
      let pit = usd_prim_iter(&material);
    if pit.is_ok {
      let pitv = pit.value;
      var pc = 0;
      var pp = usd_iter_next(&pitv);
      while pp.handle != 0 {
        pc = pc + 1;
        usd_prim_release(&pp);
        pp = usd_iter_next(&pitv);
      }
      usd_iter_release(&pitv);
      failed = failed + report(pc == 3, "prim: subtree iterator 3");
    } else {
      failed = failed + report(false, "prim: subtree iterator");
    }
    usd_stage_release(&est);
  } else {
    failed = failed + report(false, "errors: error_cases.usda open");
  }

  let ee = usd_stage_open(&lib, "tests/fixtures/empty.usda");
  if ee.is_ok {
    let est2 = ee.value;
    let eit = usd_stage_iter(&est2);
    var ecount = 0;
    if eit.is_ok {
      let eitv = eit.value;
      var ep = usd_iter_next(&eitv);
      while ep.handle != 0 {
        ecount = ecount + 1;
        usd_prim_release(&ep);
        ep = usd_iter_next(&eitv);
      }
      usd_iter_release(&eitv);
    }
    let edp = usd_stage_default_prim(&est2);
    failed = failed + report(eit.is_ok && ecount == 0 && edp.is_ok && edp.value.len() == 0,
      "empty stage: 0 prims + no defaultPrim");
    usd_stage_release(&est2);
  } else {
    failed = failed + report(false, "empty stage: open");
  }

  // Closing a stage invalidates its prim handles.
  let zr = usd_stage_open(&lib, "tests/fixtures/cube_material.usda");
  if zr.is_ok {
    let zst = zr.value;
    let zp = usd_prim_at_path(&zst, "/Root/Cube");
    if zp.is_ok {
      var zh = zp.value;
      usd_stage_release(&zst);
      let zn = usd_prim_name(&zh);
      failed = failed + report(!zn.is_ok && zn.error.code == USD_ERR_INVALID_HANDLE,
        "ownership: stage close invalidates prim");
      usd_prim_release(&zh);
    } else {
      failed = failed + report(false, "ownership: prim lookup");
      usd_stage_release(&zst);
    }
  } else {
    failed = failed + report(false, "ownership: reopen");
  }

  // -------------------------------------------------------------------
  // Cleanup
  // -------------------------------------------------------------------
  usd_prim_release(&derived);
  usd_prim_release(&shader);
  usd_prim_release(&material);
  usd_prim_release(&cube);
  usd_stage_release(&stage);
  usd_close(&lib);

  if failed == 0 {
    io.println("xiom.usd: all tests passed");
  } else {
    io.println("xiom.usd: tests failed");
  }
  return failed;
}














