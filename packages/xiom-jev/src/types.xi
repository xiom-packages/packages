// XIOM -- xiom.jev.types: state, typed questions and typed answers
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The System One data model. A State is either text or a JSON document; a
// Question is one typed primitive (choice / score / noul / box); a Response
// holds one Answer per question, in wire order, with the full probability
// distribution and (for choice/score/box) confidence.
//
// Float-free core (house style): every 0..1 quantity on the wire (a
// probability, a confidence, a noul) is carried in this package as an Int in
// micro units, micro = round(value * 1000000), range [0, 1000000]. A Score is
// carried as score_micro = round(score * 1000000), where one rubric level is
// 1000000 micro (the score domain is 0 .. top level, so up to 9000000 for 10
// levels). The only Float64 touch points are the JSON boundaries (parsing a
// response number) and micro_text rendering is integer-only. Rounding is
// round-half-away-from-zero; see SPEC.md section 6.
//
// Answers uses parallel vectors (no struct-per-answer vector): for answer i,
// kinds[i] is 0 choice / 1 score / 2 noul / 3 box, and the probability distribution
// is the slice prob_micro[prob_starts[i] .. prob_starts[i] + prob_counts[i]]
// with labels at the same offsets in prob_labels. Wire order is preserved
// (the stdlib JSON object keeps insertion order). Accessors guard every
// index: an out-of-range i or j returns the documented empty sentinel ("",
// -1) instead of trapping.

module xiom.jev.types

use xiom.serialize.json;
use xiom.string;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Constants
// --------------------------------------------------

/// One unit of probability/confidence/noul (1.0 = 1000000 micro).
pub const MICRO: Int = 1000000;

/// Question/answer kind tags.
pub const KIND_CHOICE: Int = 0;
pub const KIND_SCORE: Int = 1;
pub const KIND_NOUL: Int = 2;
pub const KIND_BOX: Int = 3;

// --------------------------------------------------
//  State
// --------------------------------------------------

/// State is the content evaluated by every question of one request: plain
/// text (is_json == 0, text set) or a JSON document (is_json == 1, doc set).
pub type State = {
  is_json: Int;
  text: Str;
  doc: JsonValue;
}

/// state_text wraps plain text as a State.
/// Complexity: O(1). Pure.
pub fn state_text(text: Str) -> State {
  return State{ is_json: 0, text: text, doc: json.json_null() };
}

/// state_json wraps a JSON document (JsonValue from xiom.serialize.json)
/// as a State. Complexity: O(1). Pure.
pub fn state_json(doc: JsonValue) -> State {
  return State{ is_json: 1, text: "", doc: doc };
}

// --------------------------------------------------
//  Assets (danger-zone images, S8 v0.2.0)
// --------------------------------------------------

/// Asset is one danger-zone media entry, referenced from state/instructions/
/// criteria by the AssetEntry placeholder. Two wire forms:
///   base64: format ("png" | "jpg" | "jpeg") + data_base64;
///   part:   part names a multipart part; data_base64 is ignored.
/// The placeholder substitution itself is server-side.
pub type Asset = {
  format: Str;
  data_base64: Str;
  part: Str;
}

/// AssetEntry maps a caller-chosen placeholder to an Asset; build order is
/// the emission order of the `assets` object.
pub type AssetEntry = {
  placeholder: Str;
  asset: Asset;
}

/// asset_image_base64 builds an inline (JSON) image asset. `format` must be
/// "png", "jpg" or "jpeg"; `data_base64` must be non-empty valid base64
/// (validated by build_request_with_assets). Complexity: O(1). Pure.
pub fn asset_image_base64(format: Str, data_base64: Str) -> Asset {
  return Asset{ format: format, data_base64: data_base64, part: "" };
}

/// asset_image_part builds a multipart image asset: `part` names the part.
/// data_base64 stays empty and is ignored on the wire. Complexity: O(1).
/// Pure.
pub fn asset_image_part(part: Str) -> Asset {
  return Asset{ format: "", data_base64: "", part: part };
}

/// asset_entry pairs a placeholder (recommend a UUID) with an Asset.
/// Complexity: O(1). Pure.
pub fn asset_entry(placeholder: Str, asset: Asset) -> AssetEntry {
  return AssetEntry{ placeholder: placeholder, asset: asset };
}

/// assets_new returns an empty asset list (emitted as no `assets` member).
/// Complexity: O(1). Pure.
pub fn assets_new() -> Vec[AssetEntry] {
  return Vec[AssetEntry].new();
}

// --------------------------------------------------
//  Questions
// --------------------------------------------------

/// Question is one typed primitive. kind selects the shape:
///   KIND_CHOICE: labels[i] is an option name, texts[i] its description
///                ("" is sent as null, docs allow null descriptions);
///   KIND_SCORE:  texts[i] is level i's description, in order; labels[i] is
///                the level number rendered as text ("0", "1", ...);
///   KIND_NOUL:   instructions is the yes/no question; noul_yes/noul_no are
///                the optional criteria descriptions ("" = absent);
///   KIND_BOX:    instructions is the optional danger-zone box prompt (no
///                criteria); an absent instruction is omitted on the wire.
///
/// Structured forms (S3/S4/S5): `instructions` and each criteria entry may be
/// a string, an object or an array. The `*_doc` / `criterion_docs` fields
/// carry those forms: when a doc is not JSON null it is emitted verbatim in
/// place of the string, so the string builders and the string byte-exact
/// fixtures are untouched. For Choice/Score, criterion_docs is parallel to
/// labels/texts (index j is option/level j); for a Choice a JSON-null doc
/// falls back to the string rule ("" -> null).
pub type Question = {
  kind: Int;
  id: Str;
  instructions: Str;
  labels: Vec[Str];
  texts: Vec[Str];
  noul_yes: Str;
  noul_no: Str;
  instructions_doc: JsonValue;
  criterion_docs: Vec[JsonValue];
  noul_yes_doc: JsonValue;
  noul_no_doc: JsonValue;
}

/// doc_is_set is 1 when `doc` is a structured value (not JSON null), i.e.
/// the caller supplied an object/array/string form to emit verbatim.
/// Complexity: O(1). Pure.
pub fn doc_is_set(doc: JsonValue) -> Int {
  if compare.str_compare(json.json_type(doc), "null") == 0 { return 0; }
  return 1;
}

/// question_choice starts a Choice question (add options with
/// question_add_option). Complexity: O(1). Pure.
pub fn question_choice(id: Str, instructions: Str) -> Question {
  return Question{
    kind: KIND_CHOICE,
    id: id,
    instructions: instructions,
    labels: Vec[Str].new(),
    texts: Vec[Str].new(),
    noul_yes: "",
    noul_no: "",
    instructions_doc: json.json_null(),
    criterion_docs: Vec[JsonValue].new(),
    noul_yes_doc: json.json_null(),
    noul_no_doc: json.json_null(),
  };
}

/// question_add_option appends one Choice option: `label` is the option
/// name (criteria key), `description` its rubric description ("" = null).
/// Complexity: O(1) amortized. Mutates q.
pub fn question_add_option(q: &mut Question, label: Str, description: Str) {
  q.labels.push(label);
  q.texts.push(description);
  q.criterion_docs.push(json.json_null());
}

/// question_add_option_json appends one Choice option whose criterion value
/// is a structured JSON value (object, array or string; S3). `label` is the
/// option name. Pass json_null to mean "no description" (emitted as null).
/// Complexity: O(1) amortized. Mutates q.
pub fn question_add_option_json(q: &mut Question, label: Str, doc: JsonValue) {
  q.labels.push(label);
  q.texts.push("");
  q.criterion_docs.push(doc);
}

/// question_set_instructions_json sets a structured `instructions` value
/// (object or array, S3/S4/S5) to be emitted verbatim in place of the plain
/// string. Complexity: O(1). Mutates q.
pub fn question_set_instructions_json(q: &mut Question, doc: JsonValue) {
  q.instructions_doc = doc;
}

/// question_score starts a Score question (add levels with
/// question_add_level). Complexity: O(1). Pure.
pub fn question_score(id: Str, instructions: Str) -> Question {
  return Question{
    kind: KIND_SCORE,
    id: id,
    instructions: instructions,
    labels: Vec[Str].new(),
    texts: Vec[Str].new(),
    noul_yes: "",
    noul_no: "",
    instructions_doc: json.json_null(),
    criterion_docs: Vec[JsonValue].new(),
    noul_yes_doc: json.json_null(),
    noul_no_doc: json.json_null(),
  };
}

/// question_add_level appends one Score rubric level, lowest first. Its
/// level number is its position (labels stays in sync for consumers).
/// Complexity: O(1) amortized. Mutates q.
pub fn question_add_level(q: &mut Question, description: Str) {
  let level: Int = q.texts.len();
  q.labels.push(convert.to_string(level));
  q.texts.push(description);
  q.criterion_docs.push(json.json_null());
}

/// question_add_level_json appends one Score rubric level whose description
/// is a structured JSON value (object or array; S4). The level number is its
/// position. Complexity: O(1) amortized. Mutates q.
pub fn question_add_level_json(q: &mut Question, doc: JsonValue) {
  let level: Int = q.texts.len();
  q.labels.push(convert.to_string(level));
  q.texts.push("");
  q.criterion_docs.push(doc);
}

/// question_noul starts a Noul (yes/no) question.
/// Complexity: O(1). Pure.
pub fn question_noul(id: Str, instructions: Str) -> Question {
  return Question{
    kind: KIND_NOUL,
    id: id,
    instructions: instructions,
    labels: Vec[Str].new(),
    texts: Vec[Str].new(),
    noul_yes: "",
    noul_no: "",
    instructions_doc: json.json_null(),
    criterion_docs: Vec[JsonValue].new(),
    noul_yes_doc: json.json_null(),
    noul_no_doc: json.json_null(),
  };
}

/// question_box starts a danger-zone Box question (S8 v0.2.0). It carries no
/// criteria; `instructions` is optional (pass "" to omit it from the wire).
/// Complexity: O(1). Pure.
pub fn question_box(id: Str, instructions: Str) -> Question {
  return Question{
    kind: KIND_BOX,
    id: id,
    instructions: instructions,
    labels: Vec[Str].new(),
    texts: Vec[Str].new(),
    noul_yes: "",
    noul_no: "",
    instructions_doc: json.json_null(),
    criterion_docs: Vec[JsonValue].new(),
    noul_yes_doc: json.json_null(),
    noul_no_doc: json.json_null(),
  };
}

/// question_set_noul_criteria sets the optional Noul criteria descriptions
/// (what a yes and a no mean). Pass "" to omit one side.
/// Complexity: O(1). Mutates q.
pub fn question_set_noul_criteria(q: &mut Question, yes_means: Str, no_means: Str) {
  q.noul_yes = yes_means;
  q.noul_no = no_means;
  q.noul_yes_doc = json.json_null();
  q.noul_no_doc = json.json_null();
}

/// question_set_noul_criteria_json sets the optional Noul true/false criteria
/// to structured JSON values (object, array or string; S5) emitted verbatim.
/// Pass json_null to omit a side. Complexity: O(1). Mutates q.
pub fn question_set_noul_criteria_json(q: &mut Question, yes_means: JsonValue, no_means: JsonValue) {
  q.noul_yes = "";
  q.noul_no = "";
  q.noul_yes_doc = yes_means;
  q.noul_no_doc = no_means;
}

// --------------------------------------------------
//  Answers and Response
// --------------------------------------------------

/// Answers is the parallel-vector answer set of one Response (see the
/// module header for the layout and micro units). choices[i] is the selected
/// option for a choice answer ("" otherwise); confidence_micro is -1 for
/// noul answers (the API returns no confidence for them) and for a box
/// answer whose wire confidence is null (Option-shaped: -1 = none);
/// score_micro, noul_micro and the box edges are 0 unless their kind
/// applies. The legend of a score answer
/// is the level -> description map reported by the API (S4), kept in
/// legend_starts/legend_counts/legend_labels parallel to the probabilities;
/// legend_docs holds each description as its raw JSON value (string or
/// object/array), so both the plain and the structured S4 legend forms
/// round-trip.
pub type Answers = {
  ids: Vec[Str];
  kinds: Vec[Int];
  choices: Vec[Str];
  confidence_micro: Vec[Int];
  score_micro: Vec[Int];
  noul_micro: Vec[Int];
  box_top_micro: Vec[Int];
  box_bottom_micro: Vec[Int];
  box_left_micro: Vec[Int];
  box_right_micro: Vec[Int];
  prob_starts: Vec[Int];
  prob_counts: Vec[Int];
  prob_labels: Vec[Str];
  prob_micro: Vec[Int];
  legend_starts: Vec[Int];
  legend_counts: Vec[Int];
  legend_labels: Vec[Str];
  legend_docs: Vec[JsonValue];
}

/// Response is one parsed System One response: the model that answered, the
/// answers in wire order, and token usage (has_usage == 0 when the `usage`
/// object was absent). Complexity: O(1). Pure.
pub type Response = {
  model: Str;
  answers: Answers;
  has_usage: Int;
  input_tokens: Int;
  output_tokens: Int;
}

/// answers_new returns an empty Answers set.
/// Complexity: O(1). Pure.
pub fn answers_new() -> Answers {
  return Answers{
    ids: Vec[Str].new(),
    kinds: Vec[Int].new(),
    choices: Vec[Str].new(),
    confidence_micro: Vec[Int].new(),
    score_micro: Vec[Int].new(),
    noul_micro: Vec[Int].new(),
    box_top_micro: Vec[Int].new(),
    box_bottom_micro: Vec[Int].new(),
    box_left_micro: Vec[Int].new(),
    box_right_micro: Vec[Int].new(),
    prob_starts: Vec[Int].new(),
    prob_counts: Vec[Int].new(),
    prob_labels: Vec[Str].new(),
    prob_micro: Vec[Int].new(),
    legend_starts: Vec[Int].new(),
    legend_counts: Vec[Int].new(),
    legend_labels: Vec[Str].new(),
    legend_docs: Vec[JsonValue].new(),
  };
}

/// response_new returns an empty Response for `model`.
/// Complexity: O(1). Pure.
pub fn response_new(model: Str) -> Response {
  return Response{
    model: model,
    answers: answers_new(),
    has_usage: 0,
    input_tokens: 0,
    output_tokens: 0,
  };
}

// --------------------------------------------------
//  Accessors (every index is guarded)
// --------------------------------------------------

/// response_count is the number of answers. Complexity: O(1).
pub fn response_count(r: &Response) -> Int {
  let a: Answers = r.answers;
  return a.ids.len();
}

/// response_model is the model that answered. Complexity: O(1).
pub fn response_model(r: &Response) -> Str {
  return r.model;
}

/// response_id is answer i's question id ("" when i is out of range).
/// Complexity: O(1).
pub fn response_id(r: &Response, i: Int) -> Str {
  let a: Answers = r.answers;
  if i < 0 || i >= a.ids.len() { return ""; }
  return a.ids[i];
}

/// response_kind is answer i's kind (KIND_CHOICE/KIND_SCORE/KIND_NOUL),
/// -1 when i is out of range. Complexity: O(1).
pub fn response_kind(r: &Response, i: Int) -> Int {
  let a: Answers = r.answers;
  if i < 0 || i >= a.kinds.len() { return -1; }
  return a.kinds[i];
}

/// response_find is the index of the answer under `id` (wire order), -1
/// when absent. Complexity: O(n). Pure.
pub fn response_find(r: &Response, id: Str) -> Int {
  let a: Answers = r.answers;
  var i: Int = 0;
  while i < a.ids.len() {
    let e: Str = a.ids[i];
    if compare.str_compare(e, id) == 0 { return i; }
    i = i + 1;
  }
  return -1;
}

/// response_choice is answer i's selected option ("" when not a choice
/// answer or i is out of range). Complexity: O(1).
pub fn response_choice(r: &Response, i: Int) -> Str {
  let a: Answers = r.answers;
  if i < 0 || i >= a.choices.len() { return ""; }
  if a.kinds[i] != KIND_CHOICE { return ""; }
  return a.choices[i];
}

/// response_confidence_micro is answer i's confidence in micro units, or
/// -1 when absent (noul answers) or i is out of range. Complexity: O(1).
pub fn response_confidence_micro(r: &Response, i: Int) -> Int {
  let a: Answers = r.answers;
  if i < 0 || i >= a.confidence_micro.len() { return -1; }
  return a.confidence_micro[i];
}

/// response_score_micro is answer i's score * 1000000 (0 when not a score
/// answer or i is out of range). Complexity: O(1).
pub fn response_score_micro(r: &Response, i: Int) -> Int {
  let a: Answers = r.answers;
  if i < 0 || i >= a.score_micro.len() { return 0; }
  if a.kinds[i] != KIND_SCORE { return 0; }
  return a.score_micro[i];
}

/// response_noul_micro is answer i's noul * 1000000 (0 when not a noul
/// answer or i is out of range). Complexity: O(1).
pub fn response_noul_micro(r: &Response, i: Int) -> Int {
  let a: Answers = r.answers;
  if i < 0 || i >= a.noul_micro.len() { return 0; }
  if a.kinds[i] != KIND_NOUL { return 0; }
  return a.noul_micro[i];
}

/// response_box_top_micro is a box answer's top edge in micro units (-1 when
/// answer i is not a box answer or i is out of range). Complexity: O(1).
pub fn response_box_top_micro(r: &Response, i: Int) -> Int {
  let a: Answers = r.answers;
  if i < 0 || i >= a.box_top_micro.len() { return -1; }
  if a.kinds[i] != KIND_BOX { return -1; }
  return a.box_top_micro[i];
}

/// response_box_bottom_micro is a box answer's bottom edge in micro units
/// (-1 when answer i is not a box answer or i is out of range).
/// Complexity: O(1).
pub fn response_box_bottom_micro(r: &Response, i: Int) -> Int {
  let a: Answers = r.answers;
  if i < 0 || i >= a.box_bottom_micro.len() { return -1; }
  if a.kinds[i] != KIND_BOX { return -1; }
  return a.box_bottom_micro[i];
}

/// response_box_left_micro is a box answer's left edge in micro units (-1
/// when answer i is not a box answer or i is out of range). Complexity: O(1).
pub fn response_box_left_micro(r: &Response, i: Int) -> Int {
  let a: Answers = r.answers;
  if i < 0 || i >= a.box_left_micro.len() { return -1; }
  if a.kinds[i] != KIND_BOX { return -1; }
  return a.box_left_micro[i];
}

/// response_box_right_micro is a box answer's right edge in micro units (-1
/// when answer i is not a box answer or i is out of range). Complexity: O(1).
pub fn response_box_right_micro(r: &Response, i: Int) -> Int {
  let a: Answers = r.answers;
  if i < 0 || i >= a.box_right_micro.len() { return -1; }
  if a.kinds[i] != KIND_BOX { return -1; }
  return a.box_right_micro[i];
}

/// response_prob_count is the number of probability entries of answer i
/// (0 when i is out of range). Complexity: O(1).
pub fn response_prob_count(r: &Response, i: Int) -> Int {
  let a: Answers = r.answers;
  if i < 0 || i >= a.prob_counts.len() { return 0; }
  return a.prob_counts[i];
}

/// response_prob_label is the label (option name / level number) of entry j
/// of answer i ("" when out of range). Complexity: O(1).
pub fn response_prob_label(r: &Response, i: Int, j: Int) -> Str {
  let a: Answers = r.answers;
  if i < 0 || i >= a.prob_counts.len() { return ""; }
  let n: Int = a.prob_counts[i];
  if j < 0 || j >= n { return ""; }
  let base: Int = a.prob_starts[i];
  return a.prob_labels[base + j];
}

/// response_prob_micro is entry j's probability in micro units (-1 when out
/// of range). Complexity: O(1).
pub fn response_prob_micro(r: &Response, i: Int, j: Int) -> Int {
  let a: Answers = r.answers;
  if i < 0 || i >= a.prob_counts.len() { return -1; }
  let n: Int = a.prob_counts[i];
  if j < 0 || j >= n { return -1; }
  let base: Int = a.prob_starts[i];
  return a.prob_micro[base + j];
}

/// response_prob_find is the entry index of `label` within answer i's
/// distribution (-1 when absent or i is out of range). Complexity: O(n).
pub fn response_prob_find(r: &Response, i: Int, label: Str) -> Int {
  let a: Answers = r.answers;
  if i < 0 || i >= a.prob_counts.len() { return -1; }
  let n: Int = a.prob_counts[i];
  let base: Int = a.prob_starts[i];
  var j: Int = 0;
  while j < n {
    let e: Str = a.prob_labels[base + j];
    if compare.str_compare(e, label) == 0 { return j; }
    j = j + 1;
  }
  return -1;
}

/// response_prob_total_micro is the sum of answer i's distribution in micro
/// units (0 when i is out of range). Complexity: O(n).
pub fn response_prob_total_micro(r: &Response, i: Int) -> Int {
  let a: Answers = r.answers;
  if i < 0 || i >= a.prob_counts.len() { return 0; }
  let n: Int = a.prob_counts[i];
  let base: Int = a.prob_starts[i];
  var total: Int = 0;
  var j: Int = 0;
  while j < n {
    total = total + a.prob_micro[base + j];
    j = j + 1;
  }
  return total;
}

// --------------------------------------------------
//  Legend (score answers)
// --------------------------------------------------

/// response_legend_count is the number of legend entries of score answer i
/// (0 for choice/noul answers and when i is out of range). The legend maps
/// each level key to its description, which may be a string or a structured
/// value (S4); entries keep wire order. Complexity: O(1).
pub fn response_legend_count(r: &Response, i: Int) -> Int {
  let a: Answers = r.answers;
  if i < 0 || i >= a.legend_counts.len() { return 0; }
  return a.legend_counts[i];
}

/// response_legend_label is the level key of legend entry j of answer i
/// ("" when out of range). Complexity: O(1).
pub fn response_legend_label(r: &Response, i: Int, j: Int) -> Str {
  let a: Answers = r.answers;
  if i < 0 || i >= a.legend_counts.len() { return ""; }
  let n: Int = a.legend_counts[i];
  if j < 0 || j >= n { return ""; }
  let base: Int = a.legend_starts[i];
  return a.legend_labels[base + j];
}

/// response_legend_doc is legend entry j of answer i as its raw JSON value
/// (JSON null when out of range). A string entry keeps its string form; a
/// structured entry keeps its object/array form (S4). Complexity: O(1).
pub fn response_legend_doc(r: &Response, i: Int, j: Int) -> JsonValue {
  let a: Answers = r.answers;
  if i < 0 || i >= a.legend_counts.len() { return json.json_null(); }
  let n: Int = a.legend_counts[i];
  if j < 0 || j >= n { return json.json_null(); }
  let base: Int = a.legend_starts[i];
  return a.legend_docs[base + j];
}

/// response_legend_is_structured is 1 when legend entry j of answer i is not
/// a plain string (an object/array form, S4), else 0 (including out of
/// range). Complexity: O(1).
pub fn response_legend_is_structured(r: &Response, i: Int, j: Int) -> Int {
  let a: Answers = r.answers;
  if i < 0 || i >= a.legend_counts.len() { return 0; }
  let n: Int = a.legend_counts[i];
  if j < 0 || j >= n { return 0; }
  let base: Int = a.legend_starts[i];
  let d: JsonValue = a.legend_docs[base + j];
  if compare.str_compare(json.json_type(d), "string") == 0 { return 0; }
  return 1;
}

/// response_legend_text is the plain-string form of legend entry j of answer
/// i ("" when the entry is structured or out of range). Complexity: O(1).
pub fn response_legend_text(r: &Response, i: Int, j: Int) -> Str {
  let a: Answers = r.answers;
  if i < 0 || i >= a.legend_counts.len() { return ""; }
  let n: Int = a.legend_counts[i];
  if j < 0 || j >= n { return ""; }
  let base: Int = a.legend_starts[i];
  let d: JsonValue = a.legend_docs[base + j];
  match d {
    JsonValue.String(s) => {
      return s;
    },
    _ => {
      return "";
    },
  };
}

/// response_legend_find is the entry index of `label` within answer i's
/// legend (-1 when absent or i is out of range). Complexity: O(n).
pub fn response_legend_find(r: &Response, i: Int, label: Str) -> Int {
  let n: Int = response_legend_count(r, i);
  var j: Int = 0;
  while j < n {
    let e: Str = response_legend_label(r, i, j);
    if compare.str_compare(e, label) == 0 { return j; }
    j = j + 1;
  }
  return -1;
}

/// response_legend_json rebuilds answer i's legend as a JSON object
/// (level -> description), in wire order; an empty object when the answer
/// carries no legend. This is the emission form of the parsed legend.
/// Complexity: O(n). Pure.
pub fn response_legend_json(r: &Response, i: Int) -> JsonValue {
  var obj: JsonValue = json.json_object_new();
  let n: Int = response_legend_count(r, i);
  var j: Int = 0;
  while j < n {
    let label: Str = response_legend_label(r, i, j);
    let doc: JsonValue = response_legend_doc(r, i, j);
    obj = json.json_set(obj, label, doc);
    j = j + 1;
  }
  return obj;
}

/// response_has_usage is 1 when the response carried a `usage` object.
/// Complexity: O(1).
pub fn response_has_usage(r: &Response) -> Int {
  return r.has_usage;
}

/// response_input_tokens is usage.input_tokens (0 when absent).
/// Complexity: O(1).
pub fn response_input_tokens(r: &Response) -> Int {
  return r.input_tokens;
}

/// response_output_tokens is usage.output_tokens (0 when absent).
/// Complexity: O(1).
pub fn response_output_tokens(r: &Response) -> Int {
  return r.output_tokens;
}

// --------------------------------------------------
//  Presentation helpers
// --------------------------------------------------

/// kind_name renders a kind tag as the API type string ("choice", "score",
/// "noul", "box"; "" for an unknown tag). Complexity: O(1). Pure.
pub fn kind_name(kind: Int) -> Str {
  if kind == KIND_CHOICE { return "choice"; }
  if kind == KIND_SCORE { return "score"; }
  if kind == KIND_NOUL { return "noul"; }
  if kind == KIND_BOX { return "box"; }
  return "";
}

/// micro_text renders a non-negative micro value as a decimal string with
/// trailing zeros stripped: 610000 -> "0.61", 1000000 -> "1",
/// 350000 -> "0.35", 0 -> "0". A negative value renders as "0". Rendering
/// is integer-only (no Float64). Complexity: O(digits). Pure.
pub fn micro_text(m: Int) -> Str {
  if m <= 0 { return "0"; }
  let whole: Int = m / MICRO;
  let frac: Int = m % MICRO;
  if frac == 0 { return convert.to_string(whole); }
  let pad: Str = "000000";
  let fs: Str = convert.to_string(frac);
  let fl: Int = fs.len();
  var cur: Str = string.str_slice(pad + fs, pad.len() + fl - 6, pad.len() + fl);
  var n: Int = cur.len();
  while n > 0 {
    let last: Str = string.str_slice(cur, n - 1, n);
    if compare.str_compare(last, "0") != 0 { break; }
    cur = string.str_slice(cur, 0, n - 1);
    n = n - 1;
  };
  return convert.to_string(whole) + "." + cur;
}
