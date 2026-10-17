// xiom.optix conformance suite -- OptiX runtime loader, typed errors,
// device context, module, program groups, SBT, pipeline and launch params.
//
// Live checks run against the user's nvoptix.dll (NVIDIA display driver);
// they classify LOADER_ABSENT / NO_DEVICE as SKIP (green) so CI without an
// NVIDIA GPU stays green.  An ABI mismatch is a FAIL (the runtime is present
// but incompatible).
//
// Build+run (the C bridge rides in port.args.json):
//   scripts/port.ps1 -Package xiom.optix -TimeoutSec 300

module optix_conformance

use xiom.io;
use xiom.string;
use xiom.test;
use xiom.optix;

fn report(ok: Bool, name: Str) -> Int {
  if ok {
    io.println("  [PASS] " + name);
    io.flush_stdout();
    return 0;
  }
  io.println("  [FAIL] " + name);
  io.flush_stdout();
  return 1;
}

fn default_options() -> OptixContextOptions
  requires: true
{
  return OptixContextOptions{
    validation_mode: false;
    log_level: 0;
    cache_enabled: true;
    cache_location: "";
  };
}

fn check_error_surface() -> Int
  requires: true
{
  var failed = 0;
  let skip_err = OptixError{ kind: OPTIX_ERR_LOADER_ABSENT; code: 0; message: "x" };
  let abi_err = OptixError{ kind: OPTIX_ERR_ABI; code: 7801; message: "x" };
  failed = failed + report(optix_error_kind_name(OPTIX_ERR_PIPELINE) == "pipeline",
    "errors: kind name for pipeline");
  failed = failed + report(optix_error_is_skip(skip_err),
    "errors: loader-absent is SKIP");
  failed = failed + report(!optix_error_is_skip(abi_err),
    "errors: ABI mismatch is not SKIP");
  return failed;
}

fn check_sbt_size_math() -> Int
  requires: true
{
  var failed = 0;
  failed = failed + report(optix_sbt_record_size_for(1) == 32,
    "sbt: record size floor is the 32-byte header");
  failed = failed + report(optix_sbt_record_size_for(32) == 32,
    "sbt: 32-byte record stays 32");
  failed = failed + report(optix_sbt_record_size_for(33) == 48,
    "sbt: 33-byte record rounds to 48");
  return failed;
}

fn check_context_lifecycle() -> Int
  requires: true
{
  var failed = 0;
  let created = optix_context_create(default_options());
  if !created.is_ok {
    return report(false, "context: create failed -- " + created.error.message);
  }
  let validated = optix_context_validate(created.value);
  if validated.is_ok {
    failed = failed + report(validated.value.abi_version == OPTIX_ABI_PIN,
      "context: ABI pin reported");
    failed = failed + report(validated.value.rtcore_version > 0,
      "context: RT core version reported");
    failed = failed + report(validated.value.max_trace_depth > 0,
      "context: max trace depth reported");
    failed = failed + report(validated.value.cache_enabled,
      "context: disk cache enabled");
    failed = failed + report(validated.value.device_name.len() > 0,
      "context: device name reported");
  } else {
    failed = failed + report(false, "context: validate failed -- " + validated.error.message);
  }
  failed = failed + report(optix_context_destroy(created.value),
    "context: destroy");
  return failed;
}

fn check_context_options() -> Int
  requires: true
{
  var failed = 0;
  let options = OptixContextOptions{
    validation_mode: true;
    log_level: 2;
    cache_enabled: false;
    cache_location: "";
  };
  let created = optix_context_create(options);
  if !created.is_ok {
    return report(false, "options: create failed -- " + created.error.message);
  }
  let validated = optix_context_validate(created.value);
  if validated.is_ok {
    failed = failed + report(!validated.value.cache_enabled,
      "options: validation-mode context honors cache_enabled=false");
  } else {
    failed = failed + report(false, "options: validate failed -- " + validated.error.message);
  }
  failed = failed + report(optix_context_destroy(created.value),
    "options: destroy");
  return failed;
}

fn check_module_error() -> Int
  requires: true
{
  let created = optix_context_create(default_options());
  if !created.is_ok {
    return report(false, "module: context create failed -- " + created.error.message);
  }
  var failed = 0;
  let mod_result = optix_module_load(created.value, "not ptx", "params", 16);
  if mod_result.is_ok {
    failed = failed + report(false, "module: invalid PTX unexpectedly compiled");
    failed = failed + report(optix_module_destroy(mod_result.value), "module: destroy");
  } else {
    failed = failed + report(mod_result.error.kind == OPTIX_ERR_MODULE,
      "module: invalid PTX classified as module error");
    failed = failed + report(mod_result.error.code != 0,
      "module: native OptiX code carried");
    failed = failed + report(string.str_contains(mod_result.error.message, "COMPILE ERROR"),
      "module: compiler log carried");
  }
  failed = failed + report(optix_context_destroy(created.value), "module: context destroy");
  return failed;
}

fn check_sbt_and_groups() -> Int
  requires: true
{
  let created = optix_context_create(default_options());
  if !created.is_ok {
    return report(false, "sbt: context create failed -- " + created.error.message);
  }
  var failed = 0;
  let none = optix_program_group_none();
  let miss = optix_program_group_create(created.value, OptixModule{ handle: 0 }, "", OPTIX_PROGRAM_GROUP_MISS);
  if !miss.is_ok {
    failed = failed + report(false, "sbt: miss group create failed -- " + miss.error.message);
    failed = failed + report(optix_context_destroy(created.value), "sbt: context destroy");
    return failed;
  }
  let sbt = optix_sbt_build(created.value, none, miss.value, none, 64);
  if sbt.is_ok {
    failed = failed + report(optix_sbt_get_record_size(sbt.value) == 64,
      "sbt: record size is the aligned request");
    failed = failed + report(optix_sbt_get_record_count(sbt.value) == 1,
      "sbt: one record packed");
    var record: Vec[UInt8] = Vec[UInt8].new();
    var i = 0;
    while i < 16 {
      record.push(0 as UInt8);
      i = i + 1;
    }
    let read = optix_sbt_read_record(sbt.value, 0, &mut record);
    if read.is_ok {
      var nonzero = false;
      var j = 0;
      while j < record.len() {
        if record[j] != (0 as UInt8) {
          nonzero = true;
        }
        j = j + 1;
      }
      failed = failed + report(nonzero,
        "sbt: packed header is non-zero (device readback)");
    } else {
      failed = failed + report(false, "sbt: record readback failed -- " + read.error.message);
    }
    failed = failed + report(optix_sbt_destroy(sbt.value), "sbt: destroy");
  } else {
    failed = failed + report(false, "sbt: build failed -- " + sbt.error.message);
  }
  failed = failed + report(optix_program_group_destroy(miss.value), "sbt: miss group destroy");
  failed = failed + report(optix_context_destroy(created.value), "sbt: context destroy");
  return failed;
}

fn check_pipeline_validation() -> Int
  requires: true
{
  let created = optix_context_create(default_options());
  if !created.is_ok {
    return report(false, "pipeline: context create failed -- " + created.error.message);
  }
  var failed = 0;
  let miss = optix_program_group_create(created.value, OptixModule{ handle: 0 }, "", OPTIX_PROGRAM_GROUP_MISS);
  if !miss.is_ok {
    failed = failed + report(false, "pipeline: miss group create failed -- " + miss.error.message);
    failed = failed + report(optix_context_destroy(created.value), "pipeline: context destroy");
    return failed;
  }
  let none = optix_program_group_none();
  let pipeline = optix_pipeline_create(created.value, none, miss.value, none,
    "params", 16, 1);
  if pipeline.is_ok {
    failed = failed + report(false, "pipeline: raygen-less pipeline unexpectedly linked");
    failed = failed + report(optix_pipeline_destroy(pipeline.value), "pipeline: destroy");
  } else {
    failed = failed + report(pipeline.error.kind == OPTIX_ERR_PIPELINE,
      "pipeline: link failure classified as pipeline error");
    failed = failed + report(string.str_contains(pipeline.error.message, "raygen"),
      "pipeline: runtime validation log carried");
  }
  failed = failed + report(optix_program_group_destroy(miss.value), "pipeline: miss group destroy");
  failed = failed + report(optix_context_destroy(created.value), "pipeline: context destroy");
  return failed;
}

fn check_params_roundtrip() -> Int
  requires: true
{
  let created = optix_context_create(default_options());
  if !created.is_ok {
    return report(false, "params: context create failed -- " + created.error.message);
  }
  var failed = 0;
  let params = optix_params_create(created.value, 64);
  if params.is_ok {
    var pattern: Vec[UInt8] = Vec[UInt8].new();
    var i = 0;
    while i < 64 {
      pattern.push((((i * 7) + 3) % 256) as UInt8);
      i = i + 1;
    }
    let wrote = optix_params_write(params.value, &pattern);
    if wrote.is_ok {
      var back: Vec[UInt8] = Vec[UInt8].new();
      var j = 0;
      while j < 64 {
        back.push(0 as UInt8);
        j = j + 1;
      }
      let read = optix_params_read(params.value, &mut back);
      if read.is_ok {
        var same = true;
        var k = 0;
        while k < 64 {
          if pattern[k] != back[k] {
            same = false;
          }
          k = k + 1;
        }
        failed = failed + report(same, "params: host -> device -> host round trip");
      } else {
        failed = failed + report(false, "params: read failed -- " + read.error.message);
      }
    } else {
      failed = failed + report(false, "params: write failed -- " + wrote.error.message);
    }
    failed = failed + report(optix_params_destroy(params.value), "params: destroy");
  } else {
    failed = failed + report(false, "params: create failed -- " + params.error.message);
  }
  failed = failed + report(optix_context_destroy(created.value), "params: context destroy");
  return failed;
}

fn main() -> Int {
  io.println("=== xiom.optix conformance tests (OptiX runtime loader, ABI 118) ===");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + report(OPTIX_ABI_PIN == 118, "pin: ABI 118");
  failed = failed + check_error_surface();
  failed = failed + check_sbt_size_math();

  // Deterministic SKIP path: an explicit bogus runtime path must be
  // classified LOADER_ABSENT on every host.
  let missing = optix_probe_named("xiom-absent-optix-probe-xyz.dll", false);
  if missing.is_ok {
    failed = failed + report(false, "probe: bogus runtime path unexpectedly succeeded");
  } else {
    failed = failed + report(missing.error.kind == OPTIX_ERR_LOADER_ABSENT,
      "probe: missing runtime classified as LOADER_ABSENT (SKIP)");
  }

  // Live probe (or SKIP without the NVIDIA driver runtime / GPU).
  let probe = optix_probe();
  var live = false;
  if probe.is_ok {
    live = true;
    failed = failed + report(probe.value.abi_version == OPTIX_ABI_PIN,
      "probe: ABI 118 negotiated");
    failed = failed + report(probe.value.rtcore_version > 0,
      "probe: RT core version");
    failed = failed + report(probe.value.max_trace_depth > 0,
      "probe: max trace depth");
    failed = failed + report(probe.value.device_name.len() > 0,
      "probe: device name");
  } else {
    if optix_error_is_skip(probe.error) {
      failed = failed + report(true, "probe: SKIP -- " + probe.error.message);
    } else {
      failed = failed + report(false, "probe: failed -- " + probe.error.message);
    }
  }

  if live {
    failed = failed + check_context_lifecycle();
    failed = failed + check_context_options();
    failed = failed + check_module_error();
    failed = failed + check_sbt_and_groups();
    failed = failed + check_pipeline_validation();
    failed = failed + check_params_roundtrip();
  } else {
    failed = failed + report(true, "context: SKIP -- runtime absent");
    failed = failed + report(true, "options: SKIP -- runtime absent");
    failed = failed + report(true, "module: SKIP -- runtime absent");
    failed = failed + report(true, "sbt: SKIP -- runtime absent");
    failed = failed + report(true, "pipeline: SKIP -- runtime absent");
    failed = failed + report(true, "params: SKIP -- runtime absent");
  }

  if failed == 0 {
    io.println("xiom.optix: all tests passed");
  } else {
    io.println("xiom.optix: tests failed");
  }
  return failed;
}

