// XIOM -- xiom.tensorflow.session: options, sessions, runs, saved models.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// The session tier of the declared surface: TF_SessionOptions (target,
// ConfigProto), session lifecycle (TF_NewSession / TF_LoadSessionFromSavedModel
// / TF_CloseSession / TF_DeleteSession / TF_ExtendSession), execution
// (TF_SessionRun, partial runs TF_SessionPRunSetup/PRun/DeletePRunHandle) and
// device enumeration (TF_SessionListDevices + the TF_DeviceList* readers).
// All calls go through a loaded TfLibrary (see xiom.tensorflow.loader for
// the input/output array marshalling conventions).

module xiom.tensorflow.session

use xiom.tensorflow.types;
use xiom.tensorflow.loader;
use xiom.ffi;

// =========================================================================
// Local helpers
// =========================================================================

fn status_alloc(lib: &TfLibrary) -> Result[Int, TfError]
  requires: true
{
  let fp = loader.tf_fn(lib, loader.TF_FN_NewStatus);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "status_alloc: TF_NewStatus missing" });
  }
  unsafe {
    let f = fp as fn() -> Int;
    let st = f();
    if st == 0 {
      return Err(TfError{ kind: types.TF_CALL_FAILED; message: "status_alloc: TF_NewStatus returned null" });
    }
    return Ok(st);
  }
}

/// Pack parallel oper/index vectors into a TF_Output array (16-byte stride).
/// Complexity: O(n).
fn pack_outputs(opers: &Vec[Int], indices: &Vec[Int]) -> Vec[UInt8]
  requires: opers.len() == indices.len()
{
  var buf: Vec[UInt8] = Vec[UInt8].with_len(opers.len() * 16);
  var i = 0;
  while i < opers.len() {
    loader.tf_out16_put(&mut buf, i * 16, opers[i], indices[i]);
    i = i + 1;
  };
  return buf;
}

/// TF_SessionRun argument list, shaped once for both entry points.
/// Complexity: O(n).
fn session_run_common(lib: &TfLibrary, session: Int, run_options: Int, in_opers: &Vec[Int], in_indices: &Vec[Int], in_tensors: &Vec[Int], out_opers: &Vec[Int], out_indices: &Vec[Int], context: Str) -> Result[TfTensorList, TfError]
  requires: session != 0
  requires: in_opers.len() == in_indices.len()
  requires: in_opers.len() == in_tensors.len()
  requires: out_opers.len() == out_indices.len()
  requires: context.len() > 0
{
  if out_opers.len() == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: context + ": no output fetches provided" });
  }
  let fp = loader.tf_fn(lib, loader.TF_FN_SessionRun);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: context + ": TF_SessionRun missing" });
  }
  var ins = pack_outputs(in_opers, in_indices);
  var outs = pack_outputs(out_opers, out_indices);
  var in_vals = Vec[Int].with_len(in_tensors.len());
  var i = 0;
  while i < in_tensors.len() {
    in_vals[i] = in_tensors[i];
    i = i + 1;
  };
  var out_vals = Vec[Int].with_len(out_opers.len());
  i = 0;
  while i < out_opers.len() {
    out_vals[i] = 0;
    i = i + 1;
  };
  var ins_ptr = 0;
  var in_vals_ptr = 0;
  if in_opers.len() > 0 {
    unsafe {
      ins_ptr = ins.as_mut_ptr() as Int;
      in_vals_ptr = in_vals.as_mut_ptr() as Int;
    }
  }
  let sr = status_alloc(lib);
  if !sr.is_ok { return Err(sr.error); }
  let st = sr.value;
  unsafe {
    let f = fp as fn(Int, Int, Int, Int, Int32, Int, Int, Int32, Int, Int32, Int, Int) -> Unit;
    f(session, run_options, ins_ptr, in_vals_ptr, in_tensors.len() as Int32, outs.as_mut_ptr() as Int, out_vals.as_mut_ptr() as Int, out_opers.len() as Int32, 0, 0, 0, st);
  }
  let c = loader.tf_check(lib, st, context);
  if !c.is_ok { return Err(c.error); }
  var items: Vec[Int] = Vec[Int].new();
  i = 0;
  while i < out_opers.len() {
    if out_vals[i] == 0 {
      return Err(TfError{
        kind: types.TF_CALL_FAILED;
        message: context + ": output " + loader.int_to_str(i) + " is null after a successful run",
      });
    }
    items.push(out_vals[i]);
    i = i + 1;
  };
  return Ok(TfTensorList{ items: items });
}

// =========================================================================
// Session options
// =========================================================================

/// TF_NewSessionOptions. Complexity: O(1).
pub fn tf_session_options_new(lib: &TfLibrary) -> Result[Int, TfError]
  requires: true
{
  let fp = loader.tf_fn(lib, loader.TF_FN_NewSessionOptions);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "session_options_new: missing" });
  }
  unsafe {
    let f = fp as fn() -> Int;
    let o = f();
    if o == 0 {
      return Err(TfError{ kind: types.TF_CALL_FAILED; message: "session_options_new: returned null" });
    }
    return Ok(o);
  }
}

/// TF_DeleteSessionOptions (safe on 0). Complexity: O(1).
pub fn tf_session_options_delete(lib: &TfLibrary, opts: Int)
  requires: true
{
  if opts == 0 { return; }
  let fp = loader.tf_fn(lib, loader.TF_FN_DeleteSessionOptions);
  if fp == 0 { return; }
  unsafe {
    let f = fp as fn(Int) -> Unit;
    f(opts);
  }
}

/// TF_SetTarget ("local" or "host:port"). Complexity: O(1).
pub fn tf_session_options_set_target(lib: &TfLibrary, opts: Int, target: Str)
  requires: opts != 0
  requires: target.len() > 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_SetTarget);
  if fp == 0 { return; }
  unsafe {
    let f = fp as fn(Int, Int) -> Unit;
    f(opts, target.c_str() as Int);
  }
}

/// TF_SetConfig with a serialized ConfigProto. Complexity: O(len).
pub fn tf_session_options_set_config(lib: &TfLibrary, opts: Int, config: &Vec[UInt8]) -> Result[Unit, TfError]
  requires: opts != 0
  requires: config.len() > 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_SetConfig);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "session_options_set_config: missing" });
  }
  let sr = status_alloc(lib);
  if !sr.is_ok { return Err(sr.error); }
  let st = sr.value;
  unsafe {
    let f = fp as fn(Int, Int, Int, Int) -> Unit;
    f(opts, config.as_mut_ptr() as Int, config.len(), st);
  }
  return loader.tf_check(lib, st, "SetConfig");
}

// =========================================================================
// Session lifecycle
// =========================================================================

/// TF_NewSession (opts 0 = null options). Complexity: O(1).
pub fn tf_session_new(lib: &TfLibrary, graph: Int, opts: Int) -> Result[Int, TfError]
  requires: graph != 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_NewSession);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "session_new: TF_NewSession missing" });
  }
  let sr = status_alloc(lib);
  if !sr.is_ok { return Err(sr.error); }
  let st = sr.value;
  var s = 0;
  unsafe {
    let f = fp as fn(Int, Int, Int) -> Int;
    s = f(graph, opts, st);
  }
  let c = loader.tf_check(lib, st, "NewSession");
  if !c.is_ok { return Err(c.error); }
  if s == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "session_new: TF_NewSession returned null" });
  }
  return Ok(s);
}

/// TF_LoadSessionFromSavedModel: creates a session from an exported
/// SavedModel directory and populates `graph`. Returns
/// [session, meta_graph_def_len]. Complexity: O(model load).
pub fn tf_session_load_saved_model(lib: &TfLibrary, opts: Int, export_dir: Str, tags: &Vec[Str], graph: Int) -> Result[TfIntList, TfError]
  requires: export_dir.len() > 0
  requires: tags.len() > 0
  requires: graph != 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_LoadSessionFromSavedModel);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "load_saved_model: TF_LoadSessionFromSavedModel missing" });
  }
  let nbf = loader.tf_fn(lib, loader.TF_FN_NewBuffer);
  if nbf == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "load_saved_model: TF_NewBuffer missing" });
  }
  var meta = 0;
  unsafe {
    let mkb = nbf as fn() -> Int;
    meta = mkb();
  }
  if meta == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "load_saved_model: null meta buffer" });
  }
  var tag_ptrs = Vec[Int].with_len(tags.len());
  var i = 0;
  while i < tags.len() {
    unsafe {
      let base = tag_ptrs.as_mut_ptr() as Int;
      ffi.ptr_write_u64_le((base + i * 8) as *UInt8, tags[i].c_str() as Int);
    }
    i = i + 1;
  };
  let sr = status_alloc(lib);
  if !sr.is_ok { return Err(sr.error); }
  let st = sr.value;
  var s = 0;
  unsafe {
    let f = fp as fn(Int, Int, Int, Int, Int32, Int, Int, Int) -> Int;
    s = f(opts, 0, export_dir.c_str() as Int, tag_ptrs.as_mut_ptr() as Int, tags.len() as Int32, graph, meta, st);
  }
  let c = loader.tf_check(lib, st, "LoadSessionFromSavedModel");
  if !c.is_ok {
    let dbf = loader.tf_fn(lib, loader.TF_FN_DeleteBuffer);
    if dbf != 0 {
      unsafe {
        let f2 = dbf as fn(Int) -> Unit;
        f2(meta);
      }
    }
    return Err(c.error);
  }
  if s == 0 {
    let dbf = loader.tf_fn(lib, loader.TF_FN_DeleteBuffer);
    if dbf != 0 {
      unsafe {
        let f2 = dbf as fn(Int) -> Unit;
        f2(meta);
      }
    }
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "load_saved_model: TF_LoadSessionFromSavedModel returned null" });
  }
  var meta_len = 0;
  unsafe {
    meta_len = ffi.ptr_read_u64_le((meta + 8) as *UInt8);
  }
  let dbf = loader.tf_fn(lib, loader.TF_FN_DeleteBuffer);
  if dbf != 0 {
    unsafe {
      let f2 = dbf as fn(Int) -> Unit;
      f2(meta);
    }
  }
  var items: Vec[Int] = Vec[Int].new();
  items.push(s);
  items.push(meta_len);
  return Ok(TfIntList{ items: items });
}

/// TF_ExtendSession: register graph additions with the session.
/// Complexity: O(new ops).
pub fn tf_session_extend(lib: &TfLibrary, session: Int) -> Result[Unit, TfError]
  requires: session != 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_ExtendSession);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "session_extend: missing" });
  }
  let sr = status_alloc(lib);
  if !sr.is_ok { return Err(sr.error); }
  let st = sr.value;
  unsafe {
    let f = fp as fn(Int, Int) -> Unit;
    f(session, st);
  }
  return loader.tf_check(lib, st, "ExtendSession");
}

/// TF_CloseSession. Complexity: O(1).
pub fn tf_session_close(lib: &TfLibrary, session: Int)
  requires: session != 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_CloseSession);
  if fp == 0 { return; }
  let sr = status_alloc(lib);
  if !sr.is_ok { return; }
  let st = sr.value;
  unsafe {
    let f = fp as fn(Int, Int) -> Unit;
    f(session, st);
  }
  let c = loader.tf_check(lib, st, "CloseSession");
}

/// TF_DeleteSession. Complexity: O(1).
pub fn tf_session_delete(lib: &TfLibrary, session: Int)
  requires: session != 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_DeleteSession);
  if fp == 0 { return; }
  let sr = status_alloc(lib);
  if !sr.is_ok { return; }
  let st = sr.value;
  unsafe {
    let f = fp as fn(Int, Int) -> Unit;
    f(session, st);
  }
  let c = loader.tf_check(lib, st, "DeleteSession");
}

// =========================================================================
// Execution
// =========================================================================

/// TF_SessionRun over parallel oper/index/tensor handle vectors: inputs are
/// (in_opers[i]:in_indices[i]) = in_tensors[i]; fetched outputs are returned
/// in order (caller owns them; TF_DeleteTensor each).
/// Complexity: O(inputs + outputs).
pub fn tf_session_run(lib: &TfLibrary, session: Int, in_opers: &Vec[Int], in_indices: &Vec[Int], in_tensors: &Vec[Int], out_opers: &Vec[Int], out_indices: &Vec[Int]) -> Result[TfTensorList, TfError]
  requires: session != 0
  requires: in_opers.len() == in_indices.len()
  requires: in_opers.len() == in_tensors.len()
  requires: out_opers.len() == out_indices.len()
{
  return session_run_common(lib, session, 0, in_opers, in_indices, in_tensors, out_opers, out_indices, "SessionRun");
}

/// TF_SessionPRunSetup: registers the feed/fetch sets for partial runs.
/// Returns the run handle (a TF-owned pointer; release with
/// `tf_prun_delete` when done). Complexity: O(inputs + outputs).
pub fn tf_session_prun_setup(lib: &TfLibrary, session: Int, in_opers: &Vec[Int], in_indices: &Vec[Int], out_opers: &Vec[Int], out_indices: &Vec[Int]) -> Result[Int, TfError]
  requires: session != 0
  requires: in_opers.len() == in_indices.len()
  requires: out_opers.len() == out_indices.len()
{
  let fp = loader.tf_fn(lib, loader.TF_FN_SessionPRunSetup);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "prun_setup: TF_SessionPRunSetup missing" });
  }
  var ins = pack_outputs(in_opers, in_indices);
  var outs = pack_outputs(out_opers, out_indices);
  var ins_ptr = 0;
  if in_opers.len() > 0 {
    unsafe {
      ins_ptr = ins.as_mut_ptr() as Int;
    }
  }
  var handle_slot = Vec[UInt8].with_len(8);
  let sr = status_alloc(lib);
  if !sr.is_ok { return Err(sr.error); }
  let st = sr.value;
  unsafe {
    let f = fp as fn(Int, Int, Int32, Int, Int32, Int, Int32, Int, Int) -> Unit;
    f(session, ins_ptr, in_opers.len() as Int32, outs.as_mut_ptr() as Int, out_opers.len() as Int32, 0, 0, handle_slot.as_mut_ptr() as Int, st);
  }
  let c = loader.tf_check(lib, st, "SessionPRunSetup");
  if !c.is_ok { return Err(c.error); }
  var handle = 0;
  unsafe {
    handle = ffi.ptr_read_u64_le(handle_slot.as_mut_ptr());
  }
  if handle == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "prun_setup: handle is null" });
  }
  return Ok(handle);
}

/// TF_SessionPRun: one partial-run step against a setup handle.
/// Complexity: O(inputs + outputs).
pub fn tf_session_prun(lib: &TfLibrary, session: Int, handle: Int, in_opers: &Vec[Int], in_indices: &Vec[Int], in_tensors: &Vec[Int], out_opers: &Vec[Int], out_indices: &Vec[Int]) -> Result[TfTensorList, TfError]
  requires: session != 0
  requires: handle != 0
  requires: in_opers.len() == in_indices.len()
  requires: in_opers.len() == in_tensors.len()
  requires: out_opers.len() == out_indices.len()
{
  if out_opers.len() == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "prun: no output fetches provided" });
  }
  let fp = loader.tf_fn(lib, loader.TF_FN_SessionPRun);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "prun: TF_SessionPRun missing" });
  }
  var ins = pack_outputs(in_opers, in_indices);
  var outs = pack_outputs(out_opers, out_indices);
  var in_vals = Vec[Int].with_len(in_tensors.len());
  var i = 0;
  while i < in_tensors.len() {
    in_vals[i] = in_tensors[i];
    i = i + 1;
  };
  var out_vals = Vec[Int].with_len(out_opers.len());
  i = 0;
  while i < out_opers.len() {
    out_vals[i] = 0;
    i = i + 1;
  };
  var ins_ptr = 0;
  var in_vals_ptr = 0;
  if in_opers.len() > 0 {
    unsafe {
      ins_ptr = ins.as_mut_ptr() as Int;
      in_vals_ptr = in_vals.as_mut_ptr() as Int;
    }
  }
  let sr = status_alloc(lib);
  if !sr.is_ok { return Err(sr.error); }
  let st = sr.value;
  unsafe {
    let f = fp as fn(Int, Int, Int, Int, Int32, Int, Int, Int32, Int, Int32, Int) -> Unit;
    f(session, handle, ins_ptr, in_vals_ptr, in_tensors.len() as Int32, outs.as_mut_ptr() as Int, out_vals.as_mut_ptr() as Int, out_opers.len() as Int32, 0, 0, st);
  }
  let c = loader.tf_check(lib, st, "SessionPRun");
  if !c.is_ok { return Err(c.error); }
  var items: Vec[Int] = Vec[Int].new();
  i = 0;
  while i < out_opers.len() {
    if out_vals[i] == 0 {
      return Err(TfError{
        kind: types.TF_CALL_FAILED;
        message: "prun: output " + loader.int_to_str(i) + " is null after a successful run",
      });
    }
    items.push(out_vals[i]);
    i = i + 1;
  };
  return Ok(TfTensorList{ items: items });
}

/// TF_DeletePRunHandle. Complexity: O(1).
pub fn tf_prun_delete(lib: &TfLibrary, handle: Int)
  requires: handle != 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_DeletePRunHandle);
  if fp == 0 { return; }
  unsafe {
    let f = fp as fn(Int) -> Unit;
    f(handle);
  }
}

// =========================================================================
// Devices
// =========================================================================

/// TF_SessionListDevices (caller owns; free with `tf_device_list_delete`).
/// Complexity: O(devices).
pub fn tf_device_list(lib: &TfLibrary, session: Int) -> Result[Int, TfError]
  requires: session != 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_SessionListDevices);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "device_list: TF_SessionListDevices missing" });
  }
  let sr = status_alloc(lib);
  if !sr.is_ok { return Err(sr.error); }
  let st = sr.value;
  var list = 0;
  unsafe {
    let f = fp as fn(Int, Int) -> Int;
    list = f(session, st);
  }
  let c = loader.tf_check(lib, st, "SessionListDevices");
  if !c.is_ok { return Err(c.error); }
  if list == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "device_list: null list" });
  }
  return Ok(list);
}

/// TF_DeleteDeviceList (safe on 0). Complexity: O(1).
pub fn tf_device_list_delete(lib: &TfLibrary, list: Int)
  requires: true
{
  if list == 0 { return; }
  let fp = loader.tf_fn(lib, loader.TF_FN_DeleteDeviceList);
  if fp == 0 { return; }
  unsafe {
    let f = fp as fn(Int) -> Unit;
    f(list);
  }
}

/// TF_DeviceListCount. Complexity: O(1).
pub fn tf_device_list_count(lib: &TfLibrary, list: Int) -> Int
  requires: list != 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_DeviceListCount);
  if fp == 0 { return -1; }
  unsafe {
    let f = fp as fn(Int) -> Int32;
    return f(list) as Int;
  }
}

/// TF_DeviceListName (owned copy). Complexity: O(len).
pub fn tf_device_list_name(lib: &TfLibrary, list: Int, index: Int) -> Result[Str, TfError]
  requires: list != 0
  requires: index >= 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_DeviceListName);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "device_list_name: missing" });
  }
  let sr = status_alloc(lib);
  if !sr.is_ok { return Err(sr.error); }
  let st = sr.value;
  var p = 0;
  unsafe {
    let f = fp as fn(Int, Int32, Int) -> Int;
    p = f(list, index as Int32, st);
  }
  let c = loader.tf_check(lib, st, "DeviceListName");
  if !c.is_ok { return Err(c.error); }
  if p == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "device_list_name: null name" });
  }
  return Ok(loader.tf_own_c_str(p));
}

/// TF_DeviceListType (owned copy). Complexity: O(len).
pub fn tf_device_list_type(lib: &TfLibrary, list: Int, index: Int) -> Result[Str, TfError]
  requires: list != 0
  requires: index >= 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_DeviceListType);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "device_list_type: missing" });
  }
  let sr = status_alloc(lib);
  if !sr.is_ok { return Err(sr.error); }
  let st = sr.value;
  var p = 0;
  unsafe {
    let f = fp as fn(Int, Int32, Int) -> Int;
    p = f(list, index as Int32, st);
  }
  let c = loader.tf_check(lib, st, "DeviceListType");
  if !c.is_ok { return Err(c.error); }
  if p == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "device_list_type: null type" });
  }
  return Ok(loader.tf_own_c_str(p));
}

/// TF_DeviceListMemoryBytes (-1 on error). Complexity: O(1).
pub fn tf_device_list_memory_bytes(lib: &TfLibrary, list: Int, index: Int) -> Result[Int, TfError]
  requires: list != 0
  requires: index >= 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_DeviceListMemoryBytes);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "device_list_memory_bytes: missing" });
  }
  let sr = status_alloc(lib);
  if !sr.is_ok { return Err(sr.error); }
  let st = sr.value;
  var v = 0;
  unsafe {
    let f = fp as fn(Int, Int32, Int) -> Int;
    v = f(list, index as Int32, st);
  }
  let c = loader.tf_check(lib, st, "DeviceListMemoryBytes");
  if !c.is_ok { return Err(c.error); }
  return Ok(v);
}

/// TF_DeviceListIncarnation. Complexity: O(1).
pub fn tf_device_list_incarnation(lib: &TfLibrary, list: Int, index: Int) -> Result[Int, TfError]
  requires: list != 0
  requires: index >= 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_DeviceListIncarnation);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "device_list_incarnation: missing" });
  }
  let sr = status_alloc(lib);
  if !sr.is_ok { return Err(sr.error); }
  let st = sr.value;
  var v = 0;
  unsafe {
    let f = fp as fn(Int, Int32, Int) -> Int;
    v = f(list, index as Int32, st);
  }
  let c = loader.tf_check(lib, st, "DeviceListIncarnation");
  if !c.is_ok { return Err(c.error); }
  return Ok(v);
}
