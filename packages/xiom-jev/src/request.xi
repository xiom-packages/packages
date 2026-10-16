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

module xiom.jev.request

use xiom.jev.errors;
use xiom.jev.types;
use xiom.serialize.json;
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
  let instructions: Str = q.instructions;
  if instructions.len() == 0 && types.doc_is_set(q.instructions_doc) == 0 {
    return "request: question '" + id + "': instructions is empty";
  }
  let kind: Int = q.kind;
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
  if kind == types.KIND_NOUL {
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
//  Builder
// --------------------------------------------------

/// build_request returns the JSON body for a System One evaluation of
/// `state` against `questions` on `model` (see the module header for the
/// exact shape and the validation catalog). On rejection the Result carries
/// JevError.BadRequest with a stable reason string; on success the body is
/// compact JSON with keys in the order "state", "model", "questions" and
/// criteria in caller order. Complexity: O(total input). Pure.
pub fn build_request(model: Str, state: State, questions: Vec[Question]) -> Result[Str, JevError] {
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
  return Ok(json.json_stringify(root));
}
