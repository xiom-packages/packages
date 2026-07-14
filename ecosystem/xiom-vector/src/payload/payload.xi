module xiom.vector.payload.payload

// Payload = the schemaless metadata attached to a point (used for filtering and
// returned alongside search hits). `FieldValue` is a tagged union over the
// supported scalar types. SCAFFOLD: today this is a linear list of fields; Phase
// 3 backs it with a sorted key index and typed columns for fast filtering.

pub enum FieldValue {
  IntVal(v: Int),
  FloatVal(v: Float32),
  TextVal(v: Str),
  BoolVal(v: Bool),
}

pub type PayloadField = {
  key: Str;
  value: FieldValue;
}

pub type Payload = {
  fields: Vec[PayloadField];
}

pub fn payload_new() -> Payload {
  var fields = Vec[PayloadField].new();
  return Payload{ fields: fields };
}

pub fn payload_set(p: &mut Payload, key: Str, value: FieldValue) {
  // TODO(Phase 3): overwrite an existing key instead of appending duplicates,
  // and maintain a sorted key index for O(log n) lookup.
  p.fields.push(PayloadField{ key: key, value: value });
}

pub fn payload_has(p: &Payload, key: Str) -> Bool {
  var i: Int = 0;
  while i < p.fields.len() {
    if p.fields[i].key == key {
      return true;
    }
    i = i + 1;
  }
  return false;
}

pub fn payload_len(p: &Payload) -> Int {
  return p.fields.len();
}

pub fn field_value_kind(v: &FieldValue) -> Str {
  match v {
    IntVal(_) => "int",
    FloatVal(_) => "float",
    TextVal(_) => "text",
    BoolVal(_) => "bool",
  }
}
