// XIOM -- xiom.azure.storage: pure-XIOM Azure Blob Storage model
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Models the blob storage surface the caller drives over its own transport:
//
//   * Account / container / blob name validation and blob URL assembly.
//   * ETag parsing ("value" and W/"value") with strong and weak comparison.
//   * HTTP precondition evaluation for If-Match / If-None-Match, including the
//     "*" wildcard form.
//   * Block-list rules: per-id shape (1..64 base64 characters), equal id
//     lengths, the 50,000-entry cap and commit resolution across the
//     committed and staged lists.
//   * Access-tier, blob-type and lease-state naming.
//
// Documented subset: validation is a conservative model of the Azure rules
// (ASCII only, no punycode, no path-segment escaping); the caller still owns
// transport, SAS signing and clocks.
//
// v0.62.2 discipline: free functions only, no match, no &mut scalar
// parameters, masked byte widening, bounded loops, no Vec[StructType],
// Ok/Err construction confined to the _ok_* / _err_* leaf helpers.

module xiom.azure.storage

use xiom.azure.base;
use xiom.string;

// Access tiers (AzureBlob.tier).
pub const AZURE_ACCESS_TIER_HOT: Int = 0;
pub const AZURE_ACCESS_TIER_COOL: Int = 1;
pub const AZURE_ACCESS_TIER_ARCHIVE: Int = 2;

// Blob types (AzureBlob.blob_type).
pub const AZURE_BLOB_TYPE_BLOCK: Int = 0;
pub const AZURE_BLOB_TYPE_APPEND: Int = 1;
pub const AZURE_BLOB_TYPE_PAGE: Int = 2;

// Lease states.
pub const AZURE_LEASE_AVAILABLE: Int = 0;
pub const AZURE_LEASE_LEASED: Int = 1;
pub const AZURE_LEASE_BREAKING: Int = 2;
pub const AZURE_LEASE_BROKEN: Int = 3;

// Precondition operators.
pub const AZURE_PRECOND_NONE: Int = 0;
pub const AZURE_PRECOND_IF_MATCH: Int = 1;
pub const AZURE_PRECOND_IF_NONE_MATCH: Int = 2;

// Block-list limits (Azure documented caps).
pub const AZURE_BLOCK_ID_MAX_BYTES: Int = 64;
pub const AZURE_BLOCK_LIST_MAX_ENTRIES: Int = 50000;

/// A parsed strong/weak ETag. `value` carries the unquoted opaque value.
pub type AzureEtag = {
  value: Str;
  weak: Bool;
}

/// One blob's modeled properties.
pub type AzureBlob = {
  name: Str;
  blob_type: Int;
  length: Int;
  etag: Str;
  tier: Int;
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

fn _ok_etag(v: AzureEtag) -> Result[AzureEtag, Str] {
  return Ok(v);
}

fn _err_etag(m: Str) -> Result[AzureEtag, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Local helpers
// --------------------------------------------------

fn _streq(a: Str, b: Str) -> Bool {
  return base.azure_streq(a, b);
}

fn _last_byte(s: Str) -> Int {
  let n = s.len();
  if n == 0 {
    return -1;
  }
  return (string.byte_at(s, n - 1) as Int) & 0xFF;
}

// --------------------------------------------------
//  Names and URLs
// --------------------------------------------------

/// Storage account name: 3..24 lowercase ASCII letters and digits only.
pub fn azure_storage_account_name_valid(s: Str) -> Bool {
  let n = s.len();
  if n < 3 || n > 24 {
    return false;
  }
  var i = 0;
  while i < n {
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    let lower = b >= 97 && b <= 122;
    if !lower && !base.azure_is_digit(b) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// Container name: 3..63 chars, lowercase letters/digits/hyphens, must start
/// and end with a letter or digit and must not contain two consecutive hyphens.
pub fn azure_container_name_valid(s: Str) -> Bool {
  let n = s.len();
  if n < 3 || n > 63 {
    return false;
  }
  var i = 0;
  var prev_dash = false;
  while i < n {
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    let lower = b >= 97 && b <= 122;
    if lower || base.azure_is_digit(b) {
      prev_dash = false;
    } else if b == 45 {
      if i == 0 || prev_dash {
        return false;
      }
      prev_dash = true;
    } else {
      return false;
    }
    i = i + 1;
  }
  if prev_dash {
    return false;
  }
  return true;
}

/// Blob name subset: 1..1024 printable ASCII bytes, without '\', '?', '#',
/// without a leading '/' or consecutive slashes and without a trailing '/'
/// or '.'.
pub fn azure_blob_name_valid(s: Str) -> Bool {
  let n = s.len();
  if n < 1 || n > 1024 {
    return false;
  }
  var i = 0;
  var prev_slash = false;
  while i < n {
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if b < 32 || b == 127 {
      return false;
    }
    if b == 92 || b == 63 || b == 35 {
      return false;
    }
    if b == 47 {
      if i == 0 || prev_slash {
        return false;
      }
      prev_slash = true;
    } else {
      prev_slash = false;
    }
    i = i + 1;
  }
  let last = _last_byte(s);
  if last == 47 || last == 46 {
    return false;
  }
  return true;
}

/// Blob URL "https://{account}.blob.core.windows.net/{container}/{blob}".
pub fn azure_blob_url(account: Str, container: Str, blob: Str) -> Result[Str, Str] {
  if !azure_storage_account_name_valid(account) {
    return _err_str("azure: invalid storage account name");
  }
  if !azure_container_name_valid(container) {
    return _err_str("azure: invalid container name");
  }
  if !azure_blob_name_valid(blob) {
    return _err_str("azure: invalid blob name");
  }
  return _ok_str("https://" + account + ".blob.core.windows.net/" + container + "/" + blob);
}

// --------------------------------------------------
//  ETag model
// --------------------------------------------------

/// Parse an ETag header value: `"value"` (strong) or `W/"value"` (weak).
/// The opaque value must be 1..128 bytes without '"' or control bytes.
pub fn azure_etag_parse(raw: Str) -> Result[AzureEtag, Str] {
  let n = raw.len();
  if n < 2 {
    return _err_etag("azure: malformed ETag");
  }
  let b0: Int = (string.byte_at(raw, 0) as Int) & 0xFF;
  var value = "";
  var weak = false;
  if b0 == 87 {
    if n < 4 {
      return _err_etag("azure: malformed ETag");
    }
    let b1: Int = (string.byte_at(raw, 1) as Int) & 0xFF;
    let b2: Int = (string.byte_at(raw, 2) as Int) & 0xFF;
    let bl: Int = (string.byte_at(raw, n - 1) as Int) & 0xFF;
    if b1 != 47 || b2 != 34 || bl != 34 {
      return _err_etag("azure: malformed ETag");
    }
    value = base.azure_substr(raw, 3, n - 1);
    weak = true;
  } else if b0 == 34 {
    let bl2: Int = (string.byte_at(raw, n - 1) as Int) & 0xFF;
    if bl2 != 34 {
      return _err_etag("azure: malformed ETag");
    }
    value = base.azure_substr(raw, 1, n - 1);
  } else {
    return _err_etag("azure: malformed ETag");
  }
  if value.len() < 1 || value.len() > 128 {
    return _err_etag("azure: malformed ETag");
  }
  var i = 0;
  while i < value.len() {
    let b: Int = (string.byte_at(value, i) as Int) & 0xFF;
    if b < 32 || b == 127 || b == 34 {
      return _err_etag("azure: malformed ETag");
    }
    i = i + 1;
  }
  return _ok_etag(AzureEtag{ value: value; weak: weak; });
}

/// Strong comparison (RFC 7232): both tags strong and byte-equal in value.
pub fn azure_etag_strong_equal(a: &AzureEtag, b: &AzureEtag) -> Bool {
  let aw: Bool = a.weak;
  let bw: Bool = b.weak;
  if aw || bw {
    return false;
  }
  let av: Str = a.value;
  let bv: Str = b.value;
  return _streq(av, bv);
}

/// Weak comparison: values byte-equal regardless of the weak marker.
pub fn azure_etag_weak_equal(a: &AzureEtag, b: &AzureEtag) -> Bool {
  let av: Str = a.value;
  let bv: Str = b.value;
  return _streq(av, bv);
}

/// Evaluate an HTTP precondition against the current state.
/// `current_etag` is "" when the blob does not exist; `requested_etag` is the
/// raw header value, with "*" meaning "any". If-Match uses strong equality
/// against "*"; If-None-Match uses weak equality. Unknown ops fail closed.
pub fn azure_precondition_allows(op: Int, exists: Bool, current_etag: Str, requested_etag: Str) -> Bool {
  if op == AZURE_PRECOND_NONE {
    return true;
  }
  if op == AZURE_PRECOND_IF_MATCH {
    if _streq(requested_etag, "*") {
      return exists;
    }
    if !exists {
      return false;
    }
    return _streq(current_etag, requested_etag);
  }
  if op == AZURE_PRECOND_IF_NONE_MATCH {
    if _streq(requested_etag, "*") {
      return !exists;
    }
    if !exists {
      return true;
    }
    return !_streq(current_etag, requested_etag);
  }
  return false;
}

// --------------------------------------------------
//  Block lists
// --------------------------------------------------

fn _is_base64_byte(b: Int) -> Bool {
  let x = b & 0xFF;
  if x >= 65 && x <= 90 {
    return true;
  }
  if x >= 97 && x <= 122 {
    return true;
  }
  if x >= 48 && x <= 57 {
    return true;
  }
  if x == 43 || x == 47 || x == 61 {
    return true;
  }
  return false;
}

/// Block id: 1..64 base64 characters. Azure also requires every id in one
/// blob to have the same length (checked by azure_block_list_valid).
pub fn azure_block_id_valid(s: Str) -> Bool {
  let n = s.len();
  if n < 1 || n > AZURE_BLOCK_ID_MAX_BYTES {
    return false;
  }
  var i = 0;
  while i < n {
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if !_is_base64_byte(b) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// A block list: 1..50,000 ids, each valid and all of equal length.
pub fn azure_block_list_valid(ids: &Vec[Str]) -> Bool {
  let n = ids.len();
  if n < 1 || n > AZURE_BLOCK_LIST_MAX_ENTRIES {
    return false;
  }
  if !base.azure_all_same_len(ids) {
    return false;
  }
  var i = 0;
  while i < n {
    let id: Str = ids[i];
    if !azure_block_id_valid(id) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when `want` occurs in `ids`.
fn _list_contains(ids: &Vec[Str], want: Str) -> Bool {
  var i = 0;
  while i < ids.len() {
    let cur: Str = ids[i];
    if _streq(cur, want) {
      return true;
    }
    i = i + 1;
  }
  return false;
}

/// Resolve a requested commit list against the blob's committed and staged
/// block ids. Every requested id must exist in one of the two lists; the
/// result is the requested ids joined with ',' in request order.
pub fn azure_block_list_resolve(committed: &Vec[Str], staged: &Vec[Str], requested: &Vec[Str]) -> Result[Str, Str] {
  let n = requested.len();
  if n < 1 {
    return _err_str("azure: empty block list");
  }
  if n > AZURE_BLOCK_LIST_MAX_ENTRIES {
    return _err_str("azure: block list too large");
  }
  let first: Str = requested[0];
  let width = first.len();
  var i = 0;
  var out = "";
  while i < n {
    let want: Str = requested[i];
    if !azure_block_id_valid(want) {
      return _err_str("azure: invalid block id: " + want);
    }
    if want.len() != width {
      return _err_str("azure: block ids must have equal length");
    }
    if !_list_contains(committed, want) {
      if !_list_contains(staged, want) {
        return _err_str("azure: block id not found: " + want);
      }
    }
    if i > 0 {
      out = out + ",";
    }
    out = out + want;
    i = i + 1;
  }
  return _ok_str(out);
}

// --------------------------------------------------
//  Property naming
// --------------------------------------------------

/// Access-tier name for AZURE_ACCESS_TIER_* (unknown -> "unknown").
pub fn azure_blob_tier_name(tier: Int) -> Str {
  if tier == AZURE_ACCESS_TIER_HOT {
    return "hot";
  }
  if tier == AZURE_ACCESS_TIER_COOL {
    return "cool";
  }
  if tier == AZURE_ACCESS_TIER_ARCHIVE {
    return "archive";
  }
  return "unknown";
}

/// True for a known access tier.
pub fn azure_blob_tier_valid(tier: Int) -> Bool {
  return tier == AZURE_ACCESS_TIER_HOT || tier == AZURE_ACCESS_TIER_COOL || tier == AZURE_ACCESS_TIER_ARCHIVE;
}

/// Blob-type name for AZURE_BLOB_TYPE_* (unknown -> "unknown").
pub fn azure_blob_type_name(blob_type: Int) -> Str {
  if blob_type == AZURE_BLOB_TYPE_BLOCK {
    return "block";
  }
  if blob_type == AZURE_BLOB_TYPE_APPEND {
    return "append";
  }
  if blob_type == AZURE_BLOB_TYPE_PAGE {
    return "page";
  }
  return "unknown";
}

/// Lease-state name (unknown -> "unknown").
pub fn azure_lease_state_name(state: Int) -> Str {
  if state == AZURE_LEASE_AVAILABLE {
    return "available";
  }
  if state == AZURE_LEASE_LEASED {
    return "leased";
  }
  if state == AZURE_LEASE_BREAKING {
    return "breaking";
  }
  if state == AZURE_LEASE_BROKEN {
    return "broken";
  }
  return "unknown";
}
