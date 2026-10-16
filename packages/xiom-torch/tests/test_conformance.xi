// XIOM -- xiom.torch conformance suite: pure tensor/NN tier + live
// libtorch runtime leg.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// The pure tier needs NO runtime: tensor constructors (+ real values),
// shape/strides semantics, typed reshape errors, NN constructors, and a
// real linear forward with exact hand-computed results.  The runtime tier
// skips typed when no libtorch build is present (the SKIP path is
// exercised deterministically via a bogus soname), and proves the
// multi-soname load, the ABI probe, the CUDA anchor, and an exact
// upload -> download round trip when one is.
//
// Build+run (pure-XIOM loader; no compiler args):
//   scripts/port.ps1 -Package xiom.torch -TimeoutSec 300
// Live leg: `XIOM_LIBTORCH_RUNTIME` (explicit build path) or a bare
// soname; put the build's lib directory on PATH for its dependencies.
//
// Bindings discipline: payloads of Result values are bound to locals
// before indexing (compiler finding, see AUDIT.md); Float32 comparisons
// go through owned copies/helpers.

module torch_conformance

use xiom.torch.types;
use xiom.torch.nn;
use xiom.torch.runtime;
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
  return runtime.int_to_str(i);
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

fn all_eq(v: &Vec[Float32], e: Float32) -> Bool {
  var i = 0;
  while i < v.len() {
    let x = v[i];
    if x != e { return false; }
    i = i + 1;
  };
  return true;
}

fn eq_at(v: &Vec[Float32], i: Int, e: Float32) -> Bool
  requires: i >= 0
  requires: i < v.len()
{
  let x = v[i];
  return x == e;
}

fn default_options() -> TensorOptions {
  return TensorOptions{
    dtype: DType.Float32,
    device: Device.CPU,
    requires_grad: false,
  };
}

fn finish(failed: Int) -> Int {
  if failed == 0 {
    io.println("xiom.torch: all tests passed");
  } else {
    io.println("xiom.torch: tests failed");
  }
  return failed;
}

// =========================================================================
// Pure tier -- types module
// =========================================================================

fn test_types() -> Int {
  var failed = 0;

  let sh23 = shape2(2, 3);
  let z = tensor_zeros(&sh23);
  var z_ok = z.data.len() == 6 && z.shape.len() == 2 && z.strides.len() == 2;
  if z.shape[0] != 2 || z.shape[1] != 3 { z_ok = false; }
  if z.strides[0] != 3 || z.strides[1] != 1 { z_ok = false; }
  if !all_eq(&z.data, 0.0) { z_ok = false; }
  failed = failed + report(z_ok, "types: tensor_zeros [2,3] (6 zeros, shape 2x3, strides 3/1)");

  let o = tensor_ones(&sh23);
  failed = failed + report(o.data.len() == 6 && all_eq(&o.data, 1.0),
    "types: tensor_ones [2,3] reads back all 1.0");

  let opts = default_options();
  let nw = tensor_new(&sh23, &opts);
  var nw_ok = nw.data.len() == 6;
  if nw.dtype != DType.Float32 { nw_ok = false; }
  failed = failed + report(nw_ok, "types: tensor_new with options (Float32, CPU, numel 6)");

  let sh = tensor_shape(&z);
  var sh_ok = sh.len() == 2 && sh[0] == 2 && sh[1] == 3;
  sh[0] = 999;
  let sh2 = tensor_shape(&z);
  if sh2[0] != 2 { sh_ok = false; }
  failed = failed + report(sh_ok, "types: tensor_shape returns an independent copy");

  // reshape OK + data preserved.
  let sh22 = shape2(2, 2);
  let base_opts = default_options();
  var base = tensor_new(&sh22, &base_opts);
  base.data[0] = 1.0;
  base.data[1] = 2.0;
  base.data[2] = 3.0;
  base.data[3] = 4.0;
  let sh4 = shape1(4);
  let rr = tensor_reshape(&base, &sh4);
  var r_ok = false;
  if rr.is_ok {
    let r = rr.value;
    r_ok = r.shape.len() == 1 && r.shape[0] == 4 && r.strides[0] == 1 && r.data.len() == 4;
    if r_ok {
      r_ok = eq_at(&r.data, 0, 1.0) && eq_at(&r.data, 3, 4.0);
    }
  } else { why(rr.error); }
  failed = failed + report(r_ok, "types: tensor_reshape [2,2] -> [4] preserves data (1,2,3,4)");

  let sh5 = shape1(5);
  let r_bad = tensor_reshape(&base, &sh5);
  failed = failed + report(r_bad.is_err, "types: tensor_reshape element-count mismatch -> typed error");

  return failed;
}

// =========================================================================
// Pure tier -- nn module (real forward math)
// =========================================================================

fn test_nn() -> Int {
  var failed = 0;

  // Constructors: declared shapes + initialization.
  let lin = linear_new(3, 2);
  var lin_ok = lin.in_features == 3 && lin.out_features == 2;
  if lin.weight.shape.len() != 2 || lin.weight.shape[0] != 2 || lin.weight.shape[1] != 3 { lin_ok = false; }
  if lin.bias.shape.len() != 1 || lin.bias.shape[0] != 2 { lin_ok = false; }
  if !all_eq(&lin.weight.data, 0.0) || !all_eq(&lin.bias.data, 0.0) { lin_ok = false; }
  failed = failed + report(lin_ok, "nn: linear_new(3,2) weight [2,3] + bias [2], zero-initialized");

  let conv = conv2d_new(3, 8, 5, 2, 1);
  var conv_ok = conv.in_ch == 3 && conv.out_ch == 8 && conv.kernel == 5 && conv.stride == 2 && conv.padding == 1;
  if conv.weight.shape.len() != 4 || conv.weight.shape[0] != 8 || conv.weight.shape[1] != 3 ||
     conv.weight.shape[2] != 5 || conv.weight.shape[3] != 5 { conv_ok = false; }
  if conv.bias.shape.len() != 1 || conv.bias.shape[0] != 8 { conv_ok = false; }
  failed = failed + report(conv_ok, "nn: conv2d_new(3,8,5,stride 2,pad 1) weight [8,3,5,5] + bias [8]");

  let bn = batchnorm2d_new(4, 0.001);
  var bn_ok = bn.eps == 0.001;
  if !all_eq(&bn.gamma.data, 1.0) { bn_ok = false; }
  if !all_eq(&bn.beta.data, 0.0) { bn_ok = false; }
  if !all_eq(&bn.running_mean.data, 0.0) { bn_ok = false; }
  if !all_eq(&bn.running_var.data, 1.0) { bn_ok = false; }
  if bn.gamma.data.len() != 4 { bn_ok = false; }
  failed = failed + report(bn_ok, "nn: batchnorm2d_new(4, 1e-3) gamma=1 beta=0 mean=0 var=1");

  var seq = sequential_new();
  var seq_ok = seq.layers.len() == 0;
  sequential_add(&mut seq, LayerType.ReLULayer);
  sequential_add(&mut seq, LayerType.SoftmaxLayer(1));
  sequential_add(&mut seq, LayerType.LinearLayer(linear_new(2, 2)));
  seq_ok = seq_ok && seq.layers.len() == 3;
  failed = failed + report(seq_ok, "nn: sequential_new empty + sequential_add appends (3 layers)");

  // Real linear forward, hand-computed, exact dyadic values.
  // Identity weights + bias: 1-D input [1,2] -> output [11,22].
  var ident = linear_new(2, 2);
  ident.weight.data[0] = 1.0; ident.weight.data[1] = 0.0;
  ident.weight.data[2] = 0.0; ident.weight.data[3] = 1.0;
  ident.bias.data[0] = 10.0; ident.bias.data[1] = 20.0;
  var x1_data: Vec[Float32] = Vec[Float32].new();
  x1_data.push(1.0);
  x1_data.push(2.0);
  let sh2v = shape1(2);
  let x1 = tensor_new(&sh2v, &default_options());
  x1.data[0] = 1.0;
  x1.data[1] = 2.0;
  let y1 = linear_forward(&ident, &x1);
  var y1_ok = y1.shape.len() == 2 && y1.shape[0] == 1 && y1.shape[1] == 2;
  if y1_ok {
    y1_ok = eq_at(&y1.data, 0, 11.0) && eq_at(&y1.data, 1, 22.0);
  }
  failed = failed + report(y1_ok, "nn: linear_forward 1-D [1,2] identity+bias -> [11,22]");

  // 2-D batch: [[1,2],[3,4]] -> [[11,22],[13,24]].
  var batch = tensor_new(&shape2(2, 2), &default_options());
  batch.data[0] = 1.0; batch.data[1] = 2.0;
  batch.data[2] = 3.0; batch.data[3] = 4.0;
  let y2 = linear_forward(&ident, &batch);
  var y2_ok = y2.shape.len() == 2 && y2.shape[0] == 2 && y2.shape[1] == 2;
  if y2_ok {
    y2_ok = eq_at(&y2.data, 0, 11.0) && eq_at(&y2.data, 1, 22.0) &&
            eq_at(&y2.data, 2, 13.0) && eq_at(&y2.data, 3, 24.0);
  }
  failed = failed + report(y2_ok, "nn: linear_forward batch [[1,2],[3,4]] -> [[11,22],[13,24]]");

  // Non-trivial weights: W=[[2,3],[4,5]], b=[1,1], x=[1,1] -> [6,10].
  var w2 = linear_new(2, 2);
  w2.weight.data[0] = 2.0; w2.weight.data[1] = 3.0;
  w2.weight.data[2] = 4.0; w2.weight.data[3] = 5.0;
  w2.bias.data[0] = 1.0; w2.bias.data[1] = 1.0;
  var x3 = tensor_new(&sh2v, &default_options());
  x3.data[0] = 1.0;
  x3.data[1] = 1.0;
  let y3 = linear_forward(&w2, &x3);
  var y3_ok = y3.shape[0] == 1 && y3.shape[1] == 2;
  if y3_ok {
    y3_ok = eq_at(&y3.data, 0, 6.0) && eq_at(&y3.data, 1, 10.0);
  }
  failed = failed + report(y3_ok, "nn: linear_forward W=[[2,3],[4,5]] b=[1,1] x=[1,1] -> [6,10]");

  return failed;
}

// =========================================================================
// Pure tier -- runtime loader statics
// =========================================================================

fn test_runtime_statics() -> Int {
  var failed = 0;

  let slots = torch_runtime_surface_names();
  var surf_ok = slots.len() == 13;
  if slots[0] != "aoti_torch_abi_version" { surf_ok = false; }
  if slots[4] != "aoti_torch_empty_strided" { surf_ok = false; }
  if slots[12] != "aoti_torch_is_contiguous" { surf_ok = false; }
  failed = failed + report(surf_ok, "runtime: declared C surface 13 entry points aligned");

  let anchors = torch_runtime_anchor_names();
  var anch_ok = anchors.len() == 1;
  if anchors[0] != "?is_available@cuda@torch@@YA_NXZ" { anch_ok = false; }
  failed = failed + report(anch_ok, "runtime: declared C++ anchor (cuda is_available)");

  let cands = torch_runtime_candidates();
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
    if cands[base + 9] != "libtorch.dylib" { cand_ok = false; }
  }
  failed = failed + report(cand_ok, "runtime: candidate order (XIOM_LIBTORCH_RUNTIME override, then 10 sonames)");

  let missing = torch_runtime_open_named("xiom-absent-libtorch-probe-xyz.dll");
  if missing.is_ok {
    failed = failed + report(false, "runtime: bogus soname unexpectedly loaded");
  } else {
    failed = failed + report(missing.error.kind == TORCH_LOAD_ABSENT && missing.error.message.len() > 0,
      "runtime: absent build classified TORCH_LOAD_ABSENT (SKIP)");
  }

  var kinds_ok = true;
  if TORCH_LOAD_ABSENT != 0 { kinds_ok = false; }
  if TORCH_LOAD_ABI != 1 { kinds_ok = false; }
  if TORCH_CALL_FAILED != 2 { kinds_ok = false; }
  failed = failed + report(kinds_ok, "runtime: classification kinds (ABSENT/ABI/CALL_FAILED)");

  return failed;
}

// =========================================================================
// Live leg (SKIP when no runtime)
// =========================================================================

fn test_live() -> Int {
  var failed = 0;
  let orr = torch_runtime_open();
  if !orr.is_ok {
    if orr.error.kind == TORCH_LOAD_ABSENT {
      return report(true, "live: SKIP -- no libtorch candidate present (" + orr.error.message + ")");
    }
    return report(false, "live: runtime present but unusable -- " + orr.error.message);
  }
  let rt: TorchRuntime = orr.value;

  let info = torch_runtime_info(&rt);
  var probe_ok = info.soname.len() > 0 && info.major >= 2;
  if info.resolved != 13 || info.required != 13 { probe_ok = false; }
  let expect_abi = (info.major << 56) | (info.minor << 48) | (info.patch << 40);
  if rt.abi_version != expect_abi { probe_ok = false; }
  failed = failed + report(probe_ok,
    "live: " + info.soname + " " + ist(info.major) + "." + ist(info.minor) + "." + ist(info.patch) +
    " (tensor-tier surface " + ist(info.resolved) + "/" + ist(info.required) + ")");

  let cu = torch_cuda_available(&rt);
  var cu_s = -1;
  if cu.is_ok {
    if cu.value { cu_s = 1; } else { cu_s = 0; }
  }
  failed = failed + report(cu.is_ok, "live: cuda anchor callable (is_available=" + ist(cu_s) + ")");

  // Upload -> download round trip, exact.
  var xs = tensor_new(&shape2(2, 3), &default_options());
  xs.data[0] = 1.0; xs.data[1] = 2.0; xs.data[2] = 3.0;
  xs.data[3] = 4.0; xs.data[4] = 5.0; xs.data[5] = 6.0;
  let up = torch_upload(&rt, &xs);
  var rt_ok = false;
  if up.is_ok {
    let h = up.value;
    let down = torch_download(&rt, h, "xs");
    if down.is_ok {
      let d = down.value;
      rt_ok = d.data.len() == 6 && d.shape.len() == 2 && d.shape[0] == 2 && d.shape[1] == 3;
      if rt_ok {
        rt_ok = eq_at(&d.data, 0, 1.0) && eq_at(&d.data, 2, 3.0) && eq_at(&d.data, 5, 6.0);
      }
      if rt_ok {
        rt_ok = d.strides.len() == 2 && d.strides[0] == 3 && d.strides[1] == 1;
      }
    } else { why(down.error.message); }
    // Upload copies: mutate the XIOM source, re-download, values unchanged.
    if rt_ok {
      xs.data[0] = 99.0;
      let down2 = torch_download(&rt, h, "xs2");
      if down2.is_ok {
        let d2 = down2.value;
        rt_ok = eq_at(&d2.data, 0, 1.0);
      } else {
        rt_ok = false;
        why(down2.error.message);
      }
    }
    let rel = torch_release(&rt, h);
    if !rel.is_ok { rt_ok = false; }
  } else { why(up.error.message); }
  failed = failed + report(rt_ok, "live: upload -> download [2,3] (1..6) exact; upload copies (source mutation invisible)");

  let cr = torch_runtime_close(&rt);
  failed = failed + report(cr.is_ok, "live: runtime handle released");

  return failed;
}

// =========================================================================
// Driver
// =========================================================================

pub fn main() -> Int {
  io.println("=== xiom.torch conformance tests (tensor types + NN + libtorch runtime tier) ===");
  io.flush_stdout();
  var failed: Int = 0;
  failed = failed + test_types();
  failed = failed + test_nn();
  failed = failed + test_runtime_statics();
  failed = failed + test_live();
  return finish(failed);
}
