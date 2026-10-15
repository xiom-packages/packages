module ptypes

pub enum KV {
  Null,
  Integer(value: Int),
  Text(value: Str),
}

pub type V = {
  kind: KV;
}

pub type Row = {
  cols: Vec[V];
}

pub fn v_int(x: Int) -> V {
  return V{ kind: KV.Integer(x) };
}

pub fn row_new() -> Row {
  var r = Row{ cols: Vec[V].new() };
  return r;
}

pub fn row_add(r: &mut Row, v: V)
  requires: true
{
  r.cols.push(v);
}

pub fn mk2() -> Row {
  var r = row_new();
  row_add(&mut r, v_int(1));
  row_add(&mut r, v_int(2));
  return r;
}
