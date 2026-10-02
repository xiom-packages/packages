// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.elastic conformance tests (28 checks).
//
// All fixtures are inline JSON; no external files. Str equality goes through
// xiom.string.compare.str_compare (BUG 17 / trap 1); parse results are bound
// to typed locals before use; every builder call passes `&mut` explicitly.

module elastic_tests
use xiom.io; use xiom.test; use xiom.elastic;
use xiom.string.compare; use xiom.convert;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn flag(b: Bool) -> Bool {
  if b {
    return true;
  }
  return false;
}

// --- inline JSON fixtures -------------------------------------------------

fn resp_text() -> Str {
  return "{\"took\":7,\"timed_out\":false,\"_shards\":{\"total\":1,\"successful\":1,\"skipped\":0,\"failed\":0},\"hits\":{\"total\":{\"value\":2,\"relation\":\"eq\"},\"max_score\":1.0,\"hits\":[{\"_index\":\"books\",\"_id\":\"1\",\"_source\":{\"title\":\"A\",\"pages\":10}},{\"_index\":\"books\",\"_id\":\"2\",\"_source\":{\"title\":\"B\",\"pages\":20}}]},\"aggregations\":{\"avg_pages\":{\"value\":15}}}";
}

fn resp_es6() -> Str {
  return "{\"took\":1,\"timed_out\":true,\"hits\":{\"total\":3,\"hits\":[]}}";
}

// --- query serialization --------------------------------------------------

fn t1() -> TestResult {
  var q = elastic_query_new();
  let n = elastic_match(&mut q, "title", "hello");
  var q2 = elastic_query_new();
  let n2 = elastic_match(&mut q2, "f", "a\"b");
  let ok = streq(elastic_query_to_json(&q, n),
      "{\"match\":{\"title\":{\"query\":\"hello\"}}}")
    && streq(elastic_query_to_json(&q2, n2),
      "{\"match\":{\"f\":{\"query\":\"a\\\"b\"}}}");
  return assert(ok, "match serializes and escapes");
}

fn t2() -> TestResult {
  var q = elastic_query_new();
  let n = elastic_term(&mut q, "status", "open");
  return assert(streq(elastic_query_to_json(&q, n),
    "{\"term\":{\"status\":{\"value\":\"open\"}}}"), "term serializes");
}

fn t3() -> TestResult {
  var q = elastic_query_new();
  let n = elastic_terms(&mut q, "tag");
  elastic_terms_add(&mut q, n, "a");
  elastic_terms_add(&mut q, n, "b");
  return assert(streq(elastic_query_to_json(&q, n),
    "{\"terms\":{\"tag\":[\"a\",\"b\"]}}"), "terms serializes two");
}

fn t4() -> TestResult {
  var q = elastic_query_new();
  let n = elastic_range(&mut q, "age", "10", "20", 1, 1);
  return assert(streq(elastic_query_to_json(&q, n),
    "{\"range\":{\"age\":{\"gte\":\"10\",\"lte\":\"20\"}}}"), "range inclusive");
}

fn t5() -> TestResult {
  var q = elastic_query_new();
  let n = elastic_range(&mut q, "age", "10", "20", 0, 0);
  return assert(streq(elastic_query_to_json(&q, n),
    "{\"range\":{\"age\":{\"gt\":\"10\",\"lt\":\"20\"}}}"), "range exclusive");
}

fn t6() -> TestResult {
  var q = elastic_query_new();
  let child = elastic_term(&mut q, "status", "open");
  let b = elastic_bool(&mut q);
  elastic_bool_must(&mut q, b, child);
  return assert(streq(elastic_query_to_json(&q, b),
    "{\"bool\":{\"must\":[{\"term\":{\"status\":{\"value\":\"open\"}}}]}}"),
    "bool must");
}

fn t7() -> TestResult {
  var q = elastic_query_new();
  let c1 = elastic_term(&mut q, "a", "1");
  let c2 = elastic_term(&mut q, "b", "2");
  let b = elastic_bool(&mut q);
  elastic_bool_filter(&mut q, b, c1);
  elastic_bool_must_not(&mut q, b, c2);
  return assert(streq(elastic_query_to_json(&q, b),
    "{\"bool\":{\"filter\":[{\"term\":{\"a\":{\"value\":\"1\"}}}],\"must_not\":[{\"term\":{\"b\":{\"value\":\"2\"}}}]}}"),
    "bool filter before must_not");
}

fn t8() -> TestResult {
  var q = elastic_query_new();
  let n = elastic_exists(&mut q, "user");
  return assert(streq(elastic_query_to_json(&q, n),
    "{\"exists\":{\"field\":\"user\"}}"), "exists serializes");
}

fn t9() -> TestResult {
  var q = elastic_query_new();
  let child = elastic_match(&mut q, "body", "hi");
  let n = elastic_nested(&mut q, "comments", child);
  return assert(streq(elastic_query_to_json(&q, n),
    "{\"nested\":{\"path\":\"comments\",\"query\":{\"match\":{\"body\":{\"query\":\"hi\"}}}}}"),
    "nested serializes");
}

fn t10() -> TestResult {
  var q = elastic_query_new();
  let n = elastic_match(&mut q, "f", "v");
  let k = elastic_query_kind(&q, n);
  let f = elastic_query_field(&q, n);
  return assert(k == QE_KIND_MATCH && streq(f, "f") && streq(elastic_query_kind_name(k), "match"),
    "kind and field accessors");
}

fn t11() -> TestResult {
  var q = elastic_query_new();
  let n = elastic_match(&mut q, "t", "x");
  return assert(streq(elastic_search_body(&q, n),
    "{\"query\":{\"match\":{\"t\":{\"query\":\"x\"}}}}"), "search body");
}

fn t12() -> TestResult {
  var q = elastic_query_new();
  let n = elastic_match(&mut q, "title", "x");
  return assert(streq(elastic_search_request("books", &q, n),
    "{\"method\":\"POST\",\"path\":\"/books/_search\",\"body\":{\"query\":{\"match\":{\"title\":{\"query\":\"x\"}}}}}"),
    "search request");
}

fn t13() -> TestResult {
  return assert(streq(elastic_index_request("books", "42", "{\"title\":\"x\"}"),
    "{\"method\":\"PUT\",\"path\":\"/books/_doc/42\",\"body\":{\"title\":\"x\"}}"),
    "index request with id");
}

fn t14() -> TestResult {
  return assert(streq(elastic_index_request("books", "", "{}"),
    "{\"method\":\"POST\",\"path\":\"/books/_doc\",\"body\":{}}"),
    "index request without id");
}

fn t15() -> TestResult {
  return assert(streq(elastic_scroll_request("s1", 5),
    "{\"method\":\"POST\",\"path\":\"/_search/scroll\",\"body\":{\"scroll\":\"30s\",\"scroll_id\":\"s1\",\"size\":5}}"),
    "scroll request");
}

fn t16() -> TestResult {
  return assert(streq(elastic_bulk_index_action("books", "1"),
    "{\"index\":{\"_index\":\"books\",\"_id\":\"1\"}}"), "bulk action with id");
}

fn t17() -> TestResult {
  let action = elastic_bulk_index_action("books", "");
  let frame = elastic_bulk_frame(action, "{\"title\":\"x\"}");
  return assert(elastic_ndjson_line_count(frame) == 2
    && flag(elastic_ndjson_wellformed(frame))
    && streq(frame, "{\"index\":{\"_index\":\"books\"}}\n{\"title\":\"x\"}\n"),
    "bulk NDJSON framing");
}

// --- response envelope parsing -------------------------------------------

fn t18() -> TestResult {
  let r = elastic_parse_response(resp_text());
  match r {
    Ok(resp) => {
      let e: EResponse = resp;
      return assert(elastic_response_took(&e) == 7, "response took");
    },
    Err(_) => { return assert(false, "response took"); },
  }
  return assert(false, "response took");
}

fn t19() -> TestResult {
  let r = elastic_parse_response(resp_text());
  match r {
    Ok(resp) => {
      let e: EResponse = resp;
      return assert(elastic_response_timed_out(&e) == false, "response timed_out");
    },
    Err(_) => { return assert(false, "response timed_out"); },
  }
  return assert(false, "response timed_out");
}

fn t20() -> TestResult {
  let r = elastic_parse_response(resp_text());
  match r {
    Ok(resp) => {
      let e: EResponse = resp;
      return assert(elastic_response_total(&e) == 2
        && streq(elastic_response_total_relation(&e), "eq"), "response total");
    },
    Err(_) => { return assert(false, "response total"); },
  }
  return assert(false, "response total");
}

fn t21() -> TestResult {
  let r = elastic_parse_response(resp_text());
  match r {
    Ok(resp) => {
      let e: EResponse = resp;
      let ok = elastic_response_hit_count(&e) == 2
        && elastic_response_source_count(&e) == 2
        && streq(elastic_response_source(resp_text(), &e, 0), "{\"title\":\"A\",\"pages\":10}")
        && streq(elastic_response_source(resp_text(), &e, 1), "{\"title\":\"B\",\"pages\":20}");
      return assert(ok, "response hits and source spans");
    },
    Err(_) => { return assert(false, "response hits and source spans"); },
  }
  return assert(false, "response hits and source spans");
}

fn t22() -> TestResult {
  let text = resp_text();
  let r = elastic_parse_response(text);
  match r {
    Ok(resp) => {
      let e: EResponse = resp;
      let ok = elastic_response_agg_count(&e) == 1
        && streq(elastic_response_agg_name(&e, 0), "avg_pages")
        && elastic_response_agg_value(&e, 0) == 15;
      return assert(ok, "aggregations subset");
    },
    Err(_) => { return assert(false, "aggregations subset"); },
  }
  return assert(false, "aggregations subset");
}

fn t23() -> TestResult {
  let r = elastic_parse_response(resp_es6());
  match r {
    Ok(resp) => {
      let e: EResponse = resp;
      let ok = elastic_response_total(&e) == 3
        && elastic_response_timed_out(&e) == true
        && elastic_response_hit_count(&e) == 0
        && streq(elastic_response_total_relation(&e), "eq");
      return assert(ok, "ES6 numeric total");
    },
    Err(_) => { return assert(false, "ES6 numeric total"); },
  }
  return assert(false, "ES6 numeric total");
}

fn t24() -> TestResult {
  let r = elastic_parse_response("not json");
  match r {
    Ok(_) => { return assert(false, "response rejects non-object"); },
    Err(m) => {
      let e: Str = m;
      return assert(e.len() > 0, "response rejects non-object");
    },
  }
  return assert(false, "response rejects non-object");
}

// --- mapping / settings ---------------------------------------------------

fn t25() -> TestResult {
  var m = elastic_mapping_new();
  elastic_mapping_add(&mut m, "title", QE_MT_TEXT);
  elastic_mapping_add(&mut m, "pages", QE_MT_INTEGER);
  let ok = elastic_mapping_count(&m) == 2
    && elastic_mapping_field_type(&m, "pages") == QE_MT_INTEGER
    && streq(elastic_mapping_type_name(QE_MT_KEYWORD), "keyword");
  return assert(ok, "mapping add and lookup");
}

fn t26() -> TestResult {
  var m = elastic_mapping_new();
  elastic_mapping_add(&mut m, "title", QE_MT_TEXT);
  elastic_mapping_add(&mut m, "pages", QE_MT_INTEGER);
  let before = elastic_mapping_to_json(&m);
  elastic_mapping_add(&mut m, "pages", QE_MT_KEYWORD);
  let after = elastic_mapping_to_json(&m);
  return assert(elastic_mapping_count(&m) == 2
    && streq(before, "{\"properties\":{\"title\":{\"type\":\"text\"},\"pages\":{\"type\":\"integer\"}}}")
    && streq(after, "{\"properties\":{\"title\":{\"type\":\"text\"},\"pages\":{\"type\":\"keyword\"}}}"),
    "mapping serialize and overwrite");
}

fn t27() -> TestResult {
  var s = elastic_settings_new();
  elastic_settings_set_shards(&mut s, 3);
  elastic_settings_set_replicas(&mut s, 2);
  elastic_settings_set_refresh(&mut s, "5s");
  return assert(streq(elastic_settings_to_json(&s),
    "{\"index\":{\"number_of_shards\":3,\"number_of_replicas\":2,\"refresh_interval\":\"5s\"}}"),
    "settings serialize");
}

// --- scroll / bounded pagination -----------------------------------------

fn t28() -> TestResult {
  var s = elastic_scroll_new("s1", 5, 3);
  elastic_scroll_add_id(&mut s, "h1");
  elastic_scroll_add_id(&mut s, "h2");
  let more1 = elastic_scroll_advance(&mut s, 5);
  let more2 = elastic_scroll_advance(&mut s, 0);
  let ok = flag(more1) && flag(more2) == false
    && elastic_scroll_done(&s) == true
    && elastic_scroll_page(&s) == 2
    && elastic_scroll_seen(&s) == 5
    && elastic_scroll_id_count(&s) == 2
    && streq(elastic_scroll_id_at(&s, 0), "h1")
    && streq(elastic_scroll_next_request(&s),
      "{\"method\":\"POST\",\"path\":\"/_search/scroll\",\"body\":{\"scroll\":\"30s\",\"scroll_id\":\"s1\",\"size\":5}}")
    && elastic_page_count(10, 3) == 4
    && elastic_page_count(9, 3) == 3
    && elastic_page_count(0, 3) == 0;
  return assert(ok, "scroll bounded pages");
}

// --- escaping -------------------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.elastic conformance tests ===");
  var failed: Int = 0;
  let r1 = t1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t8();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t9();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = t22();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  let r23 = t23();
  if r23.passed { io.println("  [PASS] " + r23.name); } else { io.println("  [FAIL] " + r23.name); failed = failed + 1; }
  let r24 = t24();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  let r25 = t25();
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  let r26 = t26();
  if r26.passed { io.println("  [PASS] " + r26.name); } else { io.println("  [FAIL] " + r26.name); failed = failed + 1; }
  let r27 = t27();
  if r27.passed { io.println("  [PASS] " + r27.name); } else { io.println("  [FAIL] " + r27.name); failed = failed + 1; }
  let r28 = t28();
  if r28.passed { io.println("  [PASS] " + r28.name); } else { io.println("  [FAIL] " + r28.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.elastic: all tests passed");
  } else {
    io.println("xiom.elastic: tests failed");
  }
  return failed;
}
