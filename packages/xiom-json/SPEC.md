# xiom.json SPEC

## Package Overview

`xiom.json` is a production-grade, pure-XIOM JSON library providing parsing, serialization, manipulation, validation, and schema checking. It requires no external C dependencies and operates entirely within the XIOM Layer 1 type system.

**Module**: `xiom.json`
**Version**: 0.1.0
**Dependencies**: None (pure XIOM)

---

## Types

### `JsonValue` (enum)

The core JSON value type representing all six JSON data types.

```
pub enum JsonValue {
  Null,
  Bool(value: Bool),
  Number(value: Float64),
  String(value: Str),
  Array(items: Vec[JsonValue]),
  Object(entries: Vec[JsonEntry]),
} derive[Clone]
```

### `JsonEntry`

A key-value pair used within JSON objects. Maintains insertion order.

```
pub type JsonEntry = {
  key: Str;
  value: JsonValue;
} derive[Clone]
```

### `ParseError`

Error returned when JSON parsing fails. Contains a human-readable message and the line/column position of the error.

```
pub type ParseError = {
  message: Str;
  line: Int;
  column: Int;
} derive[Clone]
```

### `JsonNumber`

Exact numeric representation preserving integer and fractional parts separately. Useful for applications that cannot tolerate Float64 rounding (e.g., financial calculations). Note: the parser currently returns `JsonValue::Number(Float64)`; `JsonNumber` is provided for future exact-parse support.

```
pub type JsonNumber = {
  int_part: Int;
  frac_part: Int;
  frac_digits: Int;
  is_negative: Bool;
} derive[Clone]
```

### `JsonPathSegment` (enum)

A single segment in a JSON path expression.

```
pub enum JsonPathSegment {
  Key(key: Str),
  Index(index: Int),
} derive[Clone]
```

### `JsonPath`

A sequence of path segments for navigating nested JSON structures. Supports dot-notation keys (`.name`) and bracket notation (`[0]`, `['key']`).

```
pub type JsonPath = {
  segments: Vec[JsonPathSegment];
} derive[Clone]
```

### `JsonPrettyConfig`

Configuration for pretty-printed JSON output.

```
pub type JsonPrettyConfig = {
  indent: Int;
  sort_keys: Bool;
} derive[Clone]
```

- `indent`: Number of spaces per indentation level (0 = compact).
- `sort_keys`: If `true`, object keys are sorted alphabetically.

### `JsonType` (enum)

Enum for runtime type checking of JSON values.

```
pub enum JsonType {
  NullType,
  BoolType,
  NumberType,
  StringType,
  ArrayType,
  ObjectType,
}
```

---

## Parsing

### `json_parse`

```xi
pub fn json_parse(input: Str) -> Result[JsonValue, ParseError]
```

Parses a JSON string into a `JsonValue`. Returns `Err(ParseError)` with line/column information on failure.

**Features**:
- Full recursive descent parser with no external dependencies
- Tracks line and column for precise error reporting
- Handles all JSON literals: objects, arrays, strings (with escape sequences), numbers (integer, decimal, scientific notation), booleans, and null
- Detects trailing data after root value
- Validates control characters in strings
- Supports escape sequences: `\"`, `\\`, `\/`, `\b`, `\f`, `\n`, `\r`, `\t`, `\uXXXX`
- Unicode escapes (`\uXXXX`) are accepted and preserved; actual code-point decoding requires Layer 2

**Example**:
```xi
var result = json_parse("{\"name\": \"XIOM\", \"version\": 0.1}");
match result {
  Ok(value) => {
    var name = json_get(&value, "name");
  }
  Err(err) => {
    // err.line, err.column, err.message
  }
}
```

### `json_validate`

```xi
pub fn json_validate(input: Str) -> Result[Bool, ParseError]
```

Validates JSON without building a value tree. Returns `Ok(true)` on valid input, `Err(ParseError)` on invalid input. Same strictness as `json_parse` but discards the parsed tree.

---

## Serialization

### `json_stringify`

```xi
pub fn json_stringify(value: &JsonValue) -> Str
```

Produces compact JSON output with no extra whitespace.

**Features**:
- All JSON types formatted according to RFC 8259
- Strings are properly escaped (control characters, quotes, backslashes)
- Numbers are formatted from Float64 representation
- Nested structures handled recursively

### `json_stringify_pretty`

```xi
pub fn json_stringify_pretty(value: &JsonValue, config: &JsonPrettyConfig) -> Str
```

Produces indented, human-readable JSON output. Respects `config.indent` for indentation width and `config.sort_keys` for alphabetical key ordering.

**Convenience constructors for `JsonPrettyConfig`**:
```xi
JsonPrettyConfig.compact()   // { indent: 0, sort_keys: false }
JsonPrettyConfig.default()   // { indent: 2, sort_keys: false }
JsonPrettyConfig.sorted()    // { indent: 2, sort_keys: true }
```

**Example**:
```xi
var config = JsonPrettyConfig.sorted();
var pretty = json_stringify_pretty(&value, &config);
```

---

## Manipulation API

### `json_get`

```xi
pub fn json_get(obj: &JsonValue, key: Str) -> Option[JsonValue]
```

Retrieves the value associated with a key in a JSON object. Returns `None` if the key does not exist or if the value is not an object.

### `json_get_path`

```xi
pub fn json_get_path(root: &JsonValue, path: &JsonPath) -> Option[JsonValue]
```

Navigates a nested JSON structure following a `JsonPath`. Returns `None` if any segment cannot be traversed.

**Example**:
```xi
var path = JsonPath.new();
path.push_key("users");
path.push_index(0);
path.push_key("name");
var name = json_get_path(&root, &path);
```

### `json_set`

```xi
pub fn json_set(obj: &mut JsonValue, key: Str, value: JsonValue) -> Bool
```

Sets a key to a value in a JSON object. Creates the key if it does not exist. Returns `false` only if `obj` is not an object.

### `json_set_path`

```xi
pub fn json_set_path(root: &mut JsonValue, path: &JsonPath, value: JsonValue) -> Bool
```

Sets a value at a path in a nested JSON structure. Creates intermediate objects as needed for key segments. Returns `false` if the path cannot be traversed (e.g., index into a non-array).

### `json_remove`

```xi
pub fn json_remove(obj: &mut JsonValue, key: Str) -> Bool
```

Removes a key from a JSON object. Returns `true` if the key was found and removed, `false` if the key did not exist or `obj` is not an object.

### `json_has_key`

```xi
pub fn json_has_key(obj: &JsonValue, key: Str) -> Bool
```

Returns `true` if `obj` is an object that contains the given key.

### `json_is_type`

```xi
pub fn json_is_type(value: &JsonValue, expected: JsonType) -> Bool
```

Runtime type check. Returns `true` if the value matches the expected `JsonType`.

**Example**:
```xi
if json_is_type(&value, JsonType.ArrayType) {
  // value is an array
}
```

### `json_merge`

```xi
pub fn json_merge(base: &mut JsonValue, overlay: &JsonValue) -> Bool
```

Deep-merges `overlay` into `base`. Both must be objects. Object-valued keys are recursively merged; non-object keys are replaced by the overlay value. Returns `false` if either argument is not an object.

---

## Validation

### `json_schema_validate`

```xi
pub fn json_schema_validate(value: &JsonValue, schema: &JsonValue) -> Result[Bool, Str]
```

Validates a JSON value against a JSON Schema (draft-04 subset). Returns `Ok(true)` on success, `Err(message)` on failure.

**Supported schema keywords**:
- `type`: String or array of strings (`"object"`, `"array"`, `"string"`, `"number"`, `"boolean"`, `"null"`)
- `enum`: Array of allowed values (deep equality)
- `properties`: Object mapping property names to subschemas
- `required`: Array of required property names

**Example**:
```xi
var schema = json_parse("{\"type\": \"object\", \"properties\": {\"name\": {\"type\": \"string\"}}, \"required\": [\"name\"]}").ok_value();
var data = json_parse("{\"name\": \"XIOM\"}").ok_value();
var result = json_schema_validate(&data, &schema);
```

---

## Convenience Constructors

```xi
pub fn json_null() -> JsonValue
pub fn json_bool(v: Bool) -> JsonValue
pub fn json_number(v: Float64) -> JsonValue
pub fn json_string(v: Str) -> JsonValue
pub fn json_array() -> JsonValue
pub fn json_object() -> JsonValue
pub fn json_array_push(arr: &mut JsonValue, value: JsonValue)
pub fn json_object_put(obj: &mut JsonValue, key: Str, value: JsonValue)
```

---

## JSONPath API

```xi
pub fn JsonPath.new() -> JsonPath
pub fn JsonPath.push_key(key: Str)
pub fn JsonPath.push_index(index: Int)
pub fn JsonPath.parse(path_str: Str) -> Result[JsonPath, Str]
```

`JsonPath.parse` supports a limited subset of JSONPath syntax:
- `$` -- root (optional, ignored)
- `.key` -- dot-notation key access
- `[0]` -- bracket index access
- `['key']` -- bracket key access with single quotes

**Example**:
```xi
var path = JsonPath.parse("$.store.books[0].title").ok_value();
var title = json_get_path(&root, &path);
```

---

## Usage Examples

### Parsing and Accessing Data

```xi
var input = "{\"people\": [{\"name\": \"Alice\", \"age\": 30}, {\"name\": \"Bob\", \"age\": 25}]}";
var parsed = json_parse(input);
match parsed {
  Ok(root) => {
    var people = json_get(&root, "people");
    match people {
      Some(JsonValue.Array(items)) => {
        var i: Int = 0;
        while i < items.len() {
          var name = json_get(&items[i], "name");
          i = i + 1;
        }
      }
      _ => {}
    }
  }
  Err(_) => {}
}
```

### Building and Serializing

```xi
// is a comment since // is a comment prefix. In actual XIOM, // starts a comment.
var obj = json_object();
json_object_put(&mut obj, "name", json_string("XIOM"));
json_object_put(&mut obj, "version", json_number(0.1));

var tags = json_array();
json_array_push(&mut tags, json_string("systems"));
json_array_push(&mut tags, json_string("language"));
json_object_put(&mut obj, "tags", tags);

var output = json_stringify(&obj);
```

### Pretty Printing with Sorted Keys

```xi
var config = JsonPrettyConfig{ indent: 4, sort_keys: true };
var pretty = json_stringify_pretty(&value, &config);
```

### Schema Validation

```xi
var schema_str = "{\"type\": \"object\", \"properties\": {\"name\": {\"type\": \"string\"}, \"age\": {\"type\": \"number\"}}, \"required\": [\"name\"]}";
var schema = json_parse(schema_str).ok_value();

var valid_data = json_parse("{\"name\": \"XIOM\", \"age\": 1}").ok_value();
var result = json_schema_validate(&valid_data, &schema);
// result == Ok(true)

var invalid_data = json_parse("{\"name\": 123}").ok_value();
var result2 = json_schema_validate(&invalid_data, &schema);
// result2 == Err("property 'name': type mismatch")
```

---

## Known Limitations (Layer 2 Dependencies)

The following features require runtime/stdlib support that is not available in pure XIOM Layer 1:

| Feature | Limitation | Layer 2 Solution |
|---------|-----------|-----------------|
| Unicode escape decoding | `\uXXXX` preserves the literal escape; code-point to UTF-8 conversion needs unicode tables | stdlib unicode module |
| Float64 string formatting | `json_stringify` uses a simple float-to-string converter that may produce long trailing digits for some values | `Float64::to_string()` with precision control |
| Float64 parsing precision | Numbers are parsed via manual arithmetic; very large/small numbers may lose precision | `Float64::parse()` using native FPU |
| Str indexing | `input[pos]` for byte access and `Str::len()` are assumed to work; if not, parser requires Vec[UInt8] pre-conversion | stdlib string module |
| Str concatenation | `result = result + str` is assumed to work; if not, all string building requires Vec-based approach | stdlib string builder |
| Vec truncation | `json_remove` builds a new Vec and replaces elements but cannot shrink the Vec without `.truncate()` or `.pop()` | Vec::truncate / Vec::pop |
| Reference reassignment | `json_set_path` reassigns mutable references in a loop; if XIOM does not support this, the function must be restructured | Mutable pointer chains |
| `break` in loops | Not used -- all loops rewritten with flag variables | `break` / `continue` support |
| Generics with constraints | `sort_entries` reimplements quicksort for `JsonEntry` specifically to avoid `[T: Ord]` codegen issues | Full generics support |
| Exact number representation | The `JsonNumber` type is defined but `json_parse` uses `Float64` for the Number variant; a `parse_exact` variant would fill `JsonNumber` | `JsonValue::NumberExact(JsonNumber)` variant |

---

## Design Decisions

### Recursive Descent Parser

The parser is implemented as a set of methods on an internal `JsonParser` type that maintains position, line, and column state. This avoids global mutable state and allows the parser to be re-entrant. The `JsonParser` type is not public -- all access goes through `json_parse` and `json_validate`.

### Byte-Level Comparison

Since XIOM Layer 1 has limited string manipulation, the parser works at the byte level using `input[pos]` to read individual bytes. String literals like `true`, `false`, and `null` are matched byte-by-byte via `match_literal`. Escape sequences in strings are processed byte-by-byte rather than via regex or library calls.

### No Extern Dependencies

All functionality is implemented in pure XIOM. There are no `extern` C function declarations, no FFI, and no runtime library dependencies. This ensures the library works on any platform where the XIOM compiler runs.

### Object Key Order

Object entries are stored in a `Vec[JsonEntry]` which preserves insertion order. This matches the behavior of most modern JSON libraries (Python 3.7+, JavaScript ES2015+, etc.) while being simple to implement. The `sort_keys` option in pretty-printing allows alphabetical output when needed.

### Deep Merge Semantics

`json_merge` performs a recursive deep merge: scalar values are overwritten, arrays are replaced (not concatenated), and objects are recursively merged. This is the standard deep merge behavior used by tools like `lodash.merge` and Kubernetes strategic merge patch.

### Schema Validation Subset

The schema validator implements a pragmatic subset of JSON Schema. It supports the most commonly used keywords (`type`, `enum`, `properties`, `required`) which cover a large percentage of real-world validation needs. Full JSON Schema compliance would require `oneOf`, `anyOf`, `allOf`, `$ref`, `pattern`, `minLength`, `maxLength`, `minimum`, `maximum`, and other keywords -- all implementable in pure XIOM but left for future versions.

### Int-to-Float64 Conversion

Since XIOM may not support `as` type casting between `Int` and `Float64`, a manual conversion function `int_to_float64` decomposes the integer into decimal digits and builds the Float64 value through repeated multiplication and addition. The reverse operation `float64_to_int` uses repeated subtraction. Both are O(digits) and correct for values within the 32-bit integer range. Larger numbers lose precision naturally through Float64 representation.

---

## Port Notes (compiler 0.61.3, stdlib E:\xiom-lang\stdlib)

Ported with minimal, targeted fixes. The conformance suite is green:
`scripts/port.ps1 -Package xiom.json` -> `port: PASS (passed=12 failed=0
program_exit=0 exit=0)`. Publication status is unchanged (not published).

### Known limitations (port)

| Area | Change | Reason |
|------|--------|--------|
| Match exhaustiveness | `json_get_path` and `json_set_path` use bare variant patterns (`Key(k)`, `Index(i)`) instead of qualified `JsonPathSegment.Key(k)` patterns | Compiler 0.61.3 T001 reports both variants as uncovered for qualified enum patterns; bare patterns are accepted and match the rest of the file. Signals and control flow are unchanged. |
| Character mapping (`chr_byte`) | Now maps any byte through `xiom.convert.int_to_char` + `tostring.to_string_char` (new `use xiom.convert.tostring;`) | The previous body returned `" "` for every byte that is not a control character, quote, backslash or apostrophe, so parsed strings, JSONPath keys and serialized output were corrupted (e.g. the key `"key"` read back as three spaces). Behavior fix, not a semantics change: JSON text is now preserved as written. |
| Conformance harness | `main` calls each test explicitly (`let r1 = t1(); ...`) instead of iterating `Vec[fn() -> TestResult]` | On the pinned toolchain, element calls on function-typed `Vec` elements are miscompiled: `fs[0]()` lowers to `Unit` and the array-literal form crashes at runtime (`0xC0000005`). The green sibling suites use the same explicit-call pattern. All 12 tests and their assertions are unchanged. |
| Test t6 | `JsonType.Null` corrected to `JsonType.NullType` | Obsolete variant spelling: the enum has always declared `NullType`; the old spelling compiled to garbage codegen (clang rejected a `JsonValue` passed where `JsonType` was expected). The test's intent (parsed null reports `NullType`) is unchanged. |

No test semantics were weakened or removed; the 12 checks exercise the same
behaviors as before the port.

### Toolchain issues observed

- Non-exhaustive `match` is a hard error on this toolchain, but the
  exhaustiveness checker does not recognize qualified enum variant patterns
  (`Type.Variant(x)`) and reports every variant of the scrutinee type as
  uncovered (6 false T001s at the three `JsonPathSegment` matches).
- `Vec[fn() -> TestResult]` element calls are miscompiled (element call typed
  as `()`; array-literal dispatch crashes at runtime with `0xC0000005`).
  `xiom.test.run_all` in the stdlib has the same shape and is affected.
- A user free function named `log` collides with libm `log` at codegen
  (`call double @log(double %tmp)`) when the module uses `xiom.io`.
