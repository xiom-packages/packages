// XIOM -- xiom.gcp.cloudfunctions: Cloud Functions deploy/invoke model
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM MODEL of the Cloud Functions surface: the runtime registry with
// language and generation classification, entry-point (handler) validation,
// HTTP vs event trigger shapes, a deploy-request validator and the invoke
// outcome classifier plus the gen1 HTTP URL shape. No network, no FFI.
//
// Documented subset:
//   * runtimes: nodejs20/22, python310/311/312, go121/122, java17/21,
//     dotnet6/8, ruby32, php82.
//   * entry points: 1..63 characters, ASCII letter or '_' first, then ASCII
//     letters/digits/'_'.
//   * HTTP triggers carry no event type/resource and no retry policy; event
//     triggers require a dotted event type and a resource path containing '/'.
//   * deploy limits: memory 128..32768 MB; timeout 1..3600 s for HTTP and
//     1..540 s for event triggers; max_instances 0..1000 (0 = unset).
//   * invoke classification: 2xx without error flag = OK, 2xx with error flag
//     = APP_ERROR, 429/503 = RETRY, everything else = FAIL, non-HTTP status
//     = UNKNOWN.
//   * gen1 URL: https://{region}-{project}.cloudfunctions.net/{name}.
//
// v0.62.2 discipline: free functions only; Str equality via
// xiom.string.compare; bounded loops.

module xiom.gcp.cloudfunctions

use xiom.gcp.core;
use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Runtime registry
// --------------------------------------------------

/// Unknown runtime (0).
pub const GCF_RUNTIME_UNKNOWN: Int = 0;

/// nodejs20 (1).
pub const GCF_RUNTIME_NODEJS20: Int = 1;

/// nodejs22 (2).
pub const GCF_RUNTIME_NODEJS22: Int = 2;

/// python310 (3).
pub const GCF_RUNTIME_PYTHON310: Int = 3;

/// python311 (4).
pub const GCF_RUNTIME_PYTHON311: Int = 4;

/// python312 (5).
pub const GCF_RUNTIME_PYTHON312: Int = 5;

/// go121 (6).
pub const GCF_RUNTIME_GO121: Int = 6;

/// go122 (7).
pub const GCF_RUNTIME_GO122: Int = 7;

/// java17 (8).
pub const GCF_RUNTIME_JAVA17: Int = 8;

/// java21 (9).
pub const GCF_RUNTIME_JAVA21: Int = 9;

/// dotnet6 (10).
pub const GCF_RUNTIME_DOTNET6: Int = 10;

/// dotnet8 (11).
pub const GCF_RUNTIME_DOTNET8: Int = 11;

/// ruby32 (12).
pub const GCF_RUNTIME_RUBY32: Int = 12;

/// php82 (13).
pub const GCF_RUNTIME_PHP82: Int = 13;

/// Highest modeled runtime code (13).
pub const GCF_RUNTIME_MAX: Int = 13;

// --------------------------------------------------
//  Trigger kinds and invoke classes
// --------------------------------------------------

/// Unknown trigger kind (0).
pub const GCF_TRIGGER_UNKNOWN: Int = 0;

/// HTTP trigger (1).
pub const GCF_TRIGGER_HTTP: Int = 1;

/// Event trigger (2).
pub const GCF_TRIGGER_EVENT: Int = 2;

/// Unknown invoke outcome (0).
pub const GCF_INVOKE_UNKNOWN: Int = 0;

/// Successful invoke (1).
pub const GCF_INVOKE_OK: Int = 1;

/// Function-reported application error (2).
pub const GCF_INVOKE_APP_ERROR: Int = 2;

/// Transient failure, retryable (3).
pub const GCF_INVOKE_RETRY: Int = 3;

/// Permanent failure (4).
pub const GCF_INVOKE_FAIL: Int = 4;

// --------------------------------------------------
//  Types
// --------------------------------------------------

/// A deploy request as modeled before the API call; trigger fields are carried
/// inline so the validator can check their interaction with the kind.
pub type GcfDeploy = {
  name: Str;
  runtime: Str;
  entry_point: Str;
  memory_mb: Int;
  timeout_sec: Int;
  max_instances: Int;
  trigger_kind: Int;
  event_type: Str;
  resource: Str;
  retry: Bool;
}

// --------------------------------------------------
//  Result constructors (leaf helpers only)
// --------------------------------------------------

fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Runtimes
// --------------------------------------------------

/// Map a runtime name to its GCF_RUNTIME_* code (0 = unknown). Params: runtime
/// - the runtime name. Complexity O(runtime.len()).
pub fn gcf_runtime_code(runtime: Str) -> Int {
  if core.gcp_str_eq(runtime, "nodejs20") {
    return GCF_RUNTIME_NODEJS20;
  }
  if core.gcp_str_eq(runtime, "nodejs22") {
    return GCF_RUNTIME_NODEJS22;
  }
  if core.gcp_str_eq(runtime, "python310") {
    return GCF_RUNTIME_PYTHON310;
  }
  if core.gcp_str_eq(runtime, "python311") {
    return GCF_RUNTIME_PYTHON311;
  }
  if core.gcp_str_eq(runtime, "python312") {
    return GCF_RUNTIME_PYTHON312;
  }
  if core.gcp_str_eq(runtime, "go121") {
    return GCF_RUNTIME_GO121;
  }
  if core.gcp_str_eq(runtime, "go122") {
    return GCF_RUNTIME_GO122;
  }
  if core.gcp_str_eq(runtime, "java17") {
    return GCF_RUNTIME_JAVA17;
  }
  if core.gcp_str_eq(runtime, "java21") {
    return GCF_RUNTIME_JAVA21;
  }
  if core.gcp_str_eq(runtime, "dotnet6") {
    return GCF_RUNTIME_DOTNET6;
  }
  if core.gcp_str_eq(runtime, "dotnet8") {
    return GCF_RUNTIME_DOTNET8;
  }
  if core.gcp_str_eq(runtime, "ruby32") {
    return GCF_RUNTIME_RUBY32;
  }
  if core.gcp_str_eq(runtime, "php82") {
    return GCF_RUNTIME_PHP82;
  }
  return GCF_RUNTIME_UNKNOWN;
}

/// True for a modeled runtime name. Params: runtime - the candidate.
/// Complexity O(runtime.len()).
pub fn gcf_runtime_is_valid(runtime: Str) -> Bool {
  return gcf_runtime_code(runtime) != GCF_RUNTIME_UNKNOWN;
}

/// Canonical runtime name for a code. Params: code - a GCF_RUNTIME_* code.
/// Returns the name or an "unknown runtime code" error. Complexity O(1).
pub fn gcf_runtime_name(code: Int) -> Result[Str, Str] {
  if code == GCF_RUNTIME_NODEJS20 {
    return _ok_str("nodejs20");
  }
  if code == GCF_RUNTIME_NODEJS22 {
    return _ok_str("nodejs22");
  }
  if code == GCF_RUNTIME_PYTHON310 {
    return _ok_str("python310");
  }
  if code == GCF_RUNTIME_PYTHON311 {
    return _ok_str("python311");
  }
  if code == GCF_RUNTIME_PYTHON312 {
    return _ok_str("python312");
  }
  if code == GCF_RUNTIME_GO121 {
    return _ok_str("go121");
  }
  if code == GCF_RUNTIME_GO122 {
    return _ok_str("go122");
  }
  if code == GCF_RUNTIME_JAVA17 {
    return _ok_str("java17");
  }
  if code == GCF_RUNTIME_JAVA21 {
    return _ok_str("java21");
  }
  if code == GCF_RUNTIME_DOTNET6 {
    return _ok_str("dotnet6");
  }
  if code == GCF_RUNTIME_DOTNET8 {
    return _ok_str("dotnet8");
  }
  if code == GCF_RUNTIME_RUBY32 {
    return _ok_str("ruby32");
  }
  if code == GCF_RUNTIME_PHP82 {
    return _ok_str("php82");
  }
  return _err_str("gcp: unknown runtime code: " + core.gcp_int_str(code));
}

/// Language family of a runtime. Params: runtime - the runtime name. Returns
/// the language or an "invalid runtime" error. Complexity O(runtime.len()).
pub fn gcf_runtime_language(runtime: Str) -> Result[Str, Str] {
  let code = gcf_runtime_code(runtime);
  if code == GCF_RUNTIME_UNKNOWN {
    return _err_str("gcp: invalid runtime: " + runtime);
  }
  if code == GCF_RUNTIME_NODEJS20 || code == GCF_RUNTIME_NODEJS22 {
    return _ok_str("nodejs");
  }
  if code == GCF_RUNTIME_PYTHON310 || code == GCF_RUNTIME_PYTHON311 || code == GCF_RUNTIME_PYTHON312 {
    return _ok_str("python");
  }
  if code == GCF_RUNTIME_GO121 || code == GCF_RUNTIME_GO122 {
    return _ok_str("go");
  }
  if code == GCF_RUNTIME_JAVA17 || code == GCF_RUNTIME_JAVA21 {
    return _ok_str("java");
  }
  if code == GCF_RUNTIME_DOTNET6 || code == GCF_RUNTIME_DOTNET8 {
    return _ok_str("dotnet");
  }
  if code == GCF_RUNTIME_RUBY32 {
    return _ok_str("ruby");
  }
  return _ok_str("php");
}

/// True when the modeled subset marks the runtime as gen2-capable. Params:
/// runtime - the runtime name. Complexity O(runtime.len()).
pub fn gcf_runtime_is_gen2(runtime: Str) -> Bool {
  if core.gcp_str_eq(runtime, "nodejs20") {
    return true;
  }
  if core.gcp_str_eq(runtime, "nodejs22") {
    return true;
  }
  if core.gcp_str_eq(runtime, "python312") {
    return true;
  }
  if core.gcp_str_eq(runtime, "go122") {
    return true;
  }
  if core.gcp_str_eq(runtime, "java21") {
    return true;
  }
  if core.gcp_str_eq(runtime, "dotnet8") {
    return true;
  }
  if core.gcp_str_eq(runtime, "php82") {
    return true;
  }
  return false;
}

/// True for a documented-subset entry point (handler). Params: entry_point -
/// the candidate. Complexity O(entry_point.len()).
pub fn gcf_entry_point_is_valid(entry_point: Str) -> Bool {
  let n = entry_point.len();
  if n < 1 {
    return false;
  }
  if n > 63 {
    return false;
  }
  let first = core.gcp_byte(entry_point, 0);
  if !core.gcp_is_alpha(first) {
    if first != 95 {
      return false;
    }
  }
  var i = 1;
  while i < n {
    let c = core.gcp_byte(entry_point, i);
    if !core.gcp_is_alnum(c) {
      if c != 95 {
        return false;
      }
    }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Triggers
// --------------------------------------------------

/// Validate the trigger shape. Params: kind - GCF_TRIGGER_*; event_type - the
/// event type for event triggers; resource - the resource path for event
/// triggers; retry - the retry policy flag. Returns Ok("") or the first error.
/// Complexity O(len).
pub fn gcf_trigger_validate(kind: Int, event_type: Str, resource: Str, retry: Bool) -> Result[Str, Str] {
  if kind == GCF_TRIGGER_HTTP {
    if event_type.len() != 0 {
      return _err_str("gcp: HTTP trigger must not carry an event type");
    }
    if resource.len() != 0 {
      return _err_str("gcp: HTTP trigger must not carry a resource");
    }
    if retry {
      return _err_str("gcp: HTTP trigger must not carry a retry policy");
    }
    return _ok_str("");
  }
  if kind == GCF_TRIGGER_EVENT {
    if event_type.len() == 0 {
      return _err_str("gcp: event trigger requires an event type");
    }
    if !core.gcp_contains(event_type, ".") {
      return _err_str("gcp: invalid event type: " + event_type);
    }
    if resource.len() == 0 {
      return _err_str("gcp: event trigger requires a resource");
    }
    if !core.gcp_contains(resource, "/") {
      return _err_str("gcp: invalid trigger resource: " + resource);
    }
    return _ok_str("");
  }
  return _err_str("gcp: unknown trigger kind: " + core.gcp_int_str(kind));
}

// --------------------------------------------------
//  Deploy and invoke
// --------------------------------------------------

/// Validate a deploy request. Params: d - the deploy model. Returns Ok("") or
/// the first validation error. Complexity O(total field length).
pub fn gcf_deploy_validate(d: &GcfDeploy) -> Result[Str, Str] {
  if !core.gcp_is_rfc1035_label(d.name) {
    return _err_str("gcp: invalid function name: " + d.name);
  }
  if !gcf_runtime_is_valid(d.runtime) {
    return _err_str("gcp: invalid runtime: " + d.runtime);
  }
  if !gcf_entry_point_is_valid(d.entry_point) {
    return _err_str("gcp: invalid entry point: " + d.entry_point);
  }
  if d.memory_mb < 128 {
    return _err_str("gcp: memory below 128 MB");
  }
  if d.memory_mb > 32768 {
    return _err_str("gcp: memory above 32768 MB");
  }
  if d.timeout_sec < 1 {
    return _err_str("gcp: timeout below 1 s");
  }
  if d.trigger_kind == GCF_TRIGGER_HTTP {
    if d.timeout_sec > 3600 {
      return _err_str("gcp: HTTP timeout above 3600 s");
    }
  } else {
    if d.timeout_sec > 540 {
      return _err_str("gcp: event timeout above 540 s");
    }
  }
  if d.max_instances < 0 {
    return _err_str("gcp: negative max_instances");
  }
  if d.max_instances > 1000 {
    return _err_str("gcp: max_instances above 1000");
  }
  let trig = gcf_trigger_validate(d.trigger_kind, d.event_type, d.resource, d.retry);
  if !trig.is_ok {
    let m: Str = trig.error;
    return _err_str(m);
  }
  return _ok_str("");
}

/// `projects/{project}/locations/{region}/functions/{name}`. Params: project,
/// region, name - the path parts. Returns the path or the first validation
/// error. Complexity O(total length).
pub fn gcf_deploy_path(project: Str, region: Str, name: Str) -> Result[Str, Str] {
  let pn = project.len();
  if pn < 1 || pn > 63 {
    return _err_str("gcp: invalid project id: " + project);
  }
  let rn = region.len();
  if rn < 1 || rn > 63 {
    return _err_str("gcp: invalid region: " + region);
  }
  if !core.gcp_is_rfc1035_label(name) {
    return _err_str("gcp: invalid function name: " + name);
  }
  return _ok_str("projects/" + project + "/locations/" + region + "/functions/" + name);
}

/// Classify an invoke outcome. Params: status - the HTTP status; error_flag -
/// true when the function or runtime reported an error. Returns a
/// GCF_INVOKE_* code. Complexity O(1).
pub fn gcf_invoke_class(status: Int, error_flag: Bool) -> Int {
  if status < 100 || status > 599 {
    return GCF_INVOKE_UNKNOWN;
  }
  if status >= 200 && status <= 299 {
    if error_flag {
      return GCF_INVOKE_APP_ERROR;
    }
    return GCF_INVOKE_OK;
  }
  if status == 429 || status == 503 {
    return GCF_INVOKE_RETRY;
  }
  return GCF_INVOKE_FAIL;
}

/// gen1 HTTP trigger URL. Params: region - the deploy region; project - the
/// project id; name - the function name. Returns the URL or the first
/// validation error. Complexity O(total length).
pub fn gcf_invoke_url(region: Str, project: Str, name: Str) -> Result[Str, Str] {
  let rn = region.len();
  if rn < 1 || rn > 63 {
    return _err_str("gcp: invalid region: " + region);
  }
  let pn = project.len();
  if pn < 1 || pn > 63 {
    return _err_str("gcp: invalid project id: " + project);
  }
  if !core.gcp_is_rfc1035_label(name) {
    return _err_str("gcp: invalid function name: " + name);
  }
  return _ok_str("https://" + region + "-" + project + ".cloudfunctions.net/" + name);
}
