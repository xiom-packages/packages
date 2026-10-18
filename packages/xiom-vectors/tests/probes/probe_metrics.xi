// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Probe: observability (M-O / O1+O2; surface re-gated on the xiom.metrics
// 0.2.0 adoption). Verifies the histogram math (bucket placement,
// cumulative exposition, percentiles, package min/max/mean stats, empty),
// the service counters/histograms wired through http_service_handle_state,
// `GET /metrics` (public, text/plain, prometheus-style values incl. live
// gauges), `/health` readiness, the bounded JSON log ring (cap, drop
// count, sanitization, slow flag) and the auth/rate counter paths.
// Exit = failed checks.

module probe_metrics

use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.api.http_service;
use xiom.vector.observability.metrics;
use xiom.serialize.json;
use xiom.string.slice;
use xiom.io;
use xiom.convert;

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name); return fails + 1;
}

fn mk_req(method: Str, path: Str, body: Str) -> Vec[UInt8] {
  var bb = slice.str_bytes(body);
  var s = method + " " + path + " HTTP/1.1\r\nHost: t\r\nContent-Length: "
    + convert.int_to_string(bb.len()) + "\r\n\r\n" + body;
  return slice.str_bytes(s);
}

fn mk_req_key(method: Str, path: Str, body: Str, key: Str) -> Vec[UInt8] {
  var bb = slice.str_bytes(body);
  var s = method + " " + path + " HTTP/1.1\r\nHost: t\r\nX-Api-Key: " + key
    + "\r\nContent-Length: " + convert.int_to_string(bb.len()) + "\r\n\r\n" + body;
  return slice.str_bytes(s);
}

fn status_of(resp: &Vec[UInt8]) -> Int {
  if resp.len() < 12 { return -1; }
  var d1 = (resp[9] as Int) - 48;
  var d2 = (resp[10] as Int) - 48;
  var d3 = (resp[11] as Int) - 48;
  if d1 < 0 || d1 > 9 || d2 < 0 || d2 > 9 || d3 < 0 || d3 > 9 { return -1; }
  return d1 * 100 + d2 * 10 + d3;
}

fn find_term(b: &Vec[UInt8]) -> Int {
  var i: Int = 0;
  while i + 3 < b.len() {
    if b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10 { return i; }
    i = i + 1;
  }
  return -1;
}

fn resp_body(resp: &Vec[UInt8]) -> Str {
  var t = find_term(resp);
  if t < 0 { return ""; }
  var acc = Vec[UInt8].new();
  var i: Int = t + 4;
  while i < resp.len() {
    acc.push(resp[i]);
    i = i + 1;
  }
  return Str::from_utf8(&acc);
}

// Substring search over a Str body (Str BY VALUE: &Str params mislower,
// XVC-C-13).
fn body_has(body: Str, needle: Str) -> Bool {
  var b = slice.str_bytes(body);
  var n = slice.str_bytes(needle);
  if n.len() == 0 || n.len() > b.len() { return false; }
  var i: Int = 0;
  while i + n.len() <= b.len() {
    var j: Int = 0;
    var ok: Bool = true;
    while j < n.len() {
      if b[i + j] != n[j] {
        ok = false;
        j = n.len();
      } else {
        j = j + 1;
      }
    }
    if ok { return true; }
    i = i + 1;
  }
  return false;
}

fn main() -> Int {
  io.println("=== xvector probe: observability (M-O) ===");
  var fails: Int = 0;

  // ---- histogram math (xiom.metrics-backed lane surface) ----
  var h = histogram_new();
  fails = check(histogram_bounds_len(&h) == 7 && histogram_bucket_len(&h) == 8
    && histogram_count(&h) == 0 && histogram_percentile(&h, 50) == 0,
    "histogram: fresh bounds/counts + empty percentile", fails);
  histogram_observe(&mut h, 0);
  histogram_observe(&mut h, 1);
  histogram_observe(&mut h, 5);
  histogram_observe(&mut h, 12);
  histogram_observe(&mut h, 60);
  histogram_observe(&mut h, 120);
  histogram_observe(&mut h, 600);
  histogram_observe(&mut h, 1200);
  fails = check(histogram_bucket_count(&h, 0) == 2 && histogram_bucket_count(&h, 1) == 1
    && histogram_bucket_count(&h, 2) == 0 && histogram_bucket_count(&h, 3) == 1
    && histogram_bucket_count(&h, 4) == 1 && histogram_bucket_count(&h, 5) == 1
    && histogram_bucket_count(&h, 6) == 1 && histogram_bucket_count(&h, 7) == 1,
    "histogram: bucket placement exact", fails);
  fails = check(histogram_count(&h) == 8 && histogram_sum(&h) == 1998,
    "histogram: count + sum", fails);
  fails = check(histogram_percentile(&h, 50) == 50 && histogram_percentile(&h, 95) == 1001
    && histogram_percentile(&h, 99) == 1001,
    "histogram: p50/p95/p99 (upper bounds; +Inf sentinel)", fails);
  // Adoption alignment (2026-10-10): min/max/mean exist ONLY in the
  // package layer (the pre-adoption lane histogram had count/sum only);
  // asserting them pins xiom.metrics underneath the lane surface.
  fails = check(histogram_min(&h) == 0 && histogram_max(&h) == 1200 && histogram_mean(&h) == 249
    && histogram_bound(&h, 3) == 50,
    "histogram: package min/max/mean + bounds (xiom.metrics underneath)", fails);

  // ---- service counters via the state pipeline ----
  var eng = engine_new();
  var st = service_state_new();
  var c1 = http_service_handle_state(&mut eng, &mk_req("POST", "/collections",
    "{\"name\":\"mo\",\"dim\":2,\"metric\":\"euclidean\"}"), &mut st);
  var u1 = http_service_handle_state(&mut eng, &mk_req("POST", "/collections/mo/points",
    "{\"ids\":[1,2],\"vectors\":[[1,0],[0,1]]}"), &mut st);
  var s1 = http_service_handle_state(&mut eng, &mk_req("POST", "/search",
    "{\"collection\":\"mo\",\"vector\":[1,0],\"top_k\":2}"), &mut st);
  var s2 = http_service_handle_state(&mut eng, &mk_req("POST", "/search",
    "{\"collection\":\"mo\",\"vector\":[0,1],\"top_k\":1}"), &mut st);
  var s3 = http_service_handle_state(&mut eng, &mk_req("POST", "/search",
    "{\"collection\":\"mo\",\"vector\":[1,0],\"top_k\":1}"), &mut st);
  var e1 = http_service_handle_state(&mut eng, &mk_req("GET", "/nope", ""), &mut st);
  var e2 = http_service_handle_state(&mut eng, &mk_req("POST", "/search", "not json"), &mut st);
  fails = check(status_of(&c1) == 201 && status_of(&u1) == 200 && status_of(&s3) == 200
    && status_of(&e1) == 404 && status_of(&e2) == 400,
    "service: operations executed", fails);
  fails = check(service_counter_value(&st.metrics.requests_total) == 7
    && service_counter_value(&st.metrics.errors_total) == 2
    && service_counter_value(&st.metrics.search_ops) == 4
    && service_counter_value(&st.metrics.upsert_ops) == 1,
    "service: requests/errors/search/upsert counters exact (attempts counted)", fails);
  fails = check(histogram_count(&st.metrics.latency_ms) == 7
    && histogram_count(&st.metrics.search_latency_ms) == 4,
    "service: latency histograms observe every request / every search", fails);
  fails = check(st.log.lines.len() == 7 && st.log.dropped == 0,
    "service: log ring has one line per request", fails);

  // last line parses as JSON with the expected fields.
  var last = st.log.lines[st.log.lines.len() - 1];
  var parsed_ok: Bool = false;
  match json.json_parse(last) {
    Ok(lv) => {
      var method_ok: Bool = false;
      match json.json_get(lv, "method") {
        Some(f) => {
          match f {
            String(sm) => {
              if sm == "POST" { method_ok = true; }
            }
            _ => {}
          }
        }
        None => {}
      }
      var path_ok: Bool = false;
      match json.json_get(lv, "path") {
        Some(f2) => {
          match f2 {
            String(sp) => {
              if sp == "/search" { path_ok = true; }
            }
            _ => {}
          }
        }
        None => {}
      }
      parsed_ok = method_ok && path_ok;
    }
    Err(_) => {}
  }
  fails = check(parsed_ok, "log: last line is valid JSON with method/path fields", fails);

  // ---- /metrics exposition (public) ----
  var m1 = http_service_handle_state(&mut eng, &mk_req("GET", "/metrics", ""), &mut st);
  var mbody = resp_body(&m1);
  fails = check(status_of(&m1) == 200, "metrics: GET /metrics -> 200 without a key", fails);
  fails = check(body_has(mbody, "xvector_requests_total 7")
    && body_has(mbody, "xvector_errors_total 2")
    && body_has(mbody, "xvector_search_ops 4")
    && body_has(mbody, "xvector_upsert_ops 1"),
    "metrics: counters exposed with exact values", fails);
  fails = check(body_has(mbody, "xvector_collections 1")
    && body_has(mbody, "xvector_points_active 2")
    && body_has(mbody, "xvector_lsn "),
    "metrics: live gauges (collections/points/lsn)", fails);
  fails = check(body_has(mbody, "xvector_latency_ms_bucket{le=\"10\"}")
    && body_has(mbody, "xvector_latency_ms_bucket{le=\"+Inf\"}")
    && body_has(mbody, "xvector_latency_ms_p50 ")
    && body_has(mbody, "xvector_search_latency_ms_count 4"),
    "metrics: histograms exposed (buckets, +Inf, percentiles, search)", fails);
  var m2 = http_service_handle_state(&mut eng, &mk_req("GET", "/metrics", ""), &mut st);
  fails = check(body_has(resp_body(&m2), "xvector_requests_total 8"),
    "metrics: the scrape itself is counted", fails);

  // ---- /health readiness ----
  var hb = http_service_handle_state(&mut eng, &mk_req("GET", "/health", ""), &mut st);
  var hb_ok: Bool = false;
  match json.json_parse(resp_body(&hb)) {
    Ok(hv) => {
      match json.json_get(hv, "ready") {
        Some(rv) => {
          match rv {
            Bool(b) => {
              if b { hb_ok = true; }
            }
            _ => {}
          }
        }
        None => {}
      }
    }
    Err(_) => {}
  }
  fails = check(status_of(&hb) == 200 && hb_ok, "health: ready=true field present", fails);

  // ---- auth failures + rate limited counters ----
  var eng2 = engine_new();
  var st2 = service_state_new();
  service_auth_add_key(&mut st2.auth, "mo_read_0001", ApiScope.Read);
  var na = http_service_handle_state(&mut eng2, &mk_req("GET", "/collections", ""), &mut st2);
  var na2 = http_service_handle_state(&mut eng2, &mk_req("GET", "/collections", ""), &mut st2);
  fails = check(status_of(&na) == 401 && service_counter_value(&st2.metrics.auth_failures) == 2
    && service_counter_value(&st2.metrics.errors_total) == 2,
    "counters: auth failures counted (and errors)", fails);
  var ok_key = http_service_handle_state(&mut eng2,
    &mk_req_key("GET", "/collections", "", "mo_read_0001"), &mut st2);
  fails = check(status_of(&ok_key) == 200, "auth: read key still works (no false counter)", fails);

  var eng3 = engine_new();
  var st3 = service_state_new();
  st3.rate = rate_limiter_new(1, 0);
  var r1 = http_service_handle_state(&mut eng3, &mk_req("GET", "/health", ""), &mut st3);
  var r2 = http_service_handle_state(&mut eng3, &mk_req("GET", "/health", ""), &mut st3);
  fails = check(status_of(&r1) == 200 && status_of(&r2) == 429
    && service_counter_value(&st3.metrics.rate_limited) == 1,
    "counters: rate-limited requests counted", fails);

  // ---- log ring cap + sanitization + slow flag ----
  var ring = log_ring_new(4, 1000000);
  var i: Int = 1;
  while i <= 6 {
    log_ring_push(&mut ring, "GET", "/p" + convert.int_to_string(i), 200, i);
    i = i + 1;
  }
  fails = check(ring.lines.len() == 4 && ring.dropped == 2
    && body_has(ring.lines[3], "/p6"),
    "ring: capacity enforced, oldest dropped", fails);
  var ring2 = log_ring_new(8, 0);
  log_ring_push(&mut ring2, "PO\"ST", "/x\n/y", 500, 3);
  var sanitized_ok: Bool = false;
  match json.json_parse(ring2.lines[0]) {
    Ok(sv) => {
      var slow_ok: Bool = false;
      match json.json_get(sv, "slow") {
        Some(fv) => {
          match fv {
            Bool(bv) => {
              if bv { slow_ok = true; }
            }
            _ => {}
          }
        }
        None => {}
      }
      sanitized_ok = slow_ok;
    }
    Err(_) => {}
  }
  fails = check(sanitized_ok, "ring: hostile path sanitized -> valid JSON with slow=true", fails);
  var ring3 = log_ring_new(8, 1000000);
  log_ring_push(&mut ring3, "GET", "/fast", 200, 5);
  fails = check(body_has(ring3.lines[0], "\"slow\":false"), "ring: slow flag false under threshold", fails);

  // ---- service-level ring cap in the state ----
  var eng4 = engine_new();
  var st4 = service_state_new();
  st4.log = log_ring_new(3, 1000000);
  var bi: Int = 0;
  while bi < 5 {
    http_service_handle_state(&mut eng4, &mk_req("GET", "/health", ""), &mut st4);
    bi = bi + 1;
  }
  fails = check(st4.log.lines.len() == 3 && st4.log.dropped == 2
    && service_counter_value(&st4.metrics.requests_total) == 5,
    "service ring: capped at 3 with 2 dropped after 5 requests", fails);

  io.println("");
  io.println("probe_metrics: " + convert.int_to_string(fails) + " failed checks");
  return fails;
}
