# xiom.cfn -- Specification

Version: 0.1.0 (incubating, publication pending).
Module: `xiom.cfn` (`src/cfn.xi`). Pure XIOM, no FFI, no file I/O, no network,
no clock. Conformance suite: `tests/test_conformance.xi` (26 checks).

## 1. Scope

`xiom.cfn` is a deterministic model of the AWS CloudFormation templating and
stack-lifecycle layer:

- JSON-ish template scanning into a flat arena (`json_parse`, accessors,
  `json_render`, `json_equal`),
- template validation and section accessors (`cfn_template_parse`,
  `cfn_resource_*`, `cfn_parameter_*`, `cfn_condition_*`, `cfn_output_*`),
- intrinsic evaluation (`cfn_eval`, `cfn_eval_str`, `cfn_condition_eval`)
  over Ref, Fn::GetAtt, Fn::Join, Fn::Sub, Fn::Select, Fn::Split, Fn::If,
  Fn::Equals and Fn::FindInMap,
- parameter and output handling (`cfn_parameter_effective`,
  `cfn_validate_parameters`, `cfn_parameters_valid`, `cfn_output_value`,
  `cfn_output_description`, `cfn_output_export_name`),
- the stack lifecycle state machine (`stack_new`, `stack_apply`,
  `stack_state_name`, `stack_event_name`, predicates and history),
- resource-level change sets (`changeset_compute` and accessors).

Out of scope by design: AWS API calls, credentials, real deployments, YAML
templates, float/exponent numbers, surrogate pairs, rules functions,
Fn::And/Or/Not, Fn::ImportValue, Fn::Cidr, transforms, dynamic references,
drift detection, stack imports/exports resolution, quotas and pricing.

## 2. JSON subset

The scanner is hand-rolled and byte-oriented. Accepted grammar:

```
document = ws value ws
value    = object / array / string / number / "true" / "false" / "null"
object   = "{" ws ( member *( ws "," ws member ) )? ws "}"
member   = string ws ":" ws value
array    = "[" ws ( value *( ws "," ws value ) )? ws "]"
string   = '"' *( char / escape ) '"'
escape   = '\"' / '\\' / '\/' / '\b' / '\f' / '\n' / '\r' / '\t' / '\uXXXX'
number   = [ "-" ] ( "0" / [1-9] digit* )
ws       = SP / TAB / LF / CR
```

Decisions, each covered by the conformance suite:

1. **Numbers are integers only.** Fractions, exponents and leading zeros are
   rejected (`1.5`/`1e3` -> "only integers are supported"; `01` -> invalid).
   The magnitude is bounded by the signed 64-bit maximum; the minimum
   `-9223372036854775808` is rejected as out of range (its magnitude is not
   representable as a positive `Int`; same choice as `xiom.config`).
2. **Strings.** Standard escapes decode (including `\/`); `\uXXXX` decodes a
   BMP code point through `xiom.convert.int_to_char`. `\u0000` (NUL) and the
   surrogate range `U+D800..U+DFFF` are rejected. Raw bytes >= 0x20 are
   passed through verbatim, so UTF-8 survives byte-exactly. Raw control
   bytes (< 0x20) inside a string are rejected.
3. **NUL input** is rejected up front so no value can carry a NUL sentinel.
4. **No comments, no trailing commas, no duplicate keys.** Duplicate keys are
   not detected; the first matching member wins on lookup and rendering
   keeps every member.
5. **Whitespace** is SP, TAB, LF, CR.
6. **Depth.** Recursion beyond `CFN_MAX_DEPTH` (64) fails with
   "cfn: JSON nesting too deep". The parser and the evaluator share the cap.
7. **Root.** Any value may be the document root; templates require an object.

### Data model

```xi
pub type JsonDoc = {
  kinds: Vec[Int];    // JSON_* per node
  ints: Vec[Int];     // bool 0/1, integer value, or kids start for compounds
  counts: Vec[Int];   // array element count, or 2*member count for objects
  texts: Vec[Str];    // string payload ("" otherwise)
  kids: Vec[Int];     // flat child node ids
  root: Int;          // root node id (0 after a parse)
}
```

An object's children are `key0, value0, key1, value1, ...`; keys are string
nodes. Accessors are bounds-checked and return `CFN_NONE` (-1) / `""` / `0` /
`false` for invalid nodes, so no accessor panics.

`json_render` produces compact canonical JSON (document key order; the same
escape set as parsing; non-ASCII UTF-8 bytes pass through). `json_equal` is
structural: key order is irrelevant; arrays are equal length and
element-wise equal.

## 3. Template subset

`cfn_template_parse(text)` = `json_parse` + structural validation:

| Rule | Error |
|---|---|
| root must be an object | `cfn: template root must be an object` |
| `Resources` present | `cfn: template is missing the Resources section` |
| `Resources` is an object | `cfn: Resources must be an object` |
| every member of `Resources` is an object | `cfn: resource <id> must be an object` |
| every resource has a `Type` member | `cfn: resource <id> is missing Type` |
| every `Type` is a string | `cfn: resource <id> Type must be a string` |

Recognized sections (none required except Resources; none validated beyond
the rules above):

- `AWSTemplateFormatVersion`, `Description` -- informational strings.
- `Parameters` -- object of `{ "Type", "Default", ... }`.
- `Mappings` -- `map -> top key -> second key -> literal scalar or array`.
- `Conditions` -- `{"Fn::Equals": [a, b]}` or `{"Condition": "Other"}`.
- `Resources` -- `{ "Type": string, "Properties": any JSON }`.
- `Outputs` -- `{ "Value": expression, "Description": string?, "Export": { "Name": expression }? }`.

Parameter type names: `String`, `Number`, `CommaDelimitedList`. A missing or
empty `Type` reads as `String`. `Default` is literal (string, integer,
boolean, or an array of those; an array default is comma-joined when read as
a value). `AllowedValues`, `MinLength`/`MaxLength`, `NoEcho` and constraint
messages are outside this subset.

## 4. Resolved values and context

```xi
pub type CfnValue = { kind: Int; text: Str; items: Vec[Str]; }  // CFN_SCALAR | CFN_LIST
```

`cfn_eval(doc, node, ctx)` maps a JSON node to a `CfnValue`:

| JSON node | Result |
|---|---|
| string | scalar, text verbatim |
| integer | scalar, decimal text |
| true / false | scalar `"true"` / `"false"` |
| array | list; every element must resolve to a scalar |
| object with one member | intrinsic dispatch (below) |
| object with != 1 member | `cfn: object is not a valid intrinsic` |
| null | `cfn: null is not a resolvable value` |

`cfn_eval_str` additionally rejects lists with
`cfn: value must resolve to a scalar`.

```xi
pub type CfnContext = {
  param_names: Vec[Str]; param_values: Vec[Str];          // overrides
  resource_refs: Vec[Str]; resource_ref_values: Vec[Str]; // simulated physical ids
  attr_keys: Vec[Str]; attr_values: Vec[Str];             // "Logical.Attr" overrides
  notification_arns: Vec[Str];
  region: Str; account_id: Str; stack_name: Str; partition: Str; url_suffix: Str;
}
```

Build with `cfn_context_new(region, account, stack)` (partition `aws`, URL
suffix `amazonaws.com`) or `cfn_context_default()`
(`us-east-1` / `123456789012` / `demo-stack`), then the copy-and-set helpers.

## 5. Intrinsic semantics

| Intrinsic | Input | Semantics | Errors |
|---|---|---|---|
| `Ref` | string name | pseudo-parameter (`AWS::Region`, `AWS::AccountId`, `AWS::StackName`, `AWS::Partition`, `AWS::URLSuffix`, `AWS::NotificationARNs` (comma-joined), `AWS::NoValue` -> `""`), else parameter (override > default, array defaults comma-joined), else resource (context override, else the logical id) | `cfn: Ref expects a string`; `cfn: parameter has no value: X`; `cfn: unresolved Ref: X`; `cfn: cyclic reference: X` |
| `Fn::GetAtt` | `[logical, attr]` or `"logical.attr"` | resource must exist; context attribute override wins, else the deterministic `"<logical>.<attr>"` | malformed form; `cfn: unknown resource in Fn::GetAtt: X`; `cfn: Fn::GetAtt attribute must not be empty` |
| `Fn::Join` | `[delimiter, list]` | delimiter must be scalar; list may be a literal array or any expression resolving to a list; elements are scalars | `fn::Join`-shaped messages as catalogued |
| `Fn::Sub` | `"template"` or `[template, vars]` | scans `${...}`: `${Name}` -> Ref, `${Name.Attr}` -> GetAtt, `${Var}` -> vars entry (evaluated), `${!X}` -> literal `${X}`; substitution results are **not** re-expanded | missing `}`; empty placeholder; bad vars; ref errors |
| `Fn::Select` | `[index, list]` | index must resolve to an integer scalar (decimal text, optional `-`); list must resolve to a list; bounds checked | index not integer; out of range; not a list |
| `Fn::Split` | `[delimiter, string]` | delimiter must be non-empty; uses `xiom.string.str_split` semantics (empty parts preserved: `""` -> `[""]`, `"a,b,"` -> `["a","b",""]`) | empty delimiter; non-scalar operands |
| `Fn::If` | `[condition-name, true, false]` | condition name is a string literal naming a template condition; the chosen branch is evaluated (may be a list) | unknown condition; bad condition expressions; cycle/depth |
| `Fn::Equals` | `[a, b]` | both sides scalar; byte-exact comparison -> `"true"`/`"false"` | non-scalar operands |
| `Fn::FindInMap` | `[map, top, second]` | keys may be intrinsics; the value is literal (scalar, or an array of scalars returned as a list) | `cfn: mapping not found: M`; `cfn: mapping key not found: M/T/S`; non-literal value |

Condition expressions are `{"Fn::Equals": [a, b]}` or `{"Condition": "Other"}`.
The evaluator carries an active-name trail: a condition chain that reaches
itself fails with `cfn: cyclic reference: <name>`; nesting beyond
`CFN_MAX_DEPTH` fails with `cfn: intrinsic resolution depth exceeded`.

## 6. Parameters and outputs

`cfn_validate_parameters(doc, ctx)` returns ALL errors in this order:

1. every context override that names no declared parameter:
   `cfn: unknown parameter: X`;
2. per parameter in document order: without override and without default:
   `cfn: missing required parameter: X`; a `Number` whose effective value is
   not an integer: `cfn: parameter X must be an integer: V`.

`cfn_parameter_effective(doc, name, ctx)`: override, else default, else
`cfn: parameter has no value: X`. Array defaults are comma-joined.

Outputs: `cfn_output_value` resolves `Value` and requires a scalar
(`cfn: unknown output: X`, `cfn: output has no Value: X`,
`cfn: output value must resolve to a scalar: X`); `cfn_output_description`
returns `Option[Str]`; `cfn_output_export_name` resolves `Export.Name`
(`cfn: output has no export: X`).

## 7. Stack lifecycle

States: `STACK_NOT_CREATED` (0, model-only initial state),
`CREATE_IN_PROGRESS`, `CREATE_COMPLETE`, `CREATE_FAILED`,
`ROLLBACK_IN_PROGRESS`, `ROLLBACK_COMPLETE`, `ROLLBACK_FAILED`,
`UPDATE_IN_PROGRESS`, `UPDATE_COMPLETE`,
`UPDATE_ROLLBACK_IN_PROGRESS`, `UPDATE_ROLLBACK_COMPLETE`,
`UPDATE_ROLLBACK_FAILED`, `DELETE_IN_PROGRESS`, `DELETE_COMPLETE`,
`DELETE_FAILED`, `REVIEW_IN_PROGRESS`.

Events: `CREATE_BEGIN`, `UPDATE_BEGIN`, `DELETE_BEGIN`, `SUCCEED`, `FAIL`,
`REVIEW_BEGIN`.

| From | Event | To |
|---|---|---|
| NOT_CREATED | REVIEW_BEGIN | REVIEW_IN_PROGRESS |
| NOT_CREATED | CREATE_BEGIN | CREATE_IN_PROGRESS |
| REVIEW_IN_PROGRESS | CREATE_BEGIN | CREATE_IN_PROGRESS |
| REVIEW_IN_PROGRESS | UPDATE_BEGIN | UPDATE_IN_PROGRESS |
| CREATE_IN_PROGRESS | SUCCEED | CREATE_COMPLETE |
| CREATE_IN_PROGRESS | FAIL | ROLLBACK_IN_PROGRESS |
| ROLLBACK_IN_PROGRESS | SUCCEED | ROLLBACK_COMPLETE |
| ROLLBACK_IN_PROGRESS | FAIL | ROLLBACK_FAILED |
| CREATE_COMPLETE | UPDATE_BEGIN | UPDATE_IN_PROGRESS |
| CREATE_COMPLETE | DELETE_BEGIN | DELETE_IN_PROGRESS |
| UPDATE_IN_PROGRESS | SUCCEED | UPDATE_COMPLETE |
| UPDATE_IN_PROGRESS | FAIL | UPDATE_ROLLBACK_IN_PROGRESS |
| UPDATE_ROLLBACK_IN_PROGRESS | SUCCEED | UPDATE_ROLLBACK_COMPLETE |
| UPDATE_ROLLBACK_IN_PROGRESS | FAIL | UPDATE_ROLLBACK_FAILED |
| UPDATE_COMPLETE | UPDATE_BEGIN | UPDATE_IN_PROGRESS |
| UPDATE_COMPLETE | DELETE_BEGIN | DELETE_IN_PROGRESS |
| ROLLBACK_COMPLETE | DELETE_BEGIN | DELETE_IN_PROGRESS |
| UPDATE_ROLLBACK_COMPLETE | UPDATE_BEGIN | UPDATE_IN_PROGRESS |
| UPDATE_ROLLBACK_COMPLETE | DELETE_BEGIN | DELETE_IN_PROGRESS |
| ROLLBACK_FAILED | DELETE_BEGIN | DELETE_IN_PROGRESS |
| UPDATE_ROLLBACK_FAILED | DELETE_BEGIN | DELETE_IN_PROGRESS |
| CREATE_FAILED | DELETE_BEGIN | DELETE_IN_PROGRESS |
| DELETE_IN_PROGRESS | SUCCEED | DELETE_COMPLETE |
| DELETE_IN_PROGRESS | FAIL | DELETE_FAILED |
| DELETE_FAILED | DELETE_BEGIN | DELETE_IN_PROGRESS |

Any other (state, event) pair fails with
`cfn: stack cannot apply <EVENT> in state <STATE>` and leaves the stack
unchanged. `stack_apply` returns a copy with the event and resulting state
appended to the parallel history vectors; `stack_new` starts at
NOT_CREATED with an empty history. DELETE_COMPLETE is terminal.

## 8. Change sets

`changeset_compute(old, new)` walks `Resources`:

1. every resource of `old`, in old document order:
   - absent in `new` -> `CHANGE_REMOVE`;
   - `Type` differs -> `CHANGE_MODIFY` with replacement = 1;
   - `Properties` structurally equal (key order irrelevant, absent equals
     absent) -> `CHANGE_NONE`;
   - otherwise -> `CHANGE_MODIFY` with replacement = 0;
2. every resource only in `new`, in new document order -> `CHANGE_ADD`.

Rows are parallel `logical_ids` / `kinds` / `replacements` / `old_types` /
`new_types`. `changeset_has_changes` is true when any row is not
`CHANGE_NONE`. Templates without a `Resources` section diff as empty.

## 9. Error catalog

Scanner (all prefixed `cfn: `): `NUL byte in input`, `unexpected end of
input`, `unexpected character in JSON`, `control character in JSON string`,
`unterminated string`, `invalid escape sequence in string`, `invalid unicode
escape`, `unsupported unicode escape (NUL)`, `unsupported unicode escape
(surrogate)`, `invalid number`, `invalid number (only integers are
supported)`, `number out of range`, `invalid literal`, `unterminated
object`, `unterminated array`, `object key must be a string`, `expected ':'
in object`, `trailing comma in object`, `trailing comma in array`,
`expected ',' or '}' in object`, `expected ',' or ']' in array`, `JSON
nesting too deep`, `trailing data after JSON value`.

Template: the six structural messages in section 3.

Evaluation: every message listed in the semantics table plus `invalid JSON
node`, `null is not a resolvable value`, `object is not a valid intrinsic`,
`unknown intrinsic: <key>`, `value must resolve to a scalar`, `malformed
Fn::Sub: missing '}'`, `malformed Fn::Sub: empty placeholder`, `malformed
Fn::Sub placeholder: <inner>`, `condition <name> must be Fn::Equals or
Condition`, `Condition name must be a string`, `mapping value must be a
scalar or list: <path>`.

Parameters/outputs/stacks: as in sections 6 and 7.

All messages are stable strings and are asserted exactly by the suite.

## 10. Test plan

| Check | Covers |
|---|---|
| t01-t02 | JSON scalars, kinds, arrays, objects, accessors, sentinels |
| t03 | string escapes, BMP `\uXXXX`, raw UTF-8 byte round-trip |
| t04 | scanner error catalog (19 exact messages) |
| t05 | nesting depth cap |
| t06 | canonical render and parse/render/parse round-trip |
| t07 | template validation errors |
| t08 | section accessors, parameter defaults |
| t09-t10 | Ref: parameters, pseudo-parameters, resources, overrides |
| t11 | Fn::GetAtt forms and override |
| t12 | Fn::Join nested/empty/error cases |
| t13 | Fn::Sub refs, attrs, escapes, vars, errors |
| t14 | Fn::Split / Fn::Select semantics and errors |
| t15 | Fn::If / Fn::Equals, unknown condition, cycle rejection |
| t16 | condition chain depth cap |
| t17 | Fn::FindInMap scalar/list/intrinsic-key/errors |
| t18 | parameter validation and effective values |
| t19 | outputs, descriptions, exports |
| t20-t22 | stack create/rollback, update/update-rollback/delete, review, forbidden transitions |
| t23-t24 | change-set classification, replacements, key-order insensitivity |
| t25 | end-to-end template + determinism |
| t26 | unicode canonicalization and full round-trip |
