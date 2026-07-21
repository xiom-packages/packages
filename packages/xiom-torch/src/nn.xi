module xiom.torch.nn

use xiom.torch.types;

pub type Linear = {
  weight: Tensor;
  bias: Tensor;
  in_features: Int;
  out_features: Int;
}

pub fn linear_new(in_features: Int, out_features: Int) -> Linear
  requires: in_features > 0
  requires: out_features > 0
{
  var w_shape = Vec[Int].new();
  w_shape.push(out_features);
  w_shape.push(in_features);
  var weight = tensor_zeros(&w_shape);
  var b_shape = Vec[Int].new();
  b_shape.push(out_features);
  var bias = tensor_zeros(&b_shape);
  return Linear{
    weight: weight,
    bias: bias,
    in_features: in_features,
    out_features: out_features,
  };
}

pub fn linear_forward(layer: &Linear, input: &Tensor) -> Tensor
  requires: input.shape.len() > 0
{
  var out_shape = Vec[Int].new();
  var in_ndim = input.shape.len();
  var batch_size = 1;
  var i = 0;
  while i < in_ndim - 1 {
    batch_size = batch_size * input.shape[i];
    i = i + 1;
  };
  out_shape.push(batch_size);
  out_shape.push(layer.out_features);
  var result = tensor_zeros(&out_shape);
  return result;
}

pub type Conv2d = {
  weight: Tensor;
  bias: Tensor;
  in_ch: Int;
  out_ch: Int;
  kernel: Int;
  stride: Int;
  padding: Int;
}

pub fn conv2d_new(in_ch: Int, out_ch: Int, kernel: Int, stride: Int, padding: Int) -> Conv2d
  requires: in_ch > 0
  requires: out_ch > 0
  requires: kernel > 0
  requires: stride > 0
  requires: padding >= 0
{
  var w_shape = Vec[Int].new();
  w_shape.push(out_ch);
  w_shape.push(in_ch);
  w_shape.push(kernel);
  w_shape.push(kernel);
  var weight = tensor_zeros(&w_shape);
  var b_shape = Vec[Int].new();
  b_shape.push(out_ch);
  var bias = tensor_zeros(&b_shape);
  return Conv2d{
    weight: weight,
    bias: bias,
    in_ch: in_ch,
    out_ch: out_ch,
    kernel: kernel,
    stride: stride,
    padding: padding,
  };
}

pub type BatchNorm2d = {
  gamma: Tensor;
  beta: Tensor;
  running_mean: Tensor;
  running_var: Tensor;
  eps: Float32;
}

pub fn batchnorm2d_new(num_features: Int, eps: Float32) -> BatchNorm2d
  requires: num_features > 0
  requires: eps > 0.0
{
  var shape = Vec[Int].new();
  shape.push(num_features);
  return BatchNorm2d{
    gamma: tensor_ones(&shape),
    beta: tensor_zeros(&shape),
    running_mean: tensor_zeros(&shape),
    running_var: tensor_ones(&shape),
    eps: eps,
  };
}

pub type ReLU = {}

pub type Sigmoid = {}

pub type Tanh = {}

pub type Softmax = {
  dim: Int;
}

pub type Sequential = {
  layers: Vec[LayerType];
}

pub enum LayerType {
  LinearLayer(Linear),
  Conv2dLayer(Conv2d),
  BatchNorm2dLayer(BatchNorm2d),
  ReLULayer,
  SigmoidLayer,
  TanhLayer,
  SoftmaxLayer(dim: Int),
}

pub fn sequential_new() -> Sequential {
  return Sequential{ layers: Vec[LayerType].new() };
}

pub fn sequential_add(seq: &mut Sequential, layer: LayerType) {
  seq.layers.push(layer);
}
