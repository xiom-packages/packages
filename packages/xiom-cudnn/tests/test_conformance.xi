// xiom.cudnn conformance suite -- user-supplied cuDNN runtime (nothing
// vendored), SKIP-safe when the runtime is absent.
//
// Build+run (the --c-source list rides in port.args.json):
//   scripts/port.ps1 -Package xiom.cudnn -TimeoutSec 300
//
// Live leg: the suite discovers the runtime through XIOM_CUDNN_DIR /
// CUDNN_DIR / PATH (or an explicit directory) and exercises the complete
// declared surface: version, handle, tensor/filter/convolution/activation/
// pooling descriptors, convolution forward, ReLU forward, max-pooling
// forward, softmax forward, and the CUDA device-memory support calls.
//
// SKIP leg: a bogus explicit directory is deterministic on every host and
// must classify as CUDNN_LOAD_ABSENT.

module cudnn_conformance

use xiom.io;
use xiom.cudnn;

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

fn i2s(n: Int) -> Str {
  if n == 0 { return "0"; }
  var neg = false;
  var v = n;
  if v < 0 {
    neg = true;
    v = 0 - v;
  }
  var buf = "";
  while v > 0 {
    let digit = v % 10;
    v = v / 10;
    if digit == 0 { buf = "0" + buf; }
    elif digit == 1 { buf = "1" + buf; }
    elif digit == 2 { buf = "2" + buf; }
    elif digit == 3 { buf = "3" + buf; }
    elif digit == 4 { buf = "4" + buf; }
    elif digit == 5 { buf = "5" + buf; }
    elif digit == 6 { buf = "6" + buf; }
    elif digit == 7 { buf = "7" + buf; }
    elif digit == 8 { buf = "8" + buf; }
    elif digit == 9 { buf = "9" + buf; }
  }
  if neg { return "-" + buf; }
  return buf;
}

fn close_f32(a: Float32, b: Float32, eps: Float32) -> Bool {
  var d = a - b;
  if d < (0.0 as Float32) { d = (0.0 as Float32) - d; }
  return d <= eps;
}

fn zeros_f32(n: Int) -> Vec[Float32] {
  var v = Vec[Float32].new();
  var i = 0;
  while i < n {
    v.push(0.0 as Float32);
    i = i + 1;
  }
  return v;
}

fn unit_filter() -> Vec[Float32] {
  var v = Vec[Float32].new();
  var i = 0;
  while i < 9 {
    v.push(1.0 as Float32);
    i = i + 1;
  }
  return v;
}

fn ramp_16() -> Vec[Float32] {
  var v = Vec[Float32].new();
  var i = 1;
  while i <= 16 {
    v.push(i as Float32);
    i = i + 1;
  }
  return v;
}

// Known-value checks on the self-contained probe result.
fn check_probe(p: &CudnnProbe) -> Int {
  var failed = 0;
  failed = failed + report(p.version > 0, "probe: version " + i2s(p.version));
  failed = failed + report(p.dims.len() == 4 && p.dims[0] == 1 && p.dims[1] == 1 && p.dims[2] == 4 && p.dims[3] == 4,
    "probe: tensor dims 1x1x4x4");
  failed = failed + report(p.strides.len() == 4 && p.strides[0] == 16 && p.strides[1] == 16 && p.strides[2] == 4 && p.strides[3] == 1,
    "probe: NCHW strides 16/16/4/1");
  failed = failed + report(p.conv.len() == 4
    && close_f32(p.conv[0], 54.0 as Float32, 0.001 as Float32)
    && close_f32(p.conv[1], 63.0 as Float32, 0.001 as Float32)
    && close_f32(p.conv[2], 90.0 as Float32, 0.001 as Float32)
    && close_f32(p.conv[3], 99.0 as Float32, 0.001 as Float32),
    "probe: conv forward == 54/63/90/99");
  failed = failed + report(p.relu.len() == 4
    && close_f32(p.relu[0], 54.0 as Float32, 0.001 as Float32)
    && close_f32(p.relu[3], 99.0 as Float32, 0.001 as Float32),
    "probe: ReLU(conv) == conv");
  failed = failed + report(p.relu_negative.len() == 2
    && close_f32(p.relu_negative[0], 0.0 as Float32, 0.001 as Float32)
    && close_f32(p.relu_negative[1], 2.0 as Float32, 0.001 as Float32),
    "probe: ReLU(-1,2,-3,4) clamps negatives");
  failed = failed + report(close_f32(p.pool_max, 99.0 as Float32, 0.001 as Float32),
    "probe: 2x2 max pool == 99");
  failed = failed + report(p.softmax.len() == 4
    && close_f32(p.softmax[0], 0.0320586 as Float32, 0.002 as Float32)
    && close_f32(p.softmax[1], 0.0871443 as Float32, 0.002 as Float32)
    && close_f32(p.softmax[2], 0.2368828 as Float32, 0.002 as Float32)
    && close_f32(p.softmax[3], 0.6439143 as Float32, 0.002 as Float32),
    "probe: softmax(1,2,3,4) values");
  failed = failed + report(close_f32(p.softmax_sum, 1.0 as Float32, 0.002 as Float32),
    "probe: softmax sum == 1");
  failed = failed + report(p.module_name.len() > 0, "probe: module name reported");
  failed = failed + report(p.device_name.len() > 0, "probe: device name reported");
  failed = failed + report(p.compute_capability > 0, "probe: compute capability " + i2s(p.compute_capability));
  failed = failed + report(p.workspace_bytes >= 0, "probe: workspace size queried");
  return failed;
}

// Full low-level declared-surface exercise against a working runtime.
fn check_surface(dir: Str) -> Int {
  var failed = 0;
  let lr = cudnn_load(dir);
  if !lr.is_ok {
    return report(false, "surface: cudnn_load -- " + lr.error.message);
  }
  failed = failed + report(lr.value > 0, "surface: cudnn_load -> " + i2s(lr.value));

  let vr = cudnn_version();
  failed = failed + report(vr.is_ok && vr.value == lr.value, "surface: cudnnGetVersion");

  failed = failed + report(cudnn_loaded_module().len() > 0, "surface: loader module");
  failed = failed + report(cudnn_compute_capability() > 0, "surface: compute capability");
  failed = failed + report(cudnn_error_text(CUDNN_STATUS_SUCCESS).len() > 0, "surface: cudnnGetErrorString");

  let hr = cudnn_handle_create();
  if !hr.is_ok {
    return failed + report(false, "surface: cudnnCreate -- " + hr.error.message);
  }
  let h = hr.value;

  let xdr = cudnn_tensor_create();
  let ydr = cudnn_tensor_create();
  let pdr = cudnn_tensor_create();
  let sdr = cudnn_tensor_create();
  let fdr = cudnn_filter_create();
  let cdr = cudnn_convolution_create();
  let adr = cudnn_activation_create();
  let podr = cudnn_pooling_create();
  if !xdr.is_ok || !ydr.is_ok || !pdr.is_ok || !sdr.is_ok || !fdr.is_ok || !cdr.is_ok || !adr.is_ok || !podr.is_ok {
    return failed + report(false, "surface: descriptor creation");
  }
  let xd = xdr.value;
  let yd = ydr.value;
  let pd = pdr.value;
  let sd = sdr.value;
  let fd = fdr.value;
  let cd = cdr.value;
  let ad = adr.value;
  let pod = podr.value;

  let set_x = cudnn_tensor_set_4d(xd, CUDNN_TENSOR_NCHW, CUDNN_DATA_FLOAT, 1, 1, 4, 4);
  let set_y = cudnn_tensor_set_4d(yd, CUDNN_TENSOR_NCHW, CUDNN_DATA_FLOAT, 1, 1, 2, 2);
  let set_p = cudnn_tensor_set_4d(pd, CUDNN_TENSOR_NCHW, CUDNN_DATA_FLOAT, 1, 1, 1, 1);
  let set_s = cudnn_tensor_set_4d(sd, CUDNN_TENSOR_NCHW, CUDNN_DATA_FLOAT, 1, 4, 1, 1);
  failed = failed + report(set_x.is_ok && set_y.is_ok && set_p.is_ok && set_s.is_ok, "surface: tensor set 4D");
  if !set_x.is_ok { return failed + report(false, "surface: tensor set -- " + set_x.error.message); }

  let tgr = cudnn_tensor_get_4d(xd);
  if tgr.is_ok {
    let t = tgr.value;
    failed = failed + report(t.data_type == CUDNN_DATA_FLOAT && t.n == 1 && t.c == 1 && t.h == 4 && t.w == 4,
      "surface: cudnnGetTensor4dDescriptor dims");
    failed = failed + report(t.n_stride == 16 && t.c_stride == 16 && t.h_stride == 4 && t.w_stride == 1,
      "surface: cudnnGetTensor4dDescriptor strides");
  } else {
    failed = failed + report(false, "surface: cudnnGetTensor4dDescriptor -- " + tgr.error.message);
  }

  failed = failed + report(cudnn_filter_set_4d(fd, CUDNN_DATA_FLOAT, CUDNN_TENSOR_NCHW, 1, 1, 3, 3).is_ok,
    "surface: cudnnSetFilter4dDescriptor");
  failed = failed + report(cudnn_convolution_set_2d(cd, 0, 0, 1, 1, 1, 1,
    CUDNN_CROSS_CORRELATION, CUDNN_DATA_FLOAT).is_ok, "surface: cudnnSetConvolution2dDescriptor");
  failed = failed + report(cudnn_activation_set(ad, CUDNN_ACTIVATION_RELU, CUDNN_NOT_PROPAGATE_NAN,
    0.0 as Float64).is_ok, "surface: cudnnSetActivationDescriptor");
  failed = failed + report(cudnn_pooling_set_2d(pod, CUDNN_POOLING_MAX, CUDNN_NOT_PROPAGATE_NAN,
    2, 2, 0, 0, 2, 2).is_ok, "surface: cudnnSetPooling2dDescriptor");

  let wsr = cudnn_convolution_workspace_size(h, xd, fd, cd, yd, CUDNN_CONVOLUTION_FWD_ALGO_IMPLICIT_GEMM);
  if !wsr.is_ok {
    return failed + report(false, "surface: cudnnGetConvolutionForwardWorkspaceSize -- " + wsr.error.message);
  }
  let ws = wsr.value;
  failed = failed + report(ws >= 0, "surface: workspace size " + i2s(ws));

  let dxr = cudnn_device_alloc(16 * 4);
  let dwr = cudnn_device_alloc(9 * 4);
  let dyr = cudnn_device_alloc(4 * 4);
  let dy2r = cudnn_device_alloc(4 * 4);
  let dngr = cudnn_device_alloc(4 * 4);
  let dngor = cudnn_device_alloc(4 * 4);
  let dpor = cudnn_device_alloc(1 * 4);
  let dsmr = cudnn_device_alloc(4 * 4);
  let dsmor = cudnn_device_alloc(4 * 4);
  if !dxr.is_ok || !dwr.is_ok || !dyr.is_ok || !dy2r.is_ok || !dngr.is_ok || !dngor.is_ok || !dpor.is_ok || !dsmr.is_ok || !dsmor.is_ok {
    return failed + report(false, "surface: cudnn_device_alloc");
  }
  let dx = dxr.value;
  let dw = dwr.value;
  let dy = dyr.value;
  let dy2 = dy2r.value;
  let dng = dngr.value;
  let dngo = dngor.value;
  let dpo = dpor.value;
  let dsm = dsmr.value;
  let dsmo = dsmor.value;
  var dwork = 0;
  if ws > 0 {
    let dwkr = cudnn_device_alloc(ws);
    if !dwkr.is_ok {
      return failed + report(false, "surface: workspace alloc -- " + dwkr.error.message);
    }
    dwork = dwkr.value;
  }

  let xv = ramp_16();
  let wv = unit_filter();
  var nv = Vec[Float32].new();
  nv.push(-1.0 as Float32);
  nv.push(2.0 as Float32);
  nv.push(-3.0 as Float32);
  nv.push(4.0 as Float32);
  var sv = Vec[Float32].new();
  sv.push(1.0 as Float32);
  sv.push(2.0 as Float32);
  sv.push(3.0 as Float32);
  sv.push(4.0 as Float32);

  failed = failed + report(cudnn_device_upload(dx, &xv).is_ok, "surface: device upload x");
  failed = failed + report(cudnn_device_upload(dw, &wv).is_ok, "surface: device upload w");
  failed = failed + report(cudnn_device_upload(dng, &nv).is_ok, "surface: device upload negative");
  failed = failed + report(cudnn_device_upload(dsm, &sv).is_ok, "surface: device upload softmax");

  let conv = cudnn_convolution_forward(h, xd, dx, fd, dw, cd,
    CUDNN_CONVOLUTION_FWD_ALGO_IMPLICIT_GEMM, dwork, ws,
    1.0 as Float32, 0.0 as Float32, yd, dy);
  if !conv.is_ok {
    return failed + report(false, "surface: cudnnConvolutionForward -- " + conv.error.message);
  }
  failed = failed + report(cudnn_device_sync().is_ok, "surface: device sync");

  var out = zeros_f32(4);
  let d1 = cudnn_device_download(dy, &mut out);
  failed = failed + report(d1.is_ok
    && close_f32(out[0], 54.0 as Float32, 0.001 as Float32)
    && close_f32(out[1], 63.0 as Float32, 0.001 as Float32)
    && close_f32(out[2], 90.0 as Float32, 0.001 as Float32)
    && close_f32(out[3], 99.0 as Float32, 0.001 as Float32),
    "surface: conv forward 54/63/90/99");

  let act = cudnn_activation_forward(h, ad, 1.0 as Float32, yd, dy, 0.0 as Float32, yd, dy2);
  failed = failed + report(act.is_ok, "surface: cudnnActivationForward");
  var out2 = zeros_f32(4);
  let d2 = cudnn_device_download(dy2, &mut out2);
  failed = failed + report(d2.is_ok && close_f32(out2[0], 54.0 as Float32, 0.001 as Float32)
    && close_f32(out2[3], 99.0 as Float32, 0.001 as Float32),
    "surface: ReLU forward");

  let actn = cudnn_activation_forward(h, ad, 1.0 as Float32, yd, dng, 0.0 as Float32, yd, dngo);
  failed = failed + report(actn.is_ok, "surface: cudnnActivationForward (negative input)");
  var outn = zeros_f32(4);
  let dn = cudnn_device_download(dngo, &mut outn);
  failed = failed + report(dn.is_ok
    && close_f32(outn[0], 0.0 as Float32, 0.001 as Float32)
    && close_f32(outn[1], 2.0 as Float32, 0.001 as Float32)
    && close_f32(outn[2], 0.0 as Float32, 0.001 as Float32)
    && close_f32(outn[3], 4.0 as Float32, 0.001 as Float32),
    "surface: ReLU clamps negatives");

  let pool = cudnn_pooling_forward(h, pod, 1.0 as Float32, yd, dy2, 0.0 as Float32, pd, dpo);
  failed = failed + report(pool.is_ok, "surface: cudnnPoolingForward");
  var outp = zeros_f32(1);
  let dp = cudnn_device_download(dpo, &mut outp);
  failed = failed + report(dp.is_ok && close_f32(outp[0], 99.0 as Float32, 0.001 as Float32),
    "surface: max pool 99");

  let sm = cudnn_softmax_forward(h, CUDNN_SOFTMAX_ACCURATE, CUDNN_SOFTMAX_MODE_CHANNEL,
    1.0 as Float32, sd, dsm, 0.0 as Float32, sd, dsmo);
  failed = failed + report(sm.is_ok, "surface: cudnnSoftmaxForward");
  var outs = zeros_f32(4);
  let ds = cudnn_device_download(dsmo, &mut outs);
  let ssum = outs[0] + outs[1] + outs[2] + outs[3];
  failed = failed + report(ds.is_ok
    && close_f32(outs[0], 0.0320586 as Float32, 0.002 as Float32)
    && close_f32(outs[1], 0.0871443 as Float32, 0.002 as Float32)
    && close_f32(outs[2], 0.2368828 as Float32, 0.002 as Float32)
    && close_f32(outs[3], 0.6439143 as Float32, 0.002 as Float32)
    && close_f32(ssum, 1.0 as Float32, 0.002 as Float32),
    "surface: softmax values + sum 1");

  failed = failed + report(cudnn_softmax_forward(h, CUDNN_SOFTMAX_FAST, CUDNN_SOFTMAX_MODE_INSTANCE,
    1.0 as Float32, sd, dsm, 0.0 as Float32, sd, dsmo).is_ok,
    "surface: cudnnSoftmaxForward (fast/instance)");

  failed = failed + report(cudnn_pooling_destroy(pod).is_ok, "surface: cudnnDestroyPoolingDescriptor");
  failed = failed + report(cudnn_activation_destroy(ad).is_ok, "surface: cudnnDestroyActivationDescriptor");
  failed = failed + report(cudnn_convolution_destroy(cd).is_ok, "surface: cudnnDestroyConvolutionDescriptor");
  failed = failed + report(cudnn_filter_destroy(fd).is_ok, "surface: cudnnDestroyFilterDescriptor");
  failed = failed + report(cudnn_tensor_destroy(sd).is_ok, "surface: destroy softmax tensor");
  failed = failed + report(cudnn_tensor_destroy(pd).is_ok, "surface: destroy pool tensor");
  failed = failed + report(cudnn_tensor_destroy(yd).is_ok, "surface: destroy y tensor");
  failed = failed + report(cudnn_tensor_destroy(xd).is_ok, "surface: cudnnDestroyTensorDescriptor");

  failed = failed + report(cudnn_device_free(dsmo).is_ok, "surface: device free softmax out");
  failed = failed + report(cudnn_device_free(dsm).is_ok, "surface: device free softmax");
  failed = failed + report(cudnn_device_free(dpo).is_ok, "surface: device free pool");
  failed = failed + report(cudnn_device_free(dngo).is_ok, "surface: device free negative out");
  failed = failed + report(cudnn_device_free(dng).is_ok, "surface: device free negative");
  failed = failed + report(cudnn_device_free(dy2).is_ok, "surface: device free y2");
  failed = failed + report(cudnn_device_free(dy).is_ok, "surface: device free y");
  failed = failed + report(cudnn_device_free(dw).is_ok, "surface: device free w");
  failed = failed + report(cudnn_device_free(dx).is_ok, "surface: device free x");
  if dwork != 0 {
    failed = failed + report(cudnn_device_free(dwork).is_ok, "surface: device free workspace");
  }

  failed = failed + report(cudnn_handle_destroy(h).is_ok, "surface: cudnnDestroy");
  cudnn_shutdown();
  return failed;
}

fn main() -> Int {
  io.println("=== xiom.cudnn conformance tests (runtime loader, nothing vendored) ===");
  io.flush_stdout();
  var failed: Int = 0;

  // 1. Deterministic SKIP classification on every host.
  let missing = cudnn_probe("xiom-absent-cudnn-probe-xyz");
  if missing.is_ok {
    failed = failed + report(false, "skip-path: bogus runtime unexpectedly succeeded");
  } else {
    failed = failed + report(missing.error.kind == CUDNN_LOAD_ABSENT,
      "skip-path: missing runtime classified as CUDNN_LOAD_ABSENT");
  }

  // 2. Live probe through the environment/PATH search (SKIP when absent).
  let pr = cudnn_probe_auto();
  if pr.is_ok {
    failed = failed + check_probe(&pr.value);
    failed = failed + check_surface("");
  } else {
    if pr.error.kind == CUDNN_LOAD_ABSENT || pr.error.kind == CUDNN_NO_DEVICE {
      failed = failed + report(true, "probe: SKIP -- " + pr.error.message);
    } else {
      failed = failed + report(false, "probe: failed -- " + pr.error.message
        + " (status " + i2s(pr.error.status) + ")");
    }
  }

  if failed == 0 {
    io.println("xiom.cudnn: all tests passed");
  } else {
    io.println("xiom.cudnn: tests failed");
  }
  return failed;
}
