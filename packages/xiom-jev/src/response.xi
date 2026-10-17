// XIOM -- xiom.jev.response: the System One response parser
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// parse_response turns a POST /v1/systemone response body into a typed
// Response, mirroring the SystemOneResponse schema at
// https://api.typesafe.ai/openapi.json and the answer pages of
// https://docs.typesafe.ai (see SPEC.md section 2 for the exact sources):
//   {"model": ..., "answers": {"<id>": Answer, ...}, "usage": {...}}
// with Answer one of
//   choice: {"type","choice","confidence","probabilities"}          (style A)
//   score:  {"type","score","confidence","legend","probabilities"}  (style B)
//   noul:   {"type","noul"}                                          (style C)
// Unknown extra fields are ignored (forward compatibility); the "box"
// answer type of the danger-zone API is rejected as unknown in M1.
//
// Fail-closed validation, all rejections JevError.Parse with stable reason
// strings pinned in SPEC.md section 6: the root must be an object with a
// non-empty string model and a non-empty answers object; every answer needs
// a known type; numbers must be finite (a NaN fails the >= / <= bounds) and
// in range (probabilities/confidence/noul in [0,1], score in [0,10]); a
// choice answer's selected option must be present in probabilities and be a
// maximum; a score answer's probability keys must all appear in legend; a
// choice/score distribution must sum to 1000000 micro within a +/- 2%
// tolerance (mirrors the reference client's fail-closed check); usage, when
// present, must be an object with non-negative numeric token counts.
//
// Values are converted to micro units at this boundary only:
// micro = round(value * 1000000), round half away from zero. Answers keep
// wire order.

module xiom.jev.response

use xiom.jev.errors;
use xiom.jev.types;
use xiom.serialize.json;
use xiom.string.compare;
use xiom.math;

// Distribution sum tolerance in micro units: [980000, 1020000].
const _SUM_LO: Int = 980000;
const _SUM_HI: Int = 1020000;

// --------------------------------------------------
//  Result leaf constructors
// --------------------------------------------------

fn _ok_response(v: Response) -> Result[Response, JevError] {
  return Ok(v);
}

fn _perr(reason: Str) -> Result[Response, JevError] {
  return Err(JevError.Parse(reason));
}

// --------------------------------------------------
//  JSON helpers (all Str comparisons via str_compare)
// --------------------------------------------------

fn _some_val(v: JsonValue) -> Option[JsonValue] {
  return Some(v);
}

/// _field is the object member under `key` (None when absent or not found).
fn _field(v: JsonValue, key: Str) -> Option[JsonValue] {
  match v {
    JsonValue.Object(entries) => {
      var i: Int = 0;
      while i < entries.keys.len() {
        let k: Str = entries.keys[i];
        if compare.str_compare(k, key) == 0 {
          let found: JsonValue = entries.values[i];
          return _some_val(found);
        }
        i = i + 1;
      }
      return None;
    },
    _ => {
      return None;
    },
  };
}

fn _str_of(v: JsonValue) -> Str {
  match v {
    JsonValue.String(s) => {
      return s;
    },
    _ => {
      return "";
    },
  };
}

fn _is_string(v: JsonValue) -> Bool {
  match v {
    JsonValue.String(s) => {
      return true;
    },
    _ => {
      return false;
    },
  };
}

fn _num_of(v: JsonValue) -> Bool {
  match v {
    JsonValue.Number(f) => {
      return true;
    },
    _ => {
      return false;
    },
  };
}

fn _num_value(v: JsonValue) -> Float64 {
  match v {
    JsonValue.Number(f) => {
      return f;
    },
    _ => {
      return 0.0;
    },
  };
}

fn _unit_ok(f: Float64) -> Bool {
  return (f >= 0.0) && (f <= 1.0);
}

fn _micro_of_unit(f: Float64) -> Int {
  return math.round(f * 1000000.0);
}

fn _msg(id: Str, rest: Str) -> Str {
  return "response: answer '" + id + "': " + rest;
}

fn _keys_have(keys: &Vec[Str], want: Str) -> Bool {
  var i: Int = 0;
  while i < keys.len() {
    let k: Str = keys[i];
    if compare.str_compare(k, want) == 0 { return true; }
    i = i + 1;
  }
  return false;
}

// --------------------------------------------------
//  Per-answer parsers (return "" on success, else the reason)
// --------------------------------------------------

fn _parse_choice_answer(id: Str, av: JsonValue, out: &mut Answers) -> Str {
  let co: Option[JsonValue] = _field(av, "choice");
  if !co.is_some {
    return _msg(id, "missing choice");
  }
  let cv: JsonValue = co.value;
  if !_is_string(cv) {
    return _msg(id, "choice is not a string");
  }
  let choice: Str = _str_of(cv);
  if choice.len() == 0 {
    return _msg(id, "choice is empty");
  }
  let po: Option[JsonValue] = _field(av, "probabilities");
  if !po.is_some {
    return _msg(id, "missing probabilities");
  }
  let pv: JsonValue = po.value;
  var labels: Vec[Str] = Vec[Str].new();
  var micros: Vec[Int] = Vec[Int].new();
  var total: Int = 0;
  var max_micro: Int = -1;
  var picked_micro: Int = -1;
  var ok: Bool = false;
  match pv {
    JsonValue.Object(pe) => {
      if pe.keys.len() == 0 {
        return _msg(id, "probabilities is empty");
      }
      ok = true;
      var j: Int = 0;
      while j < pe.keys.len() {
        let pl: Str = pe.keys[j];
        let pval: JsonValue = pe.values[j];
        if !_num_of(pval) {
          return _msg(id, "probability '" + pl + "' is not a number");
        }
        let f: Float64 = _num_value(pval);
        if !_unit_ok(f) {
          return _msg(id, "probability '" + pl + "' out of range");
        }
        let m: Int = _micro_of_unit(f);
        if m > max_micro { max_micro = m; }
        if compare.str_compare(pl, choice) == 0 { picked_micro = m; }
        total = total + m;
        labels.push(pl);
        micros.push(m);
        j = j + 1;
      }
    },
    _ => {
      return _msg(id, "probabilities is not an object");
    },
  };
  if !ok {
    return _msg(id, "probabilities is not an object");
  }
  if picked_micro < 0 {
    return _msg(id, "choice '" + choice + "' is not in probabilities");
  }
  if picked_micro != max_micro {
    return _msg(id, "choice '" + choice + "' is not the highest-probability option");
  }
  if total < _SUM_LO || total > _SUM_HI {
    return _msg(id, "probabilities sum out of tolerance");
  }
  let cfo: Option[JsonValue] = _field(av, "confidence");
  if !cfo.is_some {
    return _msg(id, "missing confidence");
  }
  let cfv: JsonValue = cfo.value;
  if !_num_of(cfv) {
    return _msg(id, "confidence is not a number");
  }
  let cf: Float64 = _num_value(cfv);
  if !_unit_ok(cf) {
    return _msg(id, "confidence out of range");
  }
  out.choices.push(choice);
  out.confidence_micro.push(_micro_of_unit(cf));
  out.score_micro.push(0);
  out.noul_micro.push(0);
  out.prob_starts.push(out.prob_labels.len());
  out.prob_counts.push(labels.len());
  out.legend_starts.push(out.legend_labels.len());
  out.legend_counts.push(0);
  var j: Int = 0;
  while j < labels.len() {
    let l: Str = labels[j];
    let m: Int = micros[j];
    out.prob_labels.push(l);
    out.prob_micro.push(m);
    j = j + 1;
  }
  return "";
}

fn _parse_score_answer(id: Str, av: JsonValue, out: &mut Answers) -> Str {
  let so: Option[JsonValue] = _field(av, "score");
  if !so.is_some {
    return _msg(id, "missing score");
  }
  let sv: JsonValue = so.value;
  if !_num_of(sv) {
    return _msg(id, "score is not a number");
  }
  let sf: Float64 = _num_value(sv);
  if !(sf >= 0.0) {
    return _msg(id, "score out of range");
  }
  if !(sf <= 10.0) {
    return _msg(id, "score out of range");
  }
  let lo: Option[JsonValue] = _field(av, "legend");
  if !lo.is_some {
    return _msg(id, "missing legend");
  }
  let lv: JsonValue = lo.value;
  var legend_keys: Vec[Str] = Vec[Str].new();
  var legend_docs: Vec[JsonValue] = Vec[JsonValue].new();
  var legend_ok: Bool = false;
  match lv {
    JsonValue.Object(le) => {
      if le.keys.len() == 0 {
        return _msg(id, "legend is empty");
      }
      legend_ok = true;
      var j: Int = 0;
      while j < le.keys.len() {
        let lk: Str = le.keys[j];
        let lvv: JsonValue = le.values[j];
        legend_keys.push(lk);
        legend_docs.push(lvv);
        j = j + 1;
      }
    },
    _ => {
      return _msg(id, "legend is not an object");
    },
  };
  if !legend_ok {
    return _msg(id, "legend is not an object");
  }
  let po: Option[JsonValue] = _field(av, "probabilities");
  if !po.is_some {
    return _msg(id, "missing probabilities");
  }
  let pv: JsonValue = po.value;
  var labels: Vec[Str] = Vec[Str].new();
  var micros: Vec[Int] = Vec[Int].new();
  var total: Int = 0;
  var ok: Bool = false;
  match pv {
    JsonValue.Object(pe) => {
      if pe.keys.len() == 0 {
        return _msg(id, "probabilities is empty");
      }
      ok = true;
      var j: Int = 0;
      while j < pe.keys.len() {
        let pl: Str = pe.keys[j];
        let pval: JsonValue = pe.values[j];
        if !_num_of(pval) {
          return _msg(id, "probability '" + pl + "' is not a number");
        }
        let f: Float64 = _num_value(pval);
        if !_unit_ok(f) {
          return _msg(id, "probability '" + pl + "' out of range");
        }
        if !_keys_have(&legend_keys, pl) {
          return _msg(id, "probability '" + pl + "' is not in legend");
        }
        let m: Int = _micro_of_unit(f);
        total = total + m;
        labels.push(pl);
        micros.push(m);
        j = j + 1;
      }
    },
    _ => {
      return _msg(id, "probabilities is not an object");
    },
  };
  if !ok {
    return _msg(id, "probabilities is not an object");
  }
  if total < _SUM_LO || total > _SUM_HI {
    return _msg(id, "probabilities sum out of tolerance");
  }
  let cfo: Option[JsonValue] = _field(av, "confidence");
  if !cfo.is_some {
    return _msg(id, "missing confidence");
  }
  let cfv: JsonValue = cfo.value;
  if !_num_of(cfv) {
    return _msg(id, "confidence is not a number");
  }
  let cf: Float64 = _num_value(cfv);
  if !_unit_ok(cf) {
    return _msg(id, "confidence out of range");
  }
  out.choices.push("");
  out.confidence_micro.push(_micro_of_unit(cf));
  out.score_micro.push(math.round(sf * 1000000.0));
  out.noul_micro.push(0);
  out.prob_starts.push(out.prob_labels.len());
  out.prob_counts.push(labels.len());
  var j: Int = 0;
  while j < labels.len() {
    let l: Str = labels[j];
    let m: Int = micros[j];
    out.prob_labels.push(l);
    out.prob_micro.push(m);
    j = j + 1;
  }
  out.legend_starts.push(out.legend_labels.len());
  out.legend_counts.push(legend_keys.len());
  j = 0;
  while j < legend_keys.len() {
    out.legend_labels.push(legend_keys[j]);
    out.legend_docs.push(legend_docs[j]);
    j = j + 1;
  }
  return "";
}

fn _parse_noul_answer(id: Str, av: JsonValue, out: &mut Answers) -> Str {
  let no: Option[JsonValue] = _field(av, "noul");
  if !no.is_some {
    return _msg(id, "missing noul");
  }
  let nv: JsonValue = no.value;
  if !_num_of(nv) {
    return _msg(id, "noul is not a number");
  }
  let nf: Float64 = _num_value(nv);
  if !_unit_ok(nf) {
    return _msg(id, "noul out of range");
  }
  out.choices.push("");
  out.confidence_micro.push(-1);
  out.score_micro.push(0);
  out.noul_micro.push(_micro_of_unit(nf));
  out.prob_starts.push(out.prob_labels.len());
  out.prob_counts.push(0);
  out.legend_starts.push(out.legend_labels.len());
  out.legend_counts.push(0);
  return "";
}

fn _parse_answer(id: Str, av: JsonValue, out: &mut Answers) -> Str {
  match av {
    JsonValue.Object(_body) => {},
    _ => {
      return _msg(id, "not an object");
    },
  };
  let to: Option[JsonValue] = _field(av, "type");
  if !to.is_some {
    return _msg(id, "missing type");
  }
  let tv: JsonValue = to.value;
  if !_is_string(tv) {
    return _msg(id, "type is not a string");
  }
  let ts: Str = _str_of(tv);
  var kind: Int = -1;
  if compare.str_compare(ts, "choice") == 0 {
    kind = types.KIND_CHOICE;
  } elif compare.str_compare(ts, "score") == 0 {
    kind = types.KIND_SCORE;
  } elif compare.str_compare(ts, "noul") == 0 {
    kind = types.KIND_NOUL;
  } else {
    return _msg(id, "unknown answer type '" + ts + "'");
  }
  var reason: Str = "";
  if kind == types.KIND_CHOICE {
    reason = _parse_choice_answer(id, av, out);
  } elif kind == types.KIND_SCORE {
    reason = _parse_score_answer(id, av, out);
  } else {
    reason = _parse_noul_answer(id, av, out);
  }
  if reason.len() > 0 {
    return reason;
  }
  out.ids.push(id);
  out.kinds.push(kind);
  return "";
}

// --------------------------------------------------
//  Root
// --------------------------------------------------

fn _parse_root(root: JsonValue) -> Result[Response, JevError] {
  var root_ok: Bool = false;
  match root {
    JsonValue.Object(_root_body) => {
      root_ok = true;
    },
    _ => {},
  };
  if !root_ok {
    return _perr("response: root is not an object");
  }
  let mo: Option[JsonValue] = _field(root, "model");
  if !mo.is_some {
    return _perr("response: missing model");
  }
  let mv: JsonValue = mo.value;
  if !_is_string(mv) {
    return _perr("response: model is not a string");
  }
  let model: Str = _str_of(mv);
  if model.len() == 0 {
    return _perr("response: model is empty");
  }
  var ans: Answers = types.answers_new();
  let ao: Option[JsonValue] = _field(root, "answers");
  if !ao.is_some {
    return _perr("response: missing answers");
  }
  let av: JsonValue = ao.value;
  var answers_ok: Bool = false;
  match av {
    JsonValue.Object(entries) => {
      if entries.keys.len() == 0 {
        return _perr("response: answers is empty");
      }
      answers_ok = true;
      var k: Int = 0;
      while k < entries.keys.len() {
        let id: Str = entries.keys[k];
        let av2: JsonValue = entries.values[k];
        let reason: Str = _parse_answer(id, av2, &mut ans);
        if reason.len() > 0 {
          return _perr(reason);
        }
        k = k + 1;
      }
    },
    _ => {
      return _perr("response: answers is not an object");
    },
  };
  if !answers_ok {
    return _perr("response: answers is not an object");
  }
  var has_usage: Int = 0;
  var in_tokens: Int = 0;
  var out_tokens: Int = 0;
  let uo: Option[JsonValue] = _field(root, "usage");
  if uo.is_some {
    let uv: JsonValue = uo.value;
    var usage_ok: Bool = false;
    match uv {
      JsonValue.Object(_usage_body) => {
        usage_ok = true;
        let iopt: Option[JsonValue] = _field(uv, "input_tokens");
        if iopt.is_some {
          let iv: JsonValue = iopt.value;
          if !_num_of(iv) {
            return _perr("response: usage.input_tokens is not a number");
          }
          let inf: Float64 = _num_value(iv);
          if !(inf >= 0.0) {
            return _perr("response: usage.input_tokens out of range");
          }
          if !(inf <= 1000000000000.0) {
            return _perr("response: usage.input_tokens out of range");
          }
          in_tokens = math.round(inf);
        }
        let oopt: Option[JsonValue] = _field(uv, "output_tokens");
        if oopt.is_some {
          let ov: JsonValue = oopt.value;
          if !_num_of(ov) {
            return _perr("response: usage.output_tokens is not a number");
          }
          let onf: Float64 = _num_value(ov);
          if !(onf >= 0.0) {
            return _perr("response: usage.output_tokens out of range");
          }
          if !(onf <= 1000000000000.0) {
            return _perr("response: usage.output_tokens out of range");
          }
          out_tokens = math.round(onf);
        }
      },
      _ => {
        return _perr("response: usage is not an object");
      },
    };
    if !usage_ok {
      return _perr("response: usage is not an object");
    }
    has_usage = 1;
  }
  let resp: Response = Response{
    model: model,
    answers: ans,
    has_usage: has_usage,
    input_tokens: in_tokens,
    output_tokens: out_tokens,
  };
  return _ok_response(resp);
}

/// parse_response parses a System One response body into a typed Response.
/// See the module header for the validation rules; failures carry
/// JevError.Parse with the stable reasons of SPEC.md section 6.
/// Complexity: O(body). Pure.
pub fn parse_response(body: Str) -> Result[Response, JevError] {
  let parsed: Result[JsonValue, Str] = json.json_parse(body);
  if !parsed.is_ok {
    return _perr("response: invalid JSON");
  }
  let root: JsonValue = parsed.value;
  return _parse_root(root);
}

/// api_error_detail is the best-effort human message of a TypeSafe API error
/// body. Recognized shapes (FastAPI/OpenAPI conventions, see SPEC.md
/// section 2): {"detail": "<message>"} and the 422 shape
/// {"detail": [{"loc": [...], "msg": "<message>", "type": "..."}]} (the
/// first element's "msg"). Returns "" when the body is not JSON or carries
/// neither shape; the client then falls back to a raw body preview.
/// Complexity: O(body). Pure.
pub fn api_error_detail(body: Str) -> Str {
  let parsed: Result[JsonValue, Str] = json.json_parse(body);
  if !parsed.is_ok {
    return "";
  }
  let root: JsonValue = parsed.value;
  let do_opt: Option[JsonValue] = _field(root, "detail");
  if !do_opt.is_some {
    return "";
  }
  let dv: JsonValue = do_opt.value;
  if _is_string(dv) {
    return _str_of(dv);
  }
  match dv {
    JsonValue.Array(items) => {
      if items.len() == 0 {
        return "";
      }
      let first: JsonValue = items[0];
      let mo: Option[JsonValue] = _field(first, "msg");
      if mo.is_some {
        let mv: JsonValue = mo.value;
        if _is_string(mv) {
          return _str_of(mv);
        }
      }
      return "";
    },
    _ => {
      return "";
    },
  };
  return "";
}
