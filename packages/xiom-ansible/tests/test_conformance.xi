// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.ansible conformance tests (26 checks)
// Port task: prove the pure-XIOM xiom.ansible model against its documented
// API: inventory precedence, the module registry, playbook construction and
// validation, tag/limit filtering, the linear and free executor strategies,
// handler notification order/dedup, result accounting and typed facts.
//
// All Str equality goes through str_compare: `==` on Str values read from
// Vec[Str] elements lowers to a pointer comparison, so every text check below
// is routed through streq. Vec element reads use typed `let` bindings.

module ansible_tests
use xiom.io; use xiom.test; use xiom.ansible;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn okcode(r: Result[Int, Str]) -> Int {
  match r {
    Ok(v) => { let x: Int = v; return x; },
    Err(_) => { return -100; },
  }
  return -100;
}

fn okstr(r: Result[Str, Str]) -> Str {
  match r {
    Ok(v) => { let x: Str = v; return x; },
    Err(_) => { return ""; },
  }
  return "";
}

fn okbool(r: Result[Bool, Str]) -> Bool {
  match r {
    Ok(v) => { let x: Bool = v; return x; },
    Err(_) => { return false; },
  }
  return false;
}

fn errm_of(r: Result[Str, Str]) -> Str {
  match r {
    Ok(_) => { return ""; },
    Err(m) => { let s: Str = m; return s; },
  }
  return "";
}

fn errm_rep(r: Result[RunReport, Str]) -> Str {
  match r {
    Ok(_) => { return ""; },
    Err(m) => { let s: Str = m; return s; },
  }
  return "";
}

// Err-message check for Result[Int, Str].
fn errint_is(r: Result[Int, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(m) => { let s: Str = m; return streq(s, want); },
  }
  return false;
}

// Err-message check for Result[Str, Str].
fn errstr_is(r: Result[Str, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(m) => { let s: Str = m; return streq(s, want); },
  }
  return false;
}

// Err-message check for Result[Bool, Str].
fn errbool_is(r: Result[Bool, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(m) => { let s: Str = m; return streq(s, want); },
  }
  return false;
}

fn okrep(r: Result[RunReport, Str]) -> RunReport {
  match r {
    Ok(v) => { return v; },
    Err(_) => { return empty_report(); },
  }
  return empty_report();
}

fn empty_report() -> RunReport {
  return RunReport{
    play_names: Vec[Str].new();
    task_names: Vec[Str].new();
    hosts: Vec[Str].new();
    modules: Vec[Str].new();
    results: Vec[Int].new();
    trace: Vec[Str].new();
    handler_play: Vec[Str].new();
    handler_names: Vec[Str].new();
    handler_hosts: Vec[Str].new();
    handler_results: Vec[Int].new();
    notified: Vec[Str].new();
    changed: 0;
    ok: 0;
    failed: 0;
    skipped: 0;
    filtered: 0;
  };
}

fn has_str(v: &Vec[Str], s: Str) -> Bool {
  var i = 0;
  while i < v.len() {
    let cur: Str = v[i];
    if streq(cur, s) { return true; }
    i = i + 1;
  }
  return false;
}

// Truthiness of one Result[Bool, Str] plus its message when Err.
fn bool_true(r: Result[Bool, Str]) -> Bool {
  match r {
    Ok(v) => { let b: Bool = v; return b; },
    Err(_) => { return false; },
  }
  return false;
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

// hosts: web1 web2 db1; groups: prod web db prod2; hierarchy prod->web,db.
// gvars: prod.region=eu, web.http_port=80, db.region=db-region,
// prod2.region=other; hosts: web1->web, web2->web, db1->db, web2->prod2;
// hvar: web1.region=web1-region.
fn inv_fixture() -> Inventory {
  var inv = inventory_new();
  okcode(inventory_add_host(&mut inv, "web1"));
  okcode(inventory_add_host(&mut inv, "web2"));
  okcode(inventory_add_host(&mut inv, "db1"));
  okcode(inventory_add_group(&mut inv, "prod"));
  okcode(inventory_add_group(&mut inv, "web"));
  okcode(inventory_add_group(&mut inv, "db"));
  okcode(inventory_add_group(&mut inv, "prod2"));
  okcode(inventory_add_host_to_group(&mut inv, "web1", "web"));
  okcode(inventory_add_host_to_group(&mut inv, "web2", "web"));
  okcode(inventory_add_host_to_group(&mut inv, "db1", "db"));
  okcode(inventory_add_host_to_group(&mut inv, "web2", "prod2"));
  okcode(inventory_add_group_child(&mut inv, "prod", "web"));
  okcode(inventory_add_group_child(&mut inv, "prod", "db"));
  okcode(inventory_set_group_var(&mut inv, "prod", "region", "eu"));
  okcode(inventory_set_group_var(&mut inv, "web", "http_port", "80"));
  okcode(inventory_set_group_var(&mut inv, "db", "region", "db-region"));
  okcode(inventory_set_group_var(&mut inv, "prod2", "region", "other"));
  okcode(inventory_set_host_var(&mut inv, "web1", "region", "web1-region"));
  return inv;
}

// play web-play on group web: block config-block (tags "config") with one
// changed copy task notifying restart-web, plus ping and check tasks; handler
// restart-web changed.
fn web_playbook(strategy: Int) -> Playbook {
  var pb = playbook_new();
  let play = okcode(playbook_add_play(&mut pb, "web-play", "web", strategy));
  let blk = okcode(playbook_add_block(&mut pb, play, "config-block", "config"));
  okcode(playbook_add_task(&mut pb, play, blk, "copy-index", "copy", "changed=1", "", "restart-web"));
  okcode(playbook_add_task(&mut pb, play, -1, "ping-all", "ping", "", "", ""));
  okcode(playbook_add_task(&mut pb, play, -1, "check", "command", "echo ok", "check", ""));
  okcode(playbook_add_handler(&mut pb, play, "restart-web", "service", "changed=1"));
  return pb;
}

// play mix on group web, in order: first (changed), skipme (module skip),
// boom (fail), after (ping -- skipped because the host already failed).
fn mix_playbook() -> Playbook {
  var pb = playbook_new();
  let play = okcode(playbook_add_play(&mut pb, "mix-play", "web", ANSIBLE_STRATEGY_LINEAR));
  okcode(playbook_add_task(&mut pb, play, -1, "first", "copy", "changed=1", "", ""));
  okcode(playbook_add_task(&mut pb, play, -1, "skipme", "file", "skip=1", "", ""));
  okcode(playbook_add_task(&mut pb, play, -1, "boom", "fail", "", "", ""));
  okcode(playbook_add_task(&mut pb, play, -1, "after", "ping", "", "", ""));
  return pb;
}

// play notify-play: A/B/D changed notify hA/hB/hA; C ping notifies hA but is
// not changed; handlers hA and hB both changed.
fn notify_playbook() -> Playbook {
  var pb = playbook_new();
  let play = okcode(playbook_add_play(&mut pb, "notify-play", "web", ANSIBLE_STRATEGY_LINEAR));
  okcode(playbook_add_task(&mut pb, play, -1, "A", "copy", "changed=1", "", "hA"));
  okcode(playbook_add_task(&mut pb, play, -1, "B", "copy", "changed=1", "", "hB"));
  okcode(playbook_add_task(&mut pb, play, -1, "C", "ping", "", "", "hA"));
  okcode(playbook_add_task(&mut pb, play, -1, "D", "copy", "changed=1", "", "hA"));
  okcode(playbook_add_handler(&mut pb, play, "hA", "service", "changed=1"));
  okcode(playbook_add_handler(&mut pb, play, "hB", "service", "changed=1"));
  return pb;
}

// play filter-play on group web: block b (tags config) holds in-block; then
// config-task, check-task, never-task and always-task at play level.
fn filter_playbook() -> Playbook {
  var pb = playbook_new();
  let play = okcode(playbook_add_play(&mut pb, "filter-play", "web", ANSIBLE_STRATEGY_LINEAR));
  let blk = okcode(playbook_add_block(&mut pb, play, "b", "config"));
  okcode(playbook_add_task(&mut pb, play, blk, "in-block", "ping", "", "", ""));
  okcode(playbook_add_task(&mut pb, play, -1, "config-task", "ping", "", "config", ""));
  okcode(playbook_add_task(&mut pb, play, -1, "check-task", "ping", "", "check", ""));
  okcode(playbook_add_task(&mut pb, play, -1, "never-task", "ping", "", "never", ""));
  okcode(playbook_add_task(&mut pb, play, -1, "always-task", "ping", "", "always", ""));
  return pb;
}

// play all-play on "all": a changed copy, a ping, a changed command and a
// skipping file task.
fn strategy_playbook(strategy: Int) -> Playbook {
  var pb = playbook_new();
  let play = okcode(playbook_add_play(&mut pb, "all-play", "all", strategy));
  okcode(playbook_add_task(&mut pb, play, -1, "a", "copy", "changed=1", "", ""));
  okcode(playbook_add_task(&mut pb, play, -1, "b", "ping", "", "", ""));
  okcode(playbook_add_task(&mut pb, play, -1, "c", "command", "changed=1", "", ""));
  okcode(playbook_add_task(&mut pb, play, -1, "d", "file", "skip=1", "", ""));
  return pb;
}

// play setup-play on group web with one setup task.
fn setup_playbook() -> Playbook {
  var pb = playbook_new();
  let play = okcode(playbook_add_play(&mut pb, "setup-play", "web", ANSIBLE_STRATEGY_LINEAR));
  okcode(playbook_add_task(&mut pb, play, -1, "gather", "setup", "", "", ""));
  return pb;
}

fn t1() -> TestResult {
  var inv = inventory_new();
  var ok = inventory_host_count(&inv) == 0;
  let h1 = okcode(inventory_add_host(&mut inv, "web1"));
  let h2 = okcode(inventory_add_host(&mut inv, "db1"));
  if h1 != 0 { ok = false; }
  if h2 != 1 { ok = false; }
  if !inventory_has_host(&inv, "web1") { ok = false; }
  if inventory_has_host(&inv, "ghost") { ok = false; }
  let g1 = okcode(inventory_add_group(&mut inv, "web"));
  if g1 != 0 { ok = false; }
  if !inventory_has_group(&inv, "web") { ok = false; }
  if inventory_host_count(&inv) != 2 { ok = false; }
  if inventory_group_count(&inv) != 1 { ok = false; }
  if !errint_is(inventory_add_host(&mut inv, "web1"), "ansible: duplicate host: web1") { ok = false; }
  if !errint_is(inventory_add_group(&mut inv, "web"), "ansible: duplicate group: web") { ok = false; }
  if !errint_is(inventory_add_host(&mut inv, ""), "ansible: empty name") { ok = false; }
  if !errint_is(inventory_add_group(&mut inv, "bad name"), "ansible: empty name") { ok = false; }
  return assert(ok, "inventory builder adds hosts and groups with exact duplicate errors");
}

fn t2() -> TestResult {
  let inv = inv_fixture();
  var ok = inventory_member_count(&inv) == 4;
  if inventory_child_count(&inv) != 2 { ok = false; }
  var groups = inventory_host_groups(&inv, "web2");
  if groups.len() != 2 { ok = false; }
  if !streq(okstr(inventory_host_at(&inv, 0)), "web1") { ok = false; }
  if !streq(okstr(inventory_group_at(&inv, 1)), "web") { ok = false; }
  if !errstr_is(inventory_host_at(&inv, 9), "ansible: index out of range: host") { ok = false; }
  if !inventory_group_contains(&inv, "web", "web1") { ok = false; }
  if !inventory_group_contains(&inv, "prod", "db1") { ok = false; }
  if inventory_group_contains(&inv, "db", "web1") { ok = false; }
  if !inventory_group_contains(&inv, "all", "db1") { ok = false; }
  var bad = inventory_new();
  if !errint_is(inventory_add_host_to_group(&mut bad, "ghost", "web"), "ansible: unknown host: ghost") { ok = false; }
  okcode(inventory_add_host(&mut bad, "h1"));
  if !errint_is(inventory_add_host_to_group(&mut bad, "h1", "web"), "ansible: unknown group: web") { ok = false; }
  var inv2 = inv_fixture();
  if !errint_is(inventory_add_host_to_group(&mut inv2, "web1", "web"), "ansible: duplicate membership: web1 in web") { ok = false; }
  return assert(ok, "membership edges, closure and exact error messages");
}

fn t3() -> TestResult {
  var inv = inv_fixture();
  var ok = errint_is(inventory_add_group_child(&mut inv, "prod", "web"), "ansible: duplicate group child: prod>web");
  if !errint_is(inventory_add_group_child(&mut inv, "web", "prod"), "ansible: group cycle: web>prod") { ok = false; }
  if !errint_is(inventory_add_group_child(&mut inv, "web", "web"), "ansible: group cycle: web>web") { ok = false; }
  if !errint_is(inventory_add_group_child(&mut inv, "ghost", "web"), "ansible: unknown group: ghost") { ok = false; }
  var inv3 = inventory_new();
  okcode(inventory_add_host(&mut inv3, "h1"));
  okcode(inventory_add_group(&mut inv3, "g1"));
  okcode(inventory_add_group(&mut inv3, "g2"));
  okcode(inventory_add_group(&mut inv3, "g3"));
  okcode(inventory_add_host_to_group(&mut inv3, "h1", "g3"));
  okcode(inventory_add_group_child(&mut inv3, "g1", "g2"));
  if inventory_group_contains(&inv3, "g1", "h1") { ok = false; }
  okcode(inventory_add_group_child(&mut inv3, "g2", "g3"));
  if !inventory_group_contains(&inv3, "g1", "h1") { ok = false; }
  if !inventory_group_contains(&inv3, "g3", "h1") { ok = false; }
  return assert(ok, "group hierarchy edges, two-level closure and cycle rejection");
}

fn t4() -> TestResult {
  let inv = inv_fixture();
  var ok = true;
  var web = inventory_target_hosts(&inv, "web");
  if web.len() != 2 { ok = false; }
  let w0: Str = web[0];
  let w1: Str = web[1];
  if !streq(w0, "web1") { ok = false; }
  if !streq(w1, "web2") { ok = false; }
  var prod = inventory_target_hosts(&inv, "prod");
  if prod.len() != 3 { ok = false; }
  let p2: Str = prod[2];
  if !streq(p2, "db1") { ok = false; }
  if inventory_target_hosts(&inv, "all").len() != 3 { ok = false; }
  if inventory_target_hosts(&inv, "web1").len() != 1 { ok = false; }
  if inventory_target_hosts(&inv, "nope").len() != 0 { ok = false; }
  if inventory_target_hosts(&inv, "").len() != 0 { ok = false; }
  if okcode(inventory_validate(&inv)) != 3 { ok = false; }
  var bad = inv_fixture();
  bad.member_group.push("ghost");
  bad.member_host.push("web1");
  if !errint_is(inventory_validate(&bad), "ansible: invalid membership edge") { ok = false; }
  var bad2 = inv_fixture();
  bad2.gvar_group.push("ghost");
  bad2.gvar_key.push("k");
  bad2.gvar_value.push("v");
  if !errint_is(inventory_validate(&bad2), "ansible: invalid group var edge") { ok = false; }
  return assert(ok, "target patterns resolve in declaration order and validate catches bad edges");
}

fn t5() -> TestResult {
  let inv = inv_fixture();
  var ok = streq(okstr(inventory_var(&inv, "web1", "region")), "web1-region");
  if !streq(inventory_var_or(&inv, "web1", "region", "none"), "web1-region") { ok = false; }
  if !streq(inventory_var_or(&inv, "ghost", "region", "none"), "none") { ok = false; }
  if !streq(inventory_var_or(&inv, "web2", "missing", "fallback"), "fallback") { ok = false; }
  if !errstr_is(inventory_var(&inv, "web1", "missing"), "ansible: undefined variable: missing") { ok = false; }
  if !errstr_is(inventory_var(&inv, "ghost", "region"), "ansible: unknown host: ghost") { ok = false; }
  return assert(ok, "host vars override group vars and misses fall back");
}

fn t6() -> TestResult {
  let inv = inv_fixture();
  var ok = streq(okstr(inventory_var(&inv, "web2", "region")), "other");
  if !streq(okstr(inventory_var(&inv, "db1", "region")), "db-region") { ok = false; }
  if !streq(okstr(inventory_var(&inv, "web2", "http_port")), "80") { ok = false; }
  var inv3 = inventory_new();
  okcode(inventory_add_host(&mut inv3, "h1"));
  okcode(inventory_add_host(&mut inv3, "h2"));
  okcode(inventory_add_group(&mut inv3, "g1"));
  okcode(inventory_add_host_to_group(&mut inv3, "h1", "g1"));
  okcode(inventory_set_group_var(&mut inv3, "all", "k", "low"));
  if !streq(okstr(inventory_var(&inv3, "h2", "k")), "low") { ok = false; }
  okcode(inventory_set_group_var(&mut inv3, "g1", "k", "high"));
  if !streq(okstr(inventory_var(&inv3, "h1", "k")), "high") { ok = false; }
  okcode(inventory_set_group_var(&mut inv3, "g1", "k", "high2"));
  if !streq(okstr(inventory_var(&inv3, "h1", "k")), "high2") { ok = false; }
  return assert(ok, "group var precedence: deeper, later-declared and last assignment win over all");
}

fn t7() -> TestResult {
  var ok = module_kind("ping") == ANSIBLE_MODULE_PING;
  if module_kind("debug") != ANSIBLE_MODULE_DEBUG { ok = false; }
  if module_kind("fail") != ANSIBLE_MODULE_FAIL { ok = false; }
  if module_kind("command") != ANSIBLE_MODULE_COMMAND { ok = false; }
  if module_kind("shell") != ANSIBLE_MODULE_SHELL { ok = false; }
  if module_kind("copy") != ANSIBLE_MODULE_COPY { ok = false; }
  if module_kind("template") != ANSIBLE_MODULE_TEMPLATE { ok = false; }
  if module_kind("file") != ANSIBLE_MODULE_FILE { ok = false; }
  if module_kind("package") != ANSIBLE_MODULE_PACKAGE { ok = false; }
  if module_kind("service") != ANSIBLE_MODULE_SERVICE { ok = false; }
  if module_kind("user") != ANSIBLE_MODULE_USER { ok = false; }
  if module_kind("setup") != ANSIBLE_MODULE_SETUP { ok = false; }
  if module_kind("nope") != ANSIBLE_MODULE_UNKNOWN { ok = false; }
  if !module_is_known("copy") { ok = false; }
  if module_is_known("nope") { ok = false; }
  if module_count() != 12 { ok = false; }
  var names = module_names();
  if names.len() != 12 { ok = false; }
  let n0: Str = names[0];
  let n11: Str = names[11];
  if !streq(n0, "ping") { ok = false; }
  if !streq(n11, "setup") { ok = false; }
  var i = 0;
  while i < names.len() {
    let nm: Str = names[i];
    if !module_is_known(nm) { ok = false; }
    i = i + 1;
  }
  return assert(ok, "module registry kinds, membership and documented name list");
}

fn t8() -> TestResult {
  var ok = true;
  var k = 1;
  while k <= 12 {
    let nm = module_kind_name(k);
    if module_kind(nm) != k { ok = false; }
    k = k + 1;
  }
  if !streq(module_kind_name(ANSIBLE_MODULE_PING), "ping") { ok = false; }
  if !streq(module_kind_name(ANSIBLE_MODULE_SETUP), "setup") { ok = false; }
  if !streq(module_kind_name(0), "unknown") { ok = false; }
  if !streq(module_kind_name(99), "unknown") { ok = false; }
  return assert(ok, "module kind names round-trip through the explicit dispatch");
}

fn t9() -> TestResult {
  var ok = module_simulate("ping", "changed=1") == ANSIBLE_RESULT_OK;
  if module_simulate("debug", "skip=1") != ANSIBLE_RESULT_OK { ok = false; }
  if module_simulate("fail", "changed=1") != ANSIBLE_RESULT_FAILED { ok = false; }
  if module_simulate("copy", "changed=1") != ANSIBLE_RESULT_CHANGED { ok = false; }
  if module_simulate("command", "failed=1 changed=1") != ANSIBLE_RESULT_FAILED { ok = false; }
  if module_simulate("shell", "skip=1 changed=1") != ANSIBLE_RESULT_SKIPPED { ok = false; }
  if module_simulate("file", "") != ANSIBLE_RESULT_OK { ok = false; }
  if module_simulate("template", "failed=1") != ANSIBLE_RESULT_FAILED { ok = false; }
  if module_simulate("nope", "") != ANSIBLE_RESULT_FAILED { ok = false; }
  if !streq(module_result_name(ANSIBLE_RESULT_CHANGED), "changed") { ok = false; }
  if !streq(module_result_name(ANSIBLE_RESULT_OK), "ok") { ok = false; }
  if !streq(module_result_name(ANSIBLE_RESULT_FAILED), "failed") { ok = false; }
  if !streq(module_result_name(ANSIBLE_RESULT_SKIPPED), "skipped") { ok = false; }
  if !streq(module_result_name(-1), "unknown") { ok = false; }
  return assert(ok, "module simulation rules and result code names are stable");
}

fn t10() -> TestResult {
  var pb = web_playbook(ANSIBLE_STRATEGY_LINEAR);
  var ok = playbook_play_count(&pb) == 1;
  if playbook_block_count(&pb) != 1 { ok = false; }
  if playbook_task_count(&pb) != 3 { ok = false; }
  if playbook_handler_count(&pb) != 1 { ok = false; }
  if !streq(okstr(playbook_play_name(&pb, 0)), "web-play") { ok = false; }
  if !streq(okstr(playbook_play_hosts(&pb, 0)), "web") { ok = false; }
  if !streq(okstr(playbook_block_name(&pb, 0)), "config-block") { ok = false; }
  if !streq(okstr(playbook_task_name(&pb, 0)), "copy-index") { ok = false; }
  if !streq(okstr(playbook_task_module(&pb, 0)), "copy") { ok = false; }
  if !streq(okstr(playbook_handler_name(&pb, 0)), "restart-web") { ok = false; }
  if !streq(ansible_strategy_name(ANSIBLE_STRATEGY_LINEAR), "linear") { ok = false; }
  if !streq(ansible_strategy_name(ANSIBLE_STRATEGY_FREE), "free") { ok = false; }
  if !streq(ansible_strategy_name(7), "unknown") { ok = false; }
  if okcode(playbook_validate(&mut pb)) != 3 { ok = false; }
  return assert(ok, "playbook builder counts, accessors and strategy names");
}

fn t11() -> TestResult {
  var pb = playbook_new();
  var ok = errint_is(playbook_add_play(&mut pb, "p", "web", 7), "ansible: invalid strategy");
  if !errint_is(playbook_add_play(&mut pb, "", "web", 0), "ansible: empty name") { ok = false; }
  if !errint_is(playbook_add_play(&mut pb, "p", "", 0), "ansible: empty name") { ok = false; }
  let play = okcode(playbook_add_play(&mut pb, "p", "web", 0));
  if !errint_is(playbook_add_task(&mut pb, 9, -1, "t", "ping", "", "", ""), "ansible: unknown play") { ok = false; }
  if !errint_is(playbook_add_task(&mut pb, play, 9, "t", "ping", "", "", ""), "ansible: unknown block") { ok = false; }
  if !errint_is(playbook_add_task(&mut pb, play, -1, "t", "nope", "", "", ""), "ansible: unknown module: nope") { ok = false; }
  if !errint_is(playbook_add_task(&mut pb, play, -1, "", "ping", "", "", ""), "ansible: empty name") { ok = false; }
  if !errint_is(playbook_add_block(&mut pb, 9, "b", ""), "ansible: unknown play") { ok = false; }
  if !errint_is(playbook_add_handler(&mut pb, play, "h", "nope", ""), "ansible: unknown module: nope") { ok = false; }
  let play2 = okcode(playbook_add_play(&mut pb, "p2", "web", 0));
  let blk2 = okcode(playbook_add_block(&mut pb, play2, "b2", ""));
  if !errint_is(playbook_add_task(&mut pb, play, blk2, "t", "ping", "", "", ""), "ansible: unknown block") { ok = false; }
  return assert(ok, "playbook builder rejects bad indices, names and modules");
}

fn t12() -> TestResult {
  var pb = playbook_new();
  let play = okcode(playbook_add_play(&mut pb, "p", "web", 0));
  okcode(playbook_add_task(&mut pb, play, -1, "t", "ping", "", "", "ghost"));
  let inv = inv_fixture();
  var fs = facts_new();
  var ok = errint_is(playbook_validate(&mut pb), "ansible: unknown handler: ghost");
  if !streq(errm_rep(run_playbook(&mut pb, &inv, &mut fs, "", "")), "ansible: unknown handler: ghost") { ok = false; }
  var pb2 = web_playbook(ANSIBLE_STRATEGY_LINEAR);
  if okcode(playbook_validate(&mut pb2)) != 3 { ok = false; }
  let rep = okrep(run_playbook(&mut pb2, &inv, &mut fs, "", ""));
  if report_len(&rep) != 6 { ok = false; }
  return assert(ok, "playbook validation checks notify targets and gates the executor");
}

fn t13() -> TestResult {
  var ok = ansible_tags_has("a,b", "a");
  if !ansible_tags_has("a,b", "b") { ok = false; }
  if ansible_tags_has("a,b", "c") { ok = false; }
  if ansible_tags_has("", "a") { ok = false; }
  if ansible_tags_has("a,b", "") { ok = false; }
  if ansible_tags_has("a", "a,b") { ok = false; }
  if ansible_tags_has("alpha,beta", "alp") { ok = false; }
  if ansible_tags_count("a,b,c") != 3 { ok = false; }
  if ansible_tags_count("") != 0 { ok = false; }
  if ansible_tags_count("a,,b") != 2 { ok = false; }
  if ansible_tags_count(",") != 0 { ok = false; }
  return assert(ok, "tag token membership and counting are exact");
}

fn t14() -> TestResult {
  var ok = ansible_tags_match("", "", "", "");
  if !ansible_tags_match("", "", "", "always") { ok = false; }
  if ansible_tags_match("", "", "", "never") { ok = false; }
  if !ansible_tags_match("never", "", "", "never") { ok = false; }
  if !ansible_tags_match("x", "", "", "always") { ok = false; }
  if !ansible_tags_match("all", "", "", "a") { ok = false; }
  if ansible_tags_match("all", "", "", "never") { ok = false; }
  if !ansible_tags_match("web", "", "", "web") { ok = false; }
  if ansible_tags_match("web", "", "", "db") { ok = false; }
  if !ansible_tags_match("web,db", "", "", "db") { ok = false; }
  if !ansible_tags_match("config", "", "config", "x") { ok = false; }
  if !ansible_tags_match("setup", "setup", "", "") { ok = false; }
  if !ansible_tags_match("never", "", "", "always,never") { ok = false; }
  if ansible_tags_match("config", "", "config", "never") { ok = false; }
  return assert(ok, "tag filter rules cover empty, always, never, all and cascade");
}

fn t15() -> TestResult {
  let inv = inv_fixture();
  var pb = playbook_new();
  let play = okcode(playbook_add_play(&mut pb, "limit-play", "all", ANSIBLE_STRATEGY_LINEAR));
  okcode(playbook_add_task(&mut pb, play, -1, "ping-all", "ping", "", "", ""));
  var fs = facts_new();
  var ok = true;
  let r1 = okrep(run_playbook(&mut pb, &inv, &mut fs, "", "web"));
  if r1.task_names.len() != 2 { ok = false; }
  let h0: Str = r1.hosts[0];
  let h1: Str = r1.hosts[1];
  if !streq(h0, "web1") { ok = false; }
  if !streq(h1, "web2") { ok = false; }
  let r2 = okrep(run_playbook(&mut pb, &inv, &mut fs, "", "web1"));
  if r2.task_names.len() != 1 { ok = false; }
  let r3 = okrep(run_playbook(&mut pb, &inv, &mut fs, "", "nope"));
  if r3.task_names.len() != 0 { ok = false; }
  let r4 = okrep(run_playbook(&mut pb, &inv, &mut fs, "", ""));
  if r4.task_names.len() != 3 { ok = false; }
  return assert(ok, "limit filters play targets by group, host, unknown and empty");
}

fn t16() -> TestResult {
  let inv = inv_fixture();
  var pb = web_playbook(ANSIBLE_STRATEGY_LINEAR);
  var fs = facts_new();
  let rep = okrep(run_playbook(&mut pb, &inv, &mut fs, "", ""));
  var ok = report_len(&rep) == 6;
  if !streq(report_order_text(&rep), "copy-index@web1,copy-index@web2,ping-all@web1,ping-all@web2,check@web1,check@web2") { ok = false; }
  if rep.changed != 4 { ok = false; }
  if rep.ok != 4 { ok = false; }
  if rep.failed != 0 { ok = false; }
  if rep.skipped != 0 { ok = false; }
  if rep.filtered != 0 { ok = false; }
  if report_handler_count(&rep) != 2 { ok = false; }
  if !streq(okstr(report_trace_at(&rep, 0)), "web-play | copy-index | web1 | changed") { ok = false; }
  return assert(ok, "linear strategy executes task-major in declaration order");
}

fn t17() -> TestResult {
  let inv = inv_fixture();
  var pb = web_playbook(ANSIBLE_STRATEGY_FREE);
  var fs = facts_new();
  let rep = okrep(run_playbook(&mut pb, &inv, &mut fs, "", ""));
  var ok = report_len(&rep) == 6;
  if !streq(report_order_text(&rep), "copy-index@web1,ping-all@web1,check@web1,copy-index@web2,ping-all@web2,check@web2") { ok = false; }
  if rep.changed != 4 { ok = false; }
  if rep.ok != 4 { ok = false; }
  if report_handler_count(&rep) != 2 { ok = false; }
  return assert(ok, "free strategy executes host-major in target order");
}

fn t18() -> TestResult {
  let inv = inv_fixture();
  var pb = notify_playbook();
  var fs = facts_new();
  let rep = okrep(run_playbook(&mut pb, &inv, &mut fs, "", ""));
  var ok = report_len(&rep) == 8;
  if report_notified_count(&rep) != 2 { ok = false; }
  if !streq(okstr(report_notified_at(&rep, 0)), "hA") { ok = false; }
  if !streq(okstr(report_notified_at(&rep, 1)), "hB") { ok = false; }
  if report_handler_count(&rep) != 4 { ok = false; }
  if !streq(okstr(report_handler_name(&rep, 0)), "hA") { ok = false; }
  if !streq(okstr(report_handler_host(&rep, 0)), "web1") { ok = false; }
  if !streq(okstr(report_handler_name(&rep, 3)), "hB") { ok = false; }
  if !streq(okstr(report_handler_host(&rep, 3)), "web2") { ok = false; }
  if rep.changed != 10 { ok = false; }
  if rep.ok != 2 { ok = false; }
  if rep.failed != 0 { ok = false; }
  if rep.skipped != 0 { ok = false; }
  return assert(ok, "handler notifications dedup by pair and run in first-notification order");
}

fn t19() -> TestResult {
  let inv = inv_fixture();
  var pb = mix_playbook();
  var fs = facts_new();
  let rep = okrep(run_playbook(&mut pb, &inv, &mut fs, "", ""));
  var ok = report_len(&rep) == 8;
  if rep.changed != 2 { ok = false; }
  if rep.ok != 0 { ok = false; }
  if rep.failed != 2 { ok = false; }
  if rep.skipped != 4 { ok = false; }
  if rep.changed + rep.ok + rep.failed + rep.skipped != report_len(&rep) { ok = false; }
  if report_result_count(&rep, ANSIBLE_RESULT_CHANGED) != 2 { ok = false; }
  if report_result_count(&rep, ANSIBLE_RESULT_FAILED) != 2 { ok = false; }
  if report_result_count(&rep, ANSIBLE_RESULT_SKIPPED) != 4 { ok = false; }
  if !streq(report_summary(&rep), "changed=2 ok=0 failed=2 skipped=4 filtered=0") { ok = false; }
  return assert(ok, "result accounting covers changed, ok, failed and skipped");
}

fn t20() -> TestResult {
  let inv = inv_fixture();
  var pb = mix_playbook();
  var fs = facts_new();
  let rep = okrep(run_playbook(&mut pb, &inv, &mut fs, "", ""));
  var ok = true;
  var i = 0;
  while i < report_len(&rep) {
    let tname = okstr(report_task_name(&rep, i));
    let code = report_result(&rep, i);
    if streq(tname, "boom") {
      if code != ANSIBLE_RESULT_FAILED { ok = false; }
    }
    if streq(tname, "after") {
      if code != ANSIBLE_RESULT_SKIPPED { ok = false; }
    }
    i = i + 1;
  }
  if !streq(okstr(report_task_name(&rep, 6)), "after") { ok = false; }
  if report_result(&rep, 6) != ANSIBLE_RESULT_SKIPPED { ok = false; }
  return assert(ok, "a failed host skips every later task and failures are recorded exactly once");
}

fn t21() -> TestResult {
  let inv = inv_fixture();
  var pb = filter_playbook();
  var fs = facts_new();
  let r1 = okrep(run_playbook(&mut pb, &inv, &mut fs, "config", ""));
  var ok = r1.task_names.len() == 6;
  if r1.filtered != 2 { ok = false; }
  var has_check = false;
  var has_never = false;
  var has_inblock = false;
  var i = 0;
  while i < r1.task_names.len() {
    let nm = okstr(report_task_name(&r1, i));
    if streq(nm, "check-task") { has_check = true; }
    if streq(nm, "never-task") { has_never = true; }
    if streq(nm, "in-block") { has_inblock = true; }
    i = i + 1;
  }
  if has_check { ok = false; }
  if has_never { ok = false; }
  if !has_inblock { ok = false; }
  let r2 = okrep(run_playbook(&mut pb, &inv, &mut fs, "", ""));
  if r2.task_names.len() != 8 { ok = false; }
  if r2.filtered != 1 { ok = false; }
  return assert(ok, "tag filtering selects block tags and always, excludes never and unmatched");
}

fn t22() -> TestResult {
  var fs = facts_new();
  var ok = facts_count(&fs) == 0;
  if okcode(facts_set_str(&mut fs, "h1", "distribution", "ubuntu")) != 0 { ok = false; }
  if okcode(facts_set_int(&mut fs, "h1", "cpu", 4)) != 1 { ok = false; }
  if okcode(facts_set_bool(&mut fs, "h1", "gathered", true)) != 2 { ok = false; }
  if facts_count(&fs) != 3 { ok = false; }
  if !facts_has(&fs, "h1", "cpu") { ok = false; }
  if facts_has(&fs, "h1", "missing") { ok = false; }
  if !streq(okstr(facts_get_str(&fs, "h1", "distribution")), "ubuntu") { ok = false; }
  if okcode(facts_set_str(&mut fs, "h1", "distribution", "debian")) != 0 { ok = false; }
  if facts_count(&fs) != 3 { ok = false; }
  if !streq(okstr(facts_get_str(&fs, "h1", "distribution")), "debian") { ok = false; }
  if okcode(facts_get_int(&fs, "h1", "cpu")) != 4 { ok = false; }
  if !bool_true(facts_get_bool(&fs, "h1", "gathered")) { ok = false; }
  if !errstr_is(facts_get_str(&fs, "h1", "cpu"), "ansible: fact type mismatch: h1.cpu") { ok = false; }
  if !errstr_is(facts_get_str(&fs, "h1", "missing"), "ansible: undefined fact: h1.missing") { ok = false; }
  if !errbool_is(facts_get_bool(&fs, "h1", "cpu"), "ansible: fact type mismatch: h1.cpu") { ok = false; }
  if okcode(facts_set_int(&mut fs, "h1", "cpu", 8)) != 1 { ok = false; }
  if okcode(facts_get_int(&fs, "h1", "cpu")) != 8 { ok = false; }
  if okcode(facts_set_bool(&mut fs, "h1", "gathered", false)) != 2 { ok = false; }
  if bool_true(facts_get_bool(&fs, "h1", "gathered")) { ok = false; }
  if !streq(facts_kind_name(ANSIBLE_FACT_STR), "str") { ok = false; }
  if !streq(facts_kind_name(ANSIBLE_FACT_INT), "int") { ok = false; }
  if !streq(facts_kind_name(ANSIBLE_FACT_BOOL), "bool") { ok = false; }
  if !streq(facts_kind_name(9), "unknown") { ok = false; }
  return assert(ok, "typed facts set, replace in place and reject kind mismatches");
}

fn t23() -> TestResult {
  var fs = facts_new();
  okcode(facts_set_str(&mut fs, "h1", "dist", "ubuntu"));
  okcode(facts_set_int(&mut fs, "h1", "cpu", 4));
  okcode(facts_set_int(&mut fs, "h1", "mem", 16));
  okcode(facts_set_str(&mut fs, "h2", "dist", "ubuntu"));
  okcode(facts_set_int(&mut fs, "h2", "cpu", 8));
  okcode(facts_set_int(&mut fs, "h2", "mem", 32));
  okcode(facts_set_str(&mut fs, "h3", "dist", "debian"));
  okcode(facts_set_int(&mut fs, "h3", "cpu", 2));
  var ok = facts_sum_int(&fs, "", "") == 62;
  if facts_sum_int(&fs, "", "cpu") != 14 { ok = false; }
  if facts_sum_int(&fs, "h1", "") != 20 { ok = false; }
  if facts_sum_int(&fs, "h1", "mem") != 16 { ok = false; }
  if facts_sum_int(&fs, "h9", "cpu") != 0 { ok = false; }
  if facts_count_str(&fs, "dist", "ubuntu") != 2 { ok = false; }
  if facts_count_str(&fs, "dist", "debian") != 1 { ok = false; }
  if facts_count_str(&fs, "dist", "fedora") != 0 { ok = false; }
  if facts_scope_count(&fs, "h1") != 3 { ok = false; }
  if facts_count(&fs) != 8 { ok = false; }
  return assert(ok, "facts aggregate by scope, key prefix and Str value");
}

fn t24() -> TestResult {
  var inv = inv_fixture();
  okcode(inventory_set_host_var(&mut inv, "web1", "ansible_distribution", "ubuntu"));
  okcode(inventory_set_host_var(&mut inv, "web1", "ansible_cpu_count", "4"));
  var pb = setup_playbook();
  var fs = facts_new();
  let rep = okrep(run_playbook(&mut pb, &inv, &mut fs, "", ""));
  var ok = report_len(&rep) == 2;
  if rep.ok != 2 { ok = false; }
  if facts_count(&fs) != 8 { ok = false; }
  if !streq(okstr(facts_get_str(&fs, "web1", "ansible_distribution")), "ubuntu") { ok = false; }
  if okcode(facts_get_int(&fs, "web1", "ansible_cpu_count")) != 4 { ok = false; }
  if !bool_true(facts_get_bool(&fs, "web1", "ansible_gathered")) { ok = false; }
  if !streq(okstr(facts_get_str(&fs, "web1", "ansible_host_name")), "web1") { ok = false; }
  if !streq(okstr(facts_get_str(&fs, "web2", "ansible_distribution")), "unknown") { ok = false; }
  if okcode(facts_get_int(&fs, "web2", "ansible_cpu_count")) != 0 { ok = false; }
  if facts_scope_count(&fs, "web1") != 4 { ok = false; }
  return assert(ok, "setup module gathers typed facts for every target host");
}

fn t25() -> TestResult {
  let inv = inv_fixture();
  var pb = web_playbook(ANSIBLE_STRATEGY_LINEAR);
  var fs = facts_new();
  let rep = okrep(run_playbook(&mut pb, &inv, &mut fs, "", ""));
  var ok = report_len(&rep) == 6;
  if report_result(&rep, 0) != ANSIBLE_RESULT_CHANGED { ok = false; }
  if report_result(&rep, 99) != -1 { ok = false; }
  if report_result_count(&rep, ANSIBLE_RESULT_CHANGED) != 2 { ok = false; }
  if rep.changed != 4 { ok = false; }
  if !streq(okstr(report_task_name(&rep, 5)), "check") { ok = false; }
  if !streq(okstr(report_play_name(&rep, 0)), "web-play") { ok = false; }
  if !streq(okstr(report_host(&rep, 1)), "web2") { ok = false; }
  if !streq(okstr(report_module(&rep, 0)), "copy") { ok = false; }
  if !errstr_is(report_task_name(&rep, 99), "ansible: index out of range: result") { ok = false; }
  let text = report_trace_text(&rep);
  var first = okstr(report_trace_at(&rep, 0));
  if !streq(first, "web-play | copy-index | web1 | changed") { ok = false; }
  if !streq(report_order_text(&rep), "copy-index@web1,copy-index@web2,ping-all@web1,ping-all@web2,check@web1,check@web2") { ok = false; }
  if text.len() == 0 { ok = false; }
  return assert(ok, "report accessors, trace text and bounds errors");
}

fn t26() -> TestResult {
  let inv = inv_fixture();
  var fs = facts_new();
  var ok = streq(ansible_strategy_name(ANSIBLE_STRATEGY_LINEAR), "linear");
  if !ansible_strategy_valid(ANSIBLE_STRATEGY_FREE) { ok = false; }
  if ansible_strategy_valid(7) { ok = false; }
  var lin = strategy_playbook(ANSIBLE_STRATEGY_LINEAR);
  let a = okrep(run_playbook(&mut lin, &inv, &mut fs, "", ""));
  if report_len(&a) != 12 { ok = false; }
  if a.changed != 6 { ok = false; }
  if a.ok != 3 { ok = false; }
  if a.skipped != 3 { ok = false; }
  if a.changed + a.ok + a.failed + a.skipped != 12 { ok = false; }
  if !streq(okstr(report_task_name(&a, 0)), "a") { ok = false; }
  if !streq(okstr(report_host(&a, 1)), "web2") { ok = false; }
  var fr = strategy_playbook(ANSIBLE_STRATEGY_FREE);
  let b = okrep(run_playbook(&mut fr, &inv, &mut fs, "", ""));
  if report_len(&b) != 12 { ok = false; }
  if !streq(okstr(report_task_name(&b, 1)), "b") { ok = false; }
  if !streq(okstr(report_host(&b, 1)), "web1") { ok = false; }
  if inventory_target_hosts(&inv, "all").len() != 3 { ok = false; }
  return assert(ok, "linear and free orderings differ deterministically with equal totals");
}

fn main() -> Int {
  io.println("=== xiom.ansible conformance tests ===");
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
    io.println("xiom.ansible: all tests passed");
  } else {
    io.println("xiom.ansible: tests failed");
  }
  return failed;
}

