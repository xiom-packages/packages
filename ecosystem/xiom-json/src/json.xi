module xiom.json

pub enum JsonValue {
  Null,
  Bool(value: Bool),
  Number(value: Float64),
  String(value: Str),
  Array(items: Vec[JsonValue]),
  Object(entries: Vec[JsonEntry]),
} derive[Clone]

pub type JsonEntry = {
  key: Str;
  value: JsonValue;
} derive[Clone]

pub type ParseError = {
  message: Str;
  position: Int;
} derive[Clone]

pub fn json_get(obj: &JsonValue, key: Str) -> Option[JsonValue] {
  match obj {
    JsonValue.Object(entries) => {
      var i: Int = 0;
      while i < entries.len() {
        if entries[i].key == key {
          return Some(entries[i].value.clone());
        }
        i = i + 1;
      }
      return None;
    },
    _ => None,
  }
}

pub fn json_stringify(value: &JsonValue) -> Str {
  match value {
    JsonValue.Null => "null",
    JsonValue.Bool(v) => {
      if v { return "true"; }
      return "false";
    },
    JsonValue.Number(v) => "0",
    JsonValue.String(v) => "string",
    JsonValue.Array(items) => "array",
    JsonValue.Object(entries) => "object",
  }
}

pub fn json_parse(input: Str) -> Result[JsonValue, ParseError]
  requires: input.len() > 0
{
  return Err(ParseError{ message: "JSON parsing requires stdlib string functions (Layer 2)", position: 0 });
}
