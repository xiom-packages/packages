module probe_debug_filter

use xiom.vector.engine;
use xiom.vectors;
use xiom.vector.payload.payload;
use xiom.vector.payload.filter_ast;
use xiom.io;

fn b2s(b: Bool) -> Str { if b { return "true"; } return "false"; }

fn main() -> Int {
  var p = payload_new();
  payload_set(&mut p, "color", FieldValue.TextVal("red"));
  var same = FieldValue.TextVal("red");
  match payload_get(&p, "color") {
    Some(v) => { io.println("get kind=" + field_value_kind(&v) + " eq=" + b2s(field_value_eq(&v, &same))); }
    None => { io.println("get none"); }
  }
  var e = filter_eq("color", FieldValue.TextVal("red"));
  io.println("Eq text=" + b2s(filter_matches(&e, &p)));
  var ei = filter_eq("n", FieldValue.IntVal(5));
  var pi = payload_new();
  payload_set(&mut pi, "n", FieldValue.IntVal(5));
  io.println("Eq int=" + b2s(filter_matches(&ei, &pi)));
  var r = filter_range("price", 0.0, 100.0);
  var pr = payload_new();
  payload_set(&mut pr, "price", FieldValue.FloatVal(50.0));
  io.println("Range=" + b2s(filter_matches(&r, &pr)));
  var vals = Vec[FieldValue].new();
  vals.push(FieldValue.TextVal("red"));
  var e_in = filter_in("color", vals);
  io.println("In=" + b2s(filter_matches(&e_in, &p)));
  return 0;
}
