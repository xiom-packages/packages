# xiom.cfn

> **Status:** `incubating` -- conformance-tested (26/26) on compiler v0.62.2;
> publication pending. Pure XIOM, no AWS calls, no network, no FFI.
> **Scope:** AWS CloudFormation templating and stack lifecycle MODEL:
> JSON-ish template parsing, resource model and references, intrinsic
> evaluation (Ref / Fn::GetAtt / Fn::Join / Fn::Sub / Fn::Select /
> Fn::Split / Fn::If / Fn::Equals / Fn::FindInMap), parameter and output
> handling, the stack state machine (CREATE / UPDATE / DELETE + rollback)
> and change-set resource diffing.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.str_split`,
> `xiom.string.compare.str_compare`, `xiom.convert.int_to_string`,
> `xiom.convert.int_to_char`, `xiom.convert.tostring.to_string_char`).
> Tests additionally use `xiom.test` and `xiom.io`.

## What it is

`xiom.cfn` is a deterministic, pure-XIOM model of the CloudFormation
templating layer. It parses a strict JSON subset into a flat arena, exposes
template sections, evaluates the common intrinsic-function subset against an
explicit evaluation context, validates parameters, resolves outputs, drives a
stack through its documented lifecycle states, and classifies resource-level
changes between two templates.

Every operation is a total function over plain values: the model never talks
to AWS, never reads the clock or the environment, and never performs I/O.
That makes it usable for template linting, offline plan review, teaching and
tests. `SPEC.md` is the normative document: template subset, intrinsic
semantics table and the complete error catalog.

## Template subset (short version)

```json
{
  "AWSTemplateFormatVersion": "2010-09-09",
  "Parameters": { "Env": { "Type": "String", "Default": "prod" } },
  "Mappings": { "RegionMap": { "us-east-1": { "ami": "ami-123" } } },
  "Conditions": { "IsProd": { "Fn::Equals": [ { "Ref": "Env" }, "prod" ] } },
  "Resources": { "Bucket": { "Type": "AWS::S3::Bucket", "Properties": {} } },
  "Outputs": { "BucketName": { "Value": { "Ref": "Bucket" } } }
}
```

The scanner accepts objects, arrays, strings (with `\" \\ \/ \b \f \n \r \t`
and BMP `\uXXXX`; NUL and surrogates rejected), **integer** numbers (no
fractions, no exponents, no leading zeros), `true` / `false` and `null`.
No comments, no trailing commas. Nesting is capped at 64 levels. Anything
outside the subset is rejected with a stable `cfn: ...` error.

## API

### JSON arena

| Function | Returns | Description |
|---|---|---|
| `json_parse(text)` | `Result[JsonDoc, Str]` | Parse the documented JSON subset. |
| `json_root(doc)` | `Int` | Root node id. |
| `json_kind(doc, node)` | `Int` | `JSON_NULL/BOOL/INT/STR/ARR/OBJ`, or `CFN_NONE`. |
| `json_text(doc, node)` | `Str` | String payload. |
| `json_int(doc, node)` | `Int` | Integer payload. |
| `json_bool(doc, node)` | `Bool` | Boolean payload. |
| `json_count(doc, node)` | `Int` | Child entries (array elements / 2*members). |
| `json_array_len(doc, node)` | `Int` | Array length. |
| `json_array_get(doc, node, i)` | `Int` | Element node id, or `-1`. |
| `json_member_count(doc, node)` | `Int` | Object member count. |
| `json_member_key(doc, node, i)` | `Str` | Member key. |
| `json_member_value(doc, node, i)` | `Int` | Member value node id. |
| `json_object_get(doc, node, key)` | `Int` | Value node id, or `-1`. |
| `json_render(doc, node)` | `Str` | Compact canonical JSON. |
| `json_equal(a, na, b, nb)` | `Bool` | Structural equality (key order irrelevant). |

### Template

| Function | Returns | Description |
|---|---|---|
| `cfn_template_parse(text)` | `Result[JsonDoc, Str]` | Parse + validate root/Resources/Type. |
| `cfn_resource_count(doc)` / `cfn_resource_id(doc, i)` | `Int` / `Str` | Resource enumeration. |
| `cfn_resource_type(doc, id)` / `cfn_resource_properties(doc, id)` | `Str` / `Int` | Resource lookup. |
| `cfn_parameter_count/name/type/default` | `Int` / `Str` / `Option[Str]` | Parameter metadata. |
| `cfn_condition_count/name`, `cfn_output_count/name` | `Int` / `Str` | Section enumeration. |

### Evaluation

| Function | Returns | Description |
|---|---|---|
| `cfn_context_new(region, account, stack)` | `CfnContext` | Pseudo-parameter context. |
| `cfn_context_default()` | `CfnContext` | us-east-1 / 123456789012 / demo-stack. |
| `cfn_context_set_parameter/..._resource_ref/..._attribute/..._add_notification_arn` | `CfnContext` | Copy-and-set builders. |
| `cfn_eval(doc, node, ctx)` | `Result[CfnValue, Str]` | Evaluate an intrinsic. |
| `cfn_eval_str(doc, node, ctx)` | `Result[Str, Str]` | Scalar-only evaluation. |
| `cfn_condition_eval(doc, name, ctx)` | `Result[Bool, Str]` | Named condition. |
| `cfn_parameter_effective(doc, name, ctx)` | `Result[Str, Str]` | Override > default > error. |
| `cfn_validate_parameters(doc, ctx)` / `cfn_parameters_valid` | `Vec[Str]` / `Bool` | Static parameter validation. |
| `cfn_output_value/description/export_name` | `Result[Str, Str]` / `Option[Str]` | Output handling. |

### Stack lifecycle and change sets

| Function | Returns | Description |
|---|---|---|
| `stack_new(name)` | `Stack` | NOT_CREATED stack with empty history. |
| `stack_apply(s, event)` | `Result[Stack, Str]` | Apply one lifecycle event. |
| `stack_state_name` / `stack_event_name` | `Str` | Stable display names. |
| `stack_is_busy` / `stack_is_failed` | `Bool` | State predicates. |
| `stack_history_len/event/state` | `Int` | Transition trace. |
| `changeset_compute(old, new)` | `ChangeSet` | Resource diff classification. |
| `changeset_len/logical/kind/kind_name/count/is_replacement/old_type/new_type/has_changes` | mixed | Change-set accessors. |

## Usage

```xi
use xiom.cfn;
use xiom.io;

fn main() -> Int {
  let r = cfn_template_parse("{\"Parameters\":{\"Env\":{\"Type\":\"String\",\"Default\":\"prod\"}},\"Resources\":{},\"Outputs\":{\"O\":{\"Value\":{\"Fn::Sub\":\"env=${Env}\"}}}}");
  match r {
    Ok(doc) => {
      let ctx = cfn_context_default();
      io.println(cfn_parameters_valid(&doc, &ctx));          // true
      match cfn_output_value(&doc, "O", &ctx) {
        Ok(v) => { io.println(v); },                         // env=prod
        Err(e) => { io.println(e); },
      }
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

Lifecycle:

```xi
let s = stack_new("demo");
match stack_apply(&s, STACK_EV_CREATE_BEGIN) { Ok(s1) => { /* ... */ }, Err(e) => {} }
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom-cfn
```

Expected tail: 26 `[PASS]` lines, `xiom.cfn: all tests passed`, then
`port: PASS (passed=26 failed=0 program_exit=0 exit=0)`.

## Limitations (honest scope)

- **No AWS calls.** There is no client, no credentials, no deployment: the
  package models templates and lifecycle state only. Physical ids and
  attributes are deterministic simulations (resource Ref -> logical id,
  GetAtt -> `Logical.Attr`, overridable through the context).
- **JSON subset, not full JSON.** Integer numbers only (no floats, no
  exponents), no surrogate-pair escapes, no duplicate keys, 64-level depth
  cap. CloudFormation YAML templates are out of scope.
- **Intrinsic subset.** Ref, Fn::GetAtt, Fn::Join, Fn::Sub, Fn::Select,
  Fn::Split, Fn::If, Fn::Equals, Fn::FindInMap. Rules functions, Fn::And/Or/Not,
  Fn::ImportValue, Fn::Cidr, Fn::Transform and dynamic references are out of
  scope.
- **Conditions** are `{"Fn::Equals": [...]}` or `{"Condition": "Other"}`.
  Nested Fn::If inside a condition expression is not evaluated.
- **Mappings and parameter defaults are literal.** Intrinsics inside mapping
  values or defaults are not evaluated (matching CloudFormation).
- Change sets classify MODIFY only by Type change (replacement) or a
  structural Properties difference; property-level replacement semantics
  (which property updates require replacement) are not modelled.
- Percent-encoding, YAML, stack imports/exports resolution, drift detection,
  rollback triggers and service quotas are out of scope.

See `SPEC.md` for the full template subset, the intrinsic semantics table and
the error catalog. License: MIT OR Apache-2.0 (see the repository root
`LICENSE`).
