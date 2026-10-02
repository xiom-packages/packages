// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.helm.repo: repository index subset (index.yaml) parse/render
// Port task: pure-XIOM repository index model with a bounded, documented
// index.yaml subset: top-level apiVersion, an `entries:` block, and flat
// `- name: ...` entry stanzas with name/version/appVersion/description/urls.
// urls is a comma-separated inline list in this subset (not a YAML sequence).
// No networking and no file I/O.
//
// Model: five index-aligned parallel vectors (_idx_push is the single push
// site). Str comparisons go through base.helm_streq; bytes through _byte.

module xiom.helm.repo

use xiom.helm.base;
use xiom.string;
use xiom.convert;

// --------------------------------------------------
//  Limits
// --------------------------------------------------

/// Maximum number of chart entries in one index.
pub const HELM_MAX_ENTRIES: Int = 512;
/// Maximum accepted index text length, in bytes.
pub const HELM_MAX_INDEX_INPUT: Int = 65536;

const _HASH: Int = 35;
const _DQUOTE: Int = 34;
const _CR: Int = 13;
const _TAB: Int = 9;
const _SPACE: Int = 32;
const _COLON: Int = 58;
const _COMMA: Int = 44;
const _DASH: Int = 45;

// --------------------------------------------------
//  Model and leaf constructors
// --------------------------------------------------

/// A repository index subset: `api_version` plus the chart entry columns
/// `names`, `versions`, `app_versions`, `descriptions` and `urls` (each urls
/// cell is a canonical comma+space separated list, possibly ""). All columns
/// are index-aligned; build with repo_index_add or repo_index_parse.
pub type RepoIndex = {
  api_version: Str;
  names: Vec[Str];
  versions: Vec[Str];
  app_versions: Vec[Str];
  descriptions: Vec[Str];
  urls: Vec[Str];
}

fn _repo_ok(i: RepoIndex) -> Result[RepoIndex, Str] {
  return Ok(i);
}

fn _repo_err(m: Str) -> Result[RepoIndex, Str] {
  return Err(m);
}

/// An empty index with apiVersion "v1".
pub fn repo_index_new() -> RepoIndex {
  return RepoIndex{ api_version: "v1"; names: Vec[Str].new(); versions: Vec[Str].new(); app_versions: Vec[Str].new(); descriptions: Vec[Str].new(); urls: Vec[Str].new(); };
}

// --------------------------------------------------
//  Private helpers
// --------------------------------------------------

fn _byte(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// Aligned entry count (min across all five columns).
fn _idx_min_len(idx: &RepoIndex) -> Int {
  var n = idx.names.len();
  if idx.versions.len() < n {
    n = idx.versions.len();
  }
  if idx.app_versions.len() < n {
    n = idx.app_versions.len();
  }
  if idx.descriptions.len() < n {
    n = idx.descriptions.len();
  }
  if idx.urls.len() < n {
    n = idx.urls.len();
  }
  return n;
}

// The single push site for all five parallel vectors.
fn _idx_push(idx: &mut RepoIndex, name: Str, version: Str, app: Str, desc: Str, urls: Str) {
  idx.names.push(name);
  idx.versions.push(version);
  idx.app_versions.push(app);
  idx.descriptions.push(desc);
  idx.urls.push(urls);
}

fn _copy_index(idx: &RepoIndex) -> RepoIndex {
  var out = RepoIndex{ api_version: idx.api_version; names: Vec[Str].new(); versions: Vec[Str].new(); app_versions: Vec[Str].new(); descriptions: Vec[Str].new(); urls: Vec[Str].new(); };
  let n = _idx_min_len(idx);
  var i = 0;
  while i < n {
    let nm: Str = idx.names[i];
    let vr: Str = idx.versions[i];
    let ap: Str = idx.app_versions[i];
    let ds: Str = idx.descriptions[i];
    let us: Str = idx.urls[i];
    _idx_push(&mut out, nm, vr, ap, ds, us);
    i = i + 1;
  }
  return out;
}

fn _strip_cr(s: Str) -> Str {
  let n = string.str_len(s);
  if n > 0 && _byte(s, n - 1) == _CR {
    return string.str_slice(s, 0, n - 1);
  }
  return s;
}

fn _unquote(s: Str) -> Str {
  let n = string.str_len(s);
  if n >= 2 && _byte(s, 0) == _DQUOTE && _byte(s, n - 1) == _DQUOTE {
    return string.str_slice(s, 1, n - 1);
  }
  return s;
}

// First ':' in `line`, or -1.
fn _find_colon(line: Str) -> Int {
  var i = 0;
  let n = string.str_len(line);
  while i < n {
    if _byte(line, i) == _COLON {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// True when the trimmed line opens an entry item ("- " prefix).
fn _starts_item(line: Str) -> Bool {
  if string.str_len(line) < 2 {
    return false;
  }
  if _byte(line, 0) != _DASH {
    return false;
  }
  let c = _byte(line, 1);
  return c == _SPACE || c == _TAB;
}

// Canonicalize a comma-separated url list: tokens trimmed, empty tokens
// dropped, joined with ", ". "" -> "".
fn _norm_urls(raw: Str) -> Str {
  var out = "";
  let n = string.str_len(raw);
  var i = 0;
  while i <= n {
    var j = i;
    while j < n && _byte(raw, j) != _COMMA {
      j = j + 1;
    }
    let tok = string.str_trim(string.str_slice(raw, i, j));
    if string.str_len(tok) > 0 {
      if string.str_len(out) > 0 {
        out = out + ", ";
      }
      out = out + tok;
    }
    if j >= n {
      return out;
    }
    i = j + 1;
  }
  return out;
}

// --------------------------------------------------
//  Construction and access
// --------------------------------------------------

/// Append one chart entry in a new index. Err on an invalid chart name
/// (helm_dns_name_valid, 253) or version (semver), or when the index already
/// holds HELM_MAX_ENTRIES entries. `urls` is split on commas, trimmed and
/// canonicalized; empty tokens are dropped.
pub fn repo_index_add(idx: &RepoIndex, name: Str, version: Str, app_version: Str, description: Str, urls: Str) -> Result[RepoIndex, Str] {
  if !base.helm_dns_name_valid(name, base.HELM_CHART_NAME_MAX) {
    return _repo_err("repo: invalid chart name: " + name);
  }
  if !base.helm_semver_valid(version) {
    return _repo_err("repo: invalid chart version: " + version);
  }
  if _idx_min_len(idx) >= HELM_MAX_ENTRIES {
    return _repo_err("repo: entry limit reached");
  }
  var out = _copy_index(idx);
  _idx_push(&mut out, name, version, app_version, description, _norm_urls(urls));
  return _repo_ok(out);
}

/// Number of entries.
pub fn repo_index_len(idx: &RepoIndex) -> Int {
  return _idx_min_len(idx);
}

/// Chart name at 0-based entry index `i`, or "" out of range.
pub fn repo_index_name(idx: &RepoIndex, i: Int) -> Str {
  if i < 0 || i >= _idx_min_len(idx) {
    return "";
  }
  let s: Str = idx.names[i];
  return s;
}

/// Chart version at 0-based entry index `i`, or "" out of range.
pub fn repo_index_version(idx: &RepoIndex, i: Int) -> Str {
  if i < 0 || i >= _idx_min_len(idx) {
    return "";
  }
  let s: Str = idx.versions[i];
  return s;
}

/// Chart appVersion at 0-based entry index `i`, or "" out of range.
pub fn repo_index_app_version(idx: &RepoIndex, i: Int) -> Str {
  if i < 0 || i >= _idx_min_len(idx) {
    return "";
  }
  let s: Str = idx.app_versions[i];
  return s;
}

/// Chart description at 0-based entry index `i`, or "" out of range.
pub fn repo_index_description(idx: &RepoIndex, i: Int) -> Str {
  if i < 0 || i >= _idx_min_len(idx) {
    return "";
  }
  let s: Str = idx.descriptions[i];
  return s;
}

/// Canonical url list at 0-based entry index `i`, or "" out of range.
pub fn repo_index_urls(idx: &RepoIndex, i: Int) -> Str {
  if i < 0 || i >= _idx_min_len(idx) {
    return "";
  }
  let s: Str = idx.urls[i];
  return s;
}

/// Index of the first entry with exactly `name` and `version`, or -1.
pub fn repo_index_find(idx: &RepoIndex, name: Str, version: Str) -> Int {
  let n = _idx_min_len(idx);
  var i = 0;
  while i < n {
    let nm: Str = idx.names[i];
    let vr: Str = idx.versions[i];
    if base.helm_streq(nm, name) && base.helm_streq(vr, version) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Number of entries whose chart name is exactly `name`.
pub fn repo_index_count_name(idx: &RepoIndex, name: Str) -> Int {
  var count = 0;
  let n = _idx_min_len(idx);
  var i = 0;
  while i < n {
    let nm: Str = idx.names[i];
    if base.helm_streq(nm, name) {
      count = count + 1;
    }
    i = i + 1;
  }
  return count;
}

// --------------------------------------------------
//  Parsing
// --------------------------------------------------

/// Parse the documented index.yaml subset. Grammar (SPEC.md section 6):
/// lines split on LF (one trailing CR stripped); blank lines and full-line
/// '#' comments skipped. Top level before any entry: `apiVersion: v1` and
/// `entries:`; any other line is an error. Entries start with `- name: X`
/// (a 'name' field is required as the first field of a stanza); following
/// `key: value` lines are fields (name/version/appVersion/description/urls,
/// last wins; unknown keys are ignored). Values may be double-quoted; urls is
/// comma-separated inline. Errors: see SPEC.md section 9.
pub fn repo_index_parse(text: Str) -> Result[RepoIndex, Str] {
  if base.helm_has_nul(text) {
    return _repo_err("repo: NUL byte in input");
  }
  if string.str_len(text) > HELM_MAX_INDEX_INPUT {
    return _repo_err("repo: input too large");
  }
  var api = "v1";
  var out = repo_index_new();
  var have_cur = false;
  var cur_name = "";
  var cur_version = "";
  var cur_app = "";
  var cur_desc = "";
  var cur_urls = "";
  let lines = string.str_split(text, "\n");
  let ln = lines.len();
  var li = 0;
  while li < ln {
    let raw0: Str = lines[li];
    let line = string.str_trim(_strip_cr(raw0));
    let n = string.str_len(line);
    if n == 0 {
      li = li + 1;
      continue;
    }
    if _byte(line, 0) == _HASH {
      li = li + 1;
      continue;
    }
    if _starts_item(line) {
      if have_cur {
        let fr = _flush_entry(&out, cur_name, cur_version, cur_app, cur_desc, cur_urls);
        match fr {
          Ok(m) => { out = m; },
          Err(e) => { return _repo_err(e); },
        }
      }
      let body = string.str_trim(string.str_slice(line, 1, n));
      let colon = _find_colon(body);
      if colon < 0 {
        return _repo_err("repo: expected ':' in entry line: " + line);
      }
      let key = string.str_trim(string.str_slice(body, 0, colon));
      if !base.helm_streq(key, "name") {
        return _repo_err("repo: entry must start with name: " + line);
      }
      let val = _unquote(string.str_trim(string.str_slice(body, colon + 1, string.str_len(body))));
      have_cur = true;
      cur_name = val;
      cur_version = "";
      cur_app = "";
      cur_desc = "";
      cur_urls = "";
      li = li + 1;
      continue;
    }
    let colon = _find_colon(line);
    if colon < 0 {
      return _repo_err("repo: expected ':' in line: " + line);
    }
    let key = string.str_trim(string.str_slice(line, 0, colon));
    if string.str_len(key) == 0 {
      return _repo_err("repo: missing key in line: " + line);
    }
    let val = _unquote(string.str_trim(string.str_slice(line, colon + 1, n)));
    if !have_cur {
      if base.helm_streq(key, "apiVersion") {
        if !base.helm_streq(val, "v1") {
          return _repo_err("repo: unsupported apiVersion: " + val);
        }
        api = val;
      } elif base.helm_streq(key, "entries") {
        if string.str_len(val) > 0 {
          return _repo_err("repo: malformed entries line: " + line);
        }
      } else {
        return _repo_err("repo: unexpected line: " + line);
      }
    } else {
      if base.helm_streq(key, "name") {
        cur_name = val;
      } elif base.helm_streq(key, "version") {
        cur_version = val;
      } elif base.helm_streq(key, "appVersion") {
        cur_app = val;
      } elif base.helm_streq(key, "description") {
        cur_desc = val;
      } elif base.helm_streq(key, "urls") {
        cur_urls = val;
      }
    }
    li = li + 1;
  }
  if have_cur {
    let fr = _flush_entry(&out, cur_name, cur_version, cur_app, cur_desc, cur_urls);
    match fr {
      Ok(m) => { out = m; },
      Err(e) => { return _repo_err(e); },
    }
  }
  out.api_version = api;
  return _repo_ok(out);
}

// Validate one parsed stanza and append it; shared by both flush sites.
fn _flush_entry(out: &RepoIndex, name: Str, version: Str, app: Str, desc: Str, urls: Str) -> Result[RepoIndex, Str] {
  if string.str_len(name) == 0 {
    return _repo_err("repo: entry missing name");
  }
  if string.str_len(version) == 0 {
    return _repo_err("repo: entry missing version");
  }
  if !base.helm_dns_name_valid(name, base.HELM_CHART_NAME_MAX) {
    return _repo_err("repo: invalid chart name: " + name);
  }
  if !base.helm_semver_valid(version) {
    return _repo_err("repo: invalid chart version: " + version);
  }
  if _idx_min_len(out) >= HELM_MAX_ENTRIES {
    return _repo_err("repo: entry limit reached");
  }
  var next = _copy_index(out);
  _idx_push(&mut next, name, version, app, desc, _norm_urls(urls));
  return _repo_ok(next);
}

// --------------------------------------------------
//  Rendering
// --------------------------------------------------

/// Render an index to canonical subset text: `apiVersion: v1`, `entries:` and
/// one stanza per entry (five lines each, in column order), LF separated, no
/// trailing LF. An empty index renders as "apiVersion: v1\nentries:".
/// repo_index_parse(repo_index_render(idx)) round-trips all five columns for
/// values without line breaks or surrounding double quotes.
pub fn repo_index_render(idx: &RepoIndex) -> Str {
  var out = "apiVersion: " + idx.api_version + "\nentries:";
  let n = _idx_min_len(idx);
  var i = 0;
  while i < n {
    let nm: Str = idx.names[i];
    let vr: Str = idx.versions[i];
    let ap: Str = idx.app_versions[i];
    let ds: Str = idx.descriptions[i];
    let us: Str = idx.urls[i];
    out = out + "\n  - name: " + nm;
    out = out + "\n    version: " + vr;
    out = out + "\n    appVersion: " + ap;
    out = out + "\n    description: " + ds;
    out = out + "\n    urls: " + us;
    i = i + 1;
  }
  return out;
}
