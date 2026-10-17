// XIOM -- xiom.jev.beam: hierarchical beam search over Choice probabilities
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The first M3 decision-systems helper: a pure, deterministic beam search
// over a hierarchy of Choice probability distributions.
//
// A hierarchy is an ordered vector of BeamLevel values. Level 0 is the first
// (root) level, level 1 its children, and so on. Each level carries the
// conditional distribution over its options given the prefix; the levels use
// the package's existing encoded probabilities (Int micro units, 1.0 =
// 1000000) and a label per option, exactly like Answers.prob_labels /
// prob_micro. A path is one label per level.
//
// Search is level-by-level: start with the empty path at score 1.0, expand
// every kept path with every option of the next level, rank the expanded
// paths, and keep the best `width` for the next level. The path score is the
// product of the option probabilities, carried in micro units and normalized
// after each expansion with truncating integer division:
//
//   score_0 = MICRO
//   score_{i+1} = (score_i * micro_i) / MICRO
//
// The arithmetic is integer-only (no Float64) and identical on every
// platform. With two micro values the multiplication cannot exceed 10^12.
//
// Deterministic tie-breaking (pinned): paths are ranked by score_micro
// descending; equal scores keep DISCOVERY ORDER, which is the previous
// beam order (already ranked) as the outer loop and the level's option order
// as the inner loop. There is no hash iteration or randomness anywhere.
//
// The result carries the final ranked paths (at most `width`, best first),
// the configured width and the number of levels searched. Malformed input
// fails closed with a typed JevError.BadRequest whose reason starts "beam: ":
//
//   beam: width must be positive
//   beam: missing levels
//   beam: empty children at level <n>          (1-based)
//   beam: level <n>: malformed children
//   beam: level <n>: label is empty
//   beam: level <n>: duplicate label '<label>'
//   beam: level <n>: probability out of range
//   beam: answer <i> is not a choice           (beam_level_from_answer)
//   beam: answer <i> has no probabilities      (beam_level_from_answer)
//
// Accessors guard every index and return the documented empty sentinel.

module xiom.jev.beam

use xiom.jev.errors;
use xiom.jev.types;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Types and builders
// --------------------------------------------------

/// BeamLevel is one level of a choice hierarchy: labels[j] is option j's
/// label and micro[j] its probability in micro units. The two vectors are
/// parallel and must have the same length (see beam_search).
pub type BeamLevel = {
  labels: Vec[Str];
  micro: Vec[Int];
}

/// BeamPath is one label per level plus its cumulative micro score.
pub type BeamPath = {
  labels: Vec[Str];
  score_micro: Int;
}

/// BeamResult is the ranked search outcome: at most `width` paths, best
/// first, over `levels` levels.
pub type BeamResult = {
  width: Int;
  levels: Int;
  paths: Vec[BeamPath];
}

/// beam_level_new returns an empty level (zero options). Add options with
/// beam_add_option. Complexity: O(1). Pure.
pub fn beam_level_new() -> BeamLevel {
  return BeamLevel{ labels: Vec[Str].new(), micro: Vec[Int].new() };
}

/// beam_add_option appends one option to a level. Complexity: O(1)
/// amortized. Mutates level.
pub fn beam_add_option(level: &mut BeamLevel, label: Str, micro: Int) {
  level.labels.push(label);
  level.micro.push(micro);
}

/// beam_level_len is the number of options in a level. Complexity: O(1).
pub fn beam_level_len(level: &BeamLevel) -> Int {
  return level.labels.len();
}

// --------------------------------------------------
//  Answer bridge
// --------------------------------------------------

/// beam_level_from_answer builds a BeamLevel from choice answer i of a
/// parsed Response, reusing the encoded probability distribution carried by
/// Answers (wire order labels + micro values). Fails typed when the answer
/// is out of range, not a Choice answer, or carries no probabilities.
/// Complexity: O(n). Pure.
pub fn beam_level_from_answer(r: &Response, i: Int) -> Result[BeamLevel, JevError] {
  if types.response_kind(r, i) != types.KIND_CHOICE {
    return Err(JevError.BadRequest("beam: answer " + convert.to_string(i) + " is not a choice"));
  }
  let n: Int = types.response_prob_count(r, i);
  if n <= 0 {
    return Err(JevError.BadRequest("beam: answer " + convert.to_string(i) + " has no probabilities"));
  }
  var level: BeamLevel = beam_level_new();
  var j: Int = 0;
  while j < n {
    let label: Str = types.response_prob_label(r, i, j);
    let micro: Int = types.response_prob_micro(r, i, j);
    level.labels.push(label);
    level.micro.push(micro);
    j = j + 1;
  }
  return Ok(level);
}

// --------------------------------------------------
//  Search core
// --------------------------------------------------

fn _invalid(reason: Str) -> Result[BeamResult, JevError] {
  return Err(JevError.BadRequest(reason));
}

fn _level_reason(li: Int, suffix: Str) -> Str {
  return "beam: level " + convert.to_string(li + 1) + ": " + suffix;
}

fn _validate_level(level: &BeamLevel, li: Int) -> Str {
  let n: Int = level.labels.len();
  if n == 0 {
    return "beam: empty children at level " + convert.to_string(li + 1);
  }
  if level.micro.len() != n {
    return _level_reason(li, "malformed children");
  }
  var j: Int = 0;
  while j < n {
    let label: Str = level.labels[j];
    if label.len() == 0 {
      return _level_reason(li, "label is empty");
    }
    let micro: Int = level.micro[j];
    if micro < 0 || micro > types.MICRO {
      return _level_reason(li, "probability out of range");
    }
    var k: Int = 0;
    while k < j {
      let other: Str = level.labels[k];
      if compare.str_compare(other, label) == 0 {
        return _level_reason(li, "duplicate label '" + label + "'");
      }
      k = k + 1;
    }
    j = j + 1;
  }
  return "";
}

fn _path_extend(prefix: &BeamPath, label: Str, micro: Int) -> BeamPath {
  var labels: Vec[Str] = Vec[Str].new();
  var i: Int = 0;
  while i < prefix.labels.len() {
    labels.push(prefix.labels[i]);
    i = i + 1;
  }
  labels.push(label);
  let score: Int = (prefix.score_micro * micro) / types.MICRO;
  return BeamPath{ labels: labels, score_micro: score };
}

// _rank_keep keeps the best `width` paths by score descending; equal scores
// keep the lower discovery index (the input order), so the result is stable.
fn _rank_keep(paths: Vec[BeamPath], width: Int) -> Vec[BeamPath] {
  let n: Int = paths.len();
  var used: Vec[Int] = Vec[Int].new();
  var i: Int = 0;
  while i < n {
    used.push(0);
    i = i + 1;
  }
  var out: Vec[BeamPath] = Vec[BeamPath].new();
  var k: Int = 0;
  while k < width && k < n {
    var best: Int = -1;
    var j: Int = 0;
    while j < n {
      if used[j] == 0 {
        if best < 0 {
          best = j;
        } else {
          let cur: Int = paths[j].score_micro;
          let kept: Int = paths[best].score_micro;
          if cur > kept { best = j; }
        }
      }
      j = j + 1;
    }
    if best < 0 { break; }
    out.push(paths[best]);
    used[best] = 1;
    k = k + 1;
  }
  return out;
}

/// beam_search runs a deterministic beam search over `levels`, keeping the
/// best `width` paths at every level (see the module header for the score
/// rule and the tie order). Rejections are JevError.BadRequest with the
/// stable "beam: " reasons listed above. Complexity: O(width * options *
/// levels + ranking), pure.
pub fn beam_search(levels: Vec[BeamLevel], width: Int) -> Result[BeamResult, JevError] {
  if width <= 0 {
    return _invalid("beam: width must be positive");
  }
  if levels.len() == 0 {
    return _invalid("beam: missing levels");
  }
  var li: Int = 0;
  while li < levels.len() {
    let level: BeamLevel = levels[li];
    let reason: Str = _validate_level(&level, li);
    if reason.len() > 0 {
      return _invalid(reason);
    }
    li = li + 1;
  }
  var beam: Vec[BeamPath] = Vec[BeamPath].new();
  beam.push(BeamPath{ labels: Vec[Str].new(), score_micro: types.MICRO });
  li = 0;
  while li < levels.len() {
    let level: BeamLevel = levels[li];
    var expanded: Vec[BeamPath] = Vec[BeamPath].new();
    var b: Int = 0;
    while b < beam.len() {
      let prefix: BeamPath = beam[b];
      var o: Int = 0;
      while o < level.labels.len() {
        let label: Str = level.labels[o];
        let micro: Int = level.micro[o];
        expanded.push(_path_extend(&prefix, label, micro));
        o = o + 1;
      }
      b = b + 1;
    }
    beam = _rank_keep(expanded, width);
    li = li + 1;
  }
  return Ok(BeamResult{ width: width, levels: levels.len(), paths: beam });
}

// --------------------------------------------------
//  Accessors (every index is guarded)
// --------------------------------------------------

/// beam_result_count is the number of kept paths (0 when empty).
/// Complexity: O(1).
pub fn beam_result_count(r: &BeamResult) -> Int {
  return r.paths.len();
}

/// beam_result_width is the configured beam width. Complexity: O(1).
pub fn beam_result_width(r: &BeamResult) -> Int {
  return r.width;
}

/// beam_result_levels is the number of levels searched. Complexity: O(1).
pub fn beam_result_levels(r: &BeamResult) -> Int {
  return r.levels;
}

/// beam_result_path_levels is path i's depth (0 when out of range).
/// Complexity: O(1).
pub fn beam_result_path_levels(r: &BeamResult, i: Int) -> Int {
  if i < 0 || i >= r.paths.len() { return 0; }
  let p: BeamPath = r.paths[i];
  return p.labels.len();
}

/// beam_result_path_score is path i's cumulative micro score (-1 when i is
/// out of range). Complexity: O(1).
pub fn beam_result_path_score(r: &BeamResult, i: Int) -> Int {
  if i < 0 || i >= r.paths.len() { return -1; }
  let p: BeamPath = r.paths[i];
  return p.score_micro;
}

/// beam_result_path_label is path i's label at level j ("" when out of
/// range). Complexity: O(1).
pub fn beam_result_path_label(r: &BeamResult, i: Int, j: Int) -> Str {
  if i < 0 || i >= r.paths.len() { return ""; }
  let p: BeamPath = r.paths[i];
  if j < 0 || j >= p.labels.len() { return ""; }
  return p.labels[j];
}

/// beam_result_path_text joins path i's labels with `sep` ("" when out of
/// range). Complexity: O(len). Pure.
pub fn beam_result_path_text(r: &BeamResult, i: Int, sep: Str) -> Str {
  if i < 0 || i >= r.paths.len() { return ""; }
  let p: BeamPath = r.paths[i];
  var out: Str = "";
  var j: Int = 0;
  while j < p.labels.len() {
    let label: Str = p.labels[j];
    if j == 0 {
      out = label;
    } else {
      out = out + sep + label;
    }
    j = j + 1;
  }
  return out;
}

/// beam_path_score is one path's cumulative micro score. Complexity: O(1).
pub fn beam_path_score(p: &BeamPath) -> Int {
  return p.score_micro;
}

/// beam_path_levels is one path's depth. Complexity: O(1).
pub fn beam_path_levels(p: &BeamPath) -> Int {
  return p.labels.len();
}

/// beam_path_text joins one path's labels with `sep`. Complexity: O(len).
pub fn beam_path_text(p: &BeamPath, sep: Str) -> Str {
  var out: Str = "";
  var j: Int = 0;
  while j < p.labels.len() {
    let label: Str = p.labels[j];
    if j == 0 {
      out = label;
    } else {
      out = out + sep + label;
    }
    j = j + 1;
  }
  return out;
}
