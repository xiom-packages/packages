module xiom.onnx.io

use xiom.onnx.types;

pub fn onnx_tensor_from_vec(data: &Vec[Float32], shape: &Vec[Int]) -> OnnxTensor
  requires: data.len() > 0
  requires: shape.len() > 0
{
  return OnnxTensor{
    name: "input",
    data: copy_vec_float32(data),
    shape: copy_vec_int(shape),
    dtype: types.ORT_DTYPE_FLOAT,
  };
}

pub fn onnx_tensor_to_vec(t: &OnnxTensor) -> Vec[Float32] {
  return copy_vec_float32(&t.data);
}

fn copy_vec_int(src: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < src.len() {
    out.push(src[i]);
    i = i + 1;
  };
  return out;
}

fn copy_vec_float32(src: &Vec[Float32]) -> Vec[Float32] {
  var out = Vec[Float32].new();
  var i = 0;
  while i < src.len() {
    out.push(src[i]);
    i = i + 1;
  };
  return out;
}

fn clamp_float(v: Float32, lo: Float32, hi: Float32) -> Float32 {
  if v < lo { return lo; };
  if v > hi { return hi; };
  return v;
}

pub fn onnx_preprocess_image(data: &Vec[Int], target_size: Int) -> OnnxTensor
  requires: data.len() > 0
  requires: target_size > 0
{
  var c = 3;
  var h = target_size;
  var w = target_size;
  var total = c * h * w;
  var out = Vec[Float32].new();
  var i = 0;
  while i < total {
    out.push(0.0);
    i = i + 1;
  };
  var shape = Vec[Int].new();
  shape.push(1);
  shape.push(c);
  shape.push(h);
  shape.push(w);
  return OnnxTensor{
    name: "input",
    data: out,
    shape: shape,
    dtype: types.ORT_DTYPE_FLOAT,
  };
}

pub fn onnx_tensor_zeros(name: Str, shape: &Vec[Int]) -> OnnxTensor
  requires: shape.len() > 0
{
  var total = 1;
  var i = 0;
  while i < shape.len() {
    total = total * shape[i];
    i = i + 1;
  };
  var data = Vec[Float32].new();
  var j = 0;
  while j < total {
    data.push(0.0);
    j = j + 1;
  };
  return OnnxTensor{
    name: name,
    data: data,
    shape: copy_vec_int(shape),
    dtype: types.ORT_DTYPE_FLOAT,
  };
}

pub fn onnx_tensor_get_name(t: &OnnxTensor) -> Str {
  return t.name;
}

pub fn onnx_tensor_set_name(t: &mut OnnxTensor, name: Str) {
  t.name = name;
}
