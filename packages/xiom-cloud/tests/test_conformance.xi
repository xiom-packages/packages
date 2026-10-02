// XIOM -- xiom.cloud conformance tests (26 checks)
// Port task: prove the descriptor registry documented in SPEC.md -- provider
// lookup, capability/compatibility queries, region/zone resolution, vendor
// table and structural invariants -- is deterministic and correct.
// Every check is a named assert(cond, "name") call, one fn per check, and main
// returns the failure count (0 = green). No external files.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// BUG-17 discipline: Str equality goes through compare.str_compare; every Vec
// element read is bound to a typed local.

module cloud_tests
use xiom.io; use xiom.test; use xiom.cloud;
use xiom.string; use xiom.string.compare;

// --------------------------------------------------
//  Helpers
// --------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn int_ok_is(r: Result[Int, Str], want: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Int = r.value;
  return v == want;
}

fn int_err_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return streq(m, want);
}

fn str_nonempty(s: Str) -> Bool {
  return string.str_len(s) > 0;
}

// --------------------------------------------------
//  Checks
// --------------------------------------------------

fn t1() -> TestResult {
  let rg = cloud_registry_new();
  var ok = cloud_provider_count(&rg) == CLOUD_PROVIDER_COUNT;
  ok = ok && CLOUD_PROVIDER_COUNT == 6;
  return assert(ok, "registry: six provider descriptors");
}

fn t2() -> TestResult {
  let rg = cloud_registry_new();
  var ok = int_ok_is(cloud_provider_lookup(&rg, "aws"), CLOUD_PROVIDER_AWS);
  ok = ok && int_ok_is(cloud_provider_lookup(&rg, "azure"), CLOUD_PROVIDER_AZURE);
  ok = ok && int_ok_is(cloud_provider_lookup(&rg, "gcp"), CLOUD_PROVIDER_GCP);
  ok = ok && int_ok_is(cloud_provider_lookup(&rg, "k8s"), CLOUD_PROVIDER_K8S);
  ok = ok && int_ok_is(cloud_provider_lookup(&rg, "docker"), CLOUD_PROVIDER_DOCKER);
  ok = ok && int_ok_is(cloud_provider_lookup(&rg, "nomad"), CLOUD_PROVIDER_NOMAD);
  return assert(ok, "provider: lookup resolves all six names");
}

fn t3() -> TestResult {
  let rg = cloud_registry_new();
  var ok = int_err_is(cloud_provider_lookup(&rg, ""), "cloud: empty provider name");
  ok = ok && int_err_is(cloud_provider_lookup(&rg, "not-a-cloud"), "cloud: unknown provider");
  ok = ok && int_err_is(cloud_provider_lookup(&rg, "AWS"), "cloud: unknown provider");
  return assert(ok, "provider: lookup errors are explicit and case-sensitive");
}

fn t4() -> TestResult {
  let rg = cloud_registry_new();
  var ok = cloud_provider_kind(&rg, CLOUD_PROVIDER_AWS) == CLOUD_KIND_PUBLIC;
  ok = ok && cloud_provider_kind(&rg, CLOUD_PROVIDER_AZURE) == CLOUD_KIND_PUBLIC;
  ok = ok && cloud_provider_kind(&rg, CLOUD_PROVIDER_GCP) == CLOUD_KIND_PUBLIC;
  ok = ok && cloud_provider_kind(&rg, CLOUD_PROVIDER_K8S) == CLOUD_KIND_ORCHESTRATOR;
  ok = ok && cloud_provider_kind(&rg, CLOUD_PROVIDER_DOCKER) == CLOUD_KIND_ORCHESTRATOR;
  ok = ok && cloud_provider_kind(&rg, CLOUD_PROVIDER_NOMAD) == CLOUD_KIND_ORCHESTRATOR;
  ok = ok && cloud_provider_kind(&rg, 99) == CLOUD_NOT_FOUND;
  return assert(ok, "provider: kinds split public cloud vs orchestrator");
}

fn t5() -> TestResult {
  var ok = streq(cloud_provider_kind_name(CLOUD_KIND_PUBLIC), "public-cloud");
  ok = ok && streq(cloud_provider_kind_name(CLOUD_KIND_ORCHESTRATOR), "orchestrator");
  ok = ok && streq(cloud_provider_kind_name(7), "unknown");
  return assert(ok, "provider: kind names are pinned");
}

fn t6() -> TestResult {
  let rg = cloud_registry_new();
  let d = cloud_provider_descriptor(&rg, CLOUD_PROVIDER_AWS);
  let dn: Str = d.name;
  var ok = streq(dn, "aws");
  ok = ok && d.kind == CLOUD_KIND_PUBLIC;
  ok = ok && d.vendor_index == 0;
  ok = ok && d.region_start == 0;
  ok = ok && d.region_count == 4;
  ok = ok && d.capability_count == 5;
  let bad = cloud_provider_descriptor(&rg, 42);
  let bn: Str = bad.name;
  ok = ok && string.str_len(bn) == 0;
  ok = ok && bad.kind == CLOUD_NOT_FOUND;
  ok = ok && bad.vendor_index == CLOUD_NOT_FOUND;
  ok = ok && bad.region_count == 0;
  ok = ok && bad.capability_count == 0;
  return assert(ok, "provider: descriptor exposes name/kind/vendor/regions/caps");
}

fn t7() -> TestResult {
  let rg = cloud_registry_new();
  var ok = cloud_provider_vendor(&rg, CLOUD_PROVIDER_K8S) == 3;
  let kn: Str = cloud_vendor_name(&rg, 3);
  ok = ok && streq(kn, "kubernetes");
  ok = ok && cloud_provider_vendor(&rg, CLOUD_PROVIDER_NOMAD) == 5;
  let nn: Str = cloud_vendor_name(&rg, 5);
  ok = ok && streq(nn, "nomad");
  ok = ok && cloud_provider_vendor(&rg, 99) == CLOUD_NOT_FOUND;
  return assert(ok, "provider: vendor linkage points into the vendor table");
}

fn t8() -> TestResult {
  var ok = streq(cloud_capability_name(CLOUD_CAP_COMPUTE), "compute");
  ok = ok && streq(cloud_capability_name(CLOUD_CAP_STORAGE), "storage");
  ok = ok && streq(cloud_capability_name(CLOUD_CAP_FUNCTIONS), "functions");
  ok = ok && streq(cloud_capability_name(CLOUD_CAP_DB), "db");
  ok = ok && streq(cloud_capability_name(CLOUD_CAP_QUEUE), "queue");
  ok = ok && streq(cloud_capability_name(CLOUD_CAP_COUNT), "unknown");
  return assert(ok, "capability: names and column count are pinned");
}

fn t9() -> TestResult {
  let rg = cloud_registry_new();
  var ok = rg.compat.len() == CLOUD_PROVIDER_COUNT * CLOUD_CAP_COUNT;
  ok = ok && streq(cloud_compat_name(CLOUD_COMPAT_NONE), "none");
  ok = ok && streq(cloud_compat_name(CLOUD_COMPAT_PARTIAL), "partial");
  ok = ok && streq(cloud_compat_name(CLOUD_COMPAT_FULL), "full");
  ok = ok && streq(cloud_compat_name(9), "unknown");
  return assert(ok, "compatibility: 6x5 matrix and state names");
}

fn t10() -> TestResult {
  let rg = cloud_registry_new();
  var ok = cloud_provider_compat(&rg, CLOUD_PROVIDER_AWS, CLOUD_CAP_COMPUTE) == CLOUD_COMPAT_FULL;
  ok = ok && cloud_provider_compat(&rg, CLOUD_PROVIDER_AWS, CLOUD_CAP_STORAGE) == CLOUD_COMPAT_FULL;
  ok = ok && cloud_provider_compat(&rg, CLOUD_PROVIDER_AWS, CLOUD_CAP_FUNCTIONS) == CLOUD_COMPAT_FULL;
  ok = ok && cloud_provider_compat(&rg, CLOUD_PROVIDER_AWS, CLOUD_CAP_DB) == CLOUD_COMPAT_FULL;
  ok = ok && cloud_provider_compat(&rg, CLOUD_PROVIDER_AWS, CLOUD_CAP_QUEUE) == CLOUD_COMPAT_FULL;
  ok = ok && cloud_provider_supports(&rg, CLOUD_PROVIDER_AWS, CLOUD_CAP_COMPUTE);
  ok = ok && cloud_provider_supports(&rg, CLOUD_PROVIDER_AWS, CLOUD_CAP_QUEUE);
  return assert(ok, "compatibility: aws is full on all five capabilities");
}

fn t11() -> TestResult {
  let rg = cloud_registry_new();
  var ok = cloud_provider_compat(&rg, CLOUD_PROVIDER_K8S, CLOUD_CAP_COMPUTE) == CLOUD_COMPAT_FULL;
  ok = ok && cloud_provider_compat(&rg, CLOUD_PROVIDER_K8S, CLOUD_CAP_STORAGE) == CLOUD_COMPAT_PARTIAL;
  ok = ok && cloud_provider_compat(&rg, CLOUD_PROVIDER_K8S, CLOUD_CAP_FUNCTIONS) == CLOUD_COMPAT_PARTIAL;
  ok = ok && cloud_provider_compat(&rg, CLOUD_PROVIDER_K8S, CLOUD_CAP_DB) == CLOUD_COMPAT_PARTIAL;
  ok = ok && cloud_provider_compat(&rg, CLOUD_PROVIDER_K8S, CLOUD_CAP_QUEUE) == CLOUD_COMPAT_PARTIAL;
  ok = ok && cloud_provider_supports(&rg, CLOUD_PROVIDER_K8S, CLOUD_CAP_DB);
  return assert(ok, "compatibility: k8s is full on compute and partial elsewhere");
}

fn t12() -> TestResult {
  let rg = cloud_registry_new();
  var ok = cloud_provider_compat(&rg, CLOUD_PROVIDER_DOCKER, CLOUD_CAP_FUNCTIONS) == CLOUD_COMPAT_NONE;
  ok = ok && !cloud_provider_supports(&rg, CLOUD_PROVIDER_DOCKER, CLOUD_CAP_FUNCTIONS);
  ok = ok && cloud_provider_supports(&rg, CLOUD_PROVIDER_DOCKER, CLOUD_CAP_DB);
  ok = ok && cloud_provider_compat(&rg, CLOUD_PROVIDER_DOCKER, CLOUD_CAP_COUNT) == CLOUD_COMPAT_NONE;
  ok = ok && cloud_provider_compat(&rg, 99, CLOUD_CAP_COMPUTE) == CLOUD_COMPAT_NONE;
  ok = ok && !cloud_provider_supports(&rg, 99, CLOUD_CAP_COMPUTE);
  return assert(ok, "compatibility: docker functions unsupported; range reads safe");
}

fn t13() -> TestResult {
  let rg = cloud_registry_new();
  var ok = cloud_provider_compat(&rg, CLOUD_PROVIDER_NOMAD, CLOUD_CAP_COMPUTE) == CLOUD_COMPAT_FULL;
  ok = ok && cloud_provider_compat(&rg, CLOUD_PROVIDER_NOMAD, CLOUD_CAP_STORAGE) == CLOUD_COMPAT_PARTIAL;
  ok = ok && cloud_provider_compat(&rg, CLOUD_PROVIDER_NOMAD, CLOUD_CAP_FUNCTIONS) == CLOUD_COMPAT_NONE;
  ok = ok && cloud_provider_compat(&rg, CLOUD_PROVIDER_NOMAD, CLOUD_CAP_DB) == CLOUD_COMPAT_NONE;
  ok = ok && cloud_provider_compat(&rg, CLOUD_PROVIDER_NOMAD, CLOUD_CAP_QUEUE) == CLOUD_COMPAT_NONE;
  return assert(ok, "compatibility: nomad schedules compute, no managed services");
}

fn t14() -> TestResult {
  let rg = cloud_registry_new();
  var ok = cloud_provider_capability_count(&rg, CLOUD_PROVIDER_AWS) == 5;
  ok = ok && cloud_provider_capability_count(&rg, CLOUD_PROVIDER_K8S) == 5;
  ok = ok && cloud_provider_capability_count(&rg, CLOUD_PROVIDER_DOCKER) == 4;
  ok = ok && cloud_provider_capability_count(&rg, CLOUD_PROVIDER_NOMAD) == 2;
  ok = ok && cloud_provider_capability_count(&rg, 99) == 0;
  return assert(ok, "compatibility: non-NONE capability counts per provider");
}

fn t15() -> TestResult {
  let rg = cloud_registry_new();
  var ok = cloud_provider_region_count(&rg, CLOUD_PROVIDER_AWS) == 4;
  ok = ok && cloud_provider_region_count(&rg, CLOUD_PROVIDER_AZURE) == 4;
  ok = ok && cloud_provider_region_count(&rg, CLOUD_PROVIDER_GCP) == 4;
  ok = ok && cloud_provider_region_count(&rg, CLOUD_PROVIDER_K8S) == 0;
  ok = ok && cloud_provider_region_count(&rg, CLOUD_PROVIDER_DOCKER) == 0;
  ok = ok && cloud_provider_region_count(&rg, CLOUD_PROVIDER_NOMAD) == 0;
  ok = ok && cloud_region_count(&rg) == CLOUD_REGION_COUNT;
  ok = ok && CLOUD_REGION_COUNT == 12;
  return assert(ok, "region: 4+4+4 regional providers, orchestrators region-less");
}

fn t16() -> TestResult {
  let rg = cloud_registry_new();
  let rn0: Str = cloud_region_name(&rg, 0);
  let rn4: Str = cloud_region_name(&rg, 4);
  let rn8: Str = cloud_region_name(&rg, 8);
  var ok = streq(rn0, "us-east-1");
  ok = ok && streq(rn4, "eastus");
  ok = ok && streq(rn8, "us-central1");
  ok = ok && cloud_region_owner(&rg, 0) == CLOUD_PROVIDER_AWS;
  ok = ok && cloud_region_owner(&rg, 4) == CLOUD_PROVIDER_AZURE;
  ok = ok && cloud_region_owner(&rg, 8) == CLOUD_PROVIDER_GCP;
  ok = ok && cloud_first_region(&rg, CLOUD_PROVIDER_AWS) == 0;
  ok = ok && cloud_first_region(&rg, CLOUD_PROVIDER_K8S) == CLOUD_NOT_FOUND;
  ok = ok && cloud_first_region(&rg, 99) == CLOUD_NOT_FOUND;
  let rn12: Str = cloud_region_name(&rg, 12);
  ok = ok && string.str_len(rn12) == 0;
  ok = ok && cloud_region_owner(&rg, 12) == CLOUD_NOT_FOUND;
  return assert(ok, "region: names, owners and first-region resolution");
}

fn t17() -> TestResult {
  let rg = cloud_registry_new();
  var ok = int_ok_is(cloud_region_lookup(&rg, CLOUD_PROVIDER_AWS, "eu-west-1"), 2);
  ok = ok && int_ok_is(cloud_region_lookup(&rg, CLOUD_PROVIDER_AZURE, "westus2"), 5);
  ok = ok && int_ok_is(cloud_region_lookup(&rg, CLOUD_PROVIDER_GCP, "asia-southeast1"), 11);
  ok = ok && int_err_is(cloud_region_lookup(&rg, CLOUD_PROVIDER_AWS, "nowhere"), "cloud: unknown region");
  ok = ok && int_err_is(cloud_region_lookup(&rg, CLOUD_PROVIDER_AWS, ""), "cloud: empty region name");
  ok = ok && int_err_is(cloud_region_lookup(&rg, CLOUD_PROVIDER_K8S, "us-east-1"), "cloud: provider has no region model");
  ok = ok && int_err_is(cloud_region_lookup(&rg, 99, "us-east-1"), "cloud: unknown provider");
  return assert(ok, "region: lookup resolves ids and reports explicit errors");
}

fn t18() -> TestResult {
  let rg = cloud_registry_new();
  var ok = cloud_region_valid(&rg, CLOUD_PROVIDER_AWS, "us-east-1");
  ok = ok && !cloud_region_valid(&rg, CLOUD_PROVIDER_AWS, "us-east-2");
  ok = ok && !cloud_region_valid(&rg, CLOUD_PROVIDER_K8S, "us-east-1");
  ok = ok && !cloud_region_valid(&rg, 99, "us-east-1");
  ok = ok && !cloud_region_valid(&rg, CLOUD_PROVIDER_GCP, "");
  return assert(ok, "region: validation predicate mirrors lookup");
}

fn t19() -> TestResult {
  let rg = cloud_registry_new();
  let z00: Str = cloud_zone_name(&rg, 0, 0);
  let z01: Str = cloud_zone_name(&rg, 0, 1);
  let z02: Str = cloud_zone_name(&rg, 0, 2);
  let z40: Str = cloud_zone_name(&rg, 4, 0);
  let z99: Str = cloud_zone_name(&rg, 99, 0);
  var ok = cloud_zone_count(&rg, 0) == 2;
  ok = ok && cloud_zone_count(&rg, 11) == 2;
  ok = ok && cloud_zone_count(&rg, 12) == CLOUD_NOT_FOUND;
  ok = ok && streq(z00, "us-east-1-a");
  ok = ok && streq(z01, "us-east-1-b");
  ok = ok && string.str_len(z02) == 0;
  ok = ok && streq(z40, "eastus-a");
  ok = ok && string.str_len(z99) == 0;
  return assert(ok, "zone: two zones per region, derived names, safe ranges");
}

fn t20() -> TestResult {
  let rg = cloud_registry_new();
  var ok = cloud_zone_owner(&rg, 0, 0) == 0;
  ok = ok && cloud_zone_owner(&rg, 11, 1) == 11;
  ok = ok && cloud_zone_owner(&rg, 0, 2) == CLOUD_NOT_FOUND;
  let z80: Str = cloud_zone_name(&rg, 8, 0);
  ok = ok && string.str_starts_with(z80, "us-central1");
  var total = 0;
  var i = 0;
  while i < cloud_region_count(&rg) {
    total = total + cloud_zone_count(&rg, i);
    i = i + 1;
  }
  ok = ok && total == CLOUD_ZONE_COUNT;
  ok = ok && CLOUD_ZONE_COUNT == 24;
  return assert(ok, "zone: ownership and 24-zone total");
}

fn t21() -> TestResult {
  let rg = cloud_registry_new();
  var ok = cloud_vendor_count(&rg) == CLOUD_VENDOR_COUNT;
  ok = ok && CLOUD_VENDOR_COUNT == 150;
  ok = ok && cloud_vendor_well_known_count(&rg) == CLOUD_WELL_KNOWN_VENDOR_COUNT;
  ok = ok && CLOUD_WELL_KNOWN_VENDOR_COUNT == 30;
  return assert(ok, "vendor: 150 entries with a 30-entry well-known subset");
}

fn t22() -> TestResult {
  let rg = cloud_registry_new();
  let v0: Str = cloud_vendor_name(&rg, 0);
  let v3: Str = cloud_vendor_name(&rg, 3);
  let v29: Str = cloud_vendor_name(&rg, 29);
  let v149: Str = cloud_vendor_name(&rg, 149);
  let v150: Str = cloud_vendor_name(&rg, 150);
  var ok = streq(v0, "aws");
  ok = ok && streq(v3, "kubernetes");
  ok = ok && streq(v29, "cloudstack");
  ok = ok && streq(v149, "liquid-web");
  ok = ok && string.str_len(v150) == 0;
  ok = ok && cloud_vendor_lookup(&rg, "minio") == 129;
  ok = ok && cloud_vendor_lookup(&rg, "openai") == 145;
  ok = ok && cloud_vendor_lookup(&rg, "nope-cloud") == CLOUD_NOT_FOUND;
  ok = ok && cloud_vendor_lookup(&rg, "") == CLOUD_NOT_FOUND;
  return assert(ok, "vendor: names and lookup indices are pinned");
}

fn t23() -> TestResult {
  let rg = cloud_registry_new();
  var ok = cloud_vendor_well_known(&rg, 0);
  ok = ok && cloud_vendor_well_known(&rg, 29);
  ok = ok && !cloud_vendor_well_known(&rg, 30);
  ok = ok && !cloud_vendor_well_known(&rg, 149);
  ok = ok && !cloud_vendor_well_known(&rg, 150);
  ok = ok && cloud_vendor_is_well_known(&rg, "oracle");
  ok = ok && !cloud_vendor_is_well_known(&rg, "minio");
  ok = ok && !cloud_vendor_is_well_known(&rg, "nope-cloud");
  return assert(ok, "vendor: well-known flags distinguish subset from long tail");
}

fn t24() -> TestResult {
  let rg = cloud_registry_new();
  let n = cloud_vendor_count(&rg);
  var dup = false;
  var i = 0;
  while i < n {
    let a: Str = cloud_vendor_name(&rg, i);
    var j = i + 1;
    while j < n {
      let b: Str = cloud_vendor_name(&rg, j);
      if streq(a, b) {
        dup = true;
      }
      j = j + 1;
    }
    i = i + 1;
  }
  return assert(!dup, "vendor: 150 entries are pairwise unique");
}

fn t25() -> TestResult {
  let a = cloud_registry_new();
  let b = cloud_registry_new();
  var ok = true;
  var i = 0;
  while i < CLOUD_PROVIDER_COUNT {
    let an: Str = cloud_provider_name(&a, i);
    let bn: Str = cloud_provider_name(&b, i);
    if !streq(an, bn) {
      ok = false;
    }
    i = i + 1;
  }
  i = 0;
  while i < CLOUD_REGION_COUNT {
    let an: Str = cloud_region_name(&a, i);
    let bn: Str = cloud_region_name(&b, i);
    if !streq(an, bn) {
      ok = false;
    }
    i = i + 1;
  }
  i = 0;
  while i < CLOUD_VENDOR_COUNT {
    let an: Str = cloud_vendor_name(&a, i);
    let bn: Str = cloud_vendor_name(&b, i);
    if !streq(an, bn) {
      ok = false;
    }
    i = i + 1;
  }
  var p = 0;
  while p < CLOUD_PROVIDER_COUNT {
    let da: Str = cloud_describe_provider(&a, p);
    let db: Str = cloud_describe_provider(&b, p);
    if !streq(da, db) {
      ok = false;
    }
    p = p + 1;
  }
  return assert(ok, "registry: two builds are byte-for-byte identical");
}

fn t26() -> TestResult {
  let rg = cloud_registry_new();
  var ok = cloud_registry_consistent(&rg);
  let da: Str = cloud_describe_provider(&rg, CLOUD_PROVIDER_AWS);
  let dk: Str = cloud_describe_provider(&rg, CLOUD_PROVIDER_K8S);
  let dx: Str = cloud_describe_provider(&rg, 99);
  ok = ok && streq(da, "aws: public-cloud, 4 regions, 5/5 capabilities");
  ok = ok && streq(dk, "k8s: orchestrator, 0 regions, 5/5 capabilities");
  ok = ok && streq(dx, "cloud: unknown provider");
  var i = 0;
  while i < CLOUD_PROVIDER_COUNT {
    let nm: Str = cloud_provider_name(&rg, i);
    if !str_nonempty(nm) {
      ok = false;
    }
    i = i + 1;
  }
  i = 0;
  while i < CLOUD_REGION_COUNT {
    let nm: Str = cloud_region_name(&rg, i);
    if !str_nonempty(nm) {
      ok = false;
    }
    i = i + 1;
  }
  i = 0;
  while i < CLOUD_VENDOR_COUNT {
    let nm: Str = cloud_vendor_name(&rg, i);
    if !str_nonempty(nm) {
      ok = false;
    }
    i = i + 1;
  }
  return assert(ok, "registry: structural invariants and provider summaries");
}

// --------------------------------------------------
//  Harness
// --------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.cloud conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.cloud: all tests passed");
  } else {
    io.println("xiom.cloud: tests failed");
  }
  return failed;
}
