module xiom.torch.types

pub type Tensor = {
  data: Vec[Float32];
  shape: Vec[Int];
  strides: Vec[Int];
  device: Device;
  dtype: DType;
}

pub enum DType {
  Float32,
  Float64,
  Int32,
  Int64,
  UInt8,
  Bool,
}

pub enum Device {
  CPU,
  CUDA(device_id: Int),
}

pub type TensorOptions = {
  dtype: DType;
  device: Device;
  requires_grad: Bool;
}

pub type ModuleDef = {
  name: Str;
  params: Vec[Tensor];
  buffers: Vec[Tensor];
}

fn compute_strides(shape: &Vec[Int]) -> Vec[Int] {
  var ndim = shape.len();
  var strides = Vec[Int].new();
  if ndim == 0 {
    return strides;
  };
  var i = 0;
  while i < ndim {
    strides.push(0);
    i = i + 1;
  };
  strides[ndim - 1] = 1;
  var d = ndim - 2;
  while d >= 0 {
    strides[d] = strides[d + 1] * shape[d + 1];
    d = d - 1;
  };
  return strides;
}

pub fn tensor_new(shape: &Vec[Int], options: &TensorOptions) -> Tensor
  requires: shape.len() > 0;
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
  return {
    data: data;
    shape: shape.clone();
    strides: compute_strides(shape);
    device: options.device;
    dtype: options.dtype;
  };
}

pub fn tensor_zeros(shape: &Vec[Int]) -> Tensor
  requires: shape.len() > 0;
{
  var opts = {
    dtype: DType.Float32;
    device: Device.CPU;
    requires_grad: false;
  };
  return tensor_new(shape, &opts);
}

pub fn tensor_ones(shape: &Vec[Int]) -> Tensor
  requires: shape.len() > 0;
{
  var t = tensor_zeros(shape);
  var i = 0;
  while i < t.data.len() {
    t.data[i] = 1.0;
    i = i + 1;
  };
  return t;
}

pub fn tensor_shape(t: &Tensor) -> Vec[Int] {
  return t.shape.clone();
}

fn compute_total(shape: &Vec[Int]) -> Int {
  var total = 1;
  var i = 0;
  while i < shape.len() {
    total = total * shape[i];
    i = i + 1;
  };
  return total;
}

pub fn tensor_reshape(t: &Tensor, shape: &Vec[Int]) -> Tensor
  requires: shape.len() > 0;
  ensures: result.data.len() == t.data.len();
{
  var new_total = compute_total(shape);
  var old_total = compute_total(&t.shape);
  if new_total != old_total {
    return {
      data: Vec[Float32].new();
      shape: Vec[Int].new();
      strides: Vec[Int].new();
      device: t.device;
      dtype: t.dtype;
    };
  };
  return {
    data: t.data.clone();
    shape: shape.clone();
    strides: compute_strides(shape);
    device: t.device;
    dtype: t.dtype;
  };
}
