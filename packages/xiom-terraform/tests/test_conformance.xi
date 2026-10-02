// XIOM -- xiom.terraform conformance tests (24 checks)
// Port task: prove the pure-XIOM infrastructure-as-code workflow model
// against its documented API: the HCL subset grammar and error catalog,
// config accessors and rendering, the plan graph with diffs and topological
// order, the apply/destroy state machine with revisions, and the provider
// registry/init/config integration.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// All Str equality goes through streq (string.str_compare): `==` on Str
// values read from Vec[Str] elements lowers to a pointer comparison. Every
// Vec element read binds a typed local first. Fixture helpers unwrap Results
// with empty fallbacks, so an unexpected Err fails the owning assertion
// loudly. Everything is deterministic: no threads, no wall clock, no files.

module terraform_tests
use xiom.io; use xiom.test;
use xiom.terraform;
use xiom.string;

// --------------------------------------------------
//  Helpers
// --------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return string.str_compare(a, b) == 0;
}

fn empty_cfg() -> TfConfig {
  return TfConfig{
    block_type: Vec[Str].new();
    block_labels: Vec[Str].new();
    block_line: Vec[Int].new();
    block_parent: Vec[Int].new();
    attr_name: Vec[Str].new();
    attr_owner: Vec[Int].new();
    attr_kind: Vec[Str].new();
    attr_value: Vec[Str].new();
    attr_line: Vec[Int].new();
  };
}

fn empty_state() -> TfState {
  return TfState{
    lineage: "";
    serial: 0;
    next_rev: 0;
    res_addr: Vec[Str].new();
    res_status: Vec[Int].new();
    res_rev: Vec[Int].new();
  };
}

fn cfg_of(r: Result[TfConfig, Str]) -> TfConfig {
  match r {
    Ok(v) => { return v; },
    Err(_) => { return empty_cfg(); },
  }
  return empty_cfg();
}

fn state_of(r: Result[TfState, Str]) -> TfState {
  match r {
    Ok(v) => { return v; },
    Err(_) => { return empty_state(); },
  }
  return empty_state();
}

fn parse_err_is(text: Str, want: Str) -> Bool {
  let r = hcl_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn attr_is(c: &TfConfig, owner: Int, name: Str, want: Str) -> Bool {
  let o = config_attr_get(c, owner, name);
  match o {
    Some(v) => { return streq(v, want); },
    None => { return false; },
  }
  return false;
}

fn kind_is(c: &TfConfig, owner: Int, name: Str, want: Str) -> Bool {
  let o = config_attr_get_kind(c, owner, name);
  match o {
    Some(v) => { return streq(v, want); },
    None => { return false; },
  }
  return false;
}

fn attr_missing(c: &TfConfig, owner: Int, name: Str) -> Bool {
  let o = config_attr_get(c, owner, name);
  match o {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

fn opt_str_is(o: Option[Str], want: Str) -> Bool {
  match o {
    Some(v) => { return streq(v, want); },
    None => { return false; },
  }
  return false;
}

fn opt_str_none(o: Option[Str]) -> Bool {
  match o {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
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

fn int_of(r: Result[Int, Str]) -> Int {
  match r {
    Ok(v) => { return v; },
    Err(_) => { return -9999; },
  }
  return -9999;
}

fn state_err_is(r: Result[TfState, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn order_of(r: Result[Vec[Int], Str]) -> Vec[Int] {
  match r {
    Ok(v) => { return v; },
    Err(_) => { return Vec[Int].new(); },
  }
  return Vec[Int].new();
}

fn order_err_is(r: Result[Vec[Int], Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn order_at(v: &Vec[Int], i: Int) -> Int {
  if i < 0 || i >= v.len() {
    return -1;
  }
  let x: Int = v[i];
  return x;
}

fn vec_str_at(v: &Vec[Str], i: Int) -> Str {
  if i < 0 || i >= v.len() {
    return "";
  }
  let x: Str = v[i];
  return x;
}

fn label_is(c: &TfConfig, bi: Int, li: Int, want: Str) -> Bool {
  return streq(config_block_label(c, bi, li), want);
}

// --------------------------------------------------
//  HCL parsing
// --------------------------------------------------

fn t1() -> TestResult {
  let text = "name = \"web\"\ncount = 3\nenabled = true\ndisabled = false\nnothing = null\nregion = var.region\nmixed = \"pre-${var.suffix}\"\nports = [80, 443]\ntags = { env = \"prod\" }\nratio = 1.5\n";
  let c = cfg_of(hcl_parse(text));
  var ok = config_attr_count(&c) == 10;
  if !kind_is(&c, -1, "name", "str") { ok = false; }
  if !kind_is(&c, -1, "count", "num") { ok = false; }
  if !kind_is(&c, -1, "enabled", "bool") { ok = false; }
  if !kind_is(&c, -1, "disabled", "bool") { ok = false; }
  if !kind_is(&c, -1, "nothing", "null") { ok = false; }
  if !kind_is(&c, -1, "region", "ref") { ok = false; }
  if !kind_is(&c, -1, "mixed", "interp") { ok = false; }
  if !kind_is(&c, -1, "ports", "list") { ok = false; }
  if !kind_is(&c, -1, "tags", "map") { ok = false; }
  if !kind_is(&c, -1, "ratio", "num") { ok = false; }
  if !attr_is(&c, -1, "name", "web") { ok = false; }
  if !attr_is(&c, -1, "nothing", "null") { ok = false; }
  if !attr_is(&c, -1, "region", "var.region") { ok = false; }
  if !attr_is(&c, -1, "mixed", "pre-${var.suffix}") { ok = false; }
  if !attr_is(&c, -1, "ports", "80, 443") { ok = false; }
  if !attr_is(&c, -1, "ratio", "1.5") { ok = false; }
  if !attr_missing(&c, -1, "ghost") { ok = false; }
  return assert(ok, "attribute kinds and normalized values");
}

fn t2() -> TestResult {
  let text = "terraform {\n  required_version = \">= 1.0\"\n}\nprovider \"aws\" {\n  region = \"us-east-1\"\n}\nresource \"aws_instance\" \"web\" {\n  ami = \"ami-123\"\n  count = 2\n  lifecycle {\n    create_before_destroy = true\n  }\n}\nresource \"aws_s3_bucket\" \"assets\" {\n  bucket = \"assets\"\n}\n";
  let c = cfg_of(hcl_parse(text));
  var ok = config_block_count(&c) == 5;
  if !streq(config_block_type(&c, 0), "terraform") { ok = false; }
  if !streq(config_block_type(&c, 1), "provider") { ok = false; }
  if !streq(config_block_type(&c, 2), "resource") { ok = false; }
  if !streq(config_block_type(&c, 3), "lifecycle") { ok = false; }
  if !streq(config_block_type(&c, 4), "resource") { ok = false; }
  if !streq(config_block_labels(&c, 1), "aws") { ok = false; }
  if !streq(config_block_labels(&c, 2), "aws_instance/web") { ok = false; }
  if !streq(config_block_labels(&c, 3), "") { ok = false; }
  if config_block_parent(&c, 0) != -1 { ok = false; }
  if config_block_parent(&c, 2) != -1 { ok = false; }
  if config_block_parent(&c, 3) != 2 { ok = false; }
  if !attr_is(&c, 0, "required_version", ">= 1.0") { ok = false; }
  if !attr_is(&c, 1, "region", "us-east-1") { ok = false; }
  if !attr_is(&c, 2, "ami", "ami-123") { ok = false; }
  if !attr_is(&c, 3, "create_before_destroy", "true") { ok = false; }
  if !attr_is(&c, 4, "bucket", "assets") { ok = false; }
  if config_block_attr_count(&c, 2) != 2 { ok = false; }
  if !streq(config_block_attr_name(&c, 2, 0), "ami") { ok = false; }
  if !streq(config_block_attr_value(&c, 2, 1), "2") { ok = false; }
  if config_resource_count(&c) != 2 { ok = false; }
  if !streq(config_resource_address(&c, 0), "aws_instance.web") { ok = false; }
  if !streq(config_resource_address(&c, 1), "aws_s3_bucket.assets") { ok = false; }
  return assert(ok, "blocks, labels, nesting and attribute owners");
}

fn t3() -> TestResult {
  let text = "# leading\n// another\n/* block\n   comment */\na = 1 # trailing\nb = 2\n/* mid */ c = 3\n";
  let c = cfg_of(hcl_parse(text));
  var ok = config_attr_count(&c) == 3;
  let ia = config_attr_index(&c, -1, "a");
  let ib = config_attr_index(&c, -1, "b");
  let ic2 = config_attr_index(&c, -1, "c");
  if ia != 0 || ib != 1 || ic2 != 2 { ok = false; }
  if config_attr_line(&c, ia) != 5 { ok = false; }
  if config_attr_line(&c, ib) != 6 { ok = false; }
  if config_attr_line(&c, ic2) != 7 { ok = false; }
  if !attr_is(&c, -1, "a", "1") { ok = false; }
  if !attr_is(&c, -1, "b", "2") { ok = false; }
  if !attr_is(&c, -1, "c", "3") { ok = false; }
  return assert(ok, "comments (#, //, /* */) are skipped and lines tracked");
}

fn t4() -> TestResult {
  let text = "a = \"x\\\"y\"\nb = \"tab\\there\"\nc = \"l1\\nl2\"\nd = \"back\\\\slash\"\ne = \"a-${var.x}-b\"\nf = \"${var.x}\"\n";
  let c = cfg_of(hcl_parse(text));
  var ok = attr_is(&c, -1, "a", "x\"y");
  if !attr_is(&c, -1, "b", "tab\there") { ok = false; }
  if !attr_is(&c, -1, "c", "l1\nl2") { ok = false; }
  if !attr_is(&c, -1, "d", "back\\slash") { ok = false; }
  if !attr_is(&c, -1, "e", "a-${var.x}-b") { ok = false; }
  if !kind_is(&c, -1, "e", "interp") { ok = false; }
  if !kind_is(&c, -1, "f", "interp") { ok = false; }
  if !attr_is(&c, -1, "a", "x\"y") { ok = false; }
  if !parse_err_is("bad = \"x\\qy\"\n", "hcl: invalid escape sequence at line 1") { ok = false; }
  return assert(ok, "string escapes decode and interpolation is classified");
}

fn t5() -> TestResult {
  let text = "ports = [80, 443, 8080]\nnested = [[1, 2], [3]]\nempty = []\ntags = { env = \"prod\", team = \"core\" }\n";
  let c = cfg_of(hcl_parse(text));
  let ports = config_attr_value(&c, config_attr_index(&c, -1, "ports"));
  let nested = config_attr_value(&c, config_attr_index(&c, -1, "nested"));
  let empty = config_attr_value(&c, config_attr_index(&c, -1, "empty"));
  let tags = config_attr_value(&c, config_attr_index(&c, -1, "tags"));
  var ok = streq(ports, "80, 443, 8080");
  if hcl_list_count(ports) != 3 { ok = false; }
  if !streq(hcl_list_item(ports, 1), "443") { ok = false; }
  if hcl_list_count(nested) != 2 { ok = false; }
  if !streq(hcl_list_item(nested, 0), "[1, 2]") { ok = false; }
  if !streq(empty, "") { ok = false; }
  if hcl_list_count(empty) != 0 { ok = false; }
  if hcl_map_count(tags) != 2 { ok = false; }
  if !streq(hcl_map_key(tags, 0), "env") { ok = false; }
  if !streq(hcl_map_value(tags, 0), "prod") { ok = false; }
  if !opt_str_is(hcl_map_get(tags, "team"), "core") { ok = false; }
  if !opt_str_none(hcl_map_get(tags, "ghost")) { ok = false; }
  if !streq(hcl_map_value(tags, 9), "") { ok = false; }
  return assert(ok, "list splitting and map lookup respect nesting and quotes");
}

fn t6() -> TestResult {
  var ok = parse_err_is("a = \"unterminated\n", "hcl: unterminated string at line 1");
  if !parse_err_is("a = [1, 2", "hcl: unterminated list at line 1") { ok = false; }
  if !parse_err_is("a = { x = 1", "hcl: unterminated map at line 1") { ok = false; }
  if !parse_err_is("a = [1, 2}", "hcl: mismatched brackets in list at line 1") { ok = false; }
  if !parse_err_is("a 1", "hcl: expected '{' after block header at line 1") { ok = false; }
  if !parse_err_is("/* nope", "hcl: unterminated block comment at line 1") { ok = false; }
  if !parse_err_is("a = 1 b = 2", "hcl: unexpected text after attribute at line 1") { ok = false; }
  if !parse_err_is("}", "hcl: unexpected '}' at line 1") { ok = false; }
  if !parse_err_is("1a = 2", "hcl: invalid identifier at line 1") { ok = false; }
  return assert(ok, "syntax error catalog reports the exact message and line");
}

fn t7() -> TestResult {
  var ok = parse_err_is("a = 1\na = 2\n", "hcl: duplicate attribute a at line 2");
  if !parse_err_is("a = foo(", "hcl: unsupported value expression at line 1") { ok = false; }
  if !parse_err_is("a = 1.", "hcl: invalid number at line 1") { ok = false; }
  if !parse_err_is("a \"\" {}", "hcl: invalid block label at line 1") { ok = false; }
  if !parse_err_is("a {\nb = 1\n", "hcl: expected '}' to close block at line 3") { ok = false; }
  if !parse_err_is("a = 1 x", "hcl: unexpected text after attribute at line 1") { ok = false; }
  if !parse_err_is("resource \"aws_instance\" \"web\"", "hcl: expected '{' after block header at line 1") { ok = false; }
  return assert(ok, "duplicate attributes, labels and unsupported expressions");
}

fn t8() -> TestResult {
  let text = "terraform {\n  required_version = \">= 1.0\"\n}\nresource \"aws_instance\" \"web\" {\n  ami = \"ami-123\"\n  count = 2\n}\n";
  let c = cfg_of(hcl_parse(text));
  let out = config_render(&c);
  let want = "terraform {\n  required_version = \">= 1.0\"\n}\nresource \"aws_instance\" \"web\" {\n  ami = \"ami-123\"\n  count = 2\n}\n";
  var ok = streq(out, want);
  let c2 = cfg_of(hcl_parse(out));
  if config_block_count(&c2) != config_block_count(&c) { ok = false; }
  if config_attr_count(&c2) != config_attr_count(&c) { ok = false; }
  if !attr_is(&c2, 1, "ami", "ami-123") { ok = false; }
  if !streq(config_resource_address(&c2, 0), "aws_instance.web") { ok = false; }
  return assert(ok, "canonical rendering round-trips through parse");
}

fn t9() -> TestResult {
  let text = "provider \"aws\" { region = \"us-east-1\" }\nprovider \"google\" { region = \"us-central1\" }\nresource \"aws_instance\" \"web\" {}\nresource \"aws_instance\" \"db\" {}\n";
  let c = cfg_of(hcl_parse(text));
  var ok = config_block_count(&c) == 4;
  if config_block_index(&c, "provider", "aws") != 0 { ok = false; }
  if config_block_index(&c, "provider", "google") != 1 { ok = false; }
  if config_block_index(&c, "resource", "aws_instance") != 2 { ok = false; }
  if config_block_index(&c, "resource", "nope") != -1 { ok = false; }
  if config_nth_block(&c, "provider", 1) != 1 { ok = false; }
  if config_nth_block(&c, "provider", 2) != -1 { ok = false; }
  if config_block_label_count(&c, 2) != 2 { ok = false; }
  if !label_is(&c, 2, 0, "aws_instance") { ok = false; }
  if !label_is(&c, 2, 1, "web") { ok = false; }
  if !label_is(&c, 2, 2, "") { ok = false; }
  let labs = config_block_label_list(&c, 2);
  if labs.len() != 2 { ok = false; }
  if !streq(vec_str_at(&labs, 1), "web") { ok = false; }
  if !attr_is(&c, 0, "region", "us-east-1") { ok = false; }
  return assert(ok, "block lookup by type/first label and label accessors");
}

// --------------------------------------------------
//  Execution plan
// --------------------------------------------------

fn t10() -> TestResult {
  var p = plan_new();
  var ok = int_ok_is(plan_add_change(&mut p, "aws_instance.web", TF_ACTION_CREATE, "new"), 0);
  if !int_ok_is(plan_add_change(&mut p, "aws_instance.db", TF_ACTION_UPDATE, "ami changed"), 1) { ok = false; }
  if !int_ok_is(plan_add_change(&mut p, "aws_s3_bucket.old", TF_ACTION_DELETE, "removed"), 2) { ok = false; }
  if plan_count(&p) != 3 { ok = false; }
  if !streq(plan_addr(&p, 0), "aws_instance.web") { ok = false; }
  if plan_action(&p, 1) != TF_ACTION_UPDATE { ok = false; }
  if !streq(plan_reason(&p, 2), "removed") { ok = false; }
  if !streq(plan_action_name(plan_action(&p, 0)), "create") { ok = false; }
  if !streq(plan_action_name(plan_action(&p, 1)), "update") { ok = false; }
  if !streq(plan_action_name(plan_action(&p, 2)), "delete") { ok = false; }
  if !streq(plan_action_name(9), "unknown") { ok = false; }
  if !int_err_is(plan_add_change(&mut p, "", TF_ACTION_CREATE, ""), "plan: resource address must not be empty") { ok = false; }
  if !int_err_is(plan_add_change(&mut p, "x.y", 9, ""), "plan: unknown action") { ok = false; }
  if !int_err_is(plan_add_change(&mut p, "aws_instance.web", TF_ACTION_UPDATE, ""), "plan: duplicate resource address: aws_instance.web") { ok = false; }
  if plan_count(&p) != 3 { ok = false; }
  return assert(ok, "plan change nodes, accessors and validation errors");
}

fn t11() -> TestResult {
  var p = plan_new();
  var ok = int_ok_is(plan_add_change(&mut p, "aws_instance.web", TF_ACTION_CREATE, ""), 0);
  if !int_ok_is(plan_add_change(&mut p, "aws_instance.db", TF_ACTION_UPDATE, "ami changed"), 1) { ok = false; }
  if !int_ok_is(plan_add_change(&mut p, "aws_s3_bucket.old", TF_ACTION_DELETE, "removed"), 2) { ok = false; }
  if !int_ok_is(plan_add_diff(&mut p, 0, "ami", "", "ami-123"), 0) { ok = false; }
  if !int_ok_is(plan_add_diff(&mut p, 1, "ami", "ami-1", "ami-2"), 1) { ok = false; }
  if !int_ok_is(plan_add_diff(&mut p, 2, "bucket", "assets", ""), 2) { ok = false; }
  if plan_diff_count(&p) != 3 { ok = false; }
  if plan_change_diff_count(&p, 0) != 1 { ok = false; }
  if plan_change_diff_count(&p, 1) != 1 { ok = false; }
  if plan_diff_owner(&p, 2) != 2 { ok = false; }
  if !streq(plan_diff_attr(&p, 1), "ami") { ok = false; }
  if !streq(plan_diff_before(&p, 1), "ami-1") { ok = false; }
  if !streq(plan_diff_after(&p, 1), "ami-2") { ok = false; }
  if !streq(plan_diff_before(&p, 0), "") { ok = false; }
  if !streq(plan_diff_after(&p, 2), "") { ok = false; }
  if !int_err_is(plan_add_diff(&mut p, 1, "ami", "", ""), "plan: duplicate diff attribute: ami") { ok = false; }
  if !int_err_is(plan_add_diff(&mut p, 9, "x", "", ""), "plan: unknown change id") { ok = false; }
  if !int_err_is(plan_add_diff(&mut p, 1, "", "", ""), "plan: diff attribute must not be empty") { ok = false; }
  let want = "+ aws_instance.web\n  ami:  -> ami-123\n~ aws_instance.db (ami changed)\n  ami: ami-1 -> ami-2\n- aws_s3_bucket.old (removed)\n  bucket: assets -> \n";
  if !streq(plan_render(&p), want) { ok = false; }
  if !streq(plan_summary(&p), "1 to create, 1 to update, 1 to delete") { ok = false; }
  return assert(ok, "plan diffs, rendering and summary");
}

fn t12() -> TestResult {
  var p = plan_new();
  var ok = int_ok_is(plan_add_change(&mut p, "a", TF_ACTION_CREATE, ""), 0);
  if !int_ok_is(plan_add_change(&mut p, "b", TF_ACTION_CREATE, ""), 1) { ok = false; }
  if !int_ok_is(plan_add_dep(&mut p, 0, 1), 1) { ok = false; }
  if !int_err_is(plan_add_dep(&mut p, 0, 9), "plan: unknown dependency id") { ok = false; }
  if !int_err_is(plan_add_dep(&mut p, 1, 1), "plan: dependency on self") { ok = false; }
  if !int_err_is(plan_add_dep(&mut p, 0, 1), "plan: duplicate dependency") { ok = false; }
  if plan_has_cycle(&p) { ok = false; }
  let v = order_of(plan_order(&p));
  if v.len() != 2 { ok = false; }
  if order_at(&v, 0) != 0 || order_at(&v, 1) != 1 { ok = false; }
  return assert(ok, "dependency edges validate and order dependencies first");
}

fn t13() -> TestResult {
  var p = plan_new();
  var ok = int_ok_is(plan_add_change(&mut p, "a", TF_ACTION_CREATE, ""), 0);
  if !int_ok_is(plan_add_change(&mut p, "b", TF_ACTION_UPDATE, ""), 1) { ok = false; }
  if !int_ok_is(plan_add_change(&mut p, "c", TF_ACTION_UPDATE, ""), 2) { ok = false; }
  if !int_ok_is(plan_add_change(&mut p, "d", TF_ACTION_UPDATE, ""), 3) { ok = false; }
  if !int_ok_is(plan_add_change(&mut p, "e", TF_ACTION_DELETE, ""), 4) { ok = false; }
  if !int_ok_is(plan_add_dep(&mut p, 0, 1), 1) { ok = false; }
  if !int_ok_is(plan_add_dep(&mut p, 0, 2), 2) { ok = false; }
  if !int_ok_is(plan_add_dep(&mut p, 1, 3), 3) { ok = false; }
  if !int_ok_is(plan_add_dep(&mut p, 2, 3), 4) { ok = false; }
  if !int_ok_is(plan_add_dep(&mut p, 3, 4), 5) { ok = false; }
  let v = order_of(plan_order(&p));
  var ok2 = v.len() == 5;
  if ok2 {
    if order_at(&v, 0) != 0 { ok2 = false; }
    if order_at(&v, 1) != 1 { ok2 = false; }
    if order_at(&v, 2) != 2 { ok2 = false; }
    if order_at(&v, 3) != 3 { ok2 = false; }
    if order_at(&v, 4) != 4 { ok2 = false; }
  }
  if !ok2 { ok = false; }
  if plan_has_cycle(&p) { ok = false; }
  return assert(ok, "diamond dependency graph yields deterministic order");
}

fn t14() -> TestResult {
  var p = plan_new();
  var ok = int_ok_is(plan_add_change(&mut p, "a", TF_ACTION_UPDATE, ""), 0);
  if !int_ok_is(plan_add_change(&mut p, "b", TF_ACTION_UPDATE, ""), 1) { ok = false; }
  if !int_ok_is(plan_add_change(&mut p, "c", TF_ACTION_UPDATE, ""), 2) { ok = false; }
  if !int_ok_is(plan_add_dep(&mut p, 0, 1), 1) { ok = false; }
  if !int_ok_is(plan_add_dep(&mut p, 1, 2), 2) { ok = false; }
  if !int_ok_is(plan_add_dep(&mut p, 2, 0), 3) { ok = false; }
  if !plan_has_cycle(&p) { ok = false; }
  if !order_err_is(plan_order(&p), "plan: dependency cycle") { ok = false; }
  return assert(ok, "cycle-closing edge is detected by order and has_cycle");
}

// --------------------------------------------------
//  State machine
// --------------------------------------------------

fn t15() -> TestResult {
  var ok = state_err_is(state_new(""), "state: lineage must not be empty");
  var s = state_of(state_new("lin-1"));
  if !streq(state_lineage(&s), "lin-1") { ok = false; }
  if state_serial(&s) != 1 { ok = false; }
  if state_count(&s) != 0 { ok = false; }
  if !int_ok_is(state_add_resource(&mut s, "aws_instance.web"), 0) { ok = false; }
  if !int_ok_is(state_add_resource(&mut s, "aws_instance.db"), 1) { ok = false; }
  if state_count(&s) != 2 { ok = false; }
  if state_live_count(&s) != 2 { ok = false; }
  if state_index(&s, "aws_instance.db") != 1 { ok = false; }
  if state_index(&s, "ghost") != TF_NOT_FOUND { ok = false; }
  if !state_has(&s, "aws_instance.web") { ok = false; }
  if state_has(&s, "ghost") { ok = false; }
  if !streq(state_addr(&s, 1), "aws_instance.db") { ok = false; }
  if state_status(&s, 0) != TF_RES_PENDING { ok = false; }
  if state_rev(&s, 0) != 0 { ok = false; }
  if !streq(state_status_name(TF_RES_PENDING), "pending") { ok = false; }
  if !streq(state_status_name(TF_RES_CREATED), "created") { ok = false; }
  if !streq(state_status_name(TF_RES_UPDATED), "updated") { ok = false; }
  if !streq(state_status_name(TF_RES_DELETED), "deleted") { ok = false; }
  if !streq(state_status_name(9), "unknown") { ok = false; }
  if !int_err_is(state_add_resource(&mut s, "aws_instance.web"), "state: duplicate resource address: aws_instance.web") { ok = false; }
  if !int_err_is(state_add_resource(&mut s, ""), "state: resource address must not be empty") { ok = false; }
  let want = "lineage = lin-1\nserial = 1\naws_instance.web pending rev=0\naws_instance.db pending rev=0\n";
  if !streq(state_render(&s), want) { ok = false; }
  return assert(ok, "state construction, accessors and rendering");
}

fn t16() -> TestResult {
  var allowed = 0;
  var from = 0;
  while from < 4 {
    var to = 0;
    while to < 4 {
      if state_can_transition(from, to) { allowed = allowed + 1; }
      to = to + 1;
    }
    from = from + 1;
  }
  var ok = allowed == 6;
  if !state_can_transition(TF_RES_PENDING, TF_RES_CREATED) { ok = false; }
  if !state_can_transition(TF_RES_PENDING, TF_RES_DELETED) { ok = false; }
  if !state_can_transition(TF_RES_CREATED, TF_RES_UPDATED) { ok = false; }
  if !state_can_transition(TF_RES_CREATED, TF_RES_DELETED) { ok = false; }
  if !state_can_transition(TF_RES_UPDATED, TF_RES_UPDATED) { ok = false; }
  if !state_can_transition(TF_RES_UPDATED, TF_RES_DELETED) { ok = false; }
  if state_can_transition(TF_RES_DELETED, TF_RES_UPDATED) { ok = false; }
  if state_can_transition(TF_RES_CREATED, TF_RES_PENDING) { ok = false; }
  if state_can_transition(TF_RES_PENDING, TF_RES_UPDATED) { ok = false; }
  if state_can_transition(TF_RES_CREATED, TF_RES_CREATED) { ok = false; }
  return assert(ok, "transition table has exactly six legal state pairs");
}

fn t17() -> TestResult {
  var s = state_of(state_new("lin-2"));
  var ok = int_ok_is(state_add_resource(&mut s, "aws_instance.web"), 0);
  if !int_ok_is(state_transition(&mut s, 0, TF_RES_CREATED), 1) { ok = false; }
  if state_serial(&s) != 2 { ok = false; }
  if state_status(&s, 0) != TF_RES_CREATED { ok = false; }
  if state_rev(&s, 0) != 1 { ok = false; }
  if !int_ok_is(state_transition(&mut s, 0, TF_RES_UPDATED), 2) { ok = false; }
  if state_rev(&s, 0) != 2 { ok = false; }
  if !int_ok_is(state_transition(&mut s, 0, TF_RES_UPDATED), 3) { ok = false; }
  if state_serial(&s) != 4 { ok = false; }
  if !int_ok_is(state_transition(&mut s, 0, TF_RES_DELETED), 4) { ok = false; }
  if state_live_count(&s) != 0 { ok = false; }
  if state_serial(&s) != 5 { ok = false; }
  if !int_err_is(state_transition(&mut s, 0, TF_RES_UPDATED), "state: resource already deleted") { ok = false; }
  if !int_err_is(state_transition(&mut s, 5, TF_RES_CREATED), "state: unknown resource id") { ok = false; }
  if !int_ok_is(state_add_resource(&mut s, "aws_instance.db"), 1) { ok = false; }
  if !int_err_is(state_transition(&mut s, 1, TF_RES_UPDATED), "state: illegal state transition: pending -> updated") { ok = false; }
  if state_serial(&s) != 5 { ok = false; }
  return assert(ok, "transitions assign monotone revisions and bump the serial");
}

fn t18() -> TestResult {
  var p1 = plan_new();
  var ok = int_ok_is(plan_add_change(&mut p1, "aws_instance.web", TF_ACTION_CREATE, "new"), 0);
  if !int_ok_is(plan_add_change(&mut p1, "aws_instance.db", TF_ACTION_CREATE, "new"), 1) { ok = false; }
  var s = state_of(state_new("lin-3"));
  if int_of(state_apply_plan(&mut s, &p1)) != 2 { ok = false; }
  if state_status(&s, 0) != TF_RES_CREATED { ok = false; }
  if state_status(&s, 1) != TF_RES_CREATED { ok = false; }
  if state_serial(&s) != 3 { ok = false; }
  var p2 = plan_new();
  if !int_ok_is(plan_add_change(&mut p2, "aws_instance.db", TF_ACTION_UPDATE, "resize"), 0) { ok = false; }
  if int_of(state_apply_plan(&mut s, &p2)) != 1 { ok = false; }
  if state_status(&s, 1) != TF_RES_UPDATED { ok = false; }
  if state_live_count(&s) != 2 { ok = false; }
  if state_serial(&s) != 4 { ok = false; }
  if state_rev(&s, 0) != 1 { ok = false; }
  if state_rev(&s, 1) != 3 { ok = false; }
  if !int_err_is(state_apply_plan(&mut s, &p1), "state: resource already exists: aws_instance.web") { ok = false; }
  return assert(ok, "apply creates, then updates, with monotone revisions");
}

fn t19() -> TestResult {
  var s = state_of(state_new("lin-4"));
  var ok = int_ok_is(state_add_resource(&mut s, "aws_instance.web"), 0);
  if !int_ok_is(state_add_resource(&mut s, "aws_instance.db"), 1) { ok = false; }
  if !int_ok_is(state_transition(&mut s, 0, TF_RES_CREATED), 1) { ok = false; }
  if !int_ok_is(state_transition(&mut s, 1, TF_RES_CREATED), 2) { ok = false; }
  let dp = state_destroy_plan(&s);
  if plan_count(&dp) != 2 { ok = false; }
  if !streq(plan_addr(&dp, 0), "aws_instance.web") { ok = false; }
  if !streq(plan_addr(&dp, 1), "aws_instance.db") { ok = false; }
  if plan_action(&dp, 0) != TF_ACTION_DELETE { ok = false; }
  if !streq(plan_reason(&dp, 0), "destroy") { ok = false; }
  if int_of(state_destroy_all(&mut s)) != 2 { ok = false; }
  if state_live_count(&s) != 0 { ok = false; }
  if state_status(&s, 0) != TF_RES_DELETED { ok = false; }
  if state_status(&s, 1) != TF_RES_DELETED { ok = false; }
  if state_serial(&s) != 5 { ok = false; }
  let want = "lineage = lin-4\nserial = 5\naws_instance.web deleted rev=3\naws_instance.db deleted rev=4\n";
  if !streq(state_render(&s), want) { ok = false; }
  if plan_count(&state_destroy_plan(&s)) != 0 { ok = false; }
  return assert(ok, "destroy plan and destroy-all mark every live resource deleted");
}

fn t20() -> TestResult {
  var plan1 = plan_new();
  var ok = int_ok_is(plan_add_change(&mut plan1, "aws_instance.web", TF_ACTION_CREATE, ""), 0);
  var s = state_of(state_new("lin-5"));
  if !int_ok_is(state_add_resource(&mut s, "aws_instance.web"), 0) { ok = false; }
  if !int_ok_is(state_transition(&mut s, 0, TF_RES_CREATED), 1) { ok = false; }
  if !int_err_is(state_apply_plan(&mut s, &plan1), "state: resource already exists: aws_instance.web") { ok = false; }
  var plan2 = plan_new();
  if !int_ok_is(plan_add_change(&mut plan2, "aws_instance.db", TF_ACTION_UPDATE, ""), 0) { ok = false; }
  if !int_err_is(state_apply_plan(&mut s, &plan2), "state: has no resource: aws_instance.db") { ok = false; }
  var plan3 = plan_new();
  if !int_ok_is(plan_add_change(&mut plan3, "ghost", TF_ACTION_DELETE, ""), 0) { ok = false; }
  if !int_err_is(state_apply_plan(&mut s, &plan3), "state: has no resource: ghost") { ok = false; }
  if !int_ok_is(state_add_resource(&mut s, "aws_instance.db"), 1) { ok = false; }
  var plan4 = plan_new();
  if !int_ok_is(plan_add_change(&mut plan4, "aws_instance.db", TF_ACTION_UPDATE, ""), 0) { ok = false; }
  if !int_err_is(state_apply_plan(&mut s, &plan4), "state: resource not created: aws_instance.db") { ok = false; }
  var plan5 = plan_new();
  if !int_ok_is(plan_add_change(&mut plan5, "g", TF_ACTION_CREATE, ""), 0) { ok = false; }
  if !int_ok_is(plan_add_change(&mut plan5, "h", TF_ACTION_CREATE, ""), 1) { ok = false; }
  if !int_ok_is(plan_add_dep(&mut plan5, 0, 1), 1) { ok = false; }
  if !int_ok_is(plan_add_dep(&mut plan5, 1, 0), 2) { ok = false; }
  if !int_err_is(state_apply_plan(&mut s, &plan5), "plan: dependency cycle") { ok = false; }
  return assert(ok, "apply refuses duplicates, missing, pending and cyclic changes");
}

// --------------------------------------------------
//  Providers
// --------------------------------------------------

fn t21() -> TestResult {
  var r = providers_new();
  var ok = int_ok_is(provider_register(&mut r, "aws", "hashicorp/aws", "~> 5.0"), 0);
  if !int_ok_is(provider_register(&mut r, "google", "hashicorp/google", "~> 4.0"), 1) { ok = false; }
  if provider_count(&r) != 2 { ok = false; }
  if provider_index(&r, "google") != 1 { ok = false; }
  if provider_index(&r, "nope") != TF_NOT_FOUND { ok = false; }
  if !streq(provider_name(&r, 0), "aws") { ok = false; }
  if !streq(provider_source(&r, 1), "hashicorp/google") { ok = false; }
  if !streq(provider_version(&r, 1), "~> 4.0") { ok = false; }
  if !int_err_is(provider_register(&mut r, "aws", "hashicorp/aws", "~> 5.0"), "provider: duplicate provider: aws") { ok = false; }
  if !int_err_is(provider_register(&mut r, "", "x", "1"), "provider: name must not be empty") { ok = false; }
  if !int_err_is(provider_register(&mut r, "x", "", "1"), "provider: source must not be empty") { ok = false; }
  if !int_err_is(provider_register(&mut r, "x", "y", ""), "provider: version must not be empty") { ok = false; }
  if !int_err_is(provider_init(&mut r, "nope"), "provider: unknown provider: nope") { ok = false; }
  if !int_ok_is(provider_init(&mut r, "aws"), 1) { ok = false; }
  if !provider_is_initialized(&r, 0) { ok = false; }
  if provider_is_initialized(&r, 1) { ok = false; }
  if !provider_is_ready(&r, "aws") { ok = false; }
  if provider_is_ready(&r, "google") { ok = false; }
  if !int_err_is(provider_init(&mut r, "aws"), "provider: already initialized: aws") { ok = false; }
  if provider_init_count(&r) != 1 { ok = false; }
  if !int_ok_is(provider_init_all(&mut r), 1) { ok = false; }
  if provider_init_count(&r) != 2 { ok = false; }
  let want = "aws hashicorp/aws ~> 5.0 initialized\ngoogle hashicorp/google ~> 4.0 initialized\n";
  if !streq(provider_render(&r), want) { ok = false; }
  return assert(ok, "provider registration, init and registry rendering");
}

fn t22() -> TestResult {
  let text = "provider \"aws\" { region = \"us-east-1\" }\nprovider \"google\" {}\nprovider \"aws\" {}\n";
  let c = cfg_of(hcl_parse(text));
  let names = providers_from_config(&c);
  var ok = names.len() == 2;
  if !streq(vec_str_at(&names, 0), "aws") { ok = false; }
  if !streq(vec_str_at(&names, 1), "google") { ok = false; }
  var r = providers_new();
  if !int_ok_is(provider_register(&mut r, "aws", "hashicorp/aws", "~> 5.0"), 0) { ok = false; }
  if !int_ok_is(provider_init(&mut r, "aws"), 1) { ok = false; }
  let missing = provider_missing_from_config(&r, &c);
  if missing.len() != 1 { ok = false; }
  if !streq(vec_str_at(&missing, 0), "google") { ok = false; }
  if !int_ok_is(provider_register(&mut r, "google", "hashicorp/google", "~> 4.0"), 1) { ok = false; }
  if !int_ok_is(provider_apply_config(&mut r, &c), 1) { ok = false; }
  if provider_missing_from_config(&r, &c).len() != 0 { ok = false; }
  var r2 = providers_new();
  if !int_err_is(provider_apply_config(&mut r2, &c), "provider: not registered: aws") { ok = false; }
  return assert(ok, "providers_from_config dedupes and init integration works");
}

// --------------------------------------------------
//  Value helpers and end-to-end workflow
// --------------------------------------------------

fn t23() -> TestResult {
  var ok = streq(hcl_kind("\"x\""), "str");
  if !streq(hcl_kind("\"a-${var.x}\""), "interp") { ok = false; }
  if !streq(hcl_kind("[1, 2]"), "list") { ok = false; }
  if !streq(hcl_kind("{ a = 1 }"), "map") { ok = false; }
  if !streq(hcl_kind("12"), "num") { ok = false; }
  if !streq(hcl_kind("-1.5"), "num") { ok = false; }
  if !streq(hcl_kind("true"), "bool") { ok = false; }
  if !streq(hcl_kind("false"), "bool") { ok = false; }
  if !streq(hcl_kind("null"), "null") { ok = false; }
  if !streq(hcl_kind("var.x"), "ref") { ok = false; }
  if !streq(hcl_kind("foo("), "invalid") { ok = false; }
  if !streq(hcl_kind(""), "str") { ok = false; }
  if !hcl_is_interp("${var.x}") { ok = false; }
  if hcl_is_interp("plain") { ok = false; }
  if !streq(hcl_ref_root("var.region"), "var") { ok = false; }
  if !streq(hcl_ref_root("aws_instance.web[0].id"), "aws_instance") { ok = false; }
  if !streq(hcl_ref_root("x"), "x") { ok = false; }
  if !streq(hcl_quote("a\"b"), "\"a\\\"b\"") { ok = false; }
  if !streq(hcl_quote("l\nb"), "\"l\\nb\"") { ok = false; }
  return assert(ok, "kind classification, ref roots and quoting helpers");
}

// End-to-end pipeline: parse -> providers -> plan -> apply -> destroy.
fn workflow_render(text: Str) -> Str {
  let c = cfg_of(hcl_parse(text));
  var r = providers_new();
  let names = providers_from_config(&c);
  var i = 0;
  while i < names.len() {
    let nm: Str = names[i];
    let rr = provider_register(&mut r, nm, "hashicorp/" + nm, "~> 5.0");
    match rr {
      Ok(_) => {},
      Err(_) => {},
    }
    i = i + 1;
  }
  let ir = provider_init_all(&mut r);
  match ir {
    Ok(_) => {},
    Err(_) => {},
  }
  var p = plan_new();
  let n = config_resource_count(&c);
  var j = 0;
  while j < n {
    let addr = config_resource_address(&c, j);
    let pr = plan_add_change(&mut p, addr, TF_ACTION_CREATE, "new");
    match pr {
      Ok(_) => {},
      Err(_) => {},
    }
    let dr = plan_add_diff(&mut p, j, "ami", "", "ami-123");
    match dr {
      Ok(_) => {},
      Err(_) => {},
    }
    j = j + 1;
  }
  var s = state_of(state_new("lin-workflow"));
  let ar = state_apply_plan(&mut s, &p);
  match ar {
    Ok(_) => {},
    Err(_) => {},
  }
  let sr = state_destroy_all(&mut s);
  match sr {
    Ok(_) => {},
    Err(_) => {},
  }
  return "providers:\n" + provider_render(&r) + "summary:" + plan_summary(&p) + "\nplan:\n" + plan_render(&p) + "state:\n" + state_render(&s);
}

fn t24() -> TestResult {
  let text = "provider \"aws\" { region = \"us-east-1\" }\nresource \"aws_instance\" \"web\" {\n  ami = \"ami-1\"\n}\nresource \"aws_s3_bucket\" \"assets\" {\n  bucket = \"assets\"\n}\n";
  let out1 = workflow_render(text);
  let out2 = workflow_render(text);
  var ok = streq(out1, out2);
  if !string.str_contains(out1, "2 to create, 0 to update, 0 to delete") { ok = false; }
  if !string.str_contains(out1, "aws_instance.web deleted") { ok = false; }
  if !string.str_contains(out1, "aws_s3_bucket.assets deleted") { ok = false; }
  if !string.str_contains(out1, "aws hashicorp/aws ~> 5.0 initialized") { ok = false; }
  if !string.str_contains(out1, "+ aws_instance.web") { ok = false; }
  if !string.str_contains(out1, "serial = 5") { ok = false; }
  return assert(ok, "end-to-end parse/plan/apply/destroy is deterministic");
}

fn main() -> Int {
  io.println("=== xiom.terraform conformance tests ===");
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
    io.println("xiom.terraform: all tests passed");
  } else {
    io.println("xiom.terraform: tests failed");
  }
  return failed;
}
