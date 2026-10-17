// probe_real_arrow.xi -- optional REAL Arrow-backed pandas bridge probe.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// NOT part of port.ps1 -- the conformance suite stays offline via
// bridge/pandas_bridge.c (stub). This probe links the production xiom.pandas
// surface against the REAL Arrow-backed bridge to prove, once the bindings
// lane ships it (see bridge/REAL-BACKEND-REQUIREMENTS.md):
//   1. the pandas_c_* symbols resolve against the real C++ bridge, and its
//      null-argument semantics match the stub contract (0 in -> 0 out);
//   2. a REAL round trip: a CSV file written by plain XIOM is read into a
//      live Arrow-backed DataFrame handle and written back out.
// Running this probe WITHOUT the real bridge (e.g. with the stub) fails by
// design: the CSV leg reports the backend-unavailable error.
//
// Local invocation sketch (paths resolved locally; binaries stay in %TEMP%):
//   1. system-install Apache Arrow C++ (headers + libs) per xiom.arrow;
//   2. build the real bridge bridge/xiom_pandas_arrow.cpp into
//      xiom_pandas_arrow.lib/.a (toolchain + flags in the requirements doc;
//      the C++ ABI must match the Arrow build);
//   3. from the repo root:
//        xiom --run packages\xiom-pandas\tests\probe_real_arrow.xi `
//            --c-source packages\xiom-pandas\bridge\xiom_pandas_arrow.cpp `
//            --link arrow --link-path <arrow-lib-dir>
//   (add --link parquet for the parquet leg once implemented)
//
// The two "__pandas_probe_*.csv" files are written in the invoking cwd.
//
// This probe intentionally does not run in CI/port; it is evidence-only.

module pandas_real_arrow_probe

use xiom.pandas;
use xiom.io;
use xiom.ffi;
use xiom.encoding;
use xiom.convert;

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
      }
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

pub fn main() -> Int {
  // Leg 1: null-safety on the real bridge (raw extern contract).
  let bad: Int = unsafe { pandas_c_dataframe_new(0, 0, 0) };
  if bad != 0 {
    io.println("[FAIL] real bridge: dataframe_new(0,0,0) returned a non-zero handle");
    return 1;
  };
  io.println("[PASS] real bridge: null params rejected with 0");

  // Leg 2: real CSV round trip through the production wrappers.
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

  let in_cstr = cstr_from_str(in_path);
  match in_cstr {
    Ok(path_addr) => {
      var res: Result[DataFrame, Str] = dataframe_from_csv(path_addr);
      match res {
        Ok(df) => {
          if df <= 0 {
            io.println("[FAIL] real bridge: dataframe_from_csv returned a non-positive handle");
            return 1;
          };
          io.println("[PASS] real bridge: dataframe_from_csv returned a live handle");
          let out_cstr = cstr_from_str(out_path);
          match out_cstr {
            Ok(out_addr) => {
              var wres: Result[Int, Str] = dataframe_to_csv(df, out_addr);
              match wres {
                Ok(_) => {
                  io.println("[PASS] real bridge: dataframe_to_csv wrote " + out_path);
                  return 0;
                },
                Err(e) => {
                  io.println("[FAIL] real bridge dataframe_to_csv: " + e);
                  return 1;
                },
              };
            },
            Err(e) => {
              io.println("[FAIL] probe setup: cstr for out path: " + e);
              return 1;
            },
          };
        },
        Err(e) => {
          io.println("[FAIL] real bridge dataframe_from_csv: " + e + " (real Arrow bridge not linked?)");
          return 1;
        },
      };
    },
    Err(e) => {
      io.println("[FAIL] probe setup: cstr for in path: " + e);
      return 1;
    },
  };
}
