// XIOM -- xiom.jev.request: the System One request builder
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// build_request turns (model, state, questions) into the JSON body of a
// POST https://api.typesafe.ai/v1/systemone request, mirroring the schema at
// https://api.typesafe.ai/openapi.json (SystemOneRequest): the body is
// {"state": ..., "model": ..., "questions": {...}} with question objects
// {"type","instructions","criteria"}; Choice criteria is an object of
// option -> description (an empty description is emitted as null), Score
// criteria is an ordered array of level descriptions, Noul carries the
// optional true/false criteria object. JSON is produced with
// xiom.serialize.json (compact, insertion-ordered keys, so the same inputs
// always produce the same bytes).
//
// Fail-closed validation (all rejections are JevError.BadRequest, exact
// strings pinned in SPEC.md section 6): model non-empty; state non-empty
// (text states only; an empty JSON document is allowed); at least one
// question; per question: non-empty id, no duplicate ids, non-empty
// instructions; Choice: 1..255 options, non-empty option labels, labels and
// descriptions aligned; Score: 2..10 levels, non-empty descriptions.
//
// Structured instructions/criteria (S3/S4/S5, M2 chunk 2): `instructions`
// and each criteria entry accept an object/array/string via the
// `*_json` builders in xiom.jev.types; a set doc is emitted verbatim and
// overrides the string form, so the string fixtures stay byte-exact. An
// instruction is "present" when either the string is non-empty or a doc is
// set; a Score level is present when its string is non-empty or its doc is
// set (a structured level carries no string).
//
// Danger-zone box + media (S8 v0.2.0, SPEC.md sections 19.2/19.4): a Box
// question carries type + optional instructions and no criteria. Assets are
// emitted as an insertion-ordered `assets` object after `questions`; each
// entry is {"type":"image","format","data_base64"} for inline base64 or
// {"type":"image","part"} for multipart. Placeholder substitution is
// server-side. base64 shape is validated (A-Za-z0-9+/ plus correct '='
// padding, non-empty); `data_base64` without `format` is rejected, and with
// `part` the data_base64 member is ignored entirely.

module xiom.jev.request

use xiom.jev.errors;
use xiom.jev.types;
use xiom.serialize.json;
use xiom.string;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Validation
// --------------------------------------------------

fn _dup_id(questions: &Vec[Question], i: Int) -> Bool {
  let id: Str = questions[i].id;
  var j: Int = 0;
  while j < i {
    let other: Str = questions[j].id;
    if compare.str_compare(other, id) == 0 { return true; }
    j = j + 1;
  }
  return false;
}

// _validate_question returns "" when question i is well formed, else the
// exact BadRequest reason (without the "request: " prefix is NOT omitted:
// the full reason string is returned ready for the error).
fn _validate_question(questions: &Vec[Question], i: Int) -> Str {
  let q: Question = questions[i];
  let id: Str = q.id;
  if id.len() == 0 {
    return "request: question " + convert.to_string(i) + ": id is empty";
  }
  if _dup_id(questions, i) {
    return "request: duplicate question id '" + id + "'";
  }
  let kind: Int = q.kind;
  // Box instructions are optional (S8 v0.2.0); every other kind keeps the
  // M1 rule (string non-empty or a structured doc set).
  if kind != types.KIND_BOX {
    let instructions: Str = q.instructions;
    if instructions.len() == 0 && types.doc_is_set(q.instructions_doc) == 0 {
      return "request: question '" + id + "': instructions is empty";
    }
  }
  if kind == types.KIND_CHOICE {
    let n: Int = q.labels.len();
    if n == 0 {
      return "request: question '" + id + "': choice needs at least one option";
    }
    if n > 255 {
      return "request: question '" + id + "': choice has more than 255 options";
    }
    if q.texts.len() != n {
      return "request: question '" + id + "': choice options are malformed";
    }
    var j: Int = 0;
    while j < n {
      let label: Str = q.labels[j];
      if label.len() == 0 {
        return "request: question '" + id + "': choice option " + convert.to_string(j) + ": label is empty";
      }
      j = j + 1;
    }
    return "";
  }
  if kind == types.KIND_SCORE {
    let n: Int = q.texts.len();
    if n < 2 {
      return "request: question '" + id + "': score needs at least 2 levels";
    }
    if n > 10 {
      return "request: question '" + id + "': score has more than 10 levels";
    }
    var j: Int = 0;
    while j < n {
      let level: Str = q.texts[j];
      var doc_set: Int = 0;
      if j < q.criterion_docs.len() {
        doc_set = types.doc_is_set(q.criterion_docs[j]);
      }
      if level.len() == 0 && doc_set == 0 {
        return "request: question '" + id + "': score level " + convert.to_string(j) + ": description is empty";
      }
      j = j + 1;
    }
    return "";
  }
  if kind == types.KIND_NOUL || kind == types.KIND_BOX {
    return "";
  }
  return "request: question '" + id + "': unknown question kind";
}

// --------------------------------------------------
//  Criteria emission
// --------------------------------------------------

fn _choice_criteria(q: &Question) -> JsonValue {
  var crit: JsonValue = json.json_object_new();
  var j: Int = 0;
  while j < q.labels.len() {
    let label: Str = q.labels[j];
    var emitted: JsonValue = json.json_null();
    var use_doc: Int = 0;
    if j < q.criterion_docs.len() {
      let d: JsonValue = q.criterion_docs[j];
      if types.doc_is_set(d) == 1 {
        emitted = d;
        use_doc = 1;
      }
    }
    if use_doc == 0 {
      let description: Str = q.texts[j];
      if description.len() > 0 {
        emitted = json.json_string(description);
      }
    }
    crit = json.json_set(crit, label, emitted);
    j = j + 1;
  }
  return crit;
}

fn _score_criteria(q: &Question) -> JsonValue {
  var arr: JsonValue = json.json_array_new();
  var j: Int = 0;
  while j < q.texts.len() {
    var emitted: JsonValue = json.json_string(q.texts[j]);
    if j < q.criterion_docs.len() {
      let d: JsonValue = q.criterion_docs[j];
      if types.doc_is_set(d) == 1 {
        emitted = d;
      }
    }
    arr = json.json_array_push(arr, emitted);
    j = j + 1;
  }
  return arr;
}

fn _instructions_value(q: &Question) -> JsonValue {
  let d: JsonValue = q.instructions_doc;
  if types.doc_is_set(d) == 1 { return d; }
  return json.json_string(q.instructions);
}

fn _question_object(q: &Question) -> JsonValue {
  var qobj: JsonValue = json.json_object_new();
  qobj = json.json_set(qobj, "type", json.json_string(types.kind_name(q.kind)));
  qobj = json.json_set(qobj, "instructions", _instructions_value(q));
  if q.kind == types.KIND_CHOICE {
    qobj = json.json_set(qobj, "criteria", _choice_criteria(q));
    return qobj;
  }
  if q.kind == types.KIND_SCORE {
    qobj = json.json_set(qobj, "criteria", _score_criteria(q));
    return qobj;
  }
  if q.kind == types.KIND_BOX {
    // S8 v0.2.0 BoxQuestion: type + optional instructions, no criteria.
    if q.instructions.len() == 0 && types.doc_is_set(q.instructions_doc) == 0 {
      var bare: JsonValue = json.json_object_new();
      bare = json.json_set(bare, "type", json.json_string(types.kind_name(q.kind)));
      return bare;
    }
    return qobj;
  }
  let yes: Str = q.noul_yes;
  let no: Str = q.noul_no;
  let yes_doc: JsonValue = q.noul_yes_doc;
  let no_doc: JsonValue = q.noul_no_doc;
  let yes_set: Int = types.doc_is_set(yes_doc);
  let no_set: Int = types.doc_is_set(no_doc);
  if yes.len() > 0 || no.len() > 0 || yes_set == 1 || no_set == 1 {
    var crit: JsonValue = json.json_object_new();
    if yes_set == 1 {
      crit = json.json_set(crit, "true", yes_doc);
    } elif yes.len() > 0 {
      crit = json.json_set(crit, "true", json.json_string(yes));
    }
    if no_set == 1 {
      crit = json.json_set(crit, "false", no_doc);
    } elif no.len() > 0 {
      crit = json.json_set(crit, "false", json.json_string(no));
    }
    qobj = json.json_set(qobj, "criteria", crit);
  }
  return qobj;
}

// --------------------------------------------------
//  Assets
// --------------------------------------------------

// _b64_char_ok is 1 for A-Z / a-z / 0-9 / '+' / '/'.
fn _b64_char_ok(b: Int) -> Int {
  if b >= 65 && b <= 90 { return 1; }
  if b >= 97 && b <= 122 { return 1; }
  if b >= 48 && b <= 57 { return 1; }
  if b == 43 || b == 47 { return 1; }
  return 0;
}

// _base64_ok validates base64 SHAPE only (SPEC.md 19.4): non-empty, a
// multiple of 4 bytes, only A-Za-z0-9+/ in the data section and at most two
// trailing '=' padding bytes (none before them). Unused trailing bits are not
// inspected.
fn _base64_ok(s: Str) -> Bool {
  let n: Int = s.len();
  if n == 0 { return false; }
  if n % 4 != 0 { return false; }
  var pad: Int = 0;
  let last: Int = (string.byte_at(s, n - 1) as Int) & 0xFF;
  let prev: Int = (string.byte_at(s, n - 2) as Int) & 0xFF;
  if last == 61 { pad = pad + 1; }
  if prev == 61 { pad = pad + 1; }
  if pad > 2 { return false; }
  if pad == 1 && last != 61 { return false; }
  let data_len: Int = n - pad;
  var i: Int = 0;
  while i < data_len {
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if _b64_char_ok(b) == 0 { return false; }
    i = i + 1;
  }
  return true;
}

fn _dup_asset_placeholder(assets: &Vec[AssetEntry], i: Int) -> Bool {
  let p: Str = assets[i].placeholder;
  var j: Int = 0;
  while j < i {
    let other: Str = assets[j].placeholder;
    if compare.str_compare(other, p) == 0 { return true; }
    j = j + 1;
  }
  return false;
}

fn _known_image_format(f: Str) -> Bool {
  if compare.str_compare(f, "png") == 0 { return true; }
  if compare.str_compare(f, "jpg") == 0 { return true; }
  if compare.str_compare(f, "jpeg") == 0 { return true; }
  return false;
}

// _validate_asset returns "" when asset i is well formed, else the exact
// BadRequest reason. A part form ignores data_base64 (S8 v0.2.0).
fn _validate_asset(assets: &Vec[AssetEntry], i: Int) -> Str {
  let placeholder: Str = assets[i].placeholder;
  if placeholder.len() == 0 {
    return "request: asset " + convert.to_string(i) + ": placeholder is empty";
  }
  if _dup_asset_placeholder(assets, i) {
    return "request: duplicate asset placeholder '" + placeholder + "'";
  }
  let a: Asset = assets[i].asset;
  let part: Str = a.part;
  if part.len() > 0 { return ""; }
  let data: Str = a.data_base64;
  let format: Str = a.format;
  if data.len() == 0 {
    return "request: asset '" + placeholder + "': data_base64 is empty";
  }
  if format.len() == 0 {
    return "request: asset '" + placeholder + "': data_base64 requires format";
  }
  if !_known_image_format(format) {
    return "request: asset '" + placeholder + "': unknown format '" + format + "'";
  }
  if !_base64_ok(data) {
    return "request: asset '" + placeholder + "': invalid base64";
  }
  return "";
}

fn _asset_object(a: &Asset) -> JsonValue {
  var obj: JsonValue = json.json_object_new();
  obj = json.json_set(obj, "type", json.json_string("image"));
  if a.part.len() > 0 {
    obj = json.json_set(obj, "part", json.json_string(a.part));
    return obj;
  }
  obj = json.json_set(obj, "format", json.json_string(a.format));
  obj = json.json_set(obj, "data_base64", json.json_string(a.data_base64));
  return obj;
}

/// danger_zone_images_required is 1 when a Box question or at least one
/// asset is present, else 0. The client emits
/// `TypeSafe-Danger-Zone-Images: true` exactly when this returns 1, so a box
/// question can never go out without the capability header.
/// Complexity: O(questions). Pure.
pub fn danger_zone_images_required(questions: &Vec[Question], assets: &Vec[AssetEntry]) -> Int {
  if assets.len() > 0 { return 1; }
  var i: Int = 0;
  while i < questions.len() {
    if questions[i].kind == types.KIND_BOX { return 1; }
    i = i + 1;
  }
  return 0;
}

// --------------------------------------------------
//  Builder
// --------------------------------------------------

/// build_request returns the JSON body for a System One evaluation of
/// `state` against `questions` on `model` (see the module header for the
/// exact shape and the validation catalog). This is the no-assets entry and
/// stays byte-identical to the M1/M2 output. On rejection the Result carries
/// JevError.BadRequest with a stable reason string; on success the body is
/// compact JSON with keys in the order "state", "model", "questions" and
/// criteria in caller order. Complexity: O(total input). Pure.
pub fn build_request(model: Str, state: State, questions: Vec[Question]) -> Result[Str, JevError] {
  let empty: Vec[AssetEntry] = Vec[AssetEntry].new();
  return build_request_with_assets(model, state, questions, empty);
}

/// build_request_with_assets is build_request plus the danger-zone `assets`
/// map (S8 v0.2.0). Assets are validated and emitted as an insertion-ordered
/// object after `questions`: {"placeholder":{"type":"image",...}}. An empty
/// asset list omits the member entirely, so the existing byte-exact
/// fixtures are unchanged. Complexity: O(total input). Pure.
pub fn build_request_with_assets(model: Str, state: State, questions: Vec[Question], assets: Vec[AssetEntry]) -> Result[Str, JevError] {
  if model.len() == 0 {
    return Err(JevError.BadRequest("request: model is empty"));
  }
  if state.is_json == 0 && state.text.len() == 0 {
    return Err(JevError.BadRequest("request: state is empty"));
  }
  if questions.len() == 0 {
    return Err(JevError.BadRequest("request: no questions"));
  }
  var i: Int = 0;
  while i < questions.len() {
    let reason: Str = _validate_question(&questions, i);
    if reason.len() > 0 {
      return Err(JevError.BadRequest(reason));
    }
    i = i + 1;
  }
  i = 0;
  while i < assets.len() {
    let reason: Str = _validate_asset(&assets, i);
    if reason.len() > 0 {
      return Err(JevError.BadRequest(reason));
    }
    i = i + 1;
  }
  var questions_obj: JsonValue = json.json_object_new();
  i = 0;
  while i < questions.len() {
    let q: Question = questions[i];
    questions_obj = json.json_set(questions_obj, q.id, _question_object(&q));
    i = i + 1;
  }
  var root: JsonValue = json.json_object_new();
  if state.is_json == 1 {
    root = json.json_set(root, "state", state.doc);
  } else {
    root = json.json_set(root, "state", json.json_string(state.text));
  }
  root = json.json_set(root, "model", json.json_string(model));
  root = json.json_set(root, "questions", questions_obj);
  if assets.len() > 0 {
    var assets_obj: JsonValue = json.json_object_new();
    i = 0;
    while i < assets.len() {
      let placeholder: Str = assets[i].placeholder;
      let a: Asset = assets[i].asset;
      assets_obj = json.json_set(assets_obj, placeholder, _asset_object(&a));
      i = i + 1;
    }
    root = json.json_set(root, "assets", assets_obj);
  }
  return Ok(json.json_stringify(root));
}
