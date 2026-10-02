// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.k8s conformance tests (23 checks)
// Port task: prove the pure-XIOM Kubernetes orchestration model against its
// documented API: namespaces and quota accounting, pods and the phase
// machine, labels and selectors, deployments (replicas, strategy, revision
// history, rolling-update rounds), services and endpoints, ingress exposure,
// config/secret scoping.
//
// Everything is deterministic: no threads, no wall clock, no files, no
// network. All Str equality goes through streq (string.str_compare); every
// Vec element read binds a typed local first. Fixture helpers unwrap Results
// with empty fallbacks so an unexpected Err fails the owning assertion
// loudly instead of crashing the suite.

module k8s_tests
use xiom.io; use xiom.test;
use xiom.k8s;
use xiom.k8s.selector;
use xiom.k8s.rolling;
use xiom.string;

// --------------------------------------------------
//  Helpers
// --------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return string.str_compare(a, b) == 0;
}

fn int_ok_is(r: Result[Int, Str], want: Int) -> Bool {
  match r {
    Ok(v) => { return v == want; },
    Err(_) => { return false; },
  }
  return false;
}

fn int_err_is(r: Result[Int, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn vec_ok_of(r: Result[Vec[Int], Str]) -> Vec[Int] {
  match r {
    Ok(v) => { return v; },
    Err(_) => { return Vec[Int].new(); },
  }
  return Vec[Int].new();
}

fn vec_err_is(r: Result[Vec[Int], Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn parts_of(s: Str) -> LabelParts {
  match selector.label_parts_parse(s) {
    Ok(v) => { return v; },
    Err(_) => { return selector.label_parts_new(); },
  }
  return selector.label_parts_new();
}

fn vec1_is(v: Vec[Int], a: Int) -> Bool {
  if v.len() != 1 { return false; }
  let x: Int = v[0];
  return x == a;
}

fn vec2_is(v: Vec[Int], a: Int, b: Int) -> Bool {
  if v.len() != 2 { return false; }
  let x: Int = v[0];
  let y: Int = v[1];
  return x == a && y == b;
}

fn vec3_is(v: Vec[Int], a: Int, b: Int, cc: Int) -> Bool {
  if v.len() != 3 { return false; }
  let x: Int = v[0];
  let y: Int = v[1];
  let z: Int = v[2];
  return x == a && y == b && z == cc;
}

fn vec4_is(v: Vec[Int], a: Int, b: Int, cc: Int, d: Int) -> Bool {
  if v.len() != 4 { return false; }
  let x: Int = v[0];
  let y: Int = v[1];
  let z: Int = v[2];
  let w: Int = v[3];
  return x == a && y == b && z == cc && w == d;
}

fn vec5_is(v: Vec[Int], a: Int, b: Int, cc: Int, d: Int, e: Int) -> Bool {
  if v.len() != 5 { return false; }
  let x: Int = v[0];
  let y: Int = v[1];
  let z: Int = v[2];
  let w: Int = v[3];
  let q: Int = v[4];
  return x == a && y == b && z == cc && w == d && q == e;
}

fn ep_names_is(c: &K8sCluster, id: Int, want: Str) -> Bool {
  return streq(service_endpoint_names(c, id), want);
}

// Cluster with two namespaces: "default" (quotas 8 pods / 8000m / 8192Mi)
// and "prod" (unlimited).
fn two_ns() -> K8sCluster {
  var c = k8s_cluster_new();
  let a = namespace_create(&mut c, "default", 8, 8000, 8192);
  let b = namespace_create(&mut c, "prod", 0, 0, 0);
  if int_ok_is(a, 0) && int_ok_is(b, 1) { return c; }
  return c;
}

fn set_phase(c: &mut K8sCluster, id: Int, to: Int) -> Bool {
  return int_ok_is(pod_transition(c, id, to), to);
}

// Identical deterministic fixture used by the determinism check.
fn build_fixture() -> K8sCluster {
  var c = two_ns();
  let p1 = pod_create(&mut c, 0, "web1", 100, 128);
  let p2 = pod_create(&mut c, 0, "web2", 100, 128);
  let l1 = pod_label_add(&mut c, 0, "app", "web");
  let l2 = pod_label_add(&mut c, 1, "app", "web");
  let m1 = pod_transition(&mut c, 0, K8S_PHASE_RUNNING);
  let m2 = pod_transition(&mut c, 1, K8S_PHASE_RUNNING);
  let s = service_create(&mut c, 0, "web", K8S_SVC_CLUSTER_IP, 80, 8080);
  let se = service_selector_add(&mut c, 0, "app", "web");
  let d = deployment_create(&mut c, 0, "web", "nginx:1.25", 2);
  let ing = ingress_create(&mut c, 0, "web-ing");
  let r = ingress_rule_add(&mut c, 0, "", "/", "web", 80);
  if int_ok_is(p1, 0) && int_ok_is(p2, 1) && int_ok_is(l1, 1) && int_ok_is(l2, 1) && int_ok_is(m1, K8S_PHASE_RUNNING) && int_ok_is(m2, K8S_PHASE_RUNNING) && int_ok_is(s, 0) && int_ok_is(se, 1) && int_ok_is(d, 0) && int_ok_is(ing, 0) && int_ok_is(r, 1) {
    return c;
  }
  return c;
}

// --------------------------------------------------
//  Namespaces
// --------------------------------------------------

fn t1() -> TestResult {
  var c = k8s_cluster_new();
  var ok = int_ok_is(namespace_create(&mut c, "default", 4, 4000, 4096), 0);
  if !int_ok_is(namespace_create(&mut c, "prod", 0, 0, 0), 1) { ok = false; }
  if namespace_count(&c) != 2 { ok = false; }
  if namespace_index(&c, "prod") != 1 { ok = false; }
  if namespace_index(&c, "ghost") != K8S_NOT_FOUND { ok = false; }
  if !streq(namespace_name(&c, 0), "default") { ok = false; }
  if !streq(namespace_name(&c, 9), "") { ok = false; }
  if namespace_max_pods(&c, 0) != 4 { ok = false; }
  if namespace_cpu_quota(&c, 1) != 0 { ok = false; }
  if namespace_mem_quota(&c, 0) != 4096 { ok = false; }
  if !int_err_is(namespace_create(&mut c, "default", 1, 1, 1), "namespace: duplicate namespace") { ok = false; }
  if !int_err_is(namespace_create(&mut c, "Prod", 1, 1, 1), "namespace: invalid name") { ok = false; }
  if !int_err_is(namespace_create(&mut c, "", 1, 1, 1), "namespace: name must not be empty") { ok = false; }
  if !int_err_is(namespace_create(&mut c, "neg", -1, 1, 1), "namespace: quota must be >= 0") { ok = false; }
  if !k8s_name_valid("web-1") { ok = false; }
  if k8s_name_valid("-web") { ok = false; }
  if k8s_name_valid("web_1") { ok = false; }
  if k8s_name_valid("") { ok = false; }
  return assert(ok, "namespace create, accessors, grammar and error paths");
}

// --------------------------------------------------
//  Pods
// --------------------------------------------------

fn t2() -> TestResult {
  var c = two_ns();
  var ok = int_ok_is(pod_create(&mut c, 0, "web", 100, 128), 0);
  if !int_ok_is(pod_create(&mut c, 1, "web", 0, 0), 1) { ok = false; }
  if pod_count(&c) != 2 { ok = false; }
  if !streq(pod_name(&c, 0), "web") { ok = false; }
  if pod_namespace(&c, 1) != 1 { ok = false; }
  if pod_phase(&c, 0) != K8S_PHASE_PENDING { ok = false; }
  if pod_cpu(&c, 0) != 100 { ok = false; }
  if pod_mem(&c, 0) != 128 { ok = false; }
  if pod_owner(&c, 0) != K8S_NOT_FOUND { ok = false; }
  if pod_index(&c, 0, "web") != 0 { ok = false; }
  if pod_index(&c, 1, "web") != 1 { ok = false; }
  if pod_index(&c, 0, "db") != K8S_NOT_FOUND { ok = false; }
  if !streq(pod_name(&c, 9), "") { ok = false; }
  if pod_phase(&c, 9) != K8S_NOT_FOUND { ok = false; }
  if !int_err_is(pod_create(&mut c, 0, "web", 0, 0), "pod: duplicate pod") { ok = false; }
  if !int_err_is(pod_create(&mut c, 9, "x", 0, 0), "pod: unknown namespace") { ok = false; }
  if !int_err_is(pod_create(&mut c, 0, "Bad", 0, 0), "pod: invalid name") { ok = false; }
  if !int_err_is(pod_create(&mut c, 0, "cpu-neg", -1, 0), "pod: cpu must be >= 0") { ok = false; }
  if !int_err_is(pod_create(&mut c, 0, "mem-neg", 0, -1), "pod: memory must be >= 0") { ok = false; }
  return assert(ok, "pod create, namespace scoping and accessors");
}

fn t3() -> TestResult {
  var c = two_ns();
  let p = pod_create(&mut c, 0, "web", 0, 0);
  var ok = int_ok_is(p, 0);
  if !int_ok_is(pod_label_add(&mut c, 0, "app", "web"), 1) { ok = false; }
  if !int_ok_is(pod_label_add(&mut c, 0, "tier", "front"), 2) { ok = false; }
  if pod_label_count(&c, 0) != 2 { ok = false; }
  if !streq(pod_label_value(&c, 0, "app"), "web") { ok = false; }
  if !streq(pod_label_value(&c, 0, "missing"), "") { ok = false; }
  if !streq(pod_labels_render(&c, 0), "app=web,tier=front") { ok = false; }
  let s1 = parts_of("app=web");
  if !pod_labels_match_selector(&c, 0, &s1) { ok = false; }
  let s2 = parts_of("app=web,tier=front");
  if !pod_labels_match_selector(&c, 0, &s2) { ok = false; }
  let s3 = parts_of("app=db");
  if pod_labels_match_selector(&c, 0, &s3) { ok = false; }
  let s4 = parts_of("tier=back");
  if pod_labels_match_selector(&c, 0, &s4) { ok = false; }
  let s5 = parts_of("app=web,tier=front,zone=a");
  if pod_labels_match_selector(&c, 0, &s5) { ok = false; }
  if !int_err_is(pod_label_add(&mut c, 0, "app", "db"), "label: duplicate key") { ok = false; }
  if !int_err_is(pod_label_add(&mut c, 0, "bad key", "x"), "label: invalid key") { ok = false; }
  if !int_err_is(pod_label_add(&mut c, 0, "", "x"), "label: key must not be empty") { ok = false; }
  if !int_err_is(pod_label_add(&mut c, 9, "k", "v"), "pod: unknown pod") { ok = false; }
  return assert(ok, "pod labels, selector matching and label errors");
}

fn t4() -> TestResult {
  var c = two_ns();
  let p = pod_create(&mut c, 0, "job", 0, 0);
  var ok = int_ok_is(p, 0);
  if !set_phase(&mut c, 0, K8S_PHASE_RUNNING) { ok = false; }
  if pod_phase(&c, 0) != K8S_PHASE_RUNNING { ok = false; }
  if pod_move_count(&c, 0) != 1 { ok = false; }
  if !streq(pod_phase_name(pod_phase(&c, 0)), "running") { ok = false; }
  if !set_phase(&mut c, 0, K8S_PHASE_SUCCEEDED) { ok = false; }
  if !pod_is_terminal(pod_phase(&c, 0)) { ok = false; }
  if pod_move_count(&c, 0) != 2 { ok = false; }
  if pod_is_terminal(K8S_PHASE_PENDING) { ok = false; }
  if !int_err_is(pod_transition(&mut c, 0, K8S_PHASE_RUNNING), "pod: invalid phase transition") { ok = false; }
  if !int_err_is(pod_transition(&mut c, 9, K8S_PHASE_RUNNING), "pod: unknown pod") { ok = false; }
  if !int_err_is(pod_transition(&mut c, 0, 9), "pod: invalid phase") { ok = false; }
  if !int_err_is(pod_transition(&mut c, 0, K8S_PHASE_SUCCEEDED), "pod: phase unchanged") { ok = false; }
  return assert(ok, "pod phase transitions update state and counters");
}

fn t5() -> TestResult {
  var allowed = 0;
  var from = 0;
  while from < 5 {
    var to = 0;
    while to < 5 {
      if pod_can_transition(from, to) { allowed = allowed + 1; }
      to = to + 1;
    }
    from = from + 1;
  }
  var ok = allowed == 10;
  if !pod_can_transition(K8S_PHASE_PENDING, K8S_PHASE_RUNNING) { ok = false; }
  if !pod_can_transition(K8S_PHASE_PENDING, K8S_PHASE_UNKNOWN) { ok = false; }
  if !pod_can_transition(K8S_PHASE_RUNNING, K8S_PHASE_UNKNOWN) { ok = false; }
  if !pod_can_transition(K8S_PHASE_UNKNOWN, K8S_PHASE_PENDING) { ok = false; }
  if pod_can_transition(K8S_PHASE_PENDING, K8S_PHASE_SUCCEEDED) { ok = false; }
  if pod_can_transition(K8S_PHASE_SUCCEEDED, K8S_PHASE_UNKNOWN) { ok = false; }
  if pod_can_transition(K8S_PHASE_FAILED, K8S_PHASE_RUNNING) { ok = false; }
  if !streq(pod_phase_name(K8S_PHASE_PENDING), "pending") { ok = false; }
  if !streq(pod_phase_name(K8S_PHASE_SUCCEEDED), "succeeded") { ok = false; }
  if !streq(pod_phase_name(K8S_PHASE_FAILED), "failed") { ok = false; }
  if !streq(pod_phase_name(K8S_PHASE_UNKNOWN), "unknown") { ok = false; }
  if !streq(pod_phase_name(99), "unknown") { ok = false; }
  return assert(ok, "phase table has exactly ten legal pairs");
}

fn t21() -> TestResult {
  var c = two_ns();
  let p = pod_create(&mut c, 0, "node-loss", 0, 0);
  let q = pod_create(&mut c, 0, "crash", 0, 0);
  var ok = int_ok_is(p, 0);
  if !int_ok_is(q, 1) { ok = false; }
  if !set_phase(&mut c, 0, K8S_PHASE_UNKNOWN) { ok = false; }
  if !set_phase(&mut c, 0, K8S_PHASE_RUNNING) { ok = false; }
  if !set_phase(&mut c, 0, K8S_PHASE_UNKNOWN) { ok = false; }
  if !set_phase(&mut c, 0, K8S_PHASE_SUCCEEDED) { ok = false; }
  if pod_move_count(&c, 0) != 4 { ok = false; }
  if !set_phase(&mut c, 1, K8S_PHASE_FAILED) { ok = false; }
  if !pod_is_terminal(pod_phase(&c, 1)) { ok = false; }
  if !int_err_is(pod_transition(&mut c, 0, K8S_PHASE_UNKNOWN), "pod: invalid phase transition") { ok = false; }
  if !int_err_is(pod_transition(&mut c, 1, K8S_PHASE_PENDING), "pod: invalid phase transition") { ok = false; }
  return assert(ok, "unknown recovery path and terminal phases");
}

// --------------------------------------------------
//  Deployments
// --------------------------------------------------

fn t6() -> TestResult {
  var c = two_ns();
  var ok = int_ok_is(deployment_create(&mut c, 0, "web", "nginx:1.25", 3), 0);
  if deployment_count(&c) != 1 { ok = false; }
  if !streq(deployment_name(&c, 0), "web") { ok = false; }
  if deployment_namespace(&c, 0) != 0 { ok = false; }
  if !streq(deployment_image(&c, 0), "nginx:1.25") { ok = false; }
  if deployment_replicas(&c, 0) != 3 { ok = false; }
  if deployment_revision(&c, 0) != 1 { ok = false; }
  if deployment_surge_amount(&c, 0) != rolling.K8S_ROLLING_DEFAULT_SURGE_PCT { ok = false; }
  if !deployment_surge_is_percent(&c, 0) { ok = false; }
  if deployment_unavailable_amount(&c, 0) != rolling.K8S_ROLLING_DEFAULT_UNAVAILABLE_PCT { ok = false; }
  if !deployment_unavailable_is_percent(&c, 0) { ok = false; }
  if deployment_surge_count(&c, 0) != 1 { ok = false; }
  if deployment_unavailable_count(&c, 0) != 0 { ok = false; }
  if deployment_rolling_rounds(&c, 0) != 3 { ok = false; }
  if !vec3_is(vec_ok_of(deployment_rolling_schedule(&c, 0)), 1, 2, 3) { ok = false; }
  if !int_err_is(deployment_create(&mut c, 0, "web", "nginx:1.25", 1), "deployment: duplicate deployment") { ok = false; }
  if !int_err_is(deployment_create(&mut c, 9, "x", "nginx:1.25", 1), "deployment: unknown namespace") { ok = false; }
  if !int_err_is(deployment_create(&mut c, 0, "Bad", "nginx:1.25", 1), "deployment: invalid name") { ok = false; }
  if !int_err_is(deployment_create(&mut c, 0, "noimg", "", 1), "deployment: image must not be empty") { ok = false; }
  if !int_err_is(deployment_create(&mut c, 0, "neg", "nginx:1.25", -1), "deployment: replicas must be >= 0") { ok = false; }
  return assert(ok, "deployment defaults, resolved strategy and rolling rounds");
}

fn t7() -> TestResult {
  var c = two_ns();
  let d = deployment_create(&mut c, 0, "web", "img:1", 2);
  var ok = int_ok_is(d, 0);
  if !int_ok_is(deployment_set_strategy(&mut c, 0, 2, 0, 1, 0), 0) { ok = false; }
  if deployment_surge_amount(&c, 0) != 2 { ok = false; }
  if deployment_surge_is_percent(&c, 0) { ok = false; }
  if deployment_unavailable_amount(&c, 0) != 1 { ok = false; }
  if deployment_unavailable_is_percent(&c, 0) { ok = false; }
  if deployment_surge_count(&c, 0) != 2 { ok = false; }
  if deployment_unavailable_count(&c, 0) != 1 { ok = false; }
  if !int_err_is(deployment_set_strategy(&mut c, 0, 0, 1, 0, 1), "deployment: maxSurge and maxUnavailable cannot both be zero") { ok = false; }
  if !int_err_is(deployment_set_strategy(&mut c, 0, 101, 1, 1, 0), "deployment: strategy percent must be in 0..100") { ok = false; }
  if !int_err_is(deployment_set_strategy(&mut c, 0, -1, 0, 1, 0), "deployment: strategy amount must be >= 0") { ok = false; }
  if !int_err_is(deployment_set_strategy(&mut c, 0, 1, 2, 1, 0), "deployment: strategy percent flag must be 0 or 1") { ok = false; }
  if !int_err_is(deployment_set_strategy(&mut c, 9, 1, 0, 1, 0), "deployment: unknown deployment") { ok = false; }
  if !int_ok_is(deployment_scale(&mut c, 0, 5), 5) { ok = false; }
  if deployment_replicas(&c, 0) != 5 { ok = false; }
  if !int_err_is(deployment_scale(&mut c, 0, -1), "deployment: replicas must be >= 0") { ok = false; }
  if !int_err_is(deployment_scale(&mut c, 9, 1), "deployment: unknown deployment") { ok = false; }
  return assert(ok, "strategy validation and scaling");
}

fn t8() -> TestResult {
  var ok = rolling.rolling_rounds(4, 1, 0) == 4;
  if !vec4_is(vec_ok_of(rolling.rolling_schedule(4, 1, 0)), 1, 2, 3, 4) { ok = false; }
  if !vec3_is(vec_ok_of(rolling.rolling_schedule(5, 2, 0)), 2, 4, 5) { ok = false; }
  if rolling.rolling_rounds(5, 2, 0) != 3 { ok = false; }
  if !vec5_is(vec_ok_of(rolling.rolling_schedule(4, 0, 1)), 0, 1, 2, 3, 4) { ok = false; }
  if rolling.rolling_rounds(4, 0, 1) != 5 { ok = false; }
  if !vec3_is(vec_ok_of(rolling.rolling_schedule(10, 3, 2)), 3, 8, 10) { ok = false; }
  if rolling.rolling_rounds(10, 3, 2) != 3 { ok = false; }
  let zero = vec_ok_of(rolling.rolling_schedule(0, 1, 0));
  if zero.len() != 0 { ok = false; }
  if rolling.rolling_rounds(0, 1, 0) != 0 { ok = false; }
  if !vec_err_is(rolling.rolling_schedule(5, 0, 0), "rolling: maxSurge and maxUnavailable cannot both be zero") { ok = false; }
  if rolling.rolling_rounds(5, 0, 0) != K8S_NOT_FOUND { ok = false; }
  if !vec_err_is(rolling.rolling_schedule(-1, 1, 0), "rolling: desired replicas must be >= 0") { ok = false; }
  if !vec_err_is(rolling.rolling_schedule(5, -1, 0), "rolling: maxSurge must be >= 0") { ok = false; }
  if !vec_err_is(rolling.rolling_schedule(5, 1, -1), "rolling: maxUnavailable must be >= 0") { ok = false; }
  return assert(ok, "rolling schedules are exact, bounded and end at desired");
}

fn t9() -> TestResult {
  var ok = rolling.rolling_surge(3, 25, true) == 1;
  if rolling.rolling_unavailable(3, 25, true) != 0 { ok = false; }
  if rolling.rolling_surge(4, 25, true) != 1 { ok = false; }
  if rolling.rolling_surge(8, 25, true) != 2 { ok = false; }
  if rolling.rolling_surge(10, 30, true) != 3 { ok = false; }
  if rolling.rolling_unavailable(10, 30, true) != 3 { ok = false; }
  if rolling.rolling_surge(3, 1, false) != 1 { ok = false; }
  if rolling.rolling_unavailable(3, 2, false) != 2 { ok = false; }
  if rolling.rolling_surge(0, 25, true) != 0 { ok = false; }
  if rolling.rolling_resolve(-1, 1, false, true) != K8S_NOT_FOUND { ok = false; }
  if !rolling.rolling_valid(0, 1) { ok = false; }
  if rolling.rolling_valid(0, 0) { ok = false; }
  if rolling.rolling_valid(-1, 1) { ok = false; }
  if !rolling.rolling_valid(1, 0) { ok = false; }
  return assert(ok, "percent strategies round surge up and unavailable down");
}

fn t10() -> TestResult {
  var c = two_ns();
  let d = deployment_create(&mut c, 0, "web", "img:v1", 1);
  var ok = int_ok_is(d, 0);
  if !int_ok_is(deployment_set_image(&mut c, 0, "img:v2"), 2) { ok = false; }
  if !streq(deployment_image(&c, 0), "img:v2") { ok = false; }
  if deployment_revision(&c, 0) != 2 { ok = false; }
  if deployment_history_count(&c, 0) != 1 { ok = false; }
  if deployment_history_revision_at(&c, 0, 0) != 1 { ok = false; }
  if !streq(deployment_history_image_at(&c, 0, 0), "img:v1") { ok = false; }
  if !int_ok_is(deployment_set_image(&mut c, 0, "img:v3"), 3) { ok = false; }
  if deployment_history_count(&c, 0) != 2 { ok = false; }
  if deployment_history_revision_at(&c, 0, 1) != 2 { ok = false; }
  if !streq(deployment_history_image_at(&c, 0, 1), "img:v2") { ok = false; }
  if !int_ok_is(deployment_rollback(&mut c, 0, -1), 4) { ok = false; }
  if !streq(deployment_image(&c, 0), "img:v2") { ok = false; }
  if deployment_revision(&c, 0) != 4 { ok = false; }
  if deployment_history_count(&c, 0) != 3 { ok = false; }
  if deployment_history_revision_at(&c, 0, 2) != 3 { ok = false; }
  if !streq(deployment_history_image_at(&c, 0, 2), "img:v3") { ok = false; }
  if !int_ok_is(deployment_rollback(&mut c, 0, 1), 5) { ok = false; }
  if !streq(deployment_image(&c, 0), "img:v1") { ok = false; }
  if deployment_history_count(&c, 0) != 4 { ok = false; }
  if deployment_history_revision_at(&c, 0, 3) != 4 { ok = false; }
  if !streq(deployment_history_image_at(&c, 0, 3), "img:v2") { ok = false; }
  if !int_err_is(deployment_rollback(&mut c, 0, 99), "deployment: revision not found") { ok = false; }
  if !int_err_is(deployment_set_image(&mut c, 0, "img:v1"), "deployment: image unchanged") { ok = false; }
  if !int_err_is(deployment_set_image(&mut c, 0, ""), "deployment: image must not be empty") { ok = false; }
  if !int_err_is(deployment_rollback(&mut c, 9, -1), "deployment: unknown deployment") { ok = false; }
  if deployment_history_revision_at(&c, 0, 9) != K8S_NOT_FOUND { ok = false; }
  if !streq(deployment_history_image_at(&c, 0, 9), "") { ok = false; }
  return assert(ok, "image revisions append and rollback walks history");
}

fn t11() -> TestResult {
  var c = two_ns();
  let d = deployment_create(&mut c, 0, "web", "img:1", 2);
  let p1 = pod_create(&mut c, 0, "web-1", 0, 0);
  let p2 = pod_create(&mut c, 0, "web-2", 0, 0);
  let p3 = pod_create(&mut c, 1, "other", 0, 0);
  var ok = int_ok_is(d, 0);
  if !int_ok_is(p1, 0) { ok = false; }
  if !int_ok_is(p2, 1) { ok = false; }
  if !int_ok_is(p3, 2) { ok = false; }
  if !int_ok_is(deployment_adopt_pod(&mut c, 0, 0), 0) { ok = false; }
  if deployment_pod_count(&c, 0) != 1 { ok = false; }
  if !int_ok_is(deployment_adopt_pod(&mut c, 0, 1), 0) { ok = false; }
  if deployment_pod_count(&c, 0) != 2 { ok = false; }
  if pod_owner(&c, 1) != 0 { ok = false; }
  if !int_err_is(deployment_adopt_pod(&mut c, 0, 0), "deployment: pod already owned") { ok = false; }
  if !int_err_is(deployment_adopt_pod(&mut c, 0, 2), "deployment: pod namespace mismatch") { ok = false; }
  if !int_err_is(deployment_adopt_pod(&mut c, 0, 9), "pod: unknown pod") { ok = false; }
  if !int_err_is(deployment_adopt_pod(&mut c, 9, 0), "deployment: unknown deployment") { ok = false; }
  if deployment_pod_count(&c, 9) != K8S_NOT_FOUND { ok = false; }
  return assert(ok, "deployment adopts same-namespace unowned pods only");
}

fn t23() -> TestResult {
  var c = two_ns();
  let d = deployment_create(&mut c, 0, "web", "img:1", 10);
  var ok = int_ok_is(d, 0);
  if deployment_surge_count(&c, 0) != 3 { ok = false; }
  if deployment_unavailable_count(&c, 0) != 2 { ok = false; }
  if deployment_rolling_rounds(&c, 0) != 3 { ok = false; }
  if !vec3_is(vec_ok_of(deployment_rolling_schedule(&c, 0)), 3, 8, 10) { ok = false; }
  if !int_ok_is(deployment_scale(&mut c, 0, 0), 0) { ok = false; }
  if deployment_rolling_rounds(&c, 0) != 0 { ok = false; }
  if vec_ok_of(deployment_rolling_schedule(&c, 0)).len() != 0 { ok = false; }
  if !int_ok_is(deployment_scale(&mut c, 0, 4), 4) { ok = false; }
  if !int_ok_is(deployment_set_strategy(&mut c, 0, 1, 0, 1, 0), 0) { ok = false; }
  if deployment_rolling_rounds(&c, 0) != 3 { ok = false; }
  if !vec3_is(vec_ok_of(deployment_rolling_schedule(&c, 0)), 1, 3, 4) { ok = false; }
  if !vec_err_is(deployment_rolling_schedule(&c, 9), "deployment: unknown deployment") { ok = false; }
  return assert(ok, "cluster deployments resolve their own rolling schedules");
}

// --------------------------------------------------
//  Services and endpoints
// --------------------------------------------------

fn t12() -> TestResult {
  var c = two_ns();
  var ok = int_ok_is(service_create(&mut c, 0, "web", K8S_SVC_CLUSTER_IP, 80, 8080), 0);
  if !int_ok_is(service_create(&mut c, 0, "api", K8S_SVC_NODE_PORT, 443, 8443), 1) { ok = false; }
  if service_count(&c) != 2 { ok = false; }
  if !streq(service_name(&c, 0), "web") { ok = false; }
  if service_namespace(&c, 1) != 0 { ok = false; }
  if service_type(&c, 0) != K8S_SVC_CLUSTER_IP { ok = false; }
  if !streq(service_type_name(K8S_SVC_CLUSTER_IP), "ClusterIP") { ok = false; }
  if !streq(service_type_name(K8S_SVC_NODE_PORT), "NodePort") { ok = false; }
  if !streq(service_type_name(K8S_SVC_LOAD_BALANCER), "LoadBalancer") { ok = false; }
  if !streq(service_type_name(9), "unknown") { ok = false; }
  if service_port(&c, 0) != 80 { ok = false; }
  if service_target_port(&c, 1) != 8443 { ok = false; }
  if service_index(&c, 0, "web") != 0 { ok = false; }
  if service_index(&c, 9, "web") != K8S_NOT_FOUND { ok = false; }
  if !int_err_is(service_create(&mut c, 9, "x", K8S_SVC_CLUSTER_IP, 80, 80), "service: unknown namespace") { ok = false; }
  if !int_err_is(service_create(&mut c, 0, "Bad", K8S_SVC_CLUSTER_IP, 80, 80), "service: invalid name") { ok = false; }
  if !int_err_is(service_create(&mut c, 0, "bad-type", 9, 80, 80), "service: invalid service type") { ok = false; }
  if !int_err_is(service_create(&mut c, 0, "bad-port", K8S_SVC_CLUSTER_IP, 0, 80), "service: port must be in 1..65535") { ok = false; }
  if !int_err_is(service_create(&mut c, 0, "big-port", K8S_SVC_CLUSTER_IP, 70000, 80), "service: port must be in 1..65535") { ok = false; }
  if !int_err_is(service_create(&mut c, 0, "bad-target", K8S_SVC_CLUSTER_IP, 80, 0), "service: target port must be in 1..65535") { ok = false; }
  if !int_err_is(service_create(&mut c, 0, "web", K8S_SVC_CLUSTER_IP, 80, 80), "service: duplicate service") { ok = false; }
  return assert(ok, "service create, types, ports and validation");
}

fn t13() -> TestResult {
  var c = two_ns();
  let p1 = pod_create(&mut c, 0, "web1", 0, 0);
  let p2 = pod_create(&mut c, 0, "web2", 0, 0);
  let p3 = pod_create(&mut c, 0, "db1", 0, 0);
  let p4 = pod_create(&mut c, 0, "web3", 0, 0);
  let s = service_create(&mut c, 0, "web", K8S_SVC_CLUSTER_IP, 80, 8080);
  let l1 = pod_label_add(&mut c, 0, "app", "web");
  let l2 = pod_label_add(&mut c, 0, "env", "prod");
  let l3 = pod_label_add(&mut c, 1, "app", "web");
  let l4 = pod_label_add(&mut c, 1, "env", "dev");
  let l5 = pod_label_add(&mut c, 2, "app", "db");
  let l6 = pod_label_add(&mut c, 2, "env", "prod");
  let l7 = pod_label_add(&mut c, 3, "app", "web");
  let l8 = pod_label_add(&mut c, 3, "env", "prod");
  var ok = int_ok_is(p1, 0) && int_ok_is(p2, 1) && int_ok_is(p3, 2) && int_ok_is(p4, 3) && int_ok_is(s, 0);
  if !int_ok_is(l1, 1) || !int_ok_is(l2, 2) || !int_ok_is(l3, 1) || !int_ok_is(l4, 2) { ok = false; }
  if !int_ok_is(l5, 1) || !int_ok_is(l6, 2) || !int_ok_is(l7, 1) || !int_ok_is(l8, 2) { ok = false; }
  if !set_phase(&mut c, 0, K8S_PHASE_RUNNING) || !set_phase(&mut c, 1, K8S_PHASE_RUNNING) { ok = false; }
  if !set_phase(&mut c, 2, K8S_PHASE_RUNNING) || !set_phase(&mut c, 3, K8S_PHASE_RUNNING) { ok = false; }
  if !int_ok_is(service_selector_add(&mut c, 0, "app", "web"), 1) { ok = false; }
  if service_selector_count(&c, 0) != 1 { ok = false; }
  if !vec3_is(vec_ok_of(service_endpoints(&c, 0)), 0, 1, 3) { ok = false; }
  if service_endpoint_count(&c, 0) != 3 { ok = false; }
  if !ep_names_is(&c, 0, "web1,web2,web3") { ok = false; }
  if !int_ok_is(service_selector_add(&mut c, 0, "env", "prod"), 2) { ok = false; }
  if !streq(service_selector_render(&c, 0), "app=web,env=prod") { ok = false; }
  if !vec2_is(vec_ok_of(service_endpoints(&c, 0)), 0, 3) { ok = false; }
  if !ep_names_is(&c, 0, "web1,web3") { ok = false; }
  if !set_phase(&mut c, 3, K8S_PHASE_FAILED) { ok = false; }
  if !vec1_is(vec_ok_of(service_endpoints(&c, 0)), 0) { ok = false; }
  if service_endpoint_count(&c, 0) != 1 { ok = false; }
  if !ep_names_is(&c, 0, "web1") { ok = false; }
  return assert(ok, "endpoints track selector and running phase only");
}

fn t14() -> TestResult {
  var c = two_ns();
  let s0 = service_create(&mut c, 0, "empty-sel", K8S_SVC_CLUSTER_IP, 80, 80);
  let s1 = service_create(&mut c, 1, "prod-web", K8S_SVC_CLUSTER_IP, 80, 8080);
  let p0 = pod_create(&mut c, 0, "default-web", 0, 0);
  let p1 = pod_create(&mut c, 1, "prod-web", 0, 0);
  var ok = int_ok_is(s0, 0) && int_ok_is(s1, 1) && int_ok_is(p0, 0) && int_ok_is(p1, 1);
  if !int_ok_is(pod_label_add(&mut c, 0, "app", "web"), 1) { ok = false; }
  if !int_ok_is(pod_label_add(&mut c, 1, "app", "web"), 1) { ok = false; }
  if !set_phase(&mut c, 0, K8S_PHASE_RUNNING) { ok = false; }
  if !set_phase(&mut c, 1, K8S_PHASE_RUNNING) { ok = false; }
  if !vec_err_is(service_endpoints(&c, 0), "service: selector is empty") { ok = false; }
  if service_endpoint_count(&c, 0) != K8S_NOT_FOUND { ok = false; }
  if !streq(service_endpoint_names(&c, 0), "") { ok = false; }
  if !int_ok_is(service_selector_add(&mut c, 1, "app", "web"), 1) { ok = false; }
  if !vec1_is(vec_ok_of(service_endpoints(&c, 1)), 1) { ok = false; }
  if !ep_names_is(&c, 1, "prod-web") { ok = false; }
  if !vec_err_is(service_endpoints(&c, 9), "service: unknown service") { ok = false; }
  if !int_err_is(service_selector_add(&mut c, 0, "bad key", "x"), "label: invalid key") { ok = false; }
  if !int_err_is(service_selector_add(&mut c, 9, "a", "b"), "service: unknown service") { ok = false; }
  return assert(ok, "endpoints are namespace-scoped and selector errors are exact");
}

fn t22() -> TestResult {
  var c = two_ns();
  let s = service_create(&mut c, 0, "lb", K8S_SVC_LOAD_BALANCER, 443, 8443);
  let p = pod_create(&mut c, 0, "web", 0, 0);
  var ok = int_ok_is(s, 0) && int_ok_is(p, 0);
  if service_type(&c, 0) != K8S_SVC_LOAD_BALANCER { ok = false; }
  if !int_ok_is(service_selector_add(&mut c, 0, "app", "nomatch"), 1) { ok = false; }
  if vec_ok_of(service_endpoints(&c, 0)).len() != 0 { ok = false; }
  if service_endpoint_count(&c, 0) != 0 { ok = false; }
  if !streq(service_endpoint_names(&c, 0), "") { ok = false; }
  return assert(ok, "a selector with no matching pods has zero endpoints");
}

// --------------------------------------------------
//  Ingress
// --------------------------------------------------

fn t17() -> TestResult {
  var c = two_ns();
  var ok = int_ok_is(ingress_create(&mut c, 0, "web-ing"), 0);
  if ingress_count(&c) != 1 { ok = false; }
  if !streq(ingress_name(&c, 0), "web-ing") { ok = false; }
  if ingress_namespace(&c, 0) != 0 { ok = false; }
  if ingress_rule_count(&c, 0) != 0 { ok = false; }
  if !int_ok_is(ingress_rule_add(&mut c, 0, "", "/", "web", 80), 1) { ok = false; }
  if !int_ok_is(ingress_rule_add(&mut c, 0, "api.example.com", "/v1", "api", 8080), 2) { ok = false; }
  if ingress_rule_count(&c, 0) != 2 { ok = false; }
  if !streq(ingress_rule_host(&c, 0, 0), "") { ok = false; }
  if !streq(ingress_rule_path(&c, 0, 0), "/") { ok = false; }
  if !streq(ingress_rule_service(&c, 0, 0), "web") { ok = false; }
  if ingress_rule_port(&c, 0, 0) != 80 { ok = false; }
  if !streq(ingress_rule_host(&c, 0, 1), "api.example.com") { ok = false; }
  if ingress_rule_port(&c, 0, 1) != 8080 { ok = false; }
  if ingress_index(&c, 0, "web-ing") != 0 { ok = false; }
  if !streq(ingress_rule_path(&c, 0, 9), "") { ok = false; }
  if ingress_rule_count(&c, 9) != K8S_NOT_FOUND { ok = false; }
  if !ingress_host_valid("example.com") { ok = false; }
  if !ingress_host_valid("api.example.com") { ok = false; }
  if ingress_host_valid("bad_host") { ok = false; }
  if ingress_host_valid("-bad.com") { ok = false; }
  if ingress_host_valid("") { ok = false; }
  if !int_err_is(ingress_create(&mut c, 9, "x"), "ingress: unknown namespace") { ok = false; }
  if !int_err_is(ingress_create(&mut c, 0, "Bad"), "ingress: invalid name") { ok = false; }
  if !int_err_is(ingress_create(&mut c, 0, "web-ing"), "ingress: duplicate ingress") { ok = false; }
  if !int_err_is(ingress_rule_add(&mut c, 0, "bad_host", "/x", "web", 80), "ingress: invalid host") { ok = false; }
  if !int_err_is(ingress_rule_add(&mut c, 0, "", "", "web", 80), "ingress: path must start with '/'") { ok = false; }
  if !int_err_is(ingress_rule_add(&mut c, 0, "", "v1", "web", 80), "ingress: path must start with '/'") { ok = false; }
  if !int_err_is(ingress_rule_add(&mut c, 0, "", "/x", "", 80), "ingress: service name must not be empty") { ok = false; }
  if !int_err_is(ingress_rule_add(&mut c, 0, "", "/x", "Bad", 80), "ingress: invalid service name") { ok = false; }
  if !int_err_is(ingress_rule_add(&mut c, 0, "", "/x", "web", 0), "ingress: port must be in 1..65535") { ok = false; }
  if !int_err_is(ingress_rule_add(&mut c, 9, "", "/x", "web", 80), "ingress: unknown ingress") { ok = false; }
  return assert(ok, "ingress rules, host grammar and validation");
}

fn t18() -> TestResult {
  var c = two_ns();
  let sw = service_create(&mut c, 0, "web", K8S_SVC_CLUSTER_IP, 80, 8080);
  let sa = service_create(&mut c, 0, "api", K8S_SVC_CLUSTER_IP, 80, 9080);
  let i0 = ingress_create(&mut c, 0, "main");
  let i1 = ingress_create(&mut c, 0, "empty");
  var ok = int_ok_is(sw, 0) && int_ok_is(sa, 1) && int_ok_is(i0, 0) && int_ok_is(i1, 1);
  if !int_ok_is(ingress_rule_add(&mut c, 0, "", "/", "web", 80), 1) { ok = false; }
  if !int_ok_is(ingress_rule_add(&mut c, 0, "api.example.com", "/v1", "api", 9080), 2) { ok = false; }
  if !int_ok_is(ingress_rule_add(&mut c, 0, "api.example.com", "/v1/admin", "web", 80), 3) { ok = false; }
  if !int_ok_is(ingress_resolve(&c, 0, "api.example.com", "/v1/users"), 1) { ok = false; }
  if !int_ok_is(ingress_resolve(&c, 0, "api.example.com", "/v1/admin/users"), 0) { ok = false; }
  if !int_ok_is(ingress_resolve(&c, 0, "api.example.com", "/other"), 0) { ok = false; }
  if !int_ok_is(ingress_resolve(&c, 0, "www.example.com", "/v1/users"), 0) { ok = false; }
  if !int_ok_is(ingress_resolve(&c, 0, "api.example.com", "/v1x"), 0) { ok = false; }
  if !ingress_exposes(&c, 0, "api.example.com", "/v1/users") { ok = false; }
  if ingress_exposes(&c, 1, "any.example.com", "/") { ok = false; }
  if !int_err_is(ingress_resolve(&c, 1, "any.example.com", "/"), "ingress: no matching rule") { ok = false; }
  if !int_ok_is(ingress_rule_add(&mut c, 1, "", "/api", "ghost", 80), 1) { ok = false; }
  if !int_err_is(ingress_resolve(&c, 1, "any.example.com", "/api/x"), "ingress: backend service not found") { ok = false; }
  if !int_err_is(ingress_resolve(&c, 9, "any.example.com", "/"), "ingress: unknown ingress") { ok = false; }
  if !int_err_is(ingress_resolve(&c, 0, "any.example.com", "nope"), "ingress: path must start with '/'") { ok = false; }
  if !int_err_is(ingress_resolve(&c, 0, "bad_host", "/"), "ingress: invalid host") { ok = false; }
  return assert(ok, "longest-prefix ingress resolution and exposure rules");
}

// --------------------------------------------------
//  Config, secrets and scoping
// --------------------------------------------------

fn t15() -> TestResult {
  var c = two_ns();
  var ok = int_ok_is(configmap_create(&mut c, 0, "app-config", false), 0);
  if configmap_count(&c) != 1 { ok = false; }
  if !streq(configmap_name(&c, 0), "app-config") { ok = false; }
  if configmap_namespace(&c, 0) != 0 { ok = false; }
  if configmap_immutable(&c, 0) { ok = false; }
  if !configmap_visible(&c, 0, 0) { ok = false; }
  if configmap_visible(&c, 0, 1) { ok = false; }
  if !int_ok_is(configmap_set(&mut c, 0, "log.level", "debug"), 1) { ok = false; }
  if !int_ok_is(configmap_set(&mut c, 0, "retries", "3"), 2) { ok = false; }
  if configmap_key_count(&c, 0) != 2 { ok = false; }
  if !streq(configmap_get(&c, 0, "log.level"), "debug") { ok = false; }
  if !streq(configmap_get(&c, 0, "missing"), "") { ok = false; }
  if !streq(configmap_render(&c, 0), "log.level=debug,retries=3") { ok = false; }
  if !int_err_is(configmap_set(&mut c, 0, "retries", "4"), "configmap: duplicate key") { ok = false; }
  if !int_err_is(configmap_set(&mut c, 0, "bad key", "x"), "configmap: invalid key") { ok = false; }
  if !int_err_is(configmap_set(&mut c, 0, "", "x"), "configmap: key must not be empty") { ok = false; }
  if !int_ok_is(configmap_create(&mut c, 0, "locked", true), 1) { ok = false; }
  if !configmap_immutable(&c, 1) { ok = false; }
  if !int_err_is(configmap_set(&mut c, 1, "k", "v"), "configmap: immutable") { ok = false; }
  if !int_err_is(configmap_create(&mut c, 0, "app-config", false), "configmap: duplicate configmap") { ok = false; }
  if !int_err_is(configmap_create(&mut c, 9, "x", false), "configmap: unknown namespace") { ok = false; }
  if !int_err_is(configmap_create(&mut c, 0, "Bad", false), "configmap: invalid name") { ok = false; }
  if !int_err_is(configmap_set(&mut c, 9, "k", "v"), "configmap: unknown configmap") { ok = false; }
  return assert(ok, "configmap entries, immutability and namespacing");
}

fn t16() -> TestResult {
  var c = two_ns();
  var ok = int_ok_is(secret_create(&mut c, 0, "tls-secret", "Opaque"), 0);
  if !int_ok_is(secret_create(&mut c, 1, "tls-secret", "kubernetes.io/tls"), 1) { ok = false; }
  if secret_count(&c) != 2 { ok = false; }
  if !streq(secret_name(&c, 1), "tls-secret") { ok = false; }
  if secret_namespace(&c, 1) != 1 { ok = false; }
  if !streq(secret_type_value(&c, 0), "Opaque") { ok = false; }
  if !streq(secret_type_value(&c, 1), "kubernetes.io/tls") { ok = false; }
  if !int_ok_is(secret_set(&mut c, 0, "token", "abc"), 1) { ok = false; }
  if !streq(secret_get(&c, 0, "token"), "abc") { ok = false; }
  if secret_key_count(&c, 0) != 1 { ok = false; }
  if !int_err_is(secret_set(&mut c, 0, "token", "x"), "secret: duplicate key") { ok = false; }
  if !int_err_is(secret_create(&mut c, 0, "bad", ""), "secret: type must not be empty") { ok = false; }
  if !int_err_is(secret_create(&mut c, 0, "tls-secret", "Opaque"), "secret: duplicate secret") { ok = false; }
  let cm0 = configmap_create(&mut c, 0, "shared", false);
  let cm1 = configmap_create(&mut c, 1, "shared", false);
  let p0 = pod_create(&mut c, 0, "pod-a", 0, 0);
  let p1 = pod_create(&mut c, 1, "pod-b", 0, 0);
  if !int_ok_is(cm0, 0) || !int_ok_is(cm1, 1) || !int_ok_is(p0, 0) || !int_ok_is(p1, 1) { ok = false; }
  if !int_ok_is(pod_ref_configmap(&c, 0, "shared"), 0) { ok = false; }
  if !int_ok_is(pod_ref_configmap(&c, 1, "shared"), 1) { ok = false; }
  if !int_err_is(pod_ref_configmap(&c, 0, "nope"), "configmap: not found") { ok = false; }
  if !int_ok_is(pod_ref_secret(&c, 0, "tls-secret"), 0) { ok = false; }
  if !int_ok_is(pod_ref_secret(&c, 1, "tls-secret"), 1) { ok = false; }
  if !int_err_is(pod_ref_secret(&c, 0, "nope"), "secret: not found") { ok = false; }
  if !int_err_is(pod_ref_secret(&c, 9, "x"), "pod: unknown pod") { ok = false; }
  return assert(ok, "secrets and namespace-scoped config/secret references");
}

// --------------------------------------------------
//  Quota accounting
// --------------------------------------------------

fn t19() -> TestResult {
  var c = k8s_cluster_new();
  var ok = int_ok_is(namespace_create(&mut c, "small", 2, 1000, 1024), 0);
  if !int_ok_is(namespace_create(&mut c, "cpu", 0, 500, 0), 1) { ok = false; }
  if !int_ok_is(namespace_create(&mut c, "mem", 0, 0, 100), 2) { ok = false; }
  if !int_ok_is(pod_create(&mut c, 0, "a", 300, 256), 0) { ok = false; }
  if !int_ok_is(pod_create(&mut c, 0, "b", 300, 256), 1) { ok = false; }
  if namespace_used_pods(&c, 0) != 2 { ok = false; }
  if namespace_used_cpu(&c, 0) != 600 { ok = false; }
  if namespace_used_mem(&c, 0) != 512 { ok = false; }
  if !int_err_is(pod_create(&mut c, 0, "c", 0, 0), "quota: pod limit exceeded") { ok = false; }
  if !int_err_is(namespace_admit_pod(&c, 0, 100, 100), "quota: pod limit exceeded") { ok = false; }
  if !int_ok_is(namespace_admit_pod(&c, 1, 400, 0), 1) { ok = false; }
  if !int_ok_is(pod_create(&mut c, 1, "cpu-a", 400, 0), 2) { ok = false; }
  if !int_err_is(pod_create(&mut c, 1, "cpu-b", 200, 0), "quota: cpu quota exceeded") { ok = false; }
  if namespace_used_cpu(&c, 1) != 400 { ok = false; }
  if !int_ok_is(pod_create(&mut c, 2, "mem-a", 0, 60), 3) { ok = false; }
  if !int_err_is(pod_create(&mut c, 2, "mem-b", 0, 50), "quota: memory quota exceeded") { ok = false; }
  if !int_err_is(namespace_admit_pod(&c, 0, -1, 0), "quota: resources must be >= 0") { ok = false; }
  if !int_err_is(namespace_admit_pod(&c, 9, 0, 0), "namespace: unknown namespace") { ok = false; }
  if namespace_used_pods(&c, 9) != K8S_NOT_FOUND { ok = false; }
  if namespace_used_pods(&c, 2) != 1 { ok = false; }
  if !int_ok_is(configmap_create(&mut c, 0, "c1", false), 0) { ok = false; }
  if !int_ok_is(configmap_create(&mut c, 0, "c2", false), 1) { ok = false; }
  if !int_ok_is(secret_create(&mut c, 0, "s1", "Opaque"), 0) { ok = false; }
  if namespace_used_configmaps(&c, 0) != 2 { ok = false; }
  if namespace_used_secrets(&c, 0) != 1 { ok = false; }
  if namespace_used_configmaps(&c, 1) != 0 { ok = false; }
  return assert(ok, "namespace quota accounting and admission");
}

// --------------------------------------------------
//  Determinism
// --------------------------------------------------

fn t20() -> TestResult {
  var a = build_fixture();
  var b = build_fixture();
  var ok = streq(service_endpoint_names(&a, 0), service_endpoint_names(&b, 0));
  if !streq(pod_labels_render(&a, 0), pod_labels_render(&b, 0)) { ok = false; }
  if !streq(deployment_image(&a, 0), deployment_image(&b, 0)) { ok = false; }
  if deployment_revision(&a, 0) != deployment_revision(&b, 0) { ok = false; }
  if deployment_rolling_rounds(&a, 0) != deployment_rolling_rounds(&b, 0) { ok = false; }
  if !streq(service_selector_render(&a, 0), service_selector_render(&b, 0)) { ok = false; }
  if namespace_used_cpu(&a, 0) != namespace_used_cpu(&b, 0) { ok = false; }
  let n1 = service_endpoint_names(&a, 0);
  let n2 = service_endpoint_names(&a, 0);
  if !streq(n1, n2) { ok = false; }
  if !ep_names_is(&a, 0, "web1,web2") { ok = false; }
  if !int_ok_is(ingress_resolve(&a, 0, "any.example.com", "/x"), 0) { ok = false; }
  return assert(ok, "identical inputs produce identical outputs");
}

// --------------------------------------------------
//  Runner (direct calls: indexed Vec[fn] dispatch is a known miscompile)
// --------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.k8s conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.k8s: all tests passed");
  } else {
    io.println("xiom.k8s: tests failed");
  }
  return failed;
}
