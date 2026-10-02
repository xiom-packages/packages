// XIOM -- xiom.chef conformance tests (26 checks)
// Port task: prove the pure-XIOM xiom.chef module against its documented
// model: cookbook/recipe/resource builders, runlist and role expansion,
// attribute precedence, explicit provider dispatch, the compile phase,
// immediate/delayed notification and subscription delivery, idempotence
// classification and the canonical converge report.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: builder metadata and recipe ownership; bare/recipe[...] runlist
// equivalence; runlist order across recipes; role expansion including nested
// roles; role cycle detection; the runlist error catalog; attribute
// precedence default < normal < override, same-level last-wins and
// first-position keys; the three-source resolve chain; the provider dispatch
// table; the "provider" override attribute; the compile-phase provider /
// reference validation; a basic all-updated converge; satisfied / nothing
// classification; immediate notification forcing for nothing and satisfied
// targets; delayed notification promotion of an already-converged target;
// subscription inversion; unknown reference errors; exact report rendering;
// delivery to an already-updated target (no double provider call); duplicate
// runlist entries; bare-name references; a bounded immediate notification
// cycle; and error propagation with the zero report.
//
// All Str equality goes through str_compare (BUG 17: `==` on Str values read
// from Vec[Str] elements lowers to a pointer comparison), so every comparison
// below is routed through streq / vec_eq / opt_is.

module chef_tests
use xiom.io; use xiom.test; use xiom.chef;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn opt_is(o: Option[Str], want: Str) -> Bool {
  match o {
    Some(v) => { return streq(v, want); },
    None => { return false; },
  }
  return false;
}

fn opt_none(o: Option[Str]) -> Bool {
  match o {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

fn vec_is(v: &Vec[Str], i: Int, want: Str) -> Bool {
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

// The standard fixture: recipes base (0), web (1), db (2); five resources.
//   base: package[coreutils] install
//   web:  package[nginx] install, service[nginx] start, template[nginx.conf]
//   db:   package[postgresql] install
fn web_cookbook() -> Cookbook {
  var cb = chef_cookbook_new("site");
  let base = chef_add_recipe(&mut cb, "base");
  let web = chef_add_recipe(&mut cb, "web");
  let db = chef_add_recipe(&mut cb, "db");
  chef_add_resource(&mut cb, base, "package", "coreutils", "install");
  chef_add_resource(&mut cb, web, "package", "nginx", "install");
  chef_add_resource(&mut cb, web, "service", "nginx", "start");
  let tpl = chef_add_resource(&mut cb, web, "template", "nginx.conf", "create");
  chef_set_attr(&mut cb, tpl, "satisfied", "false");
  chef_add_resource(&mut cb, db, "package", "postgresql", "install");
  return cb;
}

fn empty_roles() -> RoleSet {
  return chef_roleset_new();
}

fn one_entry_runlist(e: Str) -> Vec[Str] {
  var rl = Vec[Str].new();
  rl.push(e);
  return rl;
}

fn expand_is(cb: &Cookbook, rs: &RoleSet, rl: &Vec[Str], want: &Vec[Str]) -> Bool {
  let r = chef_runlist_expand(cb, rs, rl);
  match r {
    Ok(v) => { return vec_eq(&v, want); },
    Err(_) => { return false; },
  }
  return false;
}

fn expand_err_is(cb: &Cookbook, rs: &RoleSet, rl: &Vec[Str], want: Str) -> Bool {
  let r = chef_runlist_expand(cb, rs, rl);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn compile_len(cb: &Cookbook, rs: &RoleSet, rl: &Vec[Str]) -> Int {
  let r = chef_compile(cb, rs, rl);
  match r {
    Ok(c) => { return chef_collection_len(&c); },
    Err(_) => { return -1; },
  }
  return -1;
}

fn compile_err_is(cb: &Cookbook, rs: &RoleSet, rl: &Vec[Str], want: Str) -> Bool {
  let r = chef_compile(cb, rs, rl);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn conv_expect(cb: &Cookbook, rs: &RoleSet, rl: &Vec[Str], u: Int, un: Int, sk: Int, calls: Int, imm: Int, del: Int) -> Bool {
  let r = chef_converge(cb, rs, rl);
  match r {
    Ok(rep) => {
      var ok = rep.updated == u;
      if rep.unchanged != un { ok = false; }
      if rep.skipped != sk { ok = false; }
      if rep.provider_calls != calls { ok = false; }
      if rep.immediate_fired != imm { ok = false; }
      if rep.delayed_fired != del { ok = false; }
      if rep.total != u + un + sk { ok = false; }
      return ok;
    },
    Err(_) => { return false; },
  }
  return false;
}

fn converge_err_is(cb: &Cookbook, rs: &RoleSet, rl: &Vec[Str], want: Str) -> Bool {
  let r = chef_converge(cb, rs, rl);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn converge_render(cb: &Cookbook, rs: &RoleSet, rl: &Vec[Str]) -> Str {
  let r = chef_converge(cb, rs, rl);
  match r {
    Ok(rep) => { return chef_report_render(&rep); },
    Err(e) => { return "ERR:" + e; },
  }
  return "";
}

fn prov_is(t: Str, want: Str) -> Bool {
  let r = chef_provider_for(t);
  match r {
    Ok(p) => { return streq(p, want); },
    Err(_) => { return false; },
  }
  return false;
}

fn prov_err(t: Str, want: Str) -> Bool {
  let r = chef_provider_for(t);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn res_prov_is(cb: &Cookbook, res: Int, want: Str) -> Bool {
  let r = chef_resource_provider(cb, res);
  match r {
    Ok(p) => { return streq(p, want); },
    Err(_) => { return false; },
  }
  return false;
}

fn res_prov_err(cb: &Cookbook, res: Int, want: Str) -> Bool {
  let r = chef_resource_provider(cb, res);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// t01 -- builders, metadata and recipe ownership.
fn t01() -> TestResult {
  let cb = web_cookbook();
  var ok = streq(cb.name, "site");
  if cb.recipes.len() != 3 { ok = false; }
  if !vec_is(&cb.recipes, 0, "base") { ok = false; }
  if !vec_is(&cb.recipes, 1, "web") { ok = false; }
  if !vec_is(&cb.recipes, 2, "db") { ok = false; }
  if cb.res_type.len() != 5 { ok = false; }
  if cb.res_recipe[0] != 0 { ok = false; }
  if cb.res_recipe[3] != 1 { ok = false; }
  if cb.res_recipe[4] != 2 { ok = false; }
  return assert(ok, "builders: cookbook metadata and recipe ownership");
}

// t02 -- bare name and recipe[...] runlist entries are equivalent.
fn t02() -> TestResult {
  let cb = web_cookbook();
  let rs = empty_roles();
  let a = chef_runlist_expand(&cb, &rs, &one_entry_runlist("web"));
  var ok = false;
  match a {
    Ok(va) => {
      let b = chef_runlist_expand(&cb, &rs, &one_entry_runlist("recipe[web]"));
      match b {
        Ok(vb) => {
          ok = va.len() == 1 && vec_eq(&va, &vb);
        },
        Err(_) => { ok = false; },
      }
      if !vec_is(&va, 0, "web") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if compile_len(&cb, &rs, &one_entry_runlist("web")) != 3 { ok = false; }
  if compile_len(&cb, &rs, &one_entry_runlist("recipe[web]")) != 3 { ok = false; }
  return assert(ok, "runlist: bare name == recipe[name]");
}

// t03 -- compile preserves runlist order across recipes.
fn t03() -> TestResult {
  let cb = web_cookbook();
  let rs = empty_roles();
  var rl = Vec[Str].new();
  rl.push("recipe[base]");
  rl.push("recipe[db]");
  rl.push("recipe[web]");
  let r = chef_compile(&cb, &rs, &rl);
  var ok = false;
  match r {
    Ok(col) => {
      ok = chef_collection_len(&col) == 5;
      if !streq(chef_collection_name(&col, 0), "coreutils") { ok = false; }
      if !streq(chef_collection_name(&col, 1), "postgresql") { ok = false; }
      if !streq(chef_collection_name(&col, 2), "nginx") { ok = false; }
      if !streq(chef_collection_type(&col, 2), "package") { ok = false; }
      if !streq(chef_collection_type(&col, 3), "service") { ok = false; }
      if !streq(chef_collection_type(&col, 4), "template") { ok = false; }
      if !streq(chef_collection_name(&col, 4), "nginx.conf") { ok = false; }
      if !streq(chef_collection_recipe(&col, 0), "base") { ok = false; }
      if !streq(chef_collection_recipe(&col, 1), "db") { ok = false; }
      if !streq(chef_collection_recipe(&col, 4), "web") { ok = false; }
      if !opt_is(chef_collection_attr(&col, 4, "satisfied"), "false") { ok = false; }
      if !opt_none(chef_collection_attr(&col, 0, "satisfied")) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "compile: runlist order, recipes, accessors");
}

// t04 -- role expansion in declaration order.
fn t04() -> TestResult {
  let cb = web_cookbook();
  var rs = chef_roleset_new();
  let wr = chef_add_role(&mut rs, "web_role");
  chef_role_entry(&mut rs, wr, "recipe[base]");
  chef_role_entry(&mut rs, wr, "recipe[web]");
  var want = Vec[Str].new();
  want.push("base");
  want.push("web");
  var ok = expand_is(&cb, &rs, &one_entry_runlist("role[web_role]"), &want);
  if compile_len(&cb, &rs, &one_entry_runlist("role[web_role]")) != 4 { ok = false; }
  return assert(ok, "runlist: role expands to its entries in order");
}

// t05 -- nested roles expand depth-first in declaration order.
fn t05() -> TestResult {
  let cb = web_cookbook();
  var rs = chef_roleset_new();
  let br = chef_add_role(&mut rs, "base_role");
  chef_role_entry(&mut rs, br, "recipe[base]");
  let all = chef_add_role(&mut rs, "all");
  chef_role_entry(&mut rs, all, "role[base_role]");
  chef_role_entry(&mut rs, all, "recipe[db]");
  var want = Vec[Str].new();
  want.push("base");
  want.push("db");
  var ok = expand_is(&cb, &rs, &one_entry_runlist("role[all]"), &want);
  return assert(ok, "runlist: nested roles expand depth-first");
}

// t06 -- role cycles are detected and reported.
fn t06() -> TestResult {
  let cb = web_cookbook();
  var rs = chef_roleset_new();
  let a = chef_add_role(&mut rs, "a");
  let b = chef_add_role(&mut rs, "b");
  chef_role_entry(&mut rs, a, "role[b]");
  chef_role_entry(&mut rs, b, "role[a]");
  var ok = expand_err_is(&cb, &rs, &one_entry_runlist("role[a]"), "chef: role cycle: a");
  return assert(ok, "runlist: role cycle detection");
}

// t07 -- the runlist error catalog.
fn t07() -> TestResult {
  let cb = web_cookbook();
  let rs = empty_roles();
  var ok = expand_err_is(&cb, &rs, &one_entry_runlist("recipe[ghost]"), "chef: unknown recipe: ghost");
  if !expand_err_is(&cb, &rs, &one_entry_runlist("ghost"), "chef: unknown recipe: ghost") { ok = false; }
  if !expand_err_is(&cb, &rs, &one_entry_runlist("role[ghost]"), "chef: unknown role: ghost") { ok = false; }
  if !expand_err_is(&cb, &rs, &one_entry_runlist("recipe["), "chef: malformed runlist entry: recipe[") { ok = false; }
  if !expand_err_is(&cb, &rs, &one_entry_runlist("role[x"), "chef: malformed runlist entry: role[x") { ok = false; }
  if !expand_err_is(&cb, &rs, &one_entry_runlist("recipe[]"), "chef: malformed runlist entry: recipe[]") { ok = false; }
  if !expand_err_is(&cb, &rs, &one_entry_runlist("a[b]"), "chef: malformed runlist entry: a[b]") { ok = false; }
  if !expand_err_is(&cb, &rs, &one_entry_runlist(""), "chef: malformed runlist entry: ") { ok = false; }
  return assert(ok, "runlist errors: unknown and malformed entries");
}

// t08 -- attribute precedence default < normal < override.
fn t08() -> TestResult {
  var a = chef_attrs_new();
  var ok = chef_attrs_set(&mut a, "port", "80", "default");
  if !chef_attrs_set(&mut a, "port", "8080", "normal") { ok = false; }
  if !chef_attrs_set(&mut a, "port", "9000", "override") { ok = false; }
  if !opt_is(chef_attrs_get(&a, "port"), "9000") { ok = false; }
  if chef_attrs_level(&a, "port") != 2 { ok = false; }
  if chef_attrs_level(&a, "ghost") != -1 { ok = false; }
  if chef_attrs_set(&mut a, "x", "y", "forced") { ok = false; }
  if !opt_none(chef_attrs_get(&a, "x")) { ok = false; }
  return assert(ok, "attrs: default < normal < override, bad level rejected");
}

// t09 -- same-level last-wins, lower level never beats a higher one, first
// position kept.
fn t09() -> TestResult {
  var a = chef_attrs_new();
  chef_attrs_set(&mut a, "a", "1", "default");
  chef_attrs_set(&mut a, "b", "2", "default");
  chef_attrs_set(&mut a, "a", "3", "normal");
  chef_attrs_set(&mut a, "a", "9", "default");
  chef_attrs_set(&mut a, "b", "4", "normal");
  chef_attrs_set(&mut a, "a", "5", "normal");
  var ok = opt_is(chef_attrs_get(&a, "a"), "5");
  if chef_attrs_level(&a, "a") != 1 { ok = false; }
  if !opt_is(chef_attrs_get(&a, "b"), "4") { ok = false; }
  if a.keys.len() != 2 { ok = false; }
  if !vec_is(&a.keys, 0, "a") { ok = false; }
  if !vec_is(&a.keys, 1, "b") { ok = false; }
  return assert(ok, "attrs: last-wins at equal level, lower never wins");
}

// t10 -- the documented three-source resolve chain.
fn t10() -> TestResult {
  var d = chef_attrs_new();
  chef_attrs_set(&mut d, "k", "1", "default");
  chef_attrs_set(&mut d, "only_d", "4", "default");
  var n = chef_attrs_new();
  chef_attrs_set(&mut n, "k", "2", "normal");
  chef_attrs_set(&mut n, "only_n", "5", "normal");
  var o = chef_attrs_new();
  chef_attrs_set(&mut o, "k", "3", "override");
  let r = chef_attrs_resolve(&d, &n, &o);
  var ok = opt_is(chef_attrs_get(&r, "k"), "3");
  if chef_attrs_level(&r, "k") != 2 { ok = false; }
  if !opt_is(chef_attrs_get(&r, "only_d"), "4") { ok = false; }
  if chef_attrs_level(&r, "only_d") != 0 { ok = false; }
  if !opt_is(chef_attrs_get(&r, "only_n"), "5") { ok = false; }
  if chef_attrs_level(&r, "only_n") != 1 { ok = false; }
  if r.keys.len() != 3 { ok = false; }
  if !vec_is(&r.keys, 0, "k") { ok = false; }
  if !vec_is(&r.keys, 1, "only_d") { ok = false; }
  if !vec_is(&r.keys, 2, "only_n") { ok = false; }
  let back = chef_attrs_merge(&r, &d);
  if !opt_is(chef_attrs_get(&back, "k"), "3") { ok = false; }
  return assert(ok, "attrs: resolve merges defaults <- normal <- overrides");
}

// t11 -- the provider dispatch table.
fn t11() -> TestResult {
  var ok = prov_is("package", "package");
  if !prov_is("service", "service") { ok = false; }
  if !prov_is("file", "file") { ok = false; }
  if !prov_is("template", "file") { ok = false; }
  if !prov_is("cookbook_file", "file") { ok = false; }
  if !prov_is("remote_file", "file") { ok = false; }
  if !prov_is("directory", "file") { ok = false; }
  if !prov_is("execute", "execute") { ok = false; }
  if !prov_is("bash", "execute") { ok = false; }
  if !prov_is("script", "execute") { ok = false; }
  if !prov_is("group", "group") { ok = false; }
  if !prov_is("user", "user") { ok = false; }
  if !prov_err("fridge", "chef: no provider for resource type: fridge") { ok = false; }
  return assert(ok, "provider: explicit dispatch table and unknown type");
}

// t12 -- the "provider" resource attribute overrides type dispatch.
fn t12() -> TestResult {
  var cb = chef_cookbook_new("x");
  let r = chef_add_recipe(&mut cb, "r");
  let r0 = chef_add_resource(&mut cb, r, "file", "cfg", "create");
  chef_set_attr(&mut cb, r0, "provider", "execute");
  let r1 = chef_add_resource(&mut cb, r, "file", "cfg2", "create");
  chef_set_attr(&mut cb, r1, "provider", "wizard");
  chef_add_resource(&mut cb, r, "template", "cfg3", "create");
  var ok = res_prov_is(&cb, r0, "execute");
  if !res_prov_err(&cb, r1, "chef: unknown provider name: wizard") { ok = false; }
  if !res_prov_is(&cb, 2, "file") { ok = false; }
  return assert(ok, "provider: resource attribute override is explicit");
}

// t13 -- compile validates providers; an empty runlist compiles empty.
fn t13() -> TestResult {
  var cb = chef_cookbook_new("x");
  let r = chef_add_recipe(&mut cb, "r");
  chef_add_resource(&mut cb, r, "package", "ok", "install");
  chef_add_resource(&mut cb, r, "fridge", "cold", "cool");
  let rs = empty_roles();
  var ok = compile_err_is(&cb, &rs, &one_entry_runlist("r"), "chef: no provider for resource type: fridge");
  let empty = Vec[Str].new();
  if compile_len(&cb, &rs, &empty) != 0 { ok = false; }
  return assert(ok, "compile: unknown provider type rejected, empty runlist empty");
}

// t14 -- a basic converge: everything absent -> updated.
fn t14() -> TestResult {
  let cb = web_cookbook();
  let rs = empty_roles();
  let ok = conv_expect(&cb, &rs, &one_entry_runlist("web"), 3, 0, 0, 3, 0, 0);
  return assert(ok, "converge: unsatisfied resources all update");
}

// t15 -- satisfied / nothing classification.
fn t15() -> TestResult {
  var cb = chef_cookbook_new("x");
  let r = chef_add_recipe(&mut cb, "r");
  let s = chef_add_resource(&mut cb, r, "service", "a", "restart");
  chef_set_attr(&mut cb, s, "satisfied", "true");
  chef_add_resource(&mut cb, r, "package", "b", "nothing");
  chef_add_resource(&mut cb, r, "package", "c", "install");
  let rs = empty_roles();
  let ok = conv_expect(&cb, &rs, &one_entry_runlist("r"), 1, 1, 1, 1, 0, 0);
  return assert(ok, "converge: updated / unchanged / skipped split");
}

// t16 -- an immediate notification forces a "nothing" target to run.
fn t16() -> TestResult {
  var cb = chef_cookbook_new("x");
  let r = chef_add_recipe(&mut cb, "r");
  let t = chef_add_resource(&mut cb, r, "package", "t", "install");
  chef_add_resource(&mut cb, r, "service", "s", "nothing");
  chef_notifies(&mut cb, t, "restart", "service[s]", "immediate");
  let rs = empty_roles();
  let ok = conv_expect(&cb, &rs, &one_entry_runlist("r"), 2, 0, 0, 2, 1, 0);
  return assert(ok, "converge: immediate notification forces a nothing resource");
}

// t17 -- an immediate notification forces a satisfied target too.
fn t17() -> TestResult {
  var cb = chef_cookbook_new("x");
  let r = chef_add_recipe(&mut cb, "r");
  let t = chef_add_resource(&mut cb, r, "package", "t", "install");
  let s = chef_add_resource(&mut cb, r, "service", "s", "restart");
  chef_set_attr(&mut cb, s, "satisfied", "true");
  chef_notifies(&mut cb, t, "restart", "service[s]", "immediate");
  let rs = empty_roles();
  let ok = conv_expect(&cb, &rs, &one_entry_runlist("r"), 2, 0, 0, 2, 1, 0);
  return assert(ok, "converge: immediate notification forces a satisfied target");
}

// t18 -- delayed delivery promotes an already-converged unchanged target.
fn t18() -> TestResult {
  var cb = chef_cookbook_new("x");
  let r = chef_add_recipe(&mut cb, "r");
  let s = chef_add_resource(&mut cb, r, "service", "s", "restart");
  chef_set_attr(&mut cb, s, "satisfied", "true");
  let t = chef_add_resource(&mut cb, r, "template", "c", "create");
  chef_notifies(&mut cb, t, "restart", "service[s]", "delayed");
  let rs = empty_roles();
  let ok = conv_expect(&cb, &rs, &one_entry_runlist("r"), 2, 0, 0, 2, 0, 1);
  return assert(ok, "converge: delayed delivery promotes an unchanged target");
}

// t19 -- a subscription is the inverse view of a notification.
fn t19() -> TestResult {
  var cb = chef_cookbook_new("x");
  let r = chef_add_recipe(&mut cb, "r");
  chef_add_resource(&mut cb, r, "template", "c", "create");
  let s = chef_add_resource(&mut cb, r, "service", "s", "restart");
  chef_set_attr(&mut cb, s, "satisfied", "true");
  let sub_ok = chef_subscribes(&mut cb, s, "restart", "template[c]", "immediate");
  let rs = empty_roles();
  var ok = sub_ok;
  if !conv_expect(&cb, &rs, &one_entry_runlist("r"), 2, 0, 0, 2, 1, 0) { ok = false; }
  return assert(ok, "converge: subscription inverts into a delivery");
}

// t20 -- unknown notification targets and subscription sources fail compile.
fn t20() -> TestResult {
  let rs = empty_roles();
  var cb = chef_cookbook_new("x");
  let r = chef_add_recipe(&mut cb, "r");
  let a = chef_add_resource(&mut cb, r, "package", "a", "install");
  chef_notifies(&mut cb, a, "restart", "service[ghost]", "immediate");
  var ok = compile_err_is(&cb, &rs, &one_entry_runlist("r"), "chef: unknown notification target: service[ghost]");
  var cb2 = chef_cookbook_new("y");
  let r2 = chef_add_recipe(&mut cb2, "r");
  let b = chef_add_resource(&mut cb2, r2, "service", "b", "restart");
  chef_subscribes(&mut cb2, b, "restart", "template[ghost]", "delayed");
  if !compile_err_is(&cb2, &rs, &one_entry_runlist("r"), "chef: unknown subscription source: template[ghost]") { ok = false; }
  return assert(ok, "compile: unknown reference targets are errors");
}

// t21 -- exact report rendering, including event order.
fn t21() -> TestResult {
  var cb = chef_cookbook_new("x");
  let r = chef_add_recipe(&mut cb, "r");
  let s = chef_add_resource(&mut cb, r, "service", "svc", "restart");
  chef_set_attr(&mut cb, s, "satisfied", "true");
  let t = chef_add_resource(&mut cb, r, "template", "cfg", "create");
  chef_notifies(&mut cb, t, "restart", "service[svc]", "delayed");
  let rs = empty_roles();
  let want = "chef report: total=2 updated=2 unchanged=0 skipped=0\nprovider_calls=2 immediate=0 delayed=1\nevent: unchanged: service[svc]\nevent: updated: template[cfg]\nevent: delayed: template[cfg] -> service[svc]\nevent: notified-update: service[svc]";
  let ok = streq(converge_render(&cb, &rs, &one_entry_runlist("r")), want);
  return assert(ok, "report: canonical render and event order");
}

// t22 -- delivery to an already-updated target does not double-run it.
fn t22() -> TestResult {
  var cb = chef_cookbook_new("x");
  let r = chef_add_recipe(&mut cb, "r");
  let s = chef_add_resource(&mut cb, r, "service", "s", "restart");
  chef_notifies(&mut cb, s, "restart", "package[t]", "delayed");
  chef_add_resource(&mut cb, r, "package", "t", "install");
  let rs = empty_roles();
  let ok = conv_expect(&cb, &rs, &one_entry_runlist("r"), 2, 0, 0, 2, 0, 1);
  return assert(ok, "converge: already-updated target keeps one provider call");
}

// t23 -- duplicate runlist entries are preserved as written.
fn t23() -> TestResult {
  let cb = web_cookbook();
  let rs = empty_roles();
  var rl = Vec[Str].new();
  rl.push("web");
  rl.push("web");
  var want = Vec[Str].new();
  want.push("web");
  want.push("web");
  var ok = expand_is(&cb, &rs, &rl, &want);
  if compile_len(&cb, &rs, &rl) != 6 { ok = false; }
  return assert(ok, "runlist: duplicate recipes preserved in order");
}

// t24 -- a bare name target resolves the first matching resource.
fn t24() -> TestResult {
  var cb = chef_cookbook_new("x");
  let r = chef_add_recipe(&mut cb, "r");
  let t = chef_add_resource(&mut cb, r, "package", "t", "install");
  let s = chef_add_resource(&mut cb, r, "service", "svc", "restart");
  chef_set_attr(&mut cb, s, "satisfied", "true");
  chef_notifies(&mut cb, t, "restart", "svc", "immediate");
  let rs = empty_roles();
  let ok = conv_expect(&cb, &rs, &one_entry_runlist("r"), 2, 0, 0, 2, 1, 0);
  return assert(ok, "converge: bare-name notification target resolves");
}

// t25 -- an immediate notification cycle is bounded, not recursive.
fn t25() -> TestResult {
  var cb = chef_cookbook_new("x");
  let r = chef_add_recipe(&mut cb, "r");
  let a = chef_add_resource(&mut cb, r, "package", "a", "install");
  let b = chef_add_resource(&mut cb, r, "package", "b", "nothing");
  chef_notifies(&mut cb, a, "restart", "package[b]", "immediate");
  chef_notifies(&mut cb, b, "restart", "package[a]", "immediate");
  let rs = empty_roles();
  let ok = conv_expect(&cb, &rs, &one_entry_runlist("r"), 2, 0, 0, 2, 2, 0);
  return assert(ok, "converge: notification cycle converges once per resource");
}

// t26 -- converge error propagation and the zero report.
fn t26() -> TestResult {
  var cb = chef_cookbook_new("x");
  let r = chef_add_recipe(&mut cb, "r");
  chef_add_resource(&mut cb, r, "fridge", "cold", "cool");
  let rs = empty_roles();
  var ok = converge_err_is(&cb, &rs, &one_entry_runlist("r"), "chef: no provider for resource type: fridge");
  var empty_cb = chef_cookbook_new("empty");
  let empty = Vec[Str].new();
  let want = "chef report: total=0 updated=0 unchanged=0 skipped=0\nprovider_calls=0 immediate=0 delayed=0";
  if !streq(converge_render(&empty_cb, &rs, &empty), want) { ok = false; }
  return assert(ok, "converge: errors propagate, empty run is all zeros");
}

fn main() -> Int {
  io.println("=== xiom.chef conformance tests ===");
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
  let r26 = t26();
  if r26.passed { io.println("  [PASS] " + r26.name); } else { io.println("  [FAIL] " + r26.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.chef: all tests passed");
  } else {
    io.println("xiom.chef: tests failed");
  }
  return failed;
}
