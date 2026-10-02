// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.k8s: Kubernetes orchestration model (core object model)
// Port task: replace the xiom.k8s placeholder with a real, tested, pure-XIOM
// package: Kubernetes orchestration as a deterministic in-memory model.
// No API server, no networking, no file I/O, no FFI.
//
// The cluster is one value with parallel Vec fields per object kind (no
// Vec[StructType]); every name, image, label and rule string lives in a Str
// blob with a monotone Vec[Int] offset table (no Vec[Str]). Per-object
// collections (pod labels, service selectors, configmap/secret entries,
// deployment image history, ingress rules) are stored in cluster-wide blobs
// plus parallel owner tables; a scan is bounded by the object and entry
// limits below.
//
// Pod lifecycle phase machine (Kubernetes phases):
//
//   PENDING --start--> RUNNING --finish--> SUCCEEDED   (terminal)
//      |                  |  \--fail----> FAILED      (terminal)
//      |                  |
//      +------fail------->+-- + ----> UNKNOWN <-- (node lost)
//                                  |
//              PENDING/RUNNING/SUCCEEDED/FAILED <-- recover
//
// Concretely: PENDING -> RUNNING | FAILED | UNKNOWN; RUNNING -> SUCCEEDED |
// FAILED | UNKNOWN; UNKNOWN -> PENDING | RUNNING | SUCCEEDED | FAILED;
// SUCCEEDED and FAILED are terminal. That is exactly ten legal pairs.
//
// Companion modules in this package:
//   * xiom.k8s.selector (src/selector.xi) -- label sets and matching;
//   * xiom.k8s.rolling  (src/rolling.xi)  -- rolling-update replica math.
//
// Language notes (XIOM v0.62.2): free functions only; Ok/Err are constructed
// only inside the _k_* leaf helpers; every Vec[Int] element read binds a
// typed local; no `==` on Str (string.str_compare everywhere); no `mut` in
// match patterns; all matches exhaustive; no `log`-named function; explicit
// `&mut` at every &mut Vec call site; widened bytes masked with `& 0xFF`;
// bounded loops everywhere.

module xiom.k8s

use xiom.string;
use xiom.k8s.selector;
use xiom.k8s.rolling;

// ---------------------------------------------------------------------------
// Public constants
// ---------------------------------------------------------------------------

/// Pod phase: accepted by the scheduler, not started.
pub const K8S_PHASE_PENDING: Int = 0;

/// Pod phase: running.
pub const K8S_PHASE_RUNNING: Int = 1;

/// Pod phase: all containers finished successfully (terminal).
pub const K8S_PHASE_SUCCEEDED: Int = 2;

/// Pod phase: at least one container failed (terminal).
pub const K8S_PHASE_FAILED: Int = 3;

/// Pod phase: state unknown (node lost); recoverable.
pub const K8S_PHASE_UNKNOWN: Int = 4;

/// Service type: cluster-internal virtual IP.
pub const K8S_SVC_CLUSTER_IP: Int = 0;

/// Service type: cluster IP plus a node port.
pub const K8S_SVC_NODE_PORT: Int = 1;

/// Service type: external load balancer.
pub const K8S_SVC_LOAD_BALANCER: Int = 2;

/// Sentinel: unknown id / out-of-range accessor result.
pub const K8S_NOT_FOUND: Int = -1;

/// Longest accepted object name, in bytes.
pub const K8S_MAX_NAME: Int = 63;

/// Highest accepted port number.
pub const K8S_MAX_PORT: Int = 65535;

/// Capacity guard: namespaces per cluster.
pub const K8S_MAX_NAMESPACES: Int = 64;

/// Capacity guard: objects (pods, deployments, services, configmaps,
/// secrets, ingresses) per kind per cluster.
pub const K8S_MAX_OBJECTS: Int = 256;

/// Capacity guard: retained revision-history records per deployment.
pub const K8S_MAX_REVISIONS: Int = 16;

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// One cluster: parallel arrays indexed by dense per-kind ids (0-based, ids
/// never reused). All name-like strings are blob + offset tables. Fields are
/// implementation detail; use the accessors. Object names are unique per
/// namespace; every per-namespace query is namespace-scoped.
pub type K8sCluster = {
  // namespaces
  ns_data: Str;
  ns_off: Vec[Int];
  ns_max_pods: Vec[Int];
  ns_cpu_milli: Vec[Int];
  ns_mem_mib: Vec[Int];
  // pods
  pod_data: Str;
  pod_off: Vec[Int];
  pod_ns: Vec[Int];
  pod_phase: Vec[Int];
  pod_cpu: Vec[Int];
  pod_mem: Vec[Int];
  pod_owner: Vec[Int];
  pod_moves: Vec[Int];
  pod_lbl_data: Str;
  pod_lbl_off: Vec[Int];
  pod_lbl_owner: Vec[Int];
  // deployments
  dep_data: Str;
  dep_off: Vec[Int];
  dep_ns: Vec[Int];
  dep_replicas: Vec[Int];
  dep_surge: Vec[Int];
  dep_surge_pct: Vec[Int];
  dep_unavail: Vec[Int];
  dep_unavail_pct: Vec[Int];
  dep_revision: Vec[Int];
  dep_img_data: Str;
  dep_img_off: Vec[Int];
  dep_img_owner: Vec[Int];
  dep_hist_rev: Vec[Int];
  dep_hist_owner: Vec[Int];
  dep_hist_img_data: Str;
  dep_hist_img_off: Vec[Int];
  // services
  svc_data: Str;
  svc_off: Vec[Int];
  svc_ns: Vec[Int];
  svc_type: Vec[Int];
  svc_port: Vec[Int];
  svc_target: Vec[Int];
  svc_sel_data: Str;
  svc_sel_off: Vec[Int];
  svc_sel_owner: Vec[Int];
  // configmaps
  cm_data: Str;
  cm_off: Vec[Int];
  cm_ns: Vec[Int];
  cm_immutable: Vec[Int];
  cm_kv_data: Str;
  cm_kv_off: Vec[Int];
  cm_kv_owner: Vec[Int];
  // secrets
  sec_data: Str;
  sec_off: Vec[Int];
  sec_ns: Vec[Int];
  sec_type_data: Str;
  sec_type_off: Vec[Int];
  sec_kv_data: Str;
  sec_kv_off: Vec[Int];
  sec_kv_owner: Vec[Int];
  // ingress
  ing_data: Str;
  ing_off: Vec[Int];
  ing_ns: Vec[Int];
  ing_rule_host_data: Str;
  ing_rule_host_off: Vec[Int];
  ing_rule_host_owner: Vec[Int];
  ing_rule_path_data: Str;
  ing_rule_path_off: Vec[Int];
  ing_rule_svc_data: Str;
  ing_rule_svc_off: Vec[Int];
  ing_rule_port: Vec[Int];
}

// ---------------------------------------------------------------------------
// Result constructors (leaf helpers only)
// ---------------------------------------------------------------------------

fn _k_ok_int(v: Int) -> Result[Int, Str] { return Ok(v); }
fn _k_err_int(m: Str) -> Result[Int, Str] { return Err(m); }
fn _k_ok_vec(v: Vec[Int]) -> Result[Vec[Int], Str] { return Ok(v); }
fn _k_err_vec(m: Str) -> Result[Vec[Int], Str] { return Err(m); }
fn _k_ok_str(v: Str) -> Result[Str, Str] { return Ok(v); }
fn _k_err_str(m: Str) -> Result[Str, Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Blob helpers (Str + monotone Vec[Int] offsets; no Vec[Str])
// ---------------------------------------------------------------------------

// Append `s` to blob `data`/`off`; the caller assigns the returned Str.
fn _k_blob_append(data: Str, off: &mut Vec[Int], s: Str) -> Str {
  let start: Int = off[off.len() - 1];
  off.push(start + string.str_len(s));
  return data + s;
}

// Append `s` owned by `owner_id`: blob + offset + owner stay in lockstep.
fn _k_owner_append(data: Str, off: &mut Vec[Int], owner: &mut Vec[Int], owner_id: Int, s: Str) -> Str {
  let nd = _k_blob_append(data, off, s);
  owner.push(owner_id);
  return nd;
}

// Entry `i` of blob `data`/`off`, or "" when out of range.
fn _k_entry(data: Str, off: &Vec[Int], i: Int) -> Str {
  if i < 0 || i >= off.len() - 1 { return ""; }
  let a: Int = off[i];
  let b: Int = off[i + 1];
  return string.str_slice(data, a, b);
}

// Index of `name` in a flat name blob, or -1.
fn _k_name_find(data: Str, off: &Vec[Int], name: Str) -> Int {
  let cnt = off.len() - 1;
  var i = 0;
  while i < cnt {
    let a: Int = off[i];
    let b: Int = off[i + 1];
    if string.str_compare(string.str_slice(data, a, b), name) == 0 { return i; }
    i = i + 1;
  }
  return -1;
}

// Index of `name` in a namespace-scoped name blob, or -1. The ns and off
// arrays must stay parallel; on drift nothing matches.
fn _k_obj_find(data: Str, off: &Vec[Int], ns: &Vec[Int], ns_id: Int, name: Str) -> Int {
  let cnt = off.len() - 1;
  if ns.len() != cnt { return -1; }
  var i = 0;
  while i < cnt {
    let n: Int = ns[i];
    if n == ns_id {
      let a: Int = off[i];
      let b: Int = off[i + 1];
      if string.str_compare(string.str_slice(data, a, b), name) == 0 { return i; }
    }
    i = i + 1;
  }
  return -1;
}

// ---------------------------------------------------------------------------
// Grammar (ASCII only; every widened byte masked with & 0xFF)
// ---------------------------------------------------------------------------

fn _k_is_lower(c: Int) -> Bool { return c >= 0x61 && c <= 0x7A; }
fn _k_is_upper(c: Int) -> Bool { return c >= 0x41 && c <= 0x5A; }
fn _k_is_digit(c: Int) -> Bool { return c >= 0x30 && c <= 0x39; }

fn _k_is_alnum(c: Int) -> Bool {
  if _k_is_lower(c) { return true; }
  if _k_is_upper(c) { return true; }
  return _k_is_digit(c);
}

fn _k_name_char(c: Int) -> Bool {
  if _k_is_lower(c) { return true; }
  if _k_is_digit(c) { return true; }
  if c == 0x2D { return true; }
  return false;
}

// DNS-1123 labels are lowercase only.
fn _k_name_alnum(c: Int) -> Bool {
  if _k_is_lower(c) { return true; }
  return _k_is_digit(c);
}

/// True when `name` is a valid DNS-1123 label (object name): 1..63 bytes of
/// [a-z0-9-], first and last byte lowercase alphanumeric. Complexity: O(len).
pub fn k8s_name_valid(name: Str) -> Bool {
  let n = string.str_len(name);
  if n < 1 || n > K8S_MAX_NAME { return false; }
  let first: Int = (string.byte_at(name, 0) as Int) & 0xFF;
  let last: Int = (string.byte_at(name, n - 1) as Int) & 0xFF;
  if !_k_name_alnum(first) { return false; }
  if !_k_name_alnum(last) { return false; }
  var i = 1;
  while i < n - 1 {
    let b: Int = (string.byte_at(name, i) as Int) & 0xFF;
    if !_k_name_char(b) { return false; }
    i = i + 1;
  }
  return true;
}

fn _k_config_key_char(c: Int) -> Bool {
  if _k_is_alnum(c) { return true; }
  if c == 0x2D { return true; }
  if c == 0x5F { return true; }
  if c == 0x2E { return true; }
  return false;
}

// ConfigMap/Secret key: 1..253 bytes, first and last alphanumeric.
fn _k_config_key_valid(k: Str) -> Bool {
  let n = string.str_len(k);
  if n < 1 || n > 253 { return false; }
  let first: Int = (string.byte_at(k, 0) as Int) & 0xFF;
  let last: Int = (string.byte_at(k, n - 1) as Int) & 0xFF;
  if !_k_is_alnum(first) { return false; }
  if !_k_is_alnum(last) { return false; }
  var i = 1;
  while i < n - 1 {
    let b: Int = (string.byte_at(k, i) as Int) & 0xFF;
    if !_k_config_key_char(b) { return false; }
    i = i + 1;
  }
  return true;
}

// One dot-separated host label spanning [a, b); 1..63 bytes, first and last
// alphanumeric, inner bytes alphanumeric or '-'.
fn _k_host_label_valid(h: Str, a: Int, b: Int) -> Bool {
  let n = b - a;
  if n < 1 || n > 63 { return false; }
  let first: Int = (string.byte_at(h, a) as Int) & 0xFF;
  let last: Int = (string.byte_at(h, b - 1) as Int) & 0xFF;
  if !_k_is_alnum(first) { return false; }
  if !_k_is_alnum(last) { return false; }
  var i = a + 1;
  while i < b - 1 {
    let c: Int = (string.byte_at(h, i) as Int) & 0xFF;
    if !_k_is_alnum(c) && c != 0x2D { return false; }
    i = i + 1;
  }
  return true;
}

/// True when `h` is a valid DNS host name (label[.label]*), 1..253 bytes.
/// Complexity: O(len).
pub fn ingress_host_valid(h: Str) -> Bool {
  let n = string.str_len(h);
  if n < 1 || n > 253 { return false; }
  var start = 0;
  var i = 0;
  while i < n {
    let b: Int = (string.byte_at(h, i) as Int) & 0xFF;
    if b == 0x2E {
      if !_k_host_label_valid(h, start, i) { return false; }
      start = i + 1;
    }
    i = i + 1;
  }
  return _k_host_label_valid(h, start, n);
}

// ---------------------------------------------------------------------------
// Cluster construction
// ---------------------------------------------------------------------------

/// Empty cluster. Complexity: O(1).
pub fn k8s_cluster_new() -> K8sCluster {
  var ns_off = Vec[Int].new();
  ns_off.push(0);
  var pod_off = Vec[Int].new();
  pod_off.push(0);
  var pod_lbl_off = Vec[Int].new();
  pod_lbl_off.push(0);
  var dep_off = Vec[Int].new();
  dep_off.push(0);
  var dep_img_off = Vec[Int].new();
  dep_img_off.push(0);
  var dep_hist_img_off = Vec[Int].new();
  dep_hist_img_off.push(0);
  var svc_off = Vec[Int].new();
  svc_off.push(0);
  var svc_sel_off = Vec[Int].new();
  svc_sel_off.push(0);
  var cm_off = Vec[Int].new();
  cm_off.push(0);
  var cm_kv_off = Vec[Int].new();
  cm_kv_off.push(0);
  var sec_off = Vec[Int].new();
  sec_off.push(0);
  var sec_type_off = Vec[Int].new();
  sec_type_off.push(0);
  var sec_kv_off = Vec[Int].new();
  sec_kv_off.push(0);
  var ing_off = Vec[Int].new();
  ing_off.push(0);
  var ing_rule_host_off = Vec[Int].new();
  ing_rule_host_off.push(0);
  var ing_rule_path_off = Vec[Int].new();
  ing_rule_path_off.push(0);
  var ing_rule_svc_off = Vec[Int].new();
  ing_rule_svc_off.push(0);
  return K8sCluster{
    ns_data: ""; ns_off: ns_off; ns_max_pods: Vec[Int].new(); ns_cpu_milli: Vec[Int].new(); ns_mem_mib: Vec[Int].new();
    pod_data: ""; pod_off: pod_off; pod_ns: Vec[Int].new(); pod_phase: Vec[Int].new();
    pod_cpu: Vec[Int].new(); pod_mem: Vec[Int].new(); pod_owner: Vec[Int].new(); pod_moves: Vec[Int].new();
    pod_lbl_data: ""; pod_lbl_off: pod_lbl_off; pod_lbl_owner: Vec[Int].new();
    dep_data: ""; dep_off: dep_off; dep_ns: Vec[Int].new(); dep_replicas: Vec[Int].new();
    dep_surge: Vec[Int].new(); dep_surge_pct: Vec[Int].new();
    dep_unavail: Vec[Int].new(); dep_unavail_pct: Vec[Int].new(); dep_revision: Vec[Int].new();
    dep_img_data: ""; dep_img_off: dep_img_off; dep_img_owner: Vec[Int].new();
    dep_hist_rev: Vec[Int].new(); dep_hist_owner: Vec[Int].new();
    dep_hist_img_data: ""; dep_hist_img_off: dep_hist_img_off;
    svc_data: ""; svc_off: svc_off; svc_ns: Vec[Int].new(); svc_type: Vec[Int].new();
    svc_port: Vec[Int].new(); svc_target: Vec[Int].new();
    svc_sel_data: ""; svc_sel_off: svc_sel_off; svc_sel_owner: Vec[Int].new();
    cm_data: ""; cm_off: cm_off; cm_ns: Vec[Int].new(); cm_immutable: Vec[Int].new();
    cm_kv_data: ""; cm_kv_off: cm_kv_off; cm_kv_owner: Vec[Int].new();
    sec_data: ""; sec_off: sec_off; sec_ns: Vec[Int].new();
    sec_type_data: ""; sec_type_off: sec_type_off;
    sec_kv_data: ""; sec_kv_off: sec_kv_off; sec_kv_owner: Vec[Int].new();
    ing_data: ""; ing_off: ing_off; ing_ns: Vec[Int].new();
    ing_rule_host_data: ""; ing_rule_host_off: ing_rule_host_off; ing_rule_host_owner: Vec[Int].new();
    ing_rule_path_data: ""; ing_rule_path_off: ing_rule_path_off;
    ing_rule_svc_data: ""; ing_rule_svc_off: ing_rule_svc_off; ing_rule_port: Vec[Int].new();
  };
}

// ---------------------------------------------------------------------------
// Namespaces and quota accounting
// ---------------------------------------------------------------------------

/// Create a namespace. Quotas are 0 = unlimited (max_pods, cpu in millicores,
/// memory in MiB). Returns the dense namespace id.
/// Errors: "namespace: name must not be empty", "namespace: invalid name",
/// "namespace: duplicate namespace", "namespace: quota must be >= 0",
/// "namespace: object limit exceeded".
pub fn namespace_create(c: &mut K8sCluster, name: Str, max_pods: Int, cpu_milli: Int, mem_mib: Int) -> Result[Int, Str] {
  if string.str_len(name) == 0 { return _k_err_int("namespace: name must not be empty"); }
  if !k8s_name_valid(name) { return _k_err_int("namespace: invalid name"); }
  if max_pods < 0 || cpu_milli < 0 || mem_mib < 0 { return _k_err_int("namespace: quota must be >= 0"); }
  if _k_name_find(c.ns_data, &c.ns_off, name) >= 0 { return _k_err_int("namespace: duplicate namespace"); }
  if c.ns_off.len() - 1 >= K8S_MAX_NAMESPACES { return _k_err_int("namespace: object limit exceeded"); }
  let id = c.ns_off.len() - 1;
  c.ns_data = _k_blob_append(c.ns_data, &mut c.ns_off, name);
  c.ns_max_pods.push(max_pods);
  c.ns_cpu_milli.push(cpu_milli);
  c.ns_mem_mib.push(mem_mib);
  return _k_ok_int(id);
}

/// Number of namespaces. Complexity: O(1).
pub fn namespace_count(c: &K8sCluster) -> Int {
  return c.ns_off.len() - 1;
}

/// Namespace id of `name`, or K8S_NOT_FOUND (-1). Complexity: O(n).
pub fn namespace_index(c: &K8sCluster, name: Str) -> Int {
  return _k_name_find(c.ns_data, &c.ns_off, name);
}

/// Namespace name, or "" when the id is out of range.
pub fn namespace_name(c: &K8sCluster, id: Int) -> Str {
  return _k_entry(c.ns_data, &c.ns_off, id);
}

/// Pod quota (0 = unlimited), or K8S_NOT_FOUND.
pub fn namespace_max_pods(c: &K8sCluster, id: Int) -> Int {
  if id < 0 || id >= c.ns_max_pods.len() { return K8S_NOT_FOUND; }
  let v: Int = c.ns_max_pods[id];
  return v;
}

/// CPU quota in millicores (0 = unlimited), or K8S_NOT_FOUND.
pub fn namespace_cpu_quota(c: &K8sCluster, id: Int) -> Int {
  if id < 0 || id >= c.ns_cpu_milli.len() { return K8S_NOT_FOUND; }
  let v: Int = c.ns_cpu_milli[id];
  return v;
}

/// Memory quota in MiB (0 = unlimited), or K8S_NOT_FOUND.
pub fn namespace_mem_quota(c: &K8sCluster, id: Int) -> Int {
  if id < 0 || id >= c.ns_mem_mib.len() { return K8S_NOT_FOUND; }
  let v: Int = c.ns_mem_mib[id];
  return v;
}

/// Pods admitted in namespace `id`, or K8S_NOT_FOUND for an unknown id.
pub fn namespace_used_pods(c: &K8sCluster, id: Int) -> Int {
  if id < 0 || id >= c.ns_off.len() - 1 { return K8S_NOT_FOUND; }
  var k = 0;
  var i = 0;
  while i < c.pod_ns.len() {
    let n: Int = c.pod_ns[i];
    if n == id { k = k + 1; }
    i = i + 1;
  }
  return k;
}

/// CPU millicores requested by pods in namespace `id`, or K8S_NOT_FOUND.
pub fn namespace_used_cpu(c: &K8sCluster, id: Int) -> Int {
  if id < 0 || id >= c.ns_off.len() - 1 { return K8S_NOT_FOUND; }
  var k = 0;
  var i = 0;
  while i < c.pod_ns.len() {
    let n: Int = c.pod_ns[i];
    if n == id {
      let v: Int = c.pod_cpu[i];
      k = k + v;
    }
    i = i + 1;
  }
  return k;
}

/// Memory MiB requested by pods in namespace `id`, or K8S_NOT_FOUND.
pub fn namespace_used_mem(c: &K8sCluster, id: Int) -> Int {
  if id < 0 || id >= c.ns_off.len() - 1 { return K8S_NOT_FOUND; }
  var k = 0;
  var i = 0;
  while i < c.pod_ns.len() {
    let n: Int = c.pod_ns[i];
    if n == id {
      let v: Int = c.pod_mem[i];
      k = k + v;
    }
    i = i + 1;
  }
  return k;
}

/// ConfigMaps in namespace `id`, or K8S_NOT_FOUND.
pub fn namespace_used_configmaps(c: &K8sCluster, id: Int) -> Int {
  if id < 0 || id >= c.ns_off.len() - 1 { return K8S_NOT_FOUND; }
  var k = 0;
  var i = 0;
  while i < c.cm_ns.len() {
    let n: Int = c.cm_ns[i];
    if n == id { k = k + 1; }
    i = i + 1;
  }
  return k;
}

/// Secrets in namespace `id`, or K8S_NOT_FOUND.
pub fn namespace_used_secrets(c: &K8sCluster, id: Int) -> Int {
  if id < 0 || id >= c.ns_off.len() - 1 { return K8S_NOT_FOUND; }
  var k = 0;
  var i = 0;
  while i < c.sec_ns.len() {
    let n: Int = c.sec_ns[i];
    if n == id { k = k + 1; }
    i = i + 1;
  }
  return k;
}

/// Pre-flight admission of one pod with `cpu` millicores and `mem` MiB into
/// namespace `ns`: Ok(pods after admission) or the exact quota error.
/// Errors: "namespace: unknown namespace", "quota: resources must be >= 0",
/// "quota: pod limit exceeded", "quota: cpu quota exceeded",
/// "quota: memory quota exceeded". Complexity: O(pods).
pub fn namespace_admit_pod(c: &K8sCluster, ns: Int, cpu: Int, mem: Int) -> Result[Int, Str] {
  if ns < 0 || ns >= c.ns_off.len() - 1 { return _k_err_int("namespace: unknown namespace"); }
  if cpu < 0 || mem < 0 { return _k_err_int("quota: resources must be >= 0"); }
  let maxp: Int = c.ns_max_pods[ns];
  let usedp = namespace_used_pods(c, ns);
  if maxp > 0 && usedp + 1 > maxp { return _k_err_int("quota: pod limit exceeded"); }
  let cpuq: Int = c.ns_cpu_milli[ns];
  if cpuq > 0 && namespace_used_cpu(c, ns) + cpu > cpuq { return _k_err_int("quota: cpu quota exceeded"); }
  let memq: Int = c.ns_mem_mib[ns];
  if memq > 0 && namespace_used_mem(c, ns) + mem > memq { return _k_err_int("quota: memory quota exceeded"); }
  return _k_ok_int(usedp + 1);
}

// ---------------------------------------------------------------------------
// Pods and the phase machine
// ---------------------------------------------------------------------------

/// Create a pod in PENDING with no owner. The name is unique per namespace
/// and the pod is admitted against the namespace quota.
/// Errors: namespace, name, cpu/memory negatives, duplicate, object limit and
/// the quota errors from namespace_admit_pod.
pub fn pod_create(c: &mut K8sCluster, ns: Int, name: Str, cpu: Int, mem: Int) -> Result[Int, Str] {
  if ns < 0 || ns >= c.ns_off.len() - 1 { return _k_err_int("pod: unknown namespace"); }
  if string.str_len(name) == 0 { return _k_err_int("pod: name must not be empty"); }
  if !k8s_name_valid(name) { return _k_err_int("pod: invalid name"); }
  if cpu < 0 { return _k_err_int("pod: cpu must be >= 0"); }
  if mem < 0 { return _k_err_int("pod: memory must be >= 0"); }
  if _k_obj_find(c.pod_data, &c.pod_off, &c.pod_ns, ns, name) >= 0 { return _k_err_int("pod: duplicate pod"); }
  if c.pod_off.len() - 1 >= K8S_MAX_OBJECTS { return _k_err_int("pod: object limit exceeded"); }
  match namespace_admit_pod(c, ns, cpu, mem) {
    Ok(_) => {},
    Err(emsg) => { return _k_err_int(emsg); },
  }
  let id = c.pod_off.len() - 1;
  c.pod_data = _k_blob_append(c.pod_data, &mut c.pod_off, name);
  c.pod_ns.push(ns);
  c.pod_phase.push(K8S_PHASE_PENDING);
  c.pod_cpu.push(cpu);
  c.pod_mem.push(mem);
  c.pod_owner.push(K8S_NOT_FOUND);
  c.pod_moves.push(0);
  return _k_ok_int(id);
}

/// Number of pods. Complexity: O(1).
pub fn pod_count(c: &K8sCluster) -> Int {
  return c.pod_off.len() - 1;
}

/// Pod id of (`ns`, `name`), or K8S_NOT_FOUND. Names are namespace-scoped.
pub fn pod_index(c: &K8sCluster, ns: Int, name: Str) -> Int {
  return _k_obj_find(c.pod_data, &c.pod_off, &c.pod_ns, ns, name);
}

/// Pod name, or "" when the id is out of range.
pub fn pod_name(c: &K8sCluster, id: Int) -> Str {
  return _k_entry(c.pod_data, &c.pod_off, id);
}

/// Namespace id of pod `id`, or K8S_NOT_FOUND.
pub fn pod_namespace(c: &K8sCluster, id: Int) -> Int {
  if id < 0 || id >= c.pod_ns.len() { return K8S_NOT_FOUND; }
  let v: Int = c.pod_ns[id];
  return v;
}

/// Phase code of pod `id`, or K8S_NOT_FOUND.
pub fn pod_phase(c: &K8sCluster, id: Int) -> Int {
  if id < 0 || id >= c.pod_phase.len() { return K8S_NOT_FOUND; }
  let v: Int = c.pod_phase[id];
  return v;
}

/// Human-readable phase name ("pending", "running", "succeeded", "failed",
/// "unknown").
pub fn pod_phase_name(phase: Int) -> Str {
  if phase == K8S_PHASE_PENDING { return "pending"; }
  if phase == K8S_PHASE_RUNNING { return "running"; }
  if phase == K8S_PHASE_SUCCEEDED { return "succeeded"; }
  if phase == K8S_PHASE_FAILED { return "failed"; }
  if phase == K8S_PHASE_UNKNOWN { return "unknown"; }
  return "unknown";
}

/// CPU millicores requested by pod `id`, or K8S_NOT_FOUND.
pub fn pod_cpu(c: &K8sCluster, id: Int) -> Int {
  if id < 0 || id >= c.pod_cpu.len() { return K8S_NOT_FOUND; }
  let v: Int = c.pod_cpu[id];
  return v;
}

/// Memory MiB requested by pod `id`, or K8S_NOT_FOUND.
pub fn pod_mem(c: &K8sCluster, id: Int) -> Int {
  if id < 0 || id >= c.pod_mem.len() { return K8S_NOT_FOUND; }
  let v: Int = c.pod_mem[id];
  return v;
}

/// Successful phase transitions of pod `id`, or K8S_NOT_FOUND.
pub fn pod_move_count(c: &K8sCluster, id: Int) -> Int {
  if id < 0 || id >= c.pod_moves.len() { return K8S_NOT_FOUND; }
  let v: Int = c.pod_moves[id];
  return v;
}

/// Owning deployment id of pod `id`, or K8S_NOT_FOUND when unowned/unknown.
pub fn pod_owner(c: &K8sCluster, id: Int) -> Int {
  if id < 0 || id >= c.pod_owner.len() { return K8S_NOT_FOUND; }
  let v: Int = c.pod_owner[id];
  return v;
}

/// True when the phase-level transition from -> to is legal:
/// PENDING -> RUNNING | FAILED | UNKNOWN; RUNNING -> SUCCEEDED | FAILED |
/// UNKNOWN; UNKNOWN -> PENDING | RUNNING | SUCCEEDED | FAILED; SUCCEEDED and
/// FAILED are terminal. Exactly ten legal pairs. Complexity: O(1).
pub fn pod_can_transition(from: Int, to: Int) -> Bool {
  if from == K8S_PHASE_PENDING {
    if to == K8S_PHASE_RUNNING { return true; }
    if to == K8S_PHASE_FAILED { return true; }
    return to == K8S_PHASE_UNKNOWN;
  }
  if from == K8S_PHASE_RUNNING {
    if to == K8S_PHASE_SUCCEEDED { return true; }
    if to == K8S_PHASE_FAILED { return true; }
    return to == K8S_PHASE_UNKNOWN;
  }
  if from == K8S_PHASE_UNKNOWN {
    if to == K8S_PHASE_PENDING { return true; }
    if to == K8S_PHASE_RUNNING { return true; }
    if to == K8S_PHASE_SUCCEEDED { return true; }
    return to == K8S_PHASE_FAILED;
  }
  return false;
}

/// True when `phase` is terminal (SUCCEEDED or FAILED). Complexity: O(1).
pub fn pod_is_terminal(phase: Int) -> Bool {
  if phase == K8S_PHASE_SUCCEEDED { return true; }
  return phase == K8S_PHASE_FAILED;
}

/// Apply one phase transition to pod `id`, incrementing its move counter.
/// Returns the new phase. Errors: "pod: unknown pod", "pod: invalid phase",
/// "pod: phase unchanged", "pod: invalid phase transition". Every error
/// leaves the pod untouched.
pub fn pod_transition(c: &mut K8sCluster, id: Int, to: Int) -> Result[Int, Str] {
  if id < 0 || id >= c.pod_phase.len() { return _k_err_int("pod: unknown pod"); }
  if to < 0 || to > K8S_PHASE_UNKNOWN { return _k_err_int("pod: invalid phase"); }
  let cur: Int = c.pod_phase[id];
  if to == cur { return _k_err_int("pod: phase unchanged"); }
  if !pod_can_transition(cur, to) { return _k_err_int("pod: invalid phase transition"); }
  c.pod_phase[id] = to;
  let m: Int = c.pod_moves[id];
  c.pod_moves[id] = m + 1;
  return _k_ok_int(to);
}

/// Add a label to pod `id`. Errors: "pod: unknown pod" plus the
/// xiom.k8s.selector label errors.
pub fn pod_label_add(c: &mut K8sCluster, id: Int, key: Str, val: Str) -> Result[Int, Str] {
  if id < 0 || id >= c.pod_off.len() - 1 { return _k_err_int("pod: unknown pod"); }
  match selector.label_owned_add(c.pod_lbl_data, &mut c.pod_lbl_off, &mut c.pod_lbl_owner, id, key, val) {
    Ok(nd) => { c.pod_lbl_data = nd; },
    Err(emsg) => { return _k_err_int(emsg); },
  }
  return _k_ok_int(selector.label_owned_count(&c.pod_lbl_off, &c.pod_lbl_owner, id));
}

/// Label value of pod `id`, or "" when absent/unknown.
pub fn pod_label_value(c: &K8sCluster, id: Int, key: Str) -> Str {
  if id < 0 || id >= c.pod_off.len() - 1 { return ""; }
  return selector.label_owned_value(c.pod_lbl_data, &c.pod_lbl_off, &c.pod_lbl_owner, id, key);
}

/// Number of labels on pod `id`, or K8S_NOT_FOUND.
pub fn pod_label_count(c: &K8sCluster, id: Int) -> Int {
  if id < 0 || id >= c.pod_off.len() - 1 { return K8S_NOT_FOUND; }
  return selector.label_owned_count(&c.pod_lbl_off, &c.pod_lbl_owner, id);
}

/// Labels of pod `id` rendered as "k=v,k2=v2", or "" when unknown.
pub fn pod_labels_render(c: &K8sCluster, id: Int) -> Str {
  if id < 0 || id >= c.pod_off.len() - 1 { return ""; }
  return selector.label_owned_render(c.pod_lbl_data, &c.pod_lbl_off, &c.pod_lbl_owner, id);
}

/// True when pod `id` carries every entry of `sel` (empty selector matches).
pub fn pod_labels_match_selector(c: &K8sCluster, id: Int, sel: &LabelParts) -> Bool {
  if id < 0 || id >= c.pod_off.len() - 1 { return false; }
  let cnt = selector.label_parts_count(sel);
  var i = 0;
  while i < cnt {
    let e = selector.label_parts_entry(sel, i);
    let key = selector.label_entry_key(e);
    let want = selector.label_entry_value(e);
    if !selector.label_owned_has(c.pod_lbl_data, &c.pod_lbl_off, &c.pod_lbl_owner, id, key) { return false; }
    let got = selector.label_owned_value(c.pod_lbl_data, &c.pod_lbl_off, &c.pod_lbl_owner, id, key);
    if string.str_compare(got, want) != 0 { return false; }
    i = i + 1;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Deployments: replicas, strategy, revision history, rolling math
// ---------------------------------------------------------------------------

// Current image of deployment `id` (the last image entry it owns), or "".
fn _k_img_current(c: &K8sCluster, id: Int) -> Str {
  var out = "";
  let cnt = c.dep_img_off.len() - 1;
  if c.dep_img_owner.len() != cnt { return out; }
  var i = 0;
  while i < cnt {
    let o: Int = c.dep_img_owner[i];
    if o == id {
      let a: Int = c.dep_img_off[i];
      let b: Int = c.dep_img_off[i + 1];
      out = string.str_slice(c.dep_img_data, a, b);
    }
    i = i + 1;
  }
  return out;
}

// Revision-history records owned by `id`.
fn _k_hist_count(c: &K8sCluster, id: Int) -> Int {
  let cnt = c.dep_hist_rev.len();
  if c.dep_hist_owner.len() != cnt { return 0; }
  var k = 0;
  var i = 0;
  while i < cnt {
    let o: Int = c.dep_hist_owner[i];
    if o == id { k = k + 1; }
    i = i + 1;
  }
  return k;
}

// Global index of the `ord`-th history record owned by `id`, or -1.
fn _k_hist_global(c: &K8sCluster, id: Int, ord: Int) -> Int {
  let cnt = c.dep_hist_rev.len();
  if c.dep_hist_owner.len() != cnt { return -1; }
  var seen = 0;
  var i = 0;
  while i < cnt {
    let o: Int = c.dep_hist_owner[i];
    if o == id {
      if seen == ord { return i; }
      seen = seen + 1;
    }
    i = i + 1;
  }
  return -1;
}

/// Create a deployment with the default strategy (maxSurge 25%,
/// maxUnavailable 25%) at revision 1. Returns the dense deployment id.
/// Errors: "deployment: unknown namespace", name errors,
/// "deployment: image must not be empty", "deployment: replicas must be >= 0",
/// "deployment: duplicate deployment", "deployment: object limit exceeded".
pub fn deployment_create(c: &mut K8sCluster, ns: Int, name: Str, image: Str, replicas: Int) -> Result[Int, Str] {
  if ns < 0 || ns >= c.ns_off.len() - 1 { return _k_err_int("deployment: unknown namespace"); }
  if string.str_len(name) == 0 { return _k_err_int("deployment: name must not be empty"); }
  if !k8s_name_valid(name) { return _k_err_int("deployment: invalid name"); }
  if string.str_len(image) == 0 { return _k_err_int("deployment: image must not be empty"); }
  if replicas < 0 { return _k_err_int("deployment: replicas must be >= 0"); }
  if _k_obj_find(c.dep_data, &c.dep_off, &c.dep_ns, ns, name) >= 0 { return _k_err_int("deployment: duplicate deployment"); }
  if c.dep_off.len() - 1 >= K8S_MAX_OBJECTS { return _k_err_int("deployment: object limit exceeded"); }
  let id = c.dep_off.len() - 1;
  c.dep_data = _k_blob_append(c.dep_data, &mut c.dep_off, name);
  c.dep_ns.push(ns);
  c.dep_replicas.push(replicas);
  c.dep_surge.push(rolling.K8S_ROLLING_DEFAULT_SURGE_PCT);
  c.dep_surge_pct.push(1);
  c.dep_unavail.push(rolling.K8S_ROLLING_DEFAULT_UNAVAILABLE_PCT);
  c.dep_unavail_pct.push(1);
  c.dep_revision.push(1);
  c.dep_img_data = _k_owner_append(c.dep_img_data, &mut c.dep_img_off, &mut c.dep_img_owner, id, image);
  return _k_ok_int(id);
}

/// Number of deployments. Complexity: O(1).
pub fn deployment_count(c: &K8sCluster) -> Int {
  return c.dep_off.len() - 1;
}

/// Deployment id of (`ns`, `name`), or K8S_NOT_FOUND.
pub fn deployment_index(c: &K8sCluster, ns: Int, name: Str) -> Int {
  return _k_obj_find(c.dep_data, &c.dep_off, &c.dep_ns, ns, name);
}

/// Deployment name, or "" when the id is out of range.
pub fn deployment_name(c: &K8sCluster, id: Int) -> Str {
  return _k_entry(c.dep_data, &c.dep_off, id);
}

/// Namespace id of deployment `id`, or K8S_NOT_FOUND.
pub fn deployment_namespace(c: &K8sCluster, id: Int) -> Int {
  if id < 0 || id >= c.dep_ns.len() { return K8S_NOT_FOUND; }
  let v: Int = c.dep_ns[id];
  return v;
}

/// Current image of deployment `id`, or "".
pub fn deployment_image(c: &K8sCluster, id: Int) -> Str {
  if id < 0 || id >= c.dep_off.len() - 1 { return ""; }
  return _k_img_current(c, id);
}

/// Desired replica count of deployment `id`, or K8S_NOT_FOUND.
pub fn deployment_replicas(c: &K8sCluster, id: Int) -> Int {
  if id < 0 || id >= c.dep_replicas.len() { return K8S_NOT_FOUND; }
  let v: Int = c.dep_replicas[id];
  return v;
}

/// Current revision of deployment `id`, or K8S_NOT_FOUND.
pub fn deployment_revision(c: &K8sCluster, id: Int) -> Int {
  if id < 0 || id >= c.dep_revision.len() { return K8S_NOT_FOUND; }
  let v: Int = c.dep_revision[id];
  return v;
}

/// Raw maxSurge term of deployment `id`, or K8S_NOT_FOUND.
pub fn deployment_surge_amount(c: &K8sCluster, id: Int) -> Int {
  if id < 0 || id >= c.dep_surge.len() { return K8S_NOT_FOUND; }
  let v: Int = c.dep_surge[id];
  return v;
}

/// True when maxSurge is a percentage for deployment `id`.
pub fn deployment_surge_is_percent(c: &K8sCluster, id: Int) -> Bool {
  if id < 0 || id >= c.dep_surge_pct.len() { return false; }
  let v: Int = c.dep_surge_pct[id];
  return v == 1;
}

/// Raw maxUnavailable term of deployment `id`, or K8S_NOT_FOUND.
pub fn deployment_unavailable_amount(c: &K8sCluster, id: Int) -> Int {
  if id < 0 || id >= c.dep_unavail.len() { return K8S_NOT_FOUND; }
  let v: Int = c.dep_unavail[id];
  return v;
}

/// True when maxUnavailable is a percentage for deployment `id`.
pub fn deployment_unavailable_is_percent(c: &K8sCluster, id: Int) -> Bool {
  if id < 0 || id >= c.dep_unavail_pct.len() { return false; }
  let v: Int = c.dep_unavail_pct[id];
  return v == 1;
}

/// Set the rolling-update strategy. Percent flags are 0 (absolute) or 1
/// (percentage). Returns 0 on success.
/// Errors: "deployment: unknown deployment", "deployment: strategy amount
/// must be >= 0", "deployment: strategy percent must be in 0..100",
/// "deployment: strategy percent flag must be 0 or 1", "deployment: maxSurge
/// and maxUnavailable cannot both be zero".
pub fn deployment_set_strategy(c: &mut K8sCluster, id: Int, surge: Int, surge_pct: Int, unavail: Int, unavail_pct: Int) -> Result[Int, Str] {
  if id < 0 || id >= c.dep_replicas.len() { return _k_err_int("deployment: unknown deployment"); }
  if surge < 0 || unavail < 0 { return _k_err_int("deployment: strategy amount must be >= 0"); }
  if surge_pct != 0 && surge_pct != 1 { return _k_err_int("deployment: strategy percent flag must be 0 or 1"); }
  if unavail_pct != 0 && unavail_pct != 1 { return _k_err_int("deployment: strategy percent flag must be 0 or 1"); }
  if surge_pct == 1 && surge > 100 { return _k_err_int("deployment: strategy percent must be in 0..100"); }
  if unavail_pct == 1 && unavail > 100 { return _k_err_int("deployment: strategy percent must be in 0..100"); }
  if surge == 0 && unavail == 0 { return _k_err_int("deployment: maxSurge and maxUnavailable cannot both be zero"); }
  c.dep_surge[id] = surge;
  c.dep_surge_pct[id] = surge_pct;
  c.dep_unavail[id] = unavail;
  c.dep_unavail_pct[id] = unavail_pct;
  return _k_ok_int(0);
}

/// Set the desired replica count. Returns the new count.
/// Errors: "deployment: unknown deployment", "deployment: replicas must be
/// >= 0".
pub fn deployment_scale(c: &mut K8sCluster, id: Int, replicas: Int) -> Result[Int, Str] {
  if id < 0 || id >= c.dep_replicas.len() { return _k_err_int("deployment: unknown deployment"); }
  if replicas < 0 { return _k_err_int("deployment: replicas must be >= 0"); }
  c.dep_replicas[id] = replicas;
  return _k_ok_int(replicas);
}

/// Resolved maxSurge count for deployment `id` (percentages round up), or
/// K8S_NOT_FOUND.
pub fn deployment_surge_count(c: &K8sCluster, id: Int) -> Int {
  if id < 0 || id >= c.dep_replicas.len() { return K8S_NOT_FOUND; }
  let reps: Int = c.dep_replicas[id];
  let amt: Int = c.dep_surge[id];
  return rolling.rolling_surge(reps, amt, deployment_surge_is_percent(c, id));
}

/// Resolved maxUnavailable count for deployment `id` (percentages round
/// down), or K8S_NOT_FOUND.
pub fn deployment_unavailable_count(c: &K8sCluster, id: Int) -> Int {
  if id < 0 || id >= c.dep_replicas.len() { return K8S_NOT_FOUND; }
  let reps: Int = c.dep_replicas[id];
  let amt: Int = c.dep_unavail[id];
  return rolling.rolling_unavailable(reps, amt, deployment_unavailable_is_percent(c, id));
}

/// Number of rolling-update rounds for deployment `id`, or K8S_NOT_FOUND.
pub fn deployment_rolling_rounds(c: &K8sCluster, id: Int) -> Int {
  if id < 0 || id >= c.dep_replicas.len() { return K8S_NOT_FOUND; }
  let reps: Int = c.dep_replicas[id];
  return rolling.rolling_rounds(reps, deployment_surge_count(c, id), deployment_unavailable_count(c, id));
}

/// New-replica count after each rolling-update round for deployment `id`.
pub fn deployment_rolling_schedule(c: &K8sCluster, id: Int) -> Result[Vec[Int], Str] {
  if id < 0 || id >= c.dep_replicas.len() { return _k_err_vec("deployment: unknown deployment"); }
  let reps: Int = c.dep_replicas[id];
  return rolling.rolling_schedule(reps, deployment_surge_count(c, id), deployment_unavailable_count(c, id));
}

/// Change the deployment image: the current revision/image is pushed onto
/// the revision history and the revision increments. Returns the new
/// revision. Errors: "deployment: unknown deployment", "deployment: image
/// must not be empty", "deployment: image unchanged", "deployment: revision
/// history limit reached".
pub fn deployment_set_image(c: &mut K8sCluster, id: Int, image: Str) -> Result[Int, Str] {
  if id < 0 || id >= c.dep_replicas.len() { return _k_err_int("deployment: unknown deployment"); }
  if string.str_len(image) == 0 { return _k_err_int("deployment: image must not be empty"); }
  let cur = _k_img_current(c, id);
  if string.str_compare(cur, image) == 0 { return _k_err_int("deployment: image unchanged"); }
  if _k_hist_count(c, id) >= K8S_MAX_REVISIONS { return _k_err_int("deployment: revision history limit reached"); }
  let rev: Int = c.dep_revision[id];
  c.dep_hist_rev.push(rev);
  c.dep_hist_img_data = _k_owner_append(c.dep_hist_img_data, &mut c.dep_hist_img_off, &mut c.dep_hist_owner, id, cur);
  c.dep_img_data = _k_owner_append(c.dep_img_data, &mut c.dep_img_off, &mut c.dep_img_owner, id, image);
  c.dep_revision[id] = rev + 1;
  return _k_ok_int(rev + 1);
}

/// Number of revision-history records retained for deployment `id`.
pub fn deployment_history_count(c: &K8sCluster, id: Int) -> Int {
  if id < 0 || id >= c.dep_off.len() - 1 { return K8S_NOT_FOUND; }
  return _k_hist_count(c, id);
}

/// Revision stored in history record `i` of deployment `id`, or K8S_NOT_FOUND.
pub fn deployment_history_revision_at(c: &K8sCluster, id: Int, i: Int) -> Int {
  if id < 0 || id >= c.dep_off.len() - 1 { return K8S_NOT_FOUND; }
  let g = _k_hist_global(c, id, i);
  if g < 0 { return K8S_NOT_FOUND; }
  let v: Int = c.dep_hist_rev[g];
  return v;
}

/// Image stored in history record `i` of deployment `id`, or "".
pub fn deployment_history_image_at(c: &K8sCluster, id: Int, i: Int) -> Str {
  if id < 0 || id >= c.dep_off.len() - 1 { return ""; }
  let g = _k_hist_global(c, id, i);
  if g < 0 { return ""; }
  if c.dep_hist_img_off.len() - 1 != c.dep_hist_rev.len() { return ""; }
  return _k_entry(c.dep_hist_img_data, &c.dep_hist_img_off, g);
}

/// Roll deployment `id` back to `target` revision, or to the most recent
/// history record when `target` < 0. The state being replaced is appended to
/// the history and the revision increments monotonically, so rollback never
/// rewrites history. Returns the new revision.
/// Errors: "deployment: unknown deployment", "deployment: no revision
/// history", "deployment: revision not found", "deployment: revision history
/// limit reached".
pub fn deployment_rollback(c: &mut K8sCluster, id: Int, target: Int) -> Result[Int, Str] {
  if id < 0 || id >= c.dep_replicas.len() { return _k_err_int("deployment: unknown deployment"); }
  let cnt = _k_hist_count(c, id);
  if cnt == 0 { return _k_err_int("deployment: no revision history"); }
  var found = -1;
  var i = 0;
  while i < c.dep_hist_rev.len() {
    let o: Int = c.dep_hist_owner[i];
    if o == id {
      if target < 0 {
        found = i;
      } else {
        let r: Int = c.dep_hist_rev[i];
        if r == target { found = i; }
      }
    }
    i = i + 1;
  }
  if found < 0 { return _k_err_int("deployment: revision not found"); }
  if cnt >= K8S_MAX_REVISIONS { return _k_err_int("deployment: revision history limit reached"); }
  let hist_r: Int = c.dep_hist_rev[found];
  if c.dep_hist_img_off.len() - 1 != c.dep_hist_rev.len() { return _k_err_int("deployment: revision history limit reached"); }
  let hist_img = _k_entry(c.dep_hist_img_data, &c.dep_hist_img_off, found);
  let cur_rev: Int = c.dep_revision[id];
  let cur_img = _k_img_current(c, id);
  c.dep_hist_rev.push(cur_rev);
  c.dep_hist_img_data = _k_owner_append(c.dep_hist_img_data, &mut c.dep_hist_img_off, &mut c.dep_hist_owner, id, cur_img);
  c.dep_img_data = _k_owner_append(c.dep_img_data, &mut c.dep_img_off, &mut c.dep_img_owner, id, hist_img);
  c.dep_revision[id] = cur_rev + 1;
  return _k_ok_int(cur_rev + 1);
}

/// Adopt pod `pod` into deployment `id` (same namespace, unowned). Returns
/// the deployment id. Errors: "deployment: unknown deployment",
/// "pod: unknown pod", "deployment: pod namespace mismatch",
/// "deployment: pod already owned".
pub fn deployment_adopt_pod(c: &mut K8sCluster, id: Int, pod: Int) -> Result[Int, Str] {
  if id < 0 || id >= c.dep_replicas.len() { return _k_err_int("deployment: unknown deployment"); }
  if pod < 0 || pod >= c.pod_ns.len() { return _k_err_int("pod: unknown pod"); }
  let pns: Int = c.pod_ns[pod];
  let dns: Int = c.dep_ns[id];
  if pns != dns { return _k_err_int("deployment: pod namespace mismatch"); }
  let own: Int = c.pod_owner[pod];
  if own >= 0 { return _k_err_int("deployment: pod already owned"); }
  c.pod_owner[pod] = id;
  return _k_ok_int(id);
}

/// Pods owned by deployment `id`, or K8S_NOT_FOUND.
pub fn deployment_pod_count(c: &K8sCluster, id: Int) -> Int {
  if id < 0 || id >= c.dep_replicas.len() { return K8S_NOT_FOUND; }
  var k = 0;
  var i = 0;
  while i < c.pod_owner.len() {
    let o: Int = c.pod_owner[i];
    if o == id { k = k + 1; }
    i = i + 1;
  }
  return k;
}

// ---------------------------------------------------------------------------
// Services and endpoints
// ---------------------------------------------------------------------------

/// Create a service. Returns the dense service id.
/// Errors: "service: unknown namespace", name errors,
/// "service: invalid service type", "service: port must be in 1..65535",
/// "service: target port must be in 1..65535", "service: duplicate service",
/// "service: object limit exceeded".
pub fn service_create(c: &mut K8sCluster, ns: Int, name: Str, svc_type: Int, port: Int, target: Int) -> Result[Int, Str] {
  if ns < 0 || ns >= c.ns_off.len() - 1 { return _k_err_int("service: unknown namespace"); }
  if string.str_len(name) == 0 { return _k_err_int("service: name must not be empty"); }
  if !k8s_name_valid(name) { return _k_err_int("service: invalid name"); }
  if svc_type < K8S_SVC_CLUSTER_IP || svc_type > K8S_SVC_LOAD_BALANCER { return _k_err_int("service: invalid service type"); }
  if port < 1 || port > K8S_MAX_PORT { return _k_err_int("service: port must be in 1..65535"); }
  if target < 1 || target > K8S_MAX_PORT { return _k_err_int("service: target port must be in 1..65535"); }
  if _k_obj_find(c.svc_data, &c.svc_off, &c.svc_ns, ns, name) >= 0 { return _k_err_int("service: duplicate service"); }
  if c.svc_off.len() - 1 >= K8S_MAX_OBJECTS { return _k_err_int("service: object limit exceeded"); }
  let id = c.svc_off.len() - 1;
  c.svc_data = _k_blob_append(c.svc_data, &mut c.svc_off, name);
  c.svc_ns.push(ns);
  c.svc_type.push(svc_type);
  c.svc_port.push(port);
  c.svc_target.push(target);
  return _k_ok_int(id);
}

/// Number of services. Complexity: O(1).
pub fn service_count(c: &K8sCluster) -> Int {
  return c.svc_off.len() - 1;
}

/// Service id of (`ns`, `name`), or K8S_NOT_FOUND.
pub fn service_index(c: &K8sCluster, ns: Int, name: Str) -> Int {
  return _k_obj_find(c.svc_data, &c.svc_off, &c.svc_ns, ns, name);
}

/// Service name, or "" when the id is out of range.
pub fn service_name(c: &K8sCluster, id: Int) -> Str {
  return _k_entry(c.svc_data, &c.svc_off, id);
}

/// Namespace id of service `id`, or K8S_NOT_FOUND.
pub fn service_namespace(c: &K8sCluster, id: Int) -> Int {
  if id < 0 || id >= c.svc_ns.len() { return K8S_NOT_FOUND; }
  let v: Int = c.svc_ns[id];
  return v;
}

/// Service type code of service `id`, or K8S_NOT_FOUND.
pub fn service_type(c: &K8sCluster, id: Int) -> Int {
  if id < 0 || id >= c.svc_type.len() { return K8S_NOT_FOUND; }
  let v: Int = c.svc_type[id];
  return v;
}

/// Human-readable service type name ("ClusterIP", "NodePort",
/// "LoadBalancer", "unknown").
pub fn service_type_name(t: Int) -> Str {
  if t == K8S_SVC_CLUSTER_IP { return "ClusterIP"; }
  if t == K8S_SVC_NODE_PORT { return "NodePort"; }
  if t == K8S_SVC_LOAD_BALANCER { return "LoadBalancer"; }
  return "unknown";
}

/// Exposed port of service `id`, or K8S_NOT_FOUND.
pub fn service_port(c: &K8sCluster, id: Int) -> Int {
  if id < 0 || id >= c.svc_port.len() { return K8S_NOT_FOUND; }
  let v: Int = c.svc_port[id];
  return v;
}

/// Backend target port of service `id`, or K8S_NOT_FOUND.
pub fn service_target_port(c: &K8sCluster, id: Int) -> Int {
  if id < 0 || id >= c.svc_target.len() { return K8S_NOT_FOUND; }
  let v: Int = c.svc_target[id];
  return v;
}

/// Add one selector entry to service `id`. Errors: "service: unknown
/// service" plus the xiom.k8s.selector label errors.
pub fn service_selector_add(c: &mut K8sCluster, id: Int, key: Str, val: Str) -> Result[Int, Str] {
  if id < 0 || id >= c.svc_off.len() - 1 { return _k_err_int("service: unknown service"); }
  match selector.label_owned_add(c.svc_sel_data, &mut c.svc_sel_off, &mut c.svc_sel_owner, id, key, val) {
    Ok(nd) => { c.svc_sel_data = nd; },
    Err(emsg) => { return _k_err_int(emsg); },
  }
  return _k_ok_int(selector.label_owned_count(&c.svc_sel_off, &c.svc_sel_owner, id));
}

/// Number of selector entries on service `id`, or K8S_NOT_FOUND.
pub fn service_selector_count(c: &K8sCluster, id: Int) -> Int {
  if id < 0 || id >= c.svc_off.len() - 1 { return K8S_NOT_FOUND; }
  return selector.label_owned_count(&c.svc_sel_off, &c.svc_sel_owner, id);
}

/// Selector entries of service `id` rendered as "k=v,k2=v2".
pub fn service_selector_render(c: &K8sCluster, id: Int) -> Str {
  if id < 0 || id >= c.svc_off.len() - 1 { return ""; }
  return selector.label_owned_render(c.svc_sel_data, &c.svc_sel_off, &c.svc_sel_owner, id);
}

/// Ready endpoints of service `id`: pods in the service namespace that are
/// RUNNING and carry every selector entry, in dense pod-id order.
/// Errors: "service: unknown service", "service: selector is empty".
pub fn service_endpoints(c: &K8sCluster, id: Int) -> Result[Vec[Int], Str] {
  if id < 0 || id >= c.svc_off.len() - 1 { return _k_err_vec("service: unknown service"); }
  if service_selector_count(c, id) == 0 { return _k_err_vec("service: selector is empty"); }
  let ns: Int = c.svc_ns[id];
  var out = Vec[Int].new();
  var i = 0;
  while i < c.pod_phase.len() {
    let pns: Int = c.pod_ns[i];
    let ph: Int = c.pod_phase[i];
    if pns == ns && ph == K8S_PHASE_RUNNING {
      if selector.label_owned_matches(c.pod_lbl_data, &c.pod_lbl_off, &c.pod_lbl_owner, i, c.svc_sel_data, &c.svc_sel_off, &c.svc_sel_owner, id) {
        out.push(i);
      }
    }
    i = i + 1;
  }
  return _k_ok_vec(out);
}

/// Number of ready endpoints of service `id`, or K8S_NOT_FOUND when the
/// service or its selector is invalid.
pub fn service_endpoint_count(c: &K8sCluster, id: Int) -> Int {
  match service_endpoints(c, id) {
    Ok(v) => { return v.len(); },
    Err(_) => { return K8S_NOT_FOUND; },
  }
  return K8S_NOT_FOUND;
}

/// Endpoint pod names of service `id` joined with ",", or "" when the
/// service/selector is invalid or nothing matches.
pub fn service_endpoint_names(c: &K8sCluster, id: Int) -> Str {
  match service_endpoints(c, id) {
    Ok(v) => {
      var out = "";
      var i = 0;
      while i < v.len() {
        let p: Int = v[i];
        if i > 0 { out = out + ","; }
        out = out + _k_entry(c.pod_data, &c.pod_off, p);
        i = i + 1;
      }
      return out;
    },
    Err(_) => { return ""; },
  }
  return "";
}

// ---------------------------------------------------------------------------
// Ingress
// ---------------------------------------------------------------------------

// Total number of ingress rules (0 on parallel-array drift).
fn _k_rule_total(c: &K8sCluster) -> Int {
  let n = c.ing_rule_host_off.len() - 1;
  if c.ing_rule_host_owner.len() != n { return 0; }
  if c.ing_rule_path_off.len() - 1 != n { return 0; }
  if c.ing_rule_svc_off.len() - 1 != n { return 0; }
  if c.ing_rule_port.len() != n { return 0; }
  return n;
}

// Number of rules owned by ingress `id`.
fn _k_rule_count(c: &K8sCluster, id: Int) -> Int {
  let cnt = _k_rule_total(c);
  var k = 0;
  var i = 0;
  while i < cnt {
    let o: Int = c.ing_rule_host_owner[i];
    if o == id { k = k + 1; }
    i = i + 1;
  }
  return k;
}

// Global index of the `ord`-th rule owned by ingress `id`, or -1.
fn _k_rule_global(c: &K8sCluster, id: Int, ord: Int) -> Int {
  let cnt = _k_rule_total(c);
  var seen = 0;
  var i = 0;
  while i < cnt {
    let o: Int = c.ing_rule_host_owner[i];
    if o == id {
      if seen == ord { return i; }
      seen = seen + 1;
    }
    i = i + 1;
  }
  return -1;
}

/// Create an ingress object (no rules). Returns the dense ingress id.
/// Errors: namespace, name, duplicate and object-limit errors.
pub fn ingress_create(c: &mut K8sCluster, ns: Int, name: Str) -> Result[Int, Str] {
  if ns < 0 || ns >= c.ns_off.len() - 1 { return _k_err_int("ingress: unknown namespace"); }
  if string.str_len(name) == 0 { return _k_err_int("ingress: name must not be empty"); }
  if !k8s_name_valid(name) { return _k_err_int("ingress: invalid name"); }
  if _k_obj_find(c.ing_data, &c.ing_off, &c.ing_ns, ns, name) >= 0 { return _k_err_int("ingress: duplicate ingress"); }
  if c.ing_off.len() - 1 >= K8S_MAX_OBJECTS { return _k_err_int("ingress: object limit exceeded"); }
  let id = c.ing_off.len() - 1;
  c.ing_data = _k_blob_append(c.ing_data, &mut c.ing_off, name);
  c.ing_ns.push(ns);
  return _k_ok_int(id);
}

/// Number of ingresses. Complexity: O(1).
pub fn ingress_count(c: &K8sCluster) -> Int {
  return c.ing_off.len() - 1;
}

/// Ingress id of (`ns`, `name`), or K8S_NOT_FOUND.
pub fn ingress_index(c: &K8sCluster, ns: Int, name: Str) -> Int {
  return _k_obj_find(c.ing_data, &c.ing_off, &c.ing_ns, ns, name);
}

/// Ingress name, or "" when the id is out of range.
pub fn ingress_name(c: &K8sCluster, id: Int) -> Str {
  return _k_entry(c.ing_data, &c.ing_off, id);
}

/// Namespace id of ingress `id`, or K8S_NOT_FOUND.
pub fn ingress_namespace(c: &K8sCluster, id: Int) -> Int {
  if id < 0 || id >= c.ing_ns.len() { return K8S_NOT_FOUND; }
  let v: Int = c.ing_ns[id];
  return v;
}

/// Append one exposure rule (host, path, backend service name in the same
/// namespace, backend port). A rule with an empty host matches every host.
/// Returns the new rule count for the ingress.
/// Errors: "ingress: unknown ingress", "ingress: invalid host",
/// "ingress: path must start with '/'", "ingress: service name must not be
/// empty", "ingress: invalid service name", "ingress: port must be in
/// 1..65535".
pub fn ingress_rule_add(c: &mut K8sCluster, id: Int, host: Str, path: Str, svc_name: Str, port: Int) -> Result[Int, Str] {
  if id < 0 || id >= c.ing_off.len() - 1 { return _k_err_int("ingress: unknown ingress"); }
  if string.str_len(host) > 0 && !ingress_host_valid(host) { return _k_err_int("ingress: invalid host"); }
  if string.str_len(path) == 0 { return _k_err_int("ingress: path must start with '/'"); }
  let b0: Int = (string.byte_at(path, 0) as Int) & 0xFF;
  if b0 != 0x2F { return _k_err_int("ingress: path must start with '/'"); }
  if string.str_len(svc_name) == 0 { return _k_err_int("ingress: service name must not be empty"); }
  if !k8s_name_valid(svc_name) { return _k_err_int("ingress: invalid service name"); }
  if port < 1 || port > K8S_MAX_PORT { return _k_err_int("ingress: port must be in 1..65535"); }
  c.ing_rule_host_data = _k_owner_append(c.ing_rule_host_data, &mut c.ing_rule_host_off, &mut c.ing_rule_host_owner, id, host);
  c.ing_rule_path_data = _k_blob_append(c.ing_rule_path_data, &mut c.ing_rule_path_off, path);
  c.ing_rule_svc_data = _k_blob_append(c.ing_rule_svc_data, &mut c.ing_rule_svc_off, svc_name);
  c.ing_rule_port.push(port);
  return _k_ok_int(_k_rule_count(c, id));
}

/// Number of rules on ingress `id`, or K8S_NOT_FOUND.
pub fn ingress_rule_count(c: &K8sCluster, id: Int) -> Int {
  if id < 0 || id >= c.ing_off.len() - 1 { return K8S_NOT_FOUND; }
  return _k_rule_count(c, id);
}

/// Host of rule `i` on ingress `id` ("" = any host), or "" out of range.
pub fn ingress_rule_host(c: &K8sCluster, id: Int, i: Int) -> Str {
  let g = _k_rule_global(c, id, i);
  if g < 0 { return ""; }
  return _k_entry(c.ing_rule_host_data, &c.ing_rule_host_off, g);
}

/// Path of rule `i` on ingress `id`, or "" out of range.
pub fn ingress_rule_path(c: &K8sCluster, id: Int, i: Int) -> Str {
  let g = _k_rule_global(c, id, i);
  if g < 0 { return ""; }
  return _k_entry(c.ing_rule_path_data, &c.ing_rule_path_off, g);
}

/// Backend service name of rule `i` on ingress `id`, or "" out of range.
pub fn ingress_rule_service(c: &K8sCluster, id: Int, i: Int) -> Str {
  let g = _k_rule_global(c, id, i);
  if g < 0 { return ""; }
  return _k_entry(c.ing_rule_svc_data, &c.ing_rule_svc_off, g);
}

/// Backend port of rule `i` on ingress `id`, or K8S_NOT_FOUND.
pub fn ingress_rule_port(c: &K8sCluster, id: Int, i: Int) -> Int {
  let g = _k_rule_global(c, id, i);
  if g < 0 { return K8S_NOT_FOUND; }
  if g >= c.ing_rule_port.len() { return K8S_NOT_FOUND; }
  let v: Int = c.ing_rule_port[g];
  return v;
}

// True when request `host` (`hl` bytes) matches rule host `rh`: empty rule
// host is a wildcard, otherwise byte-exact.
fn _k_host_match(rh: Str, host: Str) -> Bool {
  if string.str_len(rh) == 0 { return true; }
  return string.str_compare(rh, host) == 0;
}

// True when rule path `rp` matches request path: exact, or a path-element
// prefix (the next request byte is '/' or the rule path ends with '/').
fn _k_path_match(rp: Str, req: Str) -> Bool {
  if string.str_compare(rp, req) == 0 { return true; }
  if !string.str_starts_with(req, rp) { return false; }
  let pl = string.str_len(rp);
  let rl = string.str_len(req);
  if pl >= rl { return false; }
  let last: Int = (string.byte_at(rp, pl - 1) as Int) & 0xFF;
  if last == 0x2F { return true; }
  let next: Int = (string.byte_at(req, pl) as Int) & 0xFF;
  return next == 0x2F;
}

/// Resolve a request (host, path) to a backend service id on ingress `id`:
/// the longest matching rule path wins (ties keep the earlier rule; an empty
/// rule host matches every host; "/" matches everything). The backend must
/// resolve to a service in the ingress namespace.
/// Errors: "ingress: unknown ingress", "ingress: invalid host",
/// "ingress: path must start with '/'", "ingress: no matching rule",
/// "ingress: backend service not found".
pub fn ingress_resolve(c: &K8sCluster, id: Int, host: Str, path: Str) -> Result[Int, Str] {
  if id < 0 || id >= c.ing_off.len() - 1 { return _k_err_int("ingress: unknown ingress"); }
  if string.str_len(host) > 0 && !ingress_host_valid(host) { return _k_err_int("ingress: invalid host"); }
  if string.str_len(path) == 0 { return _k_err_int("ingress: path must start with '/'"); }
  let b0: Int = (string.byte_at(path, 0) as Int) & 0xFF;
  if b0 != 0x2F { return _k_err_int("ingress: path must start with '/'"); }
  let cnt = _k_rule_count(c, id);
  var best_len = -1;
  var best = "";
  var i = 0;
  while i < cnt {
    let g = _k_rule_global(c, id, i);
    if g >= 0 {
      let rh = _k_entry(c.ing_rule_host_data, &c.ing_rule_host_off, g);
      let rp = _k_entry(c.ing_rule_path_data, &c.ing_rule_path_off, g);
      if _k_host_match(rh, host) && _k_path_match(rp, path) {
        let pl = string.str_len(rp);
        if pl > best_len {
          best_len = pl;
          best = _k_entry(c.ing_rule_svc_data, &c.ing_rule_svc_off, g);
        }
      }
    }
    i = i + 1;
  }
  if best_len < 0 { return _k_err_int("ingress: no matching rule"); }
  let ns: Int = c.ing_ns[id];
  let sid = _k_obj_find(c.svc_data, &c.svc_off, &c.svc_ns, ns, best);
  if sid < 0 { return _k_err_int("ingress: backend service not found"); }
  return _k_ok_int(sid);
}

/// True when ingress `id` exposes (host, path) to a resolvable backend.
pub fn ingress_exposes(c: &K8sCluster, id: Int, host: Str, path: Str) -> Bool {
  match ingress_resolve(c, id, host, path) {
    Ok(_) => { return true; },
    Err(_) => { return false; },
  }
  return false;
}

// ---------------------------------------------------------------------------
// ConfigMaps and Secrets
// ---------------------------------------------------------------------------

// Append one validated "key=value" entry owned by `owner_id`, using
// `prefix` ("configmap" or "secret") in error messages.
fn _k_kv_add(data: Str, off: &mut Vec[Int], owner: &mut Vec[Int], owner_id: Int, key: Str, val: Str, prefix: Str) -> Result[Str, Str] {
  if string.str_len(key) == 0 { return _k_err_str(prefix + ": key must not be empty"); }
  if !_k_config_key_valid(key) { return _k_err_str(prefix + ": invalid key"); }
  if selector.label_owned_has(data, off, owner, owner_id, key) { return _k_err_str(prefix + ": duplicate key"); }
  return _k_ok_str(_k_owner_append(data, off, owner, owner_id, key + "=" + val));
}

/// Create a configmap. An immutable configmap rejects every later set.
/// Errors: namespace, name, duplicate and object-limit errors.
pub fn configmap_create(c: &mut K8sCluster, ns: Int, name: Str, immutable: Bool) -> Result[Int, Str] {
  if ns < 0 || ns >= c.ns_off.len() - 1 { return _k_err_int("configmap: unknown namespace"); }
  if string.str_len(name) == 0 { return _k_err_int("configmap: name must not be empty"); }
  if !k8s_name_valid(name) { return _k_err_int("configmap: invalid name"); }
  if _k_obj_find(c.cm_data, &c.cm_off, &c.cm_ns, ns, name) >= 0 { return _k_err_int("configmap: duplicate configmap"); }
  if c.cm_off.len() - 1 >= K8S_MAX_OBJECTS { return _k_err_int("configmap: object limit exceeded"); }
  let id = c.cm_off.len() - 1;
  var im = 0;
  if immutable { im = 1; }
  c.cm_data = _k_blob_append(c.cm_data, &mut c.cm_off, name);
  c.cm_ns.push(ns);
  c.cm_immutable.push(im);
  return _k_ok_int(id);
}

/// Number of configmaps. Complexity: O(1).
pub fn configmap_count(c: &K8sCluster) -> Int {
  return c.cm_off.len() - 1;
}

/// ConfigMap id of (`ns`, `name`), or K8S_NOT_FOUND.
pub fn configmap_index(c: &K8sCluster, ns: Int, name: Str) -> Int {
  return _k_obj_find(c.cm_data, &c.cm_off, &c.cm_ns, ns, name);
}

/// ConfigMap name, or "" when the id is out of range.
pub fn configmap_name(c: &K8sCluster, id: Int) -> Str {
  return _k_entry(c.cm_data, &c.cm_off, id);
}

/// Namespace id of configmap `id`, or K8S_NOT_FOUND.
pub fn configmap_namespace(c: &K8sCluster, id: Int) -> Int {
  if id < 0 || id >= c.cm_ns.len() { return K8S_NOT_FOUND; }
  let v: Int = c.cm_ns[id];
  return v;
}

/// True when configmap `id` is immutable.
pub fn configmap_immutable(c: &K8sCluster, id: Int) -> Bool {
  if id < 0 || id >= c.cm_immutable.len() { return false; }
  let v: Int = c.cm_immutable[id];
  return v == 1;
}

/// True when configmap `id` is scoped to namespace `ns` (references only
/// resolve inside the referrer's own namespace).
pub fn configmap_visible(c: &K8sCluster, id: Int, ns: Int) -> Bool {
  if id < 0 || id >= c.cm_ns.len() { return false; }
  let v: Int = c.cm_ns[id];
  return v == ns;
}

/// Set `key` on configmap `id`. Keys are append-only within the model, so
/// reusing a key is rejected. Returns the new key count.
/// Errors: "configmap: unknown configmap", "configmap: immutable",
/// "configmap: key must not be empty", "configmap: invalid key",
/// "configmap: duplicate key".
pub fn configmap_set(c: &mut K8sCluster, id: Int, key: Str, val: Str) -> Result[Int, Str] {
  if id < 0 || id >= c.cm_off.len() - 1 { return _k_err_int("configmap: unknown configmap"); }
  if configmap_immutable(c, id) { return _k_err_int("configmap: immutable"); }
  match _k_kv_add(c.cm_kv_data, &mut c.cm_kv_off, &mut c.cm_kv_owner, id, key, val, "configmap") {
    Ok(nd) => { c.cm_kv_data = nd; },
    Err(emsg) => { return _k_err_int(emsg); },
  }
  return _k_ok_int(selector.label_owned_count(&c.cm_kv_off, &c.cm_kv_owner, id));
}

/// Value of `key` on configmap `id`, or "" when absent/unknown.
pub fn configmap_get(c: &K8sCluster, id: Int, key: Str) -> Str {
  if id < 0 || id >= c.cm_off.len() - 1 { return ""; }
  return selector.label_owned_value(c.cm_kv_data, &c.cm_kv_off, &c.cm_kv_owner, id, key);
}

/// Number of keys on configmap `id`, or K8S_NOT_FOUND.
pub fn configmap_key_count(c: &K8sCluster, id: Int) -> Int {
  if id < 0 || id >= c.cm_off.len() - 1 { return K8S_NOT_FOUND; }
  return selector.label_owned_count(&c.cm_kv_off, &c.cm_kv_owner, id);
}

/// ConfigMap data rendered as "k=v,k2=v2" in insertion order.
pub fn configmap_render(c: &K8sCluster, id: Int) -> Str {
  if id < 0 || id >= c.cm_off.len() - 1 { return ""; }
  return selector.label_owned_render(c.cm_kv_data, &c.cm_kv_off, &c.cm_kv_owner, id);
}

/// Create a secret of the given non-empty type. Returns the dense secret id.
/// Errors: namespace, name, "secret: type must not be empty", duplicate and
/// object-limit errors.
pub fn secret_create(c: &mut K8sCluster, ns: Int, name: Str, sec_type: Str) -> Result[Int, Str] {
  if ns < 0 || ns >= c.ns_off.len() - 1 { return _k_err_int("secret: unknown namespace"); }
  if string.str_len(name) == 0 { return _k_err_int("secret: name must not be empty"); }
  if !k8s_name_valid(name) { return _k_err_int("secret: invalid name"); }
  if string.str_len(sec_type) == 0 { return _k_err_int("secret: type must not be empty"); }
  if _k_obj_find(c.sec_data, &c.sec_off, &c.sec_ns, ns, name) >= 0 { return _k_err_int("secret: duplicate secret"); }
  if c.sec_off.len() - 1 >= K8S_MAX_OBJECTS { return _k_err_int("secret: object limit exceeded"); }
  let id = c.sec_off.len() - 1;
  c.sec_data = _k_blob_append(c.sec_data, &mut c.sec_off, name);
  c.sec_ns.push(ns);
  c.sec_type_data = _k_blob_append(c.sec_type_data, &mut c.sec_type_off, sec_type);
  return _k_ok_int(id);
}

/// Number of secrets. Complexity: O(1).
pub fn secret_count(c: &K8sCluster) -> Int {
  return c.sec_off.len() - 1;
}

/// Secret id of (`ns`, `name`), or K8S_NOT_FOUND.
pub fn secret_index(c: &K8sCluster, ns: Int, name: Str) -> Int {
  return _k_obj_find(c.sec_data, &c.sec_off, &c.sec_ns, ns, name);
}

/// Secret name, or "" when the id is out of range.
pub fn secret_name(c: &K8sCluster, id: Int) -> Str {
  return _k_entry(c.sec_data, &c.sec_off, id);
}

/// Namespace id of secret `id`, or K8S_NOT_FOUND.
pub fn secret_namespace(c: &K8sCluster, id: Int) -> Int {
  if id < 0 || id >= c.sec_ns.len() { return K8S_NOT_FOUND; }
  let v: Int = c.sec_ns[id];
  return v;
}

/// Type of secret `id` (e.g. "Opaque"), or "" when out of range.
pub fn secret_type_value(c: &K8sCluster, id: Int) -> Str {
  if id < 0 || id >= c.sec_off.len() - 1 { return ""; }
  return _k_entry(c.sec_type_data, &c.sec_type_off, id);
}

/// Set `key` on secret `id` (append-only keys, as for configmaps). Returns
/// the new key count. Errors: "secret: unknown secret", "secret: key must
/// not be empty", "secret: invalid key", "secret: duplicate key".
pub fn secret_set(c: &mut K8sCluster, id: Int, key: Str, val: Str) -> Result[Int, Str] {
  if id < 0 || id >= c.sec_off.len() - 1 { return _k_err_int("secret: unknown secret"); }
  match _k_kv_add(c.sec_kv_data, &mut c.sec_kv_off, &mut c.sec_kv_owner, id, key, val, "secret") {
    Ok(nd) => { c.sec_kv_data = nd; },
    Err(emsg) => { return _k_err_int(emsg); },
  }
  return _k_ok_int(selector.label_owned_count(&c.sec_kv_off, &c.sec_kv_owner, id));
}

/// Value of `key` on secret `id`, or "" when absent/unknown.
pub fn secret_get(c: &K8sCluster, id: Int, key: Str) -> Str {
  if id < 0 || id >= c.sec_off.len() - 1 { return ""; }
  return selector.label_owned_value(c.sec_kv_data, &c.sec_kv_off, &c.sec_kv_owner, id, key);
}

/// Number of keys on secret `id`, or K8S_NOT_FOUND.
pub fn secret_key_count(c: &K8sCluster, id: Int) -> Int {
  if id < 0 || id >= c.sec_off.len() - 1 { return K8S_NOT_FOUND; }
  return selector.label_owned_count(&c.sec_kv_off, &c.sec_kv_owner, id);
}

// ---------------------------------------------------------------------------
// Namespace-scoped references
// ---------------------------------------------------------------------------

/// Resolve configmap `name` for pod `pod`: only a configmap in the pod's own
/// namespace is visible. Returns the configmap id.
/// Errors: "pod: unknown pod", "configmap: not found".
pub fn pod_ref_configmap(c: &K8sCluster, pod: Int, name: Str) -> Result[Int, Str] {
  if pod < 0 || pod >= c.pod_ns.len() { return _k_err_int("pod: unknown pod"); }
  let ns: Int = c.pod_ns[pod];
  let k = _k_obj_find(c.cm_data, &c.cm_off, &c.cm_ns, ns, name);
  if k < 0 { return _k_err_int("configmap: not found"); }
  return _k_ok_int(k);
}

/// Resolve secret `name` for pod `pod`: only a secret in the pod's own
/// namespace is visible. Returns the secret id.
/// Errors: "pod: unknown pod", "secret: not found".
pub fn pod_ref_secret(c: &K8sCluster, pod: Int, name: Str) -> Result[Int, Str] {
  if pod < 0 || pod >= c.pod_ns.len() { return _k_err_int("pod: unknown pod"); }
  let ns: Int = c.pod_ns[pod];
  let k = _k_obj_find(c.sec_data, &c.sec_off, &c.sec_ns, ns, name);
  if k < 0 { return _k_err_int("secret: not found"); }
  return _k_ok_int(k);
}
