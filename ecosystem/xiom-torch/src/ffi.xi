module xiom.torch.ffi

use xiom.torch.types;

extern "C" {
  fn torch_c_load_model(path_ptr: *UInt8, path_len: Int) -> *UInt8;
  fn torch_c_forward(module_ptr: *UInt8, input_ptr: *UInt8, input_len: Int) -> *UInt8;
  fn torch_c_save_model(module_ptr: *UInt8, path_ptr: *UInt8, path_len: Int) -> Int;
  fn torch_c_is_cuda_available() -> Int;
  fn torch_c_free(ptr: *UInt8);
}

pub fn torch_load_model(path: Str) -> Result[ModuleDef, Str] {
  var dummy = ModuleDef{
    name: "stub",
    params: Vec[Tensor].new(),
    buffers: Vec[Tensor].new(),
  };
  return Ok(dummy);
}

pub fn torch_forward(module: &ModuleDef, input: &Tensor) -> Result[Tensor, Str] {
  var dummy = Tensor{
    data: Vec[Float32].new(),
    shape: Vec[Int].new(),
    strides: Vec[Int].new(),
    device: Device.CPU,
    dtype: DType.Float32,
  };
  return Ok(dummy);
}

pub fn torch_save_model(module: &ModuleDef, path: Str) -> Result[Bool, Str] {
  return Ok(true);
}

pub fn torch_is_cuda_available() -> Bool {
  return false;
}
