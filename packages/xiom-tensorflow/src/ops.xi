// XIOM -- xiom.tensorflow.ops: the ops-essentials tier (ROADMAP phase 2/3).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// High-level op builders composed from the graph tier, covering the
// in-package ROADMAP Phase 3 declaration: `op_placeholder`, `op_const`,
// `op_add`, `op_matmul`, `op_relu`. Each builder returns the finished
// TF_Operation*; outputs are consumed as `(oper, 0)` edges by the session
// tier. These are real graph constructions, verified live end-to-end in the
// suite (Placeholder+Add arithmetic, constant folding, MatMul and Relu on
// exact FP values).

module xiom.tensorflow.ops

use xiom.tensorflow.types;
use xiom.tensorflow.loader;
use xiom.tensorflow.graph;
use xiom.tensorflow.tensor;

/// `Placeholder` with a fixed dtype/shape (shape may be empty for a scalar).
/// Complexity: O(1).
pub fn op_placeholder(lib: &TfLibrary, g: Int, name: Str, dtype: Int, shape: &Vec[Int]) -> Result[Int, TfError]
  requires: g != 0
  requires: name.len() > 0
{
  let dr = graph.tf_op_new(lib, g, "Placeholder", name);
  if !dr.is_ok { return Err(dr.error); }
  let desc = dr.value;
  graph.tf_op_set_attr_type(lib, desc, "dtype", dtype);
  if shape.len() > 0 {
    graph.tf_op_set_attr_shape(lib, desc, "shape", shape);
  }
  return graph.tf_op_finish(lib, desc);
}

/// `Const` (TF_FLOAT) with a literal value tensor (shape product must equal
/// the value count). Complexity: O(elements).
pub fn op_const_f32(lib: &TfLibrary, g: Int, name: Str, shape: &Vec[Int], values: &Vec[Float32]) -> Result[Int, TfError]
  requires: g != 0
  requires: name.len() > 0
  requires: shape.len() > 0
  requires: values.len() > 0
{
  let tr = tensor.tf_tensor_create_f32(lib, shape, values);
  if !tr.is_ok { return Err(tr.error); }
  let t = tr.value;
  let dr = graph.tf_op_new(lib, g, "Const", name);
  if !dr.is_ok {
    tensor.tf_tensor_delete(lib, t);
    return Err(dr.error);
  }
  let desc = dr.value;
  graph.tf_op_set_attr_type(lib, desc, "dtype", types.TF_FLOAT);
  let at = graph.tf_op_set_attr_tensor(lib, desc, "value", t);
  if !at.is_ok {
    tensor.tf_tensor_delete(lib, t);
    return Err(at.error);
  }
  let res = graph.tf_op_finish(lib, desc);
  tensor.tf_tensor_delete(lib, t);
  return res;
}

/// `Const` (TF_INT32). Complexity: O(elements).
pub fn op_const_i32(lib: &TfLibrary, g: Int, name: Str, shape: &Vec[Int], values: &Vec[Int]) -> Result[Int, TfError]
  requires: g != 0
  requires: name.len() > 0
  requires: shape.len() > 0
  requires: values.len() > 0
{
  let tr = tensor.tf_tensor_create_i32(lib, shape, values);
  if !tr.is_ok { return Err(tr.error); }
  let t = tr.value;
  let dr = graph.tf_op_new(lib, g, "Const", name);
  if !dr.is_ok {
    tensor.tf_tensor_delete(lib, t);
    return Err(dr.error);
  }
  let desc = dr.value;
  graph.tf_op_set_attr_type(lib, desc, "dtype", types.TF_INT32);
  let at = graph.tf_op_set_attr_tensor(lib, desc, "value", t);
  if !at.is_ok {
    tensor.tf_tensor_delete(lib, t);
    return Err(at.error);
  }
  let res = graph.tf_op_finish(lib, desc);
  tensor.tf_tensor_delete(lib, t);
  return res;
}

/// `Add`: elementwise a + b (both inputs are (oper, 0) edges).
/// Complexity: O(1).
pub fn op_add(lib: &TfLibrary, g: Int, name: Str, a_oper: Int, b_oper: Int) -> Result[Int, TfError]
  requires: g != 0
  requires: name.len() > 0
  requires: a_oper != 0
  requires: b_oper != 0
{
  let dr = graph.tf_op_new(lib, g, "Add", name);
  if !dr.is_ok { return Err(dr.error); }
  let desc = dr.value;
  graph.tf_op_add_input(lib, desc, a_oper, 0);
  graph.tf_op_add_input(lib, desc, b_oper, 0);
  return graph.tf_op_finish(lib, desc);
}

/// `MatMul` with explicit transpose flags. Complexity: O(1).
pub fn op_matmul(lib: &TfLibrary, g: Int, name: Str, a_oper: Int, b_oper: Int, transpose_a: Bool, transpose_b: Bool) -> Result[Int, TfError]
  requires: g != 0
  requires: name.len() > 0
  requires: a_oper != 0
  requires: b_oper != 0
{
  let dr = graph.tf_op_new(lib, g, "MatMul", name);
  if !dr.is_ok { return Err(dr.error); }
  let desc = dr.value;
  graph.tf_op_add_input(lib, desc, a_oper, 0);
  graph.tf_op_add_input(lib, desc, b_oper, 0);
  graph.tf_op_set_attr_bool(lib, desc, "transpose_a", transpose_a);
  graph.tf_op_set_attr_bool(lib, desc, "transpose_b", transpose_b);
  return graph.tf_op_finish(lib, desc);
}

/// `Relu`: max(x, 0). Complexity: O(1).
pub fn op_relu(lib: &TfLibrary, g: Int, name: Str, x_oper: Int) -> Result[Int, TfError]
  requires: g != 0
  requires: name.len() > 0
  requires: x_oper != 0
{
  let dr = graph.tf_op_new(lib, g, "Relu", name);
  if !dr.is_ok { return Err(dr.error); }
  let desc = dr.value;
  graph.tf_op_add_input(lib, desc, x_oper, 0);
  return graph.tf_op_finish(lib, desc);
}

/// `Identity` (edge forwarding; useful to materialize a fetched name).
/// Complexity: O(1).
pub fn op_identity(lib: &TfLibrary, g: Int, name: Str, x_oper: Int) -> Result[Int, TfError]
  requires: g != 0
  requires: name.len() > 0
  requires: x_oper != 0
{
  let dr = graph.tf_op_new(lib, g, "Identity", name);
  if !dr.is_ok { return Err(dr.error); }
  let desc = dr.value;
  graph.tf_op_add_input(lib, desc, x_oper, 0);
  return graph.tf_op_finish(lib, desc);
}
