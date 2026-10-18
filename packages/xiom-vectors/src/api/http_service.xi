// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.api.http_service

// In-repo HTTP/1.1 service skeleton (M-S1). Transport-agnostic: the whole
// service is `http_service_handle(eng, raw_bytes) -> response_bytes` -- a
// pure byte-in/byte-out pipeline (parse -> route -> JSON -> serialize), so
// it is fully deterministic and testable. Endpoints:
//
//   GET    /health                      -> {"status":"ok","service":"xvector"}
//   GET    /version                     -> {"name","version","api"}
//   GET    /collections                 -> {"collections":[...]}
//   POST   /collections                 -> {"name","dim","metric"} -> 201
//                                          optional index config:
//                                          {"index":"hnsw","m","ef_construction",
//                                          "ef_search"} (default flat)
//   GET    /collections/{n}/points?id=  -> {"id","vector"}
//   POST   /collections/{n}/points      -> {"ids":[...],"vectors":[[...]]}
//   DELETE /collections/{n}/points?id=  -> {"removed":true}
//   GET    /stats?collection={n}        -> per-collection stats JSON
//   POST   /search                      -> knn/range/pagination; a
//                                          {"requests":[{...},{...}]} body
//                                          runs a batch; optional
//                                          `ef_search` = per-request beam
//
// Errors are {"error":"..."} with honest statuses (400/404/405/409/500).
// Requests are strict: CRLF framing, Content-Length must match the body
// exactly, unknown routes 404, wrong methods 405. Limits/config/auth (S2/S3)
// and the real socket adapter (stdlib `xiom.net`, gated on the C-PULSE-02
// proof) are deliberately out of this module: it stays transport-agnostic.

use xiom.convert;
use xiom.io;
use xiom.string.slice;
use xiom.serialize.json;
use xiom.os.env;
use xiom.time;
use xiom.crypto.mac;
use xiom.rate;
use xiom.http.status;
use xiom.vector.observability.metrics;
use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.core.shim;
use xiom.vector.primitives;
use xiom.vector.index.ann_index;
use xiom.vector.query.search_request;
use xiom.vector.query.search_service;
use xiom.vector.durability.wal_file;
use xiom.vector.api.json_fast;

// ---- Request model + parsing ----

pub type HttpRequest = {
  ok: Bool;
  incomplete: Bool;
  method: Str;
  path: Str;
  query: Str;
  header_names: Vec[Str];
  header_values: Vec[Str];
  body: Str;
  // The raw body bytes (linear copy from the request buffer): the fast
  // upsert scanner and any byte-level consumer use these directly --
  // `str_bytes`/`str_slice` on big Strs are quadratic on this stdlib pin
  // (REL-20261011-1453-xvector).
  body_bytes: Vec[UInt8];
}

fn bytes_to_str(b: &Vec[UInt8], from: Int, to: Int) -> Str {
  var acc = Vec[UInt8].new();
  var i: Int = from;
  while i < to {
    acc.push(b[i]);
    i = i + 1;
  }
  return Str::from_utf8(&acc);
}

// ASCII-lowercase (header names; requests are ASCII in practice).
fn ascii_lower(s: Str) -> Str {
  var b = slice.str_bytes(s);
  var i: Int = 0;
  while i < b.len() {
    if b[i] >= 65 && b[i] <= 90 { b[i] = b[i] + 32; }
    i = i + 1;
  }
  return Str::from_utf8(&b);
}

// Byte index of "\r\n\r\n" or -1.
fn find_head_end(b: &Vec[UInt8]) -> Int {
  var i: Int = 0;
  while i + 3 < b.len() {
    if b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10 { return i; }
    i = i + 1;
  }
  return -1;
}

pub fn http_parse_request(raw: &Vec[UInt8]) -> HttpRequest {
  var req = HttpRequest{
    ok: false,
    incomplete: false,
    method: "",
    path: "",
    query: "",
    header_names: Vec[Str].new(),
    header_values: Vec[Str].new(),
    body: "",
    body_bytes: Vec[UInt8].new(),
  };
  var term = find_head_end(raw);
  if term < 0 {
    req.incomplete = true;
    return req;
  }
  // Request line: METHOD SP PATH [SP HTTP/x.y]
  var line_end: Int = 0;
  while line_end < term && !(raw[line_end] == 13 && raw[line_end + 1] == 10) {
    line_end = line_end + 1;
  }
  if line_end >= term { return req; }
  var sp1: Int = -1;
  var i: Int = 0;
  while i < line_end {
    if raw[i] == 32 {
      sp1 = i;
      i = line_end;
    } else {
      i = i + 1;
    }
  }
  if sp1 <= 0 { return req; }
  var sp2: Int = -1;
  i = sp1 + 1;
  while i < line_end {
    if raw[i] == 32 {
      sp2 = i;
      i = line_end;
    } else {
      i = i + 1;
    }
  }
  var path_end: Int = line_end;
  if sp2 > 0 { path_end = sp2; }
  // The head is ASCII in practice: materialize it once and slice.
  var full = Str::from_utf8(raw);
  var method = slice.str_slice(full, 0, sp1);
  if !(method == "GET") && !(method == "POST") && !(method == "PUT") && !(method == "DELETE") {
    return req;
  }
  req.method = method;
  var raw_path = slice.str_slice(full, sp1 + 1, path_end);
  // Split optional query.
  var qpos: Int = -1;
  var pb = slice.str_bytes(raw_path);
  i = 0;
  while i < pb.len() {
    if pb[i] == 63 {
      qpos = i;
      i = pb.len();
    } else {
      i = i + 1;
    }
  }
  if qpos >= 0 {
    req.path = slice.str_slice(raw_path, 0, qpos);
    req.query = slice.str_slice(raw_path, qpos + 1, pb.len());
  } else {
    req.path = raw_path;
  }
  // Header lines. NOTE: the LAST header's CRLF is the head terminator, so
  // the scan must be allowed to reach `term` (a `lend < term` bound drops
  // the final header, e.g. Content-Length).
  var pos: Int = line_end + 2;
  while pos < term {
    var lend: Int = pos;
    while lend + 1 < raw.len() && !(raw[lend] == 13 && raw[lend + 1] == 10) {
      lend = lend + 1;
    }
    if lend + 1 >= raw.len() { break; }
    if lend > term { break; }
    // name ":" value
    var colon: Int = -1;
    i = pos;
    while i < lend {
      if raw[i] == 58 {
        colon = i;
        i = lend;
      } else {
        i = i + 1;
      }
    }
    if colon > pos {
      var name = ascii_lower(slice.str_slice(full, pos, colon));
      var vfrom: Int = colon + 1;
      while vfrom < lend && raw[vfrom] == 32 { vfrom = vfrom + 1; }
      var vto: Int = lend;
      while vto > vfrom && raw[vto - 1] == 32 { vto = vto - 1; }
      req.header_names.push(name);
      req.header_values.push(slice.str_slice(full, vfrom, vto));
    }
    pos = lend + 2;
  }
  // Body per Content-Length (strict: no trailing bytes).
  var cl: Int = 0;
  var hl = http_header(&req, "content-length");
  var clerr: Bool = false;
  match hl {
    Some(v) => {
      var vb = slice.str_bytes(v);
      var r = parse_int_at(vb, 0);
      if r.ok && r.pos == vb.len() && vb.len() > 0 {
        cl = r.value;
      } else {
        clerr = true;
      }
    }
    None => {}
  }
  if clerr { return req; }
  var body_len: Int = raw.len() - (term + 4);
  if body_len < cl {
    req.incomplete = true;
    return req;
  }
  if body_len > cl { return req; }
  // Body as BYTES (linear copy; the Str form below is for the strict path
  // -- from_utf8 is linear, whereas str_bytes/str_slice on the request Str
  // are quadratic on this stdlib pin, REL-20261011-1453-xvector).
  var bb = Vec[UInt8].new();
  var bi = term + 4;
  while bi < raw.len() {
    bb.push(raw[bi]);
    bi = bi + 1;
  }
  req.body_bytes = bb;
  req.body = Str::from_utf8(&bb);
  req.ok = true;
  return req;
}

pub fn http_header(req: &HttpRequest, name: Str) -> Option[Str] {
  var i: Int = 0;
  while i < req.header_names.len() {
    if req.header_names[i] == name {
      return Some(req.header_values[i]);
    }
    i = i + 1;
  }
  return None;
}

// ---- Service config + limits (M-S2) ----

// Hard limits enforced at the service edge. Defaults are deliberately
// generous but finite; environment variables (XVECTOR_MAX_*) and a
// key=value config file can lower them.
pub type ServiceConfig = {
  max_request_bytes: Int;
  max_top_k: Int;
  max_batch: Int;
  max_dim: Int;
  // Canonical upsert bodies take the lane-local fast scanner
  // (`api.json_fast`) instead of the generic parser; disable for
  // equivalence testing (the probe gates byte-equal responses).
  fast_upsert: Bool;
}

pub fn service_config_default() -> ServiceConfig {
  return ServiceConfig{
    max_request_bytes: 65536,
    max_top_k: 1000,
    max_batch: 256,
    max_dim: 1024,
    fast_upsert: true,
  };
}

// Apply one `key=value` pair; false when the key is unknown (ignored by
// loaders) -- values below 1 are rejected by the caller as malformed.
pub fn service_config_apply(cfg: &mut ServiceConfig, key: Str, value: Int) -> Bool {
  if value < 1 { return false; }
  if key == "max_request_bytes" {
    cfg.max_request_bytes = value;
    return true;
  }
  if key == "max_top_k" {
    cfg.max_top_k = value;
    return true;
  }
  if key == "max_batch" {
    cfg.max_batch = value;
    return true;
  }
  if key == "max_dim" {
    cfg.max_dim = value;
    return true;
  }
  return false;
}

fn env_apply(cfg: &mut ServiceConfig, env_name: Str, key: Str) -> Bool {
  var got = env.var_opt(env_name);
  match got {
    Some(v) => {
      var vb = slice.str_bytes(v);
      var r = parse_int_at(vb, 0);
      if r.ok && r.pos == vb.len() && vb.len() > 0 {
        return service_config_apply(cfg, key, r.value);
      }
    }
    None => {}
  }
  return false;
}

// Environment overrides: XVECTOR_MAX_REQUEST_BYTES / XVECTOR_MAX_TOP_K /
// XVECTOR_MAX_BATCH / XVECTOR_MAX_DIM. Malformed values are ignored
// (defaults/previous values stay); returns the number applied.
pub fn service_config_from_env(cfg: &mut ServiceConfig) -> Int {
  var n: Int = 0;
  if env_apply(cfg, "XVECTOR_MAX_REQUEST_BYTES", "max_request_bytes") { n = n + 1; }
  if env_apply(cfg, "XVECTOR_MAX_TOP_K", "max_top_k") { n = n + 1; }
  if env_apply(cfg, "XVECTOR_MAX_BATCH", "max_batch") { n = n + 1; }
  if env_apply(cfg, "XVECTOR_MAX_DIM", "max_dim") { n = n + 1; }
  return n;
}

pub type LoadedServiceConfig = {
  valid: Bool;
  loaded: Bool;
  cfg: ServiceConfig;
}

// Config file: `key=value` lines (`#` comments, blank lines skipped, CRLF
// tolerated). Unknown keys are ignored (forward-compatible); a malformed
// line sets valid=false while the valid lines still apply. Missing or
// empty files report loaded=false (defaults stay).
pub fn service_config_load(path: Str) -> LoadedServiceConfig {
  var out = LoadedServiceConfig{ valid: false, loaded: false, cfg: service_config_default() };
  if !io.file_exists(path) { return out; }
  var fsz = io.file_size(path);
  var sz: Int = -1;
  match fsz {
    Some(n) => { sz = n; }
    None => { return out; }
  }
  if sz < 1 { return out; }
  var rb = io.read_file_bytes(path);
  var b = Vec[UInt8].new();
  match rb {
    Ok(x) => { b = x; }
    Err(_) => { return out; }
  }
  out.loaded = true;
  out.valid = true;
  var pos: Int = 0;
  while pos < b.len() {
    var lend: Int = pos;
    while lend < b.len() && b[lend] != 10 { lend = lend + 1; }
    var lto: Int = lend;
    if lto > pos && b[lto - 1] == 13 { lto = lto - 1; }
    if lto > pos && b[pos] != 35 {
      var eq: Int = -1;
      var i: Int = pos;
      while i < lto {
        if b[i] == 61 {
          eq = i;
          i = lto;
        } else {
          i = i + 1;
        }
      }
      if eq > pos {
        var key = bytes_to_str(&b, pos, eq);
        var vb2 = Vec[UInt8].new();
        var j: Int = eq + 1;
        while j < lto {
          vb2.push(b[j]);
          j = j + 1;
        }
        var r2 = parse_int_at(vb2, 0);
        if !r2.ok || r2.pos != vb2.len() || r2.value < 1 {
          out.valid = false;
        } else {
          if !service_config_apply(&mut out.cfg, key, r2.value) {
            // unknown key: ignored on purpose
          }
        }
      } else {
        out.valid = false;
      }
    }
    pos = lend + 1;
  }
  return out;
}

// Graceful shutdown (M-S2): embedded mode has no in-flight requests
// (drain is a no-op), so the durable action is the whole-file WAL
// checkpoint. False when the checkpoint cannot be written.
pub fn http_service_shutdown(eng: &VectorEngine, wal_path: Str) -> Bool {
  return wal_persist(&eng.wal, wal_path);
}

// ---- Auth + rate limiting (M-S3) ----

pub enum ApiScope {
  Read,
  Write,
  Admin,
}

pub type ApiKey = {
  key: Str;
  scope: ApiScope;
}

// Service auth state: disabled by default (embedded mode); the socket/
// service adapter enables it. Keys are checked with the stdlib
// constant-time comparator (xiom.crypto.mac.constant_time_eq).
pub type ServiceAuth = {
  enabled: Bool;
  keys: Vec[ApiKey];
}

pub fn service_auth_new() -> ServiceAuth {
  return ServiceAuth{ enabled: false, keys: Vec[ApiKey].new() };
}

pub fn scope_code(s: ApiScope) -> Int {
  if s == ApiScope.Write { return 1; }
  if s == ApiScope.Admin { return 2; }
  return 0;
}

// Key rules: 8..128 chars from [A-Za-z0-9_.-].
pub fn api_key_valid(key: Str) -> Bool {
  var b = slice.str_bytes(key);
  if b.len() < 8 || b.len() > 128 { return false; }
  var i: Int = 0;
  while i < b.len() {
    var c = b[i];
    var okc: Bool = (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95 || c == 45 || c == 46;
    if !okc { return false; }
    i = i + 1;
  }
  return true;
}

// Add a key: rejects invalid keys and duplicates; the first accepted key
// enables auth.
pub fn service_auth_add_key(auth: &mut ServiceAuth, key: Str, scope: ApiScope) -> Bool {
  if !api_key_valid(key) { return false; }
  var i: Int = 0;
  while i < auth.keys.len() {
    if auth.keys[i].key == key { return false; }
    i = i + 1;
  }
  auth.keys.push(ApiKey{ key: key, scope: scope });
  auth.enabled = true;
  return true;
}

pub fn auth_lookup(auth: &ServiceAuth, presented: Str) -> Option[ApiScope] {
  var pb = slice.str_bytes(presented);
  var found: Bool = false;
  var scope: ApiScope = ApiScope.Read;
  var i: Int = 0;
  while i < auth.keys.len() {
    var kb = slice.str_bytes(auth.keys[i].key);
    if mac.constant_time_eq(&pb, &kb) {
      found = true;
      scope = auth.keys[i].scope;
    }
    i = i + 1;
  }
  if !found { return None; }
  return Some(scope);
}

fn scope_from_name(s: Str) -> Option[ApiScope] {
  if s == "read" { return Some(ApiScope.Read); }
  if s == "write" { return Some(ApiScope.Write); }
  if s == "admin" { return Some(ApiScope.Admin); }
  return None;
}

// Parse a comma-separated `key:scope` list (used by the env loader and
// tests); malformed entries are skipped. Returns the number added.
pub fn service_auth_parse_list(auth: &mut ServiceAuth, list: Str) -> Int {
  var added: Int = 0;
  var b = slice.str_bytes(list);
  var start: Int = 0;
  var i: Int = 0;
  while i <= b.len() {
    if i == b.len() || b[i] == 44 {
      var colon: Int = -1;
      var j: Int = start;
      while j < i {
        if b[j] == 58 {
          colon = j;
          j = i;
        } else {
          j = j + 1;
        }
      }
      if colon > start {
        var key = bytes_to_str(&b, start, colon);
        var sc = bytes_to_str(&b, colon + 1, i);
        match scope_from_name(sc) {
          Some(sc2) => {
            if service_auth_add_key(auth, key, sc2) { added = added + 1; }
          }
          None => {}
        }
      }
      start = i + 1;
    }
    i = i + 1;
  }
  return added;
}

// Env loader: XVECTOR_API_KEYS="key1:admin,key2:read". Returns the number
// of keys added; a missing variable adds none (auth stays disabled).
pub fn service_auth_from_env(auth: &mut ServiceAuth) -> Int {
  var got = env.var_opt("XVECTOR_API_KEYS");
  match got {
    Some(v) => { return service_auth_parse_list(auth, v); }
    None => {}
  }
  return 0;
}

// Token-bucket rate limiter backed by the `xiom.rate` registry package
// (adoption 2026-10-10; see docs/XIOM-RATE-ADOPTION.md). `enabled` gates
// the limiter (capacity < 1 -> disabled: the same construction policy as
// before) and `now_ms` stays explicit so the math is deterministic in
// tests (the service passes monotonic time). The package carries unearned
// sub-token remainders across calls, so fractional refill is now exact
// (the pre-adoption lane limiter consumed the whole elapsed span and
// discarded the remainder); every gate-visible boundary -- capacity
// drain, rate 0, whole-second refill -- is unchanged.
pub type RateLimiter = {
  enabled: Bool;
  bucket: TokenBucket;
}

pub fn rate_limiter_disabled() -> RateLimiter {
  return RateLimiter{ enabled: false, bucket: rate_bucket_new(1, 0, 0) };
}

pub fn rate_limiter_new(capacity: Int, refill_per_sec: Int) -> RateLimiter {
  if capacity < 1 { return rate_limiter_disabled(); }
  return RateLimiter{ enabled: true, bucket: rate_bucket_new(capacity, refill_per_sec, 0) };
}

pub fn rate_limiter_allow(lim: &mut RateLimiter, now_ms: Int) -> Bool {
  if !lim.enabled { return true; }
  // Nested-field mutation through a &mut param does not persist (XVC-C-09
  // family): copy the bucket out, mutate, write back once.
  var b = lim.bucket;
  var ok = rate_bucket_allow(&mut b, now_ms, 1);
  lim.bucket = b;
  return ok;
}

// The full service state: limits/config (S2), auth (S3), rate limiting,
// plus the observability bundle (M-O): counters/histograms + the bounded
// structured-log ring. `replica_lag` is the L-4 follower watermark delta
// (-1 = not a replica); /stats and /metrics surface it when >= 0.
pub type ServiceState = {
  cfg: ServiceConfig;
  auth: ServiceAuth;
  rate: RateLimiter;
  metrics: ServiceMetrics;
  log: LogRing;
  replica_lag: Int;
}

pub fn service_state_new() -> ServiceState {
  return ServiceState{
    cfg: service_config_default(),
    auth: service_auth_new(),
    rate: rate_limiter_disabled(),
    metrics: service_metrics_new(),
    log: log_ring_new(256, 250),
    replica_lag: -1,
  };
}

// Required scope for a routed request; None = public (/health only).
// Shared with the L-3 router (xiom.vector.api.router): the router edge
// applies the exact same scope map before forwarding.
pub fn required_scope(method: Str, path: Str) -> Option[ApiScope] {
  var segs = path_segments(path);
  if segs.len() == 1 && segs[0] == "health" { return None; }
  if segs.len() == 1 && segs[0] == "version" { return None; }
  if segs.len() == 1 && segs[0] == "collections" && method == "POST" { return Some(ApiScope.Admin); }
  if segs.len() == 3 && segs[0] == "collections" && segs[2] == "points" {
    if method == "POST" || method == "DELETE" { return Some(ApiScope.Write); }
    return Some(ApiScope.Read);
  }
  return Some(ApiScope.Read);
}

// Parse the 3-digit status from an assembled response (0 when unparseable).
// Shared with the L-3 router (stale-mapping retry inspects forwarded 404s).
pub fn response_status(resp: &Vec[UInt8]) -> Int {
  if resp.len() < 12 { return 0; }
  var d1 = (resp[9] as Int) - 48;
  var d2 = (resp[10] as Int) - 48;
  var d3 = (resp[11] as Int) - 48;
  if d1 < 0 || d1 > 9 || d2 < 0 || d2 > 9 || d3 < 0 || d3 > 9 { return 0; }
  return d1 * 100 + d2 * 10 + d3;
}

// Text response (prometheus exposition uses text/plain).
pub fn http_text_response(status: Int, body: Str) -> Vec[UInt8] {
  var bb = slice.str_bytes(body);
  var out = Vec[UInt8].new();
  append_bytes(&mut out, "HTTP/1.1 ");
  append_bytes(&mut out, convert.int_to_string(status));
  append_bytes(&mut out, " ");
  append_bytes(&mut out, status_text(status));
  append_bytes(&mut out, "\r\nContent-Type: text/plain; version=0.0.4\r\nContent-Length: ");
  append_bytes(&mut out, convert.int_to_string(bb.len()));
  append_bytes(&mut out, "\r\nConnection: close\r\n\r\n");
  var i: Int = 0;
  while i < bb.len() {
    out.push(bb[i]);
    i = i + 1;
  }
  return out;
}

// The Prometheus histogram block moved into observability.metrics as
// histogram_render_lines in the xiom.metrics adoption slice (consumers no
// longer name the value types; the byte output is unchanged).

// Prometheus-style exposition (O2): counters, latency histograms and live
// gauges from the engine (collections / active points / lsn).
fn render_metrics(eng: &VectorEngine, st: &ServiceState) -> Str {
  var out = "# TYPE xvector_requests_total counter\n";
  out = out + "xvector_requests_total " + convert.int_to_string(service_counter_value(&st.metrics.requests_total)) + "\n";
  out = out + "# TYPE xvector_errors_total counter\n";
  out = out + "xvector_errors_total " + convert.int_to_string(service_counter_value(&st.metrics.errors_total)) + "\n";
  out = out + "# TYPE xvector_search_ops counter\n";
  out = out + "xvector_search_ops " + convert.int_to_string(service_counter_value(&st.metrics.search_ops)) + "\n";
  out = out + "# TYPE xvector_upsert_ops counter\n";
  out = out + "xvector_upsert_ops " + convert.int_to_string(service_counter_value(&st.metrics.upsert_ops)) + "\n";
  out = out + "# TYPE xvector_auth_failures counter\n";
  out = out + "xvector_auth_failures " + convert.int_to_string(service_counter_value(&st.metrics.auth_failures)) + "\n";
  out = out + "# TYPE xvector_rate_limited counter\n";
  out = out + "xvector_rate_limited " + convert.int_to_string(service_counter_value(&st.metrics.rate_limited)) + "\n";
  out = out + histogram_render_lines("xvector_latency_ms", &st.metrics.latency_ms);
  out = out + histogram_render_lines("xvector_search_latency_ms", &st.metrics.search_latency_ms);
  out = out + "# TYPE xvector_collections gauge\n";
  out = out + "xvector_collections " + convert.int_to_string(engine_collection_count(eng)) + "\n";
  out = out + "# TYPE xvector_points_active gauge\n";
  out = out + "xvector_points_active " + convert.int_to_string(engine_size(eng)) + "\n";
  out = out + "# TYPE xvector_lsn gauge\n";
  out = out + "xvector_lsn " + convert.int_to_string(engine_durable_lsn(eng)) + "\n";
  if st.replica_lag >= 0 {
    out = out + "# TYPE xvector_replica_lag gauge\n";
    out = out + "xvector_replica_lag " + convert.int_to_string(st.replica_lag) + "\n";
  }
  return out;
}

// State-aware entry point (M-O): serves `GET /metrics` (public, like
// /health) straight from the state, then runs the inner pipeline
// (rate limit -> parse -> auth/scope -> route) and instruments it:
// request/error/auth/rate counters, latency histograms, and one bounded
// JSON log line per request (method/path/status/ms/slow).
pub fn http_service_handle_state(eng: &mut VectorEngine, raw: &Vec<UInt8], st: &mut ServiceState) -> Vec[UInt8] {
  var t0 = time.monotonic_ms();
  var req = http_parse_request(raw);
  var is_metrics: Bool = false;
  if req.ok && req.method == "GET" && req.path == "/metrics" { is_metrics = true; }
  var resp: Vec[UInt8] = Vec[UInt8].new();
  if is_metrics {
    resp = http_text_response(200, render_metrics(eng, st));
  } else {
    resp = handle_state_inner(eng, raw, st);
  }
  var t1 = time.monotonic_ms();
  var ms: Int = t1 - t0;
  if ms < 0 { ms = 0; }
  // Nested-field mutation through a &mut param does not persist (XVC-C-09
  // family): copy the metrics struct out, mutate, write back once.
  var mt = st.metrics;
  service_counter_inc(&mut mt.requests_total);
  histogram_observe(&mut mt.latency_ms, ms);
  var status = response_status(&resp);
  if status >= 400 { service_counter_inc(&mut mt.errors_total); }
  if status == 401 || status == 403 { service_counter_inc(&mut mt.auth_failures); }
  if status == 429 { service_counter_inc(&mut mt.rate_limited); }
  var m: Str = "";
  var p: Str = "";
  if req.ok {
    m = req.method;
    p = req.path;
  }
  if m == "POST" && p == "/search" {
    service_counter_inc(&mut mt.search_ops);
    histogram_observe(&mut mt.search_latency_ms, ms);
  }
  var segs = path_segments(p);
  if m == "POST" && segs.len() == 3 && segs[0] == "collections" && segs[2] == "points" {
    service_counter_inc(&mut mt.upsert_ops);
  }
  st.metrics = mt;
  log_ring_push(&mut st.log, m, p, status, ms);
  return resp;
}

// The pre-M-O state pipeline (unchanged semantics): rate limit -> parse
// -> auth/scope -> handle_cfg.
fn handle_state_inner(eng: &mut VectorEngine, raw: &Vec<UInt8>, st: &mut ServiceState) -> Vec[UInt8] {
  var now = time.monotonic_ms();
  if !rate_limiter_allow(&mut st.rate, now) {
    return jerror(429, "rate limit exceeded");
  }
  if st.auth.enabled {
    var req = http_parse_request(raw);
    if req.ok {
      var need_opt = required_scope(req.method, req.path);
      match need_opt {
        Some(need) => {
          var presented: Str = "";
          var have: Bool = false;
          match http_header(&req, "x-api-key") {
            Some(k) => {
              presented = k;
              have = true;
            }
            None => {}
          }
          if !have { return jerror(401, "missing api key"); }
          match auth_lookup(&st.auth, presented) {
            Some(got) => {
              if scope_code(got) < scope_code(need) {
                return jerror(403, "insufficient scope");
              }
            }
            None => { return jerror(401, "invalid api key"); }
          }
        }
        None => {}
      }
    }
  }
  if raw.len() > st.cfg.max_request_bytes {
    return jerror(413, "request exceeds service limit");
  }
  if st.replica_lag >= 0 {
    // Follower mode (L-4): GET /stats carries the replica lag from the
    // state layer (handle_cfg has no ServiceState). Auth has already
    // passed (the scope map gives /stats read scope) and the size gate
    // mirrors handle_cfg's.
    var req2 = http_parse_request(raw);
    if req2.ok && req2.method == "GET" && req2.path == "/stats" {
      return handle_stats(eng, req2.query, st.replica_lag);
    }
  }
  return http_service_handle_cfg(eng, raw, &st.cfg);
}

// ---- Response writing ----

// Status reason phrases come from the xiom.http package (adoption
// 2026-10-10; re-synced to 0.1.6 on 2026-10-11 after the 507 gap closed
// upstream; docs/XIOM-HTTP-EVAL.md). Lane delta kept deliberately: codes
// outside the package table fall back to "Error" (the package returns
// "Unknown" by documented contract), so every code the service emits
// keeps its pre-adoption text byte-for-byte (probe_http_service pins the
// raw 507 line; probe_package_http pins the native 507 entry).
fn status_text(status: Int) -> Str {
  var t = http_status_text(status);
  if t != "Unknown" { return t; }
  return "Error";
}

// Stable error kinds for the JSON error model (mapped from statuses and
// from CoreError; consumers can switch on `kind` without parsing text).
fn kind_for_status(status: Int) -> Str {
  if status == 400 { return "invalid_input"; }
  if status == 401 { return "unauthorized"; }
  if status == 403 { return "forbidden"; }
  if status == 404 { return "not_found"; }
  if status == 405 { return "method_not_allowed"; }
  if status == 409 { return "conflict"; }
  if status == 413 { return "too_large"; }
  if status == 429 { return "rate_limited"; }
  if status == 501 { return "unsupported"; }
  if status == 507 { return "capacity_exceeded"; }
  return "internal";
}

pub fn http_response(status: Int, doc: JsonValue) -> Vec[UInt8] {
  var body = json.json_stringify(doc);
  var bb = slice.str_bytes(body);
  var out = Vec[UInt8].new();
  append_bytes(&mut out, "HTTP/1.1 ");
  append_bytes(&mut out, convert.int_to_string(status));
  append_bytes(&mut out, " ");
  append_bytes(&mut out, status_text(status));
  append_bytes(&mut out, "\r\nContent-Type: application/json\r\nContent-Length: ");
  append_bytes(&mut out, convert.int_to_string(bb.len()));
  append_bytes(&mut out, "\r\nConnection: close\r\n\r\n");
  var i: Int = 0;
  while i < bb.len() {
    out.push(bb[i]);
    i = i + 1;
  }
  return out;
}

// Stable wire errors (shared with the L-3 router: same {error,kind,status}).
pub fn jerror(status: Int, msg: Str) -> Vec[UInt8] {
  var o = json.json_object_new();
  o = json.json_set(o, "error", json.json_string(msg));
  o = json.json_set(o, "kind", json.json_string(kind_for_status(status)));
  o = json.json_set(o, "status", json.json_number(status as Float64));
  return http_response(status, o);
}

// ---- JSON field helpers (copy out of Option before matching) ----

// Pre-parse depth guard (M-S4): the stdlib JSON parser recurses per
// nesting level, so a ~64 KB run of '[' (within the body limit) overflows
// the stack (access violation; found by probe_http_fuzz). This linear scan
// caps nesting depth BEFORE the parser sees the body; string state is
// tracked so brackets inside strings do not count.
pub fn json_depth_ok(body: Str, max_depth: Int) -> Bool {
  var b = slice.str_bytes(body);
  var depth: Int = 0;
  var in_str: Bool = false;
  var esc: Bool = false;
  var i: Int = 0;
  while i < b.len() {
    var c = b[i];
    if in_str {
      if esc {
        esc = false;
      } elif c == 92 {
        esc = true;
      } elif c == 34 {
        in_str = false;
      }
    } else {
      if c == 34 {
        in_str = true;
      } elif c == 91 || c == 123 {
        depth = depth + 1;
        if depth > max_depth { return false; }
      } elif c == 93 || c == 125 {
        depth = depth - 1;
      }
    }
    i = i + 1;
  }
  return true;
}

fn jget_str(v: JsonValue, key: Str) -> Option[Str] {
  match json.json_get(v, key) {
    Some(f) => {
      match f {
        String(s) => { return Some(s); }
        _ => {}
      }
    }
    None => {}
  }
  return None;
}

fn jget_num(v: JsonValue, key: Str) -> Option[Float64] {
  match json.json_get(v, key) {
    Some(f) => {
      match f {
        Number(n) => { return Some(n); }
        _ => {}
      }
    }
    None => {}
  }
  return None;
}

fn jv_to_vector(arr: JsonValue) -> Option[Vector] {
  match arr {
    Array(items) => {
      if items.len() == 0 { return None; }
      var v = Vector.new(items.len());
      var i: Int = 0;
      while i < items.len() {
        match items[i] {
          Number(n) => { v.set(i, n as Float32); }
          _ => { return None; }
        }
        i = i + 1;
      }
      return Some(v);
    }
    _ => {}
  }
  return None;
}

fn jv_to_int_array(arr: JsonValue) -> Option[Vec[Int]] {
  match arr {
    Array(items) => {
      var out = Vec[Int].new();
      var i: Int = 0;
      while i < items.len() {
        match items[i] {
          Number(n) => { out.push(n as Int); }
          _ => { return None; }
        }
        i = i + 1;
      }
      return Some(out);
    }
    _ => {}
  }
  return None;
}

pub fn metric_from_name(s: Str) -> Option[DistanceMetric] {
  if s == "cosine" { return Some(DistanceMetric.Cosine); }
  if s == "dot" { return Some(DistanceMetric.DotProduct); }
  if s == "euclidean" { return Some(DistanceMetric.Euclidean); }
  return None;
}

fn metric_name_of(m: DistanceMetric) -> Str {
  if m == DistanceMetric.Cosine { return "cosine"; }
  if m == DistanceMetric.DotProduct { return "dot"; }
  return "euclidean";
}

fn index_kind_name_of(k: AnnIndexKind) -> Str {
  if k == AnnIndexKind.Hnsw { return "hnsw"; }
  if k == AnnIndexKind.Ivf { return "ivf"; }
  return "flat";
}

// ---- Path / query helpers (shared with the L-3 router) ----

pub fn path_segments(path: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  var b = slice.str_bytes(path);
  var start: Int = 0;
  var i: Int = 0;
  while i <= b.len() {
    if i == b.len() || b[i] == 47 {
      if i > start {
        out.push(bytes_to_str(&b, start, i));
      }
      start = i + 1;
    }
    i = i + 1;
  }
  return out;
}

pub fn query_param(query: Str, key: Str) -> Option[Str] {
  var b = slice.str_bytes(query);
  var start: Int = 0;
  var i: Int = 0;
  while i <= b.len() {
    if i == b.len() || b[i] == 38 {
      // segment [start, i): key=value
      var eq: Int = -1;
      var j: Int = start;
      while j < i {
        if b[j] == 61 {
          eq = j;
          j = i;
        } else {
          j = j + 1;
        }
      }
      if eq > start {
        var k = bytes_to_str(&b, start, eq);
        if k == key {
          return Some(bytes_to_str(&b, eq + 1, i));
        }
      }
      start = i + 1;
    }
    i = i + 1;
  }
  return None;
}

// ---- Search request from JSON ----

fn search_req_from_json(body: JsonValue) -> Option[SearchRequest] {
  var is_range: Bool = false;
  var mo = json.json_get(body, "mode");
  match mo {
    Some(mv) => {
      match mv {
        String(m) => {
          if m == "range" {
            is_range = true;
          } else if !(m == "knn") {
            return None;
          }
        }
        _ => { return None; }
      }
    }
    None => {}
  }
  var vec_opt = json.json_get(body, "vector");
  var vec = Vector.new(1);
  var have_vec: Bool = false;
  match vec_opt {
    Some(va) => {
      match jv_to_vector(va) {
        Some(v) => { vec = v; have_vec = true; }
        None => {}
      }
    }
    None => {}
  }
  if !have_vec { return None; }
  var k: Int = 10;
  var tk_opt = json.json_get(body, "top_k");
  match tk_opt {
    Some(tk) => {
      match tk {
        Number(n) => { k = n as Int; }
        _ => { return None; }
      }
    }
    None => {}
  }
  if k < 1 || k > 10000 { return None; }
  // metric defaults to the collection's metric at dispatch time; use
  // euclidean as a placeholder and overwrite in the router.
  var req = search_request_new(vec, k, DistanceMetric.Euclidean);
  if is_range {
    var radius: Float64 = 0.0;
    var ropt = json.json_get(body, "radius");
    match ropt {
      Some(rv) => {
        match rv {
          Number(r) => { radius = r; }
          _ => { return None; }
        }
      }
      None => {}
    }
    search_request_set_range(&mut req, radius as Float32);
  } else {
    var offset: Int = 0;
    var oopt = json.json_get(body, "offset");
    match oopt {
      Some(ov) => {
        match ov {
          Number(o) => { offset = o as Int; }
          _ => { return None; }
        }
      }
      None => {}
    }
    if offset > 0 { search_request_set_page(&mut req, offset); }
    var after: Int = -1;
    var aopt = json.json_get(body, "after_id");
    match aopt {
      Some(av) => {
        match av {
          Number(a) => { after = a as Int; }
          _ => { return None; }
        }
      }
      None => {}
    }
    if after >= 0 { search_request_set_after(&mut req, after); }
  }
  return Some(req);
}

fn hits_json(hits: &Vec[SearchHit]) -> JsonValue {
  var arr = json.json_array_new();
  var i: Int = 0;
  while i < hits.len() {
    var hit = json.json_object_new();
    hit = json.json_set(hit, "id", json.json_number(hits[i].id as Float64));
    hit = json.json_set(hit, "distance", json.json_number(hits[i].distance as Float64));
    arr = json.json_array_push(arr, hit);
    i = i + 1;
  }
  return arr;
}

// Dispatch a parsed request on the engine. `fallback` metric is used when
// the request body does not carry one (the body's metric must match the
// collection anyway; we always overwrite with the collection's).
fn run_search(eng: &mut VectorEngine, collection: Str, body: JsonValue, cfg: &ServiceConfig) -> Vec[UInt8] {
  var sel = select_collection(eng, collection);
  match sel {
    Ok(_) => {}
    Err(_) => { return jerror(404, "unknown collection"); }
  }
  // Optional per-request HNSW beam (benchmark sweeps): sets the active
  // collection's ef_search for this call only (no rebuild).
  var ef_opt = json.json_get(body, "ef_search");
  match ef_opt {
    Some(ev) => {
      match ev {
        Number(n) => {
          match engine_set_ef_search(eng, n as Int) {
            Ok(_) => {}
            Err(_) => { return jerror(400, "ef_search out of range"); }
          }
        }
        _ => { return jerror(400, "ef_search must be a number"); }
      }
    }
    None => {}
  }
  // Batch form?
  var batch_opt = json.json_get(body, "requests");
  var is_batch: Bool = false;
  var batch_items = Vec[JsonValue].new();
  match batch_opt {
    Some(b) => {
      match b {
        Array(items) => {
          if items.len() == 0 { return jerror(400, "empty batch"); }
          if items.len() > cfg.max_batch { return jerror(413, "batch exceeds service limit"); }
          batch_items = items;
          is_batch = true;
        }
        _ => {}
      }
    }
    None => {}
  }
  if is_batch {
    var sets = Vec[HydratedHits].new();
    var i: Int = 0;
    while i < batch_items.len() {
      match search_req_from_json(batch_items[i]) {
        Some(r) => {
          var rr = mutate_req(r, eng.metric);
          if rr.top_k > cfg.max_top_k { return jerror(400, "top_k exceeds service limit"); }
          match search_with_request(eng, &rr) {
            Ok(h) => { sets.push(h); }
            Err(e) => { return core_err_response(e); }
          }
        }
        None => { return jerror(400, "bad request element"); }
      }
      i = i + 1;
    }
    var out = json.json_object_new();
    var arr = json.json_array_new();
    var j: Int = 0;
    while j < sets.len() {
      arr = json.json_array_push(arr, hits_json(&sets[j].items));
      j = j + 1;
    }
    out = json.json_set(out, "results", arr);
    return http_response(200, out);
  }
  match search_req_from_json(body) {
    Some(r) => {
      var rr = mutate_req(r, eng.metric);
      if rr.top_k > cfg.max_top_k { return jerror(400, "top_k exceeds service limit"); }
      match search_with_request(eng, &rr) {
        Ok(h) => {
          var out = json.json_object_new();
          out = json.json_set(out, "hits", hits_json(&h.items));
          return http_response(200, out);
        }
        Err(e) => { return core_err_response(e); }
      }
    }
    None => {}
  }
  return jerror(400, "bad search body");
}

fn mutate_req(r: SearchRequest, metric: DistanceMetric) -> SearchRequest {
  var out = r;
  out.metric = metric;
  return out;
}

fn core_err_response(e: CoreError) -> Vec[UInt8] {
  match e {
    NotFound => { return jerror(404, "not found"); }
    InvalidInput(msg) => { return jerror(400, msg); }
    OutOfBounds => { return jerror(400, "out of bounds"); }
    Corruption(msg) => { return jerror(500, msg); }
    IOFailure(msg) => { return jerror(500, msg); }
    Unsupported(msg) => { return jerror(501, msg); }
    CapacityExceeded => { return jerror(507, "capacity exceeded"); }
    InvalidState(msg) => { return jerror(409, msg); }
    ChecksumMismatch => { return jerror(500, "checksum mismatch"); }
    VersionMismatch => { return jerror(409, "version mismatch"); }
  }
}

// ---- Route handlers ----

fn index_name_of_bool(hnsw: Bool) -> Str {
  if hnsw { return "hnsw"; }
  return "flat";
}

fn handle_create_collection(eng: &mut VectorEngine, body: JsonValue, cfg: &ServiceConfig) -> Vec[UInt8] {
  var name_opt = jget_str(body, "name");
  var name: Str = "";
  var have_name: Bool = false;
  match name_opt {
    Some(n) => { name = n; have_name = true; }
    None => {}
  }
  if !have_name { return jerror(400, "missing name"); }
  var dim: Int = 0;
  match jget_num(body, "dim") {
    Some(d) => { dim = d as Int; }
    None => {}
  }
  if dim > cfg.max_dim { return jerror(400, "dimension exceeds service limit"); }
  var mname_opt = jget_str(body, "metric");
  var metric: DistanceMetric = DistanceMetric.Euclidean;
  match mname_opt {
    Some(mn) => {
      match metric_from_name(mn) {
        Some(m) => { metric = m; }
        None => { return jerror(400, "unknown metric"); }
      }
    }
    None => { return jerror(400, "missing metric"); }
  }
  // Optional index configuration (benchmark/parity): {"index":"hnsw",
  // "m":16,"ef_construction":200,"ef_search":64}; default stays flat.
  var want_hnsw: Bool = false;
  var idx_opt = jget_str(body, "index");
  match idx_opt {
    Some(ix) => {
      if ix == "hnsw" { want_hnsw = true; }
      else if ix == "flat" { want_hnsw = false; }
      else { return jerror(400, "unknown index kind"); }
    }
    None => {}
  }
  var m: Int = 16;
  var efc: Int = 200;
  var efs: Int = 64;
  match jget_num(body, "m") {
    Some(v) => { m = v as Int; }
    None => {}
  }
  match jget_num(body, "ef_construction") {
    Some(v) => { efc = v as Int; }
    None => {}
  }
  match jget_num(body, "ef_search") {
    Some(v) => { efs = v as Int; }
    None => {}
  }
  var res = create_named_collection(eng, name, dim, metric);
  match res {
    Ok(_) => {
      if want_hnsw {
        var params = AnnParams{ m: m, ef_construction: efc, ef_search: efs };
        match engine_set_index(eng, AnnIndexKind.Hnsw, params) {
          Ok(_) => {}
          Err(_) => { return jerror(400, "invalid ann params"); }
        }
      }
      var out = json.json_object_new();
      out = json.json_set(out, "ok", json.json_bool(true));
      out = json.json_set(out, "name", json.json_string(name));
      out = json.json_set(out, "index", json.json_string(index_name_of_bool(want_hnsw)));
      return http_response(201, out);
    }
    Err(e) => {
      match e {
        InvalidInput(msg) => {
          if msg == "collection exists" { return jerror(409, msg); }
          return jerror(400, msg);
        }
        _ => { return jerror(500, "create failed"); }
      }
    }
  }
}

fn handle_upsert(eng: &mut VectorEngine, name: Str, body: JsonValue, cfg: &ServiceConfig) -> Vec[UInt8] {
  var sel = select_collection(eng, name);
  match sel {
    Ok(_) => {}
    Err(_) => { return jerror(404, "unknown collection"); }
  }
  var ids_opt = json.json_get(body, "ids");
  var ids = Vec[Int].new();
  var have_ids: Bool = false;
  match ids_opt {
    Some(ia) => {
      match jv_to_int_array(ia) {
        Some(x) => { ids = x; have_ids = true; }
        None => {}
      }
    }
    None => {}
  }
  var vecs_opt = json.json_get(body, "vectors");
  var vecs = Vec[Vector].new();
  var have_vecs: Bool = false;
  match vecs_opt {
    Some(va) => {
      match va {
        Array(items) => {
          var i: Int = 0;
          var okall: Bool = true;
          while i < items.len() {
            match jv_to_vector(items[i]) {
              Some(v) => { vecs.push(v); }
              None => { okall = false; }
            }
            i = i + 1;
          }
          have_vecs = okall;
        }
        _ => {}
      }
    }
    None => {}
  }
  if !have_ids || !have_vecs || ids.len() == 0 { return jerror(400, "bad points body"); }
  if ids.len() > cfg.max_batch { return jerror(413, "batch exceeds service limit"); }
  var res = upsert_many(eng, &ids, &vecs);
  match res {
    Ok(n) => {
      var out = json.json_object_new();
      out = json.json_set(out, "count", json.json_number(n as Float64));
      return http_response(200, out);
    }
    Err(e) => { return core_err_response(e); }
  }
}

// Fast-path upsert handler: identical tail to `handle_upsert` (same
// status codes and JSON), fed by the lane-local scanner.
fn handle_upsert_fast(eng: &mut VectorEngine, name: Str, f: &FastUpsert, cfg: &ServiceConfig) -> Vec[UInt8] {
  var sel = select_collection(eng, name);
  match sel {
    Ok(_) => {}
    Err(_) => { return jerror(404, "unknown collection"); }
  }
  if f.ids.len() == 0 { return jerror(400, "bad points body"); }
  if f.ids.len() > cfg.max_batch { return jerror(413, "batch exceeds service limit"); }
  var res = upsert_many(eng, &f.ids, &f.vectors);
  match res {
    Ok(n) => {
      var out = json.json_object_new();
      out = json.json_set(out, "count", json.json_number(n as Float64));
      return http_response(200, out);
    }
    Err(e) => { return core_err_response(e); }
  }
}

fn handle_stats(eng: &VectorEngine, query: Str, replica_lag: Int) -> Vec[UInt8] {
  var name_opt = query_param(query, "collection");
  var name = eng.active_name;
  var have_name: Bool = eng.active_idx >= 0;
  match name_opt {
    Some(n) => { name = n; have_name = true; }
    None => {}
  }
  if !have_name { return jerror(400, "missing collection"); }
  var res = collection_stats(eng, name);
  match res {
    Ok(st) => {
      var out = json.json_object_new();
      out = json.json_set(out, "name", json.json_string(st.name));
      out = json.json_set(out, "dim", json.json_number(st.dimension as Float64));
      out = json.json_set(out, "metric", json.json_string(metric_name_of(st.metric)));
      out = json.json_set(out, "index", json.json_string(index_kind_name_of(st.index_kind)));
      out = json.json_set(out, "points", json.json_number(st.points as Float64));
      out = json.json_set(out, "payloads", json.json_number(st.payloads as Float64));
      out = json.json_set(out, "nodes", json.json_number(st.nodes as Float64));
      out = json.json_set(out, "tombstones", json.json_number(st.tombstones as Float64));
      out = json.json_set(out, "lsn", json.json_number(st.wal_lsn as Float64));
      if replica_lag >= 0 {
        out = json.json_set(out, "replica_lag", json.json_number(replica_lag as Float64));
      }
      // M-D7 multi-segment visibility (active-collection perspective).
      out = json.json_set(out, "sealed_segments", json.json_number(engine_sealed_count(eng) as Float64));
      out = json.json_set(out, "sealed_loaded", json.json_number(engine_sealed_loaded(eng) as Float64));
      out = json.json_set(out, "sealed_missing", json.json_number(engine_sealed_missing(eng) as Float64));
      var mem = engine_memory_estimate(eng, st.name);
      match mem {
        Ok(m) => {
          out = json.json_set(out, "mem_store", json.json_number(m.store_bytes as Float64));
          out = json.json_set(out, "mem_graph", json.json_number(m.graph_bytes as Float64));
          out = json.json_set(out, "mem_payloads", json.json_number(m.payload_bytes as Float64));
          out = json.json_set(out, "mem_total", json.json_number(m.total_bytes as Float64));
          out = json.json_set(out, "mem_wal", json.json_number(m.wal_bytes as Float64));
        }
        Err(_) => {}
      }
      return http_response(200, out);
    }
    Err(_) => { return jerror(404, "unknown collection"); }
  }
}

// ---- The router (transport-agnostic entry point) ----

// Default-config entry point (S1-compatible).
pub fn http_service_handle(eng: &mut VectorEngine, raw: &Vec[UInt8]) -> Vec[UInt8] {
  var cfg = service_config_default();
  return http_service_handle_cfg(eng, raw, &cfg);
}

// Config-aware entry point (M-S2): enforces the request-size limit before
// any parsing and threads the configured limits into the handlers.
pub fn http_service_handle_cfg(eng: &mut VectorEngine, raw: &Vec[UInt8], cfg: &ServiceConfig) -> Vec[UInt8] {
  if raw.len() > cfg.max_request_bytes {
    return jerror(413, "request exceeds service limit");
  }
  var req = http_parse_request(raw);
  if !req.ok {
    if req.incomplete { return jerror(400, "incomplete request"); }
    return jerror(400, "malformed request");
  }
  var segs = path_segments(req.path);
    if segs.len() == 1 && segs[0] == "health" {
    if !(req.method == "GET") { return jerror(405, "method not allowed"); }
    var out = json.json_object_new();
    out = json.json_set(out, "status", json.json_string("ok"));
    out = json.json_set(out, "service", json.json_string("xvector"));
    out = json.json_set(out, "ready", json.json_bool(true));
    return http_response(200, out);
    }
    if segs.len() == 1 && segs[0] == "version" {
    if !(req.method == "GET") { return jerror(405, "method not allowed"); }
    var vo = json.json_object_new();
    vo = json.json_set(vo, "name", json.json_string("xvector"));
    vo = json.json_set(vo, "version", json.json_string("1.0.0-rc.1"));
    vo = json.json_set(vo, "api", json.json_number(1.0));
    return http_response(200, vo);
    }
  if segs.len() == 1 && segs[0] == "collections" {
    if req.method == "GET" {
      var cl = list_collections(eng);
      var arr = json.json_array_new();
      var i: Int = 0;
      while i < cl.names.len() {
        arr = json.json_array_push(arr, json.json_string(cl.names[i]));
        i = i + 1;
      }
      var out = json.json_object_new();
      out = json.json_set(out, "collections", arr);
      return http_response(200, out);
    }
    if req.method == "POST" {
      if !json_depth_ok(req.body, 64) { return jerror(400, "json nesting exceeds service limit"); }
      var parsed = json.json_parse(req.body);
      match parsed {
        Ok(body) => { return handle_create_collection(eng, body, cfg); }
        Err(_) => { return jerror(400, "bad json"); }
      }
    }
    return jerror(405, "method not allowed");
  }
  if segs.len() == 3 && segs[0] == "collections" && segs[2] == "points" {
    var name = segs[1];
  if req.method == "POST" {
  if !json_depth_ok(req.body, 64) { return jerror(400, "json nesting exceeds service limit"); }
  // Fast path: the canonical {"ids":[...],"vectors":[[...]]} body is
  // scanned directly (the generic parser is superlinear on numeric
  // payloads; REL-20261011-1453-xvector). None -> strict path below.
  if cfg.fast_upsert {
  var fast = json_fast_upsert_bytes(&req.body_bytes);
  match fast {
  Some(f) => { return handle_upsert_fast(eng, name, &f, cfg); }
  None => {}
  }
  }
  var parsed = json.json_parse(req.body);
  match parsed {
  Ok(body) => { return handle_upsert(eng, name, body, cfg); }
  Err(_) => { return jerror(400, "bad json"); }
  }
  }
    if req.method == "GET" {
      var id_opt = query_param(req.query, "id");
      var id: Int = -1;
      var have_id: Bool = false;
      match id_opt {
        Some(s) => {
          var vb = slice.str_bytes(s);
          var r = parse_int_at(vb, 0);
          if r.ok && r.pos == vb.len() && vb.len() > 0 {
            id = r.value;
            have_id = true;
          }
        }
        None => {}
      }
      if !have_id { return jerror(400, "missing id"); }
      var sel = select_collection(eng, name);
      match sel {
        Ok(_) => {}
        Err(_) => { return jerror(404, "unknown collection"); }
      }
      match get_point(eng, id) {
        Some(v) => {
          var arr = json.json_array_new();
          var i: Int = 0;
          while i < v.dimension {
            arr = json.json_array_push(arr, json.json_number(v.data[i] as Float64));
            i = i + 1;
          }
          var out = json.json_object_new();
          out = json.json_set(out, "id", json.json_number(id as Float64));
          out = json.json_set(out, "vector", arr);
          return http_response(200, out);
        }
        None => { return jerror(404, "unknown point"); }
      }
    }
    if req.method == "DELETE" {
      var id_opt2 = query_param(req.query, "id");
      var id2: Int = -1;
      var have_id2: Bool = false;
      match id_opt2 {
        Some(s) => {
          var vb = slice.str_bytes(s);
          var r = parse_int_at(vb, 0);
          if r.ok && r.pos == vb.len() && vb.len() > 0 {
            id2 = r.value;
            have_id2 = true;
          }
        }
        None => {}
      }
      if !have_id2 { return jerror(400, "missing id"); }
      var sel2 = select_collection(eng, name);
      match sel2 {
        Ok(_) => {}
        Err(_) => { return jerror(404, "unknown collection"); }
      }
      match delete_point(eng, id2) {
        Ok(removed) => {
          var out = json.json_object_new();
          out = json.json_set(out, "removed", json.json_bool(removed));
          return http_response(200, out);
        }
        Err(e) => { return core_err_response(e); }
      }
    }
    return jerror(405, "method not allowed");
  }
  if segs.len() == 1 && segs[0] == "search" {
    if !(req.method == "POST") { return jerror(405, "method not allowed"); }
    if !json_depth_ok(req.body, 64) { return jerror(400, "json nesting exceeds service limit"); }
    var parsed2 = json.json_parse(req.body);
    match parsed2 {
      Ok(body) => {
        var coll_opt = jget_str(body, "collection");
        var coll: Str = "";
        var have_coll: Bool = false;
        match coll_opt {
          Some(c) => { coll = c; have_coll = true; }
          None => {}
        }
        if !have_coll {
          if eng.active_idx >= 0 {
            coll = eng.active_name;
            have_coll = true;
          }
        }
        if !have_coll { return jerror(400, "missing collection"); }
        return run_search(eng, coll, body, cfg);
      }
      Err(_) => { return jerror(400, "bad json"); }
    }
  }
  if segs.len() == 1 && segs[0] == "stats" {
    if !(req.method == "GET") { return jerror(405, "method not allowed"); }
    return handle_stats(eng, req.query, -1);
  }
  return jerror(404, "unknown route");
}
