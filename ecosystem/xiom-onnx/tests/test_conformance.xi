module xiom.onnx.test_conformance

use xiom.onnx.types;
use xiom.onnx.io;
use xiom.onnx.session;

fn test_onnx_config_default_shape() {
  var cfg = types.onnx_config_default();
  assert(cfg.num_threads == 4);
  assert(cfg.graph_optimization_level == 1);
  assert(cfg.enable_profiling == false);
}

fn test_dtype_constants() {
  assert(types.ORT_DTYPE_FLOAT == 1);
  assert(types.ORT_DTYPE_DOUBLE == 11);
  assert(types.ORT_DTYPE_INT32 == 6);
  assert(types.ORT_DTYPE_INT64 == 7);
  assert(types.ORT_DTYPE_UINT8 == 2);
  assert(types.ORT_DTYPE_BOOL == 9);
}

fn test_graph_opt_constants() {
  assert(types.ORT_GRAPH_OPT_DISABLE == 0);
  assert(types.ORT_GRAPH_OPT_BASIC == 1);
  assert(types.ORT_GRAPH_OPT_EXTENDED == 2);
  assert(types.ORT_GRAPH_OPT_ALL == 99);
}

fn test_onnx_tensor_from_vec_basic() {
  var data = Vec[Float32].new();
  data.push(1.0);
  data.push(2.0);
  data.push(3.0);
  var shape = Vec[Int].new();
  shape.push(1);
  shape.push(3);
  var t = io.onnx_tensor_from_vec(&data, &shape);
  assert(t.name == "input");
  assert(t.data.len() == 3);
  assert(t.data[0] == 1.0);
  assert(t.data[1] == 2.0);
  assert(t.data[2] == 3.0);
  assert(t.shape.len() == 2);
  assert(t.shape[0] == 1);
  assert(t.shape[1] == 3);
  assert(t.dtype == types.ORT_DTYPE_FLOAT);
}

fn test_onnx_tensor_from_vec_no_alias() {
  var data = Vec[Float32].new();
  data.push(5.0);
  var shape = Vec[Int].new();
  shape.push(1);
  var t = io.onnx_tensor_from_vec(&data, &shape);
  data[0] = 99.0;
  assert(t.data[0] == 5.0);
}

fn test_onnx_tensor_to_vec_roundtrip() {
  var data = Vec[Float32].new();
  data.push(7.0);
  data.push(8.0);
  var shape = Vec[Int].new();
  shape.push(2);
  var t = io.onnx_tensor_from_vec(&data, &shape);
  var v = io.onnx_tensor_to_vec(&t);
  assert(v.len() == 2);
  assert(v[0] == 7.0);
  assert(v[1] == 8.0);
}

fn test_onnx_tensor_to_vec_no_alias() {
  var data = Vec[Float32].new();
  data.push(3.0);
  var shape = Vec[Int].new();
  shape.push(1);
  var t = io.onnx_tensor_from_vec(&data, &shape);
  var v = io.onnx_tensor_to_vec(&t);
  v[0] = 42.0;
  assert(t.data[0] == 3.0);
}

fn test_onnx_tensor_zeros_1d() {
  var shape = Vec[Int].new();
  shape.push(4);
  var t = io.onnx_tensor_zeros("features", &shape);
  assert(t.name == "features");
  assert(t.data.len() == 4);
  assert(t.shape.len() == 1);
  assert(t.shape[0] == 4);
  var i = 0;
  while i < 4 {
    assert(t.data[i] == 0.0);
    i = i + 1;
  };
}

fn test_onnx_tensor_zeros_3d() {
  var shape = Vec[Int].new();
  shape.push(2);
  shape.push(3);
  shape.push(4);
  var t = io.onnx_tensor_zeros("volume", &shape);
  assert(t.data.len() == 24);
  assert(t.shape.len() == 3);
  assert(t.shape[0] == 2);
  assert(t.shape[1] == 3);
  assert(t.shape[2] == 4);
  var i = 0;
  while i < 24 {
    assert(t.data[i] == 0.0);
    i = i + 1;
  };
}

fn test_onnx_tensor_zeros_shape_not_aliased() {
  var shape = Vec[Int].new();
  shape.push(5);
  var t = io.onnx_tensor_zeros("x", &shape);
  shape[0] = 999;
  assert(t.shape[0] == 5);
}

fn test_onnx_tensor_get_name() {
  var shape = Vec[Int].new();
  shape.push(1);
  var t = io.onnx_tensor_zeros("logits", &shape);
  assert(io.onnx_tensor_get_name(&t) == "logits");
}

fn test_onnx_tensor_set_name() {
  var shape = Vec[Int].new();
  shape.push(1);
  var t = io.onnx_tensor_zeros("old_name", &shape);
  io.onnx_tensor_set_name(&mut t, "new_name");
  assert(t.name == "new_name");
  assert(io.onnx_tensor_get_name(&t) == "new_name");
}

fn test_onnx_preprocess_image_shape() {
  var data = Vec[Int].new();
  data.push(0);
  data.push(0);
  data.push(0);
  var t = io.onnx_preprocess_image(&data, 2);
  assert(t.name == "input");
  assert(t.shape.len() == 4);
  assert(t.shape[0] == 1);
  assert(t.shape[1] == 3);
  assert(t.shape[2] == 2);
  assert(t.shape[3] == 2);
  assert(t.data.len() == 12);
  assert(t.dtype == types.ORT_DTYPE_FLOAT);
}

fn test_onnx_preprocess_image_all_zeros() {
  var data = Vec[Int].new();
  data.push(255);
  var t = io.onnx_preprocess_image(&data, 1);
  assert(t.data.len() == 3);
  var i = 0;
  while i < 3 {
    assert(t.data[i] == 0.0);
    i = i + 1;
  };
}

fn test_onnx_load_model_ok() {
  var cfg = types.onnx_config_default();
  var r = session.onnx_load_model("model.onnx", &cfg);
  assert(r.is_ok());
}

fn test_onnx_load_model_preserves_path() {
  var cfg = types.onnx_config_default();
  var r = session.onnx_load_model("resnet.onnx", &cfg);
  assert(r.is_ok());
  var m = r.unwrap();
  assert(m.path == "resnet.onnx");
}

fn test_onnx_load_model_default_session_zero() {
  var cfg = types.onnx_config_default();
  var r = session.onnx_load_model("model.onnx", &cfg);
  assert(r.is_ok());
  var m = r.unwrap();
  assert(m.session == 0);
}

fn test_onnx_run_ok_on_stub() {
  var cfg = types.onnx_config_default();
  var m = session.onnx_load_model("model.onnx", &cfg).unwrap();
  var shape = Vec[Int].new();
  shape.push(1);
  var input = io.onnx_tensor_zeros("input", &shape);
  var inputs = Vec[OnnxTensor].new();
  inputs.push(input);
  var r = session.onnx_run(&m, &inputs);
  assert(r.is_ok());
}

fn test_onnx_run_returns_empty_on_stub() {
  var cfg = types.onnx_config_default();
  var m = session.onnx_load_model("model.onnx", &cfg).unwrap();
  var shape = Vec[Int].new();
  shape.push(1);
  var input = io.onnx_tensor_zeros("input", &shape);
  var inputs = Vec[OnnxTensor].new();
  inputs.push(input);
  var r = session.onnx_run(&m, &inputs);
  assert(r.is_ok());
  var outputs = r.unwrap();
  assert(outputs.len() == 0);
}

fn test_onnx_get_input_count_stub_returns_zero() {
  var cfg = types.onnx_config_default();
  var m = session.onnx_load_model("model.onnx", &cfg).unwrap();
  assert(session.onnx_get_input_count(&m) == 0);
}

fn test_onnx_get_output_count_stub_returns_zero() {
  var cfg = types.onnx_config_default();
  var m = session.onnx_load_model("model.onnx", &cfg).unwrap();
  assert(session.onnx_get_output_count(&m) == 0);
}

fn test_onnx_close_no_panic() {
  var cfg = types.onnx_config_default();
  var m = session.onnx_load_model("model.onnx", &cfg).unwrap();
  session.onnx_close(m);
}

fn test_onnx_load_model_with_custom_config() {
  var cfg = OnnxConfig{
    num_threads: 1,
    graph_optimization_level: types.ORT_GRAPH_OPT_ALL,
    enable_profiling: true,
  };
  var r = session.onnx_load_model("model.onnx", &cfg);
  assert(r.is_ok());
}

fn test_full_pipeline_end_to_end() {
  var cfg = types.onnx_config_default();
  var m = session.onnx_load_model("model.onnx", &cfg).unwrap();

  var shape = Vec[Int].new();
  shape.push(1);
  shape.push(3);
  shape.push(224);
  shape.push(224);
  var input = io.onnx_tensor_zeros("input", &shape);
  assert(input.data.len() == 1 * 3 * 224 * 224);
  assert(input.shape.len() == 4);

  io.onnx_tensor_set_name(&mut input, "data");
  assert(io.onnx_tensor_get_name(&input) == "data");

  var inputs = Vec[OnnxTensor].new();
  inputs.push(input);
  var r = session.onnx_run(&m, &inputs);
  assert(r.is_ok());
  var outputs = r.unwrap();

  session.onnx_close(m);
}
