module xiom.numpy

pub type NDArray = Int
pub type DType = Int

pub const DTYPE_INT32: Int = 0;
pub const DTYPE_INT64: Int = 1;
pub const DTYPE_FLOAT32: Int = 2;
pub const DTYPE_FLOAT64: Int = 3;

extern "C" {
  fn numpy_c_array_new(shape_ptr: Int, ndim: Int, dtype: Int) -> Int;
  fn numpy_c_array_from_data(data_ptr: Int, data_len: Int, shape_ptr: Int, ndim: Int) -> Int;
  fn numpy_c_array_zeros(shape_ptr: Int, ndim: Int, dtype: Int) -> Int;
  fn numpy_c_array_ones(shape_ptr: Int, ndim: Int, dtype: Int) -> Int;
  fn numpy_c_array_arange(start: Float64, stop: Float64, step: Float64) -> Int;
  fn numpy_c_array_free(arr: Int);
  fn numpy_c_array_get(arr: Int, indices_ptr: Int, ndim: Int) -> Float64;
  fn numpy_c_array_set(arr: Int, indices_ptr: Int, ndim: Int, val: Float64);
  fn numpy_c_array_ndim(arr: Int) -> Int;
  fn numpy_c_array_shape(arr: Int, out_ptr: Int, out_len: Int);
  fn numpy_c_array_size(arr: Int) -> Int;
  fn numpy_c_array_add(a: Int, b: Int) -> Int;
  fn numpy_c_array_sub(a: Int, b: Int) -> Int;
  fn numpy_c_array_mul(a: Int, b: Int) -> Int;
  fn numpy_c_array_div(a: Int, b: Int) -> Int;
  fn numpy_c_array_dot(a: Int, b: Int) -> Int;
  fn numpy_c_array_matmul(a: Int, b: Int) -> Int;
}

pub fn array_new(shape: &Vec[Int], dtype: DType) -> Result[NDArray, Str]
  requires: shape.len() > 0
{
  let handle: Int = unsafe { numpy_c_array_new(0, shape.len(), dtype) };
  if handle <= 0 {
    return Err("numpy_c_array_new: FFI bridge not linked or allocation failed");
  };
  return Ok(handle);
}

pub fn array_from_data(data: &Vec[Float64], shape: &Vec[Int]) -> Result[NDArray, Str]
  requires: data.len() > 0
  requires: shape.len() > 0
{
  let handle: Int = unsafe { numpy_c_array_from_data(0, data.len(), 0, shape.len()) };
  if handle <= 0 {
    return Err("numpy_c_array_from_data: FFI bridge not linked or allocation failed");
  };
  return Ok(handle);
}

pub fn array_zeros(shape: &Vec[Int], dtype: DType) -> Result[NDArray, Str]
  requires: shape.len() > 0
{
  let handle: Int = unsafe { numpy_c_array_zeros(0, shape.len(), dtype) };
  if handle <= 0 {
    return Err("numpy_c_array_zeros: FFI bridge not linked or allocation failed");
  };
  return Ok(handle);
}

pub fn array_ones(shape: &Vec[Int], dtype: DType) -> Result[NDArray, Str]
  requires: shape.len() > 0
{
  let handle: Int = unsafe { numpy_c_array_ones(0, shape.len(), dtype) };
  if handle <= 0 {
    return Err("numpy_c_array_ones: FFI bridge not linked or allocation failed");
  };
  return Ok(handle);
}

pub fn array_arange(start: Float64, stop: Float64, step: Float64) -> Result[NDArray, Str]
  requires: step != 0.0
{
  let handle: Int = unsafe { numpy_c_array_arange(start, stop, step) };
  if handle <= 0 {
    return Err("numpy_c_array_arange: FFI bridge not linked or allocation failed");
  };
  return Ok(handle);
}

pub fn array_free(arr: NDArray)
  requires: arr != 0
{
  unsafe { numpy_c_array_free(arr) };
}

pub fn array_get(arr: &NDArray, indices: &Vec[Int]) -> Float64
  requires: arr != 0
  requires: indices.len() > 0
{
  return unsafe { numpy_c_array_get(arr, 0, indices.len()) };
}

pub fn array_set(arr: &mut NDArray, indices: &Vec[Int], val: Float64)
  requires: arr != 0
  requires: indices.len() > 0
{
  unsafe { numpy_c_array_set(arr, 0, indices.len(), val) };
}

pub fn array_ndim(arr: &NDArray) -> Int
  requires: arr != 0
{
  return unsafe { numpy_c_array_ndim(arr) };
}

fn array_shape_into_vec(arr: &NDArray, ndim: Int) -> Vec[Int]
  requires: arr != 0
  requires: ndim >= 0
{
  var out = Vec[Int].new();
  var i = 0;
  while i < ndim {
    out.push(0);
    i = i + 1;
  };
  return out;
}

pub fn array_shape(arr: &NDArray) -> Vec[Int]
  requires: arr != 0
{
  let ndim: Int = array_ndim(arr);
  if ndim <= 0 {
    var empty = Vec[Int].new();
    return empty;
  };
  var shape = array_shape_into_vec(arr, ndim);
  unsafe { numpy_c_array_shape(arr, 0, ndim) };
  return shape;
}

pub fn array_size(arr: &NDArray) -> Int
  requires: arr != 0
{
  return unsafe { numpy_c_array_size(arr) };
}

pub fn array_add(a: &NDArray, b: &NDArray) -> Result[NDArray, Str]
  requires: a != 0
  requires: b != 0
{
  let handle: Int = unsafe { numpy_c_array_add(a, b) };
  if handle <= 0 {
    return Err("numpy_c_array_add: FFI bridge not linked or shape mismatch");
  };
  return Ok(handle);
}

pub fn array_sub(a: &NDArray, b: &NDArray) -> Result[NDArray, Str]
  requires: a != 0
  requires: b != 0
{
  let handle: Int = unsafe { numpy_c_array_sub(a, b) };
  if handle <= 0 {
    return Err("numpy_c_array_sub: FFI bridge not linked or shape mismatch");
  };
  return Ok(handle);
}

pub fn array_mul(a: &NDArray, b: &NDArray) -> Result[NDArray, Str]
  requires: a != 0
  requires: b != 0
{
  let handle: Int = unsafe { numpy_c_array_mul(a, b) };
  if handle <= 0 {
    return Err("numpy_c_array_mul: FFI bridge not linked or shape mismatch");
  };
  return Ok(handle);
}

pub fn array_div(a: &NDArray, b: &NDArray) -> Result[NDArray, Str]
  requires: a != 0
  requires: b != 0
{
  let handle: Int = unsafe { numpy_c_array_div(a, b) };
  if handle <= 0 {
    return Err("numpy_c_array_div: FFI bridge not linked or shape mismatch");
  };
  return Ok(handle);
}

pub fn array_dot(a: &NDArray, b: &NDArray) -> Result[NDArray, Str]
  requires: a != 0
  requires: b != 0
{
  let handle: Int = unsafe { numpy_c_array_dot(a, b) };
  if handle <= 0 {
    return Err("numpy_c_array_dot: FFI bridge not linked or dimension mismatch");
  };
  return Ok(handle);
}

pub fn array_matmul(a: &NDArray, b: &NDArray) -> Result[NDArray, Str]
  requires: a != 0
  requires: b != 0
{
  let handle: Int = unsafe { numpy_c_array_matmul(a, b) };
  if handle <= 0 {
    return Err("numpy_c_array_matmul: FFI bridge not linked or dimension mismatch");
  };
  return Ok(handle);
}

pub fn dtype_to_str(dtype: DType) -> Str {
  if dtype == DTYPE_INT32 {
    return "int32";
  };
  if dtype == DTYPE_INT64 {
    return "int64";
  };
  if dtype == DTYPE_FLOAT32 {
    return "float32";
  };
  if dtype == DTYPE_FLOAT64 {
    return "float64";
  };
  return "unknown";
}

pub fn is_valid_dtype(dtype: DType) -> Bool {
  return dtype == DTYPE_INT32 || dtype == DTYPE_INT64 || dtype == DTYPE_FLOAT32 || dtype == DTYPE_FLOAT64;
}
