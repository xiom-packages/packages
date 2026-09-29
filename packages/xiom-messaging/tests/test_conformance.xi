// XIOM -- xiom.messaging conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Fixture-driven deterministic checks over the documented API: topic and
// filter validation, wildcard matching, subscription ids and validation
// errors, fan-out order, QoS downgrade and QoS 0 settling, ack accounting,
// redelivery with exponential backoff (pinned at every schedule boundary),
// dead-letter routing ("max attempts" and "rejected: <reason>"), strict
// per-key ordering, unsubscribe semantics, control-byte payload round-trips
// and a two-run replay that must produce an identical transcript.
//
// Discipline: every check calls the module directly (no fn tables), every
// Str comparison goes through str_compare, every Vec element read is bound
// to a typed local first, and no Ok/Err is constructed outside the module.

module messaging_tests
use xiom.io; use xiom.test;
use xiom.messaging;
use xiom.string.compare;
use xiom.convert;

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_unit_is(r: Result[Unit, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_dl_is(r: Result[DeadLetter, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

// Publish that the test expects to succeed; -1 marks an unexpected error.
fn pub_ok(b: &mut Bus, topic: Str, payload: Str, key: Str, qos: Int) -> Int {
  let r = bus_publish(b, topic, payload, key, qos);
  if !r.is_ok {
    return -1;
  }
  let mid: Int = r.value;
  return mid;
}

// Subscribe that the test expects to succeed; -1 marks an unexpected error.
fn sub_ok(b: &mut Bus, client: Str, filter: Str, max_attempts: Int, max_qos: Int) -> Int {
  let r = bus_subscribe(b, client, filter, max_attempts, max_qos);
  if !r.is_ok {
    return -1;
  }
  let sid: Int = r.value;
  return sid;
}

// Pin one delivery identity and payload.
fn d_is(d: Delivery, did: Int, client: Str, topic: Str, payload: Str, attempt: Int) -> Bool {
  if d.delivery_id != did {
    return false;
  }
  if !str_eq(d.client, client) {
    return false;
  }
  if !str_eq(d.topic, topic) {
    return false;
  }
  if !str_eq(d.payload, payload) {
    return false;
  }
  if d.attempt != attempt {
    return false;
  }
  return true;
}

fn t1() -> TestResult {
  var ok = topic_is_valid("a");
  if !topic_is_valid("a.b.c") { ok = false; }
  if !topic_is_valid("orders.eu.new") { ok = false; }
  if !topic_is_valid("a/b-c_9") { ok = false; }
  if topic_is_valid("") { ok = false; }
  if topic_is_valid(".") { ok = false; }
  if topic_is_valid(".a") { ok = false; }
  if topic_is_valid("a.") { ok = false; }
  if topic_is_valid("a..b") { ok = false; }
  if topic_is_valid("a.+") { ok = false; }
  if topic_is_valid("a.#") { ok = false; }
  if topic_is_valid("+") { ok = false; }
  if topic_is_valid("a+b") { ok = false; }
  if topic_is_valid("a#b") { ok = false; }
  return assert(ok, "topic_is_valid: dotted names pass, empty segments and wildcards fail");
}

fn t2() -> TestResult {
  var ok = filter_is_valid("a");
  if !filter_is_valid("+") { ok = false; }
  if !filter_is_valid("#") { ok = false; }
  if !filter_is_valid("a.+") { ok = false; }
  if !filter_is_valid("a.#") { ok = false; }
  if !filter_is_valid("+.+.+") { ok = false; }
  if !filter_is_valid("orders.eu.new") { ok = false; }
  if filter_is_valid("") { ok = false; }
  if filter_is_valid("a..b") { ok = false; }
  if filter_is_valid("a.#.b") { ok = false; }
  if filter_is_valid("a#") { ok = false; }
  if filter_is_valid("a#b") { ok = false; }
  if filter_is_valid("a.+b") { ok = false; }
  if filter_is_valid(".#") { ok = false; }
  if filter_is_valid("#.a") { ok = false; }
  if filter_is_valid("a.") { ok = false; }
  return assert(ok, "filter_is_valid: + anywhere, # only as final lone segment");
}

fn t3() -> TestResult {
  var ok = topic_matches("orders.eu", "orders.eu");
  if !topic_matches("orders.+", "orders.eu") { ok = false; }
  if !topic_matches("+.eu.+", "orders.eu.new") { ok = false; }
  if !topic_matches("#", "a") { ok = false; }
  if !topic_matches("#", "a.b.c") { ok = false; }
  if !topic_matches("a.#", "a") { ok = false; }
  if !topic_matches("a.#", "a.b.c") { ok = false; }
  if !topic_matches("a.+.c", "a.b.c") { ok = false; }
  if topic_matches("orders.+", "orders") { ok = false; }
  if topic_matches("orders.+", "orders.eu.new") { ok = false; }
  if topic_matches("orders.#", "ordersX.y") { ok = false; }
  if topic_matches("a.#", "b.c") { ok = false; }
  if topic_matches("+", "a.b") { ok = false; }
  if topic_matches("a.+", "a.b.c") { ok = false; }
  if topic_matches("a.b", "a.c") { ok = false; }
  return assert(ok, "topic_matches: + is one segment, # is a trailing tail");
}

fn t4() -> TestResult {
  let b = bus_new();
  var ok = b.tick == 0;
  if bus_subscription_count(&b) != 0 { ok = false; }
  if bus_pending_count(&b) != 0 { ok = false; }
  if bus_inflight_count(&b) != 0 { ok = false; }
  if bus_dead_letter_count(&b) != 0 { ok = false; }
  let st = bus_stats(&b);
  if st.messages != 0 || st.deliveries != 0 || st.attempts != 0 { ok = false; }
  if st.subscriptions != 0 || st.pending != 0 || st.inflight != 0 { ok = false; }
  if bus_backoff_ticks(1, 64, 1) != 1 { ok = false; }
  if bus_backoff_ticks(1, 64, 2) != 2 { ok = false; }
  if bus_backoff_ticks(1, 64, 7) != 64 { ok = false; }
  if bus_backoff_ticks(1, 64, 8) != 64 { ok = false; }
  if bus_backoff_ticks(2, 8, 1) != 2 { ok = false; }
  if bus_backoff_ticks(2, 8, 2) != 4 { ok = false; }
  if bus_backoff_ticks(2, 8, 3) != 8 { ok = false; }
  if bus_backoff_ticks(2, 8, 4) != 8 { ok = false; }
  if bus_backoff_ticks(3, 100, 0) != 3 { ok = false; }
  if bus_backoff_ticks(0, 100, 5) != 0 { ok = false; }
  return assert(ok, "bus_new defaults and pinned backoff schedule boundaries");
}

fn t5() -> TestResult {
  var b = bus_new();
  var ok = true;
  let s1 = sub_ok(&mut b, "c1", "orders.+", 3, 1);
  if s1 != 1 { ok = false; }
  let s2 = sub_ok(&mut b, "c2", "#", 1, 2);
  if s2 != 2 { ok = false; }
  if !err_int_is(bus_subscribe(&mut b, "c3", "a..b", 1, 0), "messaging: bad filter") { ok = false; }
  if !err_int_is(bus_subscribe(&mut b, "", "#", 1, 0), "messaging: bad client") { ok = false; }
  if !err_int_is(bus_subscribe(&mut b, "c3", "#", 0, 0), "messaging: bad max attempts") { ok = false; }
  if !err_int_is(bus_subscribe(&mut b, "c3", "#", 1, 3), "messaging: bad qos") { ok = false; }
  if !err_int_is(bus_subscribe(&mut b, "c3", "#", 1, -1), "messaging: bad qos") { ok = false; }
  if bus_subscription_count(&b) != 2 { ok = false; }
  return assert(ok, "bus_subscribe returns stable ids and rejects bad input");
}

fn t6() -> TestResult {
  var b = bus_new();
  var ok = true;
  if sub_ok(&mut b, "c1", "#", 1, 1) != 1 { ok = false; }
  if sub_ok(&mut b, "c2", "orders.+", 1, 1) != 2 { ok = false; }
  let mid = pub_ok(&mut b, "orders.eu", "p1", "", 1);
  if mid != 1 { ok = false; }
  let d1 = bus_deliver_next(&mut b);
  if !d_is(d1, 1, "c1", "orders.eu", "p1", 1) { ok = false; }
  if d1.message_id != 1 { ok = false; }
  if d1.subscription_id != 1 { ok = false; }
  let d2 = bus_deliver_next(&mut b);
  if !d_is(d2, 2, "c2", "orders.eu", "p1", 1) { ok = false; }
  if d2.subscription_id != 2 { ok = false; }
  let d3 = bus_deliver_next(&mut b);
  if d3.delivery_id != 0 { ok = false; }
  if bus_inflight_count(&b) != 2 { ok = false; }
  if bus_pending_count(&b) != 0 { ok = false; }
  let st = bus_stats(&b);
  if st.deliveries != 2 || st.attempts != 2 || st.messages != 1 { ok = false; }
  return assert(ok, "fan-out queues one delivery per matching subscription, in id order");
}

fn t7() -> TestResult {
  var b = bus_new();
  var ok = true;
  if sub_ok(&mut b, "c1", "orders.+", 1, 1) != 1 { ok = false; }
  let mid = pub_ok(&mut b, "other.topic", "p", "", 1);
  if mid != 1 { ok = false; }
  if bus_pending_count(&b) != 0 { ok = false; }
  let st = bus_stats(&b);
  if st.deliveries != 0 || st.attempts != 0 { ok = false; }
  if st.messages != 1 { ok = false; }
  let d = bus_deliver_next(&mut b);
  if d.delivery_id != 0 { ok = false; }
  return assert(ok, "publish with no matching subscription queues nothing");
}

fn t8() -> TestResult {
  var b = bus_new();
  var ok = true;
  if sub_ok(&mut b, "c1", "t", 2, 0) != 1 { ok = false; }
  if sub_ok(&mut b, "c2", "t", 2, 2) != 2 { ok = false; }
  if pub_ok(&mut b, "t", "x", "", 2) != 1 { ok = false; }
  let d1 = bus_deliver_next(&mut b);
  if !d_is(d1, 1, "c1", "t", "x", 1) { ok = false; }
  if d1.qos != 0 { ok = false; }
  if bus_inflight_count(&b) != 0 { ok = false; }
  if !err_unit_is(bus_ack(&mut b, 1), "messaging: delivery not in flight") { ok = false; }
  let d2 = bus_deliver_next(&mut b);
  if !d_is(d2, 2, "c2", "t", "x", 1) { ok = false; }
  if d2.qos != 2 { ok = false; }
  if bus_inflight_count(&b) != 1 { ok = false; }
  let st = bus_stats(&b);
  if st.settled != 1 || st.acked != 0 { ok = false; }
  return assert(ok, "delivered QoS is min(publish, subscription) and QoS 0 settles");
}

fn t9() -> TestResult {
  var b = bus_new();
  var ok = true;
  if sub_ok(&mut b, "c1", "t", 3, 1) != 1 { ok = false; }
  if pub_ok(&mut b, "t", "a", "", 1) != 1 { ok = false; }
  let d = bus_deliver_next(&mut b);
  if d.delivery_id != 1 { ok = false; }
  if bus_inflight_count(&b) != 1 { ok = false; }
  if !bus_ack(&mut b, 1).is_ok { ok = false; }
  if bus_inflight_count(&b) != 0 { ok = false; }
  if !err_unit_is(bus_ack(&mut b, 1), "messaging: delivery not in flight") { ok = false; }
  if !err_unit_is(bus_ack(&mut b, 99), "messaging: unknown delivery") { ok = false; }
  if !err_unit_is(bus_ack(&mut b, 0), "messaging: unknown delivery") { ok = false; }
  if !err_unit_is(bus_ack(&mut b, -1), "messaging: unknown delivery") { ok = false; }
  let st = bus_stats(&b);
  if st.acked != 1 { ok = false; }
  return assert(ok, "ack accounting: one ack, repeated/unknown acks fail");
}

fn t10() -> TestResult {
  var b = bus_new();
  var ok = true;
  if sub_ok(&mut b, "c1", "t", 5, 1) != 1 { ok = false; }
  if pub_ok(&mut b, "t", "r1", "", 1) != 1 { ok = false; }
  let d1 = bus_deliver_next(&mut b);
  if !d_is(d1, 1, "c1", "t", "r1", 1) { ok = false; }
  let before = bus_deliver_next(&mut b);
  if before.delivery_id != 0 { ok = false; }
  if !bus_tick(&mut b, 1).is_ok { ok = false; }
  let d2 = bus_deliver_next(&mut b);
  if !d_is(d2, 1, "c1", "t", "r1", 2) { ok = false; }
  let st = bus_stats(&b);
  if st.redelivered != 1 || st.attempts != 2 { ok = false; }
  if !bus_ack(&mut b, 1).is_ok { ok = false; }
  return assert(ok, "timed-out in-flight delivery is redelivered after backoff");
}

fn t11() -> TestResult {
  var b = bus_new();
  var ok = true;
  if sub_ok(&mut b, "c1", "t", 9, 1) != 1 { ok = false; }
  if !bus_set_backoff(&mut b, 2, 8).is_ok { ok = false; }
  if !err_unit_is(bus_set_backoff(&mut b, 0, 8), "messaging: bad backoff") { ok = false; }
  if !err_unit_is(bus_set_backoff(&mut b, 4, 2), "messaging: bad backoff") { ok = false; }
  if pub_ok(&mut b, "t", "b", "", 1) != 1 { ok = false; }
  let d1 = bus_deliver_next(&mut b);
  if d1.attempt != 1 { ok = false; }
  if !bus_tick(&mut b, 1).is_ok { ok = false; }
  if bus_deliver_next(&mut b).delivery_id != 0 { ok = false; }
  if !bus_tick(&mut b, 1).is_ok { ok = false; }
  let d2 = bus_deliver_next(&mut b);
  if d2.attempt != 2 { ok = false; }
  if !bus_tick(&mut b, 3).is_ok { ok = false; }
  if bus_deliver_next(&mut b).delivery_id != 0 { ok = false; }
  if !bus_tick(&mut b, 1).is_ok { ok = false; }
  let d3 = bus_deliver_next(&mut b);
  if d3.attempt != 3 { ok = false; }
  if !bus_tick(&mut b, 7).is_ok { ok = false; }
  if bus_deliver_next(&mut b).delivery_id != 0 { ok = false; }
  if !bus_tick(&mut b, 1).is_ok { ok = false; }
  let d4 = bus_deliver_next(&mut b);
  if d4.attempt != 4 { ok = false; }
  if !bus_ack(&mut b, 1).is_ok { ok = false; }
  return assert(ok, "exponential backoff pinned at 2,4,8,8 with a cap of 8");
}

fn t12() -> TestResult {
  var b = bus_new();
  var ok = true;
  if sub_ok(&mut b, "c1", "t", 1, 1) != 1 { ok = false; }
  if pub_ok(&mut b, "t", "dl", "k", 1) != 1 { ok = false; }
  let d1 = bus_deliver_next(&mut b);
  if d1.delivery_id != 1 { ok = false; }
  if !bus_tick(&mut b, 1).is_ok { ok = false; }
  let d2 = bus_deliver_next(&mut b);
  if d2.delivery_id != 0 { ok = false; }
  if bus_dead_letter_count(&b) != 1 { ok = false; }
  if bus_inflight_count(&b) != 0 { ok = false; }
  if bus_pending_count(&b) != 0 { ok = false; }
  let r = bus_dead_letter_at(&b, 0);
  if !r.is_ok { ok = false; } else {
    let dl: DeadLetter = r.value;
    if dl.delivery_id != 1 { ok = false; }
    if dl.message_id != 1 { ok = false; }
    if dl.subscription_id != 1 { ok = false; }
    if !str_eq(dl.client, "c1") { ok = false; }
    if !str_eq(dl.topic, "t") { ok = false; }
    if !str_eq(dl.payload, "dl") { ok = false; }
    if !str_eq(dl.reason, "max attempts") { ok = false; }
    if dl.attempts != 1 { ok = false; }
    if dl.tick != 1 { ok = false; }
  }
  if !err_dl_is(bus_dead_letter_at(&b, 1), "messaging: dead letter index out of range") { ok = false; }
  if !err_dl_is(bus_dead_letter_at(&b, -1), "messaging: dead letter index out of range") { ok = false; }
  if !err_unit_is(bus_ack(&mut b, 1), "messaging: delivery not in flight") { ok = false; }
  return assert(ok, "max attempts exhaustion dead-letters with the full record");
}

fn t13() -> TestResult {
  var b = bus_new();
  var ok = true;
  if sub_ok(&mut b, "c1", "t", 3, 1) != 1 { ok = false; }
  if pub_ok(&mut b, "t", "j", "", 1) != 1 { ok = false; }
  let d = bus_deliver_next(&mut b);
  if d.delivery_id != 1 { ok = false; }
  if !err_unit_is(bus_reject(&mut b, 1, ""), "messaging: empty reject reason") { ok = false; }
  if !err_unit_is(bus_reject(&mut b, 99, "x"), "messaging: unknown delivery") { ok = false; }
  if !bus_reject(&mut b, 1, "subscriber crashed").is_ok { ok = false; }
  if bus_dead_letter_count(&b) != 1 { ok = false; }
  let r = bus_dead_letter_at(&b, 0);
  if !r.is_ok { ok = false; } else {
    let dl: DeadLetter = r.value;
    if !str_eq(dl.reason, "rejected: subscriber crashed") { ok = false; }
    if dl.attempts != 1 { ok = false; }
  }
  if !err_unit_is(bus_reject(&mut b, 1, "again"), "messaging: delivery not in flight") { ok = false; }
  return assert(ok, "reject dead-letters an in-flight delivery with its reason");
}

fn t14() -> TestResult {
  var b = bus_new();
  var ok = true;
  if sub_ok(&mut b, "c1", "#", 5, 1) != 1 { ok = false; }
  if pub_ok(&mut b, "t", "a1", "ka", 1) != 1 { ok = false; }
  if pub_ok(&mut b, "t", "a2", "ka", 1) != 2 { ok = false; }
  if pub_ok(&mut b, "t", "a3", "ka", 1) != 3 { ok = false; }
  let d1 = bus_deliver_next(&mut b);
  if !d_is(d1, 1, "c1", "t", "a1", 1) { ok = false; }
  let blocked = bus_deliver_next(&mut b);
  if blocked.delivery_id != 0 { ok = false; }
  if !bus_ack(&mut b, 1).is_ok { ok = false; }
  let d2 = bus_deliver_next(&mut b);
  if !d_is(d2, 2, "c1", "t", "a2", 1) { ok = false; }
  let blocked2 = bus_deliver_next(&mut b);
  if blocked2.delivery_id != 0 { ok = false; }
  if !bus_ack(&mut b, 2).is_ok { ok = false; }
  let d3 = bus_deliver_next(&mut b);
  if !d_is(d3, 3, "c1", "t", "a3", 1) { ok = false; }
  if !bus_ack(&mut b, 3).is_ok { ok = false; }
  if pub_ok(&mut b, "t", "b1", "kb", 1) != 4 { ok = false; }
  if pub_ok(&mut b, "t", "a4", "ka", 1) != 5 { ok = false; }
  if pub_ok(&mut b, "t", "b2", "kb", 1) != 6 { ok = false; }
  let d4 = bus_deliver_next(&mut b);
  if !d_is(d4, 4, "c1", "t", "b1", 1) { ok = false; }
  let d5 = bus_deliver_next(&mut b);
  if !d_is(d5, 5, "c1", "t", "a4", 1) { ok = false; }
  let blocked3 = bus_deliver_next(&mut b);
  if blocked3.delivery_id != 0 { ok = false; }
  if !bus_ack(&mut b, 4).is_ok { ok = false; }
  let d6 = bus_deliver_next(&mut b);
  if !d_is(d6, 6, "c1", "t", "b2", 1) { ok = false; }
  if !bus_ack(&mut b, 5).is_ok { ok = false; }
  if !bus_ack(&mut b, 6).is_ok { ok = false; }
  return assert(ok, "strict per-key order; different keys proceed independently");
}

fn t15() -> TestResult {
  var b = bus_new();
  var ok = true;
  if sub_ok(&mut b, "c1", "#", 5, 1) != 1 { ok = false; }
  if pub_ok(&mut b, "t", "u1", "", 1) != 1 { ok = false; }
  if pub_ok(&mut b, "t", "u2", "", 1) != 2 { ok = false; }
  let d1 = bus_deliver_next(&mut b);
  if !d_is(d1, 1, "c1", "t", "u1", 1) { ok = false; }
  let d2 = bus_deliver_next(&mut b);
  if !d_is(d2, 2, "c1", "t", "u2", 1) { ok = false; }
  if !bus_ack(&mut b, 1).is_ok { ok = false; }
  if !bus_ack(&mut b, 2).is_ok { ok = false; }
  return assert(ok, "empty-key deliveries are FIFO and never block each other");
}

fn t16() -> TestResult {
  var b = bus_new();
  var ok = true;
  if sub_ok(&mut b, "c1", "#", 3, 1) != 1 { ok = false; }
  if sub_ok(&mut b, "c2", "#", 3, 1) != 2 { ok = false; }
  if pub_ok(&mut b, "t", "m", "", 1) != 1 { ok = false; }
  if bus_pending_count(&b) != 2 { ok = false; }
  if !bus_unsubscribe(&mut b, 1).is_ok { ok = false; }
  let st1 = bus_stats(&b);
  if st1.dropped != 1 || st1.pending != 1 { ok = false; }
  if bus_subscription_count(&b) != 1 { ok = false; }
  if !err_unit_is(bus_unsubscribe(&mut b, 1), "messaging: already unsubscribed") { ok = false; }
  if !err_unit_is(bus_unsubscribe(&mut b, 42), "messaging: unknown subscription") { ok = false; }
  if pub_ok(&mut b, "t2", "m2", "", 1) != 2 { ok = false; }
  let d1 = bus_deliver_next(&mut b);
  if !d_is(d1, 2, "c2", "t", "m", 1) { ok = false; }
  let d2 = bus_deliver_next(&mut b);
  if !d_is(d2, 3, "c2", "t2", "m2", 1) { ok = false; }
  if bus_deliver_next(&mut b).delivery_id != 0 { ok = false; }
  let q1 = bus_queue_depth(&b, 2);
  if !q1.is_ok { ok = false; } else { if q1.value != 0 { ok = false; } }
  if !err_int_is(bus_queue_depth(&b, 99), "messaging: unknown subscription") { ok = false; }
  return assert(ok, "unsubscribe drops queued deliveries and stops fan-out");
}

fn t17() -> TestResult {
  var b = bus_new();
  var ok = true;
  if sub_ok(&mut b, "c1", "t", 2, 1) != 1 { ok = false; }
  if pub_ok(&mut b, "t", "z", "", 1) != 1 { ok = false; }
  let d1 = bus_deliver_next(&mut b);
  if d1.delivery_id != 1 { ok = false; }
  if !bus_unsubscribe(&mut b, 1).is_ok { ok = false; }
  if bus_inflight_count(&b) != 1 { ok = false; }
  if !bus_tick(&mut b, 2).is_ok { ok = false; }
  let d2 = bus_deliver_next(&mut b);
  if d2.delivery_id != 0 { ok = false; }
  let st = bus_stats(&b);
  if st.dropped != 1 || st.inflight != 0 { ok = false; }
  if !err_unit_is(bus_ack(&mut b, 1), "messaging: delivery not in flight") { ok = false; }
  var b2 = bus_new();
  if sub_ok(&mut b2, "c2", "t", 2, 1) != 1 { ok = false; }
  if pub_ok(&mut b2, "t", "z2", "", 1) != 1 { ok = false; }
  let e1 = bus_deliver_next(&mut b2);
  if e1.delivery_id != 1 { ok = false; }
  if !bus_unsubscribe(&mut b2, 1).is_ok { ok = false; }
  if !bus_ack(&mut b2, 1).is_ok { ok = false; }
  return assert(ok, "unsubscribe keeps in-flight acks but never redelivers them");
}

fn t18() -> TestResult {
  var b = bus_new();
  var ok = true;
  let payload = "line\u{0001}mid\u{000B}\u{001F}\u{007F}end";
  let key = "k\u{0001}";
  if sub_ok(&mut b, "c1", "#", 3, 1) != 1 { ok = false; }
  if pub_ok(&mut b, "t", payload, key, 1) != 1 { ok = false; }
  let d = bus_deliver_next(&mut b);
  if d.delivery_id != 1 { ok = false; }
  if !str_eq(d.payload, payload) { ok = false; }
  if !str_eq(d.key, key) { ok = false; }
  if !bus_reject(&mut b, 1, "bad\u{0001}bytes").is_ok { ok = false; }
  let r = bus_dead_letter_at(&b, 0);
  if !r.is_ok { ok = false; } else {
    let dl: DeadLetter = r.value;
    if !str_eq(dl.payload, payload) { ok = false; }
    if !str_eq(dl.reason, "rejected: bad\u{0001}bytes") { ok = false; }
  }
  return assert(ok, "control bytes survive publish, delivery and dead-letter paths");
}

fn d_line(d: Delivery) -> Str {
  return convert.int_to_string(d.delivery_id) + "|" + convert.int_to_string(d.message_id) + "|" +
    convert.int_to_string(d.subscription_id) + "|" + d.client + "|" + d.topic + "|" + d.payload + "|" +
    d.key + "|" + convert.int_to_string(d.qos) + "|" + convert.int_to_string(d.attempt);
}

// One full deterministic scenario; returns the observable transcript.
fn scenario_transcript() -> Vec[Str] {
  var b = bus_new();
  var tr = Vec[Str].new();
  tr.push("sub1=" + convert.int_to_string(sub_ok(&mut b, "c1", "orders.+", 3, 1)));
  tr.push("sub2=" + convert.int_to_string(sub_ok(&mut b, "c2", "#", 1, 2)));
  tr.push("m1=" + convert.int_to_string(pub_ok(&mut b, "orders.eu", "p1", "ka", 1)));
  tr.push("m2=" + convert.int_to_string(pub_ok(&mut b, "orders.eu", "p2", "ka", 1)));
  tr.push("m3=" + convert.int_to_string(pub_ok(&mut b, "ops.health", "p3", "", 1)));
  var i = 0;
  while i < 7 {
    let d = bus_deliver_next(&mut b);
    tr.push(d_line(d));
    if d.delivery_id != 0 && d.attempt == 1 {
      let a = bus_ack(&mut b, d.delivery_id);
      if a.is_ok { tr.push("ack-ok"); } else { tr.push("ack-err"); }
    }
    if !bus_tick(&mut b, 1).is_ok { tr.push("tick-err"); }
    i = i + 1;
  }
  let st = bus_stats(&b);
  tr.push("pending=" + convert.int_to_string(st.pending));
  tr.push("inflight=" + convert.int_to_string(st.inflight));
  tr.push("acked=" + convert.int_to_string(st.acked));
  tr.push("dead=" + convert.int_to_string(st.dead_lettered));
  return tr;
}

fn t19() -> TestResult {
  let a = scenario_transcript();
  let b = scenario_transcript();
  var ok = a.len() == b.len();
  if !ok { return assert(false, "replay transcripts differ in length"); }
  var i = 0;
  while i < a.len() {
    let x: Str = a[i];
    let y: Str = b[i];
    if !str_eq(x, y) { ok = false; }
    i = i + 1;
  }
  return assert(ok, "identical scenarios replay to an identical transcript");
}

fn t20() -> TestResult {
  var b = bus_new();
  var ok = true;
  if sub_ok(&mut b, "c1", "t.+", 2, 1) != 1 { ok = false; }
  if sub_ok(&mut b, "c2", "t.#", 2, 2) != 2 { ok = false; }
  if pub_ok(&mut b, "t.a", "p1", "", 1) != 1 { ok = false; }
  let d1 = bus_deliver_next(&mut b);
  if d1.delivery_id != 1 { ok = false; }
  if !bus_reject(&mut b, 1, "nope").is_ok { ok = false; }
  let d2 = bus_deliver_next(&mut b);
  if d2.delivery_id != 2 { ok = false; }
  if !bus_tick(&mut b, 1).is_ok { ok = false; }
  let d3 = bus_deliver_next(&mut b);
  if d3.delivery_id != 2 || d3.attempt != 2 { ok = false; }
  if !bus_ack(&mut b, 2).is_ok { ok = false; }
  if pub_ok(&mut b, "t.b", "p2", "", 0) != 2 { ok = false; }
  let d4 = bus_deliver_next(&mut b);
  if d4.delivery_id != 3 || d4.qos != 0 { ok = false; }
  let d5 = bus_deliver_next(&mut b);
  if d5.delivery_id != 4 || d5.qos != 0 { ok = false; }
  let st = bus_stats(&b);
  if st.subscriptions != 2 { ok = false; }
  if st.messages != 2 { ok = false; }
  if st.deliveries != 4 { ok = false; }
  if st.attempts != 5 { ok = false; }
  if st.acked != 1 { ok = false; }
  if st.settled != 2 { ok = false; }
  if st.redelivered != 1 { ok = false; }
  if st.dead_lettered != 1 { ok = false; }
  if st.dropped != 0 { ok = false; }
  if st.pending != 0 { ok = false; }
  if st.inflight != 0 { ok = false; }
  let q1 = bus_queue_depth(&b, 1);
  if !q1.is_ok { ok = false; } else { if q1.value != 0 { ok = false; } }
  let q2 = bus_queue_depth(&b, 2);
  if !q2.is_ok { ok = false; } else { if q2.value != 0 { ok = false; } }
  return assert(ok, "stats accounting is exact after a mixed scenario");
}

fn main() -> Int {
  io.println("=== xiom.messaging conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.messaging: all tests passed");
  } else {
    io.println("xiom.messaging: tests failed");
  }
  return failed;
}
