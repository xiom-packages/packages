// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.helm.release: release install/upgrade/rollback state machine
// Port task: pure-XIOM release model with revision history and explicit status
// transitions. No Kubernetes API, no networking: every operation returns a
// new Release value (Result carries an error message on invalid transitions).
//
// Model: a Release is three index-aligned parallel vectors (revisions,
// statuses, notes) plus the release name. _rpush is the single push site.
// Transitions are validated against the latest revision's status; completing
// an upgrade/rollback marks every earlier 'deployed' revision 'superseded'.
// Statuses follow Helm's names. See SPEC.md section 5 for the transition
// table and the exact error catalog.

module xiom.helm.release

use xiom.helm.base;
use xiom.string;
use xiom.convert;

// --------------------------------------------------
//  Limits and statuses
// --------------------------------------------------

/// Maximum release name length (DNS-subdomain rule, as in Helm).
pub const HELM_RELEASE_NAME_MAX: Int = 53;
/// Maximum number of revisions in one release history.
pub const HELM_RELEASE_MAX_REVISIONS: Int = 100;

/// Status of a release with no revisions.
pub const HELM_STATUS_UNKNOWN: Str = "unknown";
/// Install started, not completed.
pub const HELM_STATUS_PENDING_INSTALL: Str = "pending-install";
/// Upgrade started, not completed.
pub const HELM_STATUS_PENDING_UPGRADE: Str = "pending-upgrade";
/// Rollback started, not completed.
pub const HELM_STATUS_PENDING_ROLLBACK: Str = "pending-rollback";
/// The live revision.
pub const HELM_STATUS_DEPLOYED: Str = "deployed";
/// A revision replaced by a later upgrade/rollback.
pub const HELM_STATUS_SUPERSEDED: Str = "superseded";
/// A pending operation that failed.
pub const HELM_STATUS_FAILED: Str = "failed";
/// The release was uninstalled.
pub const HELM_STATUS_UNINSTALLED: Str = "uninstalled";

// --------------------------------------------------
//  Model and leaf constructors
// --------------------------------------------------

/// A release history: `revisions` holds 1-based revision numbers in order,
/// `statuses` the per-revision status and `notes` the per-revision
/// description, all index-aligned. The latest revision is the last one.
pub type Release = {
  name: Str;
  revisions: Vec[Int];
  statuses: Vec[Str];
  notes: Vec[Str];
}

fn _rel_ok(r: Release) -> Result[Release, Str] {
  return Ok(r);
}

fn _rel_err(m: Str) -> Result[Release, Str] {
  return Err(m);
}

/// Create a release with no revisions (status HELM_STATUS_UNKNOWN). Err on an
/// invalid release name (helm_dns_name_valid with the 53-byte limit).
pub fn release_create(name: Str) -> Result[Release, Str] {
  if !base.helm_dns_name_valid(name, HELM_RELEASE_NAME_MAX) {
    return _rel_err("release: invalid release name: " + name);
  }
  return _rel_ok(Release{ name: name; revisions: Vec[Int].new(); statuses: Vec[Str].new(); notes: Vec[Str].new(); });
}

// Aligned history length (min of the three vectors).
fn _rmin_len(r: &Release) -> Int {
  var n = r.revisions.len();
  if r.statuses.len() < n {
    n = r.statuses.len();
  }
  if r.notes.len() < n {
    n = r.notes.len();
  }
  return n;
}

// The single push site for the three parallel vectors.
fn _rpush(r: &mut Release, rev: Int, status: Str, note: Str) {
  r.revisions.push(rev);
  r.statuses.push(status);
  r.notes.push(note);
}

fn _copy_release(r: &Release) -> Release {
  var out = Release{ name: r.name; revisions: Vec[Int].new(); statuses: Vec[Str].new(); notes: Vec[Str].new(); };
  let n = _rmin_len(r);
  var i = 0;
  while i < n {
    let rv: Int = r.revisions[i];
    let st: Str = r.statuses[i];
    let nt: Str = r.notes[i];
    _rpush(&mut out, rv, st, nt);
    i = i + 1;
  }
  return out;
}

fn _status_at(r: &Release, i: Int) -> Str {
  if i < 0 || i >= _rmin_len(r) {
    return "";
  }
  let s: Str = r.statuses[i];
  return s;
}

fn _is_pending(s: Str) -> Bool {
  if base.helm_streq(s, HELM_STATUS_PENDING_INSTALL) {
    return true;
  }
  if base.helm_streq(s, HELM_STATUS_PENDING_UPGRADE) {
    return true;
  }
  return base.helm_streq(s, HELM_STATUS_PENDING_ROLLBACK);
}

// Index of revision `rev` in the history, or -1.
fn _revision_index(r: &Release, rev: Int) -> Int {
  let n = _rmin_len(r);
  var i = 0;
  while i < n {
    let rv: Int = r.revisions[i];
    if rv == rev {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// --------------------------------------------------
//  Accessors
// --------------------------------------------------

/// The release name.
pub fn release_name(r: &Release) -> Str {
  return r.name;
}

/// Number of revisions in the history.
pub fn release_history_len(r: &Release) -> Int {
  return _rmin_len(r);
}

/// Latest revision number, or 0 when the history is empty.
pub fn release_revision(r: &Release) -> Int {
  let n = _rmin_len(r);
  if n == 0 {
    return 0;
  }
  let rv: Int = r.revisions[n - 1];
  return rv;
}

/// Status of the latest revision, or HELM_STATUS_UNKNOWN when empty.
pub fn release_status(r: &Release) -> Str {
  let n = _rmin_len(r);
  if n == 0 {
    return HELM_STATUS_UNKNOWN;
  }
  return _status_at(r, n - 1);
}

/// Status at history index `i` (0-based), or "" out of range.
pub fn release_status_at(r: &Release, i: Int) -> Str {
  return _status_at(r, i);
}

/// Note at history index `i` (0-based), or "" out of range.
pub fn release_note_at(r: &Release, i: Int) -> Str {
  if i < 0 || i >= _rmin_len(r) {
    return "";
  }
  let nt: Str = r.notes[i];
  return nt;
}

/// True when the latest revision is deployed.
pub fn release_is_deployed(r: &Release) -> Bool {
  return base.helm_streq(release_status(r), HELM_STATUS_DEPLOYED);
}

/// Number of history entries with status `status`.
pub fn release_count_status(r: &Release, status: Str) -> Int {
  var count = 0;
  let n = _rmin_len(r);
  var i = 0;
  while i < n {
    let st: Str = r.statuses[i];
    if base.helm_streq(st, status) {
      count = count + 1;
    }
    i = i + 1;
  }
  return count;
}

/// True when `s` is one of the eight documented status names.
pub fn release_status_known(s: Str) -> Bool {
  if base.helm_streq(s, HELM_STATUS_UNKNOWN) {
    return true;
  }
  if _is_pending(s) {
    return true;
  }
  if base.helm_streq(s, HELM_STATUS_DEPLOYED) {
    return true;
  }
  if base.helm_streq(s, HELM_STATUS_SUPERSEDED) {
    return true;
  }
  if base.helm_streq(s, HELM_STATUS_FAILED) {
    return true;
  }
  return base.helm_streq(s, HELM_STATUS_UNINSTALLED);
}

// --------------------------------------------------
//  Transitions
// --------------------------------------------------

/// Begin an install: append revision 1 with status pending-install and the
/// given note. Err when the history is not empty.
pub fn release_begin_install(r: &Release, note: Str) -> Result[Release, Str] {
  if _rmin_len(r) != 0 {
    return _rel_err("release: install requires an empty revision history");
  }
  var out = _copy_release(r);
  _rpush(&mut out, 1, HELM_STATUS_PENDING_INSTALL, note);
  return _rel_ok(out);
}

/// Complete the latest pending revision: it becomes deployed, and every
/// earlier deployed revision becomes superseded. Err when there is no
/// revision or the latest status is not pending-install/upgrade/rollback.
pub fn release_complete(r: &Release) -> Result[Release, Str] {
  let n = _rmin_len(r);
  if n == 0 {
    return _rel_err("release: complete requires a pending revision");
  }
  let st = _status_at(r, n - 1);
  if !_is_pending(st) {
    return _rel_err("release: complete requires a pending status, got: " + st);
  }
  var out = _copy_release(r);
  var i = 0;
  while i < n - 1 {
    let s: Str = out.statuses[i];
    if base.helm_streq(s, HELM_STATUS_DEPLOYED) {
      out.statuses[i] = HELM_STATUS_SUPERSEDED;
    }
    i = i + 1;
  }
  out.statuses[n - 1] = HELM_STATUS_DEPLOYED;
  return _rel_ok(out);
}

/// Begin an upgrade: append revision n+1 with status pending-upgrade and the
/// given note. Allowed only when the latest status is deployed or failed;
/// Err on an empty history, another status, or a full history (100 revisions).
pub fn release_upgrade(r: &Release, note: Str) -> Result[Release, Str] {
  let n = _rmin_len(r);
  if n == 0 {
    return _rel_err("release: upgrade requires an installed release");
  }
  let st = _status_at(r, n - 1);
  if !base.helm_streq(st, HELM_STATUS_DEPLOYED) && !base.helm_streq(st, HELM_STATUS_FAILED) {
    return _rel_err("release: cannot upgrade from status: " + st);
  }
  if n >= HELM_RELEASE_MAX_REVISIONS {
    return _rel_err("release: revision limit reached");
  }
  var out = _copy_release(r);
  _rpush(&mut out, n + 1, HELM_STATUS_PENDING_UPGRADE, note);
  return _rel_ok(out);
}

/// Begin a rollback to `target` (a 1-based revision number): append revision
/// n+1 with status pending-rollback and the given note. The target must exist,
/// differ from the latest revision, and have status deployed or superseded.
/// Err on an empty history, an unknown/current target, another target status,
/// or a full history.
pub fn release_rollback(r: &Release, target: Int, note: Str) -> Result[Release, Str] {
  let n = _rmin_len(r);
  if n == 0 {
    return _rel_err("release: rollback requires an installed release");
  }
  if target < 1 || target > n {
    return _rel_err("release: unknown revision: " + convert.int_to_string(target));
  }
  if target == n {
    return _rel_err("release: cannot roll back to the current revision: " + convert.int_to_string(target));
  }
  let idx = _revision_index(r, target);
  let tst = _status_at(r, idx);
  if !base.helm_streq(tst, HELM_STATUS_DEPLOYED) && !base.helm_streq(tst, HELM_STATUS_SUPERSEDED) {
    return _rel_err("release: cannot roll back to revision " + convert.int_to_string(target) + " with status: " + tst);
  }
  if n >= HELM_RELEASE_MAX_REVISIONS {
    return _rel_err("release: revision limit reached");
  }
  var out = _copy_release(r);
  _rpush(&mut out, n + 1, HELM_STATUS_PENDING_ROLLBACK, note);
  return _rel_ok(out);
}

/// Fail the latest pending revision: its status becomes failed and its note is
/// replaced by `reason`. Err when there is no revision or the latest status is
/// not pending.
pub fn release_fail(r: &Release, reason: Str) -> Result[Release, Str] {
  let n = _rmin_len(r);
  if n == 0 {
    return _rel_err("release: fail requires a pending revision");
  }
  let st = _status_at(r, n - 1);
  if !_is_pending(st) {
    return _rel_err("release: fail requires a pending status, got: " + st);
  }
  var out = _copy_release(r);
  out.statuses[n - 1] = HELM_STATUS_FAILED;
  out.notes[n - 1] = reason;
  return _rel_ok(out);
}

/// Uninstall the release: the latest revision (which must be deployed) becomes
/// uninstalled. No new revision is appended; the history is kept.
pub fn release_uninstall(r: &Release) -> Result[Release, Str] {
  let n = _rmin_len(r);
  if n == 0 {
    return _rel_err("release: uninstall requires an installed release");
  }
  let st = _status_at(r, n - 1);
  if !base.helm_streq(st, HELM_STATUS_DEPLOYED) {
    return _rel_err("release: uninstall requires status deployed, got: " + st);
  }
  var out = _copy_release(r);
  out.statuses[n - 1] = HELM_STATUS_UNINSTALLED;
  return _rel_ok(out);
}
