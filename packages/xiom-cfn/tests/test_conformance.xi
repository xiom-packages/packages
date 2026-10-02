// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.cfn conformance tests (26 checks).
// Port task: prove the pure-XIOM xiom.cfn model -- the JSON-ish scanner,
// the template accessors, intrinsic evaluation, parameter/output handling,
// the stack state machine and change-set diffing -- with inline templates
// only (no files, no network, no clock; fully deterministic).
//
// All Str equality goes through compare.str_compare (BUG 17: `==` on Str
// values read from Vec[Str] elements lowers to a pointer comparison).
// Byte checks mask the widened byte ((byte_at as Int) & 0xFF).

module cfn_tests
use xiom.io; use xiom.test; use xiom.cfn;
use xiom.string; use xiom.string.compare; use xiom.convert;

// ---------------------------------------------------------------------------
// Str / byte helpers
// ---------------------------------------------------------------------------

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

fn byte_is(s: Str, i: Int, want: Int) -> Bool {
  if i < 0 || i >= s.len() {
    return false;
  }
  let b = (string.byte_at(s, i) as Int) & 0xFF;
  return b == want;
}

// ---------------------------------------------------------------------------
// JSON fixtures and evaluation helpers
// ---------------------------------------------------------------------------

fn empty_doc() -> JsonDoc {
  return JsonDoc{
    kinds: Vec[Int].new();
    ints: Vec[Int].new();
    counts: Vec[Int].new();
    texts: Vec[Str].new();
    kids: Vec[Int].new();
    root: -1;
  };
}

fn doc_of(text: Str) -> JsonDoc {
  let r = json_parse(text);
  match r {
    Ok(d) => { return d; },
    Err(_) => { return empty_doc(); },
  }
  return empty_doc();
}

fn doc_ok(text: Str) -> Bool {
  let r = json_parse(text);
  match r {
    Ok(_) => { return true; },
    Err(_) => { return false; },
  }
  return false;
}

fn doc_err_is(text: Str, want: Str) -> Bool {
  let r = json_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn ev(d: &JsonDoc, c: &CfnContext) -> Result[CfnValue, Str] {
  return cfn_eval(d, json_root(d), c);
}

fn ev_text(text: Str, c: &CfnContext) -> Str {
  let d = doc_of(text);
  let r = ev(&d, c);
  match r {
    Ok(v) => {
      if !cfn_value_is_scalar(&v) {
        return "";
      }
      return cfn_value_text(&v);
    },
    Err(_) => { return ""; },
  }
  return "";
}

fn ev_scalar_is(text: Str, c: &CfnContext, want: Str) -> Bool {
  return streq(ev_text(text, c), want);
}

fn ev_err_is(text: Str, c: &CfnContext, want: Str) -> Bool {
  let d = doc_of(text);
  let r = ev(&d, c);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn ev_list_len(text: Str, c: &CfnContext) -> Int {
  let d = doc_of(text);
  let r = ev(&d, c);
  match r {
    Ok(v) => {
      if cfn_value_is_scalar(&v) {
        return -1;
      }
      let items = cfn_value_items(&v);
      return items.len();
    },
    Err(_) => { return -2; },
  }
  return -2;
}

fn ev_list_item_is(text: Str, c: &CfnContext, i: Int, want: Str) -> Bool {
  let d = doc_of(text);
  let r = ev(&d, c);
  match r {
    Ok(v) => {
      let items = cfn_value_items(&v);
      if i < 0 || i >= items.len() {
        return false;
      }
      let got: Str = items[i];
      return streq(got, want);
    },
    Err(_) => { return false; },
  }
  return false;
}

fn render_of(text: Str) -> Str {
  let d = doc_of(text);
  return json_render(&d, json_root(&d));
}

// ---------------------------------------------------------------------------
// Template helpers
// ---------------------------------------------------------------------------

fn tmpl(text: Str) -> JsonDoc {
  let r = cfn_template_parse(text);
  match r {
    Ok(d) => { return d; },
    Err(_) => { return empty_doc(); },
  }
  return empty_doc();
}

fn tmpl_ok(text: Str) -> Bool {
  let r = cfn_template_parse(text);
  match r {
    Ok(_) => { return true; },
    Err(_) => { return false; },
  }
  return false;
}

fn tmpl_err_is(text: Str, want: Str) -> Bool {
  let r = cfn_template_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn out_is(ttext: Str, name: Str, c: &CfnContext, want: Str) -> Bool {
  let d = tmpl(ttext);
  let r = cfn_output_value(&d, name, c);
  match r {
    Ok(v) => { return streq(v, want); },
    Err(_) => { return false; },
  }
  return false;
}

fn out_err_is(ttext: Str, name: Str, c: &CfnContext, want: Str) -> Bool {
  let d = tmpl(ttext);
  let r = cfn_output_value(&d, name, c);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn eff_is(ttext: Str, name: Str, c: &CfnContext, want: Str) -> Bool {
  let d = tmpl(ttext);
  let r = cfn_parameter_effective(&d, name, c);
  match r {
    Ok(v) => { return streq(v, want); },
    Err(_) => { return false; },
  }
  return false;
}

fn eff_err_is(ttext: Str, name: Str, c: &CfnContext, want: Str) -> Bool {
  let d = tmpl(ttext);
  let r = cfn_parameter_effective(&d, name, c);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn valid_params(ttext: Str, c: &CfnContext) -> Bool {
  let d = tmpl(ttext);
  return cfn_parameters_valid(&d, c);
}

fn param_errs_len(ttext: Str, c: &CfnContext) -> Int {
  let d = tmpl(ttext);
  let errs = cfn_validate_parameters(&d, c);
  return errs.len();
}

fn param_err_is(ttext: Str, c: &CfnContext, i: Int, want: Str) -> Bool {
  let d = tmpl(ttext);
  let errs = cfn_validate_parameters(&d, c);
  if i < 0 || i >= errs.len() {
    return false;
  }
  let got: Str = errs[i];
  return streq(got, want);
}

// ---------------------------------------------------------------------------
// Context helpers
// ---------------------------------------------------------------------------

fn ctx0() -> CfnContext {
  return cfn_context_default();
}

fn ctx_param(c: &CfnContext, n: Str, v: Str) -> CfnContext {
  return cfn_context_set_parameter(c, n, v);
}

fn ctx_ref(c: &CfnContext, logical: Str, v: Str) -> CfnContext {
  return cfn_context_set_resource_ref(c, logical, v);
}

fn ctx_attr(c: &CfnContext, key: Str, v: Str) -> CfnContext {
  return cfn_context_set_attribute(c, key, v);
}

// ---------------------------------------------------------------------------
// Stack helpers
// ---------------------------------------------------------------------------

fn apply_ok(s: &Stack, event: Int) -> Stack {
  let r = stack_apply(s, event);
  match r {
    Ok(x) => { return x; },
    Err(_) => { return stack_new("?"); },
  }
  return stack_new("?");
}

fn apply_err_is(s: &Stack, event: Int, want: Str) -> Bool {
  let r = stack_apply(s, event);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t01() -> TestResult {
  let d = doc_of("[1, -2, true, false, null, \"x\"]");
  let root = json_root(&d);
  var ok = json_kind(&d, root) == JSON_ARR;
  if json_array_len(&d, root) != 6 { ok = false; }
  let n0 = json_array_get(&d, root, 0);
  if json_kind(&d, n0) != JSON_INT { ok = false; }
  if json_int(&d, n0) != 1 { ok = false; }
  if json_int(&d, json_array_get(&d, root, 1)) != -2 { ok = false; }
  let n2 = json_array_get(&d, root, 2);
  if json_kind(&d, n2) != JSON_BOOL { ok = false; }
  if !json_bool(&d, n2) { ok = false; }
  let n3 = json_array_get(&d, root, 3);
  if json_bool(&d, n3) { ok = false; }
  if json_kind(&d, json_array_get(&d, root, 4)) != JSON_NULL { ok = false; }
  if !streq(json_text(&d, json_array_get(&d, root, 5)), "x") { ok = false; }
  if json_kind(&d, 99) != CFN_NONE { ok = false; }
  if json_array_get(&d, root, 9) != CFN_NONE { ok = false; }
  return assert(ok, "json: scalars, kinds, array access, out-of-range sentinels");
}

fn t02() -> TestResult {
  let d = doc_of("{\"a\": [1, 2], \"b\": {\"c\": \"see\"}}");
  let root = json_root(&d);
  var ok = json_kind(&d, root) == JSON_OBJ;
  if json_member_count(&d, root) != 2 { ok = false; }
  if !streq(json_member_key(&d, root, 0), "a") { ok = false; }
  if !streq(json_member_key(&d, root, 1), "b") { ok = false; }
  let a = json_object_get(&d, root, "a");
  if json_array_len(&d, a) != 2 { ok = false; }
  if json_int(&d, json_array_get(&d, a, 1)) != 2 { ok = false; }
  let b = json_object_get(&d, root, "b");
  let c = json_object_get(&d, b, "c");
  if !streq(json_text(&d, c), "see") { ok = false; }
  if json_object_get(&d, root, "zz") != CFN_NONE { ok = false; }
  if json_member_value(&d, root, 1) != b { ok = false; }
  return assert(ok, "json: object members, nested lookup, key order");
}

fn t03() -> TestResult {
  let c = ctx0();
  var ok = ev_scalar_is("\"a\\nb\"", &c, "a\nb");
  if !ev_scalar_is("\"\\\"\\\"\"", &c, "\"\"") { ok = false; }
  if !ev_scalar_is("\"\\/\"", &c, "/") { ok = false; }
  if !ev_scalar_is("\"\\u0041\"", &c, "A") { ok = false; }
  let bs = ev_text("\"\\\\\"", &c);
  if bs.len() != 1 { ok = false; }
  if !byte_is(bs, 0, 92) { ok = false; }
  let tab = ev_text("\"\\t\"", &c);
  if tab.len() != 1 { ok = false; }
  if !byte_is(tab, 0, 9) { ok = false; }
  let bell = ev_text("\"\\b\"", &c);
  if !byte_is(bell, 0, 8) { ok = false; }
  let form = ev_text("\"\\f\"", &c);
  if !byte_is(form, 0, 12) { ok = false; }
  let cr = ev_text("\"\\r\"", &c);
  if !byte_is(cr, 0, 13) { ok = false; }
  let eacute = ev_text("\"\\u00e9\"", &c);
  if eacute.len() != 2 { ok = false; }
  if !byte_is(eacute, 0, 0xC3) { ok = false; }
  if !byte_is(eacute, 1, 0xA9) { ok = false; }
  let raw = ev_text("\"é\"", &c);
  if raw.len() != 2 { ok = false; }
  if !byte_is(raw, 0, 0xC3) { ok = false; }
  if !byte_is(raw, 1, 0xA9) { ok = false; }
  return assert(ok, "json strings: escapes, BMP unicode, raw UTF-8 byte round-trip");
}

fn t04() -> TestResult {
  var ok = doc_err_is("{", "cfn: unterminated object");
  if !doc_err_is("[1,", "cfn: unterminated array") { ok = false; }
  if !doc_err_is("\"abc", "cfn: unterminated string") { ok = false; }
  if !doc_err_is("\"a\\q\"", "cfn: invalid escape sequence in string") { ok = false; }
  if !doc_err_is("\"a\nb\"", "cfn: control character in JSON string") { ok = false; }
  if !doc_err_is("01", "cfn: invalid number") { ok = false; }
  if !doc_err_is("1.5", "cfn: invalid number (only integers are supported)") { ok = false; }
  if !doc_err_is("1e3", "cfn: invalid number (only integers are supported)") { ok = false; }
  if !doc_err_is("tru", "cfn: invalid literal") { ok = false; }
  if !doc_err_is("{} {}", "cfn: trailing data after JSON value") { ok = false; }
  if !doc_err_is("[1,]", "cfn: trailing comma in array") { ok = false; }
  if !doc_err_is("{\"a\":1,}", "cfn: trailing comma in object") { ok = false; }
  if !doc_err_is("{a:1}", "cfn: object key must be a string") { ok = false; }
  if !doc_err_is("{\"a\" 1}", "cfn: expected ':' in object") { ok = false; }
  if !doc_err_is("{\"a\":1 \"b\":2}", "cfn: expected ',' or '}' in object") { ok = false; }
  if !doc_err_is("[1 2]", "cfn: expected ',' or ']' in array") { ok = false; }
  if !doc_err_is("+", "cfn: unexpected character in JSON") { ok = false; }
  if !doc_err_is("\"\\ud800\"", "cfn: unsupported unicode escape (surrogate)") { ok = false; }
  if !doc_err_is("\"\\u0000\"", "cfn: unsupported unicode escape (NUL)") { ok = false; }
  if !doc_err_is("\"\\u12\"", "cfn: invalid unicode escape") { ok = false; }
  return assert(ok, "json errors: scanner diagnostics are stable and exact");
}

fn deep_array(n: Int) -> Str {
  var s = "";
  var i = 0;
  while i < n {
    s = s + "[";
    i = i + 1;
  }
  i = 0;
  while i < n {
    s = s + "]";
    i = i + 1;
  }
  return s;
}

fn t05() -> TestResult {
  var ok = doc_ok(deep_array(10));
  if !doc_ok(deep_array(64)) { ok = false; }
  if !doc_err_is(deep_array(70), "cfn: JSON nesting too deep") { ok = false; }
  return assert(ok, "json: nesting is bounded at the documented depth cap");
}

fn t06() -> TestResult {
  var ok = streq(render_of("{\"a\":[1,true,null,\"x\\n\"],\"b\":-2}"), "{\"a\":[1,true,null,\"x\\n\"],\"b\":-2}");
  if !streq(render_of("{\"b\":1,\"a\":2}"), "{\"b\":1,\"a\":2}") { ok = false; }
  let d1 = doc_of("{\"a\":[1,true,null,\"x\\n\"],\"b\":-2}");
  let first = json_render(&d1, json_root(&d1));
  let d2 = doc_of(first);
  let second = json_render(&d2, json_root(&d2));
  if !streq(first, second) { ok = false; }
  if !json_equal(&d1, json_root(&d1), &d2, json_root(&d2)) { ok = false; }
  return assert(ok, "json: canonical render is stable and parse -> render -> parse round-trips");
}

fn t07() -> TestResult {
  var ok = tmpl_err_is("[]", "cfn: template root must be an object");
  if !tmpl_err_is("{}", "cfn: template is missing the Resources section") { ok = false; }
  if !tmpl_err_is("{\"Resources\":[]}", "cfn: Resources must be an object") { ok = false; }
  if !tmpl_err_is("{\"Resources\":{\"R\":[]}}", "cfn: resource R must be an object") { ok = false; }
  if !tmpl_err_is("{\"Resources\":{\"R\":{}}}", "cfn: resource R is missing Type") { ok = false; }
  if !tmpl_err_is("{\"Resources\":{\"R\":{\"Type\":1}}}", "cfn: resource R Type must be a string") { ok = false; }
  if !tmpl_ok("{\"Resources\":{\"R\":{\"Type\":\"AWS::S3::Bucket\"}}}") { ok = false; }
  if !tmpl_err_is("{bad", "cfn: object key must be a string") { ok = false; }
  return assert(ok, "template: root/Resources/Type validation errors are exact");
}

fn t08() -> TestResult {
  let t = "{\"AWSTemplateFormatVersion\":\"2010-09-09\",\"Parameters\":{\"Env\":{\"Type\":\"String\"},\"Count\":{\"Type\":\"Number\",\"Default\":\"3\"}},\"Conditions\":{\"IsProd\":{\"Fn::Equals\":[{\"Ref\":\"Env\"},\"prod\"]}},\"Resources\":{\"B\":{\"Type\":\"T\",\"Properties\":{\"x\":1}}},\"Outputs\":{\"O\":{\"Description\":\"d\",\"Value\":\"v\"}}}";
  let d = tmpl(t);
  var ok = cfn_resource_count(&d) == 1;
  if !streq(cfn_resource_id(&d, 0), "B") { ok = false; }
  if !streq(cfn_resource_type(&d, "B"), "T") { ok = false; }
  if !streq(cfn_resource_type(&d, "Zz"), "") { ok = false; }
  if cfn_resource_properties(&d, "B") < 0 { ok = false; }
  if cfn_parameter_count(&d) != 2 { ok = false; }
  if !streq(cfn_parameter_name(&d, 1), "Count") { ok = false; }
  if !streq(cfn_parameter_type(&d, "Count"), "Number") { ok = false; }
  if !streq(cfn_parameter_type(&d, "Env"), "String") { ok = false; }
  if !streq(cfn_parameter_type(&d, "Zz"), "") { ok = false; }
  if !opt_is(cfn_parameter_default(&d, "Count"), "3") { ok = false; }
  if !opt_none(cfn_parameter_default(&d, "Env")) { ok = false; }
  if !opt_none(cfn_parameter_default(&d, "Zz")) { ok = false; }
  if cfn_condition_count(&d) != 1 { ok = false; }
  if !streq(cfn_condition_name(&d, 0), "IsProd") { ok = false; }
  if cfn_output_count(&d) != 1 { ok = false; }
  if !streq(cfn_output_name(&d, 0), "O") { ok = false; }
  return assert(ok, "template: section accessors, parameter/condition/output names");
}

fn t09() -> TestResult {
  let t = "{\"Parameters\":{\"Env\":{\"Type\":\"String\",\"Default\":\"prod\"}},\"Resources\":{},\"Outputs\":{\"O\":{\"Value\":{\"Ref\":\"Env\"}}}}";
  let c = ctx0();
  var ok = out_is(t, "O", &c, "prod");
  let c2 = ctx_param(&c, "Env", "dev");
  if !out_is(t, "O", &c2, "dev") { ok = false; }
  let t2 = "{\"Parameters\":{\"Name\":{\"Type\":\"String\"}},\"Resources\":{},\"Outputs\":{\"O\":{\"Value\":{\"Ref\":\"Name\"}}}}";
  if !out_err_is(t2, "O", &c2, "cfn: parameter has no value: Name") { ok = false; }
  let t3 = "{\"Resources\":{},\"Outputs\":{\"O\":{\"Value\":{\"Ref\":\"Nope\"}}}}";
  if !out_err_is(t3, "O", &c, "cfn: unresolved Ref: Nope") { ok = false; }
  let t4 = "{\"Parameters\":{\"N\":{\"Type\":\"CommaDelimitedList\",\"Default\":[\"a\",\"b\"]}},\"Resources\":{},\"Outputs\":{\"O\":{\"Value\":{\"Ref\":\"N\"}}}}";
  if !out_is(t4, "O", &c, "a,b") { ok = false; }
  return assert(ok, "Ref: defaults, overrides, required errors, list defaults join");
}

fn t10() -> TestResult {
  let t = "{\"Resources\":{\"B\":{\"Type\":\"T\"}},\"Outputs\":{\"O\":{\"Value\":{\"Ref\":\"B\"}}}}";
  let c = ctx0();
  var ok = out_is(t, "O", &c, "B");
  let c2 = ctx_ref(&c, "B", "bucket-123");
  if !out_is(t, "O", &c2, "bucket-123") { ok = false; }
  if !out_is(t, "O", &c, "B") { ok = false; }
  let t2 = "{\"Parameters\":{\"P\":{\"Type\":\"String\",\"Default\":\"pv\"}},\"Resources\":{\"B\":{\"Type\":\"T\"}},\"Outputs\":{\"O\":{\"Value\":{\"Fn::Join\":[\"|\",[{\"Ref\":\"P\"},{\"Ref\":\"AWS::Region\"},{\"Ref\":\"AWS::StackName\"},{\"Ref\":\"AWS::AccountId\"}]]}}}}";
  if !out_is(t2, "O", &c, "pv|us-east-1|demo-stack|123456789012") { ok = false; }
  return assert(ok, "Ref: resources (override/physical id) and pseudo-parameters");
}

fn t11() -> TestResult {
  let t = "{\"Resources\":{\"B\":{\"Type\":\"T\"}},\"Outputs\":{\"A\":{\"Value\":{\"Fn::GetAtt\":[\"B\",\"Arn\"]}},\"S\":{\"Value\":{\"Fn::GetAtt\":\"B.Arn\"}}}}";
  let c = ctx0();
  var ok = out_is(t, "A", &c, "B.Arn");
  if !out_is(t, "S", &c, "B.Arn") { ok = false; }
  let c2 = ctx_attr(&c, "B.Arn", "arn:custom");
  if !out_is(t, "A", &c2, "arn:custom") { ok = false; }
  let t2 = "{\"Resources\":{},\"Outputs\":{\"O\":{\"Value\":{\"Fn::GetAtt\":[\"X\",\"Arn\"]}}}}";
  if !out_err_is(t2, "O", &c, "cfn: unknown resource in Fn::GetAtt: X") { ok = false; }
  let t3 = "{\"Resources\":{\"B\":{\"Type\":\"T\"}},\"Outputs\":{\"O\":{\"Value\":{\"Fn::GetAtt\":\"NoDot\"}}}}";
  if !out_err_is(t3, "O", &c, "cfn: Fn::GetAtt expects 'Logical.Attr' or [logical, attribute]") { ok = false; }
  return assert(ok, "Fn::GetAtt: array and dotted-string forms, overrides, errors");
}

fn t12() -> TestResult {
  let c = ctx0();
  var ok = ev_scalar_is("{\"Fn::Join\":[\"-\",[\"a\",{\"Fn::Join\":[\"\",[\"b\",\"c\"]]}]]}", &c, "a-bc");
  if !ev_scalar_is("{\"Fn::Join\":[\"-\",[]]}", &c, "") { ok = false; }
  if !ev_err_is("{\"Fn::Join\":[\"-\",\"x\"]}", &c, "cfn: Fn::Join list must resolve to a list") { ok = false; }
  if !ev_err_is("{\"Fn::Join\":[\"-\",[[\"x\"]]]}", &c, "cfn: value must resolve to a scalar") { ok = false; }
  if !ev_err_is("{\"Fn::Join\":\"x\"}", &c, "cfn: Fn::Join expects [delimiter, list]") { ok = false; }
  return assert(ok, "Fn::Join: delimiter, nested intrinsics, empty list, errors");
}

fn t13() -> TestResult {
  let c = ctx0();
  var ok = ev_scalar_is("{\"Fn::Sub\":\"${AWS::Region}-x\"}", &c, "us-east-1-x");
  if !ev_scalar_is("{\"Fn::Sub\":\"${!Literal}\"}", &c, "${Literal}") { ok = false; }
  if !ev_scalar_is("{\"Fn::Sub\":[\"${a}-${b}\",{\"a\":\"1\",\"b\":{\"Ref\":\"AWS::StackName\"}}]}", &c, "1-demo-stack") { ok = false; }
  if !ev_err_is("{\"Fn::Sub\":\"${Oops\"}", &c, "cfn: malformed Fn::Sub: missing '}'") { ok = false; }
  if !ev_err_is("{\"Fn::Sub\":\"${Nope}\"}", &c, "cfn: unresolved Ref: Nope") { ok = false; }
  let t = "{\"Parameters\":{\"Env\":{\"Type\":\"String\",\"Default\":\"prod\"}},\"Resources\":{\"B\":{\"Type\":\"T\"}},\"Outputs\":{\"O\":{\"Value\":{\"Fn::Sub\":\"env=${Env} res=${B.Arn}\"}}}}";
  if !out_is(t, "O", &c, "env=prod res=B.Arn") { ok = false; }
  return assert(ok, "Fn::Sub: refs, attributes, escapes, vars, errors");
}

fn t14() -> TestResult {
  let c = ctx0();
  var ok = ev_list_len("{\"Fn::Split\":[\",\",\"a,b,\"]}", &c) == 3;
  if !ev_list_item_is("{\"Fn::Split\":[\",\",\"a,b,\"]}", &c, 2, "") { ok = false; }
  if !ev_list_item_is("{\"Fn::Split\":[\",\",\"\"]}", &c, 0, "") { ok = false; }
  if !ev_scalar_is("{\"Fn::Select\":[1,{\"Fn::Split\":[\"/\",\"a/b/c\"]}]}", &c, "b") { ok = false; }
  if !ev_scalar_is("{\"Fn::Select\":[\"0\",[\"x\",\"y\"]]}", &c, "x") { ok = false; }
  if !ev_err_is("{\"Fn::Split\":[\"\",\"ab\"]}", &c, "cfn: Fn::Split delimiter must not be empty") { ok = false; }
  if !ev_err_is("{\"Fn::Select\":[3,[\"x\"]]}", &c, "cfn: Fn::Select index out of range: 3") { ok = false; }
  if !ev_err_is("{\"Fn::Select\":[\"z\",[\"x\"]]}", &c, "cfn: Fn::Select index must be an integer: z") { ok = false; }
  if !ev_err_is("{\"Fn::Select\":[0,\"x\"]}", &c, "cfn: Fn::Select second argument must resolve to a list") { ok = false; }
  return assert(ok, "Fn::Split and Fn::Select: semantics and error catalog");
}

fn t15() -> TestResult {
  let t = "{\"Parameters\":{\"Env\":{\"Type\":\"String\",\"Default\":\"prod\"}},\"Conditions\":{\"IsProd\":{\"Fn::Equals\":[{\"Ref\":\"Env\"},\"prod\"]}},\"Resources\":{},\"Outputs\":{\"T\":{\"Value\":{\"Fn::If\":[\"IsProd\",\"yes\",\"no\"]}}}}";
  var ok = out_is(t, "T", &ctx0(), "yes");
  if !out_is(t, "T", &ctx_param(&ctx0(), "Env", "dev"), "no") { ok = false; }
  if !ev_scalar_is("{\"Fn::Equals\":[\"a\",\"a\"]}", &ctx0(), "true") { ok = false; }
  if !ev_scalar_is("{\"Fn::Equals\":[\"a\",\"b\"]}", &ctx0(), "false") { ok = false; }
  let t2 = "{\"Conditions\":{\"C\":{\"Fn::Equals\":[\"a\",\"a\"]}},\"Resources\":{},\"Outputs\":{\"O\":{\"Value\":{\"Fn::If\":[\"Nope\",\"y\",\"n\"]}}}}";
  if !out_err_is(t2, "O", &ctx0(), "cfn: unknown condition: Nope") { ok = false; }
  let t3 = "{\"Conditions\":{\"C1\":{\"Condition\":\"C2\"},\"C2\":{\"Condition\":\"C1\"}},\"Resources\":{},\"Outputs\":{\"O\":{\"Value\":{\"Fn::If\":[\"C1\",\"y\",\"n\"]}}}}";
  if !out_err_is(t3, "O", &ctx0(), "cfn: cyclic reference: C1") { ok = false; }
  return assert(ok, "Fn::If / Fn::Equals: branches, unknown condition, cycle rejection");
}

fn cond_chain(n: Int) -> Str {
  var s = "{\"Conditions\":{";
  var i = 0;
  while i < n - 1 {
    s = s + "\"C" + convert.int_to_string(i) + "\":{\"Condition\":\"C" + convert.int_to_string(i + 1) + "\"},";
    i = i + 1;
  }
  s = s + "\"C" + convert.int_to_string(n - 1) + "\":{\"Fn::Equals\":[\"a\",\"a\"]}},";
  s = s + "\"Resources\":{},\"Outputs\":{\"O\":{\"Value\":{\"Fn::If\":[\"C0\",\"y\",\"n\"]}}}}";
  return s;
}

fn t16() -> TestResult {
  var ok = out_is(cond_chain(3), "O", &ctx0(), "y");
  if !out_err_is(cond_chain(80), "O", &ctx0(), "cfn: intrinsic resolution depth exceeded") { ok = false; }
  return assert(ok, "condition chains: short chain resolves, long chain hits the depth cap");
}

fn t17() -> TestResult {
  let t = "{\"Mappings\":{\"M\":{\"T\":{\"S\":\"v\",\"L\":[\"a\",\"b\"]}}},\"Resources\":{},\"Outputs\":{\"S\":{\"Value\":{\"Fn::FindInMap\":[\"M\",\"T\",\"S\"]}},\"L\":{\"Value\":{\"Fn::Select\":[1,{\"Fn::FindInMap\":[\"M\",\"T\",\"L\"]}]}}}}";
  let c = ctx0();
  var ok = out_is(t, "S", &c, "v");
  if !out_is(t, "L", &c, "b") { ok = false; }
  let t2 = "{\"Mappings\":{\"M\":{\"T\":{\"S\":\"v\"}}},\"Resources\":{},\"Outputs\":{\"O\":{\"Value\":{\"Fn::FindInMap\":[\"M\",\"T\",\"Zz\"]}}}}";
  if !out_err_is(t2, "O", &c, "cfn: mapping key not found: M/T/Zz") { ok = false; }
  let t3 = "{\"Mappings\":{},\"Resources\":{},\"Outputs\":{\"O\":{\"Value\":{\"Fn::FindInMap\":[\"Z\",\"T\",\"S\"]}}}}";
  if !out_err_is(t3, "O", &c, "cfn: mapping not found: Z") { ok = false; }
  let t4 = "{\"Mappings\":{\"M\":{\"T\":{\"S\":\"v\"}}},\"Resources\":{},\"Outputs\":{\"O\":{\"Value\":{\"Fn::FindInMap\":[{\"Ref\":\"AWS::Region\"},\"T\",\"S\"]}}}}";
  if !out_err_is(t4, "O", &c, "cfn: mapping not found: us-east-1") { ok = false; }
  return assert(ok, "Fn::FindInMap: scalar/list values, intrinsic keys, missing-map errors");
}

fn t18() -> TestResult {
  let t = "{\"Parameters\":{\"Env\":{\"Type\":\"String\"},\"Count\":{\"Type\":\"Number\",\"Default\":\"3\"},\"Tags\":{\"Type\":\"CommaDelimitedList\",\"Default\":[\"a\",\"b\"]}},\"Resources\":{}}";
  let c = ctx0();
  var ok = param_errs_len(t, &c) == 1;
  if !param_err_is(t, &c, 0, "cfn: missing required parameter: Env") { ok = false; }
  if !valid_params(t, &ctx_param(&c, "Env", "x")) { ok = false; }
  let c2 = ctx_param(&ctx_param(&c, "Env", "x"), "Zz", "1");
  if param_errs_len(t, &c2) != 1 { ok = false; }
  if !param_err_is(t, &c2, 0, "cfn: unknown parameter: Zz") { ok = false; }
  let c3 = ctx_param(&ctx_param(&c, "Env", "x"), "Count", "abc");
  if !param_err_is(t, &c3, 0, "cfn: parameter Count must be an integer: abc") { ok = false; }
  if !eff_is(t, "Tags", &c, "a,b") { ok = false; }
  if !eff_err_is(t, "Env", &c, "cfn: parameter has no value: Env") { ok = false; }
  if !eff_is(t, "Count", &c, "3") { ok = false; }
  return assert(ok, "parameters: required/unknown/Number validation and effective values");
}

fn t19() -> TestResult {
  let t = "{\"Resources\":{},\"Outputs\":{\"O1\":{\"Description\":\"d\",\"Value\":{\"Fn::Join\":[\"-\",[\"a\",\"b\"]]}},\"O2\":{\"Value\":[\"a\"]},\"O3\":{\"Value\":\"v\",\"Export\":{\"Name\":{\"Fn::Sub\":\"${AWS::StackName}-x\"}}}}}";
  let d = tmpl(t);
  let c = ctx0();
  var ok = out_is(t, "O1", &c, "a-b");
  if !opt_is(cfn_output_description(&d, "O1"), "d") { ok = false; }
  if !opt_none(cfn_output_description(&d, "O2")) { ok = false; }
  if !out_err_is(t, "O2", &c, "cfn: output value must resolve to a scalar: O2") { ok = false; }
  if !out_err_is(t, "Zz", &c, "cfn: unknown output: Zz") { ok = false; }
  let er = cfn_output_export_name(&d, "O3", &c);
  match er {
    Ok(v) => { if !streq(v, "demo-stack-x") { ok = false; } },
    Err(_) => { ok = false; },
  }
  let er2 = cfn_output_export_name(&d, "O1", &c);
  match er2 {
    Ok(_) => { ok = false; },
    Err(e) => { if !streq(e, "cfn: output has no export: O1") { ok = false; } },
  }
  return assert(ok, "outputs: values, descriptions, exports and scalar enforcement");
}

fn t20() -> TestResult {
  let s0 = stack_new("demo");
  var ok = s0.state == STACK_NOT_CREATED;
  if stack_history_len(&s0) != 0 { ok = false; }
  let s1 = apply_ok(&s0, STACK_EV_CREATE_BEGIN);
  if s1.state != STACK_CREATE_IN_PROGRESS { ok = false; }
  let s2 = apply_ok(&s1, STACK_EV_SUCCEED);
  if s2.state != STACK_CREATE_COMPLETE { ok = false; }
  let r1 = apply_ok(&s1, STACK_EV_FAIL);
  if r1.state != STACK_ROLLBACK_IN_PROGRESS { ok = false; }
  let r2 = apply_ok(&r1, STACK_EV_SUCCEED);
  if r2.state != STACK_ROLLBACK_COMPLETE { ok = false; }
  let f1 = apply_ok(&r1, STACK_EV_FAIL);
  if f1.state != STACK_ROLLBACK_FAILED { ok = false; }
  if stack_history_len(&f1) != 3 { ok = false; }
  if stack_history_event(&f1, 0) != STACK_EV_CREATE_BEGIN { ok = false; }
  if stack_history_event(&f1, 1) != STACK_EV_FAIL { ok = false; }
  if stack_history_state(&f1, 1) != STACK_ROLLBACK_IN_PROGRESS { ok = false; }
  if stack_history_state(&f1, 2) != STACK_ROLLBACK_FAILED { ok = false; }
  if !streq(stack_state_name(STACK_CREATE_COMPLETE), "CREATE_COMPLETE") { ok = false; }
  if !streq(stack_event_name(STACK_EV_FAIL), "FAIL") { ok = false; }
  return assert(ok, "stack: create success, auto-rollback success and rollback failure");
}

fn t21() -> TestResult {
  let s0 = stack_new("demo");
  let s1 = apply_ok(&s0, STACK_EV_CREATE_BEGIN);
  let s2 = apply_ok(&s1, STACK_EV_SUCCEED);
  let u1 = apply_ok(&s2, STACK_EV_UPDATE_BEGIN);
  var ok = u1.state == STACK_UPDATE_IN_PROGRESS;
  let u2 = apply_ok(&u1, STACK_EV_SUCCEED);
  if u2.state != STACK_UPDATE_COMPLETE { ok = false; }
  let u3 = apply_ok(&u2, STACK_EV_UPDATE_BEGIN);
  let u4 = apply_ok(&u3, STACK_EV_FAIL);
  if u4.state != STACK_UPDATE_ROLLBACK_IN_PROGRESS { ok = false; }
  let u5 = apply_ok(&u4, STACK_EV_FAIL);
  if u5.state != STACK_UPDATE_ROLLBACK_FAILED { ok = false; }
  let u6 = apply_ok(&u4, STACK_EV_SUCCEED);
  if u6.state != STACK_UPDATE_ROLLBACK_COMPLETE { ok = false; }
  let u7 = apply_ok(&u6, STACK_EV_UPDATE_BEGIN);
  if u7.state != STACK_UPDATE_IN_PROGRESS { ok = false; }
  let d1 = apply_ok(&u2, STACK_EV_DELETE_BEGIN);
  if d1.state != STACK_DELETE_IN_PROGRESS { ok = false; }
  let d2 = apply_ok(&d1, STACK_EV_SUCCEED);
  if d2.state != STACK_DELETE_COMPLETE { ok = false; }
  let d3 = apply_ok(&d1, STACK_EV_FAIL);
  if d3.state != STACK_DELETE_FAILED { ok = false; }
  let d4 = apply_ok(&d3, STACK_EV_DELETE_BEGIN);
  if d4.state != STACK_DELETE_IN_PROGRESS { ok = false; }
  return assert(ok, "stack: update, update-rollback and delete paths");
}

fn t22() -> TestResult {
  let s0 = stack_new("demo");
  let r1 = apply_ok(&s0, STACK_EV_REVIEW_BEGIN);
  var ok = r1.state == STACK_REVIEW_IN_PROGRESS;
  if !stack_is_busy(r1.state) { ok = false; }
  let r2 = apply_ok(&r1, STACK_EV_CREATE_BEGIN);
  if r2.state != STACK_CREATE_IN_PROGRESS { ok = false; }
  let done = apply_ok(&r2, STACK_EV_SUCCEED);
  if !apply_err_is(&done, STACK_EV_SUCCEED, "cfn: stack cannot apply SUCCEED in state CREATE_COMPLETE") { ok = false; }
  if !apply_err_is(&done, STACK_EV_CREATE_BEGIN, "cfn: stack cannot apply CREATE_BEGIN in state CREATE_COMPLETE") { ok = false; }
  let del = apply_ok(&done, STACK_EV_DELETE_BEGIN);
  let del2 = apply_ok(&del, STACK_EV_SUCCEED);
  if !apply_err_is(&del2, STACK_EV_DELETE_BEGIN, "cfn: stack cannot apply DELETE_BEGIN in state DELETE_COMPLETE") { ok = false; }
  if !stack_is_failed(STACK_UPDATE_ROLLBACK_FAILED) { ok = false; }
  if stack_is_failed(STACK_CREATE_COMPLETE) { ok = false; }
  if !streq(stack_state_name(999), "UNKNOWN") { ok = false; }
  if !streq(stack_event_name(999), "UNKNOWN") { ok = false; }
  return assert(ok, "stack: review flow, forbidden transitions, busy/failed predicates");
}

fn t23() -> TestResult {
  let old = doc_of("{\"Resources\":{\"A\":{\"Type\":\"T\",\"Properties\":{\"x\":1}},\"B\":{\"Type\":\"T\",\"Properties\":{\"p\":1}},\"C\":{\"Type\":\"T\"},\"D\":{\"Type\":\"T\"}}}");
  let newd = doc_of("{\"Resources\":{\"A\":{\"Type\":\"T\",\"Properties\":{\"x\":1}},\"B\":{\"Type\":\"T\",\"Properties\":{\"p\":2}},\"C\":{\"Type\":\"U\"},\"E\":{\"Type\":\"T\"}}}");
  let cs = changeset_compute(&old, &newd);
  var ok = changeset_len(&cs) == 5;
  if changeset_kind(&cs, 0) != CHANGE_NONE { ok = false; }
  if changeset_kind(&cs, 1) != CHANGE_MODIFY { ok = false; }
  if changeset_kind(&cs, 2) != CHANGE_MODIFY { ok = false; }
  if !changeset_is_replacement(&cs, 2) { ok = false; }
  if changeset_is_replacement(&cs, 1) { ok = false; }
  if changeset_kind(&cs, 3) != CHANGE_REMOVE { ok = false; }
  if changeset_kind(&cs, 4) != CHANGE_ADD { ok = false; }
  if !streq(changeset_logical(&cs, 4), "E") { ok = false; }
  if !streq(changeset_old_type(&cs, 2), "T") { ok = false; }
  if !streq(changeset_new_type(&cs, 2), "U") { ok = false; }
  if !streq(changeset_old_type(&cs, 4), "") { ok = false; }
  if changeset_count(&cs, CHANGE_MODIFY) != 2 { ok = false; }
  if changeset_count(&cs, CHANGE_NONE) != 1 { ok = false; }
  if !changeset_has_changes(&cs) { ok = false; }
  if !streq(changeset_kind_name(CHANGE_ADD), "ADD") { ok = false; }
  if !streq(changeset_kind_name(CHANGE_MODIFY), "MODIFY") { ok = false; }
  return assert(ok, "change sets: ADD/REMOVE/MODIFY/NONE, types and replacements");
}

fn t24() -> TestResult {
  let a1 = doc_of("{\"Resources\":{\"R\":{\"Type\":\"T\",\"Properties\":{\"a\":1,\"b\":{\"c\":2,\"d\":[1,2]}}}}}");
  let a2 = doc_of("{\"Resources\":{\"R\":{\"Type\":\"T\",\"Properties\":{\"b\":{\"d\":[1,2],\"c\":2},\"a\":1}}}}");
  let cs1 = changeset_compute(&a1, &a2);
  var ok = changeset_len(&cs1) == 1;
  if changeset_kind(&cs1, 0) != CHANGE_NONE { ok = false; }
  let b1 = doc_of("{\"Resources\":{\"R\":{\"Type\":\"T\",\"Properties\":{\"a\":1}}}}");
  let b2 = doc_of("{\"Resources\":{\"R\":{\"Type\":\"T\",\"Properties\":{\"a\":2}}}}");
  let cs2 = changeset_compute(&b1, &b2);
  if changeset_kind(&cs2, 0) != CHANGE_MODIFY { ok = false; }
  if changeset_is_replacement(&cs2, 0) { ok = false; }
  let c1 = doc_of("{\"Resources\":{\"R\":{\"Type\":\"T\",\"Properties\":{\"a\":[1,2]}}}}");
  let c2 = doc_of("{\"Resources\":{\"R\":{\"Type\":\"T\",\"Properties\":{\"a\":[1,2,3]}}}}");
  let cs3 = changeset_compute(&c1, &c2);
  if changeset_kind(&cs3, 0) != CHANGE_MODIFY { ok = false; }
  let empty1 = doc_of("{\"Resources\":{}}");
  let empty2 = doc_of("{\"Resources\":{}}");
  let cs4 = changeset_compute(&empty1, &empty2);
  if changeset_len(&cs4) != 0 { ok = false; }
  if changeset_has_changes(&cs4) { ok = false; }
  if !streq(changeset_kind_name(999), "UNKNOWN") { ok = false; }
  return assert(ok, "change sets: key-order insensitivity, deep diff, no-op diffs");
}

fn t25() -> TestResult {
  let t = "{\"Parameters\":{\"Env\":{\"Type\":\"String\",\"Default\":\"prod\"}},\"Mappings\":{\"RegionMap\":{\"us-east-1\":{\"ami\":\"ami-123\"}}},\"Conditions\":{\"IsProd\":{\"Fn::Equals\":[{\"Ref\":\"Env\"},\"prod\"]}},\"Resources\":{\"Bucket\":{\"Type\":\"AWS::S3::Bucket\",\"Properties\":{\"Name\":\"b\"}}},\"Outputs\":{\"Ami\":{\"Value\":{\"Fn::FindInMap\":[\"RegionMap\",{\"Ref\":\"AWS::Region\"},\"ami\"]}},\"Msg\":{\"Value\":{\"Fn::If\":[\"IsProd\",{\"Fn::Join\":[\"-\",[\"env\",\"prod\"]]},{\"Fn::Sub\":\"env=${Env}\"}]}}}}";
  let d = tmpl(t);
  let c = ctx0();
  var ok = cfn_parameters_valid(&d, &c);
  let o1 = cfn_output_value(&d, "Ami", &c);
  match o1 {
    Ok(v) => { if !streq(v, "ami-123") { ok = false; } },
    Err(_) => { ok = false; },
  }
  let o2 = cfn_output_value(&d, "Msg", &c);
  match o2 {
    Ok(v) => { if !streq(v, "env-prod") { ok = false; } },
    Err(_) => { ok = false; },
  }
  if !out_is(t, "Msg", &ctx_param(&c, "Env", "dev"), "env=dev") { ok = false; }
  let t2 = "{\"Resources\":{\"Bucket\":{\"Type\":\"AWS::S3::Bucket\",\"Properties\":{\"Name\":\"b2\"}}}}";
  let d2 = tmpl(t2);
  let cs = changeset_compute(&d, &d2);
  if changeset_len(&cs) != 1 { ok = false; }
  if changeset_kind(&cs, 0) != CHANGE_MODIFY { ok = false; }
  let r1 = json_render(&d, json_root(&d));
  let r2 = json_render(&d, json_root(&d));
  if !streq(r1, r2) { ok = false; }
  let v1 = cfn_output_value(&d, "Ami", &c);
  let v2 = cfn_output_value(&d, "Ami", &c);
  match v1 {
    Ok(a) => {
      match v2 {
        Ok(b) => { if !streq(a, b) { ok = false; } },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "end-to-end template: params, map, condition, outputs, diff, determinism");
}

fn t26() -> TestResult {
  let c = ctx0();
  var ok = streq(render_of("\"\\u00e9\""), render_of("\"é\""));
  if !streq(render_of("\"\\u0041\\n\""), "\"A\\n\"") { ok = false; }
  let d1 = doc_of("{\"k\":\"\\u00e9\\t\\\"\",\"n\":-7,\"b\":false,\"z\":null}");
  let r1 = json_render(&d1, json_root(&d1));
  let d2 = doc_of(r1);
  let r2 = json_render(&d2, json_root(&d2));
  if !streq(r1, r2) { ok = false; }
  if !json_equal(&d1, json_root(&d1), &d2, json_root(&d2)) { ok = false; }
  let s = ev_text("\"\\u00e9\"", &c);
  if s.len() != 2 { ok = false; }
  if !byte_is(s, 0, 0xC3) { ok = false; }
  if !byte_is(s, 1, 0xA9) { ok = false; }
  let s2 = ev_text("\"é\"", &c);
  if !streq(s, s2) { ok = false; }
  return assert(ok, "bytes: unicode escape canonicalization and full render round-trip");
}

fn main() -> Int {
  io.println("=== xiom.cfn conformance tests ===");
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
    io.println("xiom.cfn: all tests passed");
  } else {
    io.println("xiom.cfn: tests failed");
  }
  return failed;
}
