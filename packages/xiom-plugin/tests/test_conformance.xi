// XIOM -- xiom.plugin conformance tests (25 checks)
// Port task: prove the pure-XIOM xiom.plugin module against its documented
// registration rules, semver range checks, dependency-order resolution and
// lifecycle state machine.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: empty registry, single/multiple registration metadata, version
// validation, duplicate/self/dependency/capability registration errors with
// registry immutability, exact/ordering/caret/tilde/compound range checks and
// the constraint error catalog, version ordering, dependency resolution on
// empty/single/shuffled/diamond graphs, registration-order stability, missing
// dependency and 2-/3-node cycle errors, the enable/disable/activate/
// deactivate transitions with their exact errors, enable_all/activate_all,
// capability lookup and provider order, fresh-copy enumeration, and the
// dependency-satisfied integration check.
//
// Fixture-driven and deterministic: every registry is built with add(...) from
// fixed metadata, so registration order -- and therefore every result -- is
// fixed. All Str equality goes through str_compare (BUG 17: `==` on Str values
// read from Vec[Str] elements lowers to a pointer comparison), and every Vec
// element read goes through a typed local first.

module plugin_tests
use xiom.io; use xiom.test; use xiom.plugin;
use xiom.string.compare;

// --------------------------------------------------
//  Test-side primitives
// --------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
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

fn str_vec_is(v: &Vec[Str], i: Int, want: Str) -> Bool {
  if i < 0 || i >= v.len() {
    return false;
  }
  let got: Str = v[i];
  return streq(got, want);
}

fn vec_eq(a: &Vec[Str], b: &Vec[Str]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: Str = a[i];
    let y: Str = b[i];
    if !streq(x, y) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn v0() -> Vec[Str] {
  return Vec[Str].new();
}

fn v1(a: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  return v;
}

fn v2(a: Str, b: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  return v;
}

fn v3(a: Str, b: Str, c: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn v4(a: Str, b: Str, c: Str, d: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  return v;
}

fn reg_err_is(r: Result[Registry, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn names_ok_is(r: Result[Vec[Str], Str], want: &Vec[Str]) -> Bool {
  match r {
    Ok(names) => { return vec_eq(&names, want); },
    Err(_) => { return false; },
  }
  return false;
}

fn names_err_is(r: Result[Vec[Str], Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn bool_ok_is(r: Result[Bool, Str], want: Bool) -> Bool {
  match r {
    Ok(v) => { return v == want; },
    Err(_) => { return false; },
  }
  return false;
}

fn bool_err_is(r: Result[Bool, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
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

// Unwrap a Registry Result. An unexpected Err yields an empty registry, which
// makes every dependent assertion fail loudly instead of crashing the suite.
fn unwrap_reg(r: Result[Registry, Str]) -> Registry {
  match r {
    Ok(next) => { return next; },
    Err(_) => { return plugin_registry_new(); },
  }
  return plugin_registry_new();
}

// Register a fixture plugin. Fixtures are valid by construction; an
// unexpected Err yields an empty registry so the owning test fails loudly.
fn add(reg: &Registry, name: Str, version: Str, deps: &Vec[Str], caps: &Vec[Str]) -> Registry {
  let spec = plugin_spec(name, version, deps, caps);
  let r = plugin_register(reg, &spec);
  match r {
    Ok(next) => { return next; },
    Err(_) => { return plugin_registry_new(); },
  }
  return plugin_registry_new();
}

fn add0(reg: &Registry, name: Str, version: Str) -> Registry {
  let none = v0();
  return add(reg, name, version, &none, &none);
}

fn register_err_is(reg: &Registry, name: Str, version: Str, want: Str) -> Bool {
  let none = v0();
  let spec = plugin_spec(name, version, &none, &none);
  return reg_err_is(plugin_register(reg, &spec), want);
}

fn register_err2_is(reg: &Registry, name: Str, version: Str, deps: &Vec[Str], want: Str) -> Bool {
  let none = v0();
  let spec = plugin_spec(name, version, deps, &none);
  return reg_err_is(plugin_register(reg, &spec), want);
}

fn register_err3_is(reg: &Registry, name: Str, version: Str, deps: &Vec[Str], caps: &Vec[Str], want: Str) -> Bool {
  let spec = plugin_spec(name, version, deps, caps);
  return reg_err_is(plugin_register(reg, &spec), want);
}

fn enable(reg: &Registry, name: Str) -> Registry {
  return unwrap_reg(plugin_enable(reg, name));
}

fn disable(reg: &Registry, name: Str) -> Registry {
  return unwrap_reg(plugin_disable(reg, name));
}

fn activate(reg: &Registry, name: Str) -> Registry {
  return unwrap_reg(plugin_activate(reg, name));
}

fn deactivate(reg: &Registry, name: Str) -> Registry {
  return unwrap_reg(plugin_deactivate(reg, name));
}

fn enable_all(reg: &Registry) -> Registry {
  return unwrap_reg(plugin_enable_all(reg));
}

fn activate_all(reg: &Registry) -> Registry {
  return unwrap_reg(plugin_activate_all(reg));
}

fn state_is(reg: &Registry, name: Str, want: Int) -> Bool {
  return plugin_state(reg, name) == want;
}

// --------------------------------------------------
//  Fixtures
// --------------------------------------------------

// core <- ui <- app plus an independent tool. Registration order:
// core, ui, app, tool.
fn fixture_graph() -> Registry {
  var reg = plugin_registry_new();
  let none = v0();
  let caps_core = v2("render", "storage");
  let deps_ui = v1("core");
  let caps_ui = v1("render");
  let deps_app = v2("ui", "core");
  let caps_app = v1("widgets");
  reg = add(&reg, "core", "1.4.0", &none, &caps_core);
  reg = add(&reg, "ui", "1.2.0", &deps_ui, &caps_ui);
  reg = add(&reg, "app", "2.0.0", &deps_app, &caps_app);
  reg = add(&reg, "tool", "0.9.0", &none, &none);
  return reg;
}

// Registered dependents first: app(deps ui, core), ui(deps core), core.
fn fixture_layout() -> Registry {
  var reg = plugin_registry_new();
  let none = v0();
  let deps_app = v2("ui", "core");
  let deps_ui = v1("core");
  reg = add(&reg, "app", "2.0.0", &deps_app, &none);
  reg = add(&reg, "ui", "1.2.0", &deps_ui, &none);
  reg = add(&reg, "core", "1.4.0", &none, &none);
  return reg;
}

// Two independent plugins registered z before a: resolution must keep
// registration order, not alphabetical order.
fn fixture_stability() -> Registry {
  var reg = plugin_registry_new();
  reg = add0(&reg, "z", "1.0.0");
  reg = add0(&reg, "a", "1.0.0");
  return reg;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t01() -> TestResult {
  let reg = plugin_registry_new();
  let none = v0();
  let names = plugin_names(&reg);
  let deps = plugin_deps(&reg, "core");
  var ok = plugin_count(&reg) == 0;
  if !vec_eq(&names, &none) { ok = false; }
  if plugin_has(&reg, "core") { ok = false; }
  if plugin_index(&reg, "core") != -1 { ok = false; }
  if !opt_str_none(plugin_version(&reg, "core")) { ok = false; }
  if deps.len() != 0 { ok = false; }
  if plugin_state(&reg, "core") != -1 { ok = false; }
  if plugin_find_capability(&reg, "render").is_some { ok = false; }
  if !streq(plugin_state_name(-1), "unknown") { ok = false; }
  if !streq(plugin_state_name(plugin_state_registered), "registered") { ok = false; }
  if !streq(plugin_state_name(plugin_state_enabled), "enabled") { ok = false; }
  if !streq(plugin_state_name(plugin_state_active), "active") { ok = false; }
  return assert(ok, "empty registry: count/names/lookups and state names");
}

fn t02() -> TestResult {
  let reg = plugin_registry_new();
  let caps = v2("render", "storage");
  let none = v0();
  let reg2 = add(&reg, "core", "1.4.0", &none, &caps);
  var ok = plugin_count(&reg2) == 1;
  if !plugin_has(&reg2, "core") { ok = false; }
  if plugin_index(&reg2, "core") != 0 { ok = false; }
  if !opt_str_is(plugin_version(&reg2, "core"), "1.4.0") { ok = false; }
  if plugin_state(&reg2, "core") != plugin_state_registered { ok = false; }
  if plugin_count_by_state(&reg2, plugin_state_registered) != 1 { ok = false; }
  let names = plugin_names(&reg2);
  if !str_vec_is(&names, 0, "core") { ok = false; }
  let caps_got = plugin_capabilities(&reg2, "core");
  if caps_got.len() != 2 { ok = false; }
  if !str_vec_is(&caps_got, 0, "render") { ok = false; }
  if !str_vec_is(&caps_got, 1, "storage") { ok = false; }
  if !plugin_has_capability(&reg2, "core", "render") { ok = false; }
  if plugin_has_capability(&reg2, "core", "nope") { ok = false; }
  if plugin_count(&reg) != 0 { ok = false; }
  return assert(ok, "register one plugin: metadata, state and capabilities");
}

fn t03() -> TestResult {
  let reg = fixture_graph();
  var ok = plugin_count(&reg) == 4;
  if plugin_index(&reg, "core") != 0 { ok = false; }
  if plugin_index(&reg, "ui") != 1 { ok = false; }
  if plugin_index(&reg, "app") != 2 { ok = false; }
  if plugin_index(&reg, "tool") != 3 { ok = false; }
  let names = plugin_names(&reg);
  if names.len() != 4 { ok = false; }
  if !str_vec_is(&names, 0, "core") { ok = false; }
  if !str_vec_is(&names, 1, "ui") { ok = false; }
  if !str_vec_is(&names, 2, "app") { ok = false; }
  if !str_vec_is(&names, 3, "tool") { ok = false; }
  if !opt_str_is(plugin_version(&reg, "app"), "2.0.0") { ok = false; }
  if !opt_str_is(plugin_version(&reg, "tool"), "0.9.0") { ok = false; }
  if plugin_count_by_state(&reg, plugin_state_registered) != 4 { ok = false; }
  return assert(ok, "registration order is stable and addressable");
}

fn t04() -> TestResult {
  let reg = fixture_graph();
  let d_app = plugin_deps(&reg, "app");
  var ok = d_app.len() == 2;
  if !str_vec_is(&d_app, 0, "ui") { ok = false; }
  if !str_vec_is(&d_app, 1, "core") { ok = false; }
  let d_ui = plugin_deps(&reg, "ui");
  if d_ui.len() != 1 { ok = false; }
  if !str_vec_is(&d_ui, 0, "core") { ok = false; }
  let d_tool = plugin_deps(&reg, "tool");
  if d_tool.len() != 0 { ok = false; }
  let d_nope = plugin_deps(&reg, "nope");
  if d_nope.len() != 0 { ok = false; }
  let c_nope = plugin_capabilities(&reg, "nope");
  if c_nope.len() != 0 { ok = false; }
  if !opt_str_none(plugin_version(&reg, "nope")) { ok = false; }
  if plugin_has_capability(&reg, "nope", "render") { ok = false; }
  return assert(ok, "dependency metadata keeps declaration order");
}

fn t05() -> TestResult {
  let reg = plugin_registry_new();
  var ok = register_err_is(&reg, "", "1.2.3", "plugin: empty plugin name");
  var bad = Vec[Str].new();
  bad.push("");
  bad.push("1.2");
  bad.push("1.2.3.4");
  bad.push("01.2.3");
  bad.push("1.02.3");
  bad.push("1.2.03");
  bad.push("a.b.c");
  bad.push("1.2.x");
  bad.push("1..2");
  bad.push("1.2.");
  bad.push(".1.2");
  bad.push("v1.2.3");
  bad.push("1.2.3-alpha");
  bad.push("1.2.3+build");
  bad.push("1.2.3 ");
  bad.push(" 1.2.3");
  bad.push("-1.2.3");
  bad.push("2147483648.0.0");
  var i = 0;
  while i < bad.len() {
    let bv: Str = bad[i];
    let want = "plugin: invalid version for p: " + bv;
    if !register_err_is(&reg, "p", bv, want) { ok = false; }
    i = i + 1;
  }
  if plugin_count(&reg) != 0 { ok = false; }
  return assert(ok, "register errors: empty name and the version grammar");
}

fn t06() -> TestResult {
  var reg = plugin_registry_new();
  reg = add0(&reg, "core", "1.0.0");
  var ok = register_err_is(&reg, "core", "2.0.0", "plugin: duplicate plugin: core");
  let reg2 = add0(&reg, "Core", "1.0.0");
  if plugin_count(&reg2) != 2 { ok = false; }
  if !plugin_has(&reg2, "Core") { ok = false; }
  let none = v0();
  let d_empty = v1("");
  if !register_err2_is(&reg, "a", "1.0.0", &d_empty, "plugin: empty dependency name for a") { ok = false; }
  let d_self = v1("a");
  if !register_err2_is(&reg, "a", "1.0.0", &d_self, "plugin: self dependency for a") { ok = false; }
  let d_dup = v2("b", "b");
  if !register_err2_is(&reg, "a", "1.0.0", &d_dup, "plugin: duplicate dependency b for a") { ok = false; }
  let c_empty = v1("");
  if !register_err3_is(&reg, "a", "1.0.0", &none, &c_empty, "plugin: empty capability name for a") { ok = false; }
  let c_dup = v2("x", "x");
  if !register_err3_is(&reg, "a", "1.0.0", &none, &c_dup, "plugin: duplicate capability x for a") { ok = false; }
  if plugin_count(&reg) != 1 { ok = false; }
  if !plugin_has(&reg, "core") { ok = false; }
  return assert(ok, "register errors: duplicates, self/duplicate deps and caps");
}

fn t07() -> TestResult {
  var ok = bool_ok_is(plugin_check_constraint("1.2.3", "=1.2.3"), true);
  if !bool_ok_is(plugin_check_constraint("1.2.3", "==1.2.3"), true) { ok = false; }
  if !bool_ok_is(plugin_check_constraint("1.2.3", "1.2.3"), true) { ok = false; }
  if !bool_ok_is(plugin_check_constraint("1.2.4", "=1.2.3"), false) { ok = false; }
  if !bool_ok_is(plugin_check_constraint("1.2.4", ">1.2.3"), true) { ok = false; }
  if !bool_ok_is(plugin_check_constraint("1.2.3", ">1.2.3"), false) { ok = false; }
  if !bool_ok_is(plugin_check_constraint("1.2.3", ">=1.2.3"), true) { ok = false; }
  if !bool_ok_is(plugin_check_constraint("1.2.2", ">=1.2.3"), false) { ok = false; }
  if !bool_ok_is(plugin_check_constraint("1.2.3", "<2.0.0"), true) { ok = false; }
  if !bool_ok_is(plugin_check_constraint("2.0.0", "<2.0.0"), false) { ok = false; }
  if !bool_ok_is(plugin_check_constraint("2.0.0", "<=2.0.0"), true) { ok = false; }
  if !bool_ok_is(plugin_check_constraint("10.0.0", ">9.9.9"), true) { ok = false; }
  if !bool_ok_is(plugin_check_constraint("9.9.9", ">10.0.0"), false) { ok = false; }
  if !bool_err_is(plugin_check_constraint("1.2", ">=1.0.0"), "plugin: invalid version: 1.2") { ok = false; }
  if !bool_err_is(plugin_check_constraint("1.2.3", ">>1.2.3"), "plugin: invalid range token: >>1.2.3") { ok = false; }
  if !bool_err_is(plugin_check_constraint("1.2.3", ">=1.2"), "plugin: invalid range token: >=1.2") { ok = false; }
  if !bool_err_is(plugin_check_constraint("1.2.3", "= "), "plugin: invalid range token: =") { ok = false; }
  if !bool_err_is(plugin_check_constraint("1.2.3", ""), "plugin: empty range") { ok = false; }
  if !bool_err_is(plugin_check_constraint("1.2.3", " , "), "plugin: empty range") { ok = false; }
  if !plugin_satisfies("1.2.4", ">=1.0.0") { ok = false; }
  if plugin_satisfies("0.9.0", ">=1.0.0") { ok = false; }
  if plugin_satisfies("bogus", "*") { ok = false; }
  return assert(ok, "constraints: exact/ordering comparators and errors");
}

fn t08() -> TestResult {
  var ok = bool_ok_is(plugin_check_constraint("1.2.3", "^1.2.3"), true);
  if !bool_ok_is(plugin_check_constraint("1.9.9", "^1.2.3"), true) { ok = false; }
  if !bool_ok_is(plugin_check_constraint("2.0.0", "^1.2.3"), false) { ok = false; }
  if !bool_ok_is(plugin_check_constraint("1.2.2", "^1.2.3"), false) { ok = false; }
  if !bool_ok_is(plugin_check_constraint("0.2.3", "^0.2.3"), true) { ok = false; }
  if !bool_ok_is(plugin_check_constraint("0.2.9", "^0.2.3"), true) { ok = false; }
  if !bool_ok_is(plugin_check_constraint("0.3.0", "^0.2.3"), false) { ok = false; }
  if !bool_ok_is(plugin_check_constraint("0.0.3", "^0.0.3"), true) { ok = false; }
  if !bool_ok_is(plugin_check_constraint("0.0.4", "^0.0.3"), false) { ok = false; }
  if !bool_ok_is(plugin_check_constraint("0.0.0", "^0.0.0"), true) { ok = false; }
  if !bool_ok_is(plugin_check_constraint("0.0.1", "^0.0.0"), false) { ok = false; }
  return assert(ok, "caret ranges: next non-zero leading component");
}

fn t09() -> TestResult {
  var ok = bool_ok_is(plugin_check_constraint("1.2.3", "~1.2.3"), true);
  if !bool_ok_is(plugin_check_constraint("1.2.99", "~1.2.3"), true) { ok = false; }
  if !bool_ok_is(plugin_check_constraint("1.3.0", "~1.2.3"), false) { ok = false; }
  if !bool_ok_is(plugin_check_constraint("1.2.2", "~1.2.3"), false) { ok = false; }
  if !bool_ok_is(plugin_check_constraint("0.1.2", "~0.1.2"), true) { ok = false; }
  if !bool_ok_is(plugin_check_constraint("0.1.9", "~0.1.2"), true) { ok = false; }
  if !bool_ok_is(plugin_check_constraint("0.2.0", "~0.1.2"), false) { ok = false; }
  return assert(ok, "tilde ranges: patch-level within one minor");
}

fn t10() -> TestResult {
  var ok = bool_ok_is(plugin_check_constraint("1.0.0", ">=1.0.0 <2.0.0"), true);
  if !bool_ok_is(plugin_check_constraint("1.9.9", ">=1.0.0 <2.0.0"), true) { ok = false; }
  if !bool_ok_is(plugin_check_constraint("2.0.0", ">=1.0.0 <2.0.0"), false) { ok = false; }
  if !bool_ok_is(plugin_check_constraint("0.9.9", ">=1.0.0 <2.0.0"), false) { ok = false; }
  if !bool_ok_is(plugin_check_constraint("1.5.0", ">=1.0.0,<2.0.0"), true) { ok = false; }
  if !bool_ok_is(plugin_check_constraint("1.5.0", ">=1.0.0, <2.0.0"), true) { ok = false; }
  if !bool_ok_is(plugin_check_constraint("2.1.0", "*,>=2.0.0"), true) { ok = false; }
  if !bool_ok_is(plugin_check_constraint("1.0.0", "*,>=2.0.0"), false) { ok = false; }
  if !bool_ok_is(plugin_check_constraint("0.0.1", "*"), true) { ok = false; }
  if !bool_ok_is(plugin_check_constraint("1.2.3", "1.2.3, 2.0.0"), false) { ok = false; }
  if !bool_err_is(plugin_check_constraint("bogus", "*"), "plugin: invalid version: bogus") { ok = false; }
  return assert(ok, "compound ranges: ANDed comparators, commas and star");
}

fn t11() -> TestResult {
  var ok = int_ok_is(plugin_version_cmp("1.2.3", "1.2.3"), 0);
  if !int_ok_is(plugin_version_cmp("1.2.3", "1.2.4"), -1) { ok = false; }
  if !int_ok_is(plugin_version_cmp("1.3.0", "1.2.9"), 1) { ok = false; }
  if !int_ok_is(plugin_version_cmp("2.0.0", "10.0.0"), -1) { ok = false; }
  if !int_ok_is(plugin_version_cmp("0.0.0", "0.0.0"), 0) { ok = false; }
  if !int_err_is(plugin_version_cmp("1.2", "1.2.3"), "plugin: invalid version: 1.2") { ok = false; }
  if !int_err_is(plugin_version_cmp("1.2.3", "x"), "plugin: invalid version: x") { ok = false; }
  if !plugin_version_valid("1.2.3") { ok = false; }
  if plugin_version_valid("1.2") { ok = false; }
  if plugin_version_valid("") { ok = false; }
  return assert(ok, "version ordering and validation");
}

fn t12() -> TestResult {
  var ok = plugin_version_valid("0.0.0");
  if !plugin_version_valid("0.1.0") { ok = false; }
  if !plugin_version_valid("2147483647.0.0") { ok = false; }
  if !plugin_version_valid("1.2147483647.2147483647") { ok = false; }
  if plugin_version_valid("2147483648.0.0") { ok = false; }
  if plugin_version_valid("01.0.0") { ok = false; }
  if plugin_version_valid("0.01.0") { ok = false; }
  if plugin_version_valid("0.0.01") { ok = false; }
  if plugin_version_valid("1.2.3-rc1") { ok = false; }
  if plugin_version_valid("1.2.3+b1") { ok = false; }
  if !bool_ok_is(plugin_check_constraint("2147483647.0.0", ">=2147483647.0.0"), true) { ok = false; }
  return assert(ok, "version component bounds, leading zeros and suffixes");
}

fn t13() -> TestResult {
  let empty = plugin_registry_new();
  let none = v0();
  var ok = names_ok_is(plugin_resolve(&empty), &none);
  var one_reg = plugin_registry_new();
  one_reg = add0(&one_reg, "core", "1.0.0");
  let want = v1("core");
  if !names_ok_is(plugin_resolve(&one_reg), &want) { ok = false; }
  return assert(ok, "resolve: empty registry and single plugin");
}

fn t14() -> TestResult {
  let reg = fixture_layout();
  let want = v3("core", "ui", "app");
  var ok = names_ok_is(plugin_resolve(&reg), &want);
  let stab = fixture_stability();
  let want2 = v2("z", "a");
  if !names_ok_is(plugin_resolve(&stab), &want2) { ok = false; }
  return assert(ok, "resolve: dependencies first, registration order tie-break");
}

fn t15() -> TestResult {
  let reg = fixture_graph();
  let want = v4("core", "ui", "app", "tool");
  var ok = names_ok_is(plugin_resolve(&reg), &want);
  return assert(ok, "resolve: diamond graph is deterministic");
}

fn t16() -> TestResult {
  var reg = plugin_registry_new();
  let none = v0();
  let d_core = v1("core");
  reg = add(&reg, "app", "1.0.0", &d_core, &none);
  var ok = names_err_is(plugin_resolve(&reg), "plugin: missing dependency: core (required by app)");
  var reg2 = plugin_registry_new();
  let d_ui = v1("ui");
  let d_core2 = v1("core");
  reg2 = add(&reg2, "ui", "1.0.0", &d_core2, &none);
  reg2 = add(&reg2, "app", "1.0.0", &d_ui, &none);
  if !names_err_is(plugin_resolve(&reg2), "plugin: missing dependency: core (required by ui)") { ok = false; }
  return assert(ok, "resolve: missing dependencies are reported with the owner");
}

fn t17() -> TestResult {
  var reg = plugin_registry_new();
  let none = v0();
  let d_b = v1("b");
  let d_a = v1("a");
  reg = add(&reg, "a", "1.0.0", &d_b, &none);
  reg = add(&reg, "b", "1.0.0", &d_a, &none);
  var ok = names_err_is(plugin_resolve(&reg), "plugin: dependency cycle: a -> b -> a");
  var reg2 = plugin_registry_new();
  let d_b2 = v1("b");
  let d_a2 = v1("a");
  reg2 = add0(&reg2, "d", "1.0.0");
  reg2 = add(&reg2, "a", "1.0.0", &d_b2, &none);
  reg2 = add(&reg2, "b", "1.0.0", &d_a2, &none);
  if !names_err_is(plugin_resolve(&reg2), "plugin: dependency cycle: a -> b -> a") { ok = false; }
  return assert(ok, "resolve: two-node cycle is reported exactly");
}

fn t18() -> TestResult {
  var reg = plugin_registry_new();
  let none = v0();
  let d_b = v1("b");
  let d_c = v1("c");
  let d_a = v1("a");
  reg = add(&reg, "a", "1.0.0", &d_b, &none);
  reg = add(&reg, "b", "1.0.0", &d_c, &none);
  reg = add(&reg, "c", "1.0.0", &d_a, &none);
  var ok = names_err_is(plugin_resolve(&reg), "plugin: dependency cycle: a -> b -> c -> a");
  var reg2 = plugin_registry_new();
  let d_b2 = v1("b");
  let d_c2 = v1("c");
  let d_a2 = v1("a");
  reg2 = add0(&reg2, "d", "1.0.0");
  reg2 = add(&reg2, "a", "1.0.0", &d_b2, &none);
  reg2 = add(&reg2, "b", "1.0.0", &d_c2, &none);
  reg2 = add(&reg2, "c", "1.0.0", &d_a2, &none);
  if !names_err_is(plugin_resolve(&reg2), "plugin: dependency cycle: a -> b -> c -> a") { ok = false; }
  return assert(ok, "resolve: three-node cycle behind an independent node");
}

fn t19() -> TestResult {
  let reg = fixture_graph();
  var ok = reg_err_is(plugin_enable(&reg, "nope"), "plugin: unknown plugin: nope");
  if !reg_err_is(plugin_disable(&reg, "core"), "plugin: cannot disable core: state is registered") { ok = false; }
  let reg2 = enable(&reg, "core");
  if !state_is(&reg2, "core", plugin_state_enabled) { ok = false; }
  if plugin_count_by_state(&reg2, plugin_state_enabled) != 1 { ok = false; }
  if !reg_err_is(plugin_enable(&reg2, "core"), "plugin: cannot enable core: state is enabled") { ok = false; }
  if plugin_state(&reg, "core") != plugin_state_registered { ok = false; }
  return assert(ok, "enable/disable: registered <-> enabled only");
}

fn t20() -> TestResult {
  let reg = fixture_layout();
  var ok = reg_err_is(plugin_activate(&reg, "core"), "plugin: cannot activate core: state is registered");
  let reg1 = enable(&reg, "app");
  if !reg_err_is(plugin_activate(&reg1, "app"), "plugin: cannot activate app: dependency not enabled: ui") { ok = false; }
  let reg2 = enable(&reg1, "ui");
  if !reg_err_is(plugin_activate(&reg2, "app"), "plugin: cannot activate app: dependency not enabled: core") { ok = false; }
  let reg3 = enable(&reg2, "core");
  let reg4 = activate(&reg3, "core");
  if !state_is(&reg4, "core", plugin_state_active) { ok = false; }
  let reg5 = activate(&reg4, "ui");
  if !state_is(&reg5, "ui", plugin_state_active) { ok = false; }
  let reg6 = activate(&reg5, "app");
  if !state_is(&reg6, "app", plugin_state_active) { ok = false; }
  if !reg_err_is(plugin_activate(&reg6, "ui"), "plugin: cannot activate ui: state is active") { ok = false; }
  if plugin_state(&reg, "app") != plugin_state_registered { ok = false; }
  return assert(ok, "activate: dependencies must be enabled first");
}

fn t21() -> TestResult {
  let reg = fixture_layout();
  let reg1 = enable_all(&reg);
  let reg2 = activate_all(&reg1);
  var ok = plugin_count_by_state(&reg2, plugin_state_active) == 3;
  let reg3 = deactivate(&reg2, "app");
  if plugin_count_by_state(&reg3, plugin_state_active) != 2 { ok = false; }
  if !reg_err_is(plugin_deactivate(&reg3, "core"), "plugin: cannot deactivate core: active dependent: ui") { ok = false; }
  let reg4 = deactivate(&reg3, "ui");
  let reg5 = deactivate(&reg4, "core");
  if plugin_count_by_state(&reg5, plugin_state_active) != 0 { ok = false; }
  if !reg_err_is(plugin_deactivate(&reg5, "core"), "plugin: cannot deactivate core: state is enabled") { ok = false; }
  if !reg_err_is(plugin_deactivate(&reg5, "nope"), "plugin: unknown plugin: nope") { ok = false; }
  return assert(ok, "deactivate: active dependents block the transition");
}

fn t22() -> TestResult {
  let reg = fixture_graph();
  let reg1 = enable_all(&reg);
  var ok = plugin_count_by_state(&reg1, plugin_state_enabled) == 4;
  let reg2 = activate_all(&reg1);
  if plugin_count_by_state(&reg2, plugin_state_active) != 4 { ok = false; }
  if !reg_err_is(plugin_activate(&reg2, "tool"), "plugin: cannot activate tool: state is active") { ok = false; }
  if !reg_err_is(plugin_disable(&reg2, "tool"), "plugin: cannot disable tool: state is active") { ok = false; }
  if plugin_count_by_state(&reg2, plugin_state_active) != 4 { ok = false; }
  var creg = plugin_registry_new();
  let none = v0();
  let d_b = v1("b");
  let d_a = v1("a");
  creg = add(&creg, "a", "1.0.0", &d_b, &none);
  creg = add(&creg, "b", "1.0.0", &d_a, &none);
  if !reg_err_is(plugin_enable_all(&creg), "plugin: dependency cycle: a -> b -> a") { ok = false; }
  if !reg_err_is(plugin_activate_all(&creg), "plugin: dependency cycle: a -> b -> a") { ok = false; }
  var mreg = plugin_registry_new();
  let d_core = v1("core");
  mreg = add(&mreg, "app", "1.0.0", &d_core, &none);
  if !reg_err_is(plugin_enable_all(&mreg), "plugin: missing dependency: core (required by app)") { ok = false; }
  return assert(ok, "enable_all/activate_all: resolve order and resolve errors");
}

fn t23() -> TestResult {
  let reg = fixture_graph();
  let prov = plugin_providers(&reg, "render");
  var ok = prov.len() == 2;
  if !str_vec_is(&prov, 0, "core") { ok = false; }
  if !str_vec_is(&prov, 1, "ui") { ok = false; }
  if !opt_str_is(plugin_find_capability(&reg, "render"), "core") { ok = false; }
  let st = plugin_providers(&reg, "storage");
  if st.len() != 1 { ok = false; }
  if !str_vec_is(&st, 0, "core") { ok = false; }
  let nonep = plugin_providers(&reg, "nope");
  if nonep.len() != 0 { ok = false; }
  if !opt_str_none(plugin_find_capability(&reg, "nope")) { ok = false; }
  let w = plugin_capabilities(&reg, "app");
  if w.len() != 1 { ok = false; }
  if !str_vec_is(&w, 0, "widgets") { ok = false; }
  if !plugin_has_capability(&reg, "ui", "render") { ok = false; }
  return assert(ok, "capabilities: provider order, first find, unknown caps");
}

fn t24() -> TestResult {
  let reg = fixture_graph();
  var names = plugin_names(&reg);
  names.push("mutated");
  var ok = plugin_count(&reg) == 4;
  if plugin_has(&reg, "mutated") { ok = false; }
  var d = plugin_deps(&reg, "app");
  d.push("mutated");
  let d_again = plugin_deps(&reg, "app");
  if d_again.len() != 2 { ok = false; }
  var c = plugin_capabilities(&reg, "core");
  c.push("mutated");
  let c_again = plugin_capabilities(&reg, "core");
  if c_again.len() != 2 { ok = false; }
  if !opt_str_is(plugin_version(&reg, "core"), "1.4.0") { ok = false; }
  return assert(ok, "enumerations return fresh copies");
}

fn t25() -> TestResult {
  let reg = fixture_graph();
  var ok = plugin_dependency_satisfied(&reg, "app", "ui", ">=1.0.0 <2.0.0");
  if !plugin_dependency_satisfied(&reg, "app", "ui", "^1.0.0") { ok = false; }
  if plugin_dependency_satisfied(&reg, "app", "ui", "^2.0.0") { ok = false; }
  if !plugin_dependency_satisfied(&reg, "app", "core", "=1.4.0") { ok = false; }
  if plugin_dependency_satisfied(&reg, "app", "core", "=1.5.0") { ok = false; }
  if plugin_dependency_satisfied(&reg, "app", "tool", "*") { ok = false; }
  if plugin_dependency_satisfied(&reg, "zz", "core", "*") { ok = false; }
  if plugin_dependency_satisfied(&reg, "app", "zz", "*") { ok = false; }
  if plugin_dependency_satisfied(&reg, "app", "core", ">=") { ok = false; }
  if !opt_str_is(plugin_version(&reg, "app"), "2.0.0") { ok = false; }
  return assert(ok, "dependency_satisfied: declared edges and range checks");
}

fn main() -> Int {
  io.println("=== xiom.plugin conformance tests ===");
  var failed: Int = 0;
  let r01 = t01();
  if r01.passed { io.println("  [PASS] " + r01.name); } else { io.println("  [FAIL] " + r01.name); failed = failed + 1; }
  let r02 = t02();
  if r02.passed { io.println("  [PASS] " + r02.name); } else { io.println("  [FAIL] " + r02.name); failed = failed + 1; }
  let r03 = t03();
  if r03.passed { io.println("  [PASS] " + r03.name); } else { io.println("  [FAIL] " + r03.name); failed = failed + 1; }
  let r04 = t04();
  if r04.passed { io.println("  [PASS] " + r04.name); } else { io.println("  [FAIL] " + r04.name); failed = failed + 1; }
  let r05 = t05();
  if r05.passed { io.println("  [PASS] " + r05.name); } else { io.println("  [FAIL] " + r05.name); failed = failed + 1; }
  let r06 = t06();
  if r06.passed { io.println("  [PASS] " + r06.name); } else { io.println("  [FAIL] " + r06.name); failed = failed + 1; }
  let r07 = t07();
  if r07.passed { io.println("  [PASS] " + r07.name); } else { io.println("  [FAIL] " + r07.name); failed = failed + 1; }
  let r08 = t08();
  if r08.passed { io.println("  [PASS] " + r08.name); } else { io.println("  [FAIL] " + r08.name); failed = failed + 1; }
  let r09 = t09();
  if r09.passed { io.println("  [PASS] " + r09.name); } else { io.println("  [FAIL] " + r09.name); failed = failed + 1; }
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
  if failed == 0 {
    io.println("xiom.plugin: all tests passed");
  } else {
    io.println("xiom.plugin: tests failed");
  }
  return failed;
}
