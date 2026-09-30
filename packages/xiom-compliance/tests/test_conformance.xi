// XIOM -- xiom.compliance conformance tests (22 checks)
// Port task: prove the pure-XIOM xiom.compliance module against its
// predicate / waiver / severity / report contract.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module compliance_tests
use xiom.io; use xiom.test; use xiom.compliance; use xiom.convert;
use xiom.string;

// All Str equality goes through string.str_compare: BUG 17 lowers `==` on Str
// values read from Vec[Str] elements to a pointer comparison, so every text
// check below is routed through streq.
//
// Read-only operations are wrapped in helpers that take `&mut`, so a
// `&local` read call is never followed by a `&mut local` call in the same
// function body (advisory E001). Each helper calls the real `&`-based API.
// Fixtures build their record in a local and return it, so no helper has to
// forward a `&mut` parameter into another `&mut` parameter.

fn streq(a: Str, b: Str) -> Bool {
  return string.str_compare(a, b) == 0;
}

fn rules_count_of(s: &mut RuleSet) -> Int {
  return cmpl_rule_count(s);
}

fn rule_id_of(s: &mut RuleSet, i: Int) -> Str {
  return cmpl_rule_id(s, i);
}

fn rule_sev_of(s: &mut RuleSet, i: Int) -> Int {
  return cmpl_rule_severity(s, i);
}

fn rule_subject_of(s: &mut RuleSet, i: Int) -> Int {
  return cmpl_rule_subject(s, i);
}

fn rule_enabled_of(s: &mut RuleSet, i: Int) -> Bool {
  return cmpl_rule_is_enabled(s, i);
}

fn ev_count_of(e: &mut Evidence) -> Int {
  return cmpl_evidence_count(e);
}

fn has_of(e: &mut Evidence, name: Str) -> Bool {
  return cmpl_evidence_has(e, name);
}

fn kind_of(e: &mut Evidence, name: Str) -> Int {
  return cmpl_evidence_kind(e, name);
}

fn ev_int_of(e: &mut Evidence, name: Str, fallback: Int) -> Int {
  return cmpl_evidence_int(e, name, fallback);
}

fn ev_str_of(e: &mut Evidence, name: Str, fallback: Str) -> Str {
  return cmpl_evidence_str(e, name, fallback);
}

fn wcount_of(w: &mut WaiverSet) -> Int {
  return cmpl_waiver_count(w);
}

fn wactive_of(w: &mut WaiverSet, rule_id: Str, now: Int) -> Bool {
  return cmpl_waiver_active(w, rule_id, now);
}

fn eval_of(s: &mut RuleSet, e: &mut Evidence, w: &mut WaiverSet, now: Int) -> Findings {
  return cmpl_eval(s, e, w, now);
}

fn findings_len_of(f: &mut Findings) -> Int {
  return cmpl_findings_len(f);
}

fn finding_rule_of(f: &mut Findings, i: Int) -> Str {
  return cmpl_finding_rule(f, i);
}

fn finding_sev_of(f: &mut Findings, i: Int) -> Int {
  return cmpl_finding_severity(f, i);
}

fn outcome_of(f: &mut Findings, i: Int) -> Int {
  return cmpl_finding_outcome(f, i);
}

fn detail_of(f: &mut Findings, i: Int) -> Str {
  return cmpl_finding_detail(f, i);
}

fn count_of(f: &mut Findings, outcome: Int) -> Int {
  return cmpl_count(f, outcome);
}

fn sev_count_of(f: &mut Findings, outcome: Int, severity: Int) -> Int {
  return cmpl_severity_count(f, outcome, severity);
}

fn compliant_of(f: &mut Findings) -> Bool {
  return cmpl_is_compliant(f);
}

fn risk_of(f: &mut Findings) -> Int {
  return cmpl_risk_score(f);
}

fn waived_score_of(f: &mut Findings) -> Int {
  return cmpl_waived_score(f);
}

fn report_of(f: &mut Findings) -> Str {
  return cmpl_report(f);
}

// ------------------------------------------------------------------
//  Fixtures
// ------------------------------------------------------------------

// Four rules covering pass, violation, not-applicable (missing attribute)
// and waived (active waiver for R-WAIVED until tick 1000).
fn build_mixed_rules() -> RuleSet {
  var s = cmpl_rules_new();
  cmpl_rule_int(&mut s, "R-AGE-RANGE", CMPL_SEV_HIGH, "age", CMPL_OP_INT_RANGE, 18, 120);
  cmpl_rule_str(&mut s, "R-REGION-EU", CMPL_SEV_MEDIUM, "region", CMPL_OP_STR_EQ, "EU");
  cmpl_rule_int(&mut s, "R-MISSING", CMPL_SEV_LOW, "team", CMPL_OP_INT_EQ, 1, 0);
  cmpl_rule_int(&mut s, "R-WAIVED", CMPL_SEV_CRITICAL, "age", CMPL_OP_INT_EQ, 99, 0);
  return s;
}

fn build_mixed_evidence() -> Evidence {
  var e = cmpl_evidence_new();
  cmpl_evidence_put_int(&mut e, "age", 30);
  cmpl_evidence_put_str(&mut e, "region", "US");
  return e;
}

fn build_mixed_waivers() -> WaiverSet {
  var w = cmpl_waivers_new();
  cmpl_waive(&mut w, "R-WAIVED", 1000);
  return w;
}

fn mixed_findings(now: Int) -> Findings {
  var s = build_mixed_rules();
  var e = build_mixed_evidence();
  var w = build_mixed_waivers();
  let f = eval_of(&mut s, &mut e, &mut w, now);
  return f;
}

// ------------------------------------------------------------------
//  Tests
// ------------------------------------------------------------------

fn t1() -> TestResult {
  var ok = cmpl_pred_int(CMPL_OP_INT_EQ, 5, 0, 5);
  if cmpl_pred_int(CMPL_OP_INT_EQ, 5, 0, 6) { ok = false; }
  if !cmpl_pred_int(CMPL_OP_INT_NEQ, 5, 0, 6) { ok = false; }
  if cmpl_pred_int(CMPL_OP_INT_NEQ, 5, 0, 5) { ok = false; }
  if !cmpl_pred_int(CMPL_OP_INT_RANGE, 18, 120, 18) { ok = false; }
  if !cmpl_pred_int(CMPL_OP_INT_RANGE, 18, 120, 65) { ok = false; }
  if !cmpl_pred_int(CMPL_OP_INT_RANGE, 18, 120, 120) { ok = false; }
  if cmpl_pred_int(CMPL_OP_INT_RANGE, 18, 120, 17) { ok = false; }
  if cmpl_pred_int(CMPL_OP_INT_RANGE, 18, 120, 121) { ok = false; }
  if cmpl_pred_int(-1, 1, 2, 1) { ok = false; }
  return assert(ok, "int predicates: eq/neq/range inclusive on both bounds, unknown op false");
}

fn t2() -> TestResult {
  var ok = cmpl_pred_str(CMPL_OP_STR_EQ, "eu-west", "eu-west");
  if cmpl_pred_str(CMPL_OP_STR_EQ, "eu-west", "eu-west-1") { ok = false; }
  if cmpl_pred_str(CMPL_OP_STR_EQ, "eu", "EU") { ok = false; }
  if !cmpl_pred_str(CMPL_OP_STR_NEQ, "eu", "EU") { ok = false; }
  if !cmpl_pred_str(CMPL_OP_STR_PREFIX, "eu-", "eu-west-1") { ok = false; }
  if cmpl_pred_str(CMPL_OP_STR_PREFIX, "west", "eu-west-1") { ok = false; }
  if !cmpl_pred_str(CMPL_OP_STR_CONTAINS, "west", "eu-west-1") { ok = false; }
  if cmpl_pred_str(CMPL_OP_STR_CONTAINS, "asia", "eu-west-1") { ok = false; }
  if cmpl_pred_str(77, "a", "a") { ok = false; }
  return assert(ok, "str predicates: eq/neq byte-exact and case-sensitive, prefix/contains, unknown op false");
}

fn t3() -> TestResult {
  var s = cmpl_rules_new();
  var ok = rules_count_of(&mut s) == 0;
  if !streq(rule_id_of(&mut s, 0), "") { ok = false; }
  if rule_sev_of(&mut s, 0) != -1 { ok = false; }
  if rule_subject_of(&mut s, 0) != -1 { ok = false; }
  if rule_enabled_of(&mut s, 0) { ok = false; }
  if !streq(rule_id_of(&mut s, -3), "") { ok = false; }
  return assert(ok, "fresh rule set is empty; out-of-range accessors return sentinels");
}

fn t4() -> TestResult {
  var s = cmpl_rules_new();
  let i0 = cmpl_rule_int(&mut s, "R1", CMPL_SEV_HIGH, "age", CMPL_OP_INT_RANGE, 18, 120);
  let i1 = cmpl_rule_str(&mut s, "R2", CMPL_SEV_LOW, "region", CMPL_OP_STR_PREFIX, "eu-");
  var ok = (i0 == 0) && (i1 == 1);
  if rules_count_of(&mut s) != 2 { ok = false; }
  if !streq(rule_id_of(&mut s, 0), "R1") { ok = false; }
  if !streq(rule_id_of(&mut s, 1), "R2") { ok = false; }
  if rule_sev_of(&mut s, 0) != CMPL_SEV_HIGH { ok = false; }
  if rule_subject_of(&mut s, 0) != CMPL_INT { ok = false; }
  if rule_subject_of(&mut s, 1) != CMPL_STR { ok = false; }
  if !rule_enabled_of(&mut s, 0) { ok = false; }
  if s.ids.len() != 2 { ok = false; }
  if s.severities.len() != 2 { ok = false; }
  if s.subjects.len() != 2 { ok = false; }
  if s.attrs.len() != 2 { ok = false; }
  if s.ops.len() != 2 { ok = false; }
  if s.int_a.len() != 2 { ok = false; }
  if s.int_b.len() != 2 { ok = false; }
  if s.strs.len() != 2 { ok = false; }
  if s.enabled.len() != 2 { ok = false; }
  return assert(ok, "rule constructors append one aligned slot in all nine vectors and return the index");
}

fn t5() -> TestResult {
  var s = cmpl_rules_new();
  var e = cmpl_evidence_new();
  var w = cmpl_waivers_new();
  cmpl_evidence_put_int(&mut e, "age", 30);
  cmpl_rule_int(&mut s, "R1", CMPL_SEV_HIGH, "age", CMPL_OP_INT_RANGE, 18, 120);
  var ok = cmpl_rule_set_enabled(&mut s, 0, false);
  if rule_enabled_of(&mut s, 0) { ok = false; }
  if cmpl_rule_set_enabled(&mut s, 5, false) { ok = false; }
  if cmpl_rule_set_enabled(&mut s, -1, true) { ok = false; }
  var f = eval_of(&mut s, &mut e, &mut w, 0);
  if findings_len_of(&mut f) != 1 { ok = false; }
  if outcome_of(&mut f, 0) != CMPL_NOT_APPLICABLE { ok = false; }
  if !streq(detail_of(&mut f, 0), "") { ok = false; }
  if !compliant_of(&mut f) { ok = false; }
  if !cmpl_rule_set_enabled(&mut s, 0, true) { ok = false; }
  var f2 = eval_of(&mut s, &mut e, &mut w, 0);
  if outcome_of(&mut f2, 0) != CMPL_PASS { ok = false; }
  return assert(ok, "disabling yields not-applicable with empty detail; re-enabling restores pass");
}

fn t6() -> TestResult {
  var s = cmpl_rules_new();
  var e = cmpl_evidence_new();
  var w = cmpl_waivers_new();
  var f = eval_of(&mut s, &mut e, &mut w, 10);
  var ok = findings_len_of(&mut f) == 0;
  if !compliant_of(&mut f) { ok = false; }
  if risk_of(&mut f) != 0 { ok = false; }
  if waived_score_of(&mut f) != 0 { ok = false; }
  let want = "compliance-report v1\nfindings=0 pass=0 violation=0 waived=0 not-applicable=0\nviolations critical=0 high=0 medium=0 low=0 info=0 other=0\nscore=0 waived_score=0";
  if !streq(report_of(&mut f), want) { ok = false; }
  return assert(ok, "empty rule set yields no findings and a zeroed canonical report");
}

fn t7() -> TestResult {
  var e = cmpl_evidence_new();
  var ok = ev_count_of(&mut e) == 0;
  let i0 = cmpl_evidence_put_int(&mut e, "age", 30);
  let i1 = cmpl_evidence_put_str(&mut e, "region", "eu-west-1");
  let i2 = cmpl_evidence_put_int(&mut e, "age", 55);
  if !((i0 == 0) && (i1 == 1) && (i2 == 2)) { ok = false; }
  if ev_count_of(&mut e) != 3 { ok = false; }
  if !has_of(&mut e, "age") { ok = false; }
  if has_of(&mut e, "team") { ok = false; }
  if ev_int_of(&mut e, "age", -1) != 30 { ok = false; }
  if !streq(ev_str_of(&mut e, "region", "none"), "eu-west-1") { ok = false; }
  if !streq(ev_str_of(&mut e, "age", "none"), "none") { ok = false; }
  if ev_int_of(&mut e, "region", -7) != -7 { ok = false; }
  if kind_of(&mut e, "region") != CMPL_STR { ok = false; }
  if kind_of(&mut e, "age") != CMPL_INT { ok = false; }
  if kind_of(&mut e, "team") != -1 { ok = false; }
  return assert(ok, "evidence stores typed attributes, first-match lookup and kind-aware fallbacks");
}

fn t8() -> TestResult {
  var s = cmpl_rules_new();
  var e = cmpl_evidence_new();
  var w = cmpl_waivers_new();
  cmpl_rule_int(&mut s, "R-AGE", CMPL_SEV_HIGH, "age", CMPL_OP_INT_RANGE, 18, 120);
  cmpl_evidence_put_int(&mut e, "age", 30);
  var f = eval_of(&mut s, &mut e, &mut w, 5);
  var ok = outcome_of(&mut f, 0) == CMPL_PASS;
  if !streq(detail_of(&mut f, 0), "age") { ok = false; }
  if !compliant_of(&mut f) { ok = false; }
  if risk_of(&mut f) != 0 { ok = false; }
  if count_of(&mut f, CMPL_PASS) != 1 { ok = false; }
  if !streq(finding_rule_of(&mut f, 0), "R-AGE") { ok = false; }
  if finding_sev_of(&mut f, 0) != CMPL_SEV_HIGH { ok = false; }
  return assert(ok, "satisfied rule passes, reports its attribute as detail and scores zero risk");
}

fn t9() -> TestResult {
  var s = cmpl_rules_new();
  var e = cmpl_evidence_new();
  var w = cmpl_waivers_new();
  cmpl_rule_str(&mut s, "R-REGION", CMPL_SEV_MEDIUM, "region", CMPL_OP_STR_EQ, "EU");
  cmpl_evidence_put_str(&mut e, "region", "US");
  var f = eval_of(&mut s, &mut e, &mut w, 5);
  var ok = outcome_of(&mut f, 0) == CMPL_VIOLATION;
  if compliant_of(&mut f) { ok = false; }
  if risk_of(&mut f) != 4 { ok = false; }
  if waived_score_of(&mut f) != 0 { ok = false; }
  if count_of(&mut f, CMPL_VIOLATION) != 1 { ok = false; }
  if sev_count_of(&mut f, CMPL_VIOLATION, CMPL_SEV_MEDIUM) != 1 { ok = false; }
  if !streq(detail_of(&mut f, 0), "region") { ok = false; }
  if !streq(cmpl_outcome_name(outcome_of(&mut f, 0)), "violation") { ok = false; }
  return assert(ok, "unsatisfied rule without waiver is a violation: non-compliant with risk = weight");
}

fn t10() -> TestResult {
  var s = cmpl_rules_new();
  var e = cmpl_evidence_new();
  var w = cmpl_waivers_new();
  cmpl_rule_str(&mut s, "R-REGION", CMPL_SEV_MEDIUM, "region", CMPL_OP_STR_EQ, "EU");
  cmpl_evidence_put_str(&mut e, "region", "US");
  cmpl_waive(&mut w, "R-REGION", 100);
  var f = eval_of(&mut s, &mut e, &mut w, 99);
  var ok = outcome_of(&mut f, 0) == CMPL_WAIVED;
  if !compliant_of(&mut f) { ok = false; }
  if risk_of(&mut f) != 0 { ok = false; }
  if waived_score_of(&mut f) != 4 { ok = false; }
  if count_of(&mut f, CMPL_WAIVED) != 1 { ok = false; }
  if !streq(cmpl_outcome_name(outcome_of(&mut f, 0)), "waived") { ok = false; }
  return assert(ok, "an active waiver turns the violation into waived: risk 0, waived_score = weight");
}

fn t11() -> TestResult {
  var w = cmpl_waivers_new();
  let i0 = cmpl_waive(&mut w, "R1", 10);
  cmpl_waive(&mut w, "R2", 4);
  var ok = (i0 == 0) && (wcount_of(&mut w) == 2);
  if !wactive_of(&mut w, "R1", 9) { ok = false; }
  if wactive_of(&mut w, "R1", 10) { ok = false; }
  if wactive_of(&mut w, "R1", 11) { ok = false; }
  if !wactive_of(&mut w, "R2", -5) { ok = false; }
  if wactive_of(&mut w, "R3", 0) { ok = false; }
  var w2 = cmpl_waivers_new();
  cmpl_waive(&mut w2, "R9", 3);
  cmpl_waive(&mut w2, "R9", 9);
  if !wactive_of(&mut w2, "R9", 5) { ok = false; }
  if wactive_of(&mut w2, "R9", 9) { ok = false; }
  return assert(ok, "waiver expiry is exclusive; the latest of duplicate waivers keeps a rule covered");
}

fn t12() -> TestResult {
  var s = cmpl_rules_new();
  var e = cmpl_evidence_new();
  var w = cmpl_waivers_new();
  cmpl_rule_int(&mut s, "R1", CMPL_SEV_LOW, "age", CMPL_OP_INT_EQ, 1, 0);
  cmpl_evidence_put_int(&mut e, "age", 2);
  cmpl_waive(&mut w, "R1", 50);
  var f_at = eval_of(&mut s, &mut e, &mut w, 50);
  var ok = outcome_of(&mut f_at, 0) == CMPL_VIOLATION;
  var f_before = eval_of(&mut s, &mut e, &mut w, 49);
  if outcome_of(&mut f_before, 0) != CMPL_WAIVED { ok = false; }
  var w2 = cmpl_waivers_new();
  cmpl_waive(&mut w2, "R1", 7);
  cmpl_waive(&mut w2, "R1", 51);
  var f_two = eval_of(&mut s, &mut e, &mut w2, 50);
  if outcome_of(&mut f_two, 0) != CMPL_WAIVED { ok = false; }
  return assert(ok, "waiver at expiry tick does not cover; an expired duplicate never masks an active one");
}

fn t13() -> TestResult {
  var s = cmpl_rules_new();
  var e = cmpl_evidence_new();
  var w = cmpl_waivers_new();
  cmpl_rule_int(&mut s, "R-MISS", CMPL_SEV_LOW, "team", CMPL_OP_INT_EQ, 1, 0);
  cmpl_rule_int(&mut s, "R-KIND", CMPL_SEV_LOW, "age", CMPL_OP_INT_EQ, 30, 0);
  cmpl_evidence_put_str(&mut e, "age", "thirty");
  var f = eval_of(&mut s, &mut e, &mut w, 0);
  var ok = outcome_of(&mut f, 0) == CMPL_NOT_APPLICABLE;
  if !streq(detail_of(&mut f, 0), "team") { ok = false; }
  if outcome_of(&mut f, 1) != CMPL_NOT_APPLICABLE { ok = false; }
  if !streq(detail_of(&mut f, 1), "age") { ok = false; }
  if count_of(&mut f, CMPL_NOT_APPLICABLE) != 2 { ok = false; }
  if !compliant_of(&mut f) { ok = false; }
  if risk_of(&mut f) != 0 { ok = false; }
  return assert(ok, "missing attribute and attribute kind mismatch are not-applicable, never violations");
}

fn t14() -> TestResult {
  var f = mixed_findings(500);
  let want = "compliance-report v1\nfindings=4 pass=1 violation=1 waived=1 not-applicable=1\nviolations critical=0 high=0 medium=1 low=0 info=0 other=0\nscore=4 waived_score=16\n0|R-AGE-RANGE|high|pass|age\n1|R-REGION-EU|medium|violation|region\n2|R-MISSING|low|not-applicable|team\n3|R-WAIVED|critical|waived|age";
  var ok = streq(report_of(&mut f), want);
  if findings_len_of(&mut f) != 4 { ok = false; }
  if risk_of(&mut f) != 4 { ok = false; }
  if waived_score_of(&mut f) != 16 { ok = false; }
  return assert(ok, "mixed fixture renders the exact canonical report line by line");
}

fn t15() -> TestResult {
  var s = cmpl_rules_new();
  var e = cmpl_evidence_new();
  var w = cmpl_waivers_new();
  cmpl_rule_int(&mut s, "R|1", CMPL_SEV_INFO, "x|y", CMPL_OP_INT_EQ, 1, 0);
  cmpl_rule_int(&mut s, "L1\nL2", CMPL_SEV_LOW, "age", CMPL_OP_INT_EQ, 1, 0);
  cmpl_evidence_put_int(&mut e, "x|y", 2);
  cmpl_evidence_put_int(&mut e, "age", 2);
  var f = eval_of(&mut s, &mut e, &mut w, 0);
  var want = "compliance-report v1\nfindings=2 pass=0 violation=2 waived=0 not-applicable=0\nviolations critical=0 high=0 medium=0 low=1 info=1 other=0\nscore=3 waived_score=0\n";
  want = want + "0|R" + "\\" + "|1|info|violation|x" + "\\" + "|y\n";
  want = want + "1|L1" + "\\" + "nL2|low|violation|age";
  var ok = streq(report_of(&mut f), want);
  if risk_of(&mut f) != 3 { ok = false; }
  return assert(ok, "report escapes '|' as \\| and LF as \\n in ids and details");
}

fn t16() -> TestResult {
  var s = cmpl_rules_new();
  var e = cmpl_evidence_new();
  var w = cmpl_waivers_new();
  cmpl_rule_int(&mut s, "P1", CMPL_SEV_INFO, "a", CMPL_OP_INT_EQ, 1, 0);
  cmpl_rule_int(&mut s, "V1", CMPL_SEV_LOW, "b", CMPL_OP_INT_EQ, 1, 0);
  cmpl_rule_int(&mut s, "V2", CMPL_SEV_MEDIUM, "b", CMPL_OP_INT_EQ, 1, 0);
  cmpl_rule_int(&mut s, "W1", CMPL_SEV_HIGH, "b", CMPL_OP_INT_EQ, 1, 0);
  cmpl_rule_int(&mut s, "N1", CMPL_SEV_CRITICAL, "zz", CMPL_OP_INT_EQ, 1, 0);
  cmpl_rule_int(&mut s, "V3", CMPL_SEV_CRITICAL, "b", CMPL_OP_INT_EQ, 1, 0);
  cmpl_rule_int(&mut s, "V4", 9, "b", CMPL_OP_INT_EQ, 1, 0);
  cmpl_evidence_put_int(&mut e, "a", 1);
  cmpl_evidence_put_int(&mut e, "b", 2);
  cmpl_waive(&mut w, "W1", 50);
  var f = eval_of(&mut s, &mut e, &mut w, 10);
  var want = "compliance-report v1\nfindings=7 pass=1 violation=4 waived=1 not-applicable=1\nviolations critical=1 high=0 medium=1 low=1 info=0 other=1\nscore=22 waived_score=8\n";
  want = want + "0|P1|info|pass|a\n1|V1|low|violation|b\n2|V2|medium|violation|b\n3|W1|high|waived|b\n4|N1|critical|not-applicable|zz\n5|V3|critical|violation|b\n6|V4|unknown|violation|b";
  var ok = streq(report_of(&mut f), want);
  if risk_of(&mut f) != 22 { ok = false; }
  if waived_score_of(&mut f) != 8 { ok = false; }
  if sev_count_of(&mut f, CMPL_VIOLATION, CMPL_SEV_CRITICAL) != 1 { ok = false; }
  if sev_count_of(&mut f, CMPL_WAIVED, CMPL_SEV_HIGH) != 1 { ok = false; }
  return assert(ok, "severity rollup: per-severity violation counts, other bucket, exact risk and waived scores");
}

fn t17() -> TestResult {
  var f1 = mixed_findings(500);
  var f2 = mixed_findings(500);
  var ok = streq(report_of(&mut f1), report_of(&mut f2));
  if findings_len_of(&mut f1) != findings_len_of(&mut f2) { ok = false; }
  var i = 0;
  while i < findings_len_of(&mut f1) {
    if outcome_of(&mut f1, i) != outcome_of(&mut f2, i) { ok = false; }
    i = i + 1;
  }
  return assert(ok, "evaluation is deterministic: identical inputs produce an identical report");
}

fn t18() -> TestResult {
  var f_viol = mixed_findings(1000);
  var ok = !compliant_of(&mut f_viol);
  if risk_of(&mut f_viol) != 20 { ok = false; }
  if waived_score_of(&mut f_viol) != 0 { ok = false; }
  var f_waived = mixed_findings(500);
  if compliant_of(&mut f_waived) { ok = false; }
  if risk_of(&mut f_waived) != 4 { ok = false; }
  if waived_score_of(&mut f_waived) != 16 { ok = false; }
  var s = cmpl_rules_new();
  var e = cmpl_evidence_new();
  var w = cmpl_waivers_new();
  cmpl_rule_int(&mut s, "R1", CMPL_SEV_LOW, "b", CMPL_OP_INT_EQ, 1, 0);
  cmpl_evidence_put_int(&mut e, "b", 2);
  cmpl_waive(&mut w, "R1", 50);
  var f_only_waived = eval_of(&mut s, &mut e, &mut w, 10);
  if !compliant_of(&mut f_only_waived) { ok = false; }
  if risk_of(&mut f_only_waived) != 0 { ok = false; }
  if waived_score_of(&mut f_only_waived) != 2 { ok = false; }
  return assert(ok, "compliance tracks unwaived violations only: waived-only findings stay compliant");
}

fn t19() -> TestResult {
  var s = cmpl_rules_new();
  var e = cmpl_evidence_new();
  var w = cmpl_waivers_new();
  cmpl_rule_int(&mut s, "R-UNK-OP", 9, "grade", 42, 0, 0);
  cmpl_evidence_put_int(&mut e, "grade", 4);
  var f = eval_of(&mut s, &mut e, &mut w, 0);
  var ok = outcome_of(&mut f, 0) == CMPL_VIOLATION;
  if risk_of(&mut f) != 0 { ok = false; }
  if sev_count_of(&mut f, CMPL_VIOLATION, 9) != 1 { ok = false; }
  if !streq(cmpl_severity_name(9), "unknown") { ok = false; }
  if !streq(cmpl_severity_name(CMPL_SEV_CRITICAL), "critical") { ok = false; }
  if cmpl_severity_weight(9) != 0 { ok = false; }
  if cmpl_severity_weight(CMPL_SEV_CRITICAL) != 16 { ok = false; }
  if !streq(cmpl_outcome_name(99), "unknown") { ok = false; }
  return assert(ok, "unknown predicate op fails closed as violation; unknown severity is reported but weighs 0");
}

fn t20() -> TestResult {
  var s = cmpl_rules_new();
  var e = cmpl_evidence_new();
  var w = cmpl_waivers_new();
  var i = 0;
  while i < 60 {
    let name = "v" + convert.int_to_string(i);
    cmpl_rule_int(&mut s, "R" + convert.int_to_string(i), CMPL_SEV_INFO, name, CMPL_OP_INT_EQ, i, 0);
    cmpl_evidence_put_int(&mut e, name, i);
    i = i + 1;
  }
  var j = 0;
  while j < 40 {
    cmpl_rule_int(&mut s, "F" + convert.int_to_string(j), CMPL_SEV_INFO, "v0", CMPL_OP_INT_EQ, 999, 0);
    j = j + 1;
  }
  var f = eval_of(&mut s, &mut e, &mut w, 0);
  var ok = findings_len_of(&mut f) == 100;
  if count_of(&mut f, CMPL_PASS) != 60 { ok = false; }
  if count_of(&mut f, CMPL_VIOLATION) != 40 { ok = false; }
  if risk_of(&mut f) != 40 { ok = false; }
  if s.ids.len() != 100 { ok = false; }
  if s.enabled.len() != 100 { ok = false; }
  if e.names.len() != 60 { ok = false; }
  return assert(ok, "a 100-rule / 60-attribute fixture evaluates in one pass with aligned vectors");
}

fn t21() -> TestResult {
  var s = build_mixed_rules();
  var e = build_mixed_evidence();
  var w = build_mixed_waivers();
  var ok = rules_count_of(&mut s) == 4;
  s.subjects.pop();
  if rules_count_of(&mut s) != 3 { ok = false; }
  var f = eval_of(&mut s, &mut e, &mut w, 500);
  if findings_len_of(&mut f) != 3 { ok = false; }
  if outcome_of(&mut f, 0) != CMPL_PASS { ok = false; }
  if outcome_of(&mut f, 2) != CMPL_NOT_APPLICABLE { ok = false; }
  f.outcomes.pop();
  if findings_len_of(&mut f) != 2 { ok = false; }
  return assert(ok, "rule count and findings length are the shortest vector: drift can never overrun");
}

fn t22() -> TestResult {
  var ok = cmpl_pred_int(CMPL_OP_INT_RANGE, -10, -1, -5);
  if cmpl_pred_int(CMPL_OP_INT_RANGE, -10, -1, -11) { ok = false; }
  if cmpl_pred_int(CMPL_OP_INT_RANGE, -10, -1, 0) { ok = false; }
  if !cmpl_pred_int(CMPL_OP_INT_RANGE, 5, 5, 5) { ok = false; }
  if !cmpl_pred_str(CMPL_OP_STR_PREFIX, "", "x") { ok = false; }
  if !cmpl_pred_str(CMPL_OP_STR_CONTAINS, "", "x") { ok = false; }
  if !cmpl_pred_str(CMPL_OP_STR_EQ, "", "") { ok = false; }
  if cmpl_pred_str(CMPL_OP_STR_EQ, "", "x") { ok = false; }
  var w = cmpl_waivers_new();
  cmpl_waive(&mut w, "R-1", 10);
  if wactive_of(&mut w, "R-10", 5) { ok = false; }
  if !wactive_of(&mut w, "R-1", 5) { ok = false; }
  return assert(ok, "boundaries: negative ranges, degenerate range, empty operands, exact waiver ids");
}

fn main() -> Int {
  io.println("=== xiom.compliance conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.compliance: all tests passed");
  } else {
    io.println("xiom.compliance: tests failed");
  }
  return failed;
}
