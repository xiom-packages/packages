// XIOM -- xiom.azure.cosmos: pure-XIOM Azure Cosmos DB model
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Models the Cosmos DB SQL (Core) surface the caller drives over its own
// transport:
//
//   * Database / container / document name rules (1..255 bytes without
//     '/', '\', '?' and '#').
//   * Partition key paths ("/tenantId", up to three hierarchical segments)
//     and values; the REST partition-key header codec for the single-value
//     form ["value"].
//   * Document shape: id, partition key and TTL (-1 = no expiry, otherwise
//     1..2^31-1 seconds).
//   * Consistency levels, RU/s throughput normalization, status-code
//     classification into error names and retryability (429/449/503), and
//     the classic "dbs/{db}/colls/{coll}/docs/{id}" REST path.
//
// Documented subset: composite (multi-value) partition-key headers are
// rejected, and both single- and multi-segment partition key paths are
// modeled (Azure's hierarchical-key maximum of three is enforced).
//
// v0.62.2 discipline: free functions only, no match, no &mut scalar
// parameters, masked byte widening, bounded loops, no Vec[StructType],
// Ok/Err construction confined to the _ok_* / _err_* leaf helpers.

module xiom.azure.cosmos

use xiom.azure.base;
use xiom.string;

// Consistency levels.
pub const AZURE_COSMOS_CONSISTENCY_STRONG: Int = 0;
pub const AZURE_COSMOS_CONSISTENCY_BOUNDED_STALENESS: Int = 1;
pub const AZURE_COSMOS_CONSISTENCY_SESSION: Int = 2;
pub const AZURE_COSMOS_CONSISTENCY_CONSISTENT_PREFIX: Int = 3;
pub const AZURE_COSMOS_CONSISTENCY_EVENTUAL: Int = 4;

// Throughput bounds (RU/s).
pub const AZURE_COSMOS_RU_MIN: Int = 400;
pub const AZURE_COSMOS_RU_MAX: Int = 1000000;
pub const AZURE_COSMOS_RU_STEP: Int = 100;

// TTL sentinel: -1 disables expiry for the item.
pub const AZURE_COSMOS_TTL_NO_EXPIRY: Int = -1;

/// One Cosmos DB document envelope.
pub type AzureCosmosDocument = {
  id: Str;
  partition_key: Str;
  etag: Str;
  ttl: Int;
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
//  Local helpers
// --------------------------------------------------

fn _streq_ci(a: Str, b: Str) -> Bool {
  return base.azure_streq_ignore_case(a, b);
}

fn _byte_at(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// --------------------------------------------------
//  Names
// --------------------------------------------------

/// Database / container / document id: 1..255 bytes, printable ASCII,
/// without '/', '\', '?' and '#'.
pub fn azure_cosmos_name_valid(s: Str) -> Bool {
  let n = s.len();
  if n < 1 || n > 255 {
    return false;
  }
  var i = 0;
  while i < n {
    let b: Int = _byte_at(s, i);
    if b < 32 || b == 127 {
      return false;
    }
    if b == 47 || b == 92 || b == 63 || b == 35 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// Database name (same subset as azure_cosmos_name_valid).
pub fn azure_cosmos_db_name_valid(s: Str) -> Bool {
  return azure_cosmos_name_valid(s);
}

/// Container name (same subset as azure_cosmos_name_valid).
pub fn azure_cosmos_container_name_valid(s: Str) -> Bool {
  return azure_cosmos_name_valid(s);
}

// --------------------------------------------------
//  Partition keys
// --------------------------------------------------

/// Partition key path: leading '/', 1..3 non-empty path segments, 2..256
/// bytes, no '?', '#', '\' or control bytes, no trailing '/'.
pub fn azure_cosmos_partition_key_path_valid(p: Str) -> Bool {
  let n = p.len();
  if n < 2 || n > 256 {
    return false;
  }
  let b0: Int = _byte_at(p, 0);
  if b0 != 47 {
    return false;
  }
  var i = 1;
  var segs = 0;
  var seg_start = 1;
  while i <= n {
    var boundary = false;
    if i == n {
      boundary = true;
    } else {
      let b: Int = _byte_at(p, i);
      if b == 47 {
        boundary = true;
      }
    }
    if boundary {
      if i == seg_start {
        return false;
      }
      segs = segs + 1;
      seg_start = i + 1;
    }
    i = i + 1;
  }
  if segs < 1 || segs > 3 {
    return false;
  }
  var j = 0;
  while j < n {
    let b: Int = _byte_at(p, j);
    if b < 32 || b == 127 {
      return false;
    }
    if b == 92 || b == 63 || b == 35 {
      return false;
    }
    j = j + 1;
  }
  return true;
}

/// Partition key value: 1..1024 bytes, printable ASCII except '/', '\',
/// '?' and '#'.
pub fn azure_cosmos_partition_key_value_valid(v: Str) -> Bool {
  let n = v.len();
  if n < 1 || n > 1024 {
    return false;
  }
  var i = 0;
  while i < n {
    let b: Int = _byte_at(v, i);
    if b < 32 || b == 127 {
      return false;
    }
    if b == 47 || b == 92 || b == 63 || b == 35 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// REST partition-key header value for a single-key container: ["value"].
pub fn azure_cosmos_partition_key_header(v: Str) -> Result[Str, Str] {
  if !azure_cosmos_partition_key_value_valid(v) {
    return _err_str("azure: invalid partition key value");
  }
  return _ok_str("[\"" + v + "\"]");
}

/// Parse the single-value ["value"] header form. Composite (multi-value)
/// headers, escapes and extra whitespace are rejected.
pub fn azure_cosmos_partition_key_header_parse(h: Str) -> Result[Str, Str] {
  let n = h.len();
  if n < 5 {
    return _err_str("azure: malformed partition key header");
  }
  let b0: Int = _byte_at(h, 0);
  let b1: Int = _byte_at(h, 1);
  let bl: Int = _byte_at(h, n - 1);
  let bp: Int = _byte_at(h, n - 2);
  if b0 != 91 || b1 != 34 || bl != 93 || bp != 34 {
    return _err_str("azure: malformed partition key header");
  }
  let v = base.azure_substr(h, 2, n - 2);
  var i = 0;
  while i < v.len() {
    let b: Int = _byte_at(v, i);
    if b == 34 || b == 92 {
      return _err_str("azure: malformed partition key header");
    }
    i = i + 1;
  }
  if !azure_cosmos_partition_key_value_valid(v) {
    return _err_str("azure: invalid partition key value");
  }
  return _ok_str(v);
}

// --------------------------------------------------
//  Documents
// --------------------------------------------------

/// TTL rule: -1 (no expiry) or 1..2^31-1 seconds; 0 is rejected.
pub fn azure_cosmos_ttl_valid(ttl: Int) -> Bool {
  if ttl == AZURE_COSMOS_TTL_NO_EXPIRY {
    return true;
  }
  if ttl < 1 {
    return false;
  }
  if ttl > 2147483647 {
    return false;
  }
  return true;
}

/// Document shape: valid id, valid partition key value, valid TTL.
pub fn azure_cosmos_document_valid(id: Str, partition_key: Str, ttl: Int) -> Bool {
  if !azure_cosmos_name_valid(id) {
    return false;
  }
  if !azure_cosmos_partition_key_value_valid(partition_key) {
    return false;
  }
  return azure_cosmos_ttl_valid(ttl);
}

/// REST path "dbs/{db}/colls/{coll}/docs/{id}".
pub fn azure_cosmos_document_path(db: Str, coll: Str, id: Str) -> Result[Str, Str] {
  if !azure_cosmos_db_name_valid(db) {
    return _err_str("azure: invalid database name");
  }
  if !azure_cosmos_container_name_valid(coll) {
    return _err_str("azure: invalid container name");
  }
  if !azure_cosmos_name_valid(id) {
    return _err_str("azure: invalid document id");
  }
  return _ok_str("dbs/" + db + "/colls/" + coll + "/docs/" + id);
}

// --------------------------------------------------
//  Consistency and throughput
// --------------------------------------------------

/// True for a pinned consistency-level constant.
pub fn azure_cosmos_consistency_valid(level: Int) -> Bool {
  if level < AZURE_COSMOS_CONSISTENCY_STRONG {
    return false;
  }
  if level > AZURE_COSMOS_CONSISTENCY_EVENTUAL {
    return false;
  }
  return true;
}

/// Consistency-level name (unknown -> "unknown").
pub fn azure_cosmos_consistency_name(level: Int) -> Str {
  if level == AZURE_COSMOS_CONSISTENCY_STRONG {
    return "strong";
  }
  if level == AZURE_COSMOS_CONSISTENCY_BOUNDED_STALENESS {
    return "bounded_staleness";
  }
  if level == AZURE_COSMOS_CONSISTENCY_SESSION {
    return "session";
  }
  if level == AZURE_COSMOS_CONSISTENCY_CONSISTENT_PREFIX {
    return "consistent_prefix";
  }
  if level == AZURE_COSMOS_CONSISTENCY_EVENTUAL {
    return "eventual";
  }
  return "unknown";
}

/// Normalize RU/s to the Azure ladder: at least 400, rounded up to the next
/// 100, capped at 1,000,000.
pub fn azure_cosmos_throughput_normalize(ru: Int) -> Int {
  if ru <= AZURE_COSMOS_RU_MIN {
    return AZURE_COSMOS_RU_MIN;
  }
  var v = ru;
  if v % AZURE_COSMOS_RU_STEP != 0 {
    v = ((v / AZURE_COSMOS_RU_STEP) + 1) * AZURE_COSMOS_RU_STEP;
  }
  if v > AZURE_COSMOS_RU_MAX {
    v = AZURE_COSMOS_RU_MAX;
  }
  return v;
}

// --------------------------------------------------
//  Status classification
// --------------------------------------------------

/// Canonical error name for a Cosmos DB status code ("" when not an error).
pub fn azure_cosmos_status_error(status: Int) -> Str {
  if status == 400 {
    return "BadRequest";
  }
  if status == 401 {
    return "Unauthorized";
  }
  if status == 403 {
    return "Forbidden";
  }
  if status == 404 {
    return "NotFound";
  }
  if status == 408 {
    return "RequestTimeout";
  }
  if status == 409 {
    return "Conflict";
  }
  if status == 412 {
    return "PreconditionFailed";
  }
  if status == 413 {
    return "RequestEntityTooLarge";
  }
  if status == 429 {
    return "TooManyRequests";
  }
  if status == 449 {
    return "RetryWith";
  }
  if status == 503 {
    return "ServiceUnavailable";
  }
  return "";
}

/// True for statuses worth retrying: 408, 429, 449, 503.
pub fn azure_cosmos_status_retryable(status: Int) -> Bool {
  if status == 408 {
    return true;
  }
  if status == 429 {
    return true;
  }
  if status == 449 {
    return true;
  }
  if status == 503 {
    return true;
  }
  return false;
}
