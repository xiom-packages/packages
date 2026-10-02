// XIOM -- xiom.cloud: cloud provider/orchestration descriptor registry
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure DESCRIPTOR REGISTRY: no SDK bindings, no FFI, no network, no file I/O.
// The registry models the cloud/orchestration umbrella as data:
//
//   * six provider descriptors: aws, azure, gcp (public cloud) plus k8s,
//     docker, nomad (orchestrators);
//   * five capabilities: compute, storage, functions, db, queue;
//   * a 6x5 compatibility matrix (none / partial / full);
//   * region and zone descriptor tables (public-cloud providers only);
//   * a 150-entry vendor table (cloud-vendor umbrella) with a documented
//     well-known subset flagged as such.
//
// Storage discipline (XIOM v0.62.2): every string table is a Str blob plus a
// parallel monotone Vec[Int] offset table; all tables are built at run time by
// cloud_registry_new() -- there are no module-level Vec globals and no
// Vec[StructType]. Callers hold one CloudRegistry value and query it through
// the resolution API (provider lookup, capability query, region validation).
//
// Language discipline: free functions only; no match; no bare loop; every
// Vec[Int] element read binds a typed local; Str equality goes through
// xiom.string.compare.str_compare; Ok/Err only inside the leaf helpers; no
// &mut scalar parameters; bounded loops everywhere.

module xiom.cloud

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// ---------------------------------------------------------------------------
// Public constants
// ---------------------------------------------------------------------------

/// Provider id: Amazon Web Services.
pub const CLOUD_PROVIDER_AWS: Int = 0;

/// Provider id: Microsoft Azure.
pub const CLOUD_PROVIDER_AZURE: Int = 1;

/// Provider id: Google Cloud Platform.
pub const CLOUD_PROVIDER_GCP: Int = 2;

/// Provider id: Kubernetes.
pub const CLOUD_PROVIDER_K8S: Int = 3;

/// Provider id: Docker.
pub const CLOUD_PROVIDER_DOCKER: Int = 4;

/// Provider id: HashiCorp Nomad.
pub const CLOUD_PROVIDER_NOMAD: Int = 5;

/// Number of modeled provider descriptors.
pub const CLOUD_PROVIDER_COUNT: Int = 6;

/// Provider kind: public/hyperscale cloud.
pub const CLOUD_KIND_PUBLIC: Int = 0;

/// Provider kind: container/workload orchestrator.
pub const CLOUD_KIND_ORCHESTRATOR: Int = 1;

/// Capability id: compute.
pub const CLOUD_CAP_COMPUTE: Int = 0;

/// Capability id: storage.
pub const CLOUD_CAP_STORAGE: Int = 1;

/// Capability id: serverless functions.
pub const CLOUD_CAP_FUNCTIONS: Int = 2;

/// Capability id: managed/operated database service.
pub const CLOUD_CAP_DB: Int = 3;

/// Capability id: queue/messaging service.
pub const CLOUD_CAP_QUEUE: Int = 4;

/// Number of capability columns.
pub const CLOUD_CAP_COUNT: Int = 5;

/// Compatibility: capability not offered.
pub const CLOUD_COMPAT_NONE: Int = 0;

/// Compatibility: offered with caveats (self-managed, operator, single host).
pub const CLOUD_COMPAT_PARTIAL: Int = 1;

/// Compatibility: offered as a first-class managed capability.
pub const CLOUD_COMPAT_FULL: Int = 2;

/// Sentinel: not found / out of range.
pub const CLOUD_NOT_FOUND: Int = -1;

/// Number of region descriptors in the registry.
pub const CLOUD_REGION_COUNT: Int = 12;

/// Number of zone descriptors in the registry (two per region).
pub const CLOUD_ZONE_COUNT: Int = 24;

/// Number of vendor-table entries.
pub const CLOUD_VENDOR_COUNT: Int = 150;

/// Size of the documented well-known vendor subset (flags bit set).
pub const CLOUD_WELL_KNOWN_VENDOR_COUNT: Int = 30;

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// One provider descriptor as returned by cloud_provider_descriptor().
pub type CloudProvider = {
  name: Str;
  kind: Int;
  vendor_index: Int;
  region_start: Int;
  region_count: Int;
  capability_count: Int;
}

/// The whole descriptor registry: parallel arrays per table. Provider id,
/// region id (global, dense) and vendor index are array indices. Fields are
/// implementation detail; use the accessors. Strings live in blobs with
/// monotone offset tables (entry i is the range off[i] .. off[i+1]).
pub type CloudRegistry = {
  // providers (6): name blob + kind / vendor index / region range / capability
  provider_data: Str;
  provider_off: Vec[Int];
  provider_kind: Vec[Int];
  provider_vendor: Vec[Int];
  provider_region_start: Vec[Int];
  provider_region_count: Vec[Int];
  // regions (12): name blob + owning provider + zone count
  reg_data: Str;
  reg_off: Vec[Int];
  reg_owner: Vec[Int];
  reg_zone_count: Vec[Int];
  // zones (24): name blob + owning region
  zone_data: Str;
  zone_off: Vec[Int];
  zone_owner: Vec[Int];
  // compatibility matrix (provider * CLOUD_CAP_COUNT + capability)
  compat: Vec[Int];
  // vendors (150): name blob + flags (bit 0 = documented well-known subset)
  vendor_data: Str;
  vendor_off: Vec[Int];
  vendor_flags: Vec[Int];
}

// ---------------------------------------------------------------------------
// Result constructors (leaf helpers only)
// ---------------------------------------------------------------------------

fn _c_ok_int(v: Int) -> Result[Int, Str] { return Ok(v); }
fn _c_err_int(m: Str) -> Result[Int, Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Blob helpers (Str + monotone Vec[Int] offsets; no Vec[Str])
// ---------------------------------------------------------------------------

// Append `s` to blob `data`/`off`; the caller assigns the returned Str.
fn _c_blob_append(data: Str, off: &mut Vec[Int], s: Str) -> Str {
  let start: Int = off[off.len() - 1];
  off.push(start + string.str_len(s));
  return data + s;
}

// Entry `i` of blob `data`/`off`, or "" when out of range.
fn _c_entry(data: Str, off: &Vec[Int], i: Int) -> Str {
  if i < 0 || i >= off.len() - 1 { return ""; }
  let a: Int = off[i];
  let b: Int = off[i + 1];
  return string.str_slice(data, a, b);
}

// Index of `name` in a blob, or CLOUD_NOT_FOUND (-1).
fn _c_name_find(data: Str, off: &Vec[Int], name: Str) -> Int {
  let cnt = off.len() - 1;
  let n = string.str_len(name);
  var i = 0;
  while i < cnt {
    let a: Int = off[i];
    let b: Int = off[i + 1];
    if b - a == n {
      if compare.str_compare(string.str_slice(data, a, b), name) == 0 {
        return i;
      }
    }
    i = i + 1;
  }
  return CLOUD_NOT_FOUND;
}

// Append zone `name` owned by `region_id`; caller assigns returned Str.
fn _c_zone_append(zone_data: Str, zone_off: &mut Vec[Int], zone_owner: &mut Vec[Int], region_id: Int, name: Str) -> Str {
  let nd = _c_blob_append(zone_data, zone_off, name);
  zone_owner.push(region_id);
  return nd;
}

// Global zone index of the first zone of `region_id` (sum of prior counts).
fn _c_zone_base(rg: &CloudRegistry, region_id: Int) -> Int {
  if region_id <= 0 { return 0; }
  var base = 0;
  var i = 0;
  while i < region_id {
    base = base + cloud_zone_count(rg, i);
    i = i + 1;
  }
  return base;
}

// ---------------------------------------------------------------------------
// Registry construction
// ---------------------------------------------------------------------------

/// Build the complete descriptor registry. Deterministic: the same tables in
/// the same order on every call. Complexity: O(entries).
pub fn cloud_registry_new() -> CloudRegistry {
  var provider_data = "";
  var provider_off = Vec[Int].new();
  provider_off.push(0);
  var provider_kind = Vec[Int].new();
  var provider_vendor = Vec[Int].new();
  var provider_region_start = Vec[Int].new();
  var provider_region_count = Vec[Int].new();

  var reg_data = "";
  var reg_off = Vec[Int].new();
  reg_off.push(0);
  var reg_owner = Vec[Int].new();
  var reg_zone_count = Vec[Int].new();

  var zone_data = "";
  var zone_off = Vec[Int].new();
  zone_off.push(0);
  var zone_owner = Vec[Int].new();

  var compat = Vec[Int].new();

  var vendor_data = "";
  var vendor_off = Vec[Int].new();
  vendor_off.push(0);
  var vendor_flags = Vec[Int].new();

  // -- provider 0: aws (public cloud, vendor 0, four regions) --------------
  provider_data = _c_blob_append(provider_data, &mut provider_off, "aws");
  provider_kind.push(CLOUD_KIND_PUBLIC);
  provider_vendor.push(0);
  let p0_start: Int = reg_off.len() - 1;
  provider_region_start.push(p0_start);
  let r0: Int = reg_off.len() - 1;
  reg_data = _c_blob_append(reg_data, &mut reg_off, "us-east-1");
  reg_owner.push(0);
  reg_zone_count.push(2);
  let r1: Int = reg_off.len() - 1;
  reg_data = _c_blob_append(reg_data, &mut reg_off, "us-west-2");
  reg_owner.push(0);
  reg_zone_count.push(2);
  let r2: Int = reg_off.len() - 1;
  reg_data = _c_blob_append(reg_data, &mut reg_off, "eu-west-1");
  reg_owner.push(0);
  reg_zone_count.push(2);
  let r3: Int = reg_off.len() - 1;
  reg_data = _c_blob_append(reg_data, &mut reg_off, "ap-southeast-1");
  reg_owner.push(0);
  reg_zone_count.push(2);
  provider_region_count.push(reg_off.len() - 1 - p0_start);

  // -- provider 1: azure (public cloud, vendor 1, four regions) ------------
  provider_data = _c_blob_append(provider_data, &mut provider_off, "azure");
  provider_kind.push(CLOUD_KIND_PUBLIC);
  provider_vendor.push(1);
  let p1_start: Int = reg_off.len() - 1;
  provider_region_start.push(p1_start);
  let r4: Int = reg_off.len() - 1;
  reg_data = _c_blob_append(reg_data, &mut reg_off, "eastus");
  reg_owner.push(1);
  reg_zone_count.push(2);
  let r5: Int = reg_off.len() - 1;
  reg_data = _c_blob_append(reg_data, &mut reg_off, "westus2");
  reg_owner.push(1);
  reg_zone_count.push(2);
  let r6: Int = reg_off.len() - 1;
  reg_data = _c_blob_append(reg_data, &mut reg_off, "westeurope");
  reg_owner.push(1);
  reg_zone_count.push(2);
  let r7: Int = reg_off.len() - 1;
  reg_data = _c_blob_append(reg_data, &mut reg_off, "southeastasia");
  reg_owner.push(1);
  reg_zone_count.push(2);
  provider_region_count.push(reg_off.len() - 1 - p1_start);

  // -- provider 2: gcp (public cloud, vendor 2, four regions) --------------
  provider_data = _c_blob_append(provider_data, &mut provider_off, "gcp");
  provider_kind.push(CLOUD_KIND_PUBLIC);
  provider_vendor.push(2);
  let p2_start: Int = reg_off.len() - 1;
  provider_region_start.push(p2_start);
  let r8: Int = reg_off.len() - 1;
  reg_data = _c_blob_append(reg_data, &mut reg_off, "us-central1");
  reg_owner.push(2);
  reg_zone_count.push(2);
  let r9: Int = reg_off.len() - 1;
  reg_data = _c_blob_append(reg_data, &mut reg_off, "us-east1");
  reg_owner.push(2);
  reg_zone_count.push(2);
  let r10: Int = reg_off.len() - 1;
  reg_data = _c_blob_append(reg_data, &mut reg_off, "europe-west1");
  reg_owner.push(2);
  reg_zone_count.push(2);
  let r11: Int = reg_off.len() - 1;
  reg_data = _c_blob_append(reg_data, &mut reg_off, "asia-southeast1");
  reg_owner.push(2);
  reg_zone_count.push(2);
  provider_region_count.push(reg_off.len() - 1 - p2_start);

  // -- provider 3: k8s (orchestrator, vendor 3, no region model) -----------
  provider_data = _c_blob_append(provider_data, &mut provider_off, "k8s");
  provider_kind.push(CLOUD_KIND_ORCHESTRATOR);
  provider_vendor.push(3);
  provider_region_start.push(CLOUD_NOT_FOUND);
  provider_region_count.push(0);

  // -- provider 4: docker (orchestrator, vendor 4, no region model) --------
  provider_data = _c_blob_append(provider_data, &mut provider_off, "docker");
  provider_kind.push(CLOUD_KIND_ORCHESTRATOR);
  provider_vendor.push(4);
  provider_region_start.push(CLOUD_NOT_FOUND);
  provider_region_count.push(0);

  // -- provider 5: nomad (orchestrator, vendor 5, no region model) ---------
  provider_data = _c_blob_append(provider_data, &mut provider_off, "nomad");
  provider_kind.push(CLOUD_KIND_ORCHESTRATOR);
  provider_vendor.push(5);
  provider_region_start.push(CLOUD_NOT_FOUND);
  provider_region_count.push(0);

  // -- zones: derived from the region table (two per region) ---------------
  var zr = 0;
  let total_regions: Int = reg_off.len() - 1;
  while zr < total_regions {
    let rn = _c_entry(reg_data, &reg_off, zr);
    zone_data = _c_zone_append(zone_data, &mut zone_off, &mut zone_owner, zr, rn + "-a");
    zone_data = _c_zone_append(zone_data, &mut zone_off, &mut zone_owner, zr, rn + "-b");
    zr = zr + 1;
  }

  // -- compatibility matrix (provider major, capability minor) -------------
  // aws: all five capabilities first-class.
  compat.push(CLOUD_COMPAT_FULL);      // compute
  compat.push(CLOUD_COMPAT_FULL);      // storage
  compat.push(CLOUD_COMPAT_FULL);      // functions
  compat.push(CLOUD_COMPAT_FULL);      // db
  compat.push(CLOUD_COMPAT_FULL);      // queue
  // azure: all five capabilities first-class.
  compat.push(CLOUD_COMPAT_FULL);
  compat.push(CLOUD_COMPAT_FULL);
  compat.push(CLOUD_COMPAT_FULL);
  compat.push(CLOUD_COMPAT_FULL);
  compat.push(CLOUD_COMPAT_FULL);
  // gcp: all five capabilities first-class.
  compat.push(CLOUD_COMPAT_FULL);
  compat.push(CLOUD_COMPAT_FULL);
  compat.push(CLOUD_COMPAT_FULL);
  compat.push(CLOUD_COMPAT_FULL);
  compat.push(CLOUD_COMPAT_FULL);
  // k8s: workload orchestration full; everything else via operators/CSI.
  compat.push(CLOUD_COMPAT_FULL);      // compute
  compat.push(CLOUD_COMPAT_PARTIAL);   // storage (CSI / persistent volumes)
  compat.push(CLOUD_COMPAT_PARTIAL);   // functions (Knative/OpenFaaS on top)
  compat.push(CLOUD_COMPAT_PARTIAL);   // db (StatefulSets / operators)
  compat.push(CLOUD_COMPAT_PARTIAL);   // queue (self-hosted brokers)
  // docker: single-host container workloads; no managed services.
  compat.push(CLOUD_COMPAT_PARTIAL);   // compute (single host)
  compat.push(CLOUD_COMPAT_PARTIAL);   // storage (volumes)
  compat.push(CLOUD_COMPAT_NONE);      // functions
  compat.push(CLOUD_COMPAT_PARTIAL);   // db (containerized)
  compat.push(CLOUD_COMPAT_PARTIAL);   // queue (containerized)
  // nomad: scheduling full, storage with host/CSI caveats, no managed svcs.
  compat.push(CLOUD_COMPAT_FULL);      // compute
  compat.push(CLOUD_COMPAT_PARTIAL);   // storage (host volumes / CSI)
  compat.push(CLOUD_COMPAT_NONE);      // functions
  compat.push(CLOUD_COMPAT_NONE);      // db
  compat.push(CLOUD_COMPAT_NONE);      // queue

  // -- vendor table: documented well-known subset (flag 1), then long tail --
  // 1-10
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "aws");
  vendor_flags.push(1);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "azure");
  vendor_flags.push(1);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "gcp");
  vendor_flags.push(1);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "kubernetes");
  vendor_flags.push(1);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "docker");
  vendor_flags.push(1);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "nomad");
  vendor_flags.push(1);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "oracle");
  vendor_flags.push(1);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "ibm");
  vendor_flags.push(1);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "alibaba");
  vendor_flags.push(1);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "tencent");
  vendor_flags.push(1);
  // 11-20
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "huawei");
  vendor_flags.push(1);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "digitalocean");
  vendor_flags.push(1);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "linode");
  vendor_flags.push(1);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "vultr");
  vendor_flags.push(1);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "hetzner");
  vendor_flags.push(1);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "ovh");
  vendor_flags.push(1);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "scaleway");
  vendor_flags.push(1);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "cloudflare");
  vendor_flags.push(1);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "rackspace");
  vendor_flags.push(1);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "vmware");
  vendor_flags.push(1);
  // 21-30
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "nutanix");
  vendor_flags.push(1);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "openstack");
  vendor_flags.push(1);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "openshift");
  vendor_flags.push(1);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "heroku");
  vendor_flags.push(1);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "vercel");
  vendor_flags.push(1);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "netlify");
  vendor_flags.push(1);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "render");
  vendor_flags.push(1);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "fly-io");
  vendor_flags.push(1);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "railway");
  vendor_flags.push(1);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "cloudstack");
  vendor_flags.push(1);
  // 31-40
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "proxmox");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "upcloud");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "gcore");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "selectel");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "yandex");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "sbercloud");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "vk-cloud");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "mail-ru");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "beget");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "timeweb");
  vendor_flags.push(0);
  // 41-50
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "reg-ru");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "ionos");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "strato");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "contabo");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "netcup");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "akamai");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "fastly");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "bunny");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "keycdn");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "stackpath");
  vendor_flags.push(0);
  // 51-60
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "imperva");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "f5");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "citrix");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "nvidia");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "coreweave");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "lambda-labs");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "paperspace");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "vast-data");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "runpod");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "modal");
  vendor_flags.push(0);
  // 61-70
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "replicate");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "huggingface");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "databricks");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "snowflake");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "mongodb-atlas");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "datastax");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "confluent");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "elastic-cloud");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "cloudera");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "datadog");
  vendor_flags.push(0);
  // 71-80
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "newrelic");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "dynatrace");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "splunk");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "grafana-cloud");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "logzio");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "sentry");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "pagerduty");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "opsgenie");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "victorops");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "atlassian");
  vendor_flags.push(0);
  // 81-90
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "github");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "gitlab");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "bitbucket");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "circleci");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "travis-ci");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "buildkite");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "drone");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "argo");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "tekton");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "flux");
  vendor_flags.push(0);
  // 91-100
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "rancher");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "harvester");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "talos");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "podman");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "containerd");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "cri-o");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "lxc");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "incus");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "kata");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "firecracker");
  vendor_flags.push(0);
  // 101-110
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "gvisor");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "xcp-ng");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "opennebula");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "cloudify");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "juju");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "maas");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "terraform-cloud");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "pulumi");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "crossplane");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "spacelift");
  vendor_flags.push(0);
  // 111-120
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "env0");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "scalr");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "consul");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "hashicorp");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "openfaas");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "knative");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "fission");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "nuclio");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "openwhisk");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "openfunction");
  vendor_flags.push(0);
  // 121-130
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "dapr");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "istio");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "linkerd");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "cilium");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "calico");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "portworx");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "longhorn");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "rook");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "ceph");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "minio");
  vendor_flags.push(0);
  // 131-140
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "openebs");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "juicefs");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "seaweedfs");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "velero");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "baidu");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "jd-cloud");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "volcano-engine");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "naver");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "kakao");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "nhn");
  vendor_flags.push(0);
  // 141-150
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "kt-cloud");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "equinix");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "digital-realty");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "cyrusone");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "interxion");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "openai");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "anthropic");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "mistral");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "dreamhost");
  vendor_flags.push(0);
  vendor_data = _c_blob_append(vendor_data, &mut vendor_off, "liquid-web");
  vendor_flags.push(0);

  return CloudRegistry{
    provider_data: provider_data; provider_off: provider_off; provider_kind: provider_kind;
    provider_vendor: provider_vendor; provider_region_start: provider_region_start;
    provider_region_count: provider_region_count;
    reg_data: reg_data; reg_off: reg_off; reg_owner: reg_owner; reg_zone_count: reg_zone_count;
    zone_data: zone_data; zone_off: zone_off; zone_owner: zone_owner;
    compat: compat;
    vendor_data: vendor_data; vendor_off: vendor_off; vendor_flags: vendor_flags;
  };
}

// ---------------------------------------------------------------------------
// Provider resolution
// ---------------------------------------------------------------------------

/// Number of provider descriptors. Complexity: O(1).
pub fn cloud_provider_count(rg: &CloudRegistry) -> Int {
  return rg.provider_off.len() - 1;
}

/// Provider name by dense id, or "" when out of range.
pub fn cloud_provider_name(rg: &CloudRegistry, id: Int) -> Str {
  return _c_entry(rg.provider_data, &rg.provider_off, id);
}

/// Provider kind by id, or CLOUD_NOT_FOUND when out of range.
pub fn cloud_provider_kind(rg: &CloudRegistry, id: Int) -> Int {
  if id < 0 || id >= rg.provider_kind.len() { return CLOUD_NOT_FOUND; }
  let v: Int = rg.provider_kind[id];
  return v;
}

/// Vendor-table index of the provider, or CLOUD_NOT_FOUND when out of range.
pub fn cloud_provider_vendor(rg: &CloudRegistry, id: Int) -> Int {
  if id < 0 || id >= rg.provider_vendor.len() { return CLOUD_NOT_FOUND; }
  let v: Int = rg.provider_vendor[id];
  return v;
}

/// Global id of the provider's first region, or CLOUD_NOT_FOUND.
pub fn cloud_provider_region_start(rg: &CloudRegistry, id: Int) -> Int {
  if id < 0 || id >= rg.provider_region_start.len() { return CLOUD_NOT_FOUND; }
  let v: Int = rg.provider_region_start[id];
  return v;
}

/// Number of regions the provider models (0 for region-less orchestrators).
pub fn cloud_provider_region_count(rg: &CloudRegistry, id: Int) -> Int {
  if id < 0 || id >= rg.provider_region_count.len() { return 0; }
  let v: Int = rg.provider_region_count[id];
  return v;
}

/// Provider descriptor, with empty/default fields when the id is out of
/// range (name "", kind CLOUD_NOT_FOUND, vendor CLOUD_NOT_FOUND, counts 0).
pub fn cloud_provider_descriptor(rg: &CloudRegistry, id: Int) -> CloudProvider {
  if id < 0 || id >= cloud_provider_count(rg) {
    return CloudProvider{
      name: "";
      kind: CLOUD_NOT_FOUND;
      vendor_index: CLOUD_NOT_FOUND;
      region_start: CLOUD_NOT_FOUND;
      region_count: 0;
      capability_count: 0;
    };
  }
  let nm = cloud_provider_name(rg, id);
  let kd = cloud_provider_kind(rg, id);
  let vi = cloud_provider_vendor(rg, id);
  let rs = cloud_provider_region_start(rg, id);
  let rc = cloud_provider_region_count(rg, id);
  let cc = cloud_provider_capability_count(rg, id);
  return CloudProvider{
    name: nm;
    kind: kd;
    vendor_index: vi;
    region_start: rs;
    region_count: rc;
    capability_count: cc;
  };
}

/// Provider id for `name`, or Err. Errors: "cloud: empty provider name",
/// "cloud: unknown provider". Complexity: O(providers).
pub fn cloud_provider_lookup(rg: &CloudRegistry, name: Str) -> Result[Int, Str] {
  if string.str_len(name) == 0 { return _c_err_int("cloud: empty provider name"); }
  let idx = _c_name_find(rg.provider_data, &rg.provider_off, name);
  if idx < 0 { return _c_err_int("cloud: unknown provider"); }
  return _c_ok_int(idx);
}

/// Human-readable provider kind name ("public-cloud", "orchestrator",
/// "unknown"). Complexity: O(1).
pub fn cloud_provider_kind_name(kind: Int) -> Str {
  if kind == CLOUD_KIND_PUBLIC { return "public-cloud"; }
  if kind == CLOUD_KIND_ORCHESTRATOR { return "orchestrator"; }
  return "unknown";
}

// ---------------------------------------------------------------------------
// Capability and compatibility queries
// ---------------------------------------------------------------------------

/// Capability name ("compute", "storage", "functions", "db", "queue",
/// "unknown"). Complexity: O(1).
pub fn cloud_capability_name(cap: Int) -> Str {
  if cap == CLOUD_CAP_COMPUTE { return "compute"; }
  if cap == CLOUD_CAP_STORAGE { return "storage"; }
  if cap == CLOUD_CAP_FUNCTIONS { return "functions"; }
  if cap == CLOUD_CAP_DB { return "db"; }
  if cap == CLOUD_CAP_QUEUE { return "queue"; }
  return "unknown";
}

/// Compatibility-state name ("none", "partial", "full", "unknown").
pub fn cloud_compat_name(state: Int) -> Str {
  if state == CLOUD_COMPAT_NONE { return "none"; }
  if state == CLOUD_COMPAT_PARTIAL { return "partial"; }
  if state == CLOUD_COMPAT_FULL { return "full"; }
  return "unknown";
}

/// Compatibility state for one provider/capability cell: CLOUD_COMPAT_NONE,
/// CLOUD_COMPAT_PARTIAL or CLOUD_COMPAT_FULL. Out-of-range (or malformed
/// matrix) reads return CLOUD_COMPAT_NONE. Complexity: O(1).
pub fn cloud_provider_compat(rg: &CloudRegistry, provider: Int, cap: Int) -> Int {
  if rg.compat.len() < CLOUD_PROVIDER_COUNT * CLOUD_CAP_COUNT { return CLOUD_COMPAT_NONE; }
  if provider < 0 || provider >= CLOUD_PROVIDER_COUNT { return CLOUD_COMPAT_NONE; }
  if cap < 0 || cap >= CLOUD_CAP_COUNT { return CLOUD_COMPAT_NONE; }
  let v: Int = rg.compat[provider * CLOUD_CAP_COUNT + cap];
  return v;
}

/// True when the provider's compatibility state is PARTIAL or FULL.
pub fn cloud_provider_supports(rg: &CloudRegistry, provider: Int, cap: Int) -> Bool {
  return cloud_provider_compat(rg, provider, cap) != CLOUD_COMPAT_NONE;
}

/// Number of capabilities with a non-NONE state (0..5), 0 when out of range.
pub fn cloud_provider_capability_count(rg: &CloudRegistry, provider: Int) -> Int {
  if provider < 0 || provider >= CLOUD_PROVIDER_COUNT { return 0; }
  var cnt = 0;
  var i = 0;
  while i < CLOUD_CAP_COUNT {
    let s: Int = rg.compat[provider * CLOUD_CAP_COUNT + i];
    if s != CLOUD_COMPAT_NONE { cnt = cnt + 1; }
    i = i + 1;
  }
  return cnt;
}

// ---------------------------------------------------------------------------
// Region and zone descriptors
// ---------------------------------------------------------------------------

/// Total number of region descriptors. Complexity: O(1).
pub fn cloud_region_count(rg: &CloudRegistry) -> Int {
  return rg.reg_off.len() - 1;
}

/// Region name by global id, or "" when out of range.
pub fn cloud_region_name(rg: &CloudRegistry, region_id: Int) -> Str {
  return _c_entry(rg.reg_data, &rg.reg_off, region_id);
}

/// Owning provider id of a region, or CLOUD_NOT_FOUND when out of range.
pub fn cloud_region_owner(rg: &CloudRegistry, region_id: Int) -> Int {
  if region_id < 0 || region_id >= rg.reg_owner.len() { return CLOUD_NOT_FOUND; }
  let v: Int = rg.reg_owner[region_id];
  return v;
}

/// Global id of the provider's first region, or CLOUD_NOT_FOUND (alias of
/// cloud_provider_region_start, kept for resolution symmetry).
pub fn cloud_first_region(rg: &CloudRegistry, provider: Int) -> Int {
  if cloud_provider_region_count(rg, provider) == 0 { return CLOUD_NOT_FOUND; }
  return cloud_provider_region_start(rg, provider);
}

/// Validate a region name for a provider and return its global region id.
/// Errors: "cloud: unknown provider", "cloud: empty region name",
/// "cloud: provider has no region model", "cloud: unknown region".
/// Complexity: O(regions of provider).
pub fn cloud_region_lookup(rg: &CloudRegistry, provider: Int, name: Str) -> Result[Int, Str] {
  if provider < 0 || provider >= cloud_provider_count(rg) {
    return _c_err_int("cloud: unknown provider");
  }
  if string.str_len(name) == 0 { return _c_err_int("cloud: empty region name"); }
  let rc = cloud_provider_region_count(rg, provider);
  if rc == 0 { return _c_err_int("cloud: provider has no region model"); }
  let start = cloud_provider_region_start(rg, provider);
  var i = 0;
  while i < rc {
    let rn = cloud_region_name(rg, start + i);
    if compare.str_compare(rn, name) == 0 {
      return _c_ok_int(start + i);
    }
    i = i + 1;
  }
  return _c_err_int("cloud: unknown region");
}

/// Region validation predicate: true when the region id resolves.
pub fn cloud_region_valid(rg: &CloudRegistry, provider: Int, name: Str) -> Bool {
  let r = cloud_region_lookup(rg, provider, name);
  return r.is_ok;
}

/// Number of zones the region models, or CLOUD_NOT_FOUND when out of range.
pub fn cloud_zone_count(rg: &CloudRegistry, region_id: Int) -> Int {
  if region_id < 0 || region_id >= rg.reg_zone_count.len() { return CLOUD_NOT_FOUND; }
  let v: Int = rg.reg_zone_count[region_id];
  return v;
}

/// Zone name for (region, zone index k), or "" when out of range.
/// Complexity: O(region_id).
pub fn cloud_zone_name(rg: &CloudRegistry, region_id: Int, k: Int) -> Str {
  if region_id < 0 || region_id >= cloud_region_count(rg) { return ""; }
  let zc = cloud_zone_count(rg, region_id);
  if k < 0 || k >= zc { return ""; }
  let base = _c_zone_base(rg, region_id);
  return _c_entry(rg.zone_data, &rg.zone_off, base + k);
}

/// Owning region id of zone (region, k), or CLOUD_NOT_FOUND.
pub fn cloud_zone_owner(rg: &CloudRegistry, region_id: Int, k: Int) -> Int {
  if region_id < 0 || region_id >= cloud_region_count(rg) { return CLOUD_NOT_FOUND; }
  let zc = cloud_zone_count(rg, region_id);
  if k < 0 || k >= zc { return CLOUD_NOT_FOUND; }
  let base = _c_zone_base(rg, region_id);
  if base + k >= rg.zone_owner.len() { return CLOUD_NOT_FOUND; }
  let v: Int = rg.zone_owner[base + k];
  return v;
}

// ---------------------------------------------------------------------------
// Vendor table (cloud-vendor umbrella)
// ---------------------------------------------------------------------------

/// Number of vendor entries. Complexity: O(1).
pub fn cloud_vendor_count(rg: &CloudRegistry) -> Int {
  return rg.vendor_off.len() - 1;
}

/// Vendor name by index, or "" when out of range.
pub fn cloud_vendor_name(rg: &CloudRegistry, i: Int) -> Str {
  return _c_entry(rg.vendor_data, &rg.vendor_off, i);
}

/// True when the vendor at `i` is part of the documented well-known subset.
pub fn cloud_vendor_well_known(rg: &CloudRegistry, i: Int) -> Bool {
  if i < 0 || i >= rg.vendor_flags.len() { return false; }
  let v: Int = rg.vendor_flags[i];
  return v != 0;
}

/// Index of a vendor by name, or CLOUD_NOT_FOUND (-1). Complexity: O(n).
pub fn cloud_vendor_lookup(rg: &CloudRegistry, name: Str) -> Int {
  if string.str_len(name) == 0 { return CLOUD_NOT_FOUND; }
  return _c_name_find(rg.vendor_data, &rg.vendor_off, name);
}

/// True when `name` is a vendor entry flagged as well-known.
pub fn cloud_vendor_is_well_known(rg: &CloudRegistry, name: Str) -> Bool {
  let i = cloud_vendor_lookup(rg, name);
  if i < 0 { return false; }
  return cloud_vendor_well_known(rg, i);
}

/// Number of well-known vendor entries. Complexity: O(n).
pub fn cloud_vendor_well_known_count(rg: &CloudRegistry) -> Int {
  var cnt = 0;
  var i = 0;
  while i < rg.vendor_flags.len() {
    let v: Int = rg.vendor_flags[i];
    if v != 0 { cnt = cnt + 1; }
    i = i + 1;
  }
  return cnt;
}

// ---------------------------------------------------------------------------
// Reporting and integrity
// ---------------------------------------------------------------------------

/// One-line provider summary:
/// "<name>: <kind>, <regions> regions, <caps>/<cap-count> capabilities";
/// "cloud: unknown provider" when the id is out of range.
pub fn cloud_describe_provider(rg: &CloudRegistry, provider: Int) -> Str {
  if provider < 0 || provider >= cloud_provider_count(rg) {
    return "cloud: unknown provider";
  }
  let nm = cloud_provider_name(rg, provider);
  let kn = cloud_provider_kind_name(cloud_provider_kind(rg, provider));
  let rc = cloud_provider_region_count(rg, provider);
  let cc = cloud_provider_capability_count(rg, provider);
  return nm + ": " + kn + ", " + convert.int_to_string(rc) + " regions, " + convert.int_to_string(cc) + "/" + convert.int_to_string(CLOUD_CAP_COUNT) + " capabilities";
}

/// Structural invariant check over the whole registry: parallel tables have
/// matching lengths, provider region ranges and zone ownership are in range,
/// region and vendor counts match the pinned constants, and zone totals match
/// the per-region zone counts. Complexity: O(entries).
pub fn cloud_registry_consistent(rg: &CloudRegistry) -> Bool {
  let pc = cloud_provider_count(rg);
  if rg.provider_kind.len() != pc { return false; }
  if rg.provider_vendor.len() != pc { return false; }
  if rg.provider_region_start.len() != pc { return false; }
  if rg.provider_region_count.len() != pc { return false; }
  let rc = cloud_region_count(rg);
  if rc != CLOUD_REGION_COUNT { return false; }
  if rg.reg_owner.len() != rc { return false; }
  if rg.reg_zone_count.len() != rc { return false; }
  let zc = rg.zone_off.len() - 1;
  if zc != CLOUD_ZONE_COUNT { return false; }
  if rg.zone_owner.len() != zc { return false; }
  if rg.compat.len() != CLOUD_PROVIDER_COUNT * CLOUD_CAP_COUNT { return false; }
  let vc = cloud_vendor_count(rg);
  if vc != CLOUD_VENDOR_COUNT { return false; }
  if rg.vendor_flags.len() != vc { return false; }
  if cloud_vendor_well_known_count(rg) != CLOUD_WELL_KNOWN_VENDOR_COUNT { return false; }

  var total = 0;
  var i = 0;
  while i < rc {
    total = total + cloud_zone_count(rg, i);
    i = i + 1;
  }
  if total != zc { return false; }

  var p = 0;
  while p < pc {
    let s = cloud_provider_region_start(rg, p);
    let n = cloud_provider_region_count(rg, p);
    if n > 0 {
      if s < 0 || s + n > rc { return false; }
    }
    var j = 0;
    while j < n {
      let owner = cloud_region_owner(rg, s + j);
      if owner != p { return false; }
      j = j + 1;
    }
    p = p + 1;
  }

  var z = 0;
  while z < zc {
    let o: Int = rg.zone_owner[z];
    if o < 0 || o >= rc { return false; }
    z = z + 1;
  }
  return true;
}
