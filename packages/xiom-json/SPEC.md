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
}
```

### `JsonEntry`

A key-value pair used within JSON objects. Maintains insertion order.

```
pub type JsonEntry = {
  key: Str;
  value: JsonValue;
}
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
}
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

### Clone surface

`derive[Clone]` is kept only on scalar-only types whose fields are `Str`,
`Int` or `Bool` (no containers): `ParseError`, `JsonNumber`,
`JsonPathSegment`, `JsonPrettyConfig`. The container-backed public types
(`JsonValue`, `JsonEntry`, `JsonPath`) do **not** implement `Clone`:
derived deep clones of Object/Array payloads are miscompiled on pin
v0.62.2 (corrupt vector handle, crash on the next `push`). Use
`json_clone` for deep copies of `JsonValue` trees; rebuild paths with the
JSONPath constructors/parser.

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

### `json_clone`

```xi
pub fn json_clone(value: &JsonValue) -> JsonValue
```

Deep-copies a `JsonValue` tree. This is the supported deep-copy API:
`JsonValue`/`JsonEntry` do not implement `Clone` on this pin because the
derived deep clone of Object/Array payloads is miscompiled.

**Example**:
```xi
var copy = json_clone(&value);
```

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

## Known Limitations (current)

| Area | Limitation | Status |
|------|-----------|--------|
| Unicode escape decoding | `\uXXXX` is consumed and preserved as a placeholder (four hex chars skipped); real code-point decoding needs unicode tables | documented subset |
| Float64 string formatting | Fractions format to <=15 digits; values with magnitude >= 1e15 serialize as `"0"` (saturation guard); exponent magnitude saturates at 1000 | documented limitation; large-magnitude round-trip is **unasserted** |
| Float64 parse precision | Numbers are parsed via manual arithmetic with an `Int` digit accumulator; very long digit runs overflow/lose precision | documented; tests stay in the exact range |
| Nesting depth | No explicit cap: parser and serializer are recursive and bounded by the process stack; 64-deep arrays and 32-deep objects are conformance-tested | tested at fixed depths; no cap semantics asserted |
| Deep clone | Container-backed types (`JsonValue`, `JsonEntry`, `JsonPath`) do not implement `Clone`: derived deep clone of Object/Array payloads is miscompiled on pin v0.62.2 (corrupt vector handle); `json_clone` is the supported deep copy | derive removed; `json_clone` public; compiler finding |
| Exact number representation | `JsonNumber` is defined but unused; `json_parse` produces `JsonValue.Number(Float64)`; no `parse_exact` variant | documented subset |
| JSON Schema | Supported keywords are exactly `type`, `enum`, `properties`, `required` | documented subset |
| Large arrays/objects | Mutation helpers rebuild the container (O(n) per operation); no in-place edit API | documented behavior |

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

Numeric conversion uses the `xiom.convert` intrinsics (`int_to_float`, `float_to_int`, `int_to_string`) rather than hand-rolled digit loops. Accuracy is bounded by the Float64 representation and by the `Int` accumulator used while scanning digits.

---

## Port Notes (compiler 0.61.3, stdlib E:\xiom-lang\stdlib)

Ported with minimal, targeted fixes. The conformance suite (44 checks) is green:

```
.\scripts\port.ps1 -Package xiom-json -TimeoutSec 60
-> port: PASS (passed=44 failed=0 program_exit=0 exit=0)   (x2 consecutive runs)
```

Publication status is unchanged (not published).

### Known limitations (port)

| Area | Change | Reason |
|------|--------|--------|
| Match exhaustiveness | `json_get_path` and `json_set_path` use bare variant patterns (`Key(k)`, `Index(i)`) instead of qualified `JsonPathSegment.Key(k)` patterns | Compiler 0.61.3 T001 reports both variants as uncovered for qualified enum patterns; bare patterns are accepted and match the rest of the file. Signals and control flow are unchanged. |
| Character mapping (`chr_byte`) | Now maps any byte through `xiom.convert.int_to_char` + `tostring.to_string_char` (new `use xiom.convert.tostring;`) | The previous body returned `" "` for every byte that is not a control character, quote, backslash or apostrophe, so parsed strings, JSONPath keys and serialized output were corrupted (e.g. the key `"key"` read back as three spaces). Behavior fix, not a semantics change: JSON text is now preserved as written. |
| Conformance harness | `main` calls each test explicitly (`let r1 = t1(); ...`) instead of iterating `Vec[fn() -> TestResult]` | On the pinned toolchain, element calls on function-typed `Vec` elements are miscompiled: `fs[0]()` lowers to `Unit` and the array-literal form crashes at runtime (`0xC0000005`). The green sibling suites use the same explicit-call pattern. The original 12 tests and their assertions are unchanged. |
| Test t6 | `JsonType.Null` corrected to `JsonType.NullType` | Obsolete variant spelling: the enum has always declared `NullType`; the old spelling compiled to garbage codegen (clang rejected a `JsonValue` passed where `JsonType` was expected). The test's intent (parsed null reports `NullType`) is unchanged. |

No existing check's intent was weakened or removed: t1-t12 are unchanged.
32 checks were added during stable preparation (error paths, numeric edge
cases, deep nesting, duplicate keys, mutation API, deep-clone independence,
determinism); see the "Stable Preparation" section below.

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
- `invariant:` is rejected by the v0.62.2 parser in every documented
  placement (`pub type X = T invariant: ...;`, after `}`, on its own line):
  `error[P001] expected ';', found invariant`. No type invariant in this
  package can be expressed on the pin.
- Mutation through a match-bound payload of a `&mut` enum parameter is
  silently dropped: `match v { A(items) => { items.push(x); } }` leaves the
  caller unchanged (no diagnostic). Writing the rebuilt value back
  (`*v = A(items)`) is required.
- Derived deep clone is miscompiled: `Vec[JsonEntry].clone()` (and any
  `JsonValue.clone()` whose payload is Object/Array) returns a corrupt
  handle; a subsequent `push` crashes with `0xC000001D` (stack overflow).
  Scalar payload clones (`Str`, `Bool`, `Number`) are fine. The public
  derives were removed from the container-backed types (`JsonValue`,
  `JsonEntry`, `JsonPath`); scalar-only types keep `Clone`.
- `xiom-verify` expects the file before `--check`
  (`xiom-verify <file> --check`); the documented order fails with
  `Error reading --check`. It also does not resolve a package's own imports
  from a test file (`CheckError: undefined variable 'json_parse'`), so
  contracts are verified on the declaring `src/json.xi`.
- `xiom-verify` contract expressions are limited: `Result`/enum patterns and
  enum constructors (`result is Ok => ...`) report
  `unsupported expression in contract`; struct-field reads report
  `field access on non-datatype receiver`; any call in a clause
  (`xiom.string.str_len`, `result.len()`) is skipped as a complex call target.
- Duplicate private function definitions pass type-checking but standalone
  `--emit-ir` reports `unresolved function symbol(s)` (C001); the duplicate
  `stringify_object_item` was removed.

## Stable Preparation (2026-10-03)

Promotion pre-work for the `stable` gate (docs/PROMOTION.md): contracts on
the public entry points, a 44-check deterministic conformance suite, and a
Z3 verification pass. Stage and `STATUS.json` are untouched (the coordinator
handles promotion).

### Contract inventory

15 clauses on 13 public entry points: 13 `requires:` and 2 `ensures:`.

| Entry point | Clause | Kind | Verification |
|---|---|---|---|
| `json_parse` | `input.len() > 0` | requires | runtime; solver-unknown (complex call target) |
| `json_validate` | `input.len() > 0` | requires | runtime; solver-unknown (complex call target) |
| `json_stringify` | `result.len() > 0` | ensures | runtime; solver-unknown (complex call target) |
| `json_stringify_pretty` | `config.indent >= 0` | requires | runtime; solver-unknown (field access on non-datatype receiver) |
| `json_stringify_pretty` | `result.len() > 0` | ensures | runtime; solver-unknown (complex call target) |
| `json_get` | `key.len() > 0` | requires | runtime; solver-unknown (complex call target) |
| `json_get_path` | `path.segments.len() > 0` | requires | runtime; solver-unknown (complex call target) |
| `json_set` | `key.len() > 0` | requires | runtime; solver-unknown (complex call target) |
| `json_set_path` | `path.segments.len() > 0` | requires | runtime; solver-unknown (complex call target) |
| `json_remove` | `key.len() > 0` | requires | runtime; solver-unknown (complex call target) |
| `json_has_key` | `key.len() > 0` | requires | runtime; solver-unknown (complex call target) |
| `json_object_put` | `key.len() > 0` | requires | runtime; solver-unknown (complex call target) |
| `json_path_push_key` | `key.len() > 0` | requires | runtime; solver-unknown (complex call target) |
| `json_path_push_index` | `index >= 0` | requires | runtime; solver-unknown (loop/body modeling) |
| `json_path_parse` | `path_str.len() > 0` | requires | runtime; solver-unknown (complex call target) |

No clause was reported violated. All clauses are runtime-checked in the
conformance suite (which stays green, 44/44, with contracts enabled).

### Solver-unproven and unasserted

- **Solver-unproven:** every package clause above. The solver skips
  `.len()` clauses as complex call targets and the config-field clause as a
  non-datatype field access; it also cannot model the recursive tree bodies.
  They remain annotated for runtime checking and review.
- **Unasserted** (property not expressible safely on the pin, reason in
  parentheses):
  - round-trip `json_parse(json_stringify(v)) == v` (contract expressions
    cannot call `json_parse`/`json_stringify`; no structural equality in the
    contract language);
  - `Ok` implies exactly one complete root value, and `Err` on malformed
    input (Result/enum patterns in contracts are unsupported by
    `xiom-verify`);
  - `json_clone` result deeply equals input (no structural equality);
  - `JsonPrettyConfig` invariant `this.indent >= 0` (parser rejects
    `invariant:` on v0.62.2); enforced as the `requires` clause on
    `json_stringify_pretty` instead;
  - `JsonPath` non-empty invariant (violated by the legitimate
    `json_path_new()` empty path; the traversals carry the `requires`
    guard instead);
  - mutation helpers' "true iff the value changed" (would need private
    helpers in the contract).

### Z3 verification (xiom-verify v0.62.2)

```
$env:Z3_PATH = "$env:LOCALAPPDATA\xiom.new\bin\z3.exe"
& "$env:LOCALAPPDATA\xiom.new\bin\xiom-verify.exe" src\json.xi --check
-> Results: 0 proven, 0 violated, 21 unknown, 16 errors

& "$env:LOCALAPPDATA\xiom.new\bin\xiom-verify.exe" tests\test_conformance.xi --check
-> CheckError: undefined variable 'json_parse' (verifier does not resolve
   the package's own imports; verification is done on src\json.xi)
```

The 16 errors are SMT-generation limitations on the recursive bodies
(`unknown constant ...`, `Invalid constant declaration: unknown sort
'xiom_unknown'`), not contract violations. No clause is solver-proven on
this pin; pure-arithmetic probes (`divide`, `grow`) are proven by the same
verifier, so the toolchain can discharge arithmetic only.

### Behavior fixes made during preparation

| Area | Change | Reason |
|------|--------|--------|
| Fraction stringify | `stringify_frac` increments the digit position and formats digits with `int_to_string` | it previously recursed forever at the decimal point (`json_stringify(json_parse("0.5"))` crashed) and emitted control characters for digit glyphs |
| Fraction parse | divisor derived from the actual fraction digit count | `json_parse("0.05")` produced `0.5` (leading zero lost) |
| Exponent bound | exponent magnitude capped at 1000 before the multiply loop | `1e999999999` looped ~1e9 times (hang) |
| Mutation API | `json_set`/`json_set_path`/`json_remove`/`json_merge`/`json_array_push`/`json_object_put` rebuild the value and write it through `*obj = ...` | match-bound payload mutations on `&mut` enums are silently dropped on the pin; all six functions were silent no-ops or corrupted callers |
| Deep clone | `derive[Clone]` removed from `JsonValue`/`JsonEntry`/`JsonPath`; new public `json_clone`; internal code uses it | derived Object/Array clone returns a corrupt vector handle and crashes on push; public `Clone` removed so callers cannot hit it |
| `json_set_path` | recursive atomic rebuild; missing intermediate keys create empty objects; no partial writes on failure | the old loop reassigned `&mut` references and created `null` intermediates, contradicting the documented "creates intermediate objects" |
| `json_merge` | atomic rebuild (failure leaves the base unchanged) | the old deep merge could mutate earlier keys before failing on a later one |

### Error catalog

`ParseError.message` values (parser):

- `unexpected end of input`, `unexpected character`
- `unterminated string`, `unexpected end of input in string escape`,
  `invalid escape character`, `unescaped control character in string`,
  `unexpected end of input in unicode escape`
- `expected digit in number`, `expected digit after decimal point`,
  `expected digit in exponent`, `empty number`, `incomplete negative number`
- `expected key string`, `expected ':'`, `expected '}'`, `expected ']'`
- `expected 'true' or 'false'`, `expected 'null'`
- `trailing data after root value`

JSONPath (`Result[JsonPath, Str]` errors):

- `unexpected character in path`, `unterminated bracket segment`,
  `unterminated bracket key`, `expected ']'`, `expected ']' or digit`

Schema (`Result[Bool, Str]` errors):

- `type mismatch`, `value not in enum`, `schema enum must be array`,
  `properties constraint requires object value`, `schema properties must be object`,
  `required constraint requires object value`, `schema required must be array`,
  `missing required key`, `property '<key>': <nested error>`

### Documented subset and semantics

- Duplicate keys: preserved in insertion order; `json_get` returns the
  first matching value (tested).
- Empty input and empty keys are `requires` violations (runtime trap in
  debug), not `Err` results.
- Numeric canonical form on output: `-0` -> `0`, `2.50` -> `2.5`,
  `1E2` -> `100`, `-1.5e3` -> `-1500` (tested). Fractions are formatted
  from Float64; magnitudes >= 1e15 serialize as `0` (see limitations).
- Whitespace is accepted anywhere JSON allows it; output is canonical
  compact (tested).
- No explicit nesting cap; 64-deep arrays and 32-deep objects round-trip
  (tested).

## Promotion notes (2026-10-03, v0.62.3)

Promoted `ported` -> `stable` per `docs/PROMOTION.md`.

- **G1**: `port.ps1 -TimeoutSec 60` x2 on the pinned v0.62.3 -- 44/44 both runs.
- **G2**: this SPEC is current; the README `Status` block is synced after the
  `eco-v0.1.37` publish.
- **G3**: API review -- public entry points are free functions over typed
  enums/structs (`JsonValue`, `JsonPath`, `ParseError`, `JsonNumber`); no
  child->parent imports; no builtin/generic-name shadowing.
- **G4**: contracts -- 13 `requires:` + 2 `ensures:` clauses on public entry
  points; `xiom-verify` (Z3) attempted over the ported candidates (0 of the 101
  clauses proven tooling-side; solver `unknown` on record-heavy clauses, see
  COMPILER-FINDINGS) -- contract verification remains review-only.
- **G5**: 44 conformance checks (>= 24) with explicit error paths.
- **G6**: workarounds -- contract-verification review-only (accepted);
  enum-payload mutation and `derive[Clone]` avoidance (accepted; revisit at the
  next package touch); indexed `Vec[fn]` harness workaround (accepted, see the
  harness note above).
- **G7**: dependents re-checked -- `graphql` and `rest` declare `xiom.json` but
  are unpublished; no published dependents.
