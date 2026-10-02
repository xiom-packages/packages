// XIOM -- xiom.gcp conformance tests (28 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Proves the pure-XIOM GCP model documented in SPEC.md: resource-name grammar,
// service registry, GCS, GCE, Cloud Functions, BigQuery, Pub/Sub and the
// service-account auth shapes. Every check is a named assert(cond, "name")
// call, one fn per check, and main returns the failure count (0 = green).
// No network, no clocks, no crypto: every vector is a fixed known answer.
//
// BUG-17 discipline: Str equality goes through compare.str_compare, every
// Vec element read is bound to a typed local, and result payloads are bound
// before their fields are read.

module gcp_tests

use xiom.io; use xiom.test;
use xiom.gcp; use xiom.gcp.core; use xiom.gcp.storage; use xiom.gcp.compute;
use xiom.gcp.cloudfunctions; use xiom.gcp.bigquery; use xiom.gcp.pubsub;
use xiom.gcp.auth;
use xiom.string; use xiom.string.builder; use xiom.string.compare;

// --------------------------------------------------
//  Helpers
// --------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn str_ok_is(r: Result[Str, Str], want: Str) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Str = r.value;
  return streq(v, want);
}

fn str_err_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return streq(m, want);
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

fn res_ok_is(r: Result[GcpResource, Str], project: Str, kind: Str, location: Str, name: Str) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: GcpResource = r.value;
  let gp: Str = v.project;
  let gk: Str = v.kind;
  let gl: Str = v.location;
  let gn: Str = v.name;
  if !streq(gp, project) {
    return false;
  }
  if !streq(gk, kind) {
    return false;
  }
  if !streq(gl, location) {
    return false;
  }
  return streq(gn, name);
}

fn res_err_is(r: Result[GcpResource, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return streq(m, want);
}

fn mt_ok_is(r: Result[GceMachineType, Str], family: Str, series: Str, size: Str) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: GceMachineType = r.value;
  let gf: Str = v.family;
  let gs: Str = v.series;
  let gz: Str = v.size;
  if !streq(gf, family) {
    return false;
  }
  if !streq(gs, series) {
    return false;
  }
  return streq(gz, size);
}

fn mt_err_is(r: Result[GceMachineType, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return streq(m, want);
}

fn page_ok_is(r: Result[BqPage, Str], offset: Int, count: Int, total: Int, more: Bool) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: BqPage = r.value;
  let go: Int = v.offset;
  let gc: Int = v.count;
  let gt: Int = v.total;
  let gm: Bool = v.has_more;
  if go != offset {
    return false;
  }
  if gc != count {
    return false;
  }
  if gt != total {
    return false;
  }
  return gm == more;
}

fn page_err_is(r: Result[BqPage, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return streq(m, want);
}

fn token_ok_is(r: Result[GcaToken, Str], access: Str, expires: Int, ttype: Str) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: GcaToken = r.value;
  let ga: Str = v.access_token;
  let ge: Int = v.expires_in;
  let gtt: Str = v.token_type;
  if !streq(ga, access) {
    return false;
  }
  if ge != expires {
    return false;
  }
  return streq(gtt, ttype);
}

fn tok_err_is(r: Result[GcaToken, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return streq(m, want);
}

// --------------------------------------------------
//  Resource names and the service registry
// --------------------------------------------------

fn t1() -> TestResult {
  let p1 = gcp.gcp_project_path("my-proj-1");
  var ok = str_ok_is(p1, "projects/my-proj-1");
  let p2 = gcp.gcp_zone_path("my-proj-1", "us-central1-a");
  ok = ok && str_ok_is(p2, "projects/my-proj-1/zones/us-central1-a");
  let p3 = gcp.gcp_region_path("my-proj-1", "europe-west1");
  ok = ok && str_ok_is(p3, "projects/my-proj-1/locations/europe-west1");
  let p4 = gcp.gcp_global_path("my-proj-1");
  ok = ok && str_ok_is(p4, "projects/my-proj-1/global");
  let e1 = gcp.gcp_project_path("Bad_Project");
  ok = ok && str_err_is(e1, "gcp: invalid project id: Bad_Project");
  return assert(ok, "resource: project/zone/region/global paths and invalid project");
}

fn t2() -> TestResult {
  var ok = gcp.gcp_project_id_is_valid("alpha-1");
  ok = ok && !gcp.gcp_project_id_is_valid("abc");
  ok = ok && !gcp.gcp_project_id_is_valid("1abcdef");
  ok = ok && !gcp.gcp_project_id_is_valid("abcdef-");
  ok = ok && gcp.gcp_zone_is_valid("us-central1-a");
  ok = ok && !gcp.gcp_zone_is_valid("us-central1");
  ok = ok && !gcp.gcp_zone_is_valid("us-central1-ab");
  ok = ok && gcp.gcp_region_is_valid("europe-west12");
  ok = ok && !gcp.gcp_region_is_valid("-europe");
  let rz = gcp.gcp_region_of_zone("us-central1-a");
  ok = ok && str_ok_is(rz, "us-central1");
  let re = gcp.gcp_region_of_zone("us-central1");
  ok = ok && str_err_is(re, "gcp: invalid zone: us-central1");
  return assert(ok, "resource: project/region/zone validators and zone->region");
}

fn t3() -> TestResult {
  let r1 = gcp.gcp_parse_resource("projects/my-proj-1/zones/us-central1-a/instances/vm-1");
  var ok = res_ok_is(r1, "my-proj-1", "instances", "us-central1-a", "vm-1");
  let r2 = gcp.gcp_parse_resource("projects/my-proj-1/topics/events");
  ok = ok && res_ok_is(r2, "my-proj-1", "topics", "", "events");
  let r3 = gcp.gcp_parse_resource("projects/my-proj-1/global/networks/default");
  ok = ok && res_ok_is(r3, "my-proj-1", "networks", "global", "default");
  let r4 = gcp.gcp_parse_resource("projects/my-proj-1/locations/europe-west1/cloudfunctions/fn-1");
  ok = ok && res_ok_is(r4, "my-proj-1", "cloudfunctions", "europe-west1", "fn-1");
  let e1 = gcp.gcp_parse_resource("organizations/123");
  ok = ok && res_err_is(e1, "gcp: resource path must start with projects/");
  let e2 = gcp.gcp_parse_resource("projects/my-proj-1/zones/us-central1-a/instances/vm-1/extra");
  ok = ok && res_err_is(e2, "gcp: unsupported resource path");
  return assert(ok, "resource: parse zone/region/global paths and error forms");
}

fn t4() -> TestResult {
  var ok = gcp.gcp_service_code("storage") == gcp.GCP_SERVICE_STORAGE;
  ok = ok && gcp.gcp_service_code("cloudfunctions") == 3;
  ok = ok && gcp.gcp_service_code("nope") == 0;
  let h = gcp.gcp_service_host(2);
  ok = ok && str_ok_is(h, "compute.googleapis.com");
  let v = gcp.gcp_service_api_version(4);
  ok = ok && str_ok_is(v, "v2");
  let b = gcp.gcp_endpoint_base(1);
  ok = ok && str_ok_is(b, "https://storage.googleapis.com/v1");
  ok = ok && gcp.gcp_service_is_global(1);
  ok = ok && !gcp.gcp_service_is_global(2);
  let n = gcp.gcp_service_name(99);
  ok = ok && str_err_is(n, "gcp: unknown service code: 99");
  return assert(ok, "registry: service codes, hosts, versions and endpoints");
}

// --------------------------------------------------
//  Cloud Storage
// --------------------------------------------------

fn t5() -> TestResult {
  var ok = storage.gcs_bucket_name_is_valid("my-bucket-1");
  ok = ok && !storage.gcs_bucket_name_is_valid("ab");
  ok = ok && !storage.gcs_bucket_name_is_valid("-bucket");
  ok = ok && !storage.gcs_bucket_name_is_valid("bucket..x");
  ok = ok && !storage.gcs_bucket_name_is_valid("google-bucket");
  ok = ok && !storage.gcs_bucket_name_is_valid("goog-bucket");
  let p = storage.gcs_bucket_path("my-bucket-1");
  ok = ok && str_ok_is(p, "b/my-bucket-1");
  return assert(ok, "gcs: bucket names and bucket path");
}

fn t6() -> TestResult {
  var ok = storage.gcs_object_name_is_valid("dir/file.txt");
  ok = ok && !storage.gcs_object_name_is_valid("");
  ok = ok && !storage.gcs_object_name_is_valid(".");
  ok = ok && !storage.gcs_object_name_is_valid("..");
  ok = ok && !storage.gcs_object_name_is_valid("a\nb");
  let op = storage.gcs_object_path("my-bucket-1", "dir/my file.txt");
  ok = ok && str_ok_is(op, "b/my-bucket-1/o/dir/my%20file.txt");
  let gp = storage.gcs_generation_path("my-bucket-1", "a.txt", 42);
  ok = ok && str_ok_is(gp, "b/my-bucket-1/o/a.txt?generation=42");
  let ge = storage.gcs_generation_path("my-bucket-1", "a.txt", 0);
  ok = ok && str_err_is(ge, "gcp: invalid generation: 0");
  return assert(ok, "gcs: object names, encoded object path and generations");
}

fn t7() -> TestResult {
  let p0 = storage.gcs_preconditions_none();
  var ok = str_ok_is(storage.gcs_preconditions_query(&p0), "");
  let p1 = GcsPreconditions{
    if_generation_match: 5;
    if_generation_not_match: 0;
    if_metageneration_match: 2;
    if_metageneration_not_match: 0;
  };
  ok = ok && str_ok_is(storage.gcs_preconditions_query(&p1), "?ifGenerationMatch=5&ifMetagenerationMatch=2");
  let p2 = GcsPreconditions{
    if_generation_match: 5;
    if_generation_not_match: 7;
    if_metageneration_match: 0;
    if_metageneration_not_match: 0;
  };
  ok = ok && str_err_is(storage.gcs_preconditions_query(&p2), "gcp: ifGenerationMatch and ifGenerationNotMatch conflict");
  let p3 = GcsPreconditions{
    if_generation_match: -1;
    if_generation_not_match: 0;
    if_metageneration_match: 0;
    if_metageneration_not_match: 0;
  };
  ok = ok && str_err_is(storage.gcs_preconditions_query(&p3), "gcp: negative ifGenerationMatch");
  return assert(ok, "gcs: precondition query and conflict rules");
}

fn t8() -> TestResult {
  var ok = storage.gcs_acl_role_is_valid("READER");
  ok = ok && storage.gcs_acl_role_is_valid("OWNER");
  ok = ok && !storage.gcs_acl_role_is_valid("ADMIN");
  ok = ok && storage.gcs_acl_entity_is_valid("allUsers");
  ok = ok && storage.gcs_acl_entity_is_valid("user-ada@example.com");
  ok = ok && storage.gcs_acl_entity_is_valid("project-team-123");
  ok = ok && !storage.gcs_acl_entity_is_valid("user-");
  ok = ok && !storage.gcs_acl_entity_is_valid("project-xyz");
  let v1 = storage.gcs_acl_entry_validate("user-ada@example.com", "READER");
  ok = ok && str_ok_is(v1, "");
  let v2 = storage.gcs_acl_entry_validate("nobody", "READER");
  ok = ok && str_err_is(v2, "gcp: invalid ACL entity: nobody");
  return assert(ok, "gcs: ACL roles, entities and entry validation");
}

// --------------------------------------------------
//  Compute Engine
// --------------------------------------------------

fn t9() -> TestResult {
  var ok = compute.gce_status_code("RUNNING") == compute.GCE_STATUS_RUNNING;
  ok = ok && compute.gce_status_code("NOPE") == 0;
  let n = compute.gce_status_name(6);
  ok = ok && str_ok_is(n, "SUSPENDED");
  let e = compute.gce_status_name(42);
  ok = ok && str_err_is(e, "gcp: unknown instance status code: 42");
  return assert(ok, "gce: status code/name dispatch");
}

fn t10() -> TestResult {
  var ok = compute.gce_transition_allowed(1, 2);
  ok = ok && compute.gce_transition_allowed(2, 3);
  ok = ok && compute.gce_transition_allowed(3, 4);
  ok = ok && compute.gce_transition_allowed(3, 5);
  ok = ok && compute.gce_transition_allowed(5, 6);
  ok = ok && compute.gce_transition_allowed(6, 3);
  ok = ok && compute.gce_transition_allowed(4, 8);
  ok = ok && compute.gce_transition_allowed(7, 3);
  ok = ok && compute.gce_transition_allowed(8, 1);
  ok = ok && !compute.gce_transition_allowed(3, 1);
  ok = ok && !compute.gce_transition_allowed(1, 3);
  ok = ok && !compute.gce_transition_allowed(3, 8);
  return assert(ok, "gce: instance lifecycle transitions");
}

fn t11() -> TestResult {
  var ok = compute.gce_machine_type_is_valid("n1-standard-4");
  ok = ok && compute.gce_machine_type_is_valid("e2-micro");
  ok = ok && compute.gce_machine_type_is_valid("custom-8-16384");
  ok = ok && !compute.gce_machine_type_is_valid("x9-standard-1");
  ok = ok && !compute.gce_machine_type_is_valid("n1-");
  let m1 = compute.gce_machine_type_parse("n1-standard-4");
  ok = ok && mt_ok_is(m1, "n1", "standard", "4");
  let m2 = compute.gce_machine_type_parse("e2-micro");
  ok = ok && mt_ok_is(m2, "e2", "micro", "");
  let m3 = compute.gce_machine_type_parse("custom-8-16384");
  ok = ok && mt_ok_is(m3, "custom", "8", "16384");
  let me = compute.gce_machine_type_parse("x9-standard-1");
  ok = ok && mt_err_is(me, "gcp: invalid machine type: x9-standard-1");
  let p = compute.gce_machine_type_path("my-proj-1", "us-central1-a", "n1-standard-4");
  ok = ok && str_ok_is(p, "projects/my-proj-1/zones/us-central1-a/machineTypes/n1-standard-4");
  return assert(ok, "gce: machine type validation, parse and path");
}

fn t12() -> TestResult {
  var ok = compute.gce_metadata_key_is_valid("startup-script");
  ok = ok && compute.gce_metadata_key_is_valid("my-key-1");
  ok = ok && !compute.gce_metadata_key_is_valid("Google-Key");
  ok = ok && !compute.gce_metadata_key_is_valid("ssh-keys");
  ok = ok && !compute.gce_metadata_key_is_valid("google-sudo");
  ok = ok && !compute.gce_metadata_key_is_valid("-bad");
  let v1 = compute.gce_metadata_validate("startup-script", "echo hi");
  ok = ok && str_ok_is(v1, "");
  let v2 = compute.gce_metadata_validate("ssh-keys", "x");
  ok = ok && str_err_is(v2, "gcp: invalid metadata key: ssh-keys");
  ok = ok && compute.gce_instance_name_is_valid("vm-1");
  ok = ok && !compute.gce_instance_name_is_valid("VM_1");
  let ip = compute.gce_instance_path("my-proj-1", "us-central1-a", "vm-1");
  ok = ok && str_ok_is(ip, "projects/my-proj-1/zones/us-central1-a/instances/vm-1");
  return assert(ok, "gce: metadata keys and instance naming/path");
}

// --------------------------------------------------
//  Cloud Functions
// --------------------------------------------------

fn t13() -> TestResult {
  var ok = cloudfunctions.gcf_runtime_code("python312") == 5;
  ok = ok && cloudfunctions.gcf_runtime_is_valid("go122");
  ok = ok && !cloudfunctions.gcf_runtime_is_valid("cobol99");
  let n = cloudfunctions.gcf_runtime_name(1);
  ok = ok && str_ok_is(n, "nodejs20");
  let l1 = cloudfunctions.gcf_runtime_language("python311");
  ok = ok && str_ok_is(l1, "python");
  let l2 = cloudfunctions.gcf_runtime_language("dotnet8");
  ok = ok && str_ok_is(l2, "dotnet");
  ok = ok && cloudfunctions.gcf_runtime_is_gen2("python312");
  ok = ok && !cloudfunctions.gcf_runtime_is_gen2("python310");
  let e = cloudfunctions.gcf_runtime_language("rust1");
  ok = ok && str_err_is(e, "gcp: invalid runtime: rust1");
  return assert(ok, "cloudfunctions: runtime registry, language and generation");
}

fn t14() -> TestResult {
  let v1 = cloudfunctions.gcf_trigger_validate(1, "", "", false);
  var ok = str_ok_is(v1, "");
  let v2 = cloudfunctions.gcf_trigger_validate(1, "google.pubsub", "", false);
  ok = ok && str_err_is(v2, "gcp: HTTP trigger must not carry an event type");
  let v3 = cloudfunctions.gcf_trigger_validate(2, "google.cloud.pubsub.topic.v1.messagePublished", "projects/p/topics/t", true);
  ok = ok && str_ok_is(v3, "");
  let v4 = cloudfunctions.gcf_trigger_validate(2, "no-dots", "projects/p/topics/t", false);
  ok = ok && str_err_is(v4, "gcp: invalid event type: no-dots");
  let v5 = cloudfunctions.gcf_trigger_validate(2, "a.b", "nopath", false);
  ok = ok && str_err_is(v5, "gcp: invalid trigger resource: nopath");
  let v6 = cloudfunctions.gcf_trigger_validate(9, "", "", false);
  ok = ok && str_err_is(v6, "gcp: unknown trigger kind: 9");
  return assert(ok, "cloudfunctions: HTTP/event trigger validation");
}

fn t15() -> TestResult {
  var ok = cloudfunctions.gcf_entry_point_is_valid("helloHttp");
  ok = ok && cloudfunctions.gcf_entry_point_is_valid("_handler_1");
  ok = ok && !cloudfunctions.gcf_entry_point_is_valid("1handler");
  ok = ok && !cloudfunctions.gcf_entry_point_is_valid("");
  let d = GcfDeploy{
    name: "fn-1";
    runtime: "python312";
    entry_point: "handler";
    memory_mb: 256;
    timeout_sec: 60;
    max_instances: 10;
    trigger_kind: 1;
    event_type: "";
    resource: "";
    retry: false;
  };
  let v1 = cloudfunctions.gcf_deploy_validate(&d);
  ok = ok && str_ok_is(v1, "");
  let bad = GcfDeploy{
    name: "fn-1";
    runtime: "cobol99";
    entry_point: "handler";
    memory_mb: 256;
    timeout_sec: 60;
    max_instances: 10;
    trigger_kind: 1;
    event_type: "";
    resource: "";
    retry: false;
  };
  let v2 = cloudfunctions.gcf_deploy_validate(&bad);
  ok = ok && str_err_is(v2, "gcp: invalid runtime: cobol99");
  let small = GcfDeploy{
    name: "fn-1";
    runtime: "python312";
    entry_point: "handler";
    memory_mb: 64;
    timeout_sec: 60;
    max_instances: 10;
    trigger_kind: 1;
    event_type: "";
    resource: "";
    retry: false;
  };
  let v3 = cloudfunctions.gcf_deploy_validate(&small);
  ok = ok && str_err_is(v3, "gcp: memory below 128 MB");
  return assert(ok, "cloudfunctions: entry point and deploy validation");
}

fn t16() -> TestResult {
  let p = cloudfunctions.gcf_deploy_path("my-proj-1", "europe-west1", "fn-1");
  var ok = str_ok_is(p, "projects/my-proj-1/locations/europe-west1/functions/fn-1");
  ok = ok && cloudfunctions.gcf_invoke_class(200, false) == 1;
  ok = ok && cloudfunctions.gcf_invoke_class(200, true) == 2;
  ok = ok && cloudfunctions.gcf_invoke_class(503, false) == 3;
  ok = ok && cloudfunctions.gcf_invoke_class(504, false) == 4;
  ok = ok && cloudfunctions.gcf_invoke_class(42, false) == 0;
  let u = cloudfunctions.gcf_invoke_url("europe-west1", "my-proj-1", "fn-1");
  ok = ok && str_ok_is(u, "https://europe-west1-my-proj-1.cloudfunctions.net/fn-1");
  return assert(ok, "cloudfunctions: deploy path, invoke class and gen1 URL");
}

// --------------------------------------------------
//  BigQuery
// --------------------------------------------------

fn t17() -> TestResult {
  var ok = bigquery.bq_dataset_id_is_valid("analytics_1");
  ok = ok && !bigquery.bq_dataset_id_is_valid("1bad");
  ok = ok && bigquery.bq_table_id_is_valid("events");
  ok = ok && bigquery.bq_field_name_is_valid("user_id");
  ok = ok && !bigquery.bq_field_name_is_valid("bad-name");
  let q = bigquery.bq_qualified_name("my-proj-1", "analytics_1", "events");
  ok = ok && str_ok_is(q, "my-proj-1.analytics_1.events");
  let e = bigquery.bq_qualified_name("my-proj-1", "bad-id", "events");
  ok = ok && str_err_is(e, "gcp: invalid dataset id: bad-id");
  return assert(ok, "bigquery: identifier rules and qualified names");
}

fn t18() -> TestResult {
  var ok = bigquery.bq_type_code("TIMESTAMP") == 8;
  ok = ok && bigquery.bq_type_code("NOPE") == 0;
  let tn = bigquery.bq_type_name(14);
  ok = ok && str_ok_is(tn, "RECORD");
  let fv = bigquery.bq_field_validate("id", 3, 2);
  ok = ok && str_ok_is(fv, "");
  let fe = bigquery.bq_field_validate("id", 99, 1);
  ok = ok && str_err_is(fe, "gcp: invalid field type code: 99");
  var names = Vec[Str].new();
  names.push("id");
  names.push("name");
  var types = Vec[Int].new();
  types.push(3);
  types.push(1);
  var modes = Vec[Int].new();
  modes.push(2);
  modes.push(1);
  let sv = bigquery.bq_schema_validate(&names, &types, &modes);
  ok = ok && str_ok_is(sv, "");
  var dup = Vec[Str].new();
  dup.push("id");
  dup.push("ID");
  var dup_types = Vec[Int].new();
  dup_types.push(3);
  dup_types.push(3);
  var dup_modes = Vec[Int].new();
  dup_modes.push(1);
  dup_modes.push(1);
  let de = bigquery.bq_schema_validate(&dup, &dup_types, &dup_modes);
  ok = ok && str_err_is(de, "gcp: duplicate field name: ID");
  var short_modes = Vec[Int].new();
  short_modes.push(1);
  let se = bigquery.bq_schema_validate(&names, &types, &short_modes);
  ok = ok && str_err_is(se, "gcp: schema names/modes length mismatch");
  return assert(ok, "bigquery: type registry and schema validation");
}

fn t19() -> TestResult {
  let r1 = bigquery.bq_page_frame(0, 100, 250);
  var ok = page_ok_is(r1, 0, 100, 250, true);
  if r1.is_ok {
    let pv: BqPage = r1.value;
    ok = ok && streq(bigquery.bq_page_token(&pv), "offset=100");
  } else {
    ok = false;
  }
  let r2 = bigquery.bq_page_frame(200, 100, 250);
  ok = ok && page_ok_is(r2, 200, 50, 250, false);
  let r3 = bigquery.bq_page_frame(250, 100, 250);
  ok = ok && page_ok_is(r3, 250, 0, 250, false);
  let e1 = bigquery.bq_page_frame(251, 100, 250);
  ok = ok && page_err_is(e1, "gcp: page offset beyond row total");
  let e2 = bigquery.bq_page_frame(0, 0, 250);
  ok = ok && page_err_is(e2, "gcp: page size below 1");
  return assert(ok, "bigquery: row-page framing and next-page token");
}

fn t20() -> TestResult {
  var ok = bigquery.bq_job_type_code("QUERY") == 1;
  let tn = bigquery.bq_job_type_name(4);
  ok = ok && str_ok_is(tn, "COPY");
  ok = ok && bigquery.bq_job_state_code("RUNNING") == 2;
  let sn = bigquery.bq_job_state_name(3);
  ok = ok && str_ok_is(sn, "DONE");
  ok = ok && bigquery.bq_job_transition_allowed(1, 2);
  ok = ok && bigquery.bq_job_transition_allowed(2, 3);
  ok = ok && !bigquery.bq_job_transition_allowed(3, 2);
  ok = ok && bigquery.bq_job_id_is_valid("job_1");
  let jp = bigquery.bq_job_path("my-proj-1", "job_1");
  ok = ok && str_ok_is(jp, "projects/my-proj-1/jobs/job_1");
  let te = bigquery.bq_job_type_name(9);
  ok = ok && str_err_is(te, "gcp: unknown job type code: 9");
  return assert(ok, "bigquery: job types, states and transitions");
}

// --------------------------------------------------
//  Pub/Sub
// --------------------------------------------------

fn t21() -> TestResult {
  var ok = pubsub.ps_resource_name_is_valid("event-topic");
  ok = ok && pubsub.ps_resource_name_is_valid("my.topic+1");
  ok = ok && !pubsub.ps_resource_name_is_valid("1topic");
  ok = ok && !pubsub.ps_resource_name_is_valid("ab");
  let tp = pubsub.ps_topic_path("my-proj-1", "event-topic");
  ok = ok && str_ok_is(tp, "projects/my-proj-1/topics/event-topic");
  let sp = pubsub.ps_subscription_path("my-proj-1", "sub-1");
  ok = ok && str_ok_is(sp, "projects/my-proj-1/subscriptions/sub-1");
  let te = pubsub.ps_topic_path("my-proj-1", "1bad");
  ok = ok && str_err_is(te, "gcp: invalid topic name: 1bad");
  return assert(ok, "pubsub: topic/subscription names and paths");
}

fn t22() -> TestResult {
  var data = Vec[UInt8].new();
  data.push(104 as UInt8);
  var an = Vec[Str].new();
  an.push("origin");
  var av = Vec[Str].new();
  av.push("web");
  let v1 = pubsub.ps_publish_validate(&data, &an, &av, "key-1");
  var ok = str_ok_is(v1, "");
  var bad = Vec[Str].new();
  bad.push("googClient");
  let v2 = pubsub.ps_publish_validate(&data, &bad, &av, "");
  ok = ok && str_err_is(v2, "gcp: reserved attribute prefix: googClient");
  var av2 = Vec[Str].new();
  av2.push("a");
  av2.push("b");
  let v3 = pubsub.ps_publish_validate(&data, &an, &av2, "");
  ok = ok && str_err_is(v3, "gcp: attribute name/value count mismatch");
  var empty = Vec[UInt8].new();
  let v4 = pubsub.ps_publish_validate(&empty, &an, &av, "");
  ok = ok && str_err_is(v4, "gcp: empty message data");
  return assert(ok, "pubsub: publish validation and reserved attributes");
}

fn t23() -> TestResult {
  var ok = pubsub.ps_ack_id_is_valid("ack-1");
  ok = ok && !pubsub.ps_ack_id_is_valid("bad id");
  ok = ok && pubsub.ps_ack_deadline_is_valid(10);
  ok = ok && pubsub.ps_ack_deadline_is_valid(600);
  ok = ok && !pubsub.ps_ack_deadline_is_valid(9);
  ok = ok && !pubsub.ps_ack_deadline_is_valid(601);
  ok = ok && pubsub.ps_ack_deadline_clamp(3) == 10;
  ok = ok && pubsub.ps_ack_deadline_clamp(999) == 600;
  ok = ok && pubsub.ps_ack_deadline_clamp(120) == 120;
  let x1 = pubsub.ps_ack_deadline_extend(500, 300);
  ok = ok && int_ok_is(x1, 600);
  let x2 = pubsub.ps_ack_deadline_extend(500, 700);
  ok = ok && int_err_is(x2, "gcp: extension out of 0..600: 700");
  return assert(ok, "pubsub: ack ids, deadline clamp and extension");
}

fn t24() -> TestResult {
  let v1 = pubsub.ps_subscription_validate(1, 60, 3600, "");
  var ok = str_ok_is(v1, "");
  let v2 = pubsub.ps_subscription_validate(2, 30, 600, "https://example.com/push");
  ok = ok && str_ok_is(v2, "");
  let v3 = pubsub.ps_subscription_validate(1, 60, 3600, "https://example.com");
  ok = ok && str_err_is(v3, "gcp: pull subscription must not carry a push endpoint");
  let v4 = pubsub.ps_subscription_validate(2, 30, 600, "http://example.com");
  ok = ok && str_err_is(v4, "gcp: push endpoint must be https");
  let v5 = pubsub.ps_subscription_validate(1, 5, 3600, "");
  ok = ok && str_err_is(v5, "gcp: ack deadline out of 10..600: 5");
  let v6 = pubsub.ps_subscription_validate(1, 60, 100, "");
  ok = ok && str_err_is(v6, "gcp: retention below 600 s");
  return assert(ok, "pubsub: pull/push subscription validation");
}

// --------------------------------------------------
//  Auth model
// --------------------------------------------------

fn t25() -> TestResult {
  let k = GcaServiceAccountKey{
    key_type: "service_account";
    project_id: "my-proj-1";
    private_key_id: "kid-1";
    private_key: "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkq\n-----END PRIVATE KEY-----";
    client_email: "svc@my-proj-1.iam.gserviceaccount.com";
    client_id: "123456789";
    token_uri: "https://oauth2.googleapis.com/token";
  };
  let v1 = auth.gca_service_account_key_validate(&k);
  var ok = str_ok_is(v1, "");
  let bad = GcaServiceAccountKey{
    key_type: "authorized_user";
    project_id: "my-proj-1";
    private_key_id: "kid-1";
    private_key: "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkq\n-----END PRIVATE KEY-----";
    client_email: "svc@my-proj-1.iam.gserviceaccount.com";
    client_id: "123456789";
    token_uri: "https://oauth2.googleapis.com/token";
  };
  let v2 = auth.gca_service_account_key_validate(&bad);
  ok = ok && str_err_is(v2, "gcp: key_type must be service_account");
  let bad2 = GcaServiceAccountKey{
    key_type: "service_account";
    project_id: "my-proj-1";
    private_key_id: "kid-1";
    private_key: "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkq\n-----END PRIVATE KEY-----";
    client_email: "foo@example.com";
    client_id: "123456789";
    token_uri: "https://oauth2.googleapis.com/token";
  };
  let v3 = auth.gca_service_account_key_validate(&bad2);
  ok = ok && str_err_is(v3, "gcp: client_email is not a service account: foo@example.com");
  return assert(ok, "auth: service-account key shape");
}

fn t26() -> TestResult {
  var ok = auth.gca_scope_is_valid(auth.GCA_SCOPE_CLOUD_PLATFORM);
  ok = ok && auth.gca_scope_is_valid("https://www.googleapis.com/auth/devstorage.read_only");
  ok = ok && !auth.gca_scope_is_valid("https://example.com/auth/x");
  ok = ok && !auth.gca_scope_is_valid("https://www.googleapis.com/auth/");
  var scopes = Vec[Str].new();
  scopes.push(auth.GCA_SCOPE_CLOUD_PLATFORM);
  scopes.push(auth.GCA_SCOPE_PUBSUB);
  let j = auth.gca_scope_list_join(&scopes);
  ok = ok && str_ok_is(j, "https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/pubsub");
  ok = ok && auth.gca_scope_list_has(&scopes, auth.GCA_SCOPE_PUBSUB);
  ok = ok && !auth.gca_scope_list_has(&scopes, auth.GCA_SCOPE_COMPUTE);
  var badscopes = Vec[Str].new();
  badscopes.push("nope");
  let be = auth.gca_scope_list_join(&badscopes);
  ok = ok && str_err_is(be, "gcp: invalid scope: nope");
  return assert(ok, "auth: OAuth scope validation and joining");
}

fn t27() -> TestResult {
  let j = "{\"access_token\":\"ya29.abc\",\"expires_in\":3599,\"token_type\":\"Bearer\"}";
  let r = auth.gca_token_json_parse(j);
  var ok = token_ok_is(r, "ya29.abc", 3599, "Bearer");
  if r.is_ok {
    let t: GcaToken = r.value;
    ok = ok && auth.gca_token_is_valid(&t);
  } else {
    ok = false;
  }
  let badj = "{\"access_token\":\"x\",\"token_type\":\"Bearer\"}";
  let re = auth.gca_token_json_parse(badj);
  ok = ok && tok_err_is(re, "gcp: token JSON missing field: expires_in");
  let weird = "{\"access_token\":\"a\\\"b\",\"expires_in\":60,\"token_type\":\"Bearer\"}";
  let rw = auth.gca_token_json_parse(weird);
  ok = ok && token_ok_is(rw, "a\"b", 60, "Bearer");
  return assert(ok, "auth: flat token-envelope JSON parsing");
}

fn t28() -> TestResult {
  let c = GcaJwtClaims{
    issuer: "svc@my-proj-1.iam.gserviceaccount.com";
    scope: "https://www.googleapis.com/auth/cloud-platform";
    audience: "https://oauth2.googleapis.com/token";
    issued_at: 1700000000;
    expires_at: 1700003600;
  };
  let v = auth.gca_jwt_claims_validate(&c);
  var ok = str_ok_is(v, "");
  let rendered = auth.gca_jwt_claims_json(&c);
  let want = "{\"iss\":\"svc@my-proj-1.iam.gserviceaccount.com\",\"scope\":\"https://www.googleapis.com/auth/cloud-platform\",\"aud\":\"https://oauth2.googleapis.com/token\",\"iat\":1700000000,\"exp\":1700003600}";
  ok = ok && str_ok_is(rendered, want);
  let badc = GcaJwtClaims{
    issuer: "svc@my-proj-1.iam.gserviceaccount.com";
    scope: "https://www.googleapis.com/auth/cloud-platform";
    audience: "https://oauth2.googleapis.com/token";
    issued_at: 1700000000;
    expires_at: 1700010000;
  };
  let bv = auth.gca_jwt_claims_validate(&badc);
  ok = ok && str_err_is(bv, "gcp: jwt lifetime above 3600 s");
  ok = ok && !auth.gca_jwt_signing_supported();
  return assert(ok, "auth: JWT claim-set validation, rendering and no-signing boundary");
}

// --------------------------------------------------
//  Harness
// --------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.gcp conformance tests ===");
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
    io.println("xiom.gcp: all tests passed");
  } else {
    io.println("xiom.gcp: tests failed");
  }
  return failed;
}
