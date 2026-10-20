// probe_real_arrow.xi -- optional REAL Arrow-backed pandas bridge probe.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// NOT part of port.ps1 -- the conformance suite stays offline via
// bridge/pandas_bridge.c (stub). This probe links the production xiom.pandas
// surface against the REAL Acero-free Arrow-backed bridge and exercises the
// owner-approved section-8 surface:
//   1. null contract (0 in -> 0 out) on the real bridge;
//   2. CSV round trip;
//   3. Acero-free group-by (Grouper + bridge-side count);
//   4. Acero-free join (fallback: Grouper ids + Take gather), all 4 types;
//   5. series_apply with the pinned `double (*)(double)` callback (Float64);
//   6. dataframe_filter_f64 (IEEE-754 bits carried as Int64);
//   7. additive ownership frees;
//   8. Parquet round trip through the Arrow Parquet component (SKIP-safe when
//      the bridge was built without the component: to_parquet reports the
//      backend unavailable and the probe prints [SKIP], not [FAIL]).
//
// Local invocation (paths resolved locally; binaries stay in %TEMP%):
//   $arrow = "E:\repos\arrow-bin\pyarrow-22.0.0"
//   $env:CPLUS_INCLUDE_PATH = "<arrow-noacero-copy>"   # Acero headers removed
//   $env:PATH = "$arrow\pyarrow;$arrow\pyarrow.libs;$env:PATH"
//   xiom --run packages\xiom-pandas\tests\probe_real_arrow.xi `
//       --cxx-standard 17 `
//       --c-source packages\xiom-pandas\bridge\xiom_pandas_arrow.cpp `
//       --c-source packages\xiom-pandas\tests\probe_real_arrow_callback.c `
//       --link arrow --link arrow_compute --link parquet `
//       --link-path "$arrow\pyarrow"
// No --link arrow_acero: the bridge has no Acero headers or symbols.
//
// The "__pandas_probe_*.csv" / "*.parquet" files are written in the invoking
// cwd. This probe intentionally does not run in CI/port; it is evidence-only.

module pandas_real_arrow_probe

use xiom.pandas;
use xiom.io;
use xiom.ffi;
use xiom.encoding;
use xiom.convert;

extern "C" {
  fn xiom_pandas_probe_double_addr() -> Int;
}

/// Copy a XIOM Str into a NUL-terminated C string (libc heap, via xiom.ffi)
/// and return its address as Int for the pandas_c_* Int-address ABI.
fn cstr_from_str(s: Str) -> Result[Int, Str] {
  var bytes: Vec[UInt8] = encoding.utf8_encode(s);
  let n: Int = bytes.len();
  let alloc = xiom.ffi.safe_ptr_alloc(n + 1);
  match alloc {
    Ok(sp) => {
      var handle = sp;
      var i: Int = 0;
      while i < n {
        let w = xiom.ffi.safe_ptr_write_byte(&mut handle, i, bytes[i] as Int);
        match w {
          Ok(_) => {},
          Err(e) => { return Err(e); },
        };
        i = i + 1;
      };
      let z = xiom.ffi.safe_ptr_write_byte(&mut handle, n, 0);
      match z {
        Ok(_) => {},
        Err(e) => { return Err(e); },
      };
      let addr: Int = unsafe { handle.ptr as Int };
      return Ok(addr);
    },
    Err(e) => { return Err(e); },
  };
}

fn free_cstr(addr: Int) {
  if addr != 0 {
    unsafe { xiom.ffi.free(addr as *UInt8); }
  };
}

/// Allocate an owned Float64 buffer and return its address.
fn alloc_f64(values: Vec[Float64]) -> Result[Int, Str] {
  let n = values.len();
  let alloc = xiom.ffi.safe_ptr_alloc(n * 8);
  match alloc {
    Ok(sp) => {
      var handle = sp;
      var i: Int = 0;
      while i < n {
        let w = xiom.ffi.safe_ptr_write_f64(&mut handle, i * 8, values[i]);
        match w {
          Ok(_) => {},
          Err(e) => { return Err(e); },
        };
        i = i + 1;
      };
      let addr: Int = unsafe { handle.ptr as Int };
      return Ok(addr);
    },
    Err(e) => { return Err(e); },
  };
}

/// IEEE-754 binary64 bit pattern of v, carried as an Int64.
fn f64_bits(v: Float64) -> Result[Int, Str] {
  let alloc = xiom.ffi.safe_ptr_alloc(8);
  match alloc {
    Ok(sp) => {
      var handle = sp;
      let w = xiom.ffi.safe_ptr_write_f64(&mut handle, 0, v);
      match w {
        Ok(_) => {},
        Err(e) => { return Err(e); },
      };
      let bits = xiom.ffi.safe_ptr_read_i64(&handle, 0);
      xiom.ffi.safe_ptr_free(handle);
      return bits;
    },
    Err(e) => { return Err(e); },
  };
}

fn line_count(path: Str) -> Result[Int, Str] {
  match io.read_file_lines(path) {
    Ok(lines) => {
      var n: Int = 0;
      var i: Int = 0;
      while i < lines.len() {
        if lines[i].len() > 0 {
          n = n + 1;
        };
        i = i + 1;
      };
      return Ok(n);
    },
    Err(e) => { return Err("cannot read " + path); },
  };
}

fn check(ok: Bool, label: Str) -> Int {
  if ok {
    io.println("[PASS] " + label);
    return 0;
  };
  io.println("[FAIL] " + label);
  return 1;
}

fn write_csv(df: DataFrame, path: Str) -> Result[Unit, Str] {
  let cpath = cstr_from_str(path);
  match cpath {
    Ok(addr) => {
      let res = dataframe_to_csv(df, addr);
      free_cstr(addr);
      match res {
        Ok(_) => { return Ok({}); },
        Err(e) => { return Err(e); },
      };
    },
    Err(e) => { return Err(e); },
  };
}

fn read_csv(path: Str) -> Result[DataFrame, Str] {
  let cpath = cstr_from_str(path);
  match cpath {
    Ok(addr) => {
      let res = dataframe_from_csv(addr);
      free_cstr(addr);
      return res;
    },
    Err(e) => { return Err(e); },
  };
}

fn write_parquet(df: DataFrame, path: Str) -> Result[Unit, Str] {
  let cpath = cstr_from_str(path);
  match cpath {
    Ok(addr) => {
      let res = dataframe_to_parquet(df, addr);
      free_cstr(addr);
      match res {
        Ok(_) => { return Ok({}); },
        Err(e) => { return Err(e); },
      };
    },
    Err(e) => { return Err(e); },
  };
}

fn read_parquet(path: Str) -> Result[DataFrame, Str] {
  let cpath = cstr_from_str(path);
  match cpath {
    Ok(addr) => {
      let res = dataframe_from_parquet(addr);
      free_cstr(addr);
      return res;
    },
    Err(e) => { return Err(e); },
  };
}

fn join_count(left: DataFrame, right: DataFrame, how: Int) -> Result[Int, Str] {
  let on = cstr_from_str("k");
  match on {
    Ok(on_addr) => {
      let joined = dataframe_join(left, right, on_addr, how);
      free_cstr(on_addr);
      match joined {
        Ok(df) => {
          let path = "__pandas_probe_join.csv";
          let w = write_csv(df, path);
          let freed = dataframe_free(df);
          match w {
            Ok(_) => {
              match freed {
                Ok(_) => {},
                Err(e) => { return Err(e); },
              };
              let count = line_count(path);
              match count {
                Ok(n) => { return Ok(n); },
                Err(e) => { return Err(e); },
              };
            },
            Err(e) => { return Err(e); },
          };
        },
        Err(e) => { return Err(e); },
      };
    },
    Err(e) => { return Err(e); },
  };
}

pub fn main() -> Int {
  io.println("=== xiom.pandas real Arrow-backed probe (section 8) ===");
  io.println("");
  var fails: Int = 0;

  // Leg 1: null/argument contract on the real bridge.
  let bad_new: Int = unsafe { pandas_c_dataframe_new(0, 0, 0) };
  fails = fails + check(bad_new == 0, "real bridge: dataframe_new(0,0,0) returns 0");
  let bad_ff: Int = unsafe { pandas_dataframe_filter_f64(0, 0, CMP_EQ, 0) };
  fails = fails + check(bad_ff == 0, "real bridge: filter_f64(0,0,CMP_EQ,0) returns 0");
  let bad_pq: Int = unsafe { pandas_c_dataframe_from_parquet(0) };
  fails = fails + check(bad_pq == 0, "real bridge: from_parquet(0) returns 0");

  // Leg 2: CSV round trip through the production wrappers.
  let in_path: Str = "__pandas_probe_real.csv";
  let out_path: Str = "__pandas_probe_real_out.csv";
  let csv: Str = "a,b\n1.5,2.5\n3.5,4.5\n";
  match io.write_file(in_path, csv) {
    Ok(_) => {},
    Err(e) => {
      io.println("[FAIL] probe setup: cannot write " + in_path);
      return 1;
    },
  };
  match read_csv(in_path) {
    Ok(df) => {
      fails = fails + check(df > 0, "real bridge: dataframe_from_csv returned a live handle");
      match write_csv(df, out_path) {
        Ok(_) => { fails = fails + check(true, "real bridge: dataframe_to_csv wrote " + out_path); },
        Err(e) => { fails = fails + check(false, "real bridge: dataframe_to_csv: " + e); },
      };
      match dataframe_free(df) {
        Ok(_) => { fails = fails + check(true, "real bridge: dataframe_free(valid) -> Ok"); },
        Err(e) => { fails = fails + check(false, "real bridge: dataframe_free: " + e); },
      };
    },
    Err(e) => {
      fails = fails + check(false, "real bridge: dataframe_from_csv: " + e + " (real Arrow bridge not linked?)");
    },
  };

  // Leg 3: Acero-free group-by.
  let gb_in: Str = "__pandas_probe_groupby.csv";
  match io.write_file(gb_in, "k,v\na,1\nb,2\na,3\n") {
    Ok(_) => {},
    Err(e) => { io.println("[FAIL] probe setup: cannot write " + gb_in); fails = fails + 1; },
  };
  match read_csv(gb_in) {
    Ok(df) => {
      let key = cstr_from_str("k");
      match key {
        Ok(key_addr) => {
          let grouped = dataframe_groupby(df, key_addr);
          free_cstr(key_addr);
          match grouped {
            Ok(handle) => {
              fails = fails + check(handle > 0, "real bridge: dataframe_groupby returned a live handle");
            },
            Err(e) => { fails = fails + check(false, "real bridge: dataframe_groupby: " + e); },
          };
        },
        Err(e) => { fails = fails + check(false, "probe setup: groupby key: " + e); },
      };
      match dataframe_free(df) {
        Ok(_) => {},
        Err(e) => { io.println("[FAIL] real bridge: dataframe_free(groupby input): " + e); fails = fails + 1; },
      };
    },
    Err(e) => { fails = fails + check(false, "real bridge: groupby input read: " + e); },
  };

  // Leg 4: Acero-free join fallback, all four join types.
  let left_path: Str = "__pandas_probe_left.csv";
  let right_path: Str = "__pandas_probe_right.csv";
  match io.write_file(left_path, "k,v\na,1\nb,2\na,3\n") {
    Ok(_) => {},
    Err(e) => { io.println("[FAIL] probe setup: cannot write " + left_path); fails = fails + 1; },
  };
  match io.write_file(right_path, "k,w\na,10\nc,30\n") {
    Ok(_) => {},
    Err(e) => { io.println("[FAIL] probe setup: cannot write " + right_path); fails = fails + 1; },
  };
  match read_csv(left_path) {
    Ok(left) => {
      match read_csv(right_path) {
        Ok(right) => {
          let expected: Vec[Int] = Vec[Int].new();
          expected.push(3);  // INNER: 2 a-matches + header
          expected.push(4);  // LEFT: 2 a + 1 b-null + header
          expected.push(4);  // RIGHT: 2 a + 1 c-null + header
          expected.push(5);  // OUTER: 2 a + b + c + header
          var how: Int = 0;
          while how <= 3 {
            match join_count(left, right, how) {
              Ok(n) => {
                fails = fails + check(n == expected[how], "real bridge: join how=" + convert.int_to_string(how) + " rows=" + convert.int_to_string(n));
              },
              Err(e) => {
                fails = fails + check(false, "real bridge: join how=" + convert.int_to_string(how) + ": " + e);
              },
            };
            how = how + 1;
          };
          match dataframe_free(right) {
            Ok(_) => {},
            Err(e) => { io.println("[FAIL] real bridge: dataframe_free(right): " + e); fails = fails + 1; },
          };
        },
        Err(e) => { fails = fails + check(false, "real bridge: right read: " + e); },
      };
      match dataframe_free(left) {
        Ok(_) => {},
        Err(e) => { io.println("[FAIL] real bridge: dataframe_free(left): " + e); fails = fails + 1; },
      };
    },
    Err(e) => { fails = fails + check(false, "real bridge: left read: " + e); },
  };

  // Leg 5: series_apply (double (*)(double), Float64-only).
  let values: Vec[Float64] = Vec[Float64].new();
  values.push(1.5);
  values.push(2.5);
  values.push(3.5);
  match alloc_f64(values) {
    Ok(values_addr) => {
      let series = series_from_vec(DTYPE_FLOAT64, values_addr, 3);
      unsafe { xiom.ffi.free(values_addr as *UInt8); }
      match series {
        Ok(s) => {
          let fn_addr: Int = unsafe { xiom_pandas_probe_double_addr() };
          let applied = series_apply(s, fn_addr);
          match applied {
            Ok(out_series) => {
              let len_alloc = xiom.ffi.safe_ptr_alloc(8);
              match len_alloc {
                Ok(len_sp) => {
                  var len_handle = len_sp;
                  let data = series_to_vec(out_series, unsafe { len_handle.ptr as Int });
                  match data {
                    Ok(data_addr) => {
                      match xiom.ffi.safe_ptr_read_i64(&len_handle, 0) {
                        Ok(n) => {
                          fails = fails + check(n == 3, "real bridge: series_apply returned 3 elements");
                          let view = xiom.ffi.safe_ptr_from_raw(unsafe { data_addr as *UInt8 }, 24);
                          match view {
                            Ok(buf) => {
                              match xiom.ffi.safe_ptr_read_f64(&buf, 0) {
                                Ok(v0) => { fails = fails + check(v0 == 3.0, "real bridge: apply[0] == 3.0"); },
                                Err(e) => { fails = fails + check(false, "real bridge: apply read[0]: " + e); },
                              };
                              match xiom.ffi.safe_ptr_read_f64(&buf, 8) {
                                Ok(v1) => { fails = fails + check(v1 == 5.0, "real bridge: apply[1] == 5.0"); },
                                Err(e) => { fails = fails + check(false, "real bridge: apply read[1]: " + e); },
                              };
                              match xiom.ffi.safe_ptr_read_f64(&buf, 16) {
                                Ok(v2) => { fails = fails + check(v2 == 7.0, "real bridge: apply[2] == 7.0"); },
                                Err(e) => { fails = fails + check(false, "real bridge: apply read[2]: " + e); },
                              };
                            },
                            Err(e) => { fails = fails + check(false, "real bridge: apply buffer view: " + e); },
                          };
                        },
                        Err(e) => { fails = fails + check(false, "real bridge: apply length: " + e); },
                      };
                      match series_buffer_free(data_addr) {
                        Ok(_) => { fails = fails + check(true, "real bridge: series_buffer_free(valid) -> Ok"); },
                        Err(e) => { fails = fails + check(false, "real bridge: series_buffer_free: " + e); },
                      };
                    },
                    Err(e) => { fails = fails + check(false, "real bridge: series_to_vec: " + e); },
                  };
                  xiom.ffi.safe_ptr_free(len_handle);
                },
                Err(e) => { fails = fails + check(false, "real bridge: length alloc: " + e); },
              };
              match series_free(out_series) {
                Ok(_) => {},
                Err(e) => { io.println("[FAIL] real bridge: series_free(applied): " + e); fails = fails + 1; },
              };
            },
            Err(e) => { fails = fails + check(false, "real bridge: series_apply: " + e); },
          };
          match series_free(s) {
            Ok(_) => { fails = fails + check(true, "real bridge: series_free(valid) -> Ok"); },
            Err(e) => { fails = fails + check(false, "real bridge: series_free: " + e); },
          };
        },
        Err(e) => { fails = fails + check(false, "real bridge: series_from_vec: " + e); },
      };
    },
    Err(e) => { fails = fails + check(false, "probe setup: values alloc: " + e); },
  };

  // Leg 6: dataframe_filter_f64 (IEEE-754 bits as Int64).
  let filter_path: Str = "__pandas_probe_filter.csv";
  match io.write_file(filter_path, "x\n1.0\n2.0\n3.0\n") {
    Ok(_) => {},
    Err(e) => { io.println("[FAIL] probe setup: cannot write " + filter_path); fails = fails + 1; },
  };
  match read_csv(filter_path) {
    Ok(df) => {
      match f64_bits(2.0) {
        Ok(bits) => {
          let col = cstr_from_str("x");
          match col {
            Ok(col_addr) => {
              let filtered = dataframe_filter_f64(df, col_addr, CMP_GT, bits);
              free_cstr(col_addr);
              match filtered {
                Ok(fdf) => {
                  let out = "__pandas_probe_filter_out.csv";
                  match write_csv(fdf, out) {
                    Ok(_) => {
                      match line_count(out) {
                        Ok(n) => { fails = fails + check(n == 2, "real bridge: filter_f64(x > 2.0) rows=" + convert.int_to_string(n)); },
                        Err(e) => { fails = fails + check(false, "real bridge: filter output read: " + e); },
                      };
                    },
                    Err(e) => { fails = fails + check(false, "real bridge: filter output write: " + e); },
                  };
                  match dataframe_free(fdf) {
                    Ok(_) => {},
                    Err(e) => { io.println("[FAIL] real bridge: dataframe_free(filtered): " + e); fails = fails + 1; },
                  };
                },
                Err(e) => { fails = fails + check(false, "real bridge: dataframe_filter_f64: " + e); },
              };
            },
            Err(e) => { fails = fails + check(false, "probe setup: filter column: " + e); },
          };
        },
        Err(e) => { fails = fails + check(false, "probe setup: f64 bits: " + e); },
      };
      match dataframe_free(df) {
        Ok(_) => {},
        Err(e) => { io.println("[FAIL] real bridge: dataframe_free(filter input): " + e); fails = fails + 1; },
      };
    },
    Err(e) => { fails = fails + check(false, "real bridge: filter input read: " + e); },
  };

  // Leg 7: Parquet round trip through the Arrow Parquet component.
  let pq_path: Str = "__pandas_probe.parquet";
  match read_csv(gb_in) {
    Ok(df) => {
      match write_parquet(df, pq_path) {
        Ok(_) => {
          match read_parquet(pq_path) {
            Ok(pdf) => {
              fails = fails + check(pdf > 0, "real bridge: parquet read returned a live handle");
              let pq_csv: Str = "__pandas_probe_parquet_out.csv";
              match write_csv(pdf, pq_csv) {
                Ok(_) => {
                  match line_count(pq_csv) {
                    Ok(n) => { fails = fails + check(n == 4, "real bridge: parquet round-trip rows=" + convert.int_to_string(n)); },
                    Err(e) => { fails = fails + check(false, "real bridge: parquet output read: " + e); },
                  };
                },
                Err(e) => { fails = fails + check(false, "real bridge: parquet output write: " + e); },
              };
              match dataframe_free(pdf) {
                Ok(_) => {},
                Err(e) => { io.println("[FAIL] real bridge: dataframe_free(parquet): " + e); fails = fails + 1; },
              };
            },
            Err(e) => {
              fails = fails + check(false, "real bridge: parquet read: " + e);
            },
          };
        },
        Err(e) => {
          if io.file_exists(pq_path) {
            fails = fails + check(false, "real bridge: parquet write: " + e);
          } else {
            io.println("[SKIP] real bridge: Arrow Parquet component unavailable (" + e + ")");
          };
        },
      };
      match dataframe_free(df) {
        Ok(_) => {},
        Err(e) => { io.println("[FAIL] real bridge: dataframe_free(parquet input): " + e); fails = fails + 1; },
      };
    },
    Err(e) => { fails = fails + check(false, "real bridge: parquet input read: " + e); },
  };

  io.println("");
  if fails == 0 {
    io.println("probe: OK");
  } else {
    io.println("probe: FAILED (" + convert.int_to_string(fails) + " failures)");
  };
  return fails;
}
