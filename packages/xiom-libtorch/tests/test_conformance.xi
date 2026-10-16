// XIOM -- xiom.libtorch conformance suite: pure tier + live libtorch leg.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// CI WITHOUT a runtime stays green: no candidate soname -> SKIP (the SKIP
// path is exercised deterministically every run via a bogus soname). When
// a libtorch build is present the suite proves the declared surface live:
// version probe (TORCH_ABI_VERSION decode), the C++ CUDA anchors, tensor
// creation/zeros/ones/from_data/clone/copy/reshape/narrow, metadata
// (numel/dim/size/shape/strides/contiguity/dtype/device/storage offset),
// scalar item + scalar tensor, element-wise add/mul/scale, 2-D matmul
// with exact arithmetic, relu + softmax through the boxed dispatcher
// (including the verified input-handle-preservation semantics), grad-mode
// toggle, one SGD step (functional update), and typed error paths (absent
// runtime, shape mismatch, non-contiguous to_vec, dispatcher failure).
//
// Build+run (pure-XIOM loader; no compiler args):
//   scripts/port.ps1 -Package xiom.libtorch -TimeoutSec 300
// The live leg uses the loader candidate order: `XIOM_LIBTORCH_RUNTIME`
// (an explicit path to a build, e.g. the pinned E:\repos\libtorch-bin
// extraction) then the bare Windows/Linux/macOS sonames. The libtorch
// dependencies (c10.dll, uv.dll, libiomp5md.dll) must be resolvable, so
// put the build's lib directory on PATH for the live run. Without a
// runtime the suite reports SKIP and stays green.
//
// Bindings discipline notes (compiler findings, see AUDIT.md):
//   * `Result[Vec[Float32], _].value[i]` read INLINE miscompiles on the
//     pin; every payload is bound to a local before indexing here.
//   * the AOTI boxed dispatcher consumes its input handles; the wrapper
//     clones first, and this suite proves the caller handle stays valid.

module libtorch_conformance

use xiom.libtorch;
use xiom.libtorch.loader;
use xiom.io;

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

fn why(msg: Str) {
  io.println("    detail: " + msg);
  io.flush_stdout();
}

fn ist(i: Int) -> Str {
  return loader.int_to_str(i);
}

fn bstr(b: Bool) -> Str {
  if b { return "true"; }
  return "false";
}

/// Substring test (byte scan; avoids extra stdlib coupling).
fn contains(hay: Str, needle: Str) -> Bool
  requires: needle.len() > 0
{
  if needle.len() > hay.len() { return false; }
  var i = 0;
  while i + needle.len() <= hay.len() {
    var j = 0;
    var hit = true;
    while j < needle.len() {
      if hay.byte_at(i + j) != needle.byte_at(j) { hit = false; j = needle.len(); }
      else { j = j + 1; }
    };
    if hit { return true; }
    i = i + 1;
  };
  return false;
}

fn finish(failed: Int) -> Int {
  if failed == 0 {
    io.println("xiom.libtorch: all tests passed");
  } else {
    io.println("xiom.libtorch: tests failed");
  }
  return failed;
}

fn shape1(a: Int) -> Vec[Int] {
  var v: Vec[Int] = Vec[Int].new();
  v.push(a);
  return v;
}

fn shape2(a: Int, b: Int) -> Vec[Int] {
  var v: Vec[Int] = Vec[Int].new();
  v.push(a);
  v.push(b);
  return v;
}

fn vec2(a: Float32, b: Float32) -> Vec[Float32] {
  var v: Vec[Float32] = Vec[Float32].new();
  v.push(a);
  v.push(b);
  return v;
}

fn vec4(a: Float32, b: Float32, c: Float32, d: Float32) -> Vec[Float32] {
  var v: Vec[Float32] = Vec[Float32].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  return v;
}

/// Float32 equality over an owned copy (self-documenting call-site shape
/// for the payload-copy discipline).
fn eq_at(v: &Vec[Float32], i: Int, e: Float32) -> Bool
  requires: i >= 0
  requires: i < v.len()
{
  let x = v[i];
  return x == e;
}

fn all_eq(v: &Vec[Float32], e: Float32) -> Bool {
  var i = 0;
  while i < v.len() {
    let x = v[i];
    if x != e { return false; }
    i = i + 1;
  };
  return true;
}

fn vec_exact(v: &Vec[Float32], a: Float32, b: Float32) -> Bool
  requires: v.len() == 2
{
  return eq_at(v, 0, a) && eq_at(v, 1, b);
}

// =========================================================================
// Pure tier (no runtime needed)
// =========================================================================

fn test_pure() -> Int {
  var failed = 0;

  var kinds_ok = true;
  if loader.LT_LOAD_ABSENT != 0 { kinds_ok = false; }
  if loader.LT_LOAD_ABI != 1 { kinds_ok = false; }
  if loader.LT_CALL_FAILED != 2 { kinds_ok = false; }
  if loader.LT_UNAVAILABLE != 3 { kinds_ok = false; }
  failed = failed + report(kinds_ok, "loader: classification kinds (ABSENT/ABI/CALL_FAILED/UNAVAILABLE)");

  // Declared C surface: 38 names, index-checked at the ends + spot checks.
  let slots = loader.lt_surface_names();
  var surf_ok = slots.len() == 38;
  if slots[0] != "aoti_torch_abi_version" { surf_ok = false; }
  if slots[37] != "aoti_torch_grad_mode_set_enabled" { surf_ok = false; }
  if slots[6] != "aoti_torch_empty_strided" { surf_ok = false; }
  if slots[35] != "aoti_torch_call_dispatcher" { surf_ok = false; }
  failed = failed + report(surf_ok, "loader: declared C surface 38 entry points aligned");

  let anchors = loader.lt_anchor_names();
  var anch_ok = anchors.len() == 3;
  if anchors[0] != "?is_available@cuda@torch@@YA_NXZ" { anch_ok = false; }
  if anchors[1] != "?device_count@cuda@torch@@YACXZ" { anch_ok = false; }
  if !contains(anchors[2], "load@jit@torch") { anch_ok = false; }
  failed = failed + report(anch_ok, "loader: declared C++ anchors (cuda is_available/device_count + jit load)");

  // Candidate order: the Windows trio + Linux/macOS sonames follow the
  // optional env override.
  let cands = torch_load_candidates();
  var has_override = false;
  let ov = io.env_var("XIOM_LIBTORCH_RUNTIME");
  if ov.is_some {
    if ov.value.len() > 0 { has_override = true; }
  }
  var base = 0;
  if has_override { base = 1; }
  var cand_ok = cands.len() == base + 10;
  if cands.len() == base + 10 {
    if cands[base + 0] != "torch_cpu.dll" { cand_ok = false; }
    if cands[base + 1] != "libtorch_cpu.dll" { cand_ok = false; }
    if cands[base + 2] != "libtorch.dll" { cand_ok = false; }
    if cands[base + 3] != "torch.dll" { cand_ok = false; }
    if cands[base + 4] != "libtorch_cpu.so" { cand_ok = false; }
    if cands[base + 5] != "libtorch.so" { cand_ok = false; }
    if cands[base + 6] != "libtorch_cpu.so.2" { cand_ok = false; }
    if cands[base + 7] != "libtorch.so.2" { cand_ok = false; }
    if cands[base + 8] != "libtorch_cpu.dylib" { cand_ok = false; }
    if cands[base + 9] != "libtorch.dylib" { cand_ok = false; }
  } else {
    why("candidates=" + ist(cands.len()) + " expected=" + ist(base + 10));
  }
  failed = failed + report(cand_ok, "loader: candidate order (XIOM_LIBTORCH_RUNTIME override, then 10 sonames)");

  // Deterministic SKIP-path classification (every host, every run).
  let missing = torch_load_named("xiom-absent-libtorch-probe-xyz.dll");
  if missing.is_ok {
    failed = failed + report(false, "skip-path: bogus soname unexpectedly loaded");
  } else {
    failed = failed + report(missing.error.kind == loader.LT_LOAD_ABSENT && missing.error.message.len() > 0,
      "skip-path: absent runtime classified LT_LOAD_ABSENT (SKIP)");
  }

  // IEEE-754 binary32 -> Float64 reconstruction (exact for these values).
  var fb_ok = true;
  if loader.lt_f32_from_bits(0x3F800000) != 1.0 { fb_ok = false; }
  if loader.lt_f32_from_bits(0x40000000) != 2.0 { fb_ok = false; }
  if loader.lt_f32_from_bits(0xC0000000) != -2.0 { fb_ok = false; }
  if loader.lt_f32_from_bits(0x3F000000) != 0.5 { fb_ok = false; }
  if loader.lt_f32_from_bits(0x40400000) != 3.0 { fb_ok = false; }
  if loader.lt_f32_from_bits(0xBF400000) != -0.75 { fb_ok = false; }
  if loader.lt_f32_from_bits(0x00000000) != 0.0 { fb_ok = false; }
  failed = failed + report(fb_ok, "loader: f32_from_bits exact (1.0/2.0/-2.0/0.5/3.0/-0.75/0.0)");

  var its_ok = true;
  if loader.int_to_str(0) != "0" { its_ok = false; }
  if loader.int_to_str(7) != "7" { its_ok = false; }
  if loader.int_to_str(123) != "123" { its_ok = false; }
  if loader.int_to_str(-4) != "-4" { its_ok = false; }
  failed = failed + report(its_ok, "loader: int_to_str edge cases");

  return failed;
}

// =========================================================================
// Live leg (SKIP when no runtime)
// =========================================================================

fn test_live() -> Int {
  var failed = 0;
  let lr = torch_load();
  if !lr.is_ok {
    if lr.error.kind == loader.LT_LOAD_ABSENT {
      return report(true, "live: SKIP -- no libtorch candidate present (" + lr.error.message + ")");
    }
    return report(false, "live: runtime present but unusable -- " + lr.error.message);
  }
  let lib: LtLibrary = lr.value;

  // Version + surface probe.
  let info = torch_probe(&lib);
  var probe_ok = info.soname.len() > 0 && info.major >= 2;
  if info.resolved != 38 || info.required != 38 { probe_ok = false; }
  if info.anchors_resolved != 3 || info.anchors_required != 3 { probe_ok = false; }
  let expect_abi = (info.major << 56) | (info.minor << 48) | (info.patch << 40);
  if torch_abi_version(&lib) != expect_abi { probe_ok = false; }
  failed = failed + report(probe_ok,
    "live: " + info.soname + " " + ist(info.major) + "." + ist(info.minor) + "." + ist(info.patch) +
    " (surface " + ist(info.resolved) + "/" + ist(info.required) +
    " + anchors " + ist(info.anchors_resolved) + "/" + ist(info.anchors_required) + ")");

  // C++ CUDA anchors (trivial-ABI calls; the pinned CPU build -> false/0).
  let av = torch_cuda_is_available(&lib);
  let dc = torch_cuda_device_count(&lib);
  var cuda_ok = av.is_ok && dc.is_ok;
  if av.is_ok && dc.is_ok {
    if av.value && dc.value < 1 { cuda_ok = false; }
  }
  var av_s = -1;
  if av.is_ok {
    if av.value { av_s = 1; } else { av_s = 0; }
  }
  var dc_s = -1;
  if dc.is_ok { dc_s = dc.value; }
  failed = failed + report(cuda_ok,
    "live: cuda anchors callable (is_available=" + ist(av_s) + ", device_count=" + ist(dc_s) + ")");

  // Runtime constants.
  let d_f32 = torch_dtype_float32(&lib);
  let d_cpu = torch_device_type_cpu(&lib);
  let d_cuda = torch_device_type_cuda(&lib);
  var const_ok = d_f32.is_ok && d_cpu.is_ok && d_cuda.is_ok;
  var dtype_code = 0;
  var cpu_code = 0;
  if const_ok {
    dtype_code = d_f32.value;
    cpu_code = d_cpu.value;
    if d_cuda.value == d_cpu.value { const_ok = false; }
    let sz = torch_dtype_size(&lib, dtype_code);
    if !sz.is_ok || sz.value != 4 { const_ok = false; }
  }
  failed = failed + report(const_ok,
    "live: runtime constants (float32 dtype=" + ist(dtype_code) + " element_size=4, cpu/cuda device codes distinct)");

  // [2,3] tensor: creation + full metadata (CPU tensors report device
  // index -1 per c10::Device).
  let sh23 = shape2(2, 3);
  let t_r = torch_tensor_new(&lib, &sh23);
  if !t_r.is_ok {
    why(t_r.error.message);
    let crc = torch_close(&lib);
    return failed + report(false, "live: torch_tensor_new failed");
  }
  let t = t_r.value;
  let numel = torch_tensor_numel(&lib, t);
  let dim = torch_tensor_dim(&lib, t);
  let sz0 = torch_tensor_size(&lib, t, 0);
  let sz1 = torch_tensor_size(&lib, t, 1);
  let str0 = torch_tensor_stride(&lib, t, 0);
  let str1 = torch_tensor_stride(&lib, t, 1);
  let shp = torch_tensor_shape(&lib, t);
  let sd = torch_tensor_strides(&lib, t);
  let cont = torch_tensor_is_contiguous(&lib, t);
  let dfl = torch_tensor_is_defined(&lib, t);
  let dty = torch_tensor_dtype(&lib, t);
  let devt = torch_tensor_device_type(&lib, t);
  let devi = torch_tensor_device_index(&lib, t);
  let soff = torch_tensor_storage_offset(&lib, t);
  var meta_ok = numel.is_ok && numel.value == 6;
  if dim.is_ok && dim.value != 2 { meta_ok = false; }
  if sz0.is_ok && sz0.value != 2 { meta_ok = false; }
  if sz1.is_ok && sz1.value != 3 { meta_ok = false; }
  if str0.is_ok && str0.value != 3 { meta_ok = false; }
  if str1.is_ok && str1.value != 1 { meta_ok = false; }
  if shp.is_ok {
    let pv = shp.value;
    if pv.len() != 2 { meta_ok = false; }
    elif pv[0] != 2 || pv[1] != 3 { meta_ok = false; }
  }
  if sd.is_ok {
    let sv = sd.value;
    if sv.len() != 2 { meta_ok = false; }
    elif sv[0] != 3 || sv[1] != 1 { meta_ok = false; }
  }
  if cont.is_ok && !cont.value { meta_ok = false; }
  if dfl.is_ok && !dfl.value { meta_ok = false; }
  if dty.is_ok && dty.value != dtype_code { meta_ok = false; }
  if devt.is_ok && devt.value != cpu_code { meta_ok = false; }
  if devi.is_ok && devi.value != -1 { meta_ok = false; }
  if soff.is_ok && soff.value != 0 { meta_ok = false; }
  if !meta_ok {
    why("numel=" + ist(numel.value) + " dim=" + ist(dim.value) + " size0=" + ist(sz0.value) + " size1=" + ist(sz1.value));
    why("stride0=" + ist(str0.value) + " stride1=" + ist(str1.value) + " dtype=" + ist(dty.value) + " expect " + ist(dtype_code));
    why("dev_type=" + ist(devt.value) + " expect " + ist(cpu_code) + " dev_index=" + ist(devi.value) + " expect -1");
    why("contiguous=" + bstr(cont.value) + " defined=" + bstr(dfl.value) + " storage_offset=" + ist(soff.value));
  }
  failed = failed + report(meta_ok, "live: [2,3] metadata (numel 6, dim 2, sizes 2/3, strides 3/1, contiguous, defined, float32, cpu, index -1)");

  // zeros / ones (zero_ + fill entry points).
  let z_r = torch_tensor_zeros(&lib, &sh23);
  var z_ok = false;
  if z_r.is_ok {
    let zv = torch_tensor_to_vec(&lib, z_r.value);
    if zv.is_ok {
      let zvv = zv.value;
      z_ok = zvv.len() == 6 && all_eq(&zvv, 0.0);
    } else { why(zv.error.message); }
    let ig = torch_tensor_free(&lib, z_r.value);
  } else { why(z_r.error.message); }
  failed = failed + report(z_ok, "live: zeros [2,3] reads back all 0.0 through zero_");

  let o_r = torch_tensor_ones(&lib, &sh23);
  var o_ok = false;
  if o_r.is_ok {
    let ov2 = torch_tensor_to_vec(&lib, o_r.value);
    if ov2.is_ok {
      let ov2v = ov2.value;
      o_ok = ov2v.len() == 6 && all_eq(&ov2v, 1.0);
    } else { why(ov2.error.message); }
    let ig = torch_tensor_free(&lib, o_r.value);
  } else { why(o_r.error.message); }
  failed = failed + report(o_ok, "live: ones [2,3] reads back all 1.0 through aten fill");

  // from_data copy + alias proof.
  var src = vec4(1.0, 2.0, 3.0, 4.0);
  let sh22 = shape2(2, 2);
  let fd_r = torch_tensor_from_data(&lib, &src, &sh22);
  var fd_ok = false;
  if fd_r.is_ok {
    let fdv = torch_tensor_to_vec(&lib, fd_r.value);
    var exact = false;
    if fdv.is_ok {
      let fvv = fdv.value;
      exact = fvv.len() == 4 && eq_at(&fvv, 0, 1.0) && eq_at(&fvv, 1, 2.0) && eq_at(&fvv, 2, 3.0) && eq_at(&fvv, 3, 4.0);
    } else { why(fdv.error.message); }
    src[0] = 99.0;
    var independent = false;
    if exact {
      let fdv2 = torch_tensor_to_vec(&lib, fd_r.value);
      if fdv2.is_ok {
        let f2v = fdv2.value;
        independent = f2v.len() == 4 && eq_at(&f2v, 0, 1.0);
      }
    }
    fd_ok = exact && independent;
    let ig = torch_tensor_free(&lib, fd_r.value);
  } else { why(fd_r.error.message); }
  failed = failed + report(fd_ok, "live: from_data [2,2] copies (1,2,3,4) and never aliases the XIOM buffer");

  // Scalar round trip: scalar_to_tensor -> item_float32.
  let sc_r = torch_tensor_scalar(&lib, 2.5);
  var sc_ok = false;
  if sc_r.is_ok {
    let iv = torch_tensor_item_float32(&lib, sc_r.value);
    let nv = torch_tensor_numel(&lib, sc_r.value);
    sc_ok = iv.is_ok && iv.value == 2.5 && nv.is_ok && nv.value == 1;
    if !sc_ok && !iv.is_ok { why(iv.error.message); }
    let ig = torch_tensor_free(&lib, sc_r.value);
  } else { why(sc_r.error.message); }
  failed = failed + report(sc_ok, "live: scalar_to_tensor(2.5) -> item_float32 == 2.5 (numel 1)");

  // Clone independence: mutate the original after cloning.
  let a42 = vec4(1.0, 2.0, 3.0, 4.0);
  let orig_r = torch_tensor_from_data(&lib, &a42, &sh22);
  var cl_ok = false;
  if orig_r.is_ok {
    let cl_r = torch_tensor_clone(&lib, orig_r.value);
    if cl_r.is_ok {
      let f0 = torch_tensor_fill(&lib, orig_r.value, 9.0);
      let clv = torch_tensor_to_vec(&lib, cl_r.value);
      if f0.is_ok && clv.is_ok {
        let clvv = clv.value;
        cl_ok = clvv.len() == 4 && eq_at(&clvv, 0, 1.0) && eq_at(&clvv, 3, 4.0);
      } else if !clv.is_ok { why(clv.error.message); }
      let ig1 = torch_tensor_free(&lib, cl_r.value);
    } else { why(cl_r.error.message); }
    let ig2 = torch_tensor_free(&lib, orig_r.value);
  } else { why(orig_r.error.message); }
  failed = failed + report(cl_ok, "live: clone is independent (original filled 9.0, clone keeps 1..4)");

  // copy_into: dst receives the source contents.
  let a23 = vec4(5.0, 6.0, 7.0, 8.0);
  let s_r = torch_tensor_from_data(&lib, &a23, &sh22);
  let d_r = torch_tensor_zeros(&lib, &sh22);
  var cp_ok = false;
  if s_r.is_ok && d_r.is_ok {
    let cp = torch_tensor_copy_into(&lib, d_r.value, s_r.value);
    let dv = torch_tensor_to_vec(&lib, d_r.value);
    if cp.is_ok && dv.is_ok {
      let dvv = dv.value;
      cp_ok = dvv.len() == 4 && eq_at(&dvv, 0, 5.0) && eq_at(&dvv, 3, 8.0);
    } else if !cp.is_ok { why(cp.error.message); }
  } else {
    if !s_r.is_ok { why(s_r.error.message); }
    if !d_r.is_ok { why(d_r.error.message); }
  }
  if s_r.is_ok { let ig = torch_tensor_free(&lib, s_r.value); }
  if d_r.is_ok { let ig = torch_tensor_free(&lib, d_r.value); }
  failed = failed + report(cp_ok, "live: copy_into fills a zeros tensor with (5,6,7,8)");

  // Element-wise ops: add / mul / scale.
  let va = vec2(1.0, 2.0);
  let vb = vec2(3.0, 4.0);
  let sh2a = shape1(2);
  let ta_r = torch_tensor_from_data(&lib, &va, &sh2a);
  let sh2b = shape1(2);
  let tb_r = torch_tensor_from_data(&lib, &vb, &sh2b);
  var add_ok = false;
  var mul_ok = false;
  var scale_ok = false;
  if ta_r.is_ok && tb_r.is_ok {
    let add_r = torch_tensor_add(&lib, ta_r.value, tb_r.value);
    if add_r.is_ok {
      let av2 = torch_tensor_to_vec(&lib, add_r.value);
      if av2.is_ok {
        let av2v = av2.value;
        add_ok = vec_exact(&av2v, 4.0, 6.0);
      } else { why(av2.error.message); }
      let ig = torch_tensor_free(&lib, add_r.value);
    } else { why(add_r.error.message); }
    let mul_r = torch_tensor_mul(&lib, ta_r.value, tb_r.value);
    if mul_r.is_ok {
      let mv = torch_tensor_to_vec(&lib, mul_r.value);
      if mv.is_ok {
        let mvv = mv.value;
        mul_ok = vec_exact(&mvv, 3.0, 8.0);
      } else { why(mv.error.message); }
      let ig = torch_tensor_free(&lib, mul_r.value);
    } else { why(mul_r.error.message); }
    let sc2_r = torch_tensor_scale(&lib, ta_r.value, 2.5);
    if sc2_r.is_ok {
      let sv = torch_tensor_to_vec(&lib, sc2_r.value);
      if sv.is_ok {
        let svv = sv.value;
        scale_ok = vec_exact(&svv, 2.5, 5.0);
      } else { why(sv.error.message); }
      let ig = torch_tensor_free(&lib, sc2_r.value);
    } else { why(sc2_r.error.message); }
  } else {
    if !ta_r.is_ok { why(ta_r.error.message); }
    if !tb_r.is_ok { why(tb_r.error.message); }
  }
  failed = failed + report(add_ok, "live: add (1,2)+(3,4) = (4,6) exact");
  failed = failed + report(mul_ok, "live: mul (1,2)*(3,4) = (3,8) exact");
  failed = failed + report(scale_ok, "live: scale (1,2)*2.5 = (2.5,5.0) exact");
  if ta_r.is_ok { let ig = torch_tensor_free(&lib, ta_r.value); }
  if tb_r.is_ok { let ig = torch_tensor_free(&lib, tb_r.value); }

  // 2-D matmul with exact arithmetic + mismatch typed error.
  let aM = vec4(1.0, 2.0, 3.0, 4.0);
  let bM = vec4(5.0, 6.0, 7.0, 8.0);
  let m1_r = torch_tensor_from_data(&lib, &aM, &sh22);
  let m2_r = torch_tensor_from_data(&lib, &bM, &sh22);
  var mm_ok = false;
  if m1_r.is_ok && m2_r.is_ok {
    let mm_r = torch_tensor_matmul(&lib, m1_r.value, m2_r.value);
    if mm_r.is_ok {
      let mv = torch_tensor_to_vec(&lib, mm_r.value);
      if mv.is_ok {
        let mvv = mv.value;
        mm_ok = mvv.len() == 4 && eq_at(&mvv, 0, 19.0) && eq_at(&mvv, 1, 22.0) && eq_at(&mvv, 2, 43.0) && eq_at(&mvv, 3, 50.0);
      } else { why(mv.error.message); }
      let ig = torch_tensor_free(&lib, mm_r.value);
    } else { why(mm_r.error.message); }
  } else {
    if !m1_r.is_ok { why(m1_r.error.message); }
    if !m2_r.is_ok { why(m2_r.error.message); }
  }
  failed = failed + report(mm_ok, "live: matmul [[1,2],[3,4]]@[[5,6],[7,8]] = [[19,22],[43,50]] exact");
  if m1_r.is_ok { let ig = torch_tensor_free(&lib, m1_r.value); }
  if m2_r.is_ok { let ig = torch_tensor_free(&lib, m2_r.value); }
  // Inner-dimension / rank mismatch with real handles -> typed error before
  // any C++ call.
  let b22_mm = vec4(1.0, 2.0, 3.0, 4.0);
  let a44_mm = vec4(1.0, 2.0, 3.0, 4.0);
  let mm2 = torch_tensor_from_data(&lib, &b22_mm, &sh22);
  let sh4m = shape1(4);
  let mm3 = torch_tensor_from_data(&lib, &a44_mm, &sh4m);
  var mm_bad_ok = false;
  if mm2.is_ok && mm3.is_ok {
    let mm_bad = torch_tensor_matmul(&lib, mm2.value, mm3.value);
    mm_bad_ok = mm_bad.is_err && mm_bad.error.kind == loader.LT_UNAVAILABLE;
  }
  if mm2.is_ok { let ig = torch_tensor_free(&lib, mm2.value); }
  if mm3.is_ok { let ig = torch_tensor_free(&lib, mm3.value); }
  failed = failed + report(mm_bad_ok, "live: matmul [2,2]@[4] -> typed error (rank check, no C++ call)");

  // reshape (view) + typed mismatch.
  let rs_a = vec4(1.0, 2.0, 3.0, 4.0);
  let r1 = torch_tensor_from_data(&lib, &rs_a, &sh22);
  let sh41 = shape2(4, 1);
  var rs_ok = false;
  if r1.is_ok {
    let rr = torch_tensor_reshape(&lib, r1.value, &sh41);
    if rr.is_ok {
      let rs2 = torch_tensor_shape(&lib, rr.value);
      let rn = torch_tensor_numel(&lib, rr.value);
      rs_ok = rs2.is_ok && rn.is_ok && rn.value == 4;
      if rs_ok {
        let rs2v = rs2.value;
        if rs2v.len() != 2 || rs2v[0] != 4 || rs2v[1] != 1 { rs_ok = false; }
      }
      let ig = torch_tensor_free(&lib, rr.value);
    } else { why(rr.error.message); }
    let ig = torch_tensor_free(&lib, r1.value);
  } else { why(r1.error.message); }
  failed = failed + report(rs_ok, "live: reshape [2,2] -> [4,1] (numel preserved, view handle)");
  let r_bad_src = vec4(1.0, 2.0, 3.0, 4.0);
  let r_bad_t = torch_tensor_from_data(&lib, &r_bad_src, &sh22);
  var r_bad_ok = false;
  if r_bad_t.is_ok {
    let sh5r = shape1(5);
    let r_bad = torch_tensor_reshape(&lib, r_bad_t.value, &sh5r);
    r_bad_ok = r_bad.is_err && r_bad.error.kind == loader.LT_CALL_FAILED;
    let ig = torch_tensor_free(&lib, r_bad_t.value);
  }
  failed = failed + report(r_bad_ok, "live: reshape element-count mismatch -> typed error");

  // narrow: slice [4] -> [2,3]; the view starts at storage offset 1.
  let nv_src = vec4(10.0, 20.0, 30.0, 40.0);
  let sh4n = shape1(4);
  let n1 = torch_tensor_from_data(&lib, &nv_src, &sh4n);
  var nw_ok = false;
  if n1.is_ok {
    let nr = torch_tensor_narrow(&lib, n1.value, 0, 1, 2);
    if nr.is_ok {
      let nvv = torch_tensor_to_vec(&lib, nr.value);
      let nnum = torch_tensor_numel(&lib, nr.value);
      let nsoff = torch_tensor_storage_offset(&lib, nr.value);
      if nvv.is_ok {
        let nvvv = nvv.value;
        nw_ok = nvvv.len() == 2 && eq_at(&nvvv, 0, 20.0) && eq_at(&nvvv, 1, 30.0) && nnum.is_ok && nnum.value == 2;
        if nsoff.is_ok && nsoff.value != 1 { nw_ok = false; }
      } else { why(nvv.error.message); }
      let ig = torch_tensor_free(&lib, nr.value);
    } else { why(nr.error.message); }
    let ig = torch_tensor_free(&lib, n1.value);
  } else { why(n1.error.message); }
  failed = failed + report(nw_ok, "live: narrow [4]@[1,3) reads (20,30), storage_offset 1");

  // Non-contiguous view -> to_vec typed error (dim-1 narrow of [2,3]).
  var nc6: Vec[Float32] = Vec[Float32].new();
  nc6.push(1.0); nc6.push(2.0); nc6.push(3.0);
  nc6.push(4.0); nc6.push(5.0); nc6.push(6.0);
  let nc1 = torch_tensor_from_data(&lib, &nc6, &sh23);
  var nc_ok = false;
  if nc1.is_ok {
    let nr2 = torch_tensor_narrow(&lib, nc1.value, 1, 0, 2);
    if nr2.is_ok {
      let c2 = torch_tensor_is_contiguous(&lib, nr2.value);
      let tv = torch_tensor_to_vec(&lib, nr2.value);
      nc_ok = c2.is_ok && !c2.value && tv.is_err;
      let ig = torch_tensor_free(&lib, nr2.value);
    } else { why(nr2.error.message); }
    let ig = torch_tensor_free(&lib, nc1.value);
  } else { why(nc1.error.message); }
  failed = failed + report(nc_ok, "live: dim-1 narrow is non-contiguous; to_vec -> typed error");

  // relu + softmax through the boxed dispatcher; the input handles must
  // survive the call (dispatcher-consumes-clone semantics).
  var rl_src: Vec[Float32] = Vec[Float32].new();
  rl_src.push(-1.0); rl_src.push(2.0);
  let sh2rl = shape1(2);
  let rl1 = torch_tensor_from_data(&lib, &rl_src, &sh2rl);
  var rl_ok = false;
  if rl1.is_ok {
    let rr = torch_tensor_relu(&lib, rl1.value);
    if rr.is_ok {
      let rv = torch_tensor_to_vec(&lib, rr.value);
      if rv.is_ok {
        let rvv = rv.value;
        rl_ok = vec_exact(&rvv, 0.0, 2.0);
      } else { why(rv.error.message); }
      let ig = torch_tensor_free(&lib, rr.value);
      // Input handle still valid: read it back after the dispatch.
      if rl_ok {
        let back = torch_tensor_to_vec(&lib, rl1.value);
        if back.is_ok {
          let bv = back.value;
          rl_ok = vec_exact(&bv, -1.0, 2.0);
        } else { rl_ok = false; }
      }
    } else { why(rr.error.message); }
    let ig = torch_tensor_free(&lib, rl1.value);
  } else { why(rl1.error.message); }
  failed = failed + report(rl_ok, "live: dispatcher aten::relu (-1,2) -> (0,2); input handle preserved");

  let sm_src = vec2(0.0, 0.0);
  let sh2sm = shape1(2);
  let sm1 = torch_tensor_from_data(&lib, &sm_src, &sh2sm);
  var sm_ok = false;
  if sm1.is_ok {
    let sr = torch_tensor_softmax(&lib, sm1.value, 0);
    if sr.is_ok {
      let sv2 = torch_tensor_to_vec(&lib, sr.value);
      if sv2.is_ok {
        let sv2v = sv2.value;
        sm_ok = vec_exact(&sv2v, 0.5, 0.5);
      } else { why(sv2.error.message); }
      let ig = torch_tensor_free(&lib, sr.value);
    } else { why(sr.error.message); }
    let ig = torch_tensor_free(&lib, sm1.value);
  } else { why(sm1.error.message); }
  failed = failed + report(sm_ok, "live: dispatcher aten::softmax ([0,0], dim 0) -> (0.5,0.5)");

  // Dispatcher failure path: out-of-range softmax dim -> typed CALL_FAILED.
  let sc3 = torch_tensor_scalar(&lib, 1.0);
  var disp_err_ok = false;
  if sc3.is_ok {
    let bad = torch_tensor_softmax(&lib, sc3.value, 5);
    disp_err_ok = bad.is_err && bad.error.kind == loader.LT_CALL_FAILED;
    let ig = torch_tensor_free(&lib, sc3.value);
  }
  failed = failed + report(disp_err_ok, "live: dispatcher failure (softmax dim 5) -> typed LT_CALL_FAILED");

  // SGD step: param [1,2], grad [0.5,1], lr 0.25 -> [0.875, 1.75] exact;
  // the source parameter handle is not mutated.
  let p_src = vec2(1.0, 2.0);
  let g_src = vec2(0.5, 1.0);
  let sh2p = shape1(2);
  let p1 = torch_tensor_from_data(&lib, &p_src, &sh2p);
  let sh2g = shape1(2);
  let g1 = torch_tensor_from_data(&lib, &g_src, &sh2g);
  var sgd_ok = false;
  if p1.is_ok && g1.is_ok {
    let upd = torch_sgd_step(&lib, p1.value, g1.value, 0.25);
    if upd.is_ok {
      let uv = torch_tensor_to_vec(&lib, upd.value);
      if uv.is_ok {
        let uvv = uv.value;
        sgd_ok = vec_exact(&uvv, 0.875, 1.75);
        let pv = torch_tensor_to_vec(&lib, p1.value);
        if !pv.is_ok { sgd_ok = false; }
        else {
          let pvv = pv.value;
          if !eq_at(&pvv, 0, 1.0) { sgd_ok = false; }
        }
      } else { why(uv.error.message); }
      let ig = torch_tensor_free(&lib, upd.value);
    } else { why(upd.error.message); }
  } else {
    if !p1.is_ok { why(p1.error.message); }
    if !g1.is_ok { why(g1.error.message); }
  }
  failed = failed + report(sgd_ok, "live: sgd_step [1,2] - 0.25*(0.5,1) = [0.875,1.75] exact; source untouched");
  if p1.is_ok { let ig = torch_tensor_free(&lib, p1.value); }
  if g1.is_ok { let ig = torch_tensor_free(&lib, g1.value); }

  // Grad mode round trip.
  var grad_ok = false;
  let gm0 = torch_grad_mode_enabled(&lib);
  if gm0.is_ok {
    let s1 = torch_set_grad_mode(&lib, false);
    let gm1 = torch_grad_mode_enabled(&lib);
    let s2 = torch_set_grad_mode(&lib, true);
    let gm2 = torch_grad_mode_enabled(&lib);
    grad_ok = gm0.value && s1.is_ok && gm1.is_ok && !gm1.value && s2.is_ok && gm2.is_ok && gm2.value;
  } else { why(gm0.error.message); }
  failed = failed + report(grad_ok, "live: grad mode enabled -> disabled -> enabled round trip");

  // JIT anchor presence (declared C++ tier; call deferred to ROADMAP P2).
  failed = failed + report(torch_jit_anchor_present(&lib), "live: torch::jit::load anchor resolved");

  let ig = torch_tensor_free(&lib, t);

  let cr = torch_close(&lib);
  failed = failed + report(cr.is_ok, "live: runtime handle released");

  return failed;
}

// =========================================================================
// Driver
// =========================================================================

pub fn main() -> Int {
  io.println("=== xiom.libtorch conformance tests (libtorch AOTI C ABI + C++ anchors loader) ===");
  io.flush_stdout();
  var failed: Int = 0;
  failed = failed + test_pure();
  failed = failed + test_live();
  return finish(failed);
}
