module xiom.onnx.types

pub type OnnxModel = {
  path: Str;
  session: Int;
  input_names: Vec[Str];
  output_names: Vec[Str];
}

pub type OnnxTensor = {
  name: Str;
  data: Vec[Float32];
  shape: Vec[Int];
  dtype: Int;
}

pub type OnnxConfig = {
  num_threads: Int;
  graph_optimization_level: Int;
  enable_profiling: Bool;
}

pub fn onnx_config_default() -> OnnxConfig {
  return {
    num_threads: 4;
    graph_optimization_level: 1;
    enable_profiling: false;
  };
}

pub const ORT_DTYPE_FLOAT: Int = 1;
pub const ORT_DTYPE_DOUBLE: Int = 11;
pub const ORT_DTYPE_INT32: Int = 6;
pub const ORT_DTYPE_INT64: Int = 7;
pub const ORT_DTYPE_UINT8: Int = 2;
pub const ORT_DTYPE_BOOL: Int = 9;

pub const ORT_GRAPH_OPT_DISABLE: Int = 0;
pub const ORT_GRAPH_OPT_BASIC: Int = 1;
pub const ORT_GRAPH_OPT_EXTENDED: Int = 2;
pub const ORT_GRAPH_OPT_ALL: Int = 99;
