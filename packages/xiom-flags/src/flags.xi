// XIOM -- xiom.flags: command-line flag and argument parsing
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A small, dependency-light flag parser for XIOM CLI programs. Declared flags
// are stored in parallel arrays inside FlagParser (the current compiler cannot
// reliably hold Vec[StructType] containers), and environment fallback is read
// from xiom.env when a declared flag was not provided on the command line.
//
// Accepted argument grammar (see SPEC.md for the full contract):
//   --name            boolean long flag
//   --name=value      inline value
//   --name value      spaced value (only when the flag takes a value)
//   -s                boolean short flag
//   -s value          spaced value (only when the short flag takes a value)
//   --                terminator: every later argument is a positional
//   anything else     positional
//
// Unknown flags and missing values are reported as Err; required flags are
// checked after parsing and can be satisfied by an environment variable.

module xiom.flags

use xiom.string;
use xiom.string.compare;
use xiom.convert;
use xiom.os.args;
use xiom.env;

// FlagParser holds every declared flag in parallel arrays:
//   names       -- long name without dashes
//   shorts      -- one-character short name, "" when unused
//   env_vars    -- environment fallback variable, "" when unused
//   helps       -- help text, "" when unused
//   values      -- last command-line value seen for the flag
//   takes_value -- whether the flag consumes a value
//   required    -- whether the flag must be provided
//   present     -- whether the flag appeared on the command line
//   positionals -- non-flag arguments, in order
// All fields are internal: use the flags_* functions below.
pub type FlagParser = {
  names: Vec[Str];
  shorts: Vec[Str];
  env_vars: Vec[Str];
  helps: Vec[Str];
  values: Vec[Str];
  takes_value: Vec[Bool];
  required: Vec[Bool];
  present: Vec[Bool];
  positionals: Vec[Str];
}

/// A parser with no declared flags.
pub fn flags_new() -> FlagParser {
  return FlagParser{
    names: Vec[Str].new(),
    shorts: Vec[Str].new(),
    env_vars: Vec[Str].new(),
    helps: Vec[Str].new(),
    values: Vec[Str].new(),
    takes_value: Vec[Bool].new(),
    required: Vec[Bool].new(),
    present: Vec[Bool].new(),
    positionals: Vec[Str].new(),
  };
}

/// Declare a flag. Pass "" for an unused short name, environment variable, or
/// help text. Returns the declaration index (usable as an opaque handle).
/// Precondition: `name` is non-empty; declared names are expected to be unique
/// (the first declaration wins when looking a flag up).
pub fn flags_flag(p: &mut FlagParser, name: Str, short: Str, takes_value: Bool, required: Bool, env_var: Str, help: Str) -> Int {
  p.names.push(name);
  p.shorts.push(short);
  p.env_vars.push(env_var);
  p.helps.push(help);
  p.values.push("");
  p.takes_value.push(takes_value);
  p.required.push(required);
  p.present.push(false);
  return p.names.len() - 1;
}

/// Index of the declared long flag `name`, or -1 when absent.
fn find_long(p: &FlagParser, name: Str) -> Int {
  var i = 0;
  while i < p.names.len() {
    if str_compare(p.names[i], name) == 0 { return i; }
    i = i + 1;
  }
  return -1;
}

/// Index of the declared short flag `short`, or -1 when absent.
fn find_short(p: &FlagParser, short: Str) -> Int {
  var i = 0;
  while i < p.shorts.len() {
    if p.shorts[i].len() > 0 && str_compare(p.shorts[i], short) == 0 { return i; }
    i = i + 1;
  }
  return -1;
}

/// Record `value` as the flag's current command-line value (last one wins).
fn set_value(p: &mut FlagParser, idx: Int, value: Str) {
  p.values[idx] = value;
  p.present[idx] = true;
}

/// Record a boolean flag as provided on the command line.
fn mark_present(p: &mut FlagParser, idx: Int) {
  p.present[idx] = true;
}

/// Read the environment fallback for declaration `i`, or None when the flag
/// declares no environment variable or it is unset.
fn env_fallback(p: &FlagParser, i: Int) -> Option[Str] {
  if p.env_vars[i].len() == 0 { return None; }
  let v = var_opt(p.env_vars[i]);
  return v;
}

/// True when declaration `i` names a set environment variable.
fn has_env(p: &FlagParser, i: Int) -> Bool {
  if p.env_vars[i].len() == 0 { return false; }
  let v = var_opt(p.env_vars[i]);
  match v {
    Some(_) => return true;
    None => return false;
  }
}

/// Handle one `--name` / `--name=value` / `--name value` argument at index
/// `i`. Returns how many argument slots were consumed.
fn handle_long(p: &mut FlagParser, a: Str, args: &Vec[Str], i: Int) -> Result[Int, Str] {
  let eq = index_of(a, "=");
  match eq {
    Some(pos) => {
      if pos <= 2 { return Err("unknown flag: " + a); }
      let fname = str_slice(a, 2, pos);
      let fval = str_slice(a, pos + 1, a.len());
      let fi = find_long(p, fname);
      if fi < 0 { return Err("unknown flag: " + a); }
      set_value(p, fi, fval);
      return Ok(1);
    }
    None => {
      let fname = str_slice(a, 2, a.len());
      let fi = find_long(p, fname);
      if fi < 0 { return Err("unknown flag: " + a); }
      if !p.takes_value[fi] {
        mark_present(p, fi);
        return Ok(1);
      }
      if i + 1 >= args.len() { return Err("missing value for: " + a); }
      set_value(p, fi, args[i + 1]);
      return Ok(2);
    }
  }
}

/// Handle one `-s` / `-s value` argument at index `i`. Only single-character
/// short names are supported. Returns how many argument slots were consumed.
fn handle_short(p: &mut FlagParser, a: Str, args: &Vec[Str], i: Int) -> Result[Int, Str] {
  if a.len() != 2 { return Err("unknown flag: " + a); }
  let s = str_slice(a, 1, 2);
  let si = find_short(p, s);
  if si < 0 { return Err("unknown flag: " + a); }
  if !p.takes_value[si] {
    mark_present(p, si);
    return Ok(1);
  }
  if i + 1 >= args.len() { return Err("missing value for: " + a); }
  set_value(p, si, args[i + 1]);
  return Ok(2);
}

/// Every required flag must be present on the command line or fall back to a
/// set environment variable; checked after the whole argument vector.
fn check_required(p: &FlagParser) -> Result[Unit, Str] {
  var i = 0;
  while i < p.names.len() {
    if p.required[i] && !p.present[i] && !has_env(p, i) {
      return Err("missing required flag: --" + p.names[i]);
    }
    i = i + 1;
  }
  return Ok(());
}

/// Parse `args` into `p`. Later occurrences of a flag overwrite earlier ones
/// (last one wins). On Err the parser state is unspecified: inspect nothing
/// except the error and re-parse with fresh state if needed.
pub fn flags_parse(p: &mut FlagParser, args: &Vec[Str]) -> Result[Unit, Str] {
  var i = 0;
  var terminated = false;
  while i < args.len() {
    let a = args[i];
    if terminated {
      p.positionals.push(a);
      i = i + 1;
    } elif str_compare(a, "--") == 0 {
      terminated = true;
      i = i + 1;
    } elif str_starts_with(a, "--") {
      let consumed = handle_long(p, a, args, i);
      match consumed {
        Ok(n) => { i = i + n; }
        Err(e) => { return Err(e); }
      }
    } elif a.len() >= 2 && str_starts_with(a, "-") {
      let consumed = handle_short(p, a, args, i);
      match consumed {
        Ok(n) => { i = i + n; }
        Err(e) => { return Err(e); }
      }
    } else {
      p.positionals.push(a);
      i = i + 1;
    }
  }
  return check_required(p);
}

/// Parse the process's own arguments (xiom.os.args.args_raw(), skipping the
/// program name at index 0) into `p`.
pub fn flags_parse_process(p: &mut FlagParser) -> Result[Unit, Str] {
  let raw = args_raw();
  var tail = Vec[Str].new();
  var i = 1;
  while i < raw.len() {
    tail.push(raw[i]);
    i = i + 1;
  }
  return flags_parse(p, &tail);
}

/// True when the flag was provided on the command line, or when its declared
/// environment variable is set. False for undeclared names.
pub fn flags_has(p: &FlagParser, name: Str) -> Bool {
  let i = find_long(p, name);
  if i < 0 { return false; }
  if p.present[i] { return true; }
  return has_env(p, i);
}

/// Command-line value of the flag; for boolean flags the presence value is
/// "true". Falls back to the declared environment variable when the flag did
/// not appear on the command line. None when the flag is undeclared, absent
/// and has no set environment variable.
pub fn flags_value(p: &FlagParser, name: Str) -> Option[Str] {
  let i = find_long(p, name);
  if i < 0 { return None; }
  if p.present[i] {
    if p.takes_value[i] { return Some(p.values[i]); }
    return Some("true");
  }
  return env_fallback(p, i);
}

/// Integer value of the flag: Err("flag not provided: <name>") when neither
/// the command line nor the environment supplied a value, otherwise the
/// xiom.convert parse result (Err carries the parser message, e.g.
/// "invalid digit" or "overflow").
pub fn flags_int_value(p: &FlagParser, name: Str) -> Result[Int, Str] {
  let v = flags_value(p, name);
  match v {
    Some(s) => parse_int(s);
    None => Err("flag not provided: " + name);
  }
}

/// Non-flag arguments collected during parsing, in the order seen (including
/// everything after a `--` terminator).
pub fn flags_positionals(p: &FlagParser) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = 0;
  while i < p.positionals.len() {
    out.push(p.positionals[i]);
    i = i + 1;
  }
  return out;
}

/// One line per declared flag:
///   --name, -s VALUE (required) [env: VAR]  help text
/// Missing pieces are omitted. Lines are separated by "\n".
pub fn flags_help(p: &FlagParser) -> Str {
  var out = "";
  var i = 0;
  while i < p.names.len() {
    var line = "  --" + p.names[i];
    if p.shorts[i].len() > 0 { line = line + ", -" + p.shorts[i]; }
    if p.takes_value[i] { line = line + " VALUE"; }
    if p.required[i] { line = line + " (required)"; }
    if p.env_vars[i].len() > 0 { line = line + " [env: " + p.env_vars[i] + "]"; }
    if p.helps[i].len() > 0 { line = line + "  " + p.helps[i]; }
    if out.len() == 0 { out = line; } else { out = out + "\n" + line; }
    i = i + 1;
  }
  return out;
}
