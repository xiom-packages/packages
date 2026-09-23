// XIOM -- xiom.option: combinators for Option and Result values
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Concrete Int/Str specializations of the frozen Option/Result combinator
// API (SPEC.md). The compiler's function-pointer codegen only supports
// non-generic concrete signatures, so every combinator here is monomorphic
// and callbacks must be NAMED top-level functions (never inline lambdas).
//
// Semantics: map/flat_map/filter transform only the present (`Some`) or
// `Ok` side; `None` and `Err` pass through unchanged (map on `Err` returns
// the original `Err`, including its message).

module xiom.option

// ===========================================================================
// Option[Int]
// ===========================================================================

// Apply f to the contained Int. None passes through unchanged.
pub fn option_map_int(o: Option[Int], f: fn(&Int) -> Int) -> Option[Int] {
  match o {
    Some(v) => {
      let mapped = f(&v);
      return Some(mapped);
    },
    None => {
      return None;
    },
  }
}

// Apply f to the contained Int and return its Option (flattened).
pub fn option_flat_map_int(o: Option[Int], f: fn(&Int) -> Option[Int]) -> Option[Int] {
  match o {
    Some(v) => {
      let mapped = f(&v);
      return mapped;
    },
    None => {
      return None;
    },
  }
}

// Keep the contained Int only when pred holds; otherwise None.
pub fn option_filter_int(o: Option[Int], pred: fn(&Int) -> Bool) -> Option[Int] {
  match o {
    Some(v) => {
      if pred(&v) {
        return Some(v);
      }
      return None;
    },
    None => {
      return None;
    },
  }
}

// Return the contained Int, or fallback when the option is None.
pub fn option_unwrap_or_int(o: Option[Int], fallback: Int) -> Int {
  match o {
    Some(v) => {
      return v;
    },
    None => {
      return fallback;
    },
  }
}

// Return the contained Int, or f() when the option is None.
pub fn option_unwrap_or_else_int(o: Option[Int], f: fn() -> Int) -> Int {
  match o {
    Some(v) => {
      return v;
    },
    None => {
      let produced = f();
      return produced;
    },
  }
}

// Return the option itself when Some, otherwise the alternate option.
pub fn option_or_else_int(o: Option[Int], alt: Option[Int]) -> Option[Int] {
  match o {
    Some(v) => {
      return Some(v);
    },
    None => {
      return alt;
    },
  }
}

// Some(v) -> Ok(v); None -> Err(err).
pub fn option_to_result_int(o: Option[Int], err: Str) -> Result[Int, Str] {
  match o {
    Some(v) => {
      return Ok(v);
    },
    None => {
      return Err(err);
    },
  }
}

// Ok(v) -> Some(v); Err(_) -> None.
pub fn option_from_result_int(r: Result[Int, Str]) -> Option[Int] {
  match r {
    Ok(v) => {
      return Some(v);
    },
    Err(_) => {
      return None;
    },
  }
}

// ===========================================================================
// Option[Str]
// ===========================================================================

// Apply f to the contained Str. None passes through unchanged.
pub fn option_map_str(o: Option[Str], f: fn(&Str) -> Str) -> Option[Str] {
  match o {
    Some(v) => {
      let mapped = f(&v);
      return Some(mapped);
    },
    None => {
      return None;
    },
  }
}

// Return the contained Str, or fallback when the option is None.
pub fn option_unwrap_or_str(o: Option[Str], fallback: Str) -> Str {
  match o {
    Some(v) => {
      return v;
    },
    None => {
      return fallback;
    },
  }
}

// Some(v) -> Ok(v); None -> Err(err).
pub fn option_to_result_str(o: Option[Str], err: Str) -> Result[Str, Str] {
  match o {
    Some(v) => {
      return Ok(v);
    },
    None => {
      return Err(err);
    },
  }
}

// ===========================================================================
// Result[Int, Str]
// ===========================================================================

// Apply f to the Ok payload. Err passes through unchanged.
pub fn result_map_int(r: Result[Int, Str], f: fn(&Int) -> Int) -> Result[Int, Str] {
  match r {
    Ok(v) => {
      let mapped = f(&v);
      return Ok(mapped);
    },
    Err(e) => {
      return Err(e);
    },
  }
}

// Return the Ok payload, or fallback when the result is Err.
pub fn result_unwrap_or_int(r: Result[Int, Str], fallback: Int) -> Int {
  match r {
    Ok(v) => {
      return v;
    },
    Err(_) => {
      return fallback;
    },
  }
}

// Ok(v) -> Some(v); Err(_) -> None.
pub fn result_ok_int(r: Result[Int, Str]) -> Option[Int] {
  match r {
    Ok(v) => {
      return Some(v);
    },
    Err(_) => {
      return None;
    },
  }
}

// Err(e) -> Some(e); Ok(_) -> None.
pub fn result_err_str(r: Result[Int, Str]) -> Option[Str] {
  match r {
    Ok(_) => {
      return None;
    },
    Err(e) => {
      return Some(e);
    },
  }
}

// Discard Err, keep the Ok payload as an Option. Alias of result_ok_int.
pub fn result_to_option_int(r: Result[Int, Str]) -> Option[Int] {
  return result_ok_int(r);
}
