// XIOM -- xiom.blas.runtime: typed OpenBLAS runtime availability classification.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// The rules implemented here MIRROR the canonical loader in
// `xiom.openblas` (packages/xiom-openblas/tests/probe_openblas_shim.c,
// live in eco-v0.1.193): candidate order = XIOM_OPENBLAS_LIB override,
// then standard install locations, then bare sonames through the OS loader
// search order; a candidate wins only when it loads AND exports both
// cblas_ddot and cblas_dgemm. The BLAS runtime itself ships entirely via
// xiom.openblas -- nothing is vendored or linked here; this module only
// classifies presence/absence for the safe layer's SKIP discipline.
//
// Classification (typed, stable constants):
//   BLAS_RT_ABSENT  -> no candidate resolved          -> SKIP
//   BLAS_RT_PRESENT -> library loaded, symbols export -> present path
//   BLAS_RT_ABI     -> loaded, required names missing -> FAIL (loud)
//
// No `unsafe` is used: `xiom.ffi.dl` resolves handles and symbol presence
// only (no calls through the loaded library -- the real numerical exercise
// lives in tests/probe_real_blas.xi via the xiom.openblas probe shim, which
// performs the cblas_* calls in C where Float64 returns are reliable on the
// v0.64.5 toolchain).

module xiom.blas.runtime

use xiom.ffi.dl;
use xiom.os.env;

/// No candidate library resolved -> callers report SKIP.
pub const BLAS_RT_ABSENT: Int = 0;

/// A library loaded AND exports the required entry points -> present path.
pub const BLAS_RT_PRESENT: Int = 1;

/// A library loaded but the required entry points are missing -> FAIL
/// (a real install/ABI mismatch, never a silent skip).
pub const BLAS_RT_ABI: Int = 2;

/// Entry points the xiom.openblas seam requires (same pair the canonical
/// probe checks in probe_openblas_shim.c).
pub const BLAS_RT_SYMBOL_1: Str = "cblas_ddot";
pub const BLAS_RT_SYMBOL_2: Str = "cblas_dgemm";

/// Environment override consulted first (canonical rule 1).
pub const BLAS_RT_ENV_OVERRIDE: Str = "XIOM_OPENBLAS_LIB";

pub type RuntimeProbe = {
  kind: Int;
  path: Str;
  message: Str;
}

fn __absent(path: Str, message: Str) -> RuntimeProbe {
  return RuntimeProbe{ kind: BLAS_RT_ABSENT, path: path, message: message };
}

fn __present(path: Str) -> RuntimeProbe {
  return RuntimeProbe{ kind: BLAS_RT_PRESENT, path: path, message: "" };
}

fn __abi(path: Str, message: Str) -> RuntimeProbe {
  return RuntimeProbe{ kind: BLAS_RT_ABI, path: path, message: message };
}

/// Classify a single candidate path/soname. Never leaves a handle open:
/// present candidates are closed right after symbol classification (the
/// probe is a classifier, not a user of the library).
pub fn runtime_probe_named(path: Str) -> RuntimeProbe
  requires: path.len() > 0
{
  match dl.dl_open(path) {
    Ok(h) => {
      let has1 = dl.dl_has_symbol(h, BLAS_RT_SYMBOL_1);
      let has2 = dl.dl_has_symbol(h, BLAS_RT_SYMBOL_2);
      match dl.dl_close(h) {
        Ok(_) => { }
        Err(_) => { }
      };
      if has1 && has2 {
        return __present(path);
      };
      return __abi(path, "loaded but does not export " + BLAS_RT_SYMBOL_1 + " + " + BLAS_RT_SYMBOL_2);
    }
    Err(e) => {
      return __absent(path, e);
    }
  }
}

fn __try_list(cands: &Vec[Str], i: Int, abi_path: Str, abi_msg: Str, saw_abi: Bool) -> RuntimeProbe
  requires: i >= 0
{
  var idx = i;
  var abi_p = abi_path;
  var abi_m = abi_msg;
  var saw = saw_abi;
  while idx < cands.len() {
    let r = runtime_probe_named(cands[idx]);
    if r.kind == BLAS_RT_PRESENT {
      return r;
    };
    if r.kind == BLAS_RT_ABI {
      saw = true;
      abi_p = r.path;
      abi_m = r.message;
    };
    idx = idx + 1;
  };
  if saw {
    return __abi(abi_p, abi_m);
  };
  return __absent(abi_p, abi_m);
}

fn __candidates() -> Vec[Str]
  ensures: result.len() > 0
{
  var cands = Vec[Str].new();
  if env.host_is_windows() {
    cands.push("C:\\OpenBLAS\\lib\\libopenblas.dll");
    cands.push("C:\\OpenBLAS\\bin\\libopenblas.dll");
    cands.push("C:\\OpenBLAS\\libopenblas.dll");
    cands.push("C:\\Program Files\\OpenBLAS\\lib\\libopenblas.dll");
    cands.push("C:\\Program Files\\OpenBLAS\\bin\\libopenblas.dll");
    cands.push("C:\\msys64\\mingw64\\bin\\libopenblas.dll");
    cands.push("C:\\tools\\msys64\\mingw64\\bin\\libopenblas.dll");
    cands.push("C:\\ProgramData\\chocolatey\\bin\\libopenblas.dll");
    cands.push("libopenblas.dll");
    cands.push("openblas64_.dll");
    cands.push("openblas.dll");
  } else {
    cands.push("/usr/local/lib/libopenblas.so");
    cands.push("/usr/lib/libopenblas.so");
    cands.push("/usr/lib/x86_64-linux-gnu/libopenblas.so");
    cands.push("/opt/OpenBLAS/lib/libopenblas.so");
    cands.push("libopenblas.so");
    cands.push("libopenblas.so.0");
  };
  return cands;
}

/// Full canonical ruleset: env override first, then the standard install
/// locations, then bare sonames (OS loader search order). Returns the first
/// PRESENT candidate; otherwise ABI if any candidate loaded without the
/// required exports; otherwise ABSENT.
pub fn runtime_probe() -> RuntimeProbe {
  let override_path = env.var_or(BLAS_RT_ENV_OVERRIDE, "");
  if override_path.len() > 0 {
    let r = runtime_probe_named(override_path);
    if r.kind == BLAS_RT_PRESENT {
      return r;
    };
    if r.kind == BLAS_RT_ABI {
      return r;
    };
  };
  let cands = __candidates();
  return __try_list(&cands, 0, "", "", false);
}
