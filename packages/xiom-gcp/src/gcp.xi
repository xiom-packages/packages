// XIOM -- xiom.gcp: GCP resource names, service registry and endpoint bases
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM MODEL of the Google Cloud resource-name grammar and the per-service
// JSON API registry. Everything is caller-supplied text: no network, no FFI,
// no clocks, no crypto. The documented subset is:
//
//   * project ids: 6..30 characters, lowercase letters/digits/hyphens, a
//     lowercase letter first and a lowercase letter or digit last.
//   * regions: 2..63 characters, lowercase letters/digits/hyphens, a lowercase
//     letter first and a lowercase letter or digit last.
//   * zones: a valid region followed by "-" and exactly one lowercase letter
//     (us-central1-a); the region of a zone is the part before the last dash.
//   * resource paths: projects/{p}, projects/{p}/{collection}/{name},
//     projects/{p}/global/{collection}/{name},
//     projects/{p}/zones/{z}/{collection}/{name} and
//     projects/{p}/locations/{r}/{collection}/{name}.
//   * endpoint bases: https://{service}.googleapis.com/{api-version} for the
//     six modeled services (storage, compute, cloudfunctions, bigquery,
//     pubsub, iam).
//
// v0.62.2 discipline: free functions only; Str equality via
// xiom.string.compare; no &mut Int scalar parameters; bounded loops.

module xiom.gcp

use xiom.gcp.core;
use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Service codes
// --------------------------------------------------

/// Unknown service code (0).
pub const GCP_SERVICE_UNKNOWN: Int = 0;

/// Cloud Storage service code (1).
pub const GCP_SERVICE_STORAGE: Int = 1;

/// Compute Engine service code (2).
pub const GCP_SERVICE_COMPUTE: Int = 2;

/// Cloud Functions service code (3).
pub const GCP_SERVICE_FUNCTIONS: Int = 3;

/// BigQuery service code (4).
pub const GCP_SERVICE_BIGQUERY: Int = 4;

/// Pub/Sub service code (5).
pub const GCP_SERVICE_PUBSUB: Int = 5;

/// IAM service code (6).
pub const GCP_SERVICE_IAM: Int = 6;

/// Highest modeled service code (6).
pub const GCP_SERVICE_MAX: Int = 6;

// --------------------------------------------------
//  Types
// --------------------------------------------------

/// A decomposed GCP resource path. `kind` and `name` are "" for the
/// project-only form `projects/{project}`; `location` is "" when the resource
/// has no location segment, else "global", a region or a zone.
pub type GcpResource = {
  project: Str;
  kind: Str;
  location: Str;
  name: Str;
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

fn _ok_res(v: GcpResource) -> Result[GcpResource, Str] {
  return Ok(v);
}

fn _err_res(m: Str) -> Result[GcpResource, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Local helpers
// --------------------------------------------------

// Last index of byte `ch` in s[from, to), or -1. Caller bounds the range.
fn _gcp_last_index_of_char(s: Str, from: Int, to: Int, ch: Int) -> Int {
  var i = to - 1;
  while i >= from {
    let b = core.gcp_byte(s, i);
    if b == ch {
      return i;
    }
    i = i - 1;
  }
  return -1;
}

// Collection token: 1..64 ASCII letters (camelCase like machineTypes).
fn _gcp_collection_is_valid(collection: Str) -> Bool {
  let n = collection.len();
  if n < 1 {
    return false;
  }
  if n > 64 {
    return false;
  }
  var i = 0;
  while i < n {
    let c = core.gcp_byte(collection, i);
    if !core.gcp_is_alpha(c) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Resource name leaf: 1..255 bytes and no '/'.
fn _gcp_name_is_valid(name: Str) -> Bool {
  let n = name.len();
  if n < 1 {
    return false;
  }
  if n > 255 {
    return false;
  }
  var i = 0;
  while i < n {
    let c = core.gcp_byte(name, i);
    if c == 47 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Project / region / zone names
// --------------------------------------------------

/// True for a documented-subset GCP project id: 6..30 characters, lowercase
/// letters/digits/hyphens, lowercase letter first, lowercase letter or digit
/// last. Params: project - the candidate id. Complexity O(project.len()).
pub fn gcp_project_id_is_valid(project: Str) -> Bool {
  let n = project.len();
  if n < GCP_PROJECT_ID_MIN {
    return false;
  }
  if n > GCP_PROJECT_ID_MAX {
    return false;
  }
  if !core.gcp_is_lower_alpha(core.gcp_byte(project, 0)) {
    return false;
  }
  if !core.gcp_is_alnum_lower(core.gcp_byte(project, n - 1)) {
    return false;
  }
  var i = 0;
  while i < n {
    let c = core.gcp_byte(project, i);
    if !core.gcp_is_alnum_lower(c) {
      if c != 45 {
        return false;
      }
    }
    i = i + 1;
  }
  return true;
}

/// True for a documented-subset GCP region name: 2..63 characters, lowercase
/// letters/digits/hyphens, lowercase letter first, lowercase letter or digit
/// last. Params: region - the candidate name. Complexity O(region.len()).
pub fn gcp_region_is_valid(region: Str) -> Bool {
  let n = region.len();
  if n < 2 {
    return false;
  }
  if n > 63 {
    return false;
  }
  if !core.gcp_is_lower_alpha(core.gcp_byte(region, 0)) {
    return false;
  }
  if !core.gcp_is_alnum_lower(core.gcp_byte(region, n - 1)) {
    return false;
  }
  var i = 0;
  while i < n {
    let c = core.gcp_byte(region, i);
    if !core.gcp_is_alnum_lower(c) {
      if c != 45 {
        return false;
      }
    }
    i = i + 1;
  }
  return true;
}

/// True for a documented-subset GCP zone name: a valid region, a dash and
/// exactly one lowercase letter (us-central1-a). Params: zone - the candidate
/// name. Complexity O(zone.len()).
pub fn gcp_zone_is_valid(zone: Str) -> Bool {
  let n = zone.len();
  if n < 4 {
    return false;
  }
  let last_dash = _gcp_last_index_of_char(zone, 0, n, 45);
  if last_dash < 0 {
    return false;
  }
  if n - last_dash != 2 {
    return false;
  }
  let letter = core.gcp_byte(zone, last_dash + 1);
  if !core.gcp_is_lower_alpha(letter) {
    return false;
  }
  let base = core.gcp_substr(zone, 0, last_dash);
  return gcp_region_is_valid(base);
}

/// The region of a zone: the part before the last dash. Params: zone - a zone
/// name. Returns a Result with the region text or an "invalid zone" error.
/// Complexity O(zone.len()).
pub fn gcp_region_of_zone(zone: Str) -> Result[Str, Str] {
  if !gcp_zone_is_valid(zone) {
    return _err_str("gcp: invalid zone: " + zone);
  }
  let last_dash = _gcp_last_index_of_char(zone, 0, zone.len(), 45);
  return _ok_str(core.gcp_substr(zone, 0, last_dash));
}

// --------------------------------------------------
//  Path construction
// --------------------------------------------------

/// `projects/{project}`. Params: project - the project id. Returns the path or
/// an "invalid project id" error. Complexity O(project.len()).
pub fn gcp_project_path(project: Str) -> Result[Str, Str] {
  if !gcp_project_id_is_valid(project) {
    return _err_str("gcp: invalid project id: " + project);
  }
  return _ok_str("projects/" + project);
}

/// `projects/{project}/zones/{zone}`. Params: project - the project id; zone -
/// the zone name. Returns the path or the first validation error. Complexity
/// O(project.len() + zone.len()).
pub fn gcp_zone_path(project: Str, zone: Str) -> Result[Str, Str] {
  if !gcp_project_id_is_valid(project) {
    return _err_str("gcp: invalid project id: " + project);
  }
  if !gcp_zone_is_valid(zone) {
    return _err_str("gcp: invalid zone: " + zone);
  }
  return _ok_str("projects/" + project + "/zones/" + zone);
}

/// `projects/{project}/locations/{region}`. Params: project - the project id;
/// region - the region name. Returns the path or the first validation error.
/// Complexity O(project.len() + region.len()).
pub fn gcp_region_path(project: Str, region: Str) -> Result[Str, Str] {
  if !gcp_project_id_is_valid(project) {
    return _err_str("gcp: invalid project id: " + project);
  }
  if !gcp_region_is_valid(region) {
    return _err_str("gcp: invalid region: " + region);
  }
  return _ok_str("projects/" + project + "/locations/" + region);
}

/// `projects/{project}/global`. Params: project - the project id. Returns the
/// path or an "invalid project id" error. Complexity O(project.len()).
pub fn gcp_global_path(project: Str) -> Result[Str, Str] {
  if !gcp_project_id_is_valid(project) {
    return _err_str("gcp: invalid project id: " + project);
  }
  return _ok_str("projects/" + project + "/global");
}

/// `projects/{project}/{collection}/{name}` for the project-only and global
/// forms with an explicit location. The location "" selects the no-location
/// form, "global" the global form, a zone the `zones/{z}` form, and a region
/// the `locations/{r}` form. Params: project - the project id; collection -
/// the collection token; location - "" / "global" / zone / region; name - the
/// resource name. Returns the path or the first validation error. Complexity
/// O(total input length).
pub fn gcp_resource_path(project: Str, collection: Str, location: Str, name: Str) -> Result[Str, Str] {
  if !gcp_project_id_is_valid(project) {
    return _err_str("gcp: invalid project id: " + project);
  }
  if !_gcp_collection_is_valid(collection) {
    return _err_str("gcp: invalid collection: " + collection);
  }
  if !_gcp_name_is_valid(name) {
    return _err_str("gcp: invalid resource name: " + name);
  }
  if location.len() == 0 {
    return _ok_str("projects/" + project + "/" + collection + "/" + name);
  }
  if core.gcp_str_eq(location, core.GCP_LOCATION_GLOBAL) {
    return _ok_str("projects/" + project + "/global/" + collection + "/" + name);
  }
  if gcp_zone_is_valid(location) {
    return _ok_str("projects/" + project + "/zones/" + location + "/" + collection + "/" + name);
  }
  if gcp_region_is_valid(location) {
    return _ok_str("projects/" + project + "/locations/" + location + "/" + collection + "/" + name);
  }
  return _err_str("gcp: invalid location: " + location);
}

/// Decompose a GCP resource path. Params: path - the path text. Returns the
/// GcpResource or a "gcp: ..." error. Complexity O(path.len()).
pub fn gcp_parse_resource(path: Str) -> Result[GcpResource, Str] {
  var segs = Vec[Str].new();
  let n = path.len();
  var start = 0;
  var i = 0;
  while i <= n {
    let at_end = i == n;
    var is_sep = false;
    if !at_end {
      let b = core.gcp_byte(path, i);
      if b == 47 {
        is_sep = true;
      }
    }
    if at_end || is_sep {
      segs.push(core.gcp_substr(path, start, i));
      start = i + 1;
    }
    i = i + 1;
  }
  let count = segs.len();
  if count < 2 {
    return _err_res("gcp: resource path must start with projects/");
  }
  let s0: Str = segs[0];
  if !core.gcp_str_eq(s0, "projects") {
    return _err_res("gcp: resource path must start with projects/");
  }
  let project: Str = segs[1];
  if !gcp_project_id_is_valid(project) {
    return _err_res("gcp: invalid project id: " + project);
  }
  if count == 2 {
    let r = GcpResource{ project: project; kind: ""; location: ""; name: ""; };
    return _ok_res(r);
  }
  if count == 4 {
    let kind: Str = segs[2];
    let name: Str = segs[3];
    if !_gcp_collection_is_valid(kind) {
      return _err_res("gcp: invalid collection: " + kind);
    }
    if !_gcp_name_is_valid(name) {
      return _err_res("gcp: invalid resource name: " + name);
    }
    let r = GcpResource{ project: project; kind: kind; location: ""; name: name; };
    return _ok_res(r);
  }
  if count == 6 {
    let loc_kind: Str = segs[2];
    let loc: Str = segs[3];
    let kind: Str = segs[4];
    let name: Str = segs[5];
    if !_gcp_collection_is_valid(kind) {
      return _err_res("gcp: invalid collection: " + kind);
    }
    if !_gcp_name_is_valid(name) {
      return _err_res("gcp: invalid resource name: " + name);
    }
    if core.gcp_str_eq(loc_kind, core.GCP_LOCATION_GLOBAL) {
      return _err_res("gcp: global segment takes no location name");
    }
    if core.gcp_str_eq(loc_kind, "zones") {
      if !gcp_zone_is_valid(loc) {
        return _err_res("gcp: invalid zone: " + loc);
      }
      let rz = GcpResource{ project: project; kind: kind; location: loc; name: name; };
      return _ok_res(rz);
    }
    if core.gcp_str_eq(loc_kind, "locations") {
      if !gcp_region_is_valid(loc) {
        return _err_res("gcp: invalid region: " + loc);
      }
      let rr = GcpResource{ project: project; kind: kind; location: loc; name: name; };
      return _ok_res(rr);
    }
    return _err_res("gcp: unknown location segment: " + loc_kind);
  }
  if count == 5 {
    let loc_kind: Str = segs[2];
    let kind: Str = segs[3];
    let name: Str = segs[4];
    if !core.gcp_str_eq(loc_kind, core.GCP_LOCATION_GLOBAL) {
      return _err_res("gcp: unknown location segment: " + loc_kind);
    }
    if !_gcp_collection_is_valid(kind) {
      return _err_res("gcp: invalid collection: " + kind);
    }
    if !_gcp_name_is_valid(name) {
      return _err_res("gcp: invalid resource name: " + name);
    }
    let rg = GcpResource{ project: project; kind: kind; location: core.GCP_LOCATION_GLOBAL; name: name; };
    return _ok_res(rg);
  }
  return _err_res("gcp: unsupported resource path");
}

// --------------------------------------------------
//  Service registry
// --------------------------------------------------

/// Map a service name to its code (0 = unknown). Params: name - the service
/// name. Complexity O(name.len()).
pub fn gcp_service_code(name: Str) -> Int {
  if core.gcp_str_eq(name, "storage") {
    return GCP_SERVICE_STORAGE;
  }
  if core.gcp_str_eq(name, "compute") {
    return GCP_SERVICE_COMPUTE;
  }
  if core.gcp_str_eq(name, "cloudfunctions") {
    return GCP_SERVICE_FUNCTIONS;
  }
  if core.gcp_str_eq(name, "bigquery") {
    return GCP_SERVICE_BIGQUERY;
  }
  if core.gcp_str_eq(name, "pubsub") {
    return GCP_SERVICE_PUBSUB;
  }
  if core.gcp_str_eq(name, "iam") {
    return GCP_SERVICE_IAM;
  }
  return GCP_SERVICE_UNKNOWN;
}

/// Canonical service name for a code. Params: code - a GCP_SERVICE_* code.
/// Complexity O(1).
pub fn gcp_service_name(code: Int) -> Result[Str, Str] {
  if code == GCP_SERVICE_STORAGE {
    return _ok_str("storage");
  }
  if code == GCP_SERVICE_COMPUTE {
    return _ok_str("compute");
  }
  if code == GCP_SERVICE_FUNCTIONS {
    return _ok_str("cloudfunctions");
  }
  if code == GCP_SERVICE_BIGQUERY {
    return _ok_str("bigquery");
  }
  if code == GCP_SERVICE_PUBSUB {
    return _ok_str("pubsub");
  }
  if code == GCP_SERVICE_IAM {
    return _ok_str("iam");
  }
  return _err_str("gcp: unknown service code: " + core.gcp_int_str(code));
}

/// API host for a service code (e.g. storage.googleapis.com). Params: code - a
/// GCP_SERVICE_* code. Complexity O(1).
pub fn gcp_service_host(code: Int) -> Result[Str, Str] {
  if code == GCP_SERVICE_STORAGE {
    return _ok_str("storage.googleapis.com");
  }
  if code == GCP_SERVICE_COMPUTE {
    return _ok_str("compute.googleapis.com");
  }
  if code == GCP_SERVICE_FUNCTIONS {
    return _ok_str("cloudfunctions.googleapis.com");
  }
  if code == GCP_SERVICE_BIGQUERY {
    return _ok_str("bigquery.googleapis.com");
  }
  if code == GCP_SERVICE_PUBSUB {
    return _ok_str("pubsub.googleapis.com");
  }
  if code == GCP_SERVICE_IAM {
    return _ok_str("iam.googleapis.com");
  }
  return _err_str("gcp: unknown service code: " + core.gcp_int_str(code));
}

/// JSON API version for a service code. Params: code - a GCP_SERVICE_* code.
/// Complexity O(1).
pub fn gcp_service_api_version(code: Int) -> Result[Str, Str] {
  if code == GCP_SERVICE_BIGQUERY {
    return _ok_str("v2");
  }
  if code == GCP_SERVICE_STORAGE {
    return _ok_str("v1");
  }
  if code == GCP_SERVICE_COMPUTE {
    return _ok_str("v1");
  }
  if code == GCP_SERVICE_FUNCTIONS {
    return _ok_str("v1");
  }
  if code == GCP_SERVICE_PUBSUB {
    return _ok_str("v1");
  }
  if code == GCP_SERVICE_IAM {
    return _ok_str("v1");
  }
  return _err_str("gcp: unknown service code: " + core.gcp_int_str(code));
}

/// True when the modeled service uses a single global JSON endpoint
/// (storage, bigquery, pubsub, iam); false for compute and cloudfunctions,
/// whose calls are zonal/regional. Params: code - a GCP_SERVICE_* code.
/// Complexity O(1).
pub fn gcp_service_is_global(code: Int) -> Bool {
  if code == GCP_SERVICE_STORAGE {
    return true;
  }
  if code == GCP_SERVICE_BIGQUERY {
    return true;
  }
  if code == GCP_SERVICE_PUBSUB {
    return true;
  }
  if code == GCP_SERVICE_IAM {
    return true;
  }
  return false;
}

/// Endpoint base `https://{host}/{api-version}` for a service code; the caller
/// appends the resource path. Params: code - a GCP_SERVICE_* code. Returns the
/// base or an "unknown service code" error. Complexity O(1).
pub fn gcp_endpoint_base(code: Int) -> Result[Str, Str] {
  let host = gcp_service_host(code);
  if !host.is_ok {
    let m: Str = host.error;
    return _err_str(m);
  }
  let version = gcp_service_api_version(code);
  if !version.is_ok {
    let m2: Str = version.error;
    return _err_str(m2);
  }
  let h: Str = host.value;
  let v: Str = version.value;
  return _ok_str("https://" + h + "/" + v);
}
