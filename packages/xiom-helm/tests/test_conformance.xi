// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.helm conformance tests (23 checks)
// Port task: prove the pure-XIOM xiom.helm modules against their documented
// behavior: chart parse/validate/render, values deep-merge precedence, the
// release state machine, the repository index subset and the bounded template
// renderer. Deterministic, inline fixtures only: no files, no network.
//
// All Str equality goes through str_compare (BUG 17: `==` on Str values read
// from Vec[Str] elements lowers to a pointer comparison). Typed locals are
// bound before every Vec element read, and `&pair.0`-style tuple-field
// borrows are avoided by binding to a local first (trap 4).

module helm_tests
use xiom.io; use xiom.test;
use xiom.string.compare;
use xiom.helm;
use xiom.helm.base;
use xiom.helm.release;
use xiom.helm.repo;
use xiom.helm.tmpl;

// --------------------------------------------------
//  Shared assertion helpers
// --------------------------------------------------

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

fn vec_is(v: &Vec[Str], i: Int, want: Str) -> Bool {
  if i < 0 || i >= v.len() {
    return false;
  }
  let got: Str = v[i];
  return streq(got, want);
}

fn result_str_is(r: Result[Str, Str], want: Str) -> Bool {
  match r {
    Ok(v) => { return streq(v, want); },
    Err(_) => { return false; },
  }
  return false;
}

fn result_str_err_is(r: Result[Str, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn values_err_is(r: Result[Values, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn vset(v: &Values, path: Str, val: Str) -> Values {
  let r = values_set(v, path, val);
  match r {
    Ok(x) => { return x; },
    Err(_) => { return values_new(); },
  }
  return values_new();
}

fn vget_is(v: &Values, path: Str, want: Str) -> Bool {
  return opt_is(values_get(v, path), want);
}

fn vmissing(v: &Values, path: Str) -> Bool {
  let o = values_get(v, path);
  match o {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

fn chart_get_is(c: &Chart, key: Str, want: Str) -> Bool {
  if streq(key, "apiVersion") { return streq(c.api_version, want); }
  if streq(key, "name") { return streq(c.name, want); }
  if streq(key, "version") { return streq(c.version, want); }
  if streq(key, "appVersion") { return streq(c.app_version, want); }
  if streq(key, "description") { return streq(c.description, want); }
  return false;
}

fn chart_parse_ok_is(text: Str, key: Str, want: Str) -> Bool {
  let r = chart_parse(text);
  match r {
    Ok(c) => { return chart_get_is(&c, key, want); },
    Err(_) => { return false; },
  }
  return false;
}

fn chart_parse_err_is(text: Str, want: Str) -> Bool {
  let r = chart_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn chart_err_is(r: Result[Chart, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn repo_field(text: Str, i: Int, col: Str) -> Str {
  let r = repo_index_parse(text);
  match r {
    Ok(idx) => {
      if streq(col, "name") { return repo_index_name(&idx, i); }
      if streq(col, "version") { return repo_index_version(&idx, i); }
      if streq(col, "appVersion") { return repo_index_app_version(&idx, i); }
      if streq(col, "description") { return repo_index_description(&idx, i); }
      if streq(col, "urls") { return repo_index_urls(&idx, i); }
      return "";
    },
    Err(_) => { return "<parse-error>"; },
  }
  return "";
}

fn repo_parse_err_is(text: Str, want: Str) -> Bool {
  let r = repo_index_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn rel_result_is(r: Result[Release, Str], want_status: Str, want_rev: Int) -> Bool {
  match r {
    Ok(x) => { return streq(release_status(&x), want_status) && release_revision(&x) == want_rev; },
    Err(_) => { return false; },
  }
  return false;
}

fn rel_err_is(r: Result[Release, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn rel_installed(name: Str) -> Release {
  let r0 = release_create(name);
  match r0 {
    Ok(a) => {
      let r1 = release_begin_install(&a, "install");
      match r1 {
        Ok(b) => {
          let r2 = release_complete(&b);
          match r2 {
            Ok(c) => { return c; },
            Err(_) => { return b; },
          }
        },
        Err(_) => { return a; },
      }
    },
    Err(_) => {
      return Release{ name: name; revisions: Vec[Int].new(); statuses: Vec[Str].new(); notes: Vec[Str].new(); };
    },
  }
}

fn rel_upgraded(r: &Release) -> Release {
  let u = release_upgrade(r, "up");
  match u {
    Ok(x) => {
      let c = release_complete(&x);
      match c {
        Ok(y) => { return y; },
        Err(_) => { return x; },
      }
    },
    Err(_) => { return rel_installed("fallback"); },
  }
}

fn ctx_basic(v: &Values, release_name: Str) -> RenderContext {
  let pair = values_entries(v);
  let ks = pair.0;
  let vs = pair.1;
  return tmpl_context_basic(&ks, &vs, release_name);
}

fn tmpl_is(text: Str, ctx: &RenderContext, want: Str) -> Bool {
  return result_str_is(tmpl_render(text, ctx), want);
}

fn tmpl_err_is(text: Str, ctx: &RenderContext, want: Str) -> Bool {
  return result_str_err_is(tmpl_render(text, ctx), want);
}

// --------------------------------------------------
//  Chart checks
// --------------------------------------------------

fn t01() -> TestResult {
  var ok = true;
  let r = chart_new("web", "1.2.3");
  match r {
    Ok(c) => {
      if !streq(c.api_version, "v2") { ok = false; }
      if !streq(c.name, "web") { ok = false; }
      if !streq(c.version, "1.2.3") { ok = false; }
      if !streq(c.app_version, "") { ok = false; }
      if !streq(c.description, "") { ok = false; }
      if !chart_valid(&c) { ok = false; }
      if !streq(chart_render(&c), "apiVersion: v2\nname: web\nversion: 1.2.3\nappVersion: \ndescription: ") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !chart_err_is(chart_new("Web", "1.0.0"), "chart: invalid chart name: Web") { ok = false; }
  if !chart_err_is(chart_new("web", "1.2"), "chart: invalid chart version: 1.2") { ok = false; }
  return assert(ok, "chart_new: defaults, validity, render, name/version errors");
}

fn t02() -> TestResult {
  let text = "# top comment\napiVersion: v2\nname: web-app\nversion: \"1.0.0\"\nappVersion: \"2.3.4\"\ndescription: A web app\nicon: ignored.png\n";
  var ok = true;
  if !chart_parse_ok_is(text, "apiVersion", "v2") { ok = false; }
  if !chart_parse_ok_is(text, "name", "web-app") { ok = false; }
  if !chart_parse_ok_is(text, "version", "1.0.0") { ok = false; }
  if !chart_parse_ok_is(text, "appVersion", "2.3.4") { ok = false; }
  if !chart_parse_ok_is(text, "description", "A web app") { ok = false; }
  let r = chart_parse(text);
  match r {
    Ok(c) => {
      if !chart_valid(&c) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "chart_parse: fields, quotes, comments, unknown keys ignored");
}

fn t03() -> TestResult {
  var ok = true;
  if !chart_parse_err_is("apiVersion v2", "chart: expected ':' in line: apiVersion v2") { ok = false; }
  if !chart_parse_err_is(": v2", "chart: missing key in line: : v2") { ok = false; }
  if !chart_parse_ok_is("name: x", "name", "x") { ok = false; }
  if chart_parse_err_is("name: x", "chart: expected ':' in line: name: x") { ok = false; }
  return assert(ok, "chart_parse errors: missing ':' and missing key");
}

fn t04() -> TestResult {
  var ok = true;
  let empty = Chart{ api_version: ""; name: ""; version: ""; app_version: ""; description: ""; };
  let errs = chart_validate(&empty);
  ok = errs.len() == 3;
  if !vec_is(&errs, 0, "chart: missing apiVersion") { ok = false; }
  if !vec_is(&errs, 1, "chart: missing name") { ok = false; }
  if !vec_is(&errs, 2, "chart: missing version") { ok = false; }
  let bad = Chart{ api_version: "v3"; name: "Bad_1"; version: "1.2"; app_version: ""; description: ""; };
  let errs2 = chart_validate(&bad);
  ok = ok && errs2.len() == 3;
  if !vec_is(&errs2, 0, "chart: unsupported apiVersion: v3") { ok = false; }
  if !vec_is(&errs2, 1, "chart: invalid chart name: Bad_1") { ok = false; }
  if !vec_is(&errs2, 2, "chart: invalid chart version: 1.2") { ok = false; }
  if chart_valid(&bad) { ok = false; }
  return assert(ok, "chart_validate: all errors in field order; invalid chart rejected");
}

fn t05() -> TestResult {
  let text = "apiVersion: v1\nname: db\nversion: 2.0.0\nappVersion: \"5\"\ndescription: data store";
  var ok = true;
  let r = chart_parse(text);
  match r {
    Ok(c) => {
      let out = chart_render(&c);
      if !streq(out, "apiVersion: v1\nname: db\nversion: 2.0.0\nappVersion: 5\ndescription: data store") { ok = false; }
      let r2 = chart_parse(out);
      match r2 {
        Ok(c2) => {
          if !streq(c.api_version, c2.api_version) { ok = false; }
          if !streq(c.name, c2.name) { ok = false; }
          if !streq(c.version, c2.version) { ok = false; }
          if !streq(c.app_version, c2.app_version) { ok = false; }
          if !streq(c.description, c2.description) { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "chart: parse -> render -> parse round-trip");
}

// --------------------------------------------------
//  Values checks
// --------------------------------------------------

fn t06() -> TestResult {
  var v = values_new();
  v = vset(&v, "image.tag", "1.2");
  v = vset(&v, "replicas", "3");
  var ok = values_len(&v) == 2;
  if !vget_is(&v, "image.tag", "1.2") { ok = false; }
  if !values_has(&v, "replicas") { ok = false; }
  if !vmissing(&v, "image.pull") { ok = false; }
  if !vmissing(&v, "zz") { ok = false; }
  let pair = values_entries(&v);
  let ks = pair.0;
  let vs = pair.1;
  if !vec_is(&ks, 0, "image.tag") { ok = false; }
  if !vec_is(&vs, 1, "3") { ok = false; }
  if !values_err_is(values_set(&v, "image..tag", "x"), "values: malformed path: image..tag") { ok = false; }
  if !values_err_is(values_set(&v, "", "x"), "values: malformed path: ") { ok = false; }
  return assert(ok, "values_set/get: lookup, length, entries, malformed path Err");
}

fn t07() -> TestResult {
  var v = values_new();
  v = vset(&v, "a.b", "1");
  v = vset(&v, "a.c", "2");
  var ok = values_len(&v) == 2;
  v = vset(&v, "a.b.c", "3");
  ok = ok && values_len(&v) == 2;
  if !vmissing(&v, "a.b") { ok = false; }
  if !vget_is(&v, "a.b.c", "3") { ok = false; }
  if !vget_is(&v, "a.c", "2") { ok = false; }
  v = vset(&v, "a", "top");
  ok = ok && values_len(&v) == 1;
  if !vget_is(&v, "a", "top") { ok = false; }
  if !vmissing(&v, "a.b.c") { ok = false; }
  var pos = values_new();
  pos = vset(&pos, "a.b", "1");
  pos = vset(&pos, "q", "2");
  pos = vset(&pos, "a.x", "3");
  let pair = values_entries(&pos);
  let ks = pair.0;
  ok = ok && ks.len() == 3;
  if !vec_is(&ks, 0, "a.b") { ok = false; }
  if !vec_is(&ks, 1, "q") { ok = false; }
  if !vec_is(&ks, 2, "a.x") { ok = false; }
  var pos2 = values_new();
  pos2 = vset(&pos2, "a.b", "1");
  pos2 = vset(&pos2, "q", "2");
  pos2 = vset(&pos2, "a", "9");
  let pair2 = values_entries(&pos2);
  let ks2 = pair2.0;
  ok = ok && ks2.len() == 2;
  if !vec_is(&ks2, 0, "a") { ok = false; }
  if !vec_is(&ks2, 1, "q") { ok = false; }
  return assert(ok, "values deep-set: subtree replace, ancestor replace, first position kept");
}

fn t08() -> TestResult {
  var base_map = values_new();
  base_map = vset(&base_map, "a.b", "2");
  base_map = vset(&base_map, "c", "3");
  var over = values_new();
  over = vset(&over, "a.b", "9");
  over = vset(&over, "c.d", "5");
  over = vset(&over, "d", "4");
  var ok = true;
  let mr = values_merge(&base_map, &over);
  match mr {
    Ok(m) => {
      if values_len(&m) != 3 { ok = false; }
      if !vget_is(&m, "a.b", "9") { ok = false; }
      if !vget_is(&m, "c.d", "5") { ok = false; }
      if !vmissing(&m, "c") { ok = false; }
      if !vget_is(&m, "d", "4") { ok = false; }
      let pair = values_entries(&m);
      let ks = pair.0;
      if !vec_is(&ks, 0, "a.b") { ok = false; }
      if !vec_is(&ks, 1, "c.d") { ok = false; }
      if !vec_is(&ks, 2, "d") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !vget_is(&base_map, "a.b", "2") { ok = false; }
  if !vget_is(&over, "a.b", "9") { ok = false; }
  var defaults = values_new();
  defaults = vset(&defaults, "port", "80");
  defaults = vset(&defaults, "host", "localhost");
  var file = values_new();
  file = vset(&file, "port", "8080");
  var runtime = values_new();
  runtime = vset(&runtime, "port", "9000");
  runtime = vset(&runtime, "name", "svc");
  let rr = values_resolve(&defaults, &file, &runtime);
  match rr {
    Ok(m2) => {
      if !vget_is(&m2, "port", "9000") { ok = false; }
      if !vget_is(&m2, "host", "localhost") { ok = false; }
      if !vget_is(&m2, "name", "svc") { ok = false; }
      if values_len(&m2) != 3 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "values_merge/resolve: overlay wins, ancestor scalar replaced, inputs untouched");
}

fn t09() -> TestResult {
  var bad = values_new();
  bad.keys.push("bad..x");
  bad.vals.push("1");
  var ok = values_err_is(values_merge(&values_new(), &bad), "values: malformed path: bad..x");
  var v = values_new();
  v = vset(&v, "b", "2");
  v = vset(&v, "a", "1");
  if !streq(values_render(&v), "b: 2\na: 1") { ok = false; }
  let empty = values_new();
  if !streq(values_render(&empty), "") { ok = false; }
  if !vmissing(&empty, "x") { ok = false; }
  let pair = values_entries(&v);
  let ks = pair.0;
  ks.push("mutated");
  if values_len(&v) != 2 { ok = false; }
  if !vmissing(&v, "mutated") { ok = false; }
  return assert(ok, "values: merge error, canonical render, empty map, fresh-copy entries");
}

// --------------------------------------------------
//  Release checks
// --------------------------------------------------

fn t10() -> TestResult {
  var ok = true;
  let r0 = release_create("web");
  match r0 {
    Ok(a) => {
      if !streq(release_status(&a), "unknown") { ok = false; }
      if release_revision(&a) != 0 { ok = false; }
      if release_history_len(&a) != 0 { ok = false; }
      let r1 = release_begin_install(&a, "install");
      if !rel_result_is(r1, "pending-install", 1) { ok = false; }
      match r1 {
        Ok(b) => {
          let r2 = release_complete(&b);
          if !rel_result_is(r2, "deployed", 1) { ok = false; }
          match r2 {
            Ok(c) => {
              if !release_is_deployed(&c) { ok = false; }
              if release_count_status(&c, "deployed") != 1 { ok = false; }
              if !rel_err_is(release_complete(&c), "release: complete requires a pending status, got: deployed") { ok = false; }
              if !rel_err_is(release_begin_install(&c, "again"), "release: install requires an empty revision history") { ok = false; }
            },
            Err(_) => { ok = false; },
          }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  if !rel_err_is(release_create("Bad_Name"), "release: invalid release name: Bad_Name") { ok = false; }
  return assert(ok, "release: create, pending-install -> deployed, invalid repeat transitions");
}

fn t11() -> TestResult {
  var ok = true;
  let base_rel = rel_installed("web");
  if !release_is_deployed(&base_rel) { ok = false; }
  let u = release_upgrade(&base_rel, "up-2");
  if !rel_result_is(u, "pending-upgrade", 2) { ok = false; }
  match u {
    Ok(p) => {
      if !streq(release_note_at(&p, 1), "up-2") { ok = false; }
      let c = release_complete(&p);
      match c {
        Ok(d) => {
          if !streq(release_status_at(&d, 0), "superseded") { ok = false; }
          if !streq(release_status_at(&d, 1), "deployed") { ok = false; }
          if release_count_status(&d, "superseded") != 1 { ok = false; }
          let rb = release_rollback(&d, 1, "back");
          if !rel_result_is(rb, "pending-rollback", 3) { ok = false; }
          match rb {
            Ok(q) => {
              let c2 = release_complete(&q);
              match c2 {
                Ok(e) => {
                  if !streq(release_status_at(&e, 0), "superseded") { ok = false; }
                  if !streq(release_status_at(&e, 1), "superseded") { ok = false; }
                  if !streq(release_status_at(&e, 2), "deployed") { ok = false; }
                  if release_count_status(&e, "deployed") != 1 { ok = false; }
                  if release_history_len(&e) != 3 { ok = false; }
                },
                Err(_) => { ok = false; },
              }
            },
            Err(_) => { ok = false; },
          }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "release: upgrade -> supersede, rollback -> new revision, history kept");
}

fn t12() -> TestResult {
  var ok = true;
  let base_rel = rel_installed("web");
  if !rel_err_is(release_rollback(&base_rel, 5, "x"), "release: unknown revision: 5") { ok = false; }
  if !rel_err_is(release_rollback(&base_rel, 1, "x"), "release: cannot roll back to the current revision: 1") { ok = false; }
  let u = release_upgrade(&base_rel, "up");
  var chain = base_rel;
  match u {
    Ok(p) => {
      chain = p;
      let f = release_fail(&chain, "boom");
      if !rel_result_is(f, "failed", 2) { ok = false; }
      match f {
        Ok(fx) => {
          if !streq(release_note_at(&fx, 1), "boom") { ok = false; }
          if !rel_err_is(release_complete(&fx), "release: complete requires a pending status, got: failed") { ok = false; }
          let u2 = release_upgrade(&fx, "recover");
          if !rel_result_is(u2, "pending-upgrade", 3) { ok = false; }
          match u2 {
            Ok(r3) => {
              let c3 = release_complete(&r3);
              match c3 {
                Ok(d) => {
                  if !streq(release_status_at(&d, 1), "failed") { ok = false; }
                  if !rel_err_is(release_rollback(&d, 2, "back"), "release: cannot roll back to revision 2 with status: failed") { ok = false; }
                },
                Err(_) => { ok = false; },
              }
            },
            Err(_) => { ok = false; },
          }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  if !rel_err_is(release_fail(&base_rel, "x"), "release: fail requires a pending status, got: deployed") { ok = false; }
  return assert(ok, "release: rollback errors, failed release, upgrade from failed");
}

fn t13() -> TestResult {
  var ok = true;
  let base_rel = rel_installed("web");
  let u = release_uninstall(&base_rel);
  match u {
    Ok(x) => {
      if !streq(release_status(&x), "uninstalled") { ok = false; }
      if release_history_len(&x) != 1 { ok = false; }
      if release_revision(&x) != 1 { ok = false; }
      if !rel_err_is(release_uninstall(&x), "release: uninstall requires status deployed, got: uninstalled") { ok = false; }
      if !rel_err_is(release_upgrade(&x, "u"), "release: cannot upgrade from status: uninstalled") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let empty = release_create("web");
  match empty {
    Ok(e) => {
      if !rel_err_is(release_upgrade(&e, "u"), "release: upgrade requires an installed release") { ok = false; }
      if !rel_err_is(release_rollback(&e, 1, "r"), "release: rollback requires an installed release") { ok = false; }
      if !rel_err_is(release_complete(&e), "release: complete requires a pending revision") { ok = false; }
      if !rel_err_is(release_fail(&e, "f"), "release: fail requires a pending revision") { ok = false; }
      if !rel_err_is(release_uninstall(&e), "release: uninstall requires an installed release") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  var known = release_status_known("deployed") && release_status_known("pending-rollback");
  if release_status_known("weird") { known = false; }
  if !known { ok = false; }
  if !streq(release_status_at(&base_rel, 9), "") { ok = false; }
  if !streq(release_note_at(&base_rel, -1), "") { ok = false; }
  return assert(ok, "release: uninstall, empty-history errors, range-safe accessors, status table");
}

fn t14() -> TestResult {
  var rel = rel_installed("web");
  var i = 0;
  while i < 200 && release_history_len(&rel) < 100 {
    let u = release_upgrade(&rel, "n");
    match u {
      Ok(x) => {
        rel = x;
        let c = release_complete(&rel);
        match c {
          Ok(y) => { rel = y; },
          Err(_) => {},
        }
      },
      Err(_) => {},
    }
    i = i + 1;
  }
  var ok = release_history_len(&rel) == 100;
  if !rel_err_is(release_upgrade(&rel, "over"), "release: revision limit reached") { ok = false; }
  return assert(ok, "release: revision cap at 100");
}

// --------------------------------------------------
//  Repository index checks
// --------------------------------------------------

fn t15() -> TestResult {
  var ok = true;
  let idx0 = repo_index_new();
  if !streq(idx0.api_version, "v1") { ok = false; }
  if repo_index_len(&idx0) != 0 { ok = false; }
  if !streq(repo_index_render(&idx0), "apiVersion: v1\nentries:") { ok = false; }
  let a = repo_index_add(&idx0, "nginx", "1.2.3", "1.19", "A web server", "https://a/x.tgz,  https://b/x.tgz");
  match a {
    Ok(idx1) => {
      if repo_index_len(&idx1) != 1 { ok = false; }
      if !streq(repo_index_name(&idx1, 0), "nginx") { ok = false; }
      if !streq(repo_index_version(&idx1, 0), "1.2.3") { ok = false; }
      if !streq(repo_index_app_version(&idx1, 0), "1.19") { ok = false; }
      if !streq(repo_index_description(&idx1, 0), "A web server") { ok = false; }
      if !streq(repo_index_urls(&idx1, 0), "https://a/x.tgz, https://b/x.tgz") { ok = false; }
      let b = repo_index_add(&idx1, "redis", "6.0.0", "", "", "");
      match b {
        Ok(idx2) => {
          if repo_index_len(&idx2) != 2 { ok = false; }
          if repo_index_find(&idx2, "nginx", "1.2.3") != 0 { ok = false; }
          if repo_index_find(&idx2, "nginx", "9.9.9") != -1 { ok = false; }
          if repo_index_find(&idx2, "redis", "6.0.0") != 1 { ok = false; }
          if repo_index_count_name(&idx2, "nginx") != 1 { ok = false; }
          if repo_index_count_name(&idx2, "missing") != 0 { ok = false; }
          if !streq(repo_index_name(&idx2, 9), "") { ok = false; }
          if !streq(repo_index_urls(&idx2, 0), "https://a/x.tgz, https://b/x.tgz") { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  let badname = repo_index_add(&idx0, "NGINX", "1.0.0", "", "", "");
  match badname {
    Ok(_) => { ok = false; },
    Err(e) => {
      if !streq(e, "repo: invalid chart name: NGINX") { ok = false; }
    },
  }
  let badver = repo_index_add(&idx0, "nginx", "1.2", "", "", "");
  match badver {
    Ok(_) => { ok = false; },
    Err(e) => {
      if !streq(e, "repo: invalid chart version: 1.2") { ok = false; }
    },
  }
  return assert(ok, "repo_index_add: entry model, accessors, find/count, validation errors");
}

fn t16() -> TestResult {
  let text = "# index\napiVersion: v1\nentries:\n  - name: nginx\n    version: \"1.2.3\"\n    appVersion: \"1.19.0\"\n    description: A web server\n    urls: https://a/x.tgz, https://b/x.tgz\n  - name: redis\n    version: 6.0.0\n    digest: sha256:abc\n    urls: https://c/r.tgz\n";
  var ok = true;
  if !streq(repo_field(text, 0, "name"), "nginx") { ok = false; }
  if !streq(repo_field(text, 0, "version"), "1.2.3") { ok = false; }
  if !streq(repo_field(text, 0, "appVersion"), "1.19.0") { ok = false; }
  if !streq(repo_field(text, 0, "description"), "A web server") { ok = false; }
  if !streq(repo_field(text, 0, "urls"), "https://a/x.tgz, https://b/x.tgz") { ok = false; }
  if !streq(repo_field(text, 1, "name"), "redis") { ok = false; }
  if !streq(repo_field(text, 1, "version"), "6.0.0") { ok = false; }
  if !streq(repo_field(text, 1, "appVersion"), "") { ok = false; }
  if !streq(repo_field(text, 1, "urls"), "https://c/r.tgz") { ok = false; }
  let r = repo_index_parse(text);
  match r {
    Ok(idx) => {
      if repo_index_len(&idx) != 2 { ok = false; }
      if !streq(idx.api_version, "v1") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let e = repo_index_parse("");
  match e {
    Ok(empty) => {
      if repo_index_len(&empty) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "repo_index_parse: two entries, quotes, comments, unknown keys, empty index");
}

fn t17() -> TestResult {
  var ok = true;
  if !repo_parse_err_is("- version: 1.0.0", "repo: entry must start with name: - version: 1.0.0") { ok = false; }
  if !repo_parse_err_is("- name: web\n  version:", "repo: entry missing version") { ok = false; }
  if !repo_parse_err_is("- name: web\n  version: 1.2", "repo: invalid chart version: 1.2") { ok = false; }
  if !repo_parse_err_is("- name: web\n  version: 1.0.0\n- name: Bad\n  version: 2.0.0", "repo: invalid chart name: Bad") { ok = false; }
  if !repo_parse_err_is("name: web", "repo: unexpected line: name: web") { ok = false; }
  if !repo_parse_err_is("entries: junk", "repo: malformed entries line: entries: junk") { ok = false; }
  if !repo_parse_err_is("apiVersion: v2", "repo: unsupported apiVersion: v2") { ok = false; }
  if !repo_parse_err_is("justkey", "repo: expected ':' in line: justkey") { ok = false; }
  return assert(ok, "repo_index_parse errors: entry shape, missing/invalid fields, bad top level");
}

fn t18() -> TestResult {
  var ok = true;
  let idx0 = repo_index_new();
  var idx = idx0;
  let a = repo_index_add(&idx, "web", "1.0.0", "2", "desc", "https://a/w.tgz");
  match a {
    Ok(x) => {
      idx = x;
      let b = repo_index_add(&idx, "db", "3.1.4", "", "", "");
      match b {
        Ok(y) => { idx = y; },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  let out = repo_index_render(&idx);
  let r = repo_index_parse(out);
  match r {
    Ok(idx2) => {
      if repo_index_len(&idx2) != 2 { ok = false; }
      if !streq(idx2.api_version, "v1") { ok = false; }
      if !streq(repo_index_name(&idx2, 0), "web") { ok = false; }
      if !streq(repo_index_app_version(&idx2, 0), "2") { ok = false; }
      if !streq(repo_index_description(&idx2, 0), "desc") { ok = false; }
      if !streq(repo_index_urls(&idx2, 0), "https://a/w.tgz") { ok = false; }
      if !streq(repo_index_name(&idx2, 1), "db") { ok = false; }
      if !streq(repo_index_urls(&idx2, 1), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "repo: render -> parse round-trip preserves all five columns");
}

// --------------------------------------------------
//  Template checks
// --------------------------------------------------

fn t19() -> TestResult {
  var v = values_new();
  v = vset(&v, "a.b", "x");
  v = vset(&v, "on", "yes");
  let pair = values_entries(&v);
  let ks = pair.0;
  let vs = pair.1;
  let ctx = RenderContext{
    vkeys: ks;
    vvals: vs;
    release_name: "web";
    release_namespace: "prod";
    release_revision: 3;
    chart_api_version: "v2";
    chart_name: "web-chart";
    chart_version: "1.2.3";
    chart_app_version: "9";
    chart_description: "d";
  };
  var ok = tmpl_is("hello world", &ctx, "hello world");
  if !tmpl_is("v={{ .Values.a.b }}", &ctx, "v=x") { ok = false; }
  if !tmpl_is("{{.Values.on}}", &ctx, "yes") { ok = false; }
  if !tmpl_is("[{{ .Values.missing }}]", &ctx, "[]") { ok = false; }
  if !tmpl_is("{{ .Release.Name }}", &ctx, "web") { ok = false; }
  if !tmpl_is("{{ .Release.Namespace }}", &ctx, "prod") { ok = false; }
  if !tmpl_is("{{ .Release.Revision }}", &ctx, "3") { ok = false; }
  if !tmpl_is("{{ .Release.Service }}", &ctx, "Helm") { ok = false; }
  if !tmpl_is("{{ .Release.IsInstall }}", &ctx, "false") { ok = false; }
  if !tmpl_is("{{ .Release.IsUpgrade }}", &ctx, "true") { ok = false; }
  if !tmpl_is("{{ .Chart.Name }}/{{ .Chart.Version }}", &ctx, "web-chart/1.2.3") { ok = false; }
  if !tmpl_is("{{ .Chart.AppVersion }}", &ctx, "9") { ok = false; }
  let base_ctx = ctx_basic(&v, "web");
  if !tmpl_is("{{ .Release.Revision }}|{{ .Release.IsInstall }}", &base_ctx, "1|true") { ok = false; }
  return assert(ok, "tmpl: plain text and Values/Release/Chart substitution, defaults");
}

fn t20() -> TestResult {
  var v = values_new();
  v = vset(&v, "on", "true");
  v = vset(&v, "off", "false");
  v = vset(&v, "zero", "0");
  v = vset(&v, "empty", "");
  let ctx = ctx_basic(&v, "web");
  var ok = true;
  if !tmpl_is("{{ if .Values.on }}yes{{ else }}no{{ end }}", &ctx, "yes") { ok = false; }
  if !tmpl_is("{{ if .Values.off }}yes{{ else }}no{{ end }}", &ctx, "no") { ok = false; }
  if !tmpl_is("{{ if .Values.zero }}yes{{ else }}no{{ end }}", &ctx, "no") { ok = false; }
  if !tmpl_is("{{ if .Values.empty }}yes{{ else }}no{{ end }}", &ctx, "no") { ok = false; }
  if !tmpl_is("{{ if .Values.missing }}yes{{ end }}ok", &ctx, "ok") { ok = false; }
  if !tmpl_is("{{ if .Values.on }}yes{{ end }}", &ctx, "yes") { ok = false; }
  if !tmpl_is("pre {{ if .Values.on }}mid{{ end }} post", &ctx, "pre mid post") { ok = false; }
  if !tmpl_is("{{ if .Values.on }}A{{ if .Values.on }}B{{ end }}C{{ end }}", &ctx, "ABC") { ok = false; }
  if !tmpl_is("{{ if .Values.off }}A{{ else }}B{{ if .Values.on }}C{{ end }}{{ end }}", &ctx, "BC") { ok = false; }
  if !tmpl_is("{{ if .Values.off }}{{ .Bogus.Root }}{{ end }}ok", &ctx, "ok") { ok = false; }
  return assert(ok, "tmpl: if/else/end truthiness, nesting, suppressed branches");
}

fn t21() -> TestResult {
  let ctx = tmpl_context_new();
  var ok = true;
  if !tmpl_err_is("a {{ .Values.x", &ctx, "tmpl: unterminated action at offset 2") { ok = false; }
  if !tmpl_err_is("{{ }}", &ctx, "tmpl: empty action at offset 0") { ok = false; }
  if !tmpl_err_is("{{ foo }}", &ctx, "tmpl: unexpected action: foo") { ok = false; }
  if !tmpl_err_is("{{ else }}", &ctx, "tmpl: unexpected else") { ok = false; }
  if !tmpl_err_is("{{ end }}", &ctx, "tmpl: unexpected end") { ok = false; }
  if !tmpl_err_is("{{ if .Values.x }}x", &ctx, "tmpl: unclosed if") { ok = false; }
  if !tmpl_err_is("{{ if }}", &ctx, "tmpl: if requires a path") { ok = false; }
  if !tmpl_err_is("{{ if x }}", &ctx, "tmpl: if requires a path starting with '.': if x") { ok = false; }
  if !tmpl_err_is("{{ .Values.a..b }}", &ctx, "tmpl: malformed path: .Values.a..b") { ok = false; }
  if !tmpl_err_is("{{ .Bogus.Root }}", &ctx, "tmpl: unknown context path: Bogus.Root") { ok = false; }
  if !tmpl_err_is("{{ .Release.Unknown }}", &ctx, "tmpl: unknown context path: Release.Unknown") { ok = false; }
  if !tmpl_err_is("{{ .Chart.Nope }}", &ctx, "tmpl: unknown context path: Chart.Nope") { ok = false; }
  return assert(ok, "tmpl: syntax and context error catalog");
}

fn t22() -> TestResult {
  var deep = "";
  var i = 0;
  while i < 40 {
    deep = deep + "{{ if .Values.x }}";
    i = i + 1;
  }
  while i > 0 {
    deep = deep + "{{ end }}";
    i = i - 1;
  }
  var v = values_new();
  v = vset(&v, "x", "1");
  let ctx = ctx_basic(&v, "web");
  var ok = tmpl_err_is(deep, &ctx, "tmpl: if nesting limit exceeded");
  if !tmpl_is("{{ if .Values.x }}ok{{ end }}", &ctx, "ok") { ok = false; }
  return assert(ok, "tmpl: nesting cap enforced, depth-1 if still fine");
}

fn t23() -> TestResult {
  var v = values_new();
  v = vset(&v, "replicas", "3");
  v = vset(&v, "image", "nginx");
  let pair = values_entries(&v);
  let ks = pair.0;
  let vs = pair.1;
  let r = tmpl_render_values("{{ .Values.image }}:{{ .Values.replicas }}@{{ .Release.Name }}", &ks, &vs, "web");
  var ok = result_str_is(r, "nginx:3@web");
  let ctx = ctx_basic(&v, "web");
  if !tmpl_is("{{ if .Values.replicas }}scaled{{ end }}", &ctx, "scaled") { ok = false; }
  if !tmpl_is("{{ .Release.Name }}", &ctx, "web") { ok = false; }
  return assert(ok, "tmpl_render_values: flat columns and release name");
}

// --------------------------------------------------
//  Runner
// --------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.helm conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.helm: all tests passed");
  } else {
    io.println("xiom.helm: tests failed");
  }
  return failed;
}
