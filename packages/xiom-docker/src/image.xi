// XIOM -- xiom.docker.image: Docker image reference parsing and image model
// Port task: replace the xiom.docker placeholder with a real, tested,
// pure-XIOM package (no FFI, no HTTP, no sockets, no daemon).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: the management model behind a Docker-like container engine, as a
// pure deterministic value layer. There is no network, no daemon and no
// clock: every function is a total transition over plain values.
//
// This core module owns:
//   * image references: [registry/]repository[:tag][@sha256:digest]
//     parsing and validation (lowercase repository components, tag grammar,
//     sha256 digest grammar) plus canonical rendering;
//   * images: an ordered, duplicate-free layer digest chain and the config
//     digest.
//
// Companion modules in this package:
//   * xiom.docker (src/docker.xi) -- container state machine
//     (create/start/stop/restart/remove);
//   * xiom.docker.registry (src/registry.xi) -- login state and
//     deterministic push/pull plans;
//   * xiom.docker.compose (src/compose.xi) -- services, dependency graph,
//     topological start order and cycle detection;
//   * xiom.docker.resources (src/resources.xi) -- named volume and network
//     sets with drivers.
//
// Language notes (XIOM v0.62.2): free functions only; Ok/Err are
// constructed only inside the _ok_*/_err_* leaf helpers; every Vec[Int]
// element read binds a typed local; no Str is compared with `==` (all
// equality goes through string.str_compare); lists of names/digests are
// stored as one Str blob plus a monotone Vec[Int] offset table, never as
// Vec[Str]; no Vec[StructType], no indexed Vec[fn] dispatch, no generic
// callbacks, no Vec[Float64], no `mut` in match patterns, no `log`-named
// function.

module xiom.docker.image

use xiom.string;

// ---------------------------------------------------------------------------
// Public constants
// ---------------------------------------------------------------------------

/// Sentinel: unknown id / out-of-range accessor result.
pub const DOCKER_NOT_FOUND: Int = -1;

/// Capacity guard: layers per image.
pub const DOCKER_MAX_LAYERS: Int = 128;

/// Longest accepted tag, in bytes.
pub const DOCKER_MAX_TAG: Int = 128;

/// Byte length of a sha256 digest string ("sha256:" + 64 hex digits).
pub const DOCKER_DIGEST_LEN: Int = 71;

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// A parsed image reference: `registry/repository:tag@digest` where registry
/// defaults to "docker.io", tag defaults to "latest" when neither a tag nor
/// a digest is written, and digest is "" when absent. Fields are
/// implementation detail; use the image_ref_* accessors.
pub type ImageRef = {
  registry: Str;
  repository: Str;
  tag: Str;
  digest: Str;
}

/// An image: the parsed reference fields plus an ordered, duplicate-free
/// layer digest chain and the config digest (both "" until set).
pub type DockerImage = {
  registry: Str;
  repository: Str;
  tag: Str;
  digest: Str;
  config_digest: Str;
  layer_data: Str;
  layer_off: Vec[Int];
}

// ---------------------------------------------------------------------------
// Result constructors (leaf helpers only)
// ---------------------------------------------------------------------------

fn _ok_ref(v: ImageRef) -> Result[ImageRef, Str] { return Ok(v); }
fn _err_ref(m: Str) -> Result[ImageRef, Str] { return Err(m); }
fn _ok_image(v: DockerImage) -> Result[DockerImage, Str] { return Ok(v); }
fn _err_image(m: Str) -> Result[DockerImage, Str] { return Err(m); }
fn _ok_int(v: Int) -> Result[Int, Str] { return Ok(v); }
fn _err_int(m: Str) -> Result[Int, Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Blob helper (Str + monotone Vec[Int] offsets; no Vec[Str])
// ---------------------------------------------------------------------------

// Append `s` to the blob `data`/`offs`. Precondition: offs is non-empty and
// its last entry equals string.str_len(data). Pushes the new end offset and
// returns the extended data string, so the invariant
// offs.len() == count + 1 and offs[count] == string.str_len(data) can never
// drift. Callers assign the returned Str back.
fn _d_blob_append(data: Str, offs: &mut Vec[Int], s: Str) -> Str {
  let start: Int = offs[offs.len() - 1];
  offs.push(start + string.str_len(s));
  return data + s;
}

// ---------------------------------------------------------------------------
// Character classifiers (ASCII only; bytes masked after widening)
// ---------------------------------------------------------------------------

fn _d_is_lower(c: Int) -> Bool { return c >= 0x61 && c <= 0x7A; }
fn _d_is_upper(c: Int) -> Bool { return c >= 0x41 && c <= 0x5A; }
fn _d_is_digit(c: Int) -> Bool { return c >= 0x30 && c <= 0x39; }

fn _d_is_hex_lower(c: Int) -> Bool {
  if _d_is_digit(c) { return true; }
  return c >= 0x61 && c <= 0x66;
}

fn _d_is_sep(c: Int) -> Bool {
  if c == 0x2E { return true; }
  if c == 0x5F { return true; }
  if c == 0x2D { return true; }
  return false;
}

fn _d_is_tag_char(c: Int) -> Bool {
  if _d_is_lower(c) { return true; }
  if _d_is_upper(c) { return true; }
  if _d_is_digit(c) { return true; }
  return _d_is_sep(c);
}

// ---------------------------------------------------------------------------
// Image reference grammar
// ---------------------------------------------------------------------------

// A tag is 1..DOCKER_MAX_TAG tag characters and does not start with '.' or
// '-'.
fn _d_tag_valid(tag: Str) -> Bool {
  let n = string.str_len(tag);
  if n < 1 || n > DOCKER_MAX_TAG { return false; }
  let first: Int = (string.byte_at(tag, 0) as Int) & 0xFF;
  if first == 0x2E || first == 0x2D { return false; }
  var i = 0;
  while i < n {
    let b: Int = (string.byte_at(tag, i) as Int) & 0xFF;
    if !_d_is_tag_char(b) { return false; }
    i = i + 1;
  }
  return true;
}

// One repository path component: lowercase letters, digits and ._-; must
// start and end with a letter or digit.
fn _d_component_valid(comp: Str) -> Bool {
  let n = string.str_len(comp);
  if n < 1 { return false; }
  let first: Int = (string.byte_at(comp, 0) as Int) & 0xFF;
  let last: Int = (string.byte_at(comp, n - 1) as Int) & 0xFF;
  if !_d_is_lower(first) && !_d_is_digit(first) { return false; }
  if !_d_is_lower(last) && !_d_is_digit(last) { return false; }
  var i = 0;
  while i < n {
    let b: Int = (string.byte_at(comp, i) as Int) & 0xFF;
    if !_d_is_lower(b) && !_d_is_digit(b) && !_d_is_sep(b) { return false; }
    i = i + 1;
  }
  return true;
}

// A repository is one or more '/'-separated valid components (no empty
// component, so no leading, trailing or doubled slash).
fn _d_repo_valid(repo: Str) -> Bool {
  let n = string.str_len(repo);
  if n < 1 { return false; }
  var start = 0;
  var i = 0;
  while i < n {
    let b: Int = (string.byte_at(repo, i) as Int) & 0xFF;
    if b == 0x2F {
      if i == start { return false; }
      if !_d_component_valid(string.str_slice(repo, start, i)) { return false; }
      start = i + 1;
    }
    i = i + 1;
  }
  if start == n { return false; }
  return _d_component_valid(string.str_slice(repo, start, n));
}

// A digest is exactly "sha256:" followed by 64 lowercase hex digits.
fn _d_digest_valid(d: Str) -> Bool {
  if string.str_len(d) != DOCKER_DIGEST_LEN { return false; }
  if !string.str_starts_with(d, "sha256:") { return false; }
  var i = 7;
  while i < DOCKER_DIGEST_LEN {
    let b: Int = (string.byte_at(d, i) as Int) & 0xFF;
    if !_d_is_hex_lower(b) { return false; }
    i = i + 1;
  }
  return true;
}

// First '/' of `s`, or -1.
fn _d_find_slash(s: Str) -> Int {
  let n = string.str_len(s);
  var i = 0;
  while i < n {
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if b == 0x2F { return i; }
    i = i + 1;
  }
  return -1;
}

// True when the first path component names a registry: it contains '.' or
// ':' or equals "localhost".
fn _d_is_registry(head: Str) -> Bool {
  let n = string.str_len(head);
  if n == 0 { return false; }
  if string.str_compare(head, "localhost") == 0 { return true; }
  var i = 0;
  while i < n {
    let b: Int = (string.byte_at(head, i) as Int) & 0xFF;
    if b == 0x2E || b == 0x3A { return true; }
    i = i + 1;
  }
  return false;
}

/// Parse `[registry/]repository[:tag][@sha256:digest]` into an ImageRef.
/// Tag defaults to "latest" only when the reference carries neither a tag
/// nor a digest; a digest-only reference keeps tag "".
/// Returns: Ok(ImageRef); Err("image: empty reference"), Err("image:
/// multiple digests"), Err("image: invalid digest"), Err("image: invalid
/// tag") or Err("image: invalid repository").
/// Complexity: O(len).
pub fn image_ref_parse(ref: Str) -> Result[ImageRef, Str] {
  let n = string.str_len(ref);
  if n == 0 { return _err_ref("image: empty reference"); }
  var at = -1;
  var i = 0;
  while i < n {
    let b: Int = (string.byte_at(ref, i) as Int) & 0xFF;
    if b == 0x40 {
      if at >= 0 { return _err_ref("image: multiple digests"); }
      at = i;
    }
    i = i + 1;
  }
  var name_end = n;
  if at >= 0 { name_end = at; }
  var digest = "";
  if at >= 0 {
    digest = string.str_slice(ref, at + 1, n);
    if !_d_digest_valid(digest) { return _err_ref("image: invalid digest"); }
  }
  // The tag separator is the last ':' before the digest; every '/' resets
  // the candidate so a registry port ("host:5000/name") never counts.
  var colon = -1;
  i = 0;
  while i < name_end {
    let b: Int = (string.byte_at(ref, i) as Int) & 0xFF;
    if b == 0x2F {
      colon = -1;
    } elif b == 0x3A {
      colon = i;
    }
    i = i + 1;
  }
  var tag = "";
  var repo_part = ref;
  if at >= 0 { repo_part = string.str_slice(ref, 0, at); }
  if colon >= 0 {
    tag = string.str_slice(ref, colon + 1, name_end);
    repo_part = string.str_slice(ref, 0, colon);
    if !_d_tag_valid(tag) { return _err_ref("image: invalid tag"); }
  } else {
    if at < 0 { tag = "latest"; }
  }
  var registry = "docker.io";
  var repository = repo_part;
  let rn = string.str_len(repo_part);
  let first_slash = _d_find_slash(repo_part);
  if first_slash > 0 {
    let head = string.str_slice(repo_part, 0, first_slash);
    if _d_is_registry(head) {
      registry = head;
      repository = string.str_slice(repo_part, first_slash + 1, rn);
    }
  }
  if !_d_repo_valid(repository) { return _err_ref("image: invalid repository"); }
  return _ok_ref(ImageRef{
    registry: registry;
    repository: repository;
    tag: tag;
    digest: digest;
  });
}

/// Canonical repository-side rendering: "repository[:tag][@digest]".
/// Complexity: O(len).
pub fn image_ref_render(r: &ImageRef) -> Str {
  var out = r.repository;
  if string.str_len(r.tag) > 0 { out = out + ":" + r.tag; }
  if string.str_len(r.digest) > 0 { out = out + "@" + r.digest; }
  return out;
}

/// Registry component ("docker.io" when none was written).
pub fn image_ref_registry(r: &ImageRef) -> Str { return r.registry; }

/// Repository path (no registry, no tag, no digest).
pub fn image_ref_repository(r: &ImageRef) -> Str { return r.repository; }

/// Tag ("" for a digest-only reference, "latest" when omitted).
pub fn image_ref_tag(r: &ImageRef) -> Str { return r.tag; }

/// Digest ("" when absent).
pub fn image_ref_digest(r: &ImageRef) -> Str { return r.digest; }

/// True when the reference carries a digest.
pub fn image_ref_has_digest(r: &ImageRef) -> Bool {
  return string.str_len(r.digest) > 0;
}

/// True when `ref` parses as a valid image reference. Complexity: O(len).
pub fn image_ref_valid(ref: Str) -> Bool {
  match image_ref_parse(ref) {
    Ok(_) => { return true; },
    Err(_) => { return false; },
  }
  return false;
}

/// Fully qualified name "registry/repository". Complexity: O(len).
pub fn image_ref_name(r: &ImageRef) -> Str {
  return r.registry + "/" + r.repository;
}

// ---------------------------------------------------------------------------
// Image model
// ---------------------------------------------------------------------------

/// Build an image from a reference string (parsed and validated). The layer
/// chain starts empty and the config digest is "".
pub fn docker_image_new(ref: Str) -> Result[DockerImage, Str] {
  match image_ref_parse(ref) {
    Ok(r) => {
      var offs = Vec[Int].new();
      offs.push(0);
      return _ok_image(DockerImage{
        registry: r.registry;
        repository: r.repository;
        tag: r.tag;
        digest: r.digest;
        config_digest: "";
        layer_data: "";
        layer_off: offs;
      });
    },
    Err(emsg) => { return _err_image(emsg); },
  }
  return _err_image("image: empty reference");
}

// Slot of `digest` in the layer chain, or -1.
fn _d_layer_index(img: &DockerImage, digest: Str) -> Int {
  var i = 0;
  let cnt = img.layer_off.len() - 1;
  while i < cnt {
    let a: Int = img.layer_off[i];
    let b: Int = img.layer_off[i + 1];
    let cur: Str = string.str_slice(img.layer_data, a, b);
    if string.str_compare(cur, digest) == 0 { return i; }
    i = i + 1;
  }
  return -1;
}

/// Append a layer digest to the chain, rejecting malformed and duplicate
/// digests. Returns the new layer count.
pub fn docker_image_add_layer(img: &mut DockerImage, digest: Str) -> Result[Int, Str] {
  if !_d_digest_valid(digest) { return _err_int("image: invalid layer digest"); }
  if _d_layer_index(img, digest) >= 0 { return _err_int("image: duplicate layer"); }
  let cnt = img.layer_off.len() - 1;
  if cnt >= DOCKER_MAX_LAYERS { return _err_int("image: layer limit exceeded"); }
  img.layer_data = _d_blob_append(img.layer_data, &mut img.layer_off, digest);
  return _ok_int(img.layer_off.len() - 1);
}

/// Set the config digest. Returns 0 on success.
pub fn docker_image_set_config(img: &mut DockerImage, digest: Str) -> Result[Int, Str] {
  if !_d_digest_valid(digest) { return _err_int("image: invalid layer digest"); }
  img.config_digest = digest;
  return _ok_int(0);
}

/// Layer count. Complexity: O(1).
pub fn docker_image_layer_count(img: &DockerImage) -> Int {
  return img.layer_off.len() - 1;
}

/// Layer digest at slot `i`, or "" when out of range. Complexity: O(1).
pub fn docker_image_layer_at(img: &DockerImage, i: Int) -> Str {
  if i < 0 || i >= img.layer_off.len() - 1 { return ""; }
  let a: Int = img.layer_off[i];
  let b: Int = img.layer_off[i + 1];
  return string.str_slice(img.layer_data, a, b);
}

/// True when `digest` is a layer of the chain. Complexity: O(layers).
pub fn docker_image_has_layer(img: &DockerImage, digest: Str) -> Bool {
  return _d_layer_index(img, digest) >= 0;
}

pub fn docker_image_repository(img: &DockerImage) -> Str { return img.repository; }
pub fn docker_image_tag(img: &DockerImage) -> Str { return img.tag; }
pub fn docker_image_digest(img: &DockerImage) -> Str { return img.digest; }
pub fn docker_image_registry(img: &DockerImage) -> Str { return img.registry; }
pub fn docker_image_config_digest(img: &DockerImage) -> Str { return img.config_digest; }
