// XIOM -- xiom.puppet conformance tests (26 checks)
// Port task: prove the pure-XIOM xiom.puppet module against its documented
// model: manifest parsing (classes, resources, attributes, metaparams,
// chains), module metadata validation and layout, hiera lookup (first /
// unique / hash merge and %{...} interpolation), catalog dependency ordering
// and the deterministic apply / idempotence / failure / refresh report.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: parse structure and ownership; metaparam extraction; chaining;
// the parse error catalog; accessor guards; module validation errors; module
// immutable builders and file layout; module duplicate/self errors; hiera
// priority, first/unique/hash merge; interpolation success, escapes, errors
// and recursion depth; catalog topology (require / chain / notify /
// subscribe); the catalog error catalog; apply basics, absent/present
// classification, idempotence, notify and subscribe refresh, failure
// propagation, exact report rendering, an end-to-end web fixture and parser
// edge cases.
//
// All Str equality goes through str_compare (BUG 17: `==` on Str values read
// from Vec[Str] elements lowers to a pointer comparison), so every comparison
// below is routed through streq / vec_is / vec_eq / opt_is.

module puppet_tests
use xiom.io;
use xiom.test;
use xiom.puppet;
use xiom.string;
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

fn man_err_has(r: Result[Manifest, Str], needle: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_contains(e, needle); },
  }
  return false;
}

fn cat_err_has(r: Result[Catalog, Str], needle: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_contains(e, needle); },
  }
  return false;
}

fn str_err_has(r: Result[Str, Str], needle: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_contains(e, needle); },
  }
  return false;
}

fn strs_err_has(r: Result[Vec[Str], Str], needle: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_contains(e, needle); },
  }
  return false;
}

fn scope_err_has(r: Result[Scope, Str], needle: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_contains(e, needle); },
  }
  return false;
}

fn apply_expect(text: Str, cls: Str, st: &mut State, wc: Int, wu: Int, ws: Int, wf: Int, wcalls: Int, wr: Int, wt: Int) -> Bool {
  let m = puppet_manifest_parse(text);
  match m {
    Ok(mm) => {
      let c = puppet_catalog(&mm, cls);
      match c {
        Ok(cc) => {
          let rep = puppet_apply(&cc, st);
          var ok = rep.changed == wc;
          if rep.unchanged != wu { ok = false; }
          if rep.skipped != ws { ok = false; }
          if rep.failed != wf { ok = false; }
          if rep.provider_calls != wcalls { ok = false; }
          if rep.refreshed != wr { ok = false; }
          if rep.total != wt { ok = false; }
          if rep.applied != wc + wu { ok = false; }
          return ok;
        },
        Err(_) => { return false; },
      }
    },
    Err(_) => { return false; },
  }
  return false;
}

fn render_of(text: Str, cls: Str, st: &mut State) -> Str {
  let m = puppet_manifest_parse(text);
  match m {
    Ok(mm) => {
      let c = puppet_catalog(&mm, cls);
      match c {
        Ok(cc) => {
          let rep = puppet_apply(&cc, st);
          return puppet_report_render(&rep);
        },
        Err(e) => { return "CATERR:" + e; },
      }
    },
    Err(e) => { return "MANERR:" + e; },
  }
  return "";
}

fn has_edge(c: &Catalog, from: Int, to: Int) -> Bool {
  var i = 0;
  while i < puppet_catalog_edge_count(c) {
    let f: Int = puppet_catalog_edge_from(c, i);
    let t: Int = puppet_catalog_edge_to(c, i);
    if f == from && t == to {
      return true;
    }
    i = i + 1;
  }
  return false;
}

fn has_refresh(c: &Catalog, from: Int, to: Int) -> Bool {
  var i = 0;
  while i < puppet_catalog_refresh_count(c) {
    let f: Int = puppet_catalog_refresh_from(c, i);
    let t: Int = puppet_catalog_refresh_to(c, i);
    if f == from && t == to {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// The standard fixture: two classes. Class web: package[openssl] (0),
// package[nginx] (1) requiring openssl, file[nginx.conf] (2) notifying the
// nginx service, service[nginx] (3), exec[reload] (4) subscribing to the
// file. Class db: package[postgresql] (5).
fn web_manifest() -> Str {
  var s = "# site manifest\n";
  s = s + "class web {\n";
  s = s + "  package { 'openssl': ensure => present, }\n";
  s = s + "  package { 'nginx': ensure => present, require => Package['openssl'], }\n";
  s = s + "  file { 'nginx.conf': ensure => present, notify => Service['nginx'], }\n";
  s = s + "  service { 'nginx': ensure => present, }\n";
  s = s + "  exec { 'reload': ensure => 'present', subscribe => File['nginx.conf'], fail => false, }\n";
  s = s + "}\n";
  s = s + "class db {\n";
  s = s + "  package { 'postgresql': ensure => present, }\n";
  s = s + "}\n";
  return s;
}

// Three packages chained with arrows: a -> b -> c.
fn chain_manifest() -> Str {
  var s = "class chain {\n";
  s = s + "  package { 'a': ensure => present, }\n";
  s = s + "  package { 'b': ensure => present, }\n";
  s = s + "  package { 'c': ensure => present, }\n";
  s = s + "  Package['a'] -> Package['b'] -> Package['c']\n";
  s = s + "}\n";
  return s;
}

fn simple_package_manifest() -> Str {
  var s = "class srv {\n";
  s = s + "  package { 'a': ensure => present, }\n";
  s = s + "  package { 'b': ensure => present, }\n";
  s = s + "}\n";
  return s;
}

fn three_state_manifest() -> Str {
  var s = "class srv {\n";
  s = s + "  package { 'a': ensure => present, }\n";
  s = s + "  package { 'b': ensure => absent, }\n";
  s = s + "  package { 'c': ensure => present, }\n";
  s = s + "}\n";
  return s;
}

// service[svc] declared first, file[cfg] declared second; cfg notifies svc.
fn notify_manifest() -> Str {
  var s = "class r {\n";
  s = s + "  service { 'svc': ensure => present, }\n";
  s = s + "  file { 'cfg': ensure => present, notify => Service['svc'], }\n";
  s = s + "}\n";
  return s;
}

// service[svc] subscribes to file[cfg]; the subscribe edge is the inverse
// view of notify.
fn subscribe_manifest() -> Str {
  var s = "class r {\n";
  s = s + "  service { 'svc': ensure => present, subscribe => File['cfg'], }\n";
  s = s + "  file { 'cfg': ensure => present, }\n";
  s = s + "}\n";
  return s;
}

// A failing a blocks b, which blocks c.
fn fail_manifest() -> Str {
  var s = "class f {\n";
  s = s + "  package { 'a': ensure => present, fail => true, }\n";
  s = s + "  package { 'b': ensure => present, require => Package['a'], }\n";
  s = s + "  package { 'c': ensure => present, require => Package['b'], }\n";
  s = s + "}\n";
  return s;
}

// t01 -- parse structure: classes, resources, ownership.
fn t01() -> TestResult {
  let m = puppet_manifest_parse(web_manifest());
  var ok = false;
  match m {
    Ok(mm) => {
      ok = puppet_manifest_class_count(&mm) == 2;
      if !streq(puppet_manifest_class_name(&mm, 0), "web") { ok = false; }
      if !streq(puppet_manifest_class_name(&mm, 1), "db") { ok = false; }
      if puppet_manifest_resource_count(&mm) != 6 { ok = false; }
      if !streq(puppet_manifest_resource_type(&mm, 0), "package") { ok = false; }
      if !streq(puppet_manifest_resource_title(&mm, 1), "nginx") { ok = false; }
      if !streq(puppet_manifest_resource_ref(&mm, 2), "file[nginx.conf]") { ok = false; }
      if puppet_manifest_resource_class(&mm, 0) != 0 { ok = false; }
      if puppet_manifest_resource_class(&mm, 5) != 1 { ok = false; }
      if puppet_manifest_resource_class(&mm, 6) != -1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "manifest: classes, resources, ownership");
}

// t02 -- metaparam rows are extracted, not stored as attributes.
fn t02() -> TestResult {
  let m = puppet_manifest_parse(web_manifest());
  var ok = false;
  match m {
    Ok(mm) => {
      ok = puppet_manifest_rel_count(&mm) == 3;
      if puppet_manifest_rel_owner(&mm, 0) != 1 { ok = false; }
      if !streq(puppet_manifest_rel_kind(&mm, 0), "require") { ok = false; }
      if !streq(puppet_manifest_rel_src_type(&mm, 0), "package") { ok = false; }
      if !streq(puppet_manifest_rel_src_title(&mm, 0), "nginx") { ok = false; }
      if !streq(puppet_manifest_rel_type(&mm, 0), "Package") { ok = false; }
      if !streq(puppet_manifest_rel_title(&mm, 0), "openssl") { ok = false; }
      if !streq(puppet_manifest_rel_kind(&mm, 1), "notify") { ok = false; }
      if !streq(puppet_manifest_rel_title(&mm, 1), "nginx") { ok = false; }
      if !streq(puppet_manifest_rel_kind(&mm, 2), "subscribe") { ok = false; }
      if !opt_none(puppet_manifest_attr(&mm, 1, "require")) { ok = false; }
      if !opt_is(puppet_manifest_attr(&mm, 0, "ensure"), "present") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "manifest: metaparams become relationship rows");
}

// t03 -- chained arrows parse into source/target rows with owner -1.
fn t03() -> TestResult {
  let m = puppet_manifest_parse(chain_manifest());
  var ok = false;
  match m {
    Ok(mm) => {
      ok = puppet_manifest_rel_count(&mm) == 2;
      if puppet_manifest_rel_owner(&mm, 0) != -1 { ok = false; }
      if !streq(puppet_manifest_rel_kind(&mm, 0), "chain") { ok = false; }
      if !streq(puppet_manifest_rel_src_title(&mm, 0), "a") { ok = false; }
      if !streq(puppet_manifest_rel_title(&mm, 0), "b") { ok = false; }
      if !streq(puppet_manifest_rel_src_title(&mm, 1), "b") { ok = false; }
      if !streq(puppet_manifest_rel_title(&mm, 1), "c") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "manifest: chained arrows become chain rows");
}

// t04 -- the parse error catalog.
fn t04() -> TestResult {
  var ok = man_err_has(puppet_manifest_parse("nope {}"), "expected class declaration");
  if !man_err_has(puppet_manifest_parse("class web {"), "unterminated class body") { ok = false; }
  if !man_err_has(puppet_manifest_parse("class web { package { 'x' ensure => present } }"), "expected ':' after title") { ok = false; }
  if !man_err_has(puppet_manifest_parse("class web { package { 'x': ensure } }"), "expected '=>'") { ok = false; }
  if !man_err_has(puppet_manifest_parse("class w { file { 'x: ensure => present } }"), "unterminated string") { ok = false; }
  if !man_err_has(puppet_manifest_parse("class a {} class a {}"), "puppet: duplicate class: a") { ok = false; }
  if !man_err_has(puppet_manifest_parse("class w { package { 'x': require => 'y' } }"), "expected resource reference for metaparam: require") { ok = false; }
  let goodm = puppet_manifest_parse("class w { package { 'x': ensure => present } }");
  match goodm {
    Ok(g) => {
      if puppet_manifest_resource_count(&g) != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parse: error catalog and valid manifest");
}

// t05 -- accessor guards and attribute enumeration.
fn t05() -> TestResult {
  let m = puppet_manifest_parse(web_manifest());
  var ok = false;
  match m {
    Ok(mm) => {
      ok = puppet_manifest_class_index(&mm, "db") == 1;
      if puppet_manifest_class_index(&mm, "ghost") != -1 { ok = false; }
      if !streq(puppet_manifest_class_name(&mm, 9), "") { ok = false; }
      if !streq(puppet_manifest_resource_type(&mm, -1), "") { ok = false; }
      if !streq(puppet_manifest_rel_kind(&mm, 9), "") { ok = false; }
      if puppet_manifest_attr_count(&mm) != 7 { ok = false; }
      if !streq(puppet_manifest_attr_key_at(&mm, 0), "ensure") { ok = false; }
      if !opt_none(puppet_manifest_attr(&mm, 0, "ghost")) { ok = false; }
      if !opt_is(puppet_manifest_attr(&mm, 4, "fail"), "false") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "manifest: accessor guards and attribute rows");
}

// t06 -- module validation: a good module is valid; bad fields report.
fn t06() -> TestResult {
  var good = puppet_module_new("web-app", "1.2.3");
  good = puppet_module_add_manifest(&good, "init");
  good = puppet_module_add_dep(&good, "puppetlabs-stdlib");
  var ok = puppet_module_valid(&good);
  if puppet_module_manifest_count(&good) != 1 { ok = false; }
  if puppet_module_dep_count(&good) != 1 { ok = false; }
  if !puppet_module_has_manifest(&good, "init") { ok = false; }
  if !puppet_module_has_dep(&good, "puppetlabs-stdlib") { ok = false; }
  let bad = puppet_module_new("Web", "1.2");
  let errs = puppet_module_validate(&bad);
  if errs.len() != 2 { ok = false; }
  if !vec_is(&errs, 0, "puppet: malformed module name: Web") { ok = false; }
  if !vec_is(&errs, 1, "puppet: malformed module version: 1.2") { ok = false; }
  var badm = puppet_module_new("web-app", "1.2.3");
  badm = puppet_module_add_manifest(&badm, "Bad-Name");
  let errs2 = puppet_module_validate(&badm);
  if errs2.len() != 1 { ok = false; }
  if !vec_is(&errs2, 0, "puppet: malformed manifest name: Bad-Name") { ok = false; }
  return assert(ok, "module: metadata validation");
}

// t07 -- immutable builders and the canonical file layout.
fn t07() -> TestResult {
  let base = puppet_module_new("web-app", "1.2.3");
  let m2 = puppet_module_add_manifest(&base, "init");
  let m3 = puppet_module_add_manifest(&m2, "config");
  var ok = puppet_module_manifest_count(&base) == 0;
  if puppet_module_manifest_count(&m3) != 2 { ok = false; }
  if !puppet_module_has_manifest(&m3, "config") { ok = false; }
  let files = puppet_module_files(&m3);
  if files.len() != 3 { ok = false; }
  if !vec_is(&files, 0, "metadata.json") { ok = false; }
  if !vec_is(&files, 1, "manifests/init.pp") { ok = false; }
  if !vec_is(&files, 2, "manifests/config.pp") { ok = false; }
  return assert(ok, "module: immutable builders and file layout");
}

// t08 -- duplicate manifest, self-dependency and duplicate dependency.
fn t08() -> TestResult {
  var mm = puppet_module_new("web-app", "1.2.3");
  mm = puppet_module_add_manifest(&mm, "init");
  mm = puppet_module_add_manifest(&mm, "init");
  mm = puppet_module_add_dep(&mm, "web-app");
  mm = puppet_module_add_dep(&mm, "web-app");
  let errs = puppet_module_validate(&mm);
  var ok = errs.len() == 3;
  if !vec_is(&errs, 0, "puppet: duplicate manifest: init") { ok = false; }
  if !vec_is(&errs, 1, "puppet: module depends on itself: web-app") { ok = false; }
  if !vec_is(&errs, 2, "puppet: module depends on itself: web-app") { ok = false; }
  return assert(ok, "module: duplicate and self-dependency errors");
}

fn node_scope() -> Scope {
  var sc = puppet_scope_new();
  puppet_scope_set(&mut sc, "node", "web01");
  puppet_scope_set(&mut sc, "dc", "eu");
  return sc;
}

fn three_level_hiera() -> Hiera {
  var h = puppet_hiera_new();
  puppet_hiera_add_level(&mut h, "node");
  puppet_hiera_add_level(&mut h, "env");
  puppet_hiera_add_level(&mut h, "common");
  return h;
}

// t09 -- hierarchy level management and first-lookup priority.
fn t09() -> TestResult {
  var h = three_level_hiera();
  var ok = puppet_hiera_level_count(&h) == 3;
  if !streq(puppet_hiera_level_name(&h, 0), "node") { ok = false; }
  if puppet_hiera_add_level(&mut h, "node") != -1 { ok = false; }
  if !puppet_hiera_set(&mut h, "common", "port", "80") { ok = false; }
  if !puppet_hiera_set(&mut h, "env", "port", "8080") { ok = false; }
  if !puppet_hiera_set(&mut h, "node", "port", "9000") { ok = false; }
  if puppet_hiera_set(&mut h, "ghost", "port", "1") { ok = false; }
  let sc = node_scope();
  let r = puppet_hiera_lookup_first(&h, "port", &sc);
  match r {
    Ok(v) => { ok = streq(v, "9000"); },
    Err(_) => { ok = false; },
  }
  if !str_err_has(puppet_hiera_lookup_first(&h, "ghost", &sc), "no value for key: ghost") { ok = false; }
  return assert(ok, "hiera: first lookup uses hierarchy priority");
}

// t10 -- first lookup interpolates against the scope.
fn t10() -> TestResult {
  var h = three_level_hiera();
  puppet_hiera_set(&mut h, "common", "host", "host-%{::dc}-%{node}");
  puppet_hiera_set(&mut h, "common", "literal", "%%{node}");
  let sc = node_scope();
  var ok = false;
  let r = puppet_hiera_lookup_first(&h, "host", &sc);
  match r {
    Ok(v) => { ok = streq(v, "host-eu-web01"); },
    Err(_) => { ok = false; },
  }
  let r2 = puppet_hiera_lookup_first(&h, "literal", &sc);
  match r2 {
    Ok(v) => {
      if !streq(v, "%{node}") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "hiera: first lookup interpolates and escapes");
}

// t11 -- unique merge: union across levels in hierarchy order, deduped.
fn t11() -> TestResult {
  var h = three_level_hiera();
  puppet_hiera_set(&mut h, "node", "dns", "9.9.9.9");
  puppet_hiera_set(&mut h, "env", "dns", "1.1.1.1");
  puppet_hiera_set(&mut h, "common", "dns", "9.9.9.9");
  let sc = node_scope();
  var want = Vec[Str].new();
  want.push("9.9.9.9");
  want.push("1.1.1.1");
  var ok = false;
  let r = puppet_hiera_lookup_unique(&h, "dns", &sc);
  match r {
    Ok(v) => { ok = vec_eq(&v, &want); },
    Err(_) => { ok = false; },
  }
  if !strs_err_has(puppet_hiera_lookup_unique(&h, "ghost", &sc), "no value for key: ghost") { ok = false; }
  return assert(ok, "hiera: unique merge dedupes in priority order");
}

// t12 -- hash merge: descendants of a prefix, first level wins per subkey.
fn t12() -> TestResult {
  var h = three_level_hiera();
  puppet_hiera_set(&mut h, "common", "users.admin.uid", "1000");
  puppet_hiera_set(&mut h, "common", "users.admin.shell", "/bin/sh");
  puppet_hiera_set(&mut h, "env", "users.admin.uid", "2000");
  puppet_hiera_set(&mut h, "env", "users.admin.groups", "wheel");
  puppet_hiera_set(&mut h, "node", "users.admin.uid", "3000");
  puppet_hiera_set(&mut h, "common", "users", "scalar-ignored");
  let sc = node_scope();
  var ok = false;
  let r = puppet_hiera_lookup_hash(&h, "users.admin", &sc);
  match r {
    Ok(d) => {
      ok = puppet_scope_len(&d) == 3;
      if !opt_is(puppet_scope_get(&d, "uid"), "3000") { ok = false; }
      if !opt_is(puppet_scope_get(&d, "shell"), "/bin/sh") { ok = false; }
      if !opt_is(puppet_scope_get(&d, "groups"), "wheel") { ok = false; }
      if !streq(puppet_scope_key_at(&d, 0), "uid") { ok = false; }
      if !streq(puppet_scope_key_at(&d, 1), "groups") { ok = false; }
      if !streq(puppet_scope_key_at(&d, 2), "shell") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = puppet_hiera_lookup_hash(&h, "users", &sc);
  match r2 {
    Ok(d2) => {
      if puppet_scope_len(&d2) != 3 { ok = false; }
      if !opt_is(puppet_scope_get(&d2, "admin.uid"), "3000") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !scope_err_has(puppet_hiera_lookup_hash(&h, "ghost", &sc), "no hash values for key: ghost") { ok = false; }
  return assert(ok, "hiera: hash merge wins by priority per subkey");
}

// t13 -- interpolation error catalog.
fn t13() -> TestResult {
  let sc = node_scope();
  var ok = str_err_has(puppet_interpolate("%{ghost}", &sc), "unknown variable: ghost");
  if !str_err_has(puppet_interpolate("%{1bad}", &sc), "malformed variable name: 1bad") { ok = false; }
  if !str_err_has(puppet_interpolate("%{oops", &sc), "unterminated variable reference") { ok = false; }
  if !str_err_has(puppet_interpolate("%{}", &sc), "malformed variable name") { ok = false; }
  let r = puppet_interpolate("plain text", &sc);
  match r {
    Ok(v) => {
      if !streq(v, "plain text") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "interpolation: error catalog and plain text");
}

// t14 -- recursive interpolation and the depth guard.
fn t14() -> TestResult {
  var sc = puppet_scope_new();
  puppet_scope_set(&mut sc, "a", "%{b}");
  puppet_scope_set(&mut sc, "b", "done");
  puppet_scope_set(&mut sc, "cycle", "%{cycle}");
  var ok = false;
  let r = puppet_interpolate("%{a}", &sc);
  match r {
    Ok(v) => { ok = streq(v, "done"); },
    Err(_) => { ok = false; },
  }
  if !str_err_has(puppet_interpolate("%{cycle}", &sc), "depth exceeded") { ok = false; }
  return assert(ok, "interpolation: recursion and depth guard");
}

// t15 -- catalog: require reorders resources into dependency order.
fn t15() -> TestResult {
  var s = "class order {\n";
  s = s + "  service { 'app': ensure => present, require => File['app.conf'], }\n";
  s = s + "  file { 'app.conf': ensure => present, }\n";
  s = s + "}\n";
  let m = puppet_manifest_parse(s);
  var ok = false;
  match m {
    Ok(mm) => {
      let c = puppet_catalog(&mm, "order");
      match c {
        Ok(cc) => {
          ok = puppet_catalog_len(&cc) == 2;
          if puppet_catalog_order(&cc, 0) != 1 { ok = false; }
          if puppet_catalog_order(&cc, 1) != 0 { ok = false; }
          if puppet_catalog_order(&cc, 2) != -1 { ok = false; }
          if puppet_catalog_edge_count(&cc) != 1 { ok = false; }
          if puppet_catalog_edge_from(&cc, 0) != 1 { ok = false; }
          if puppet_catalog_edge_to(&cc, 0) != 0 { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "catalog: require reorders into dependency order");
}

// t16 -- catalog edges: require, notify refresh, subscribe refresh; chain.
fn t16() -> TestResult {
  let m = puppet_manifest_parse(web_manifest());
  var ok = false;
  match m {
    Ok(mm) => {
      let c = puppet_catalog(&mm, "web");
      match c {
        Ok(cc) => {
          ok = puppet_catalog_len(&cc) == 5;
          if puppet_catalog_edge_count(&cc) != 3 { ok = false; }
          if !has_edge(&cc, 0, 1) { ok = false; }
          if !has_edge(&cc, 2, 3) { ok = false; }
          if !has_edge(&cc, 2, 4) { ok = false; }
          if puppet_catalog_refresh_count(&cc) != 2 { ok = false; }
          if !has_refresh(&cc, 2, 3) { ok = false; }
          if !has_refresh(&cc, 2, 4) { ok = false; }
          if puppet_catalog_order(&cc, 0) != 0 { ok = false; }
          if puppet_catalog_order(&cc, 4) != 4 { ok = false; }
          if !opt_none(puppet_catalog_attr(&cc, 1, "require")) { ok = false; }
          if !streq(puppet_catalog_ref(&cc, 2), "file[nginx.conf]") { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  let m2 = puppet_manifest_parse(chain_manifest());
  match m2 {
    Ok(mm2) => {
      let c2 = puppet_catalog(&mm2, "chain");
      match c2 {
        Ok(cc2) => {
          if puppet_catalog_edge_count(&cc2) != 2 { ok = false; }
          if !has_edge(&cc2, 0, 1) { ok = false; }
          if !has_edge(&cc2, 1, 2) { ok = false; }
          if puppet_catalog_refresh_count(&cc2) != 0 { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "catalog: metaparam and chain edges");
}

// t17 -- the catalog error catalog.
fn t17() -> TestResult {
  let m = puppet_manifest_parse(web_manifest());
  var ok = false;
  match m {
    Ok(mm) => {
      ok = cat_err_has(puppet_catalog(&mm, "ghost"), "puppet: unknown class: ghost");
      let c = puppet_catalog(&mm, "web");
      match c {
        Ok(cc) => {
          if puppet_catalog_len(&cc) != 5 { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  let u = puppet_manifest_parse("class x { frob { 'a': ensure => present } }");
  match u {
    Ok(mm) => {
      if !cat_err_has(puppet_catalog(&mm, "x"), "puppet: unknown resource type: frob") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let d = puppet_manifest_parse("class x { package { 'a': ensure => present } package { 'a': ensure => present } }");
  match d {
    Ok(mm) => {
      if !cat_err_has(puppet_catalog(&mm, "x"), "puppet: duplicate resource: package[a]") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r = puppet_manifest_parse("class x { package { 'a': ensure => present, require => Package['ghost'], } }");
  match r {
    Ok(mm) => {
      if !cat_err_has(puppet_catalog(&mm, "x"), "puppet: unresolved reference: Package[ghost]") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let cy = puppet_manifest_parse("class x { package { 'a': ensure => present, require => Package['b'], } package { 'b': ensure => present, require => Package['a'], } }");
  match cy {
    Ok(mm) => {
      if !cat_err_has(puppet_catalog(&mm, "x"), "puppet: dependency cycle: package[a]") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "catalog: error catalog");
}

// t18 -- apply basics: both resources change and state is updated.
fn t18() -> TestResult {
  var st = puppet_state_new();
  var ok = apply_expect(simple_package_manifest(), "srv", &mut st, 2, 0, 0, 0, 2, 0, 2);
  if puppet_state_len(&st) != 2 { ok = false; }
  if !opt_is(puppet_state_get(&st, "package[a]"), "present") { ok = false; }
  if !opt_is(puppet_state_get(&st, "package[b]"), "present") { ok = false; }
  return assert(ok, "apply: unchanged state changes every resource");
}

// t19 -- idempotence: a second apply over the updated state changes nothing.
fn t19() -> TestResult {
  var st = puppet_state_new();
  var ok = apply_expect(simple_package_manifest(), "srv", &mut st, 2, 0, 0, 0, 2, 0, 2);
  if !apply_expect(simple_package_manifest(), "srv", &mut st, 0, 2, 0, 0, 0, 0, 2) { ok = false; }
  return assert(ok, "apply: second run is idempotent");
}

// t20 -- present/absent classification against the current state.
fn t20() -> TestResult {
  var st = puppet_state_new();
  puppet_state_set(&mut st, "package[a]", "present");
  puppet_state_set(&mut st, "package[b]", "absent");
  let ok = apply_expect(three_state_manifest(), "srv", &mut st, 1, 2, 0, 0, 1, 0, 3);
  return assert(ok, "apply: ensure matches current state");
}

// t21 -- notify refreshes an unchanged target through the run order.
fn t21() -> TestResult {
  var st = puppet_state_new();
  puppet_state_set(&mut st, "service[svc]", "present");
  let ok = apply_expect(notify_manifest(), "r", &mut st, 2, 0, 0, 0, 2, 1, 2);
  return assert(ok, "apply: notify refreshes an unchanged target");
}

// t22 -- subscribe is the inverse refresh view.
fn t22() -> TestResult {
  var st = puppet_state_new();
  puppet_state_set(&mut st, "service[svc]", "present");
  var ok = apply_expect(subscribe_manifest(), "r", &mut st, 2, 0, 0, 0, 2, 1, 2);
  let m = puppet_manifest_parse(subscribe_manifest());
  match m {
    Ok(mm) => {
      let c = puppet_catalog(&mm, "r");
      match c {
        Ok(cc) => {
          if puppet_catalog_refresh_count(&cc) != 1 { ok = false; }
          if puppet_catalog_refresh_from(&cc, 0) != 1 { ok = false; }
          if puppet_catalog_refresh_to(&cc, 0) != 0 { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "apply: subscribe inverts into a refresh");
}

// t23 -- failure propagation skips dependents transitively.
fn t23() -> TestResult {
  var st = puppet_state_new();
  var ok = apply_expect(fail_manifest(), "f", &mut st, 0, 0, 2, 1, 0, 0, 3);
  if puppet_state_len(&st) != 0 { ok = false; }
  if !opt_none(puppet_state_get(&st, "package[a]")) { ok = false; }
  let want = "puppet report: total=3 applied=0 changed=0 unchanged=0 skipped=2 failed=1\nprovider_calls=0 refreshed=0\nevent: failed: package[a]\nevent: skipped: package[b] (dependency failed)\nevent: skipped: package[c] (dependency failed)";
  var st2 = puppet_state_new();
  if !streq(render_of(fail_manifest(), "f", &mut st2), want) { ok = false; }
  return assert(ok, "apply: failure propagates to dependents");
}

// t24 -- exact report rendering, including the empty catalog.
fn t24() -> TestResult {
  var st = puppet_state_new();
  puppet_state_set(&mut st, "service[svc]", "present");
  let want = "puppet report: total=2 applied=2 changed=2 unchanged=0 skipped=0 failed=0\nprovider_calls=2 refreshed=1\nevent: changed: file[cfg]\nevent: refreshed: service[svc]";
  var ok = streq(render_of(notify_manifest(), "r", &mut st), want);
  var st2 = puppet_state_new();
  let empty = "class e {}\n";
  let want2 = "puppet report: total=0 applied=0 changed=0 unchanged=0 skipped=0 failed=0\nprovider_calls=0 refreshed=0";
  if !streq(render_of(empty, "e", &mut st2), want2) { ok = false; }
  return assert(ok, "report: exact rendering and empty catalog");
}

// t25 -- end to end: parse, catalog and apply the web fixture twice.
fn t25() -> TestResult {
  var st = puppet_state_new();
  var ok = apply_expect(web_manifest(), "web", &mut st, 5, 0, 0, 0, 5, 0, 5);
  if !apply_expect(web_manifest(), "web", &mut st, 0, 5, 0, 0, 0, 0, 5) { ok = false; }
  if !opt_is(puppet_state_get(&st, "package[openssl]"), "present") { ok = false; }
  if !opt_is(puppet_state_get(&st, "exec[reload]"), "present") { ok = false; }
  return assert(ok, "end to end: web fixture applies and idempotent");
}

// t26 -- parser edge cases: comments, CRLF, bare titles, empty class.
fn t26() -> TestResult {
  var s = "# lead\n";
  s = s + "class a {}\r\n";
  s = s + "class b {\r\n";
  s = s + "  package { nginx: ensure => present, }\r\n";
  s = s + "  Package[nginx] -> Package[other]\r\n";
  s = s + "}\n";
  let m = puppet_manifest_parse(s);
  var ok = false;
  match m {
    Ok(mm) => {
      ok = puppet_manifest_class_count(&mm) == 2;
      if puppet_manifest_resource_count(&mm) != 1 { ok = false; }
      if !streq(puppet_manifest_resource_title(&mm, 0), "nginx") { ok = false; }
      if puppet_manifest_resource_class(&mm, 0) != 1 { ok = false; }
      if puppet_manifest_rel_count(&mm) != 1 { ok = false; }
      if !streq(puppet_manifest_rel_kind(&mm, 0), "chain") { ok = false; }
      if !streq(puppet_manifest_rel_title(&mm, 0), "other") { ok = false; }
      if !opt_is(puppet_manifest_attr(&mm, 0, "ensure"), "present") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parse: comments, CRLF, bare titles, chains");
}

fn main() -> Int {
  io.println("=== xiom.puppet conformance tests ===");
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
    io.println("xiom.puppet: all tests passed");
  } else {
    io.println("xiom.puppet: tests failed");
  }
  return failed;
}
