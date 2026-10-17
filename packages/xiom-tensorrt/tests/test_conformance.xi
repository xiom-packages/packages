// xiom.tensorrt conformance suite -- loader + live build/run when the
// user-supplied TensorRT runtime and a CUDA device are present.
//
// Build+run (the C++ bridge rides in port.args.json):
//   $env:XIOM_TENSORRT_DIR = "<wheel>\tensorrt_libs"
//   scripts/port.ps1 -Package xiom.tensorrt -TimeoutSec 300
//
// Without the runtime (or without an NVIDIA GPU) the live half reports a
// typed SKIP; the deterministic SKIP-path check always runs.

module tensorrt_conformance

use xiom.io;
use xiom.ffi;
use xiom.convert;
use xiom.tensorrt;

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

fn skip(name: Str) -> Int {
  io.println("  [SKIP] " + name);
  io.flush_stdout();
  return 0;
}

fn f32s(v: Float32) -> Str {
  return convert.float_to_string(v as Float64);
}

fn main() -> Int {
  io.println("=== xiom.tensorrt conformance tests (runtime loader + live leg) ===");
  io.flush_stdout();
  var failed: Int = 0;

  // 1. Deterministic SKIP classification on every host.
  let missing = trt_probe_named("xiom-absent-tensorrt-probe-xyz.dll");
  if missing.is_ok {
    failed = failed + report(false, "skip-path: bogus loader unexpectedly succeeded");
  } else {
    failed = failed + report(missing.error.kind == TRT_LOAD_ABSENT,
      "skip-path: missing loader classified as TRT_LOAD_ABSENT (SKIP)");
  }

  // 2. CUDA must be initialised before TensorRT creates its builder.
  let cu = trt_cuda_init();
  if cu.is_err {
    if cu.error.kind == TRT_NO_DEVICE || cu.error.kind == TRT_CUDA_FAILED {
      failed = failed + skip("cuda: " + cu.error.message);
    } else {
      failed = failed + report(false, "cuda: " + cu.error.message);
    }
    io.println("xiom.tensorrt: live leg SKIP (no usable CUDA runtime)");
    return failed;
  }
  failed = failed + report(true, "cuda: " + trt_cuda_device_name().value);

  // 3. Live probe (or SKIP when the user-supplied runtime is absent).
  let probe = trt_probe();
  if probe.is_err {
    if probe.error.kind == TRT_LOAD_ABSENT {
      failed = failed + skip("probe: " + probe.error.message);
      io.println("xiom.tensorrt: live leg SKIP (runtime absent)");
      return failed;
    }
    failed = failed + report(false, "probe: " + probe.error.message);
    return failed;
  }
  let info = probe.value;
  failed = failed + report(info.version.major == TRT_PINNED_MAJOR && info.version.raw > 0,
    "probe: TensorRT " + convert.int_to_string(info.version.major) + "."
      + convert.int_to_string(info.version.minor) + "."
      + convert.int_to_string(info.version.patch) + " (" + info.dll + ")");
  failed = failed + report(info.symbols_resolved == info.symbols_required && info.symbols_required == 3,
    "probe: 3/3 C entry points resolved");
  failed = failed + report(info.enqueue == "v3" && info.abi == "10.x",
    "probe: enqueue mode v3, ABI 10.x");
  failed = failed + report(trt_loaded(), "probe: module is loaded");

  // 4. Logger plumbing.
  let logger = trt_logger_create(TRT_SEVERITY_INFO);
  if logger.is_err {
    failed = failed + report(false, "logger: " + logger.error.message);
    let ig = trt_close();
    return failed;
  }
  let lg = logger.value;
  failed = failed + report(trt_logger_severity(lg).value == TRT_SEVERITY_INFO,
    "logger: severity INFO reported");
  failed = failed + report(trt_logger_set_severity(lg, TRT_SEVERITY_VERBOSE).is_ok,
    "logger: severity set to VERBOSE");
  failed = failed + report(trt_logger_severity(lg).value == TRT_SEVERITY_VERBOSE,
    "logger: severity round trip");
  let ig1 = trt_logger_set_severity(lg, TRT_SEVERITY_INFO);

  // 5. Builder + platform capability queries.
  let b = trt_builder_create(lg);
  if b.is_err {
    failed = failed + report(false, "builder: " + b.error.message);
    trt_logger_destroy(lg);
    let ig = trt_close();
    return failed;
  }
  let builder = b.value;
  failed = failed + report(trt_builder_platform_has_fp16(builder).is_ok
    && trt_builder_platform_has_int8(builder).is_ok
    && trt_builder_platform_has_tf32(builder).is_ok,
    "builder: platform capability queries");

  // 6. Network definition basics: input, constant, element-wise Mul.
  let n = trt_builder_create_network(builder);
  if n.is_err {
    failed = failed + report(false, "network: " + n.error.message);
    trt_builder_destroy(builder);
    trt_logger_destroy(lg);
    let ig = trt_close();
    return failed;
  }
  let net = n.value;
  failed = failed + report(trt_network_nb_inputs(net).value == 0,
    "network: starts with no inputs");
  let ti = trt_network_add_input_2d(net, "input", TRT_DTYPE_FLOAT, 1, 4);
  failed = failed + report(ti.is_ok, "network: addInput [1,4] Float32");
  let input = ti.value;
  failed = failed + report(trt_tensor_name(input).value == "input"
    && trt_tensor_dtype(input).value == TRT_DTYPE_FLOAT
    && trt_tensor_ndim(input).value == 2,
    "tensor: name/dtype/rank");
  failed = failed + report(trt_tensor_dim(input, 0).value == 1
    && trt_tensor_dim(input, 1).value == 4,
    "tensor: dims [1,4]");
  failed = failed + report(trt_tensor_is_input(input).value && !trt_tensor_is_output(input).value,
    "tensor: input flag set, output flag clear");
  failed = failed + report(trt_tensor_dims(input).value.len() == 2,
    "tensor: Vec shape length 2");

  let c = trt_network_add_constant_f32_2d(net, 2.0, 1, 4);
  failed = failed + report(c.is_ok, "network: constant Float32 2.0 [1,4]");
  let constant = c.value;
  let e = trt_network_add_elementwise(net, TRT_ELEMENTWISE_PROD, input, constant);
  failed = failed + report(e.is_ok, "network: elementwise PROD layer");
  let output = e.value;
  failed = failed + report(trt_tensor_set_name(output, "output").is_ok,
    "tensor: output renamed to \"output\"");
  failed = failed + report(trt_network_mark_output(net, output).is_ok,
    "network: markOutput");
  failed = failed + report(trt_network_nb_layers(net).value == 2,
    "network: 2 layers (constant + elementwise)");
  failed = failed + report(trt_network_nb_outputs(net).value == 1,
    "network: 1 output");
  failed = failed + report(trt_network_output(net, 0).is_ok
    && trt_network_input(net, 0).is_ok,
    "network: input/output accessors");
  failed = failed + report(trt_network_layer(net, 0).is_ok,
    "network: layer accessor");

  // 7. Builder config.
  let cfg = trt_builder_create_config(builder);
  if cfg.is_err {
    failed = failed + report(false, "config: " + cfg.error.message);
    trt_network_destroy(net);
    trt_builder_destroy(builder);
    trt_logger_destroy(lg);
    let ig = trt_close();
    return failed;
  }
  let config = cfg.value;
  failed = failed + report(trt_config_set_flag(config, TRT_FLAG_DEBUG, true).is_ok
    && trt_config_get_flag(config, TRT_FLAG_DEBUG).value
    && trt_config_set_flag(config, TRT_FLAG_DEBUG, false).is_ok
    && !trt_config_get_flag(config, TRT_FLAG_DEBUG).value,
    "config: DEBUG flag round trip");
  let pool_before = trt_config_memory_pool_limit(config, TRT_POOL_WORKSPACE);
  failed = failed + report(pool_before.is_ok && pool_before.value > 0,
    "config: default workspace pool positive");
  failed = failed + report(trt_config_set_memory_pool_limit(config, TRT_POOL_WORKSPACE, 268435456).is_ok
    && trt_config_memory_pool_limit(config, TRT_POOL_WORKSPACE).value == 268435456,
    "config: workspace pool set to 256 MiB");
  let tactics = trt_config_tactic_sources(config);
  failed = failed + report(tactics.is_ok
    && trt_config_set_tactic_sources(config, tactics.value).is_ok
    && trt_config_tactic_sources(config).value == tactics.value,
    "config: tactic sources round trip");

  // 8. Build + serialize.
  let hm = trt_builder_build_serialized(builder, net, config);
  if hm.is_err {
    failed = failed + report(false, "build: " + hm.error.message);
    trt_config_destroy(config);
    trt_network_destroy(net);
    trt_builder_destroy(builder);
    trt_logger_destroy(lg);
    let ig = trt_close();
    return failed;
  }
  let plan = hm.value;
  let plan_size = trt_host_memory_size(plan).value;
  failed = failed + report(plan_size > 0 && trt_host_memory_data(plan).value > 0,
    "build: serialized plan " + convert.int_to_string(plan_size) + " bytes");
  failed = failed + report(trt_host_memory_save(plan, "trt-test.plan").is_ok,
    "serialize: plan written to trt-test.plan");
  let loaded = trt_host_memory_load("trt-test.plan");
  failed = failed + report(loaded.is_ok && trt_host_memory_size(loaded.value).value == plan_size,
    "serialize: file plan reloaded with the same size");
  let plan2 = loaded.value;

  // 9. Runtime + deserialize (memory and file-backed paths).
  let rt = trt_runtime_create(lg);
  if rt.is_err {
    failed = failed + report(false, "runtime: " + rt.error.message);
    trt_host_memory_destroy(plan2);
    trt_host_memory_destroy(plan);
    trt_config_destroy(config);
    trt_network_destroy(net);
    trt_builder_destroy(builder);
    trt_logger_destroy(lg);
    let ig = trt_close();
    return failed;
  }
  let runtime = rt.value;
  let eng = trt_runtime_deserialize_memory(runtime, plan);
  failed = failed + report(eng.is_ok, "runtime: deserialize from host memory");
  let engine = eng.value;
  let eng2 = trt_runtime_deserialize_memory(runtime, plan2);
  failed = failed + report(eng2.is_ok, "runtime: deserialize from file-backed plan");
  let engine2 = eng2.value;

  // 10. Engine introspection.
  failed = failed + report(trt_engine_nb_io_tensors(engine).value == 2,
    "engine: 2 IO tensors");
  let names = trt_engine_io_tensor_names(engine);
  failed = failed + report(names.is_ok && names.value.len() == 2
    && names.value[0] == "input" && names.value[1] == "output",
    "engine: IO tensor names [input, output]");
  failed = failed + report(trt_engine_tensor_dtype(engine, "input").value == TRT_DTYPE_FLOAT
    && trt_engine_tensor_io_mode(engine, "input").value == TRT_IO_INPUT
    && trt_engine_tensor_ndim(engine, "input").value == 2
    && trt_engine_tensor_dim(engine, "input", 0).value == 1
    && trt_engine_tensor_dim(engine, "input", 1).value == 4,
    "engine: input shape [1,4] Float32");
  failed = failed + report(trt_engine_tensor_dtype(engine, "output").value == TRT_DTYPE_FLOAT
    && trt_engine_tensor_io_mode(engine, "output").value == TRT_IO_OUTPUT
    && trt_engine_tensor_ndim(engine, "output").value == 2
    && trt_engine_tensor_dim(engine, "output", 0).value == 1
    && trt_engine_tensor_dim(engine, "output", 1).value == 4,
    "engine: output shape [1,4] Float32");
  failed = failed + report(trt_engine_tensor_dims(engine, "input").value.len() == 2,
    "engine: Vec shape helper");
  failed = failed + report(trt_engine_tensor_location(engine, "input").value
    == TRT_TENSOR_LOCATION_DEVICE,
    "engine: IO tensors are device tensors");

  // 11. Execution context + device buffers + enqueueV3.
  let ctxr = trt_engine_create_context(engine);
  if ctxr.is_err {
    failed = failed + report(false, "context: " + ctxr.error.message);
    trt_engine_destroy(engine2);
    trt_engine_destroy(engine);
    trt_runtime_destroy(runtime);
    trt_host_memory_destroy(plan2);
    trt_host_memory_destroy(plan);
    trt_config_destroy(config);
    trt_network_destroy(net);
    trt_builder_destroy(builder);
    trt_logger_destroy(lg);
    let ig = trt_close();
    return failed;
  }
  let ctx = ctxr.value;
  failed = failed + report(trt_context_all_input_dims_specified(ctx).value,
    "context: all input dimensions specified");
  failed = failed + report(trt_context_set_input_shape(ctx, "input", 1, 4, 0, 0, 0, 0, 0, 0, 2).is_ok,
    "context: setInputShape [1,4]");

  let dinr = trt_cuda_alloc(16);
  let doutr = trt_cuda_alloc(16);
  failed = failed + report(dinr.is_ok && doutr.is_ok, "cuda: device buffers allocated");
  let din = dinr.value;
  let dout = doutr.value;
  let host_in = ffi.safe_ptr_alloc(16);
  let host_out = ffi.safe_ptr_alloc(16);
  if host_in.is_err || host_out.is_err {
    failed = failed + report(false, "cuda: host staging buffers");
    return failed;
  }
  var hin = host_in.value;
  var hout = host_out.value;
  let w0 = ffi.safe_ptr_write_f32(&mut hin, 0, 1.0);
  let w1 = ffi.safe_ptr_write_f32(&mut hin, 4, 2.0);
  let w2 = ffi.safe_ptr_write_f32(&mut hin, 8, 3.0);
  let w3 = ffi.safe_ptr_write_f32(&mut hin, 12, 4.0);
  failed = failed + report(w0.is_ok && w1.is_ok && w2.is_ok && w3.is_ok,
    "cuda: host input staged (1,2,3,4)");
  let src = unsafe { hin.ptr as Int };
  failed = failed + report(trt_cuda_upload(din, src, 16).is_ok,
    "cuda: upload host -> device");
  let streamr = trt_cuda_stream_create();
  failed = failed + report(streamr.is_ok, "cuda: stream created");
  let stream = streamr.value;
  failed = failed + report(trt_context_set_tensor_address(ctx, "input", din).is_ok,
    "context: set input address");
  failed = failed + report(trt_context_set_tensor_address(ctx, "output", dout).is_ok,
    "context: set output address");
  failed = failed + report(trt_context_tensor_address(ctx, "input").value == din
    && trt_context_tensor_address(ctx, "output").value == dout,
    "context: tensor address round trip");
  failed = failed + report(trt_context_enqueue(ctx, stream).is_ok,
    "context: enqueueV3");
  failed = failed + report(trt_cuda_stream_sync(stream).is_ok,
    "cuda: stream synchronised");
  let dst = unsafe { hout.ptr as Int };
  failed = failed + report(trt_cuda_download(dst, dout, 16).is_ok,
    "cuda: download device -> host");
  let r0 = ffi.safe_ptr_read_f32(&hout, 0);
  let r1 = ffi.safe_ptr_read_f32(&hout, 4);
  let r2 = ffi.safe_ptr_read_f32(&hout, 8);
  let r3 = ffi.safe_ptr_read_f32(&hout, 12);
  failed = failed + report(r0.is_ok && r1.is_ok && r2.is_ok && r3.is_ok
    && (r0.value as Float64) == 2.0 && (r1.value as Float64) == 4.0
    && (r2.value as Float64) == 6.0 && (r3.value as Float64) == 8.0,
    "live: Mul-by-2 output = 2,4,6,8 (got "
      + f32s(r0.value) + "," + f32s(r1.value) + ","
      + f32s(r2.value) + "," + f32s(r3.value) + ")");

  // 12. Logger captured the build/run messages.
  let msgs = trt_logger_message_count(lg);
  failed = failed + report(msgs.is_ok && msgs.value > 0,
    "logger: " + convert.int_to_string(msgs.value) + " messages captured");
  failed = failed + report(trt_logger_last_message(lg).is_ok,
    "logger: last message readable");

  // 13. Ordered cleanup.
  trt_context_destroy(ctx);
  trt_engine_destroy(engine2);
  trt_engine_destroy(engine);
  trt_runtime_destroy(runtime);
  trt_host_memory_destroy(plan2);
  trt_host_memory_destroy(plan);
  trt_config_destroy(config);
  trt_network_destroy(net);
  trt_builder_destroy(builder);
  trt_logger_destroy(lg);
  trt_cuda_stream_destroy(stream);
  trt_cuda_free(din);
  trt_cuda_free(dout);
  ffi.safe_ptr_free(hin);
  ffi.safe_ptr_free(hout);
  let ig2 = trt_cuda_shutdown();
  let ig3 = trt_close();
  failed = failed + report(!trt_loaded(), "cleanup: module unloaded");

  if failed == 0 {
    io.println("xiom.tensorrt: all tests passed");
  } else {
    io.println("xiom.tensorrt: tests failed");
  }
  return failed;
}
