// Bindings-lane compiler probe: nondeterministic enum-payload codegen.
//
// This is the PRE-FIX xiom.sqlite value model (enum with payloads) reduced to
// one file: constructors, match-based accessors, a row/result container and
// clone helpers. Build+run it repeatedly; each invocation rebuilds the
// binary. Observed on v0.64.0: in a fraction of builds every accessor below
// reports false (the enum layout/dispatch is miscompiled globally for that
// build) while other builds are fully green. In the pre-fix package this
// made the conformance suite alternate 16/16 and 11/16 across rebuilds; a
// 4-check micro variant flipped to all-false in 1 of 6 builds.
//
// Healthy build:  all lines true, exit 0.
// Bad build:      one or more lines false, exit 1 (often ALL false).

module bindings_enum_nd_probe

use xiom.io;
use xiom.convert;

pub type ProbeValue = {
  value: ProbeKind;
}

pub enum ProbeKind {
  Null,
  Integer(value: Int),
  Real(value: Float64),
  Text(value: Str),
  Blob(value: Vec[Int]),
}

pub type ProbeRow = {
  columns: Vec[ProbeValue];
}

pub type ProbeResult = {
  rows: Vec[ProbeRow];
  column_names: Vec[Str];
}

fn v_null() -> ProbeValue {
  return ProbeValue{ value: ProbeKind.Null };
}
fn v_int(v: Int) -> ProbeValue {
  return ProbeValue{ value: ProbeKind.Integer(v) };
}
fn v_text(v: Str) -> ProbeValue {
  return ProbeValue{ value: ProbeKind.Text(v) };
}

fn as_int(val: &ProbeValue) -> Option[Int] {
  match val.value {
    ProbeKind.Integer(value) => Some(value),
    _ => None,
  }
}

fn as_text(val: &ProbeValue) -> Option[Str] {
  match val.value {
    ProbeKind.Text(value) => Some(value),
    _ => None,
  }
}

fn is_null(val: &ProbeValue) -> Bool {
  match val.value {
    ProbeKind.Null => true,
    _ => false,
  }
}

fn clone_value(v: &ProbeValue) -> ProbeValue {
  match v.value {
    ProbeKind.Null => v_null(),
    ProbeKind.Integer(value) => ProbeValue{ value: ProbeKind.Integer(value) },
    ProbeKind.Real(value) => ProbeValue{ value: ProbeKind.Real(value) },
    ProbeKind.Text(value) => ProbeValue{ value: ProbeKind.Text(value) },
    ProbeKind.Blob(value) => ProbeValue{ value: ProbeKind.Blob(value) },
  }
}

fn row_new() -> ProbeRow {
  var cols = Vec[ProbeValue].new();
  return ProbeRow{ columns: cols };
}

fn row_add(row: &mut ProbeRow, value: ProbeValue) {
  row.columns.push(value);
}

fn row_get(row: &ProbeRow, index: Int) -> Option[ProbeValue] {
  if index < 0 { return None; }
  if index >= row.columns.len() { return None; }
  return Some(clone_value(&row.columns[index]));
}

fn result_new() -> ProbeResult {
  var rows = Vec[ProbeRow].new();
  var names = Vec[Str].new();
  return ProbeResult{ rows: rows, column_names: names };
}

fn result_get_row(result: &ProbeResult, index: Int) -> Option[ProbeRow] {
  if index < 0 { return None; }
  if index >= result.rows.len() { return None; }
  return Some(result.rows[index]);
}

fn b2s(b: Bool) -> Str {
  if b { return "true"; }
  return "false";
}

fn main() -> Int {
  // A: direct accessor
  let iv = v_int(2);
  let oa = as_int(&iv);
  var a = false;
  if oa.is_some { a = oa.value == 2; }

  // B: text accessor through row get
  var row = row_new();
  row_add(&mut row, v_int(2));
  row_add(&mut row, v_text("beta"));
  let vb = row_get(&row, 1);
  var b = false;
  if vb.is_some {
    let ot = as_text(&vb.value);
    if ot.is_some { b = ot.value.len() == 4; }
  }

  // C: null tagging
  let nv = v_null();
  let c = is_null(&nv);

  // D: through the result container
  var res = result_new();
  var r2 = row_new();
  row_add(&mut r2, v_int(7));
  row_add(&mut r2, v_text("gamma"));
  res.rows.push(r2);
  res.column_names.push("id");
  res.column_names.push("name");
  var d = false;
  let got = result_get_row(&res, 0);
  if got.is_some {
    let rw = got.value;
    let v0 = row_get(&rw, 0);
    let v2 = row_get(&rw, 1);
    if v0.is_some {
      if v2.is_some {
        let i0 = as_int(&v0.value);
        let t2 = as_text(&v2.value);
        if i0.is_some {
          if t2.is_some {
            d = (i0.value == 7);
            if t2.value.len() != 5 { d = false; }
          }
        }
      }
    }
  }

  io.println("A=" + b2s(a) + " B=" + b2s(b) + " C=" + b2s(c) + " D=" + b2s(d));
  var all = a;
  if !b { all = false; }
  if !c { all = false; }
  if !d { all = false; }
  if all { return 0; }
  return 1;
}
