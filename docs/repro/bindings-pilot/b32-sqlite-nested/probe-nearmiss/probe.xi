// Minimal repro attempt: Result[Option[Row]] where Row = { cols: Vec[V] }
// and V wraps an enum with payloads (the xiom.sqlite row shape).
module vecenum_probe

use xiom.io;
use xiom.convert;
use ptypes;

// CROSS-MODULE variant: the row type + builders live in `ptypes`,
// mirroring xiom.sqlite (types in xiom.sqlite.types, query_one in
// xiom.sqlite.rows, extraction in the test module).
fn nested_cross() -> Result[Option[ptypes.Row], Str] {
  return Ok(Some(ptypes.mk2()));
}

pub type E = {
  code: Int;
  msg: Str;
}

// Mirrors the xiom.sqlite error type shape (struct with Str) + in-function
// Err paths before the Ok(Some(row)) construction.
fn query_one_like_e(fail1: Bool, fail2: Bool) -> Result[Option[ptypes.Row], E] {
  if fail1 {
    return Err(E{ code: 21, msg: "prep" });
  }
  var row = ptypes.row_new();
  var has_row = false;
  if fail2 {
    return Err(E{ code: 1, msg: "step" });
  }
  if g_ncols > 0 {
    var k: Int = 0;
    while k < g_ncols {
      ptypes.row_add(&mut row, ptypes.v_int(70 + k));
      k = k + 1;
    }
    has_row = true;
  }
  if has_row {
    return Ok(Some(row));
  }
  return Ok(None);
}

fn query_one_like_cross() -> Result[Option[ptypes.Row], Str] {
  var row = ptypes.row_new();
  var has_row = false;
  if g_ncols > 0 {
    var k: Int = 0;
    while k < g_ncols {
      ptypes.row_add(&mut row, ptypes.v_int(70 + k));
      k = k + 1;
    }
    has_row = true;
  }
  if has_row {
    return Ok(Some(row));
  }
  return Ok(None);
}

pub enum KV {
  Null,
  Integer(value: Int),
  Real(value: Float64),
  Text(value: Str),
  Blob(value: Vec[Int]),
}

pub type V = {
  kind: KV;
}

pub type Row = {
  cols: Vec[V];
}

fn v_int(x: Int) -> V {
  return V{ kind: KV.Integer(x) };
}

fn v_text(s: Str) -> V {
  return V{ kind: KV.Text(s) };
}

fn row_new() -> Row {
  var r = Row{ cols: Vec[V].new() };
  return r;
}

fn row_add(r: &mut Row, v: V)
  requires: true
{
  r.cols.push(v);
}

fn build_via_helper() -> Row {
  var r = row_new();
  row_add(&mut r, v_int(7));
  row_add(&mut r, v_int(9));
  return r;
}

fn build_inline() -> Row {
  var r = Row{ cols: Vec[V].new() };
  r.cols.push(v_int(1));
  r.cols.push(v_text("hello"));
  return r;
}

fn nested_helper() -> Result[Option[Row], Str] {
  return Ok(Some(build_via_helper()));
}

fn nested_inline() -> Result[Option[Row], Str] {
  return Ok(Some(build_inline()));
}

fn flat_control() -> Result[Row, Str] {
  return Ok(build_via_helper());
}

var g_ncols: Int = 2;

fn at(KV: Int) -> V {
  if KV == 0 {
    return v_int(1);
  }
  return v_text("hello");
}

// Mirrors xiom.sqlite query_one: var row + method-ish add in a while loop +
// has_row flag + the two return paths.
fn query_one_like() -> Result[Option[Row], Str] {
  var row = row_new();
  var has_row = false;
  if g_ncols > 0 {
    var KV: Int = 0;
    while KV < g_ncols {
      row_add(&mut row, at(KV));
      KV = KV + 1;
    }
    has_row = true;
  }
  if has_row {
    return Ok(Some(row));
  }
  return Ok(None);
}

fn main() -> Int {
  var bad: Int = 0;

  let f = flat_control();
  if !f.is_ok { io.println("flat err"); bad = bad + 1; } else {
    let frow: Row = f.value;
    io.println("flat cols.len=" + convert.int_to_string(frow.cols.len()) + " (expect 2)");
    if frow.cols.len() != 2 { bad = bad + 1; }
  }

  let h = nested_helper();
  if !h.is_ok { io.println("helper err"); bad = bad + 1; } else {
    let ho = h.value;
    if !ho.is_some { io.println("helper none"); bad = bad + 1; } else {
      let hrow: Row = ho.value;
      io.println("nested(helper) cols.len=" + convert.int_to_string(hrow.cols.len()) + " (expect 2)");
      if hrow.cols.len() != 2 { bad = bad + 1; }
    }
  }

  let i = nested_inline();
  if !i.is_ok { io.println("inline err"); bad = bad + 1; } else {
    let io2 = i.value;
    if !io2.is_some { io.println("inline none"); bad = bad + 1; } else {
      let irow: Row = io2.value;
      io.println("nested(inline) cols.len=" + convert.int_to_string(irow.cols.len()) + " (expect 2)");
      if irow.cols.len() != 2 { bad = bad + 1; }
    }
  }

  let q = query_one_like();
  if !q.is_ok { io.println("qol err"); bad = bad + 1; } else {
    let qo = q.value;
    if !qo.is_some { io.println("qol none"); bad = bad + 1; } else {
      let qrow: Row = qo.value;
      io.println("query_one_like cols.len=" + convert.int_to_string(qrow.cols.len()) + " (expect 2)");
      if qrow.cols.len() != 2 { bad = bad + 1; }
    }
  }

  let cx = nested_cross();
  if !cx.is_ok { io.println("cross err"); bad = bad + 1; } else {
    let cxo = cx.value;
    if !cxo.is_some { io.println("cross none"); bad = bad + 1; } else {
      let prow: ptypes.Row = cxo.value;
      io.println("nested(cross-module) cols.len=" + convert.int_to_string(prow.cols.len()) + " (expect 2)");
      if prow.cols.len() != 2 { bad = bad + 1; }
    }
  }

  let qc = query_one_like_cross();
  if !qc.is_ok { io.println("qoc err"); bad = bad + 1; } else {
    let qco = qc.value;
    if !qco.is_some { io.println("qoc none"); bad = bad + 1; } else {
      let qcrow: ptypes.Row = qco.value;
      io.println("query_one_like_cross cols.len=" + convert.int_to_string(qcrow.cols.len()) + " (expect 2)");
      if qcrow.cols.len() != 2 { bad = bad + 1; }
    }
  }

  let qe = query_one_like_e(false, false);
  if !qe.is_ok { io.println("qoe err"); bad = bad + 1; } else {
    let qeo = qe.value;
    if !qeo.is_some { io.println("qoe none"); bad = bad + 1; } else {
      let qerow: ptypes.Row = qeo.value;
      io.println("query_one_like_e cols.len=" + convert.int_to_string(qerow.cols.len()) + " (expect 2)");
      if qerow.cols.len() != 2 { bad = bad + 1; }
    }
  }

  io.println("failures=" + convert.int_to_string(bad));
  return bad;
}
