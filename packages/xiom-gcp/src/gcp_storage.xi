// XIOM -- xiom.gcp.storage: Google Cloud Storage model
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM MODEL of the GCS JSON API surface: bucket-name and object-name
// validation, JSON API paths (`b/{bucket}`, `b/{bucket}/o/{object}`), object
// generations and the ifGenerationMatch / ifMetagenerationMatch precondition
// family, plus the ACL entity/role shape. No network, no FFI.
//
// Documented subset:
//   * bucket names: 3..63 characters, lowercase letters/digits/'-'/'_'/'.',
//     lowercase letter or digit first and last, no ".." run, no leading
//     "goog" and no "google" substring.
//   * object names: 1..1024 bytes, no CR/LF, not "." or "..".
//   * object path encoding: RFC 3986 unreserved bytes plus '/' stay literal,
//     everything else becomes %XX with uppercase hex.
//   * preconditions: non-negative; a positive match and a positive negated
//     match of the same generation kind conflict.
//   * ACL roles: READER / WRITER / OWNER; entities: allUsers,
//     allAuthenticatedUsers, user-*/group-*/domain-*/project-*.
//
// v0.62.2 discipline: free functions only; Str equality via
// xiom.string.compare; bounded loops; no Vec[StructType].

module xiom.gcp.storage

use xiom.gcp.core;
use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Constants
// --------------------------------------------------

/// Minimum bucket-name length (3).
pub const GCS_BUCKET_NAME_MIN: Int = 3;

/// Maximum bucket-name length (63).
pub const GCS_BUCKET_NAME_MAX: Int = 63;

/// Maximum object-name length in bytes (1024).
pub const GCS_OBJECT_NAME_MAX: Int = 1024;

/// ACL role READER.
pub const GCS_ACL_ROLE_READER: Str = "READER";

/// ACL role WRITER.
pub const GCS_ACL_ROLE_WRITER: Str = "WRITER";

/// ACL role OWNER.
pub const GCS_ACL_ROLE_OWNER: Str = "OWNER";

const _GCS_HEX_UPPER: Str = "0123456789ABCDEF";

// --------------------------------------------------
//  Types
// --------------------------------------------------

/// The four GCS preconditions; 0 means "unset".
pub type GcsPreconditions = {
  if_generation_match: Int;
  if_generation_not_match: Int;
  if_metageneration_match: Int;
  if_metageneration_not_match: Int;
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
//  Buckets and objects
// --------------------------------------------------

/// True for a documented-subset GCS bucket name. Params: name - the candidate
/// bucket. Complexity O(name.len()).
pub fn gcs_bucket_name_is_valid(name: Str) -> Bool {
  let n = name.len();
  if n < GCS_BUCKET_NAME_MIN {
    return false;
  }
  if n > GCS_BUCKET_NAME_MAX {
    return false;
  }
  let first = core.gcp_byte(name, 0);
  if !core.gcp_is_alnum_lower(first) {
    return false;
  }
  let last = core.gcp_byte(name, n - 1);
  if !core.gcp_is_alnum_lower(last) {
    return false;
  }
  var i = 0;
  while i < n {
    let c = core.gcp_byte(name, i);
    if !core.gcp_is_alnum_lower(c) {
      var ok = false;
      if c == 45 || c == 95 || c == 46 {
        ok = true;
      }
      if !ok {
        return false;
      }
    }
    if i + 1 < n {
      let d = core.gcp_byte(name, i + 1);
      if c == 46 && d == 46 {
        return false;
      }
    }
    i = i + 1;
  }
  if core.gcp_starts_with(name, "goog") {
    return false;
  }
  if core.gcp_contains(name, "google") {
    return false;
  }
  return true;
}

/// `b/{bucket}` JSON API path. Params: bucket - the bucket name. Returns the
/// path or an "invalid bucket" error. Complexity O(bucket.len()).
pub fn gcs_bucket_path(bucket: Str) -> Result[Str, Str] {
  if !gcs_bucket_name_is_valid(bucket) {
    return _err_str("gcp: invalid bucket name: " + bucket);
  }
  return _ok_str("b/" + bucket);
}

/// True for a documented-subset GCS object name. Params: name - the candidate
/// object name. Complexity O(name.len()).
pub fn gcs_object_name_is_valid(name: Str) -> Bool {
  let n = name.len();
  if n < 1 {
    return false;
  }
  if n > GCS_OBJECT_NAME_MAX {
    return false;
  }
  if core.gcp_str_eq(name, ".") {
    return false;
  }
  if core.gcp_str_eq(name, "..") {
    return false;
  }
  var i = 0;
  while i < n {
    let c = core.gcp_byte(name, i);
    if c == 10 || c == 13 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Percent-encode one object byte: unreserved and '/' stay literal.
fn _gcs_encode_byte(out: &mut Vec[UInt8], b: Int) {
  var literal = false;
  if core.gcp_is_alnum(b) {
    literal = true;
  }
  if b == 45 || b == 46 || b == 95 || b == 126 || b == 47 {
    literal = true;
  }
  if literal {
    out.push((b & 0xFF) as UInt8);
  } else {
    out.push(37 as UInt8);
    out.push(string.byte_at(_GCS_HEX_UPPER, b / 16));
    out.push(string.byte_at(_GCS_HEX_UPPER, b % 16));
  }
}

/// `b/{bucket}/o/{object}` with the object percent-encoded (slashes kept).
/// Params: bucket - the bucket name; object - the object name. Returns the
/// path or the first validation error. Complexity O(bucket.len()+object.len()).
pub fn gcs_object_path(bucket: Str, object: Str) -> Result[Str, Str] {
  if !gcs_bucket_name_is_valid(bucket) {
    return _err_str("gcp: invalid bucket name: " + bucket);
  }
  if !gcs_object_name_is_valid(object) {
    return _err_str("gcp: invalid object name: " + object);
  }
  var out = Vec[UInt8].new();
  out.push(98 as UInt8);
  out.push(47 as UInt8);
  var i = 0;
  while i < bucket.len() {
    out.push(string.byte_at(bucket, i));
    i = i + 1;
  }
  out.push(47 as UInt8);
  out.push(111 as UInt8);
  out.push(47 as UInt8);
  var j = 0;
  while j < object.len() {
    _gcs_encode_byte(&mut out, core.gcp_byte(object, j));
    j = j + 1;
  }
  return _ok_str(builder.sb_to_str(&out));
}

/// True for a positive GCS object generation number. Params: generation - the
/// candidate. Complexity O(1).
pub fn gcs_generation_is_valid(generation: Int) -> Bool {
  if generation < 1 {
    return false;
  }
  return true;
}

/// `b/{bucket}/o/{object}?generation={n}` for a specific object generation.
/// Params: bucket - the bucket name; object - the object name; generation - a
/// positive generation. Returns the path or the first validation error.
/// Complexity O(bucket.len()+object.len()).
pub fn gcs_generation_path(bucket: Str, object: Str, generation: Int) -> Result[Str, Str] {
  if !gcs_generation_is_valid(generation) {
    return _err_str("gcp: invalid generation: " + core.gcp_int_str(generation));
  }
  let base = gcs_object_path(bucket, object);
  if !base.is_ok {
    let m: Str = base.error;
    return _err_str(m);
  }
  let b: Str = base.value;
  return _ok_str(b + "?generation=" + core.gcp_int_str(generation));
}

// --------------------------------------------------
//  Preconditions
// --------------------------------------------------

/// All four preconditions unset (zero).
pub fn gcs_preconditions_none() -> GcsPreconditions {
  let p = GcsPreconditions{
    if_generation_match: 0;
    if_generation_not_match: 0;
    if_metageneration_match: 0;
    if_metageneration_not_match: 0;
  };
  return p;
}

/// Render the preconditions as a deterministic query suffix ("?" + pairs in
/// fixed order, "" when all are unset). Params: p - the preconditions. Returns
/// the suffix or a conflict/negative error. Complexity O(1).
pub fn gcs_preconditions_query(p: &GcsPreconditions) -> Result[Str, Str] {
  if p.if_generation_match < 0 {
    return _err_str("gcp: negative ifGenerationMatch");
  }
  if p.if_generation_not_match < 0 {
    return _err_str("gcp: negative ifGenerationNotMatch");
  }
  if p.if_metageneration_match < 0 {
    return _err_str("gcp: negative ifMetagenerationMatch");
  }
  if p.if_metageneration_not_match < 0 {
    return _err_str("gcp: negative ifMetagenerationNotMatch");
  }
  if p.if_generation_match > 0 && p.if_generation_not_match > 0 {
    return _err_str("gcp: ifGenerationMatch and ifGenerationNotMatch conflict");
  }
  if p.if_metageneration_match > 0 && p.if_metageneration_not_match > 0 {
    return _err_str("gcp: ifMetagenerationMatch and ifMetagenerationNotMatch conflict");
  }
  var out = "";
  var sep = "?";
  if p.if_generation_match > 0 {
    out = out + sep + "ifGenerationMatch=" + core.gcp_int_str(p.if_generation_match);
    sep = "&";
  }
  if p.if_generation_not_match > 0 {
    out = out + sep + "ifGenerationNotMatch=" + core.gcp_int_str(p.if_generation_not_match);
    sep = "&";
  }
  if p.if_metageneration_match > 0 {
    out = out + sep + "ifMetagenerationMatch=" + core.gcp_int_str(p.if_metageneration_match);
    sep = "&";
  }
  if p.if_metageneration_not_match > 0 {
    out = out + sep + "ifMetagenerationNotMatch=" + core.gcp_int_str(p.if_metageneration_not_match);
    sep = "&";
  }
  return _ok_str(out);
}

// --------------------------------------------------
//  ACL shape
// --------------------------------------------------

/// True for a modeled GCS ACL role (READER / WRITER / OWNER). Params: role -
/// the candidate role. Complexity O(role.len()).
pub fn gcs_acl_role_is_valid(role: Str) -> Bool {
  if core.gcp_str_eq(role, GCS_ACL_ROLE_READER) {
    return true;
  }
  if core.gcp_str_eq(role, GCS_ACL_ROLE_WRITER) {
    return true;
  }
  if core.gcp_str_eq(role, GCS_ACL_ROLE_OWNER) {
    return true;
  }
  return false;
}

/// True for a modeled GCS ACL entity. Params: entity - the candidate entity.
/// Complexity O(entity.len()).
pub fn gcs_acl_entity_is_valid(entity: Str) -> Bool {
  if core.gcp_str_eq(entity, "allUsers") {
    return true;
  }
  if core.gcp_str_eq(entity, "allAuthenticatedUsers") {
    return true;
  }
  if core.gcp_starts_with(entity, "user-") {
    return entity.len() > 5;
  }
  if core.gcp_starts_with(entity, "group-") {
    return entity.len() > 6;
  }
  if core.gcp_starts_with(entity, "domain-") {
    return entity.len() > 7;
  }
  if core.gcp_starts_with(entity, "project-") {
    if entity.len() <= 8 {
      return false;
    }
    let rest = core.gcp_substr(entity, 8, entity.len());
    return core.gcp_contains(rest, "-");
  }
  return false;
}

/// Validate one ACL entry pair. Params: entity - the entity; role - the role.
/// Returns Ok("") or the first validation error. Complexity O(len).
pub fn gcs_acl_entry_validate(entity: Str, role: Str) -> Result[Str, Str] {
  if !gcs_acl_entity_is_valid(entity) {
    return _err_str("gcp: invalid ACL entity: " + entity);
  }
  if !gcs_acl_role_is_valid(role) {
    return _err_str("gcp: invalid ACL role: " + role);
  }
  return _ok_str("");
}
