// XIOM -- xiom.jev conformance tests (offline deterministic fixtures)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Everything here is offline and deterministic: canned request shapes are
// built and compared byte-for-byte against the exact JSON pinned in the
// public TypeSafe documentation (docs.typesafe.ai quickstart, primitives
// choice/score/noul, confidence, patterns fan-out) and the OpenAPI schema at
// https://api.typesafe.ai/openapi.json; canned responses are parsed and
// every probability/confidence/noul is checked in micro units. There is NO
// network, NO API key and NO randomness: selection is exercised with
// hand-supplied entropy values only.
//
// The transport module (xiom.jev.client) is deliberately NOT imported here:
// it links the libcurl bridge (see the package README, "Live probe"), so the
// suite stays link-free. Its offline-composed pieces (endpoint composition
// in xiom.jev, api_error_detail in xiom.jev.response) are covered below; the
// client itself is covered by tests/probe_live.xi and `xiom --check`.
//
// Harness style mirrors xiom.llm/xiom.gguf: one fn tN() -> Int per check,
// called directly from main; main prints [PASS]/[FAIL] and returns the
// failure count. Str payloads are compared with str_compare and every
// Vec/Result field read is bound to a typed local first.

module jev_tests

use xiom.io;
use xiom.string;
use xiom.string.compare;
use xiom.convert;
use xiom.convert.tostring;
use xiom.encoding;
use xiom.compress.gzip;
use xiom.serialize.json;
use xiom.jev;
use xiom.jev.compression;
use xiom.jev.errors;
use xiom.jev.types;
use xiom.jev.request;
use xiom.jev.response;
use xiom.jev.retry;
use xiom.jev.selection;

// --------------------------------------------------
//  Harness helpers
// --------------------------------------------------

fn report(passed: Bool, name: Str) -> Int {
  if passed {
    io.println("  [PASS] " + name);
    return 0;
  }
  io.println("  [FAIL] " + name);
  return 1;
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// jv parses a JSON literal into a JsonValue for the structured-instruction
// fixtures (callers pass known-good literals; json_null on a malformed one so
// a regression shows up as a byte mismatch, never a crash).
fn jv(s: Str) -> JsonValue {
  let r: Result[JsonValue, Str] = json.json_parse(s);
  if !r.is_ok { return json.json_null(); }
  let v: JsonValue = r.value;
  return v;
}

fn expect_bad(r: Result[Str, JevError], want: Str, name: Str) -> Int {
  match r {
    Ok(_v) => {
      return report(false, name + " (expected BadRequest, got Ok)");
    },
    Err(e) => {
      let got: Str = errors.jev_error_text(e);
      let want_full: Str = "jev: bad request: " + want;
      if !str_eq(got, want_full) {
        return report(false, name + " (got: " + got + ")");
      }
      return report(true, name);
    },
  };
}

// expect_bad_int is expect_bad for a Result carrying an Int payload (the
// body-size rule).
fn expect_bad_int(r: Result[Int, JevError], want: Str, name: Str) -> Int {
  match r {
    Ok(_v) => {
      return report(false, name + " (expected BadRequest, got Ok)");
    },
    Err(e) => {
      let got: Str = errors.jev_error_text(e);
      let want_full: Str = "jev: bad request: " + want;
      if !str_eq(got, want_full) {
        return report(false, name + " (got: " + got + ")");
      }
      return report(true, name);
    },
  };
}

// expect_bad_bytes is expect_bad for a Result carrying an encoded byte buffer.
fn expect_bad_bytes(r: Result[Vec[UInt8], JevError], want: Str, name: Str) -> Int {
  match r {
    Ok(_v) => {
      return report(false, name + " (expected BadRequest, got Ok)");
    },
    Err(e) => {
      let got: Str = errors.jev_error_text(e);
      let want_full: Str = "jev: bad request: " + want;
      if !str_eq(got, want_full) {
        return report(false, name + " (got: " + got + ")");
      }
      return report(true, name);
    },
  };
}

fn expect_ok_int(r: Result[Int, JevError], want: Int, name: Str) -> Int {
  match r {
    Ok(v) => {
      if v != want {
        return report(false, name + " (got " + convert.to_string(v) + ", want " + convert.to_string(want) + ")");
      }
      return report(true, name);
    },
    Err(e) => {
      let got: Str = errors.jev_error_text(e);
      return report(false, name + " (got error: " + got + ")");
    },
  };
}

fn bytes_eq(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() { return false; }
  var i: Int = 0;
  while i < a.len() {
    if a[i] != b[i] { return false; }
    i = i + 1;
  }
  return true;
}

fn expect_parse(r: Result[Response, JevError], want: Str, name: Str) -> Int {
  match r {
    Ok(_v) => {
      return report(false, name + " (expected Parse, got Ok)");
    },
    Err(e) => {
      let got: Str = errors.jev_error_text(e);
      let want_full: Str = "jev: parse: " + want;
      if !str_eq(got, want_full) {
        return report(false, name + " (got: " + got + ")");
      }
      return report(true, name);
    },
  };
}

// triage_questions is the docs quickstart question set (department Choice,
// frustration Score, is_urgent Noul) rebuilt in test code.
fn triage_questions() -> Vec[Question] {
  var qs: Vec[Question] = Vec[Question].new();
  var d: Question = types.question_choice("department", "Which team should handle this");
  types.question_add_option(&mut d, "billing", "Payment or subscription issues");
  types.question_add_option(&mut d, "technical", "Bugs or integration problems");
  types.question_add_option(&mut d, "sales", "Pricing or account questions");
  qs.push(d);
  var f: Question = types.question_score("frustration", "How frustrated the customer appears");
  types.question_add_level(&mut f, "Calm, just stating facts");
  types.question_add_level(&mut f, "Frustrated but civil");
  types.question_add_level(&mut f, "Very angry, strong language");
  qs.push(f);
  var u: Question = types.question_noul("is_urgent", "The message conveys urgency or time-sensitivity");
  qs.push(u);
  return qs;
}

// --------------------------------------------------
//  Request builder fixtures (exact bytes)
// --------------------------------------------------

fn t1() -> Int {
  var qs: Vec[Question] = Vec[Question].new();
  var q: Question = types.question_choice("department", "Which team should handle this?");
  types.question_add_option(&mut q, "returns", "Exchanges, wrong or damaged items");
  types.question_add_option(&mut q, "shipping", "Delivery status, delays, lost packages");
  types.question_add_option(&mut q, "billing", "Charges, invoices, payment problems");
  qs.push(q);
  let state: State = types.state_text("My running shoes arrived in the wrong size. Can I swap them for a size 10?");
  let built: Result[Str, JevError] = request.build_request("jev-latest", state, qs);
  if !built.is_ok { return report(false, "docs choice request builds"); }
  let got: Str = built.value;
  let want: Str = "{\"state\":\"My running shoes arrived in the wrong size. Can I swap them for a size 10?\",\"model\":\"jev-latest\",\"questions\":{\"department\":{\"type\":\"choice\",\"instructions\":\"Which team should handle this?\",\"criteria\":{\"returns\":\"Exchanges, wrong or damaged items\",\"shipping\":\"Delivery status, delays, lost packages\",\"billing\":\"Charges, invoices, payment problems\"}}}}";
  return report(str_eq(got, want), "docs choice request byte-exact");
}

fn t2() -> Int {
  let state: State = types.state_text("Our API integration started returning 500 errors on every request about 20 minutes ago, and we can't process any customer orders until this is fixed.");
  let built: Result[Str, JevError] = request.build_request("jev-latest", state, triage_questions());
  if !built.is_ok { return report(false, "docs quickstart mixed request builds"); }
  let got: Str = built.value;
  let want: Str = "{\"state\":\"Our API integration started returning 500 errors on every request about 20 minutes ago, and we can't process any customer orders until this is fixed.\",\"model\":\"jev-latest\",\"questions\":{\"department\":{\"type\":\"choice\",\"instructions\":\"Which team should handle this\",\"criteria\":{\"billing\":\"Payment or subscription issues\",\"technical\":\"Bugs or integration problems\",\"sales\":\"Pricing or account questions\"}},\"frustration\":{\"type\":\"score\",\"instructions\":\"How frustrated the customer appears\",\"criteria\":[\"Calm, just stating facts\",\"Frustrated but civil\",\"Very angry, strong language\"]},\"is_urgent\":{\"type\":\"noul\",\"instructions\":\"The message conveys urgency or time-sensitivity\"}}}";
  return report(str_eq(got, want), "docs quickstart mixed request byte-exact");
}

fn t3() -> Int {
  var qs: Vec[Question] = Vec[Question].new();
  var q: Question = types.question_noul("escalate", "Should this page a human immediately?");
  types.question_set_noul_criteria(&mut q, "Explicitly time-sensitive", "No urgency expressed");
  qs.push(q);
  let state: State = types.state_text("deploy failed twice in a row");
  let built: Result[Str, JevError] = request.build_request("jev-latest", state, qs);
  if !built.is_ok { return report(false, "noul criteria request builds"); }
  let got: Str = built.value;
  let want: Str = "{\"state\":\"deploy failed twice in a row\",\"model\":\"jev-latest\",\"questions\":{\"escalate\":{\"type\":\"noul\",\"instructions\":\"Should this page a human immediately?\",\"criteria\":{\"true\":\"Explicitly time-sensitive\",\"false\":\"No urgency expressed\"}}}}";
  if !str_eq(got, want) {
    return report(false, "noul true/false criteria request byte-exact (got: " + got + ")");
  }
  var qs2: Vec[Question] = Vec[Question].new();
  var c: Question = types.question_choice("q", "pick");
  types.question_add_option(&mut c, "a", "");
  types.question_add_option(&mut c, "b", "desc");
  qs2.push(c);
  let state2: State = types.state_text("x");
  let built2: Result[Str, JevError] = request.build_request("m", state2, qs2);
  if !built2.is_ok { return report(false, "null-description choice builds"); }
  let got2: Str = built2.value;
  let want2: Str = "{\"state\":\"x\",\"model\":\"m\",\"questions\":{\"q\":{\"type\":\"choice\",\"instructions\":\"pick\",\"criteria\":{\"a\":null,\"b\":\"desc\"}}}}";
  return report(str_eq(got2, want2), "empty option description emitted as null");
}

fn t4() -> Int {
  let doc: Result[JsonValue, Str] = json.json_parse("{\"message\":\"help!\",\"subject\":\"double charge\"}");
  if !doc.is_ok { return report(false, "json state fixture parses"); }
  let state: State = types.state_json(doc.value);
  var qs: Vec[Question] = Vec[Question].new();
  var q: Question = types.question_noul("billing", "Is this about billing?");
  qs.push(q);
  let built: Result[Str, JevError] = request.build_request("jev-latest", state, qs);
  if !built.is_ok { return report(false, "json-state request builds"); }
  let got: Str = built.value;
  let want: Str = "{\"state\":{\"message\":\"help!\",\"subject\":\"double charge\"},\"model\":\"jev-latest\",\"questions\":{\"billing\":{\"type\":\"noul\",\"instructions\":\"Is this about billing?\"}}}";
  return report(str_eq(got, want), "json-state request byte-exact");
}

// --------------------------------------------------
//  Request validation (typed BadRequest catalog)
// --------------------------------------------------

fn t5() -> Int {
  var failed: Int = 0;
  var qs: Vec[Question] = Vec[Question].new();
  var q: Question = types.question_noul("q", "Is it?");
  qs.push(q);
  failed = failed + expect_bad(request.build_request("", types.state_text("x"), qs), "request: model is empty", "empty model rejected");
  failed = failed + expect_bad(request.build_request("m", types.state_text(""), qs), "request: state is empty", "empty text state rejected");
  var none: Vec[Question] = Vec[Question].new();
  failed = failed + expect_bad(request.build_request("m", types.state_text("x"), none), "request: no questions", "empty question list rejected");
  var empty_id: Vec[Question] = Vec[Question].new();
  empty_id.push(types.question_noul("", "Is it?"));
  failed = failed + expect_bad(request.build_request("m", types.state_text("x"), empty_id), "request: question 0: id is empty", "empty question id rejected");
  var dup: Vec[Question] = Vec[Question].new();
  dup.push(types.question_noul("q", "one?"));
  dup.push(types.question_noul("q", "two?"));
  failed = failed + expect_bad(request.build_request("m", types.state_text("x"), dup), "request: duplicate question id 'q'", "duplicate question id rejected");
  var noins: Vec[Question] = Vec[Question].new();
  noins.push(types.question_noul("q", ""));
  failed = failed + expect_bad(request.build_request("m", types.state_text("x"), noins), "request: question 'q': instructions is empty", "empty instructions rejected");
  var noopt: Vec[Question] = Vec[Question].new();
  noopt.push(types.question_choice("q", "pick"));
  failed = failed + expect_bad(request.build_request("m", types.state_text("x"), noopt), "request: question 'q': choice needs at least one option", "choice without options rejected");
  var badlabel: Vec[Question] = Vec[Question].new();
  var bq: Question = types.question_choice("q", "pick");
  types.question_add_option(&mut bq, "", "desc");
  badlabel.push(bq);
  failed = failed + expect_bad(request.build_request("m", types.state_text("x"), badlabel), "request: question 'q': choice option 0: label is empty", "empty option label rejected");
  var onelevel: Vec[Question] = Vec[Question].new();
  var sq: Question = types.question_score("q", "rate");
  types.question_add_level(&mut sq, "only");
  onelevel.push(sq);
  failed = failed + expect_bad(request.build_request("m", types.state_text("x"), onelevel), "request: question 'q': score needs at least 2 levels", "one-level score rejected");
  var badlevel: Vec[Question] = Vec[Question].new();
  var sq2: Question = types.question_score("q", "rate");
  types.question_add_level(&mut sq2, "a");
  types.question_add_level(&mut sq2, "");
  badlevel.push(sq2);
  failed = failed + expect_bad(request.build_request("m", types.state_text("x"), badlevel), "request: question 'q': score level 1: description is empty", "empty score level rejected");
  var badkind: Vec[Question] = Vec[Question].new();
  badkind.push(Question{ kind: 9, id: "q", instructions: "x", labels: Vec[Str].new(), texts: Vec[Str].new(), noul_yes: "", noul_no: "", instructions_doc: json.json_null(), criterion_docs: Vec[JsonValue].new(), noul_yes_doc: json.json_null(), noul_no_doc: json.json_null() });
  failed = failed + expect_bad(request.build_request("m", types.state_text("x"), badkind), "request: question 'q': unknown question kind", "unknown question kind rejected");
  return report(failed == 0, "request BadRequest catalog (11 cases)");
}

fn t6() -> Int {
  var failed: Int = 0;
  var big: Vec[Question] = Vec[Question].new();
  var bq: Question = types.question_choice("q", "pick");
  var i: Int = 0;
  while i < 256 {
    types.question_add_option(&mut bq, "opt" + convert.to_string(i), "");
    i = i + 1;
  }
  big.push(bq);
  failed = failed + expect_bad(request.build_request("m", types.state_text("x"), big), "request: question 'q': choice has more than 255 options", "256 choice options rejected");
  var wide: Vec[Question] = Vec[Question].new();
  var sq: Question = types.question_score("q", "rate");
  i = 0;
  while i < 11 {
    types.question_add_level(&mut sq, "level" + convert.to_string(i));
    i = i + 1;
  }
  wide.push(sq);
  failed = failed + expect_bad(request.build_request("m", types.state_text("x"), wide), "request: question 'q': score has more than 10 levels", "11 score levels rejected");
  return report(failed == 0, "request size limits (255 options / 10 levels)");
}

// --------------------------------------------------
//  Response parsing fixtures
// --------------------------------------------------

fn t7() -> Int {
  let body: Str = "{\"model\":\"jev-1.13.0\",\"answers\":{\"department\":{\"type\":\"choice\",\"choice\":\"returns\",\"confidence\":1.0,\"probabilities\":{\"shipping\":0.0,\"returns\":1.0,\"billing\":0.0}}},\"usage\":{\"input_tokens\":328,\"output_tokens\":34}}";
  let r: Result[Response, JevError] = response.parse_response(body);
  if !r.is_ok { return report(false, "docs choice response parses"); }
  let resp: Response = r.value;
  var ok: Bool = true;
  if types.response_count(&resp) != 1 { ok = false; }
  if !str_eq(types.response_model(&resp), "jev-1.13.0") { ok = false; }
  if !str_eq(types.response_id(&resp, 0), "department") { ok = false; }
  if types.response_kind(&resp, 0) != types.KIND_CHOICE { ok = false; }
  if !str_eq(types.response_choice(&resp, 0), "returns") { ok = false; }
  if types.response_confidence_micro(&resp, 0) != 1000000 { ok = false; }
  if types.response_prob_count(&resp, 0) != 3 { ok = false; }
  if !str_eq(types.response_prob_label(&resp, 0, 0), "shipping") { ok = false; }
  if types.response_prob_micro(&resp, 0, 0) != 0 { ok = false; }
  if types.response_prob_micro(&resp, 0, 1) != 1000000 { ok = false; }
  if types.response_prob_micro(&resp, 0, 2) != 0 { ok = false; }
  if types.response_prob_find(&resp, 0, "returns") != 1 { ok = false; }
  if types.response_prob_total_micro(&resp, 0) != 1000000 { ok = false; }
  if types.response_has_usage(&resp) != 1 { ok = false; }
  if types.response_input_tokens(&resp) != 328 { ok = false; }
  if types.response_output_tokens(&resp) != 34 { ok = false; }
  return report(ok, "docs choice response parses (micro units, wire order, usage)");
}

fn t8() -> Int {
  let body: Str = "{\"model\":\"jev-1.13.0\",\"answers\":{\"department\":{\"type\":\"choice\",\"choice\":\"returns\",\"confidence\":0.42,\"probabilities\":{\"shipping\":0.04,\"billing\":0.35,\"returns\":0.61}},\"return_reason\":{\"type\":\"choice\",\"choice\":\"wrong_size\",\"confidence\":1.0,\"probabilities\":{\"other\":0.0,\"wrong_size\":1.0,\"changed_mind\":0.0,\"damaged\":0.0,\"wrong_item\":0.0}},\"shipping_issue\":{\"type\":\"choice\",\"choice\":\"delayed\",\"confidence\":0.67,\"probabilities\":{\"wrong_address\":0.0,\"other\":0.26,\"not_delivered\":0.0,\"damaged_in_transit\":0.0,\"delayed\":0.74}},\"requested_resolution\":{\"type\":\"choice\",\"choice\":\"refund\",\"confidence\":0.2,\"probabilities\":{\"replacement\":0.34,\"refund\":0.4,\"information\":0.02,\"exchange\":0.24}},\"tone\":{\"type\":\"choice\",\"choice\":\"frustrated\",\"confidence\":0.76,\"probabilities\":{\"frustrated\":0.84,\"angry\":0.16,\"calm\":0.0}}},\"usage\":{\"input_tokens\":589,\"output_tokens\":212}}";
  let r: Result[Response, JevError] = response.parse_response(body);
  if !r.is_ok { return report(false, "docs fan-out response parses"); }
  let resp: Response = r.value;
  var ok: Bool = true;
  if types.response_count(&resp) != 5 { ok = false; }
  if types.response_find(&resp, "department") != 0 { ok = false; }
  if types.response_find(&resp, "return_reason") != 1 { ok = false; }
  if types.response_find(&resp, "shipping_issue") != 2 { ok = false; }
  if types.response_find(&resp, "requested_resolution") != 3 { ok = false; }
  if types.response_find(&resp, "tone") != 4 { ok = false; }
  if types.response_find(&resp, "absent") != -1 { ok = false; }
  if types.response_confidence_micro(&resp, 0) != 420000 { ok = false; }
  if types.response_prob_micro(&resp, 0, 0) != 40000 { ok = false; }
  if types.response_prob_micro(&resp, 0, 1) != 350000 { ok = false; }
  if types.response_prob_micro(&resp, 0, 2) != 610000 { ok = false; }
  if types.response_confidence_micro(&resp, 3) != 200000 { ok = false; }
  if !str_eq(types.response_choice(&resp, 3), "refund") { ok = false; }
  if types.response_prob_micro(&resp, 3, 0) != 340000 { ok = false; }
  if types.response_prob_micro(&resp, 3, 1) != 400000 { ok = false; }
  if types.response_prob_micro(&resp, 3, 2) != 20000 { ok = false; }
  if types.response_prob_micro(&resp, 3, 3) != 240000 { ok = false; }
  if types.response_confidence_micro(&resp, 4) != 760000 { ok = false; }
  if types.response_prob_micro(&resp, 4, 0) != 840000 { ok = false; }
  if types.response_confidence_micro(&resp, 1) != 1000000 { ok = false; }
  if types.response_prob_count(&resp, 1) != 5 { ok = false; }
  if types.response_confidence_micro(&resp, 2) != 670000 { ok = false; }
  if types.response_prob_micro(&resp, 2, 4) != 740000 { ok = false; }
  if types.response_input_tokens(&resp) != 589 { ok = false; }
  return report(ok, "docs five-question fan-out parses (order, confidences, micros)");
}

fn t9() -> Int {
  let body: Str = "{\"model\":\"jev-1.13.0\",\"answers\":{\"bug_severity\":{\"type\":\"score\",\"score\":1.43,\"confidence\":0.35,\"legend\":{\"0\":\"Cosmetic; no impact to functionality\",\"1\":\"Broken or degraded feature, but workaround exists\",\"2\":\"Blocking issue; no workaround exists\"},\"probabilities\":{\"0\":0.0,\"1\":0.57,\"2\":0.43}}},\"usage\":{\"input_tokens\":332,\"output_tokens\":18}}";
  let r: Result[Response, JevError] = response.parse_response(body);
  if !r.is_ok { return report(false, "docs score response parses"); }
  let resp: Response = r.value;
  var ok: Bool = true;
  if types.response_kind(&resp, 0) != types.KIND_SCORE { ok = false; }
  if types.response_score_micro(&resp, 0) != 1430000 { ok = false; }
  if types.response_confidence_micro(&resp, 0) != 350000 { ok = false; }
  if types.response_prob_count(&resp, 0) != 3 { ok = false; }
  if !str_eq(types.response_prob_label(&resp, 0, 1), "1") { ok = false; }
  if types.response_prob_micro(&resp, 0, 1) != 570000 { ok = false; }
  if types.response_prob_micro(&resp, 0, 2) != 430000 { ok = false; }
  if types.response_prob_total_micro(&resp, 0) != 1000000 { ok = false; }
  if selection.score_round_level(types.response_score_micro(&resp, 0)) != 1 { ok = false; }
  if selection.score_normalized_micro(types.response_score_micro(&resp, 0), 2) != 715000 { ok = false; }
  if selection.answer_argmax(&resp, 0) != 1 { ok = false; }
  return report(ok, "docs score response parses (1.43 -> micro, round, normalize)");
}

fn t10() -> Int {
  let body: Str = "{\"model\":\"jev-1.13.0\",\"answers\":{\"bug_severity\":{\"type\":\"score\",\"score\":1.09,\"confidence\":0.87,\"legend\":{\"0\":{\"what\":\"Cosmetic; no impact to functionality\",\"examples\":[\"typo in a label\",\"misaligned icon\"]},\"1\":{\"what\":\"Broken or degraded feature, but workaround exists\",\"examples\":[\"export fails in one browser but works in another\"]},\"2\":{\"what\":\"Blocking issue; no workaround exists\",\"examples\":[\"cannot log in\",\"data loss\"]}},\"probabilities\":{\"0\":0.0,\"1\":0.91,\"2\":0.09}}},\"usage\":{\"input_tokens\":379,\"output_tokens\":18}}";
  let r: Result[Response, JevError] = response.parse_response(body);
  if !r.is_ok { return report(false, "structured-legend score response parses"); }
  let resp: Response = r.value;
  var ok: Bool = true;
  if types.response_score_micro(&resp, 0) != 1090000 { ok = false; }
  if types.response_confidence_micro(&resp, 0) != 870000 { ok = false; }
  if types.response_prob_micro(&resp, 0, 1) != 910000 { ok = false; }
  if types.response_prob_micro(&resp, 0, 2) != 90000 { ok = false; }
  return report(ok, "structured (object) legend score response parses");
}

fn t11() -> Int {
  let body: Str = "{\"model\":\"jev-1.13.0\",\"answers\":{\"is_human_escalation\":{\"type\":\"noul\",\"noul\":0.99},\"is_repeat_contact\":{\"type\":\"noul\",\"noul\":0.93}},\"usage\":{\"input_tokens\":360,\"output_tokens\":39}}";
  let r: Result[Response, JevError] = response.parse_response(body);
  if !r.is_ok { return report(false, "docs noul response parses"); }
  let resp: Response = r.value;
  var ok: Bool = true;
  if types.response_count(&resp) != 2 { ok = false; }
  if types.response_kind(&resp, 0) != types.KIND_NOUL { ok = false; }
  if types.response_noul_micro(&resp, 0) != 990000 { ok = false; }
  if types.response_noul_micro(&resp, 1) != 930000 { ok = false; }
  if types.response_confidence_micro(&resp, 0) != -1 { ok = false; }
  if types.response_prob_count(&resp, 0) != 0 { ok = false; }
  if types.response_score_micro(&resp, 0) != 0 { ok = false; }
  if selection.noul_yes(990000, 900000) != 1 { ok = false; }
  if selection.noul_yes(799999, 800000) != 0 { ok = false; }
  if selection.noul_yes(800000, 800000) != 1 { ok = false; }
  if selection.noul_confidence_micro(990000) != 980000 { ok = false; }
  if selection.noul_confidence_micro(500000) != 0 { ok = false; }
  return report(ok, "docs noul response parses (gating, no confidence, spread)");
}

fn t12() -> Int {
  let body: Str = "{\"model\":\"m\",\"answers\":{\"q\":{\"type\":\"noul\",\"noul\":0.5}}}";
  let r: Result[Response, JevError] = response.parse_response(body);
  if !r.is_ok { return report(false, "usage-less response parses"); }
  let resp: Response = r.value;
  var ok: Bool = true;
  if types.response_has_usage(&resp) != 0 { ok = false; }
  if types.response_input_tokens(&resp) != 0 { ok = false; }
  if types.response_output_tokens(&resp) != 0 { ok = false; }
  return report(ok, "missing usage object tolerated (has_usage 0)");
}

// --------------------------------------------------
//  Response validation (typed Parse catalog)
// --------------------------------------------------

fn t13() -> Int {
  var failed: Int = 0;
  failed = failed + expect_parse(response.parse_response("not json{"), "response: invalid JSON", "invalid JSON rejected");
  failed = failed + expect_parse(response.parse_response("[]"), "response: root is not an object", "non-object root rejected");
  failed = failed + expect_parse(response.parse_response("{}"), "response: missing model", "missing model rejected");
  failed = failed + expect_parse(response.parse_response("{\"model\":3,\"answers\":{}}"), "response: model is not a string", "non-string model rejected");
  failed = failed + expect_parse(response.parse_response("{\"model\":\"\",\"answers\":{}}"), "response: model is empty", "empty model rejected");
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\"}"), "response: missing answers", "missing answers rejected");
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\",\"answers\":{}}"), "response: answers is empty", "empty answers rejected");
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\",\"answers\":[]}"), "response: answers is not an object", "non-object answers rejected");
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\",\"answers\":{\"q\":{\"box\":{}}}}"), "response: answer 'q': missing type", "missing answer type rejected");
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\",\"answers\":{\"q\":{\"type\":\"box\"}}}"), "response: answer 'q': unknown answer type 'box'", "box answer type rejected (M1)");
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\",\"answers\":{\"q\":{\"type\":true,\"noul\":0.5}}}"), "response: answer 'q': type is not a string", "non-string answer type rejected");
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\",\"answers\":{\"q\":[]}}"), "response: answer 'q': not an object", "non-object answer rejected");
  return report(failed == 0, "response Parse catalog 1 (12 structural cases)");
}

fn t14() -> Int {
  var failed: Int = 0;
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\",\"answers\":{\"q\":{\"type\":\"choice\",\"probabilities\":{\"a\":1.0},\"confidence\":1.0}}}"), "response: answer 'q': missing choice", "choice: missing choice");
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\",\"answers\":{\"q\":{\"type\":\"choice\",\"choice\":7,\"probabilities\":{\"a\":1.0},\"confidence\":1.0}}}"), "response: answer 'q': choice is not a string", "choice: non-string choice");
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\",\"answers\":{\"q\":{\"type\":\"choice\",\"choice\":\"\",\"probabilities\":{\"a\":1.0},\"confidence\":1.0}}}"), "response: answer 'q': choice is empty", "choice: empty choice");
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\",\"answers\":{\"q\":{\"type\":\"choice\",\"choice\":\"a\",\"confidence\":1.0}}}"), "response: answer 'q': missing probabilities", "choice: missing probabilities");
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\",\"answers\":{\"q\":{\"type\":\"choice\",\"choice\":\"a\",\"probabilities\":[],\"confidence\":1.0}}}"), "response: answer 'q': probabilities is not an object", "choice: non-object probabilities");
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\",\"answers\":{\"q\":{\"type\":\"choice\",\"choice\":\"a\",\"probabilities\":{},\"confidence\":1.0}}}"), "response: answer 'q': probabilities is empty", "choice: empty probabilities");
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\",\"answers\":{\"q\":{\"type\":\"choice\",\"choice\":\"a\",\"probabilities\":{\"a\":\"x\"},\"confidence\":1.0}}}"), "response: answer 'q': probability 'a' is not a number", "choice: non-number probability");
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\",\"answers\":{\"q\":{\"type\":\"choice\",\"choice\":\"a\",\"probabilities\":{\"a\":1.5},\"confidence\":1.0}}}"), "response: answer 'q': probability 'a' out of range", "choice: out-of-range probability");
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\",\"answers\":{\"q\":{\"type\":\"choice\",\"choice\":\"a\",\"probabilities\":{\"a\":0.5,\"b\":0.3},\"confidence\":1.0}}}"), "response: answer 'q': probabilities sum out of tolerance", "choice: sum out of tolerance");
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\",\"answers\":{\"q\":{\"type\":\"choice\",\"choice\":\"b\",\"probabilities\":{\"a\":0.5,\"b\":0.3},\"confidence\":1.0}}}"), "response: answer 'q': choice 'b' is not the highest-probability option", "choice: not the argmax");
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\",\"answers\":{\"q\":{\"type\":\"choice\",\"choice\":\"zzz\",\"probabilities\":{\"a\":1.0},\"confidence\":1.0}}}"), "response: answer 'q': choice 'zzz' is not in probabilities", "choice: label absent from probabilities");
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\",\"answers\":{\"q\":{\"type\":\"choice\",\"choice\":\"a\",\"probabilities\":{\"a\":1.0}}}}"), "response: answer 'q': missing confidence", "choice: missing confidence");
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\",\"answers\":{\"q\":{\"type\":\"choice\",\"choice\":\"a\",\"probabilities\":{\"a\":1.0},\"confidence\":\"x\"}}}"), "response: answer 'q': confidence is not a number", "choice: non-number confidence");
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\",\"answers\":{\"q\":{\"type\":\"choice\",\"choice\":\"a\",\"probabilities\":{\"a\":1.0},\"confidence\":2.0}}}"), "response: answer 'q': confidence out of range", "choice: out-of-range confidence");
  return report(failed == 0, "response Parse catalog 2 (14 choice cases)");
}

fn t15() -> Int {
  var failed: Int = 0;
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\",\"answers\":{\"q\":{\"type\":\"score\",\"legend\":{\"0\":\"a\"},\"probabilities\":{\"0\":1.0},\"confidence\":1.0}}}"), "response: answer 'q': missing score", "score: missing score");
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\",\"answers\":{\"q\":{\"type\":\"score\",\"score\":\"x\",\"legend\":{\"0\":\"a\"},\"probabilities\":{\"0\":1.0},\"confidence\":1.0}}}"), "response: answer 'q': score is not a number", "score: non-number score");
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\",\"answers\":{\"q\":{\"type\":\"score\",\"score\":-0.5,\"legend\":{\"0\":\"a\"},\"probabilities\":{\"0\":1.0},\"confidence\":1.0}}}"), "response: answer 'q': score out of range", "score: negative score");
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\",\"answers\":{\"q\":{\"type\":\"score\",\"score\":10.5,\"legend\":{\"0\":\"a\"},\"probabilities\":{\"0\":1.0},\"confidence\":1.0}}}"), "response: answer 'q': score out of range", "score: score above 10");
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\",\"answers\":{\"q\":{\"type\":\"score\",\"score\":1.0,\"probabilities\":{\"0\":1.0},\"confidence\":1.0}}}"), "response: answer 'q': missing legend", "score: missing legend");
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\",\"answers\":{\"q\":{\"type\":\"score\",\"score\":1.0,\"legend\":[],\"probabilities\":{\"0\":1.0},\"confidence\":1.0}}}"), "response: answer 'q': legend is not an object", "score: non-object legend");
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\",\"answers\":{\"q\":{\"type\":\"score\",\"score\":1.0,\"legend\":{},\"probabilities\":{\"0\":1.0},\"confidence\":1.0}}}"), "response: answer 'q': legend is empty", "score: empty legend");
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\",\"answers\":{\"q\":{\"type\":\"score\",\"score\":1.0,\"legend\":{\"0\":\"a\"},\"probabilities\":{\"1\":1.0},\"confidence\":1.0}}}"), "response: answer 'q': probability '1' is not in legend", "score: probability key absent from legend");
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\",\"answers\":{\"q\":{\"type\":\"score\",\"score\":0.7,\"legend\":{\"0\":\"a\",\"1\":\"b\"},\"probabilities\":{\"0\":0.4,\"1\":0.3},\"confidence\":1.0}}}"), "response: answer 'q': probabilities sum out of tolerance", "score: sum out of tolerance");
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\",\"answers\":{\"q\":{\"type\":\"noul\"}}}"), "response: answer 'q': missing noul", "noul: missing noul");
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\",\"answers\":{\"q\":{\"type\":\"noul\",\"noul\":\"x\"}}}"), "response: answer 'q': noul is not a number", "noul: non-number noul");
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\",\"answers\":{\"q\":{\"type\":\"noul\",\"noul\":1.5}}}"), "response: answer 'q': noul out of range", "noul: noul above 1");
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\",\"answers\":{\"q\":{\"type\":\"noul\",\"noul\":-0.1}}}"), "response: answer 'q': noul out of range", "noul: negative noul");
  return report(failed == 0, "response Parse catalog 3 (13 score/noul cases)");
}

fn t16() -> Int {
  var failed: Int = 0;
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\",\"answers\":{\"q\":{\"type\":\"noul\",\"noul\":0.5}},\"usage\":[]}"), "response: usage is not an object", "usage non-object rejected");
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\",\"answers\":{\"q\":{\"type\":\"noul\",\"noul\":0.5}},\"usage\":{\"input_tokens\":\"x\"}}"), "response: usage.input_tokens is not a number", "usage: non-number input_tokens");
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\",\"answers\":{\"q\":{\"type\":\"noul\",\"noul\":0.5}},\"usage\":{\"input_tokens\":-1}}"), "response: usage.input_tokens out of range", "usage: negative input_tokens");
  failed = failed + expect_parse(response.parse_response("{\"model\":\"m\",\"answers\":{\"q\":{\"type\":\"noul\",\"noul\":0.5}},\"usage\":{\"output_tokens\":\"x\"}}"), "response: usage.output_tokens is not a number", "usage: non-number output_tokens");
  return report(failed == 0, "response Parse catalog 4 (usage, 4 cases)");
}

fn t17() -> Int {
  let body: Str = "{\"model\":\"m\",\"unexpected\":1,\"answers\":{\"q\":{\"type\":\"noul\",\"noul\":0.5,\"extra\":\"ignored\"}},\"usage\":{\"input_tokens\":1,\"output_tokens\":2,\"z\":9}}";
  let r: Result[Response, JevError] = response.parse_response(body);
  if !r.is_ok { return report(false, "forward-compatible body parses"); }
  let resp: Response = r.value;
  var ok: Bool = true;
  if types.response_count(&resp) != 1 { ok = false; }
  if types.response_noul_micro(&resp, 0) != 500000 { ok = false; }
  if types.response_input_tokens(&resp) != 1 { ok = false; }
  if types.response_output_tokens(&resp) != 2 { ok = false; }
  return report(ok, "unknown extra fields ignored (forward compatibility)");
}

// --------------------------------------------------
//  Selection helpers
// --------------------------------------------------

fn fan_out_response() -> Result[Response, JevError] {
  let body: Str = "{\"model\":\"jev-1.13.0\",\"answers\":{\"department\":{\"type\":\"choice\",\"choice\":\"returns\",\"confidence\":0.42,\"probabilities\":{\"shipping\":0.04,\"billing\":0.35,\"returns\":0.61}},\"return_reason\":{\"type\":\"choice\",\"choice\":\"wrong_size\",\"confidence\":1.0,\"probabilities\":{\"other\":0.0,\"wrong_size\":1.0,\"changed_mind\":0.0,\"damaged\":0.0,\"wrong_item\":0.0}},\"shipping_issue\":{\"type\":\"choice\",\"choice\":\"delayed\",\"confidence\":0.67,\"probabilities\":{\"wrong_address\":0.0,\"other\":0.26,\"not_delivered\":0.0,\"damaged_in_transit\":0.0,\"delayed\":0.74}},\"requested_resolution\":{\"type\":\"choice\",\"choice\":\"refund\",\"confidence\":0.2,\"probabilities\":{\"replacement\":0.34,\"refund\":0.4,\"information\":0.02,\"exchange\":0.24}},\"tone\":{\"type\":\"choice\",\"choice\":\"frustrated\",\"confidence\":0.76,\"probabilities\":{\"frustrated\":0.84,\"angry\":0.16,\"calm\":0.0}}},\"usage\":{\"input_tokens\":589,\"output_tokens\":212}}";
  return response.parse_response(body);
}

fn t18() -> Int {
  let r: Result[Response, JevError] = fan_out_response();
  if !r.is_ok { return report(false, "fan-out fixture parses for selection"); }
  let resp: Response = r.value;
  var ok: Bool = true;
  if selection.answer_argmax(&resp, 0) != 2 { ok = false; }
  if !str_eq(selection.answer_argmax_label(&resp, 0), "returns") { ok = false; }
  if selection.answer_max_micro(&resp, 0) != 610000 { ok = false; }
  if selection.answer_count_at_or_above(&resp, 0, 250000) != 2 { ok = false; }
  let above: Vec[Str] = selection.answer_labels_at_or_above(&resp, 0, 250000);
  if above.len() != 2 { ok = false; }
  let a0: Str = above[0];
  let a1: Str = above[1];
  if !str_eq(a0, "billing") { ok = false; }
  if !str_eq(a1, "returns") { ok = false; }
  if selection.answer_count_at_or_above(&resp, 0, 610000) != 1 { ok = false; }
  if selection.answer_count_at_or_above(&resp, 3, 20000) != 4 { ok = false; }
  if !str_eq(selection.answer_argmax_label(&resp, 3), "refund") { ok = false; }
  if !str_eq(selection.answer_argmax_label(&resp, 2), "delayed") { ok = false; }
  return report(ok, "argmax and inclusive threshold over fan-out answers");
}

fn t19() -> Int {
  let r: Result[Response, JevError] = fan_out_response();
  if !r.is_ok { return report(false, "fan-out fixture parses for sampling"); }
  let resp: Response = r.value;
  var ok: Bool = true;
  if selection.answer_sample_index(&resp, 0, 0) != 0 { ok = false; }
  if selection.answer_sample_index(&resp, 0, 39999) != 0 { ok = false; }
  if selection.answer_sample_index(&resp, 0, 40000) != 1 { ok = false; }
  if selection.answer_sample_index(&resp, 0, 389999) != 1 { ok = false; }
  if selection.answer_sample_index(&resp, 0, 390000) != 2 { ok = false; }
  if selection.answer_sample_index(&resp, 0, 999999) != 2 { ok = false; }
  if selection.answer_sample_index(&resp, 0, -1) != 2 { ok = false; }
  if selection.answer_sample_index(&resp, 0, 1000000) != 0 { ok = false; }
  if selection.answer_sample_index(&resp, 0, -1000000) != 0 { ok = false; }
  if !str_eq(selection.answer_sample_label(&resp, 0, 500000), "returns") { ok = false; }
  if selection.answer_sample_index(&resp, 99, 0) != -1 { ok = false; }
  return report(ok, "sample-by-probability boundaries (half-open, negative entropy)");
}

fn t20() -> Int {
  var ans: Answers = types.answers_new();
  ans.ids.push("z");
  ans.kinds.push(types.KIND_CHOICE);
  ans.choices.push("a");
  ans.confidence_micro.push(0);
  ans.score_micro.push(0);
  ans.noul_micro.push(0);
  ans.prob_starts.push(0);
  ans.prob_counts.push(2);
  ans.prob_labels.push("a");
  ans.prob_labels.push("b");
  ans.prob_micro.push(0);
  ans.prob_micro.push(0);
  var resp: Response = types.response_new("m");
  resp.answers = ans;
  var ok: Bool = true;
  if selection.answer_sample_index(&resp, 0, 7) != -1 { ok = false; }
  if selection.answer_argmax(&resp, 0) != 0 { ok = false; }
  if selection.answer_max_micro(&resp, 0) != 0 { ok = false; }
  if selection.answer_count_at_or_above(&resp, 0, 0) != 2 { ok = false; }
  let body: Str = "{\"model\":\"m\",\"answers\":{\"q\":{\"type\":\"choice\",\"choice\":\"b\",\"confidence\":0.5,\"probabilities\":{\"a\":0.0,\"b\":1.0,\"c\":0.0}}}}";
  let r: Result[Response, JevError] = response.parse_response(body);
  if !r.is_ok { return report(false, "zero-entry choice fixture parses"); }
  let r2: Response = r.value;
  if selection.answer_sample_index(&r2, 0, 0) != 1 { ok = false; }
  if selection.answer_sample_index(&r2, 0, 999999) != 1 { ok = false; }
  if selection.answer_count_at_or_above(&r2, 0, 1) != 1 { ok = false; }
  let single: Str = "{\"model\":\"m\",\"answers\":{\"q\":{\"type\":\"choice\",\"choice\":\"a\",\"confidence\":1.0,\"probabilities\":{\"a\":1.0}}}}";
  let r3: Result[Response, JevError] = response.parse_response(single);
  if !r3.is_ok { return report(false, "single-entry choice fixture parses"); }
  let r4: Response = r3.value;
  if selection.answer_sample_index(&r4, 0, 123456) != 0 { ok = false; }
  return report(ok, "degenerate distributions (all-zero, zero-probability options, single)");
}

fn t21() -> Int {
  var ok: Bool = true;
  if selection.score_round_level(0) != 0 { ok = false; }
  if selection.score_round_level(499999) != 0 { ok = false; }
  if selection.score_round_level(500000) != 1 { ok = false; }
  if selection.score_round_level(1499999) != 1 { ok = false; }
  if selection.score_round_level(1500000) != 2 { ok = false; }
  if selection.score_round_level(2520000) != 3 { ok = false; }
  if selection.score_round_level(9000000) != 9 { ok = false; }
  if selection.score_normalized_micro(1430000, 2) != 715000 { ok = false; }
  if selection.score_normalized_micro(1000000, 2) != 500000 { ok = false; }
  if selection.score_normalized_micro(2000000, 2) != 1000000 { ok = false; }
  if selection.score_normalized_micro(1000000, 3) != 333333 { ok = false; }
  if selection.score_normalized_micro(2000000, 3) != 666667 { ok = false; }
  if selection.score_normalized_micro(777777, 0) != 0 { ok = false; }
  if selection.score_normalized_micro(0, 3) != 0 { ok = false; }
  return report(ok, "score round/normalize (half-up, top-level guard)");
}

fn t22() -> Int {
  var ok: Bool = true;
  if selection.noul_confidence_micro(0) != 1000000 { ok = false; }
  if selection.noul_confidence_micro(1000000) != 1000000 { ok = false; }
  if selection.noul_confidence_micro(750000) != 500000 { ok = false; }
  if selection.noul_confidence_micro(400000) != 200000 { ok = false; }
  if selection.noul_yes(-1, 0) != 0 { ok = false; }
  return report(ok, "noul threshold and |2p-1| spread");
}

// --------------------------------------------------
//  Presentation and helper surfaces
// --------------------------------------------------

fn t23() -> Int {
  var ok: Bool = true;
  if !str_eq(types.micro_text(0), "0") { ok = false; }
  if !str_eq(types.micro_text(10000), "0.01") { ok = false; }
  if !str_eq(types.micro_text(40000), "0.04") { ok = false; }
  if !str_eq(types.micro_text(610000), "0.61") { ok = false; }
  if !str_eq(types.micro_text(350000), "0.35") { ok = false; }
  if !str_eq(types.micro_text(150000), "0.15") { ok = false; }
  if !str_eq(types.micro_text(999999), "0.999999") { ok = false; }
  if !str_eq(types.micro_text(1000000), "1") { ok = false; }
  if !str_eq(types.micro_text(1430000), "1.43") { ok = false; }
  if !str_eq(types.micro_text(2000000), "2") { ok = false; }
  if !str_eq(types.micro_text(-5), "0") { ok = false; }
  if !str_eq(types.kind_name(0), "choice") { ok = false; }
  if !str_eq(types.kind_name(1), "score") { ok = false; }
  if !str_eq(types.kind_name(2), "noul") { ok = false; }
  if !str_eq(types.kind_name(7), "") { ok = false; }
  return report(ok, "micro_text rendering and kind_name");
}

fn t24() -> Int {
  var ok: Bool = true;
  if !str_eq(jev.systemone_endpoint("https://api.typesafe.ai"), "https://api.typesafe.ai/v1/systemone") { ok = false; }
  if !str_eq(jev.systemone_endpoint("https://api.typesafe.ai/"), "https://api.typesafe.ai/v1/systemone") { ok = false; }
  if !str_eq(jev.systemone_endpoint("https://api.typesafe.ai///"), "https://api.typesafe.ai/v1/systemone") { ok = false; }
  if !str_eq(jev.systemone_endpoint("http://127.0.0.1:8080"), "http://127.0.0.1:8080/v1/systemone") { ok = false; }
  if !str_eq(jev.systemone_endpoint(""), "") { ok = false; }
  if !str_eq(jev.systemone_endpoint("/"), "") { ok = false; }
  if !str_eq(jev.default_model(), "jev-latest") { ok = false; }
  return report(ok, "endpoint composition (trailing slashes, empty base)");
}

fn t25() -> Int {
  var ok: Bool = true;
  if !str_eq(response.api_error_detail("{\"detail\":\"Invalid API key\"}"), "Invalid API key") { ok = false; }
  if !str_eq(response.api_error_detail("{\"detail\":[{\"loc\":[\"body\",\"state\"],\"msg\":\"Field required\",\"type\":\"missing\"}]}"), "Field required") { ok = false; }
  if !str_eq(response.api_error_detail("{\"detail\":[]}"), "") { ok = false; }
  if !str_eq(response.api_error_detail("{\"detail\":123}"), "") { ok = false; }
  if !str_eq(response.api_error_detail("{\"error\":\"x\"}"), "") { ok = false; }
  if !str_eq(response.api_error_detail("junk"), "") { ok = false; }
  return report(ok, "api_error_detail (detail string, 422 array, fallbacks)");
}

fn t26() -> Int {
  let body: Str = "{\"model\":\"jev-1.13.0\",\"answers\":{\"department\":{\"type\":\"choice\",\"choice\":\"returns\",\"confidence\":1.0,\"probabilities\":{\"shipping\":0.0,\"returns\":1.0,\"billing\":0.0}}},\"usage\":{\"input_tokens\":328,\"output_tokens\":34}}";
  let r: Result[Response, JevError] = response.parse_response(body);
  if !r.is_ok { return report(false, "covers fixture parses"); }
  let resp: Response = r.value;
  var ok: Bool = true;
  var q: Question = types.question_choice("department", "Which team should handle this?");
  types.question_add_option(&mut q, "returns", "Exchanges, wrong or damaged items");
  types.question_add_option(&mut q, "shipping", "Delivery status, delays, lost packages");
  types.question_add_option(&mut q, "billing", "Charges, invoices, payment problems");
  if selection.choice_answer_covers_question(&resp, 0, &q) != 1 { ok = false; }
  var q2: Question = types.question_choice("department", "Which team should handle this?");
  types.question_add_option(&mut q2, "returns", "x");
  types.question_add_option(&mut q2, "shipping", "x");
  types.question_add_option(&mut q2, "billing", "x");
  types.question_add_option(&mut q2, "legal", "x");
  if selection.choice_answer_covers_question(&resp, 0, &q2) != 0 { ok = false; }
  var q3: Question = types.question_score("s", "rate");
  types.question_add_level(&mut q3, "a");
  types.question_add_level(&mut q3, "b");
  if selection.choice_answer_covers_question(&resp, 0, &q3) != 0 { ok = false; }
  if !str_eq(types.response_id(&resp, -1), "") { ok = false; }
  if types.response_kind(&resp, 99) != -1 { ok = false; }
  if types.response_prob_micro(&resp, 0, 9) != -1 { ok = false; }
  if types.response_prob_find(&resp, 0, "nope") != -1 { ok = false; }
  if types.response_choice(&resp, 5) != "" { ok = false; }
  let state: State = types.state_text("x");
  var qs: Vec[Question] = Vec[Question].new();
  qs.push(types.question_noul("q", "Is it?"));
  let b1: Result[Str, JevError] = request.build_request("m", state, qs);
  let b2: Result[Str, JevError] = request.build_request("m", types.state_text("x"), triage_questions());
  if !b1.is_ok || !b2.is_ok { ok = false; }
  let g1: Str = b1.value;
  let g2: Str = b2.value;
  if str_eq(g1, g2) { ok = false; }
  let again: Result[Response, JevError] = response.parse_response(body);
  if !again.is_ok { ok = false; }
  let r2: Response = again.value;
  if !str_eq(types.response_choice(&r2, 0), "returns") { ok = false; }
  return report(ok, "covers check, guards and determinism");
}

// --------------------------------------------------
//  M2 chunk 1: retry policy (429/503/529, bounded backoff)
// --------------------------------------------------

fn t27() -> Int {
  var ok: Bool = true;
  if retry.retry_is_retryable(429) != 1 { ok = false; }
  if retry.retry_is_retryable(503) != 1 { ok = false; }
  if retry.retry_is_retryable(529) != 1 { ok = false; }
  if retry.retry_is_retryable(500) != 0 { ok = false; }
  if retry.retry_is_retryable(528) != 0 { ok = false; }
  if retry.retry_is_retryable(530) != 0 { ok = false; }
  if retry.retry_is_retryable(401) != 0 { ok = false; }
  if retry.retry_is_retryable(200) != 0 { ok = false; }
  if retry.retry_is_retryable(0) != 0 { ok = false; }
  return report(ok, "retry classification (429/503/529 transient)");
}

fn t28() -> Int {
  var ok: Bool = true;
  if retry.retry_backoff_millis(1, 500, 30000) != 500 { ok = false; }
  if retry.retry_backoff_millis(2, 500, 30000) != 1000 { ok = false; }
  if retry.retry_backoff_millis(3, 500, 30000) != 2000 { ok = false; }
  if retry.retry_backoff_millis(4, 500, 30000) != 4000 { ok = false; }
  if retry.retry_backoff_millis(5, 500, 30000) != 8000 { ok = false; }
  if retry.retry_backoff_millis(6, 500, 30000) != 16000 { ok = false; }
  if retry.retry_backoff_millis(7, 500, 30000) != 30000 { ok = false; }
  if retry.retry_backoff_millis(8, 500, 30000) != 30000 { ok = false; }
  if retry.retry_backoff_millis(99, 500, 30000) != 30000 { ok = false; }
  return report(ok, "retry backoff doubling and cap (500ms base, 30s cap)");
}

fn t29() -> Int {
  var ok: Bool = true;
  if retry.retry_backoff_millis(0, 500, 30000) != 0 { ok = false; }
  if retry.retry_backoff_millis(-3, 500, 30000) != 0 { ok = false; }
  if retry.retry_backoff_millis(1, 0, 30000) != 0 { ok = false; }
  if retry.retry_backoff_millis(1, -10, 30000) != 0 { ok = false; }
  if retry.retry_backoff_millis(1, 100, 50) != 50 { ok = false; }
  if retry.retry_backoff_millis(5, 100, 250) != 250 { ok = false; }
  if retry.retry_backoff_millis(1, 500, 0) != 500 { ok = false; }
  if retry.retry_backoff_millis(3, 500, 0) != 2000 { ok = false; }
  if retry.retry_backoff_millis(100, 1, 0) != 549755813888 { ok = false; }
  return report(ok, "retry backoff edges (guards, no-cap, overflow bound)");
}

fn t30() -> Int {
  var ok: Bool = true;
  if retry.default_max_attempts() != 4 { ok = false; }
  if retry.default_base_millis() != 500 { ok = false; }
  if retry.default_cap_millis() != 30000 { ok = false; }
  return report(ok, "retry defaults (4 attempts, 500ms base, 30s cap)");
}

// --------------------------------------------------
//  M2 chunk 2: structured instructions and criteria (S3/S4/S5)
// --------------------------------------------------

fn t31() -> Int {
  var qs: Vec[Question] = Vec[Question].new();
  var q: Question = types.question_choice("return_topic", "");
  types.question_set_instructions_json(&mut q, jv("{\"question\":\"Which returns topic is the customer asking about?\",\"focus\":\"Classify the information the customer wants.\"}"));
  types.question_add_option_json(&mut q, "return_policy", jv("{\"what\":\"Whether and how an item can be returned\",\"not_for\":\"Progress of a return already sent\",\"examples\":[\"Can I return shoes I've worn once?\",\"How long do I have to return an order?\"]}"));
  types.question_add_option_json(&mut q, "return_status", jv("{\"what\":\"Progress of a return already sent\",\"not_for\":\"Whether and how an item can be returned\",\"examples\":[\"Has my return arrived yet?\",\"When will my refund be paid?\"]}"));
  qs.push(q);
  let state: State = types.state_text("I sent the shoes back a week ago. When do I get my money?");
  let built: Result[Str, JevError] = request.build_request("jev-latest", state, qs);
  if !built.is_ok { return report(false, "S3 structured choice request builds"); }
  let got: Str = built.value;
  let want: Str = "{\"state\":\"I sent the shoes back a week ago. When do I get my money?\",\"model\":\"jev-latest\",\"questions\":{\"return_topic\":{\"type\":\"choice\",\"instructions\":{\"question\":\"Which returns topic is the customer asking about?\",\"focus\":\"Classify the information the customer wants.\"},\"criteria\":{\"return_policy\":{\"what\":\"Whether and how an item can be returned\",\"not_for\":\"Progress of a return already sent\",\"examples\":[\"Can I return shoes I've worn once?\",\"How long do I have to return an order?\"]},\"return_status\":{\"what\":\"Progress of a return already sent\",\"not_for\":\"Whether and how an item can be returned\",\"examples\":[\"Has my return arrived yet?\",\"When will my refund be paid?\"]}}}}}";
  return report(str_eq(got, want), "S3 structured choice instructions/criteria byte-exact");
}

fn t32() -> Int {
  var qs: Vec[Question] = Vec[Question].new();
  var q: Question = types.question_score("bug_severity", "How severe is the reported issue?");
  types.question_add_level_json(&mut q, jv("{\"what\":\"Cosmetic; no impact to functionality\",\"examples\":[\"typo in a label\",\"misaligned icon\"]}"));
  types.question_add_level_json(&mut q, jv("{\"what\":\"Broken or degraded feature, but workaround exists\",\"examples\":[\"export fails in one browser but works in another\"]}"));
  types.question_add_level_json(&mut q, jv("{\"what\":\"Blocking issue; no workaround exists\",\"examples\":[\"cannot log in\",\"data loss\"]}"));
  qs.push(q);
  let state: State = types.state_text("Export to PDF fails with a spinner that never finishes. Some of our team say CSV export still works for them, others say it fails too.");
  let built: Result[Str, JevError] = request.build_request("jev-latest", state, qs);
  if !built.is_ok { return report(false, "S4 structured score levels build"); }
  let got: Str = built.value;
  let want: Str = "{\"state\":\"Export to PDF fails with a spinner that never finishes. Some of our team say CSV export still works for them, others say it fails too.\",\"model\":\"jev-latest\",\"questions\":{\"bug_severity\":{\"type\":\"score\",\"instructions\":\"How severe is the reported issue?\",\"criteria\":[{\"what\":\"Cosmetic; no impact to functionality\",\"examples\":[\"typo in a label\",\"misaligned icon\"]},{\"what\":\"Broken or degraded feature, but workaround exists\",\"examples\":[\"export fails in one browser but works in another\"]},{\"what\":\"Blocking issue; no workaround exists\",\"examples\":[\"cannot log in\",\"data loss\"]}]}}}";
  return report(str_eq(got, want), "S4 structured score levels byte-exact (object array form)");
}

fn t33() -> Int {
  let state: State = types.state_json(jv("{\"resume\":{\"name\":\"John Smith\",\"location\":\"Oakland, CA\",\"summary\":\"Backend engineer with eight years of Python and Go experience.\",\"experience\":[{\"employer\":\"Google\",\"title\":\"Senior Backend Engineer\",\"years\":\"2021-2025\"},{\"employer\":\"Microsoft\",\"title\":\"Software Engineer\",\"years\":\"2017-2021\"}]}}"));
  var qs: Vec[Question] = Vec[Question].new();
  var q: Question = types.question_noul("same_as_record_18", "");
  types.question_set_instructions_json(&mut q, jv("{\"potential_duplicate\":{\"name\":\"Jon Smith\",\"location\":\"Oakland, CA\",\"last_employer\":\"Google\"},\"question\":\"Is the resume for the same person as `potential_duplicate`?\"}"));
  qs.push(q);
  let built: Result[Str, JevError] = request.build_request("jev-latest", state, qs);
  if !built.is_ok { return report(false, "S5 structured noul instructions build"); }
  let got: Str = built.value;
  let want: Str = "{\"state\":{\"resume\":{\"name\":\"John Smith\",\"location\":\"Oakland, CA\",\"summary\":\"Backend engineer with eight years of Python and Go experience.\",\"experience\":[{\"employer\":\"Google\",\"title\":\"Senior Backend Engineer\",\"years\":\"2021-2025\"},{\"employer\":\"Microsoft\",\"title\":\"Software Engineer\",\"years\":\"2017-2021\"}]}},\"model\":\"jev-latest\",\"questions\":{\"same_as_record_18\":{\"type\":\"noul\",\"instructions\":{\"potential_duplicate\":{\"name\":\"Jon Smith\",\"location\":\"Oakland, CA\",\"last_employer\":\"Google\"},\"question\":\"Is the resume for the same person as `potential_duplicate`?\"}}}}";
  return report(str_eq(got, want), "S5 structured noul instructions byte-exact (object form)");
}

fn t34() -> Int {
  var qs: Vec[Question] = Vec[Question].new();
  var q: Question = types.question_noul("escalate", "");
  types.question_set_instructions_json(&mut q, jv("[\"Is the customer asking for a human agent?\",\"Consider explicit requests only.\"]"));
  types.question_set_noul_criteria_json(&mut q, jv("{\"what\":\"Mentions a prior attempt\",\"examples\":[\"asked three times\"]}"), jv("[\"No sign of any previous contact\"]"));
  qs.push(q);
  let built: Result[Str, JevError] = request.build_request("m", types.state_text("x"), qs);
  if !built.is_ok { return report(false, "S5 array instructions + structured criteria build"); }
  let got: Str = built.value;
  let want: Str = "{\"state\":\"x\",\"model\":\"m\",\"questions\":{\"escalate\":{\"type\":\"noul\",\"instructions\":[\"Is the customer asking for a human agent?\",\"Consider explicit requests only.\"],\"criteria\":{\"true\":{\"what\":\"Mentions a prior attempt\",\"examples\":[\"asked three times\"]},\"false\":[\"No sign of any previous contact\"]}}}}";
  return report(str_eq(got, want), "S5 array instructions + structured true/false criteria byte-exact");
}

fn t35() -> Int {
  var qs: Vec[Question] = Vec[Question].new();
  var q: Question = types.question_choice("mixed", "pick one");
  types.question_add_option(&mut q, "a", "plain text");
  types.question_add_option_json(&mut q, "b", jv("{\"what\":\"object form\"}"));
  types.question_add_option(&mut q, "c", "");
  types.question_add_option_json(&mut q, "d", jv("[\"array\",\"form\"]"));
  types.question_add_option_json(&mut q, "e", json.json_null());
  qs.push(q);
  let built: Result[Str, JevError] = request.build_request("m", types.state_text("x"), qs);
  if !built.is_ok { return report(false, "mixed string/object/array choice criteria builds"); }
  let got: Str = built.value;
  let want: Str = "{\"state\":\"x\",\"model\":\"m\",\"questions\":{\"mixed\":{\"type\":\"choice\",\"instructions\":\"pick one\",\"criteria\":{\"a\":\"plain text\",\"b\":{\"what\":\"object form\"},\"c\":null,\"d\":[\"array\",\"form\"],\"e\":null}}}}";
  if !str_eq(got, want) {
    return report(false, "mixed criteria byte-exact (got: " + got + ")");
  }
  var qs2: Vec[Question] = Vec[Question].new();
  var s: Question = types.question_score("s", "rate");
  types.question_add_level(&mut s, "text level");
  types.question_add_level_json(&mut s, jv("{\"what\":\"structured level\"}"));
  qs2.push(s);
  let built2: Result[Str, JevError] = request.build_request("m", types.state_text("x"), qs2);
  if !built2.is_ok { return report(false, "mixed string/object score levels build"); }
  let got2: Str = built2.value;
  let want2: Str = "{\"state\":\"x\",\"model\":\"m\",\"questions\":{\"s\":{\"type\":\"score\",\"instructions\":\"rate\",\"criteria\":[\"text level\",{\"what\":\"structured level\"}]}}}";
  return report(str_eq(got2, want2), "mixed string/object score levels byte-exact");
}

// --------------------------------------------------
//  M2 chunk 3: legend exposure (score answers)
// --------------------------------------------------

fn t36() -> Int {
  let body: Str = "{\"model\":\"jev-1.13.0\",\"answers\":{\"bug_severity\":{\"type\":\"score\",\"score\":1.43,\"confidence\":0.35,\"legend\":{\"0\":\"Cosmetic; no impact to functionality\",\"1\":\"Broken or degraded feature, but workaround exists\",\"2\":\"Blocking issue; no workaround exists\"},\"probabilities\":{\"0\":0.0,\"1\":0.57,\"2\":0.43}}},\"usage\":{\"input_tokens\":332,\"output_tokens\":18}}";
  let r: Result[Response, JevError] = response.parse_response(body);
  if !r.is_ok { return report(false, "score fixture parses for legend"); }
  let resp: Response = r.value;
  var ok: Bool = true;
  if types.response_legend_count(&resp, 0) != 3 { ok = false; }
  if !str_eq(types.response_legend_label(&resp, 0, 0), "0") { ok = false; }
  if !str_eq(types.response_legend_label(&resp, 0, 1), "1") { ok = false; }
  if !str_eq(types.response_legend_label(&resp, 0, 2), "2") { ok = false; }
  if !str_eq(types.response_legend_text(&resp, 0, 0), "Cosmetic; no impact to functionality") { ok = false; }
  if !str_eq(types.response_legend_text(&resp, 0, 2), "Blocking issue; no workaround exists") { ok = false; }
  if types.response_legend_is_structured(&resp, 0, 0) != 0 { ok = false; }
  if types.response_legend_find(&resp, 0, "1") != 1 { ok = false; }
  if types.response_legend_find(&resp, 0, "9") != -1 { ok = false; }
  if types.response_legend_count(&resp, 9) != 0 { ok = false; }
  if !str_eq(types.response_legend_label(&resp, 0, 9), "") { ok = false; }
  let emitted: Str = json.json_stringify(types.response_legend_json(&resp, 0));
  let want: Str = "{\"0\":\"Cosmetic; no impact to functionality\",\"1\":\"Broken or degraded feature, but workaround exists\",\"2\":\"Blocking issue; no workaround exists\"}";
  if !str_eq(emitted, want) {
    return report(false, "string legend emission byte-exact (got: " + emitted + ")");
  }
  let cb: Str = "{\"model\":\"m\",\"answers\":{\"q\":{\"type\":\"choice\",\"choice\":\"a\",\"confidence\":1.0,\"probabilities\":{\"a\":1.0}}}}";
  let cr: Result[Response, JevError] = response.parse_response(cb);
  if !cr.is_ok {
    ok = false;
  } else {
    let cresp: Response = cr.value;
    if types.response_legend_count(&cresp, 0) != 0 { ok = false; }
  }
  return report(ok, "score legend exposed (string form: labels, text, find, emission)");
}

fn t37() -> Int {
  let body: Str = "{\"model\":\"jev-1.13.0\",\"answers\":{\"bug_severity\":{\"type\":\"score\",\"score\":1.09,\"confidence\":0.87,\"legend\":{\"0\":{\"what\":\"Cosmetic; no impact to functionality\",\"examples\":[\"typo in a label\",\"misaligned icon\"]},\"1\":{\"what\":\"Broken or degraded feature, but workaround exists\",\"examples\":[\"export fails in one browser but works in another\"]},\"2\":{\"what\":\"Blocking issue; no workaround exists\",\"examples\":[\"cannot log in\",\"data loss\"]}},\"probabilities\":{\"0\":0.0,\"1\":0.91,\"2\":0.09}}},\"usage\":{\"input_tokens\":379,\"output_tokens\":18}}";
  let r: Result[Response, JevError] = response.parse_response(body);
  if !r.is_ok { return report(false, "structured-legend fixture parses"); }
  let resp: Response = r.value;
  var ok: Bool = true;
  if types.response_legend_count(&resp, 0) != 3 { ok = false; }
  if !str_eq(types.response_legend_label(&resp, 0, 1), "1") { ok = false; }
  if types.response_legend_is_structured(&resp, 0, 0) != 1 { ok = false; }
  if types.response_legend_is_structured(&resp, 0, 2) != 1 { ok = false; }
  if !str_eq(types.response_legend_text(&resp, 0, 0), "") { ok = false; }
  let d0: JsonValue = types.response_legend_doc(&resp, 0, 0);
  if compare.str_compare(json.json_type(d0), "object") != 0 { ok = false; }
  let emitted: Str = json.json_stringify(types.response_legend_json(&resp, 0));
  let want: Str = "{\"0\":{\"what\":\"Cosmetic; no impact to functionality\",\"examples\":[\"typo in a label\",\"misaligned icon\"]},\"1\":{\"what\":\"Broken or degraded feature, but workaround exists\",\"examples\":[\"export fails in one browser but works in another\"]},\"2\":{\"what\":\"Blocking issue; no workaround exists\",\"examples\":[\"cannot log in\",\"data loss\"]}}";
  if !str_eq(emitted, want) {
    return report(false, "structured legend emission byte-exact (got: " + emitted + ")");
  }
  return report(ok, "score legend exposed (structured form: docs, structured flag, emission)");
}

// --------------------------------------------------
//  M2 chunk 3: API-key hygiene and base_url validation
// --------------------------------------------------

fn t38() -> Int {
  var failed: Int = 0;
  let okr: Result[Str, JevError] = jev.api_key_validate("  sk-abc-123\t");
  if !okr.is_ok {
    failed = failed + report(false, "padded api key accepted");
  } else {
    let k: Str = okr.value;
    failed = failed + report(str_eq(k, "sk-abc-123"), "api key trimmed to its printable core");
  }
  failed = failed + expect_bad(jev.api_key_validate(""), "client: api_key is empty", "empty api key rejected");
  failed = failed + expect_bad(jev.api_key_validate("   "), "client: api_key is empty", "whitespace-only api key rejected");
  failed = failed + expect_bad(jev.api_key_validate("sk abc"), "client: api_key has invalid characters", "internal space rejected");
  failed = failed + expect_bad(jev.api_key_validate("sk\tabc"), "client: api_key has invalid characters", "internal tab rejected");
  failed = failed + expect_bad(jev.api_key_validate("sk\nabc"), "client: api_key has invalid characters", "control byte rejected");
  let nc: Option[Char] = convert.int_to_char(233);
  if nc.is_some {
    let nonascii: Str = tostring.to_string_char(nc.value);
    failed = failed + expect_bad(jev.api_key_validate("sk" + nonascii), "client: api_key has invalid characters", "non-ASCII key rejected");
  }
  return report(failed == 0, "api key hygiene (trim + printable-ASCII)");
}

fn t39() -> Int {
  var failed: Int = 0;
  let ok1: Result[Str, JevError] = jev.base_url_validate("https://api.typesafe.ai");
  if !ok1.is_ok {
    failed = failed + report(false, "https base accepted");
  } else {
    let v1: Str = ok1.value;
    failed = failed + report(str_eq(v1, "https://api.typesafe.ai"), "https base accepted unchanged");
  }
  let ok2: Result[Str, JevError] = jev.base_url_validate("http://127.0.0.1:8080/");
  if !ok2.is_ok {
    failed = failed + report(false, "http host:port base accepted");
  } else {
    let v2: Str = ok2.value;
    failed = failed + report(str_eq(v2, "http://127.0.0.1:8080/"), "http host:port base accepted unchanged");
  }
  failed = failed + expect_bad(jev.base_url_validate(""), "client: base_url is empty", "empty base rejected");
  failed = failed + expect_bad(jev.base_url_validate("///"), "client: base_url is empty", "all-slash base rejected");
  failed = failed + expect_bad(jev.base_url_validate("ftp://api.typesafe.ai"), "client: base_url scheme must be http or https", "non-http scheme rejected");
  failed = failed + expect_bad(jev.base_url_validate("api.typesafe.ai"), "client: base_url scheme must be http or https", "scheme-less base rejected");
  failed = failed + expect_bad(jev.base_url_validate("https://"), "client: base_url host is empty", "scheme-only base (empty host) rejected");
  failed = failed + expect_bad(jev.base_url_validate("https:///v1"), "client: base_url host is empty", "slash-only host rejected");
  return report(failed == 0, "base_url validation (scheme + host)");
}

// --------------------------------------------------
//  M2 chunk 4 (S8): 32 MiB body rule and compression
// --------------------------------------------------

fn t40() -> Int {
  var failed: Int = 0;
  if compression.max_body_bytes() != 33554432 {
    failed = failed + report(false, "MAX body is 33554432");
  } else {
    failed = failed + report(true, "MAX body is 33554432");
  }
  failed = failed + expect_ok_int(compression.body_size_check(0), 0, "body size 0 accepted");
  failed = failed + expect_ok_int(compression.body_size_check(33554431), 33554431, "body size 32 MiB - 1 accepted");
  failed = failed + expect_ok_int(compression.body_size_check(33554432), 33554432, "body size 32 MiB (inclusive) accepted");
  failed = failed + expect_bad_int(compression.body_size_check(33554433), "request: body exceeds 32 MiB limit", "body size 32 MiB + 1 rejected");
  failed = failed + expect_bad_int(compression.body_size_check(-1), "compression: body size is negative", "negative body size rejected");

  // Synthetic buffer (no network): exact MAX, MAX-1 and MAX+1 byte lengths.
  let max_s: Str = string.str_repeat("A", compression.max_body_bytes());
  if max_s.len() != 33554432 {
    failed = failed + report(false, "synthetic 32 MiB buffer has exact length");
  } else {
    failed = failed + report(true, "synthetic 32 MiB buffer has exact length");
  }
  failed = failed + expect_ok_int(compression.body_size_check(max_s.len()), 33554432, "synthetic 32 MiB buffer accepted");
  let under_s: Str = string.str_slice(max_s, 0, 33554431);
  if under_s.len() != 33554431 {
    failed = failed + report(false, "synthetic 32 MiB - 1 buffer has exact length");
  } else {
    failed = failed + report(true, "synthetic 32 MiB - 1 buffer has exact length");
  }
  failed = failed + expect_ok_int(compression.body_size_check(under_s.len()), 33554431, "synthetic 32 MiB - 1 buffer accepted");
  let over_s: Str = max_s + "A";
  if over_s.len() != 33554433 {
    failed = failed + report(false, "synthetic 32 MiB + 1 buffer has exact length");
  } else {
    failed = failed + report(true, "synthetic 32 MiB + 1 buffer has exact length");
  }
  failed = failed + expect_bad_int(compression.body_size_check(over_s.len()), "request: body exceeds 32 MiB limit", "synthetic 32 MiB + 1 buffer rejected");
  return report(failed == 0, "32 MiB body rule (inclusive boundary, synthetic buffers)");
}

fn t41() -> Int {
  var failed: Int = 0;
  // Encoding tag <-> Content-Encoding token map.
  if !str_eq(compression.encoding_name(compression.ENCODING_IDENTITY), "identity") { failed = failed + report(false, "identity encoding name"); } else { failed = failed + report(true, "identity encoding name"); }
  if !str_eq(compression.encoding_name(compression.ENCODING_GZIP), "gzip") { failed = failed + report(false, "gzip encoding name"); } else { failed = failed + report(true, "gzip encoding name"); }
  if !str_eq(compression.encoding_name(compression.ENCODING_ZSTD), "zstd") { failed = failed + report(false, "zstd encoding name"); } else { failed = failed + report(true, "zstd encoding name"); }
  if !str_eq(compression.encoding_name(99), "") { failed = failed + report(false, "unknown encoding name is empty"); } else { failed = failed + report(true, "unknown encoding name is empty"); }
  let gzip_tag: Result[Int, JevError] = compression.encoding_from_name("gzip");
  failed = failed + expect_ok_int(gzip_tag, compression.ENCODING_GZIP, "encoding_from_name(gzip)");
  failed = failed + expect_bad_int(compression.encoding_from_name("br"), "compression: unknown encoding 'br'", "encoding_from_name rejects unknown token");
  if compression.encoding_supported(compression.ENCODING_IDENTITY) != 1 { failed = failed + report(false, "identity supported"); } else { failed = failed + report(true, "identity supported"); }
  if compression.encoding_supported(compression.ENCODING_GZIP) != 1 { failed = failed + report(false, "gzip supported"); } else { failed = failed + report(true, "gzip supported"); }
  if compression.encoding_supported(compression.ENCODING_ZSTD) != 0 { failed = failed + report(false, "zstd not supported"); } else { failed = failed + report(true, "zstd not supported"); }

  let body: Str = "{\"state\":\"hello hello hello\",\"model\":\"jev-latest\",\"questions\":{}}";
  let plain: Vec[UInt8] = encoding.utf8_encode(body);
  // identity is a byte-exact pass-through.
  let idr: Result[Vec[UInt8], JevError] = compression.compress_body(body, compression.ENCODING_IDENTITY);
  if !idr.is_ok {
    failed = failed + report(false, "identity body encodes");
  } else {
    let idv: Vec[UInt8] = idr.value;
    failed = failed + report(bytes_eq(&idv, &plain), "identity body is byte-exact");
  }
  // gzip round-trip: header magic + decompressed bytes equal the input bytes.
  let gr: Result[Vec[UInt8], JevError] = compression.compress_body(body, compression.ENCODING_GZIP);
  if !gr.is_ok {
    failed = failed + report(false, "gzip body compresses");
  } else {
    let frame: Vec[UInt8] = gr.value;
    var magic_ok: Bool = false;
    if frame.len() >= 2 {
      if frame[0] == 0x1F && frame[1] == 0x8B { magic_ok = true; }
    }
    failed = failed + report(magic_ok, "gzip frame starts with 1F 8B");
    let dec: Result[Vec[UInt8], Str] = gzip.gzip_decompress(&frame);
    if !dec.is_ok {
      failed = failed + report(false, "gzip body decompresses");
    } else {
      let decv: Vec[UInt8] = dec.value;
      failed = failed + report(bytes_eq(&decv, &plain), "gzip round-trip bytes equal the UTF-8 body");
    }
  }
  // Binary corpus: every byte value survives a gzip round-trip.
  var src: Vec[UInt8] = Vec[UInt8].new();
  var b: Int = 0;
  while b < 256 {
    src.push(b as UInt8);
    b = b + 1;
  }
  let br: Result[Vec[UInt8], JevError] = compression.compress_bytes(&src, compression.ENCODING_GZIP);
  if !br.is_ok {
    failed = failed + report(false, "binary gzip bytes compress");
  } else {
    let bframe: Vec[UInt8] = br.value;
    let bdec: Result[Vec[UInt8], Str] = gzip.gzip_decompress(&bframe);
    if !bdec.is_ok {
      failed = failed + report(false, "binary gzip bytes decompress");
    } else {
      let bdecv: Vec[UInt8] = bdec.value;
      failed = failed + report(bytes_eq(&bdecv, &src), "gzip round-trip preserves all 256 byte values");
    }
  }
  // Typed error arms: zstd absent and unknown tag.
  failed = failed + expect_bad_bytes(compression.compress_bytes(&plain, compression.ENCODING_ZSTD), "compression: zstd compressor is not available", "zstd compressor absent is a typed error");
  failed = failed + expect_bad_bytes(compression.compress_body(body, compression.ENCODING_ZSTD), "compression: zstd compressor is not available", "compress_body zstd absent is a typed error");
  failed = failed + expect_bad_bytes(compression.compress_bytes(&plain, 99), "compression: unknown encoding 99", "unknown encoding tag is a typed error");
  return report(failed == 0, "compression encodings (gzip round-trip, identity, typed errors)");
}

fn t42() -> Int {
  var failed: Int = 0;
  // The rule is checked on the logical body BEFORE compression runs. A
  // 32 MiB + 1 repetitive body must fail typed even though gzip would shrink
  // it far below the wire limit.
  let over_s: Str = string.str_repeat("A", compression.max_body_bytes()) + "A";
  failed = failed + expect_bad_bytes(compression.compress_body(over_s, compression.ENCODING_GZIP), "request: body exceeds 32 MiB limit", "oversized body rejected before gzip runs");
  failed = failed + expect_bad_bytes(compression.compress_body(over_s, compression.ENCODING_IDENTITY), "request: body exceeds 32 MiB limit", "oversized body rejected before identity encoding");
  return report(failed == 0, "32 MiB rule gates compression (no oversized logical body is encoded)");
}

// --------------------------------------------------
//  Entry point
// --------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.jev conformance tests ===");
  var failed: Int = 0;
  failed = failed + t1();
  failed = failed + t2();
  failed = failed + t3();
  failed = failed + t4();
  failed = failed + t5();
  failed = failed + t6();
  failed = failed + t7();
  failed = failed + t8();
  failed = failed + t9();
  failed = failed + t10();
  failed = failed + t11();
  failed = failed + t12();
  failed = failed + t13();
  failed = failed + t14();
  failed = failed + t15();
  failed = failed + t16();
  failed = failed + t17();
  failed = failed + t18();
  failed = failed + t19();
  failed = failed + t20();
  failed = failed + t21();
  failed = failed + t22();
  failed = failed + t23();
  failed = failed + t24();
  failed = failed + t25();
  failed = failed + t26();
  failed = failed + t27();
  failed = failed + t28();
  failed = failed + t29();
  failed = failed + t30();
  failed = failed + t31();
  failed = failed + t32();
  failed = failed + t33();
  failed = failed + t34();
  failed = failed + t35();
  failed = failed + t36();
  failed = failed + t37();
  failed = failed + t38();
  failed = failed + t39();
  failed = failed + t40();
  failed = failed + t41();
  failed = failed + t42();
  if failed == 0 {
    io.println("xiom.jev: all tests passed");
  } else {
    io.println("xiom.jev: tests failed");
  }
  return failed;
}
