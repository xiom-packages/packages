# xiom.terraform -- specification

Version 0.1.0. Pure-XIOM infrastructure-as-code workflow model for the
`xiom.terraform` module: HCL subset parsing, execution plan modelling,
apply/destroy state machine, state and provider registry. No network, no
sockets, no FFI, no clock, no randomness, no file access. Every function is
total over its documented domain and deterministic.

All strings are byte strings; comparisons are byte-exact and go through
`xiom.string.str_compare` internally. Byte reads are widened and masked before
any comparison.

## 1. HCL subset grammar

```
document    = *body-element
body-element = attribute / block
attribute   = ident ws* "=" ws* value line-end
block       = ident *(" " label) ws* "{" body "}"
label       = quoted-string                     ; non-empty, no "/"
value       = quoted-string                     ; kind str or interp
            | number                            ; kind num
            | "true" / "false"                  ; kind bool
            | "null"                            ; kind null
            | "[" ws* [ element *( "," element ) ] ws* "]"   ; kind list
            | "{" ws* [ map-entry *( "," map-entry ) ] ws* "}" ; kind map
            | reference                         ; kind ref
reference   = ident *( "." ident / "[" ... "]" )
ident       = ( letter / "_" ) *( letter / digit / "_" / "-" )
number      = [ "-" ] 1*digit [ "." 1*digit ]
```

Lexical rules:

* whitespace is space, tab, LF, CR (CRLF counts as one line break);
* comments are `# ...` to end of line, `// ...` to end of line, and
  `/* ... */` (block comments do not nest and may span lines);
* an attribute must end at a line end (`LF`/`CR`), a `#` or `//` comment, the
  end of input, or a closing `}` of the enclosing block; trailing text after a
  value is an error;
* a block header is `type` followed by zero or more `"label"` strings and a
  `{`. Labels are joined for storage with `/`; a label containing `/` or an
  empty label is rejected so the joined form stays reversible;
* nesting depth is capped at 32, blocks at 256, attributes at 1024, and the
  whole input at 65536 bytes.

Value kinds (`attr_kind`): `"str"`, `"interp"`, `"num"`, `"bool"`, `"null"`,
`"list"`, `"map"`, `"ref"`. A quoted string containing the two-byte sequence
`${` is `interp`, otherwise `str`. Values are stored in normal form:

* `str`: the string content with escape sequences decoded, without quotes;
* `interp`: same, with `${...}` kept verbatim;
* strings support exactly the escapes `\"`, `\\`, `\n`, `\t`, `\r`; any other
  backslash sequence is an error;
* `num`: the literal text (no `Float64` is ever produced; decimals stay text);
* `bool` / `null`: the canonical word;
* `ref`: the dotted/indexed reference text;
* `list`: the comma-separated element texts, trimmed, without the outer
  brackets (the empty list is stored as `""`);
* `map`: the comma-separated `key = value` entries, trimmed, without the outer
  braces.

`hcl_parse(text) -> Result[TfConfig, Str]` parses one document. On success the
document is stored as parallel vectors (`block_*`, `attr_*`), never as
`Vec[StructType]`: blocks are in source order (preorder), attributes in source
order with `attr_owner` = block index or `-1` for top-level attributes.

Helpers: `hcl_kind(text)` classifies a raw value text; `hcl_is_interp(text)`
tests for `${`; `hcl_ref_root(ref)` returns the first reference segment;
`hcl_split_list(text)` / `hcl_list_count` / `hcl_list_item` split list text on
top-level commas (nested brackets and quoted strings are respected);
`hcl_map_count` / `hcl_map_key` / `hcl_map_value` / `hcl_map_get` read map text
(`=` or `:` separators; quoted keys and values are returned unquoted);
`hcl_quote(s)` renders a string value with the supported escapes.

### 1.1 Error catalog

Every parse error is `"hcl: <message> at line <n>"` except the two whole-input
checks, which have no line suffix:

| condition | message |
|-----------|---------|
| NUL byte in input | `hcl: NUL byte in input` |
| input longer than 65536 bytes | `hcl: input too large` |
| stray `}` at top level | `hcl: unexpected '}'` |
| block comment never closed | `hcl: unterminated block comment at line <n>` |
| string never closed / raw newline inside | `hcl: unterminated string at line <n>` |
| unknown escape | `hcl: invalid escape sequence at line <n>` |
| list never closed | `hcl: unterminated list at line <n>` |
| map never closed | `hcl: unterminated map at line <n>` |
| mixed bracket pair (`[1, 2}`) | `hcl: mismatched brackets in <list/map> at line <n>` |
| attribute name does not start with letter/`_` | `hcl: invalid identifier at line <n>` |
| attribute value has trailing garbage on the line | `hcl: unexpected text after attribute at line <n>` |
| duplicate attribute in the same body | `hcl: duplicate attribute <name> at line <n>` |
| empty label or label containing `/` | `hcl: invalid block label at line <n>` |
| block header not followed by `{` | `hcl: expected '{' after block header at line <n>` |
| block body not closed | `hcl: expected '}' to close block at line <n>` |
| function calls / other expressions | `hcl: unsupported value expression at line <n>` |
| malformed number | `hcl: invalid number at line <n>` |
| nesting deeper than 32 | `hcl: block nesting too deep at line <n>` |
| more than 256 blocks | `hcl: too many blocks at line <n>` |
| more than 1024 attributes | `hcl: too many attributes at line <n>` |

## 2. Config model

Blocks:

* `config_block_count`, `config_block_type`, `config_block_labels` (joined
  with `/`), `config_block_label_count`, `config_block_label(bi, li)` (`""`
  out of range), `config_block_label_list`, `config_block_line`,
  `config_block_parent` (`-1` at top level);
* `config_block_index(c, type, label)` -- first block of `type` whose first
  label equals `label` (label `""` matches any), or `-1`;
* `config_nth_block(c, type, n)` -- index of the n-th block of `type`, or `-1`;
* `config_resource_count` / `config_resource_address(c, i)` -- n-th `resource`
  block as `type.name` from its first two labels.

Attributes:

* `config_attr_count`, `config_attr_name`, `config_attr_kind`,
  `config_attr_value`, `config_attr_line`, `config_attr_owner`;
* `config_attr_index(c, owner, name)` -- first attribute of `owner` with
  `name`, or `-1`;
* `config_attr_get(c, owner, name) -> Option[Str]`,
  `config_attr_get_kind(c, owner, name) -> Option[Str]`;
* `config_block_attr_count(c, bi)`, `config_block_attr_name/_kind/_value(c,
  bi, j)` -- j-th attribute owned by block `bi`.

`config_render(c)` renders canonical HCL text: top-level attributes first (in
order), then blocks (in order), each block as `type "label" ... {`, indented
attributes, then nested blocks, then `}`. Values are re-rendered by kind
(strings quoted and escaped; lists/maps bracketed; everything else verbatim).
Because blocks and attributes are stored in separate vectors, the relative
order of an attribute and a block in the same body is not preserved; within
each category order is stable, so `parse -> render -> parse` preserves the
block tree, kinds and values.

## 3. Plan model

Actions: `TF_ACTION_CREATE=1`, `TF_ACTION_UPDATE=2`, `TF_ACTION_DELETE=3`;
`plan_action_name` returns `"create"`, `"update"`, `"delete"` or `"unknown"`.

* `plan_new()` -- empty plan.
* `plan_add_change(p, addr, action, reason) -> Result[Int, Str]` -- adds one
  change node and returns its index. Errors: empty address
  (`plan: resource address must not be empty`), unknown action
  (`plan: unknown action`), duplicate address
  (`plan: duplicate resource address: <addr>`), capacity
  (`plan: change limit exceeded`).
* `plan_add_diff(p, ci, attr, before, after) -> Result[Int, Str]` -- adds one
  attribute diff under change `ci` (the observed value before and the planned
  value after; `""` on the absent side). Errors: unknown change
  (`plan: unknown change id`), empty attribute
  (`plan: diff attribute must not be empty`), duplicate attribute for that
  change (`plan: duplicate diff attribute: <attr>`), capacity
  (`plan: diff limit exceeded`).
* `plan_add_dep(p, before, after) -> Result[Int, Str]` -- declares that change
  `after` depends on change `before` (so `before` applies first). Errors:
  unknown id (`plan: unknown dependency id`), self edge
  (`plan: dependency on self`), duplicate edge (`plan: duplicate dependency`).
* accessors: `plan_count`, `plan_addr`, `plan_action`, `plan_reason`,
  `plan_diff_count`, `plan_change_diff_count`, `plan_diff_owner`,
  `plan_diff_attr`, `plan_diff_before`, `plan_diff_after`.
* `plan_order(p) -> Result[Vec[Int], Str]` -- Kahn topological order, smallest
  ready index first; `Err("plan: dependency cycle")` on a cycle.
  `plan_has_cycle` mirrors it.
* `plan_summary(p)` -- `"<c> to create, <u> to update, <d> to delete"`.
* `plan_render(p)` -- deterministic multi-line text: `+ addr` / `~ addr` /
  `- addr`, `" (reason)"` appended when the reason is non-empty, then two-space
  indented `attr: before -> after` lines for each diff.

## 4. State model and apply/destroy machine

State fields: `lineage` (non-empty), `serial` (starts at 1), `next_rev`
(starts at 1), and per-resource parallel vectors `res_addr`, `res_status`,
`res_rev`. Statuses: `TF_RES_PENDING=0`, `TF_RES_CREATED=1`,
`TF_RES_UPDATED=2`, `TF_RES_DELETED=3`; `state_status_name` returns
`pending`/`created`/`updated`/`deleted`/`unknown`.

`state_new(lineage) -> Result[TfState, Str]` (error `state: lineage must not
be empty`). `state_add_resource(s, addr) -> Result[Int, Str]` adds a
`pending` resource with revision 0; errors `state: resource address must not
be empty`, `state: duplicate resource address: <addr>`,
`state: resource limit exceeded`.

Transition table (`state_can_transition`), exactly six legal pairs:

| from \ to | PENDING | CREATED | UPDATED | DELETED |
|-----------|---------|---------|---------|---------|
| PENDING   | -       | yes     | -       | yes     |
| CREATED   | -       | -       | yes     | yes     |
| UPDATED   | -       | -       | yes     | yes     |
| DELETED   | -       | -       | -       | -       |

`state_transition(s, i, to) -> Result[Int, Str]` performs one transition,
assigns the next revision ID (`next_rev`, monotonically increasing) to the
resource, increments `serial` and returns the new revision. Errors:
`state: unknown resource id`, `state: resource already deleted`,
`state: illegal state transition: <from> -> <to>`.

`state_apply_plan(s, p) -> Result[Int, Str]` walks the plan in `plan_order`
and applies every change:

* create: the address must not exist; adds it as `pending` then transitions to
  `created` (error `state: resource already exists: <addr>`);
* update: the address must exist and not be `deleted`; a `pending` resource
  must be created first (error `state: resource not created: <addr>`,
  `state: has no resource: <addr>`, `state: resource already deleted:
  <addr>`), then transitions to `updated`;
* delete: the address must exist and be live, then transitions to `deleted`.

It returns the number of applied changes; state is only partially modified if
a change fails (documented, deterministic).

`state_destroy_plan(s)` builds a delete plan for every live resource in
insertion order (reason `destroy`); `state_destroy_all(s)` applies it and
returns the number of destroyed resources. `state_render(s)` emits
`lineage = <lineage>`, `serial = <n>` and one
`<addr> <status> rev=<rev>` line per resource, LF separated.

Other accessors: `state_count`, `state_live_count`, `state_addr`,
`state_status`, `state_rev`, `state_serial`, `state_lineage`,
`state_index` (`-1` when absent), `state_has`.

## 5. Provider registry

`providers_new()`, `provider_register(r, name, source, version) -> Result[Int,
Str]` (non-empty fields; errors `provider: name must not be empty`,
`provider: source must not be empty`, `provider: version must not be empty`,
`provider: duplicate provider: <name>`, `provider: provider limit exceeded`).

`provider_init(r, name)` initializes exactly one registered provider (errors
`provider: unknown provider: <name>`, `provider: already initialized:
<name>`) and returns the new initialized count; `provider_init_all(r)`
initializes all pending providers in registration order and returns how many
were initialized. `provider_is_initialized`, `provider_is_ready`,
`provider_index`, `provider_count`, `provider_name/_source/_version`,
`provider_init_count`, `provider_render`.

Config integration: `providers_from_config(c)` returns the first label of
every top-level `provider` block, deduplicated in first-occurrence order;
`provider_missing_from_config(r, c)` returns those names that are not
registered or not initialized; `provider_apply_config(r, c) -> Result[Int,
Str]` initializes every configured provider (errors `provider: not
registered: <name>` for names absent from the registry) and returns the number
initialized by the call.

## 6. Capacity limits

`TF_MAX_DEPTH=32`, `TF_MAX_BLOCKS=256`, `TF_MAX_ATTRS=1024`,
`TF_MAX_RESOURCES=256`, `TF_MAX_CHANGES=256`, `TF_MAX_EDGES=1024`,
`TF_MAX_PROVIDERS=64`, `TF_MAX_INPUT=65536`. Graph walks (plan topo order) are
bounded by `TF_MAX_CHANGES` and make progress on every pass.

## 7. Known deviations from full Terraform/HCL

* only the documented HCL subset is supported: no heredocs, no `for`
  expressions, no conditionals, no function calls, no splat expressions;
* numbers are kept as text (no floating-point value is produced);
* interpolation is classified and preserved verbatim; it is never evaluated;
* there are no real providers, no resources and no network: apply/destroy
  transitions are pure state updates;
* state persistence, locking, import and refresh are out of scope.
