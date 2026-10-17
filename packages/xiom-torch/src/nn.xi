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

/// Real linear forward: y = x @ W^T + b (Float32).
///
/// Accepts 1-D input [in_features] or n-D input with a trailing
/// [in_features] axis (leading axes flatten row-major to the batch axis).
/// The output is always 2-D [batch, out_features] -- the declared shape of
/// the stub this replaced, now computed for real.  Weight/bias storage is
/// row-major [out_features, in_features] / [out_features] (see
/// `linear_new`); input indexing honors the tensor's declared strides for
/// the trailing axis.
/// Complexity: O(batch * in_features * out_features).
pub fn linear_forward(layer: &Linear, input: &Tensor) -> Tensor
  requires: input.shape.len() > 0
  requires: layer.in_features > 0
  requires: input.shape[input.shape.len() - 1] == layer.in_features
{
  let ndim = input.shape.len();
  var batch = 1;
  var i = 0;
  while i < ndim - 1 {
    batch = batch * input.shape[i];
    i = i + 1;
  };
  var row_stride = 1;
  if ndim > 1 { row_stride = input.strides[0]; }
  let last_stride = input.strides[ndim - 1];
  let in_f = layer.in_features;
  let out_f = layer.out_features;
  var out_shape: Vec[Int] = Vec[Int].new();
  out_shape.push(batch);
  out_shape.push(out_f);
  var opts = TensorOptions{
    dtype: DType.Float32,
    device: Device.CPU,
    requires_grad: false,
  };
  var out = tensor_new(&out_shape, &opts);
  var b = 0;
  while b < batch {
    let base = b * row_stride;
    var o = 0;
    while o < out_f {
      var acc = layer.bias.data[o];
      var k = 0;
      while k < in_f {
        acc = acc + input.data[base + k * last_stride] * layer.weight.data[o * in_f + k];
        k = k + 1;
      };
      out.data[b * out_f + o] = acc;
      o = o + 1;
    };
    b = b + 1;
  };
  return out;
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
