// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// XIOM -- xiom.azure conformance tests (24 checks)
// Port task: prove the pure-XIOM Azure provider model documented in SPEC.md.
// Every check is a named assert(cond, "name") call, one fn per check, and main
// returns the failure count (0 = green).
//
// BUG-17 discipline: Str equality goes through compare.str_compare, every
// Vec element read is bound to a typed local, and struct fields are bound to
// typed locals before use.

module azure_tests

use xiom.io;
use xiom.test;
use xiom.azure;
use xiom.azure.base;
use xiom.azure.arm;
use xiom.azure.storage;
use xiom.azure.compute;
use xiom.azure.functions;
use xiom.azure.cosmos;
use xiom.azure.servicebus;
use xiom.azure.auth;
use xiom.string.compare;

// --------------------------------------------------
//  Helpers
// --------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn rid_err_is(r: Result[ArmResourceId, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return streq(m, want);
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

fn size_ok_is(r: Result[AzureVmSize, Str], name: Str, vcpus: Int, mem: Int, disks: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  let s: AzureVmSize = r.value;
  let gn: Str = s.name;
  let gv: Int = s.vcpus;
  let gm: Int = s.memory_mb;
  let gd: Int = s.max_data_disks;
  return streq(gn, name) && gv == vcpus && gm == mem && gd == disks;
}

fn size_err_is(r: Result[AzureVmSize, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return streq(m, want);
}

fn etag_ok_is(r: Result[AzureEtag, Str], value: Str, weak: Bool) -> Bool {
  if !r.is_ok {
    return false;
  }
  let e: AzureEtag = r.value;
  let v: Str = e.value;
  return streq(v, value) && e.weak == weak;
}

fn etag_err_is(r: Result[AzureEtag, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return streq(m, want);
}

fn app_ok_is(r: Result[AzureFunctionApp, Str], name: Str, runtime: Int, version: Str) -> Bool {
  if !r.is_ok {
    return false;
  }
  let a: AzureFunctionApp = r.value;
  let gn: Str = a.name;
  let gr: Int = a.runtime;
  let gv: Str = a.runtime_version;
  return streq(gn, name) && gr == runtime && streq(gv, version);
}

fn app_err_is(r: Result[AzureFunctionApp, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return streq(m, want);
}

fn q_ok_is(r: Result[AzureSbQueue, Str], name: Str, lock_sec: Int, max_delivery: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  let q: AzureSbQueue = r.value;
  let gn: Str = q.name;
  let gl: Int = q.lock_duration_sec;
  let gm: Int = q.max_delivery_count;
  return streq(gn, name) && gl == lock_sec && gm == max_delivery;
}

fn q_err_is(r: Result[AzureSbQueue, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return streq(m, want);
}

// --------------------------------------------------
//  ARM ids
// --------------------------------------------------

fn t1() -> TestResult {
  let g = "11111111-2222-3333-4444-555555555555";
  let r1 = azure_arm_parse("/subscriptions/" + g);
  var ok = r1.is_ok;
  if ok {
    let a: ArmResourceId = r1.value;
    let s: Str = a.subscription;
    let rg: Str = a.resource_group;
    ok = streq(s, g) && rg.len() == 0;
    ok = ok && a.scope == AZURE_ARM_SCOPE_SUBSCRIPTION;
  }
  let r2 = azure_arm_parse("/SUBSCRIPTIONS/" + g + "/RESOURCEGROUPS/rg-prod");
  if !r2.is_ok {
    ok = false;
  } else {
    let b: ArmResourceId = r2.value;
    let s2: Str = b.subscription;
    let rg2: Str = b.resource_group;
    ok = ok && streq(s2, g) && streq(rg2, "rg-prod");
    ok = ok && b.scope == AZURE_ARM_SCOPE_RESOURCE_GROUP;
    ok = ok && streq(azure_arm_scope_name(b.scope), "resource_group");
  }
  return assert(ok, "arm: subscription and resource-group scopes, case-insensitive keywords");
}

fn t2() -> TestResult {
  let g = "11111111-2222-3333-4444-555555555555";
  let id = "/subscriptions/" + g + "/resourceGroups/rg-prod/providers/Microsoft.Storage/storageAccounts/mystorageacct";
  let r = azure_arm_parse(id);
  var ok = r.is_ok;
  if ok {
    let a: ArmResourceId = r.value;
    let ns: Str = a.namespace;
    let tp: Str = a.type_path;
    let rn: Str = a.resource_name;
    let pid: Str = a.parent_id;
    let raw: Str = a.raw;
    ok = streq(ns, "Microsoft.Storage") && streq(tp, "storageAccounts");
    ok = ok && streq(rn, "mystorageacct");
    ok = ok && a.scope == AZURE_ARM_SCOPE_RESOURCE;
    ok = ok && streq(pid, "/subscriptions/" + g + "/resourceGroups/rg-prod/providers/Microsoft.Storage");
    ok = ok && streq(raw, id);
  }
  return assert(ok, "arm: full resource fields, parent id and raw round-trip");
}

fn t3() -> TestResult {
  let g = "11111111-2222-3333-4444-555555555555";
  let child = "/subscriptions/" + g + "/resourceGroups/rg-app/providers/Microsoft.Web/sites/site1/config/web";
  let r = azure_arm_parse(child);
  var ok = r.is_ok;
  if ok {
    let a: ArmResourceId = r.value;
    let tp: Str = a.type_path;
    let rn: Str = a.resource_name;
    let pid: Str = a.parent_id;
    ok = streq(tp, "sites/config") && streq(rn, "site1/web");
    ok = ok && streq(pid, "/subscriptions/" + g + "/resourceGroups/rg-app/providers/Microsoft.Web/sites/site1");
  }
  let b = azure_arm_resource_id(g, "rg-app", "Microsoft.Web", "sites/config", "site1/web");
  ok = ok && str_ok_is(b, child);
  let bad = azure_arm_resource_id(g, "rg-app", "Microsoft.Web", "sites/config", "site1");
  ok = ok && str_err_is(bad, "azure: type/name segment count mismatch");
  let bad2 = azure_arm_resource_id(g, "rg-app", "", "sites", "site1");
  ok = ok && str_err_is(bad2, "azure: invalid provider namespace");
  return assert(ok, "arm: child resource parse and build round-trip with errors");
}

fn t4() -> TestResult {
  var ok = rid_err_is(azure_arm_parse(""), "azure: empty resource id");
  ok = ok && rid_err_is(azure_arm_parse("subscriptions/x"), "azure: resource id must start with '/'");
  ok = ok && rid_err_is(azure_arm_parse("/subscriptions/x//providers/y"), "azure: empty path segment");
  ok = ok && rid_err_is(azure_arm_parse("/subscriptions/x/resourceGroups/rg/providers/NS/type1/name1/type2"), "azure: resource id must end with a name");
  ok = ok && rid_err_is(azure_arm_parse("/subscriptions/x/resourceGroups/rg/providers/NS"), "azure: provider scope has no resource type");
  ok = ok && rid_err_is(azure_arm_parse("/subscriptions/x/resourceGroups/rg/other/thing"), "azure: expected providers segment");
  let g = "11111111-2222-3333-4444-555555555555";
  ok = ok && base.azure_guid_valid(g);
  ok = ok && base.azure_guid_valid("AABBCCDD-1122-3344-5566-778899AABBCC");
  ok = ok && !base.azure_guid_valid("11111111222233334444555555555555");
  ok = ok && !base.azure_guid_valid("11111111-2222-3333-4444-55555555555");
  ok = ok && streq(azure_arm_scope_name(AZURE_ARM_SCOPE_SUBSCRIPTION), "subscription");
  ok = ok && streq(azure_arm_scope_name(9), "unknown");
  return assert(ok, "arm: parse errors, GUID shape and scope names");
}

// --------------------------------------------------
//  Blob storage
// --------------------------------------------------

fn t5() -> TestResult {
  var ok = azure_storage_account_name_valid("mystorageacct");
  ok = ok && azure_storage_account_name_valid("abc123");
  ok = ok && !azure_storage_account_name_valid("ab");
  ok = ok && !azure_storage_account_name_valid("MyStorageAcct");
  ok = ok && !azure_storage_account_name_valid("abcdefghijklmnopqrstuvwxy");
  ok = ok && !azure_storage_account_name_valid("has_underscore");
  ok = ok && azure_container_name_valid("my-container");
  ok = ok && azure_container_name_valid("abc123");
  ok = ok && !azure_container_name_valid("ab");
  ok = ok && !azure_container_name_valid("-bad");
  ok = ok && !azure_container_name_valid("bad-");
  ok = ok && !azure_container_name_valid("bad--name");
  ok = ok && !azure_container_name_valid("UPPER");
  return assert(ok, "storage: account and container name rules");
}

fn t6() -> TestResult {
  var ok = azure_blob_name_valid("folder/file.txt");
  ok = ok && azure_blob_name_valid("a");
  ok = ok && !azure_blob_name_valid("");
  ok = ok && !azure_blob_name_valid("/lead");
  ok = ok && !azure_blob_name_valid("trail/");
  ok = ok && !azure_blob_name_valid("trail.");
  ok = ok && !azure_blob_name_valid("a//b");
  ok = ok && !azure_blob_name_valid("a\\b");
  let u = azure_blob_url("mystorageacct", "my-container", "folder/file.txt");
  ok = ok && str_ok_is(u, "https://mystorageacct.blob.core.windows.net/my-container/folder/file.txt");
  ok = ok && str_err_is(azure_blob_url("Bad", "my-container", "b"), "azure: invalid storage account name");
  ok = ok && str_err_is(azure_blob_url("mystorageacct", "Bad", "b"), "azure: invalid container name");
  ok = ok && str_err_is(azure_blob_url("mystorageacct", "my-container", "bad\\name"), "azure: invalid blob name");
  return assert(ok, "storage: blob name rules and URL assembly");
}

fn t7() -> TestResult {
  let r1 = azure_etag_parse("\"abc123\"");
  var ok = etag_ok_is(r1, "abc123", false);
  let r2 = azure_etag_parse("W/\"xyz\"");
  ok = ok && etag_ok_is(r2, "xyz", true);
  ok = ok && etag_err_is(azure_etag_parse("abc"), "azure: malformed ETag");
  ok = ok && etag_err_is(azure_etag_parse("\"\""), "azure: malformed ETag");
  ok = ok && etag_err_is(azure_etag_parse("W/abc"), "azure: malformed ETag");
  ok = ok && etag_err_is(azure_etag_parse("W/\"abc"), "azure: malformed ETag");
  if r1.is_ok && r2.is_ok {
    let e1: AzureEtag = r1.value;
    let e2: AzureEtag = r2.value;
    let e3 = AzureEtag{ value: "abc123"; weak: true; };
    ok = ok && azure_etag_strong_equal(&e1, &e1);
    ok = ok && !azure_etag_strong_equal(&e1, &e3);
    ok = ok && azure_etag_weak_equal(&e1, &e3);
    ok = ok && !azure_etag_weak_equal(&e1, &e2);
  } else {
    ok = false;
  }
  return assert(ok, "storage: ETag parse and strong/weak comparison");
}

fn t8() -> TestResult {
  var ok = azure_precondition_allows(AZURE_PRECOND_NONE, false, "", "");
  ok = ok && azure_precondition_allows(AZURE_PRECOND_IF_MATCH, true, "\"a\"", "*");
  ok = ok && !azure_precondition_allows(AZURE_PRECOND_IF_MATCH, false, "", "*");
  ok = ok && azure_precondition_allows(AZURE_PRECOND_IF_MATCH, true, "\"a\"", "\"a\"");
  ok = ok && !azure_precondition_allows(AZURE_PRECOND_IF_MATCH, true, "\"a\"", "\"b\"");
  ok = ok && !azure_precondition_allows(AZURE_PRECOND_IF_MATCH, false, "", "\"a\"");
  ok = ok && !azure_precondition_allows(AZURE_PRECOND_IF_NONE_MATCH, true, "\"a\"", "*");
  ok = ok && azure_precondition_allows(AZURE_PRECOND_IF_NONE_MATCH, false, "", "*");
  ok = ok && !azure_precondition_allows(AZURE_PRECOND_IF_NONE_MATCH, true, "\"a\"", "\"a\"");
  ok = ok && azure_precondition_allows(AZURE_PRECOND_IF_NONE_MATCH, true, "\"a\"", "\"b\"");
  ok = ok && !azure_precondition_allows(99, true, "\"a\"", "\"a\"");
  return assert(ok, "storage: If-Match / If-None-Match precondition table");
}

fn t9() -> TestResult {
  var ok = azure_block_id_valid("AAAA");
  ok = ok && azure_block_id_valid("AA/A");
  ok = ok && azure_block_id_valid("ab+cd=");
  ok = ok && !azure_block_id_valid("bad!");
  ok = ok && !azure_block_id_valid("");
  var b65 = "";
  var k = 0;
  while k < 65 {
    b65 = b65 + "A";
    k = k + 1;
  }
  ok = ok && !azure_block_id_valid(b65);
  var ids = Vec[Str].new();
  ids.push("AAAA");
  ids.push("BBBB");
  ok = ok && azure_block_list_valid(&ids);
  var ids2 = Vec[Str].new();
  ids2.push("AAAA");
  ids2.push("BBB");
  ok = ok && !azure_block_list_valid(&ids2);
  var empty = Vec[Str].new();
  ok = ok && !azure_block_list_valid(&empty);
  var committed = Vec[Str].new();
  committed.push("AAAA");
  committed.push("BBBB");
  var staged = Vec[Str].new();
  staged.push("CCCC");
  var requested = Vec[Str].new();
  requested.push("AAAA");
  requested.push("CCCC");
  ok = ok && str_ok_is(azure_block_list_resolve(&committed, &staged, &requested), "AAAA,CCCC");
  var missing = Vec[Str].new();
  missing.push("DDDD");
  ok = ok && str_err_is(azure_block_list_resolve(&committed, &staged, &missing), "azure: block id not found: DDDD");
  var uneven = Vec[Str].new();
  uneven.push("AAAA");
  uneven.push("CCC");
  ok = ok && str_err_is(azure_block_list_resolve(&committed, &staged, &uneven), "azure: block ids must have equal length");
  ok = ok && streq(azure_blob_tier_name(AZURE_ACCESS_TIER_ARCHIVE), "archive");
  ok = ok && streq(azure_blob_tier_name(9), "unknown");
  ok = ok && azure_blob_tier_valid(AZURE_ACCESS_TIER_COOL);
  ok = ok && !azure_blob_tier_valid(9);
  ok = ok && streq(azure_blob_type_name(AZURE_BLOB_TYPE_PAGE), "page");
  ok = ok && streq(azure_lease_state_name(AZURE_LEASE_BREAKING), "breaking");
  return assert(ok, "storage: block-list rules, commit resolution and property names");
}

// --------------------------------------------------
//  Virtual machines
// --------------------------------------------------

fn t10() -> TestResult {
  var ok = size_ok_is(azure_vm_size_lookup("Standard_D4s_v5"), "Standard_D4s_v5", 4, 16384, 8);
  ok = ok && size_ok_is(azure_vm_size_lookup("standard_b1s"), "Standard_B1s", 1, 1024, 2);
  ok = ok && size_ok_is(azure_vm_size_lookup("Standard_E2s_v5"), "Standard_E2s_v5", 2, 16384, 4);
  ok = ok && size_ok_is(azure_vm_size_lookup("Standard_B2s"), "Standard_B2s", 2, 4096, 4);
  ok = ok && size_err_is(azure_vm_size_lookup("Standard_Z9"), "azure: unknown VM size: Standard_Z9");
  ok = ok && streq(azure_vm_size_name_by_shape(2, 8192), "Standard_D2s_v5");
  ok = ok && streq(azure_vm_size_name_by_shape(1, 1024), "Standard_B1s");
  ok = ok && streq(azure_vm_size_name_by_shape(3, 3), "");
  return assert(ok, "vm: size lookup, reverse lookup and unknown size");
}

fn t11() -> TestResult {
  var ok = azure_vm_power_parse("PowerState/running") == AZURE_VM_POWER_RUNNING;
  ok = ok && azure_vm_power_parse("deallocated") == AZURE_VM_POWER_DEALLOCATED;
  ok = ok && azure_vm_power_parse("PowerState/STOPPED") == AZURE_VM_POWER_STOPPED;
  ok = ok && azure_vm_power_parse("bogus") == AZURE_VM_POWER_UNKNOWN;
  ok = ok && streq(azure_vm_power_name(AZURE_VM_POWER_DEALLOCATING), "deallocating");
  ok = ok && streq(azure_vm_power_name(42), "unknown");
  ok = ok && azure_vm_power_transition(AZURE_VM_POWER_RUNNING, AZURE_VM_POWER_DEALLOCATING);
  ok = ok && azure_vm_power_transition(AZURE_VM_POWER_DEALLOCATING, AZURE_VM_POWER_DEALLOCATED);
  ok = ok && azure_vm_power_transition(AZURE_VM_POWER_DEALLOCATED, AZURE_VM_POWER_STARTING);
  ok = ok && azure_vm_power_transition(AZURE_VM_POWER_STOPPED, AZURE_VM_POWER_DEALLOCATING);
  ok = ok && azure_vm_power_transition(AZURE_VM_POWER_STARTING, AZURE_VM_POWER_STOPPED);
  ok = ok && azure_vm_power_transition(AZURE_VM_POWER_UNKNOWN, AZURE_VM_POWER_RUNNING);
  ok = ok && azure_vm_power_transition(AZURE_VM_POWER_RUNNING, AZURE_VM_POWER_RUNNING);
  ok = ok && !azure_vm_power_transition(AZURE_VM_POWER_RUNNING, AZURE_VM_POWER_DEALLOCATED);
  ok = ok && !azure_vm_power_transition(AZURE_VM_POWER_DEALLOCATED, AZURE_VM_POWER_RUNNING);
  ok = ok && azure_vm_power_can_start(AZURE_VM_POWER_STOPPED);
  ok = ok && azure_vm_power_can_start(AZURE_VM_POWER_DEALLOCATED);
  ok = ok && !azure_vm_power_can_start(AZURE_VM_POWER_RUNNING);
  ok = ok && azure_vm_power_can_deallocate(AZURE_VM_POWER_RUNNING);
  ok = ok && !azure_vm_power_can_deallocate(AZURE_VM_POWER_DEALLOCATED);
  return assert(ok, "vm: power-state parse, transitions and start/deallocate predicates");
}

fn t12() -> TestResult {
  var ok = streq(azure_location_canonical("West Europe"), "westeurope");
  ok = ok && streq(azure_location_canonical("EAST US"), "eastus");
  ok = ok && azure_location_valid("westeurope");
  ok = ok && azure_location_valid("West Europe");
  ok = ok && !azure_location_valid("atlantis");
  var names = Vec[Str].new();
  var values = Vec[Str].new();
  names.push("env");
  names.push("owner");
  values.push("prod");
  values.push("ada");
  ok = ok && azure_tags_valid(&names, &values);
  var dup = Vec[Str].new();
  var dupv = Vec[Str].new();
  dup.push("Env");
  dup.push("env");
  dupv.push("a");
  dupv.push("b");
  ok = ok && !azure_tags_valid(&dup, &dupv);
  var longv = "";
  var k = 0;
  while k < 257 {
    longv = longv + "a";
    k = k + 1;
  }
  var ln = Vec[Str].new();
  var lv = Vec[Str].new();
  ln.push("env");
  lv.push(longv);
  ok = ok && !azure_tags_valid(&ln, &lv);
  ok = ok && str_ok_is(azure_tags_get(&names, &values, "ENV"), "prod");
  ok = ok && str_err_is(azure_tags_get(&names, &values, "zone"), "azure: tag not found: zone");
  return assert(ok, "vm: location canonicalization and tag validation/lookup");
}

// --------------------------------------------------
//  Functions
// --------------------------------------------------

fn t13() -> TestResult {
  var ok = azure_function_app_name_valid("my-func-app");
  ok = ok && azure_function_app_name_valid("ab");
  ok = ok && !azure_function_app_name_valid("MyFunc");
  ok = ok && !azure_function_app_name_valid("a");
  ok = ok && !azure_function_app_name_valid("-ab");
  ok = ok && !azure_function_app_name_valid("ab-");
  ok = ok && azure_function_runtime_valid(AZURE_RUNTIME_CUSTOM);
  ok = ok && !azure_function_runtime_valid(9);
  ok = ok && streq(azure_function_runtime_name(AZURE_RUNTIME_NODE), "node");
  ok = ok && azure_function_runtime_lookup("Python") == AZURE_RUNTIME_PYTHON;
  ok = ok && azure_function_runtime_lookup("go") == -1;
  let r = azure_function_app_lookup("my-func-app", "West Europe", AZURE_RUNTIME_NODE, "18");
  ok = ok && app_ok_is(r, "my-func-app", AZURE_RUNTIME_NODE, "18");
  if r.is_ok {
    let a: AzureFunctionApp = r.value;
    ok = ok && streq(azure_function_default_hostname(&a), "my-func-app.azurewebsites.net");
  } else {
    ok = false;
  }
  ok = ok && app_err_is(azure_function_app_lookup("my-func-app", "atlantis", AZURE_RUNTIME_NODE, "18"), "azure: unknown location: atlantis");
  ok = ok && app_err_is(azure_function_app_lookup("MyFunc", "West Europe", AZURE_RUNTIME_NODE, "18"), "azure: invalid function app name");
  ok = ok && app_err_is(azure_function_app_lookup("my-func-app", "West Europe", AZURE_RUNTIME_NODE, ""), "azure: invalid runtime version");
  return assert(ok, "functions: app names, runtimes, lookup and hostname");
}

fn t14() -> TestResult {
  var ok = azure_route_valid("");
  ok = ok && azure_route_valid("api/items");
  ok = ok && azure_route_valid("api/items/{id:int}");
  ok = ok && azure_route_valid("api/{name:alpha}");
  ok = ok && azure_route_valid("api/{id?}");
  ok = ok && azure_route_valid("api/{id:int?}");
  ok = ok && azure_route_valid("{id}");
  ok = ok && azure_route_valid("api/items/{d:datetime}/{n:guid}");
  ok = ok && !azure_route_valid("api//items");
  ok = ok && !azure_route_valid("api/{id");
  ok = ok && !azure_route_valid("api/{id:bad}");
  ok = ok && !azure_route_valid("api/{:int}");
  ok = ok && !azure_route_valid("api/items/");
  var long_route = "a";
  var k = 1;
  while k < 33 {
    long_route = long_route + "/a";
    k = k + 1;
  }
  ok = ok && !azure_route_valid(long_route);
  ok = ok && str_ok_is(azure_route_parameter_names("api/{a}/{b:int}"), "a,b");
  ok = ok && str_ok_is(azure_route_parameter_names("api/items"), "");
  ok = ok && str_err_is(azure_route_parameter_names("api//x"), "azure: invalid route");
  return assert(ok, "functions: route validity and parameter extraction");
}

fn t15() -> TestResult {
  let g = "11111111-2222-3333-4444-555555555555";
  var ok = azure_route_match("api/items/{id:int}", "api/items/42");
  ok = ok && !azure_route_match("api/items/{id:int}", "api/items/abc");
  ok = ok && azure_route_match("api/items/{id:guid}", "api/items/" + g);
  ok = ok && azure_route_match("api/items", "api/ITEMS");
  ok = ok && azure_route_match("api/{id?}", "api/");
  ok = ok && azure_route_match("api/{id?}", "api");
  ok = ok && !azure_route_match("api/{id}", "api/");
  ok = ok && !azure_route_match("api/items/{id}", "api/items");
  ok = ok && azure_route_match("", "");
  ok = ok && !azure_route_match("", "x");
  ok = ok && !azure_route_match("api//x", "api//x");
  ok = ok && azure_route_match("api/{n:alpha}", "api/abc");
  ok = ok && !azure_route_match("api/{n:alpha}", "api/ab1");
  ok = ok && azure_route_match("api/{n:bool}", "api/TRUE");
  ok = ok && azure_route_match("api/{n:float}", "api/3.14");
  ok = ok && !azure_route_match("api/{n:float}", "api/3.1.4");
  ok = ok && azure_route_match("api/{n:datetime}", "api/2026-10-02");
  ok = ok && azure_route_match("api/{n:long}", "api/-42");
  return assert(ok, "functions: path matching with constraints and optionals");
}

fn t16() -> TestResult {
  var ok = azure_trigger_method_allowed("get, post", "POST");
  ok = ok && azure_trigger_method_allowed("get", "get");
  ok = ok && !azure_trigger_method_allowed("get", "delete");
  ok = ok && !azure_trigger_method_allowed("", "get");
  ok = ok && azure_trigger_method_valid("patch");
  ok = ok && !azure_trigger_method_valid("fetch");
  let trig = AzureHttpTrigger{ methods_csv: "get,post"; route: "api/items/{id:int}"; auth_level: AZURE_AUTH_FUNCTION; };
  ok = ok && azure_trigger_valid(&trig);
  let bad_auth = AzureHttpTrigger{ methods_csv: "get"; route: "api/x"; auth_level: 9; };
  ok = ok && !azure_trigger_valid(&bad_auth);
  let bad_route = AzureHttpTrigger{ methods_csv: "get"; route: "a//b"; auth_level: AZURE_AUTH_ANONYMOUS; };
  ok = ok && !azure_trigger_valid(&bad_route);
  let bad_method = AzureHttpTrigger{ methods_csv: "fetch"; route: "api/x"; auth_level: AZURE_AUTH_ADMIN; };
  ok = ok && !azure_trigger_valid(&bad_method);
  ok = ok && azure_function_key_valid("abcDEF0123-_");
  ok = ok && !azure_function_key_valid("bad!");
  ok = ok && !azure_function_key_valid("");
  ok = ok && str_ok_is(azure_function_invoke_url("my-func-app", "/api/items"), "https://my-func-app.azurewebsites.net/api/items");
  ok = ok && str_ok_is(azure_function_invoke_url("my-func-app", ""), "https://my-func-app.azurewebsites.net/");
  ok = ok && str_err_is(azure_function_invoke_url("MyFunc", "api"), "azure: invalid function app name");
  ok = ok && azure_function_status_class(200) == AZURE_HTTP_SUCCESS;
  ok = ok && azure_function_status_class(404) == AZURE_HTTP_CLIENT_ERROR;
  ok = ok && azure_function_status_class(503) == AZURE_HTTP_SERVER_ERROR;
  ok = ok && azure_function_status_retryable(429);
  ok = ok && azure_function_status_retryable(503);
  ok = ok && !azure_function_status_retryable(404);
  return assert(ok, "functions: triggers, keys, invoke URL and status classification");
}

// --------------------------------------------------
//  Cosmos DB
// --------------------------------------------------

fn t17() -> TestResult {
  var ok = azure_cosmos_db_name_valid("catalog");
  ok = ok && azure_cosmos_container_name_valid("items");
  ok = ok && !azure_cosmos_name_valid("bad/name");
  ok = ok && !azure_cosmos_name_valid("");
  ok = ok && azure_cosmos_partition_key_path_valid("/tenantId");
  ok = ok && azure_cosmos_partition_key_path_valid("/a/b/c");
  ok = ok && !azure_cosmos_partition_key_path_valid("/a/b/c/d");
  ok = ok && !azure_cosmos_partition_key_path_valid("tenantId");
  ok = ok && !azure_cosmos_partition_key_path_valid("/a//b");
  ok = ok && !azure_cosmos_partition_key_path_valid("/a/");
  ok = ok && azure_cosmos_partition_key_value_valid("tenant-1");
  ok = ok && !azure_cosmos_partition_key_value_valid("bad/val");
  ok = ok && !azure_cosmos_partition_key_value_valid("");
  let h = azure_cosmos_partition_key_header("t1");
  ok = ok && str_ok_is(h, "[\"t1\"]");
  ok = ok && str_ok_is(azure_cosmos_partition_key_header_parse("[\"t1\"]"), "t1");
  ok = ok && str_err_is(azure_cosmos_partition_key_header_parse("[\"a\",\"b\"]"), "azure: malformed partition key header");
  ok = ok && str_err_is(azure_cosmos_partition_key_header_parse("t1"), "azure: malformed partition key header");
  ok = ok && str_err_is(azure_cosmos_partition_key_header("bad/val"), "azure: invalid partition key value");
  return assert(ok, "cosmos: names, partition-key path/value and header codec");
}

fn t18() -> TestResult {
  var ok = azure_cosmos_ttl_valid(-1);
  ok = ok && azure_cosmos_ttl_valid(1);
  ok = ok && azure_cosmos_ttl_valid(2147483647);
  ok = ok && !azure_cosmos_ttl_valid(0);
  ok = ok && azure_cosmos_document_valid("doc1", "pk1", 3600);
  ok = ok && !azure_cosmos_document_valid("bad/id", "pk1", 3600);
  ok = ok && !azure_cosmos_document_valid("doc1", "bad/id", 3600);
  ok = ok && !azure_cosmos_document_valid("doc1", "pk1", 0);
  ok = ok && azure_cosmos_consistency_valid(AZURE_COSMOS_CONSISTENCY_STRONG);
  ok = ok && azure_cosmos_consistency_valid(AZURE_COSMOS_CONSISTENCY_EVENTUAL);
  ok = ok && !azure_cosmos_consistency_valid(5);
  ok = ok && !azure_cosmos_consistency_valid(-1);
  ok = ok && streq(azure_cosmos_consistency_name(AZURE_COSMOS_CONSISTENCY_STRONG), "strong");
  ok = ok && streq(azure_cosmos_consistency_name(AZURE_COSMOS_CONSISTENCY_SESSION), "session");
  ok = ok && streq(azure_cosmos_consistency_name(9), "unknown");
  return assert(ok, "cosmos: TTL, document shape and consistency levels");
}

fn t19() -> TestResult {
  var ok = azure_cosmos_throughput_normalize(0) == 400;
  ok = ok && azure_cosmos_throughput_normalize(400) == 400;
  ok = ok && azure_cosmos_throughput_normalize(401) == 500;
  ok = ok && azure_cosmos_throughput_normalize(450) == 500;
  ok = ok && azure_cosmos_throughput_normalize(1000) == 1000;
  ok = ok && azure_cosmos_throughput_normalize(999999999) == 1000000;
  ok = ok && streq(azure_cosmos_status_error(409), "Conflict");
  ok = ok && streq(azure_cosmos_status_error(429), "TooManyRequests");
  ok = ok && streq(azure_cosmos_status_error(412), "PreconditionFailed");
  ok = ok && streq(azure_cosmos_status_error(200), "");
  ok = ok && azure_cosmos_status_retryable(429);
  ok = ok && azure_cosmos_status_retryable(449);
  ok = ok && azure_cosmos_status_retryable(503);
  ok = ok && !azure_cosmos_status_retryable(412);
  ok = ok && str_ok_is(azure_cosmos_document_path("db1", "coll1", "doc1"), "dbs/db1/colls/coll1/docs/doc1");
  ok = ok && str_err_is(azure_cosmos_document_path("bad/name", "coll1", "doc1"), "azure: invalid database name");
  ok = ok && str_err_is(azure_cosmos_document_path("db1", "coll1", "bad/id"), "azure: invalid document id");
  return assert(ok, "cosmos: throughput ladder, status names, retryability and document path");
}

// --------------------------------------------------
//  Service Bus
// --------------------------------------------------

fn t20() -> TestResult {
  var ok = azure_sb_entity_name_valid("orders");
  ok = ok && azure_sb_entity_name_valid("orders-queue");
  ok = ok && azure_sb_entity_name_valid("orders.queue");
  ok = ok && !azure_sb_entity_name_valid("-bad");
  ok = ok && !azure_sb_entity_name_valid("bad.");
  ok = ok && !azure_sb_entity_name_valid("a..b");
  ok = ok && !azure_sb_entity_name_valid("a--b");
  ok = ok && !azure_sb_entity_name_valid("a b");
  ok = ok && azure_sb_namespace_valid("ns-prod");
  ok = ok && !azure_sb_namespace_valid("ab");
  ok = ok && !azure_sb_namespace_valid("-ns");
  let q = azure_sb_queue("orders", 30, 10, false, true);
  ok = ok && q_ok_is(q, "orders", 30, 10);
  ok = ok && q_err_is(azure_sb_queue("orders", 4, 10, false, true), "azure: invalid lock duration");
  ok = ok && q_err_is(azure_sb_queue("orders", 30, 0, false, true), "azure: invalid max delivery count");
  ok = ok && q_err_is(azure_sb_queue("", 30, 10, false, true), "azure: invalid entity name");
  ok = ok && str_ok_is(azure_sb_queue_url("ns-prod", "orders"), "https://ns-prod.servicebus.windows.net/orders");
  ok = ok && str_err_is(azure_sb_queue_url("ab", "orders"), "azure: invalid namespace");
  ok = ok && str_ok_is(azure_sb_subscription_path("orders-topic", "sub-a"), "orders-topic/subscriptions/sub-a");
  ok = ok && str_err_is(azure_sb_subscription_path("orders-topic", "-bad"), "azure: invalid subscription name");
  return assert(ok, "servicebus: entity names, queue validation and URLs");
}

fn t21() -> TestResult {
  var ok = streq(azure_sb_delivery_mode_name(AZURE_SB_MODE_PEEK_LOCK), "peek_lock");
  ok = ok && streq(azure_sb_delivery_mode_name(AZURE_SB_MODE_RECEIVE_AND_DELETE), "receive_and_delete");
  ok = ok && streq(azure_sb_state_name(AZURE_SB_STATE_DEAD_LETTER), "dead_letter");
  ok = ok && streq(azure_sb_state_name(AZURE_SB_STATE_COMPLETED), "completed");
  ok = ok && azure_sb_message_transition(AZURE_SB_STATE_ACTIVE, AZURE_SB_ACTION_COMPLETE) == AZURE_SB_STATE_COMPLETED;
  ok = ok && azure_sb_message_transition(AZURE_SB_STATE_ACTIVE, AZURE_SB_ACTION_ABANDON) == AZURE_SB_STATE_ACTIVE;
  ok = ok && azure_sb_message_transition(AZURE_SB_STATE_ACTIVE, AZURE_SB_ACTION_DEFER) == AZURE_SB_STATE_DEFERRED;
  ok = ok && azure_sb_message_transition(AZURE_SB_STATE_ACTIVE, AZURE_SB_ACTION_DEAD_LETTER) == AZURE_SB_STATE_DEAD_LETTER;
  ok = ok && azure_sb_message_transition(AZURE_SB_STATE_DEFERRED, AZURE_SB_ACTION_RECEIVE) == AZURE_SB_STATE_ACTIVE;
  ok = ok && azure_sb_message_transition(AZURE_SB_STATE_SCHEDULED, AZURE_SB_ACTION_SCHEDULED_DUE) == AZURE_SB_STATE_ACTIVE;
  ok = ok && azure_sb_message_transition(AZURE_SB_STATE_DEAD_LETTER, AZURE_SB_ACTION_COMPLETE) == -1;
  ok = ok && azure_sb_message_transition(AZURE_SB_STATE_COMPLETED, AZURE_SB_ACTION_COMPLETE) == -1;
  ok = ok && !azure_sb_lock_expired(100, 99);
  ok = ok && azure_sb_lock_expired(100, 100);
  ok = ok && !azure_sb_lock_expired(0, 5);
  ok = ok && !azure_sb_delivery_count_exceeded(10, 10);
  ok = ok && azure_sb_delivery_count_exceeded(11, 10);
  ok = ok && azure_sb_delivery_count_exceeded(5, 0);
  ok = ok && azure_sb_deadletter_reason_valid("MaxDeliveryCountExceeded");
  ok = ok && azure_sb_deadletter_reason_valid("ttlexpiredexception");
  ok = ok && !azure_sb_deadletter_reason_valid("made-up");
  ok = ok && azure_sb_scheduled_delay_valid(1);
  ok = ok && azure_sb_scheduled_delay_valid(604800);
  ok = ok && !azure_sb_scheduled_delay_valid(604801);
  ok = ok && !azure_sb_scheduled_delay_valid(0);
  ok = ok && azure_sb_rule_filter_valid("$Default");
  ok = ok && azure_sb_rule_filter_valid("sys.Label='x'");
  ok = ok && !azure_sb_rule_filter_valid("");
  let m = AzureSbMessage{ message_id: "msg-1"; state: AZURE_SB_STATE_ACTIVE; delivery_count: 0; lock_expires_at: 0; session_id: ""; };
  ok = ok && azure_sb_message_valid(&m);
  let m2 = AzureSbMessage{ message_id: "msg-1"; state: 9; delivery_count: 0; lock_expires_at: 0; session_id: ""; };
  ok = ok && !azure_sb_message_valid(&m2);
  return assert(ok, "servicebus: delivery states, lock/delivery rules and message shape");
}

// --------------------------------------------------
//  Entra ID auth
// --------------------------------------------------

fn t22() -> TestResult {
  let g = "11111111-2222-3333-4444-555555555555";
  let c = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
  var ok = azure_tenant_id_valid(g);
  ok = ok && azure_tenant_id_valid("contoso.onmicrosoft.com");
  ok = ok && !azure_tenant_id_valid("bad tenant");
  ok = ok && !azure_tenant_id_valid("bad!");
  ok = ok && azure_client_id_valid(c);
  ok = ok && !azure_client_id_valid("not-a-guid");
  ok = ok && azure_scope_valid("https://vault.azure.net/.default");
  ok = ok && !azure_scope_valid("https://vault.azure.net");
  ok = ok && !azure_scope_valid("http://vault.azure.net/.default");
  ok = ok && str_ok_is(azure_scope_for_resource("https://vault.azure.net/"), "https://vault.azure.net/.default");
  ok = ok && str_ok_is(azure_scope_for_resource("https://vault.azure.net/.default"), "https://vault.azure.net/.default");
  ok = ok && str_ok_is(azure_scope_resource("https://vault.azure.net/.default"), "https://vault.azure.net");
  ok = ok && str_err_is(azure_scope_for_resource("http://vault.azure.net"), "azure: resource must be https");
  ok = ok && str_err_is(azure_scope_for_resource(""), "azure: empty resource");
  ok = ok && str_err_is(azure_scope_resource("https://vault.azure.net"), "azure: invalid scope");
  ok = ok && str_ok_is(azure_authority_url(g), "https://login.microsoftonline.com/" + g);
  ok = ok && str_ok_is(azure_token_url(g), "https://login.microsoftonline.com/" + g + "/oauth2/v2.0/token");
  ok = ok && str_err_is(azure_authority_url("bad tenant"), "azure: invalid tenant id");
  return assert(ok, "auth: tenant/client ids, scopes and endpoint URLs");
}

fn t23() -> TestResult {
  let scope = "https://vault.azure.net/.default";
  let tok = AzureToken{ access_token: "tok123"; token_type: "bearer"; expires_in_sec: 3600; scope: scope; refresh_token: ""; };
  var ok = azure_token_valid(&tok);
  ok = ok && str_ok_is(azure_bearer_header(&tok), "Bearer tok123");
  let bad1 = AzureToken{ access_token: ""; token_type: "Bearer"; expires_in_sec: 3600; scope: scope; refresh_token: ""; };
  ok = ok && !azure_token_valid(&bad1);
  let bad2 = AzureToken{ access_token: "tok"; token_type: "MAC"; expires_in_sec: 3600; scope: scope; refresh_token: ""; };
  ok = ok && !azure_token_valid(&bad2);
  let bad3 = AzureToken{ access_token: "tok"; token_type: "Bearer"; expires_in_sec: 0; scope: scope; refresh_token: ""; };
  ok = ok && !azure_token_valid(&bad3);
  let bad4 = AzureToken{ access_token: "tok"; token_type: "Bearer"; expires_in_sec: 60; scope: "https://vault.azure.net"; refresh_token: ""; };
  ok = ok && !azure_token_valid(&bad4);
  ok = ok && str_err_is(azure_bearer_header(&bad1), "azure: malformed token");
  ok = ok && azure_token_expires_at(1000, 3600) == 4600;
  ok = ok && azure_token_expires_at(-1, 10) == -1;
  ok = ok && azure_token_expires_at(0, 0) == -1;
  ok = ok && !azure_token_is_expired(4600, 1000, 0);
  ok = ok && azure_token_is_expired(4600, 4600, 0);
  ok = ok && azure_token_is_expired(4600, 4550, 60);
  ok = ok && !azure_token_is_expired(4600, 4550, 49);
  ok = ok && azure_token_is_expired(0, 0, 0);
  return assert(ok, "auth: token envelope, expiry arithmetic and bearer header");
}

fn t24() -> TestResult {
  let g = "11111111-2222-3333-4444-555555555555";
  let c = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
  var ok = streq(azure_identity_source_name(AZURE_IDENTITY_MANAGED_IDENTITY), "managed_identity");
  ok = ok && streq(azure_identity_source_name(9), "unknown");
  let good = AzureIdentity{ tenant_id: g; client_id: c; client_secret: "s3cret"; source: AZURE_IDENTITY_CLIENT_SECRET; expires_unix: 0; };
  ok = ok && azure_identity_valid(&good, 1000);
  let mi = AzureIdentity{ tenant_id: g; client_id: c; client_secret: ""; source: AZURE_IDENTITY_MANAGED_IDENTITY; expires_unix: 0; };
  ok = ok && azure_identity_valid(&mi, 1000);
  let no_secret = AzureIdentity{ tenant_id: g; client_id: c; client_secret: ""; source: AZURE_IDENTITY_CLIENT_SECRET; expires_unix: 0; };
  ok = ok && !azure_identity_valid(&no_secret, 1000);
  let expired = AzureIdentity{ tenant_id: g; client_id: c; client_secret: "s"; source: AZURE_IDENTITY_CLIENT_SECRET; expires_unix: 100; };
  ok = ok && !azure_identity_valid(&expired, 200);
  var sources = Vec[Int].new();
  var tenants = Vec[Str].new();
  var clients = Vec[Str].new();
  var secrets = Vec[Str].new();
  var exps = Vec[Int].new();
  sources.push(AZURE_IDENTITY_CLIENT_SECRET);
  tenants.push(g);
  clients.push(c);
  secrets.push("");
  exps.push(0);
  sources.push(AZURE_IDENTITY_MANAGED_IDENTITY);
  tenants.push(g);
  clients.push(c);
  secrets.push("");
  exps.push(0);
  let r = azure_identity_resolve(&sources, &tenants, &clients, &secrets, &exps, 1000);
  ok = ok && r.is_ok;
  if r.is_ok {
    let id: AzureIdentity = r.value;
    let src: Int = id.source;
    ok = ok && src == AZURE_IDENTITY_MANAGED_IDENTITY;
  } else {
    ok = false;
  }
  ok = ok && streq(azure_version(), "0.1.0");
  ok = ok && str_ok_is(azure_cloud_host(AZURE_SERVICE_MANAGEMENT), "management.azure.com");
  ok = ok && str_ok_is(azure_cloud_host(AZURE_SERVICE_SERVICE_BUS), "servicebus.windows.net");
  ok = ok && str_err_is(azure_cloud_host(9), "azure: unknown service code");
  ok = ok && streq(azure_provider_namespace(AZURE_PROVIDER_STORAGE), "Microsoft.Storage");
  ok = ok && streq(azure_provider_namespace(9), "");
  ok = ok && str_ok_is(azure_api_version(AZURE_PROVIDER_COMPUTE), "2023-03-01");
  ok = ok && str_err_is(azure_api_version(9), "azure: unknown provider code");
  ok = ok && streq(azure_management_url(), "https://management.azure.com/");
  return assert(ok, "auth: identity chain and the package registry facade");
}

// --------------------------------------------------
//  Harness
// --------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.azure conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.azure: all tests passed");
  } else {
    io.println("xiom.azure: tests failed");
  }
  return failed;
}
