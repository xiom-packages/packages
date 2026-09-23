module xiom.durable.result

// Result[T, E] is a built-in type in XIOM. The xiom.durable convention is that
// every fallible engine function returns `Result[T, CoreError]`, propagating
// with the `?` operator and constructing with `Ok(v)` / `Err(e)`.
//
// This module provides a couple of lightweight, allocation-free helpers plus
// a plain-old-data `ResultInfo` record for FFI / wire boundaries where a
// tagged union is inconvenient to serialize.

// Trivial predicate -- mostly used to keep call sites readable.
pub fn is_ok_result(ok: Bool) -> Bool {
  return ok;
}

// Serializable success/failure summary. `error_code` is 0 on success and a
// stable numeric code otherwise (see docs/contracts-and-invariants.md).
pub type ResultInfo = {
  succeeded: Bool;
  error_code: Int;
}

pub fn result_info_ok() -> ResultInfo {
  return ResultInfo{ succeeded: true, error_code: 0 };
}

pub fn result_info_err(code: Int) -> ResultInfo {
  return ResultInfo{ succeeded: false, error_code: code };
}
