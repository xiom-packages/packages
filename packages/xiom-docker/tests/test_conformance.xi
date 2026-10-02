// XIOM -- xiom.docker conformance tests (26 checks)
// Port task: prove the pure-XIOM Docker management model against its
// documented API (image reference grammar, layer chains, container state
// machine, registry login and push/pull plans, compose dependency graph and
// topological order, volume/network sets).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// All Str equality goes through streq (str_compare): `==` on Str values
// read from Vec[Str] elements lowers to a pointer comparison. Every Vec
// element read binds a typed local first. Fixture helpers unwrap Results
// with an empty fallback, so an unexpected Err fails the owning assertion
// loudly instead of crashing the suite. Everything is deterministic: no
// threads, no wall clock, no files.

module docker_tests
use xiom.io; use xiom.test;
use xiom.docker;
use xiom.docker.image;
use xiom.docker.registry;
use xiom.docker.compose;
use xiom.docker.resources;
use xiom.string.compare;

const DIGEST_A: Str = "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
const DIGEST_B: Str = "sha256:fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210";
const DIGEST_C: Str = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
const DIGEST_D: Str = "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// --------------------------------------------------
//  Fixtures (Err branches are unreachable for the valid inputs used)
// --------------------------------------------------

fn empty_ref() -> ImageRef {
  return ImageRef{ registry: ""; repository: ""; tag: ""; digest: ""; };
}

fn empty_image() -> DockerImage {
  var offs = Vec[Int].new();
  offs.push(0);
  return DockerImage{
    registry: ""; repository: ""; tag: ""; digest: "";
    config_digest: ""; layer_data: ""; layer_off: offs;
  };
}

fn empty_reg() -> DockerRegistry {
  return DockerRegistry{ host: ""; user: ""; logged_in: false; logins: 0; logouts: 0; };
}

fn empty_plan() -> DockerPlan {
  var offs = Vec[Int].new();
  offs.push(0);
  return DockerPlan{
    op: -1; registry: ""; repository: ""; tag: ""; digest: "";
    needs_auth: false; steps_data: ""; steps_off: offs;
  };
}

fn ref_of(r: Result[ImageRef, Str]) -> ImageRef {
  match r {
    Ok(v) => { return v; },
    Err(_) => { return empty_ref(); },
  }
  return empty_ref();
}

fn image_of(r: Result[DockerImage, Str]) -> DockerImage {
  match r {
    Ok(v) => { return v; },
    Err(_) => { return empty_image(); },
  }
  return empty_image();
}

fn reg_of(r: Result[DockerRegistry, Str]) -> DockerRegistry {
  match r {
    Ok(v) => { return v; },
    Err(_) => { return empty_reg(); },
  }
  return empty_reg();
}

fn plan_of(r: Result[DockerPlan, Str]) -> DockerPlan {
  match r {
    Ok(v) => { return v; },
    Err(_) => { return empty_plan(); },
  }
  return empty_plan();
}

fn order_of(r: Result[Vec[Int], Str]) -> Vec[Int] {
  match r {
    Ok(v) => { return v; },
    Err(_) => { return Vec[Int].new(); },
  }
  return Vec[Int].new();
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

fn ref_err_is(r: Result[ImageRef, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn image_err_is(r: Result[DockerImage, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn reg_err_is(r: Result[DockerRegistry, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn plan_err_is(r: Result[DockerPlan, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn order_err_is(r: Result[Vec[Int], Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn step_is(p: &DockerPlan, i: Int, want: Str) -> Bool {
  let got: Str = plan_step_at(p, i);
  return streq(got, want);
}

// --------------------------------------------------
//  Image references
// --------------------------------------------------

fn t1() -> TestResult {
  let r = ref_of(image_ref_parse("nginx:1.25"));
  var ok = streq(image_ref_registry(&r), "docker.io");
  if !streq(image_ref_repository(&r), "nginx") { ok = false; }
  if !streq(image_ref_tag(&r), "1.25") { ok = false; }
  if !streq(image_ref_digest(&r), "") { ok = false; }
  if image_ref_has_digest(&r) { ok = false; }
  if !streq(image_ref_render(&r), "nginx:1.25") { ok = false; }
  if !streq(image_ref_name(&r), "docker.io/nginx") { ok = false; }
  return assert(ok, "parse repo:tag defaults registry and round-trips");
}

fn t2() -> TestResult {
  let r = ref_of(image_ref_parse("acme/tool"));
  var ok = streq(image_ref_repository(&r), "acme/tool");
  if !streq(image_ref_tag(&r), "latest") { ok = false; }
  if !streq(image_ref_registry(&r), "docker.io") { ok = false; }
  return assert(ok, "omitted tag defaults to latest");
}

fn t3() -> TestResult {
  let r = ref_of(image_ref_parse("ghcr.io:443/acme/tool:v2@" + DIGEST_A));
  var ok = streq(image_ref_registry(&r), "ghcr.io:443");
  if !streq(image_ref_repository(&r), "acme/tool") { ok = false; }
  if !streq(image_ref_tag(&r), "v2") { ok = false; }
  if !streq(image_ref_digest(&r), DIGEST_A) { ok = false; }
  if !image_ref_has_digest(&r) { ok = false; }
  return assert(ok, "registry port, tag and digest split correctly");
}

fn t4() -> TestResult {
  let r = ref_of(image_ref_parse("alpine@" + DIGEST_B));
  var ok = streq(image_ref_tag(&r), "");
  if !streq(image_ref_repository(&r), "alpine") { ok = false; }
  if !streq(image_ref_render(&r), "alpine@" + DIGEST_B) { ok = false; }
  let l = ref_of(image_ref_parse("localhost/tool"));
  if !streq(image_ref_registry(&l), "localhost") { ok = false; }
  let p = ref_of(image_ref_parse("localhost:5000/tool"));
  if !streq(image_ref_registry(&p), "localhost:5000") { ok = false; }
  if !streq(image_ref_repository(&p), "tool") { ok = false; }
  return assert(ok, "digest-only keeps empty tag; localhost is a registry");
}

fn t5() -> TestResult {
  var ok = ref_err_is(image_ref_parse(""), "image: empty reference");
  if !ref_err_is(image_ref_parse("a@" + DIGEST_A + "@" + DIGEST_B), "image: multiple digests") { ok = false; }
  if !ref_err_is(image_ref_parse("a@sha256:xyz"), "image: invalid digest") { ok = false; }
  if !ref_err_is(image_ref_parse("Tool:1"), "image: invalid repository") { ok = false; }
  if !ref_err_is(image_ref_parse("nginx:"), "image: invalid tag") { ok = false; }
  if !ref_err_is(image_ref_parse("nginx:-bad"), "image: invalid tag") { ok = false; }
  if !ref_err_is(image_ref_parse("/nginx"), "image: invalid repository") { ok = false; }
  if !ref_err_is(image_ref_parse("nginx//x"), "image: invalid repository") { ok = false; }
  return assert(ok, "malformed references report the exact grammar error");
}

fn t6() -> TestResult {
  let r = ref_of(image_ref_parse("registry.example.com/team/repo:1.2.3-rc_1"));
  var ok = streq(image_ref_tag(&r), "1.2.3-rc_1");
  if !image_ref_valid("repo:1.0") { ok = false; }
  if image_ref_valid("repo:..") { ok = false; }
  if image_ref_valid("repo::") { ok = false; }
  return assert(ok, "tag grammar accepts dots, dashes and underscores");
}

// --------------------------------------------------
//  Image model
// --------------------------------------------------

fn t7() -> TestResult {
  var img = image_of(docker_image_new("alpine:3.19"));
  var ok = streq(docker_image_repository(&img), "alpine");
  if !int_ok_is(docker_image_add_layer(&mut img, DIGEST_A), 1) { ok = false; }
  if !int_ok_is(docker_image_add_layer(&mut img, DIGEST_B), 2) { ok = false; }
  if !int_ok_is(docker_image_add_layer(&mut img, DIGEST_C), 3) { ok = false; }
  if docker_image_layer_count(&img) != 3 { ok = false; }
  if !streq(docker_image_layer_at(&img, 0), DIGEST_A) { ok = false; }
  if !streq(docker_image_layer_at(&img, 2), DIGEST_C) { ok = false; }
  if !docker_image_has_layer(&img, DIGEST_B) { ok = false; }
  if docker_image_has_layer(&img, DIGEST_D) { ok = false; }
  if !int_err_is(docker_image_add_layer(&mut img, DIGEST_B), "image: duplicate layer") { ok = false; }
  if !int_err_is(docker_image_add_layer(&mut img, "sha256:zz"), "image: invalid layer digest") { ok = false; }
  if docker_image_layer_count(&img) != 3 { ok = false; }
  return assert(ok, "layer chain appends unique digests and rejects duplicates");
}

fn t8() -> TestResult {
  var img = image_of(docker_image_new("alpine:3.19"));
  var ok = image_err_is(docker_image_new(""), "image: empty reference");
  if !streq(docker_image_config_digest(&img), "") { ok = false; }
  if !int_ok_is(docker_image_set_config(&mut img, DIGEST_D), 0) { ok = false; }
  if !streq(docker_image_config_digest(&img), DIGEST_D) { ok = false; }
  if !int_err_is(docker_image_set_config(&mut img, "nope"), "image: invalid layer digest") { ok = false; }
  if !streq(docker_image_layer_at(&img, -1), "") { ok = false; }
  if !streq(docker_image_layer_at(&img, 0), "") { ok = false; }
  return assert(ok, "config digest set/validate and layer bounds return empty");
}

// --------------------------------------------------
//  Container state machine
// --------------------------------------------------

fn t9() -> TestResult {
  var m = container_model_new();
  var ok = int_ok_is(container_create(&mut m, "web", "nginx:1.25"), 0);
  if !int_ok_is(container_create(&mut m, "db", "postgres:16"), 1) { ok = false; }
  if container_count(&m) != 2 { ok = false; }
  if container_live_count(&m) != 2 { ok = false; }
  if !streq(container_name(&m, 0), "web") { ok = false; }
  if !streq(container_name(&m, 1), "db") { ok = false; }
  if !streq(container_image(&m, 1), "postgres:16") { ok = false; }
  if container_index(&m, "db") != 1 { ok = false; }
  if container_index(&m, "nope") != DOCKER_NOT_FOUND { ok = false; }
  if container_state(&m, 0) != DOCKER_CT_CREATED { ok = false; }
  if container_state(&m, 9) != DOCKER_NOT_FOUND { ok = false; }
  if !int_err_is(container_create(&mut m, "web", "nginx:1.25"), "container: duplicate name") { ok = false; }
  if !int_err_is(container_create(&mut m, "", "nginx:1.25"), "container: name must not be empty") { ok = false; }
  if !int_err_is(container_create(&mut m, "x", "bad ref"), "image: invalid repository") { ok = false; }
  return assert(ok, "container creation, accessors and duplicate/empty-image errors");
}

fn t10() -> TestResult {
  var m = container_model_new();
  var ok = int_ok_is(container_create(&mut m, "web", "nginx:1.25"), 0);
  if !int_ok_is(container_start(&mut m, 0), DOCKER_CT_RUNNING) { ok = false; }
  if !int_ok_is(container_stop(&mut m, 0), DOCKER_CT_STOPPED) { ok = false; }
  if !int_ok_is(container_start(&mut m, 0), DOCKER_CT_RUNNING) { ok = false; }
  if !int_ok_is(container_restart(&mut m, 0), DOCKER_CT_RUNNING) { ok = false; }
  if !int_err_is(container_remove(&mut m, 0), "container: stop before removing") { ok = false; }
  if !int_ok_is(container_stop(&mut m, 0), DOCKER_CT_STOPPED) { ok = false; }
  if !int_ok_is(container_remove(&mut m, 0), DOCKER_CT_REMOVED) { ok = false; }
  if container_state(&m, 0) != DOCKER_CT_REMOVED { ok = false; }
  if container_live_count(&m) != 0 { ok = false; }
  if container_count(&m) != 1 { ok = false; }
  if container_start_count(&m, 0) != 2 { ok = false; }
  if container_stop_count(&m, 0) != 2 { ok = false; }
  if container_restart_count(&m, 0) != 1 { ok = false; }
  if !int_err_is(container_start(&mut m, 0), "container: container removed") { ok = false; }
  return assert(ok, "valid lifecycle path updates state and counters");
}

fn t11() -> TestResult {
  var m = container_model_new();
  var ok = int_ok_is(container_create(&mut m, "web", "nginx:1.25"), 0);
  if !int_err_is(container_stop(&mut m, 0), "container: not running") { ok = false; }
  if !int_err_is(container_restart(&mut m, 0), "container: not started") { ok = false; }
  if !int_err_is(container_start(&mut m, 7), "container: unknown id") { ok = false; }
  if !int_ok_is(container_start(&mut m, 0), DOCKER_CT_RUNNING) { ok = false; }
  if !int_err_is(container_start(&mut m, 0), "container: already running") { ok = false; }
  if !int_ok_is(container_stop(&mut m, 0), DOCKER_CT_STOPPED) { ok = false; }
  if !int_err_is(container_stop(&mut m, 0), "container: already stopped") { ok = false; }
  if !int_ok_is(container_remove(&mut m, 0), DOCKER_CT_REMOVED) { ok = false; }
  if !int_err_is(container_remove(&mut m, 0), "container: container removed") { ok = false; }
  if !int_err_is(container_transition(&mut m, 0, 99), "container: unknown action") { ok = false; }
  return assert(ok, "invalid transitions return the exact error and keep state");
}

fn t12() -> TestResult {
  var allowed = 0;
  var from = 0;
  while from < 4 {
    var to = 0;
    while to < 4 {
      if container_can_transition(from, to) { allowed = allowed + 1; }
      to = to + 1;
    }
    from = from + 1;
  }
  var ok = allowed == 6;
  if !container_can_transition(DOCKER_CT_CREATED, DOCKER_CT_RUNNING) { ok = false; }
  if !container_can_transition(DOCKER_CT_CREATED, DOCKER_CT_REMOVED) { ok = false; }
  if !container_can_transition(DOCKER_CT_RUNNING, DOCKER_CT_STOPPED) { ok = false; }
  if !container_can_transition(DOCKER_CT_RUNNING, DOCKER_CT_RUNNING) { ok = false; }
  if !container_can_transition(DOCKER_CT_STOPPED, DOCKER_CT_RUNNING) { ok = false; }
  if !container_can_transition(DOCKER_CT_STOPPED, DOCKER_CT_REMOVED) { ok = false; }
  if container_can_transition(DOCKER_CT_REMOVED, DOCKER_CT_RUNNING) { ok = false; }
  if container_can_transition(DOCKER_CT_CREATED, DOCKER_CT_STOPPED) { ok = false; }
  return assert(ok, "transition table has exactly six legal state pairs");
}

fn t13() -> TestResult {
  var ok = streq(container_state_name(DOCKER_CT_CREATED), "created");
  if !streq(container_state_name(DOCKER_CT_RUNNING), "running") { ok = false; }
  if !streq(container_state_name(DOCKER_CT_STOPPED), "stopped") { ok = false; }
  if !streq(container_state_name(DOCKER_CT_REMOVED), "removed") { ok = false; }
  if !streq(container_state_name(DOCKER_NOT_FOUND), "unknown") { ok = false; }
  return assert(ok, "state names render deterministically");
}

// --------------------------------------------------
//  Registry login and plans
// --------------------------------------------------

fn t14() -> TestResult {
  var reg = reg_of(registry_new("ghcr.io"));
  var ok = streq(registry_host(&reg), "ghcr.io");
  if !reg_err_is(registry_new(""), "registry: host must not be empty") { ok = false; }
  if !int_err_is(registry_login(&mut reg, "", "pw"), "registry: user must not be empty") { ok = false; }
  if !int_err_is(registry_login(&mut reg, "u", ""), "registry: password must not be empty") { ok = false; }
  if registry_logged_in(&reg) { ok = false; }
  if !int_err_is(registry_logout(&mut reg), "registry: not logged in") { ok = false; }
  if !int_ok_is(registry_login(&mut reg, "alice", "secret"), 1) { ok = false; }
  if !registry_logged_in(&reg) { ok = false; }
  if !streq(registry_user(&reg), "alice") { ok = false; }
  if !int_ok_is(registry_login(&mut reg, "bob", "secret"), 2) { ok = false; }
  if !streq(registry_user(&reg), "bob") { ok = false; }
  if !int_ok_is(registry_logout(&mut reg), 1) { ok = false; }
  if registry_logged_in(&reg) { ok = false; }
  if registry_login_count(&reg) != 2 { ok = false; }
  if registry_logout_count(&reg) != 1 { ok = false; }
  return assert(ok, "login/logout validation and counters");
}

fn t15() -> TestResult {
  var reg = reg_of(registry_new("docker.io"));
  let p = plan_of(registry_plan_pull(&reg, "nginx:1.25"));
  var ok = plan_op(&p) == DOCKER_PLAN_PULL;
  if !streq(plan_operation_name(plan_op(&p)), "pull") { ok = false; }
  if plan_needs_auth(&p) { ok = false; }
  if plan_step_count(&p) != 3 { ok = false; }
  if !step_is(&p, 0, "resolve manifest") { ok = false; }
  if !step_is(&p, 1, "fetch config") { ok = false; }
  if !step_is(&p, 2, "fetch layers") { ok = false; }
  if !streq(plan_tag(&p), "1.25") { ok = false; }
  if !streq(plan_digest(&p), "") { ok = false; }
  if !plan_err_is(registry_plan_pull(&reg, ""), "image: empty reference") { ok = false; }
  return assert(ok, "pull plan needs no login and lists three steps");
}

fn t16() -> TestResult {
  var reg = reg_of(registry_new("ghcr.io"));
  var ok = plan_err_is(registry_plan_push(&reg, "acme/tool:1"), "registry: login required for push");
  if !int_ok_is(registry_login(&mut reg, "alice", "secret"), 1) { ok = false; }
  if !plan_err_is(registry_plan_push(&reg, "acme/tool@" + DIGEST_A), "registry: push requires a tag") { ok = false; }
  if !plan_err_is(registry_plan_push(&reg, "bad ref"), "image: invalid repository") { ok = false; }
  return assert(ok, "push requires login and a tagged reference");
}

fn t17() -> TestResult {
  var reg = reg_of(registry_new("ghcr.io"));
  var ok = int_ok_is(registry_login(&mut reg, "alice", "secret"), 1);
  let p = plan_of(registry_plan_push(&reg, "ghcr.io/acme/tool:v2"));
  if plan_op(&p) != DOCKER_PLAN_PUSH { ok = false; }
  if !streq(plan_operation_name(plan_op(&p)), "push") { ok = false; }
  if !plan_needs_auth(&p) { ok = false; }
  if plan_step_count(&p) != 4 { ok = false; }
  if !step_is(&p, 0, "authenticate") { ok = false; }
  if !step_is(&p, 3, "push manifest") { ok = false; }
  if !streq(plan_registry(&p), "ghcr.io") { ok = false; }
  if !streq(plan_repository(&p), "acme/tool") { ok = false; }
  if !streq(plan_tag(&p), "v2") { ok = false; }
  return assert(ok, "push plan records auth, reference parts and four steps");
}

// --------------------------------------------------
//  Compose model
// --------------------------------------------------

fn t18() -> TestResult {
  var c = compose_new();
  var ok = int_ok_is(compose_add_service(&mut c, "web", "nginx:1.25"), 0);
  if !int_ok_is(compose_add_service(&mut c, "db", "postgres:16"), 1) { ok = false; }
  if compose_service_count(&c) != 2 { ok = false; }
  if compose_service_index(&c, "db") != 1 { ok = false; }
  if !streq(compose_service_name(&c, 0), "web") { ok = false; }
  if !streq(compose_service_image(&c, 1), "postgres:16") { ok = false; }
  if compose_service_replicas(&c, 0) != 1 { ok = false; }
  if !int_ok_is(compose_set_replicas(&mut c, 0, 3), 3) { ok = false; }
  if compose_service_replicas(&c, 0) != 3 { ok = false; }
  if !int_err_is(compose_set_replicas(&mut c, 0, 0), "compose: replicas must be >= 1") { ok = false; }
  if !int_err_is(compose_set_replicas(&mut c, 9, 1), "compose: unknown service") { ok = false; }
  if !int_err_is(compose_add_service(&mut c, "web", "nginx:1.25"), "compose: duplicate service name") { ok = false; }
  if !int_err_is(compose_add_service(&mut c, "", "nginx:1.25"), "compose: service name must not be empty") { ok = false; }
  if !int_err_is(compose_add_service(&mut c, "x", "bad ref"), "image: invalid repository") { ok = false; }
  return assert(ok, "compose services, replicas and validation");
}

fn t19() -> TestResult {
  var c = compose_new();
  var ok = int_ok_is(compose_add_service(&mut c, "web", "nginx:1.25"), 0);
  if !int_ok_is(compose_add_service(&mut c, "db", "postgres:16"), 1) { ok = false; }
  if !int_ok_is(compose_add_dep(&mut c, 0, 1), 1) { ok = false; }
  if compose_dep_count(&c, 0) != 1 { ok = false; }
  if compose_dep_at(&c, 0, 0) != 1 { ok = false; }
  if !compose_depends_on(&c, 0, 1) { ok = false; }
  if compose_depends_on(&c, 1, 0) { ok = false; }
  if compose_dep_count(&c, 9) != DOCKER_NOT_FOUND { ok = false; }
  if !int_err_is(compose_add_dep(&mut c, 0, 1), "compose: duplicate dependency") { ok = false; }
  if !int_err_is(compose_add_dep(&mut c, 0, 0), "compose: service cannot depend on itself") { ok = false; }
  if !int_err_is(compose_add_dep(&mut c, 0, 7), "compose: unknown service") { ok = false; }
  return assert(ok, "dependency edges record direction and reject duplicates");
}

fn t20() -> TestResult {
  var c = compose_new();
  var ok = int_ok_is(compose_add_service(&mut c, "a", "alpine:3.19"), 0);
  if !int_ok_is(compose_add_service(&mut c, "b", "alpine:3.19"), 1) { ok = false; }
  if !int_ok_is(compose_add_service(&mut c, "c", "alpine:3.19"), 2) { ok = false; }
  if !int_ok_is(compose_add_dep(&mut c, 1, 0), 1) { ok = false; }
  if !int_ok_is(compose_add_dep(&mut c, 2, 1), 2) { ok = false; }
  let v = order_of(compose_topo_order(&c));
  if v.len() != 3 { ok = false; }
  let v0: Int = v[0];
  let v1: Int = v[1];
  let v2: Int = v[2];
  if v0 != 0 || v1 != 1 || v2 != 2 { ok = false; }
  if !streq(compose_order_text(&c), "a,b,c") { ok = false; }
  if compose_has_cycle(&c) { ok = false; }
  return assert(ok, "chain dependencies yield the deterministic start order");
}

fn t21() -> TestResult {
  var c = compose_new();
  var ok = int_ok_is(compose_add_service(&mut c, "a", "alpine:3.19"), 0);
  if !int_ok_is(compose_add_service(&mut c, "b", "alpine:3.19"), 1) { ok = false; }
  if !int_ok_is(compose_add_service(&mut c, "c", "alpine:3.19"), 2) { ok = false; }
  if !int_ok_is(compose_add_service(&mut c, "d", "alpine:3.19"), 3) { ok = false; }
  if !int_ok_is(compose_add_dep(&mut c, 3, 1), 1) { ok = false; }
  if !int_ok_is(compose_add_dep(&mut c, 3, 2), 2) { ok = false; }
  if !int_ok_is(compose_add_dep(&mut c, 1, 0), 3) { ok = false; }
  if !int_ok_is(compose_add_dep(&mut c, 2, 0), 4) { ok = false; }
  let v = order_of(compose_topo_order(&c));
  var ok2 = v.len() == 4;
  if ok2 {
    let v0: Int = v[0];
    let v1: Int = v[1];
    let v2: Int = v[2];
    let v3: Int = v[3];
    if v0 != 0 || v1 != 1 || v2 != 2 || v3 != 3 { ok2 = false; }
  }
  if !ok2 { ok = false; }
  if !streq(compose_order_text(&c), "a,b,c,d") { ok = false; }
  return assert(ok, "diamond dependencies order by smallest ready index");
}

fn t22() -> TestResult {
  var c = compose_new();
  var ok = int_ok_is(compose_add_service(&mut c, "a", "alpine:3.19"), 0);
  if !int_ok_is(compose_add_service(&mut c, "b", "alpine:3.19"), 1) { ok = false; }
  if !int_ok_is(compose_add_service(&mut c, "c", "alpine:3.19"), 2) { ok = false; }
  if !int_ok_is(compose_add_dep(&mut c, 1, 0), 1) { ok = false; }
  if !int_ok_is(compose_add_dep(&mut c, 2, 1), 2) { ok = false; }
  if !int_ok_is(compose_add_dep(&mut c, 0, 2), 3) { ok = false; }
  if !compose_has_cycle(&c) { ok = false; }
  if !order_err_is(compose_topo_order(&c), "compose: dependency cycle") { ok = false; }
  if !streq(compose_order_text(&c), "cycle") { ok = false; }
  if compose_dep_count(&c, 0) != 1 { ok = false; }
  return assert(ok, "cycle-closing edge is detected by topo order and has_cycle");
}

fn t23() -> TestResult {
  var c = compose_new();
  var ok = int_ok_is(compose_add_service(&mut c, "web", "nginx:1.25"), 0);
  if !int_ok_is(compose_attach_network(&mut c, 0, "front"), 1) { ok = false; }
  if !int_ok_is(compose_attach_network(&mut c, 0, "back"), 2) { ok = false; }
  if compose_network_count(&c, 0) != 2 { ok = false; }
  if !streq(compose_network_at(&c, 0, 0), "front") { ok = false; }
  if !streq(compose_network_at(&c, 0, 1), "back") { ok = false; }
  if !streq(compose_network_at(&c, 0, 2), "") { ok = false; }
  if !int_err_is(compose_attach_network(&mut c, 0, "front"), "compose: duplicate network") { ok = false; }
  if !int_err_is(compose_attach_network(&mut c, 0, ""), "compose: network name must not be empty") { ok = false; }
  if !int_err_is(compose_attach_network(&mut c, 9, "x"), "compose: unknown service") { ok = false; }
  if !int_ok_is(compose_attach_volume(&mut c, 0, "data"), 1) { ok = false; }
  if compose_volume_count(&c, 0) != 1 { ok = false; }
  if !streq(compose_volume_at(&c, 0, 0), "data") { ok = false; }
  if !int_err_is(compose_attach_volume(&mut c, 0, "data"), "compose: duplicate volume") { ok = false; }
  return assert(ok, "compose network and volume references stay parallel");
}

// --------------------------------------------------
//  Volumes and networks
// --------------------------------------------------

fn t24() -> TestResult {
  var r = resources_new();
  var ok = int_ok_is(resources_add_volume(&mut r, "v1", "local"), 0);
  if !int_ok_is(resources_add_volume(&mut r, "v2", "nfs"), 1) { ok = false; }
  if resources_volume_count(&r) != 2 { ok = false; }
  if resources_volume_total(&r) != 2 { ok = false; }
  if !streq(resources_volume_name(&r, 0), "v1") { ok = false; }
  if !streq(resources_volume_driver(&r, 1), "nfs") { ok = false; }
  if !resources_volume_exists(&r, "v1") { ok = false; }
  if !int_err_is(resources_add_volume(&mut r, "v1", "local"), "volume: duplicate name") { ok = false; }
  if !int_err_is(resources_add_volume(&mut r, "", "local"), "volume: name must not be empty") { ok = false; }
  if !int_err_is(resources_add_volume(&mut r, "v3", ""), "volume: driver must not be empty") { ok = false; }
  if !int_ok_is(resources_remove_volume(&mut r, "v1"), 1) { ok = false; }
  if resources_volume_exists(&r, "v1") { ok = false; }
  if !resources_volume_removed(&r, "v1") { ok = false; }
  if resources_volume_count(&r) != 1 { ok = false; }
  if resources_volume_total(&r) != 2 { ok = false; }
  if !streq(resources_volume_name(&r, 0), "v1") { ok = false; }
  if !int_err_is(resources_remove_volume(&mut r, "v1"), "volume: already removed") { ok = false; }
  if !int_err_is(resources_remove_volume(&mut r, "nope"), "volume: not found") { ok = false; }
  return assert(ok, "volume set lifecycle, stable names and live counts");
}

fn t25() -> TestResult {
  var r = resources_new();
  var ok = int_ok_is(resources_add_network(&mut r, "front", "bridge"), 0);
  if !int_ok_is(resources_add_network(&mut r, "back", "overlay"), 1) { ok = false; }
  if resources_network_count(&r) != 2 { ok = false; }
  if !streq(resources_network_name(&r, 1), "back") { ok = false; }
  if !streq(resources_network_driver(&r, 1), "overlay") { ok = false; }
  if !int_err_is(resources_add_network(&mut r, "front", "bridge"), "network: duplicate name") { ok = false; }
  if !int_err_is(resources_add_network(&mut r, "", "bridge"), "network: name must not be empty") { ok = false; }
  if !int_ok_is(resources_remove_network(&mut r, "front"), 1) { ok = false; }
  if resources_network_exists(&r, "front") { ok = false; }
  if resources_network_count(&r) != 1 { ok = false; }
  if !int_err_is(resources_remove_network(&mut r, "front"), "network: already removed") { ok = false; }
  if !int_err_is(resources_remove_network(&mut r, "ghost"), "network: not found") { ok = false; }
  return assert(ok, "network set lifecycle mirrors volumes");
}

fn t26() -> TestResult {
  var a = compose_new();
  var ok = int_ok_is(compose_add_service(&mut a, "web", "nginx:1.25"), 0);
  if !int_ok_is(compose_add_service(&mut a, "db", "postgres:16"), 1) { ok = false; }
  if !int_ok_is(compose_add_dep(&mut a, 0, 1), 1) { ok = false; }
  let ta = compose_order_text(&a);
  var b = compose_new();
  if !int_ok_is(compose_add_service(&mut b, "web", "nginx:1.25"), 0) { ok = false; }
  if !int_ok_is(compose_add_service(&mut b, "db", "postgres:16"), 1) { ok = false; }
  if !int_ok_is(compose_add_dep(&mut b, 0, 1), 1) { ok = false; }
  if !streq(ta, compose_order_text(&b)) { ok = false; }
  let ra = ref_of(image_ref_parse("ghcr.io/acme/tool:v2@" + DIGEST_A));
  let rb = ref_of(image_ref_parse("ghcr.io/acme/tool:v2@" + DIGEST_A));
  if !streq(image_ref_render(&ra), image_ref_render(&rb)) { ok = false; }
  if !streq(docker_image_layer_at(&image_of(docker_image_new("alpine:3.19")), 0), "") { ok = false; }
  return assert(ok, "identical inputs produce identical outputs");
}

fn main() -> Int {
  io.println("=== xiom.docker conformance tests ===");
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
    io.println("xiom.docker: all tests passed");
  } else {
    io.println("xiom.docker: tests failed");
  }
  return failed;
}
