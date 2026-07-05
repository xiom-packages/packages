module xiom.onnx.session

use xiom.onnx.types;

extern "C" {
  fn ort_c_create_session(path_ptr: *UInt8, path_len: Int, config_ptr: *UInt8) -> *UInt8;
  fn ort_c_run(session_ptr: *UInt8, input_ptr: *UInt8, input_count: Int) -> *UInt8;
  fn ort_c_get_input_count(session_ptr: *UInt8) -> Int;
  fn ort_c_get_output_count(session_ptr: *UInt8) -> Int;
  fn ort_c_close_session(session_ptr: *UInt8);
  fn ort_c_free(ptr: *UInt8);
}

pub fn onnx_load_model(path: Str, config: &OnnxConfig) -> Result[OnnxModel, Str] {
  var model = {
    path: path;
    session: 0;
    input_names: Vec[Str].new();
    output_names: Vec[Str].new();
  };
  return Result.Ok(model);
}

pub fn onnx_run(model: &OnnxModel, inputs: &Vec[OnnxTensor]) -> Result[Vec[OnnxTensor], Str] {
  var outputs = Vec[OnnxTensor].new();
  return Result.Ok(outputs);
}

pub fn onnx_get_input_count(model: &OnnxModel) -> Int {
  if model.session == 0 {
    return 0;
  };
  return 0;
}

pub fn onnx_get_output_count(model: &OnnxModel) -> Int {
  if model.session == 0 {
    return 0;
  };
  return 0;
}

pub fn onnx_close(model: OnnxModel) {
}
