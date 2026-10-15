# xiom.template -- Specification

Version: 0.2.0 (stable tier). Published reference: 0.1.2.
Modules: `xiom.template` (`src/template.xi`, the v0.1 placeholder surface,
unchanged) and `xiom.template.blocks` (`src/blocks.xi`, the v0.2 block
surface: sections, loops, inverted sections, dotted paths, auto-escaping).
Pure XIOM, no FFI.

## 1. Scope

A small, dependency-free Mustache-subset renderer for in-memory `Str`
templates, driven by two parallel vectors (`keys` and `values`):

- render strictly, reporting missing keys and unterminated braces as `Err`
  (`template_render`),
- render leniently, treating both as empty text (`template_render_lenient`),
- list referenced names (`template_keys`) and names missing from a key list
  (`template_needs_keys`).

The v0.1 feature set is intentionally limited to substitution, comments and
literal-brace escaping. The 0.2.0 block module adds a separate surface with
sections, loops, inverted sections, dotted paths, a context stack and
optional HTML auto-escaping over a conservative flat data model (§10-§13);
the v0.1.x signatures are unchanged and keep their exact semantics (§3-§5).
Partials remain a non-goal for both surfaces (§2).

## 2. Non-goals

Package-wide (both surfaces):

- Partials (`{{>...}}`), template inheritance/blocks/parents, lambdas and
  set-delimiters (`{{=...=}}`); standalone-line whitespace handling.
- Any recursive, self-referential or nested object model: structure is
  expressed by dotted names over the flat ordered data (§10).
- A compile step, a key-value map type or streaming/incremental rendering
  (one whole `Str` in, one whole `Str` out; re-render as often as needed).
- Any FFI, file I/O, or registry integration; globals; wall clock.

v0.1 surface specifically: no sections, loops, inverted sections or dotted
names (use the 0.2.0 block module for those), no context stack, no value
types beyond `Str`, and no output escaping; values are inserted byte-exact
(§3-§5).

## 3. Grammar

Informal grammar over UTF-8 bytes (`SP` = ASCII space, 0x20):

```
template    = *( text | quadruple | comment | placeholder )
text        = byte not starting a "{{" sequence
quadruple   = "{{{{"
comment     = "{{" *SP "!" *( UTF8 except "}}" ) "}}"
placeholder = "{{" *SP name *SP "}}"
name        = *( UTF8 except "}}" )
```

Linearity is left-to-right and single-pass. The closing `}}` of a comment or
placeholder is the **first** `}}` at or after the two bytes that follow the
opening `{{`; there is no nesting and no escape character other than `{{{{`.
The only trimming is ASCII spaces (0x20) immediately inside the braces.

## 4. Semantics

1. **Scan.** At each byte, `{{` opens a decision point; any other byte is
   copied to the output verbatim (including a lone `{`, a lone `}`, and a
   stray `}}` outside a placeholder).
2. **Quadruple rule.** If the two bytes after `{{` are also `{{`, the four
   bytes emit one literal `{{` and scanning continues after them. Examples:
   `{{{{` => `{{`; `a{{{{b` => `a{{b`; `{{{{name}}` => `{{name}}`.
3. **Comments.** Otherwise, if the byte after the inner leading spaces is
   `!`, everything from `{{` through the closing `}}` is removed. Comments
   are never key references and are excluded from `template_keys` /
   `template_needs_keys`. `{{!x}}`, `{{! x }}` and `{{ ! x }}` are all
   comments.
4. **Placeholders.** Otherwise the inner text (between the braces, before
   trimming) is trimmed of ASCII spaces on both sides; the result is the
   **name**. The name may be empty; it is a normal name and matches the
   empty-string key when one is present.
5. **Lookup.** The renderer scans `keys` and `values` in parallel from index
   0 up to `min(keys.len(), values.len()) - 1` and takes the first index
   whose key equals the name (`str_compare == 0`). Consequences: the first
   duplicate key wins; a key without a parallel value never matches and is
   treated as missing.
6. **Substitution.** On a hit, the value is copied into the output byte-exact.
7. **Single pass.** Substituted values are never re-scanned, so a value
   containing `{{...}}` is emitted literally and rendering cannot recurse.
8. **Missing key.** Strict mode returns
   `Err("template: missing key: <name>")`; lenient mode emits nothing for
   that placeholder and continues.
9. **Unterminated `{{`.** When no closing `}}` exists (this includes an
   unterminated comment), strict mode returns
   `Err("template: unterminated placeholder")`; lenient mode drops the tail
   from the `{{` to EOF and returns the output built so far.
10. **`template_keys`.** Returns the distinct placeholder names in first-seen
    order (deduplicated by `str_compare`), comments excluded. Names seen
    before an unterminated `{{` are still reported; an unterminated tail
    contributes nothing.
11. **`template_needs_keys`.** Returns the names from `template_keys` that
    have no match in `keys` (again first-seen order and deduplicated). Only
    `keys` is consulted: a key present without a parallel value is not
    flagged here, but `template_render` reports it as missing (rule 5).
12. **Encoding.** `Str` is treated as an opaque UTF-8 byte buffer. Scanning
    is byte-wise; all multi-byte sequences pass through byte-exact because
    the trigger bytes (`{` 0x7B, `}` 0x7D, ` ` 0x20, `!` 0x21) are ASCII and
    can never occur inside a multi-byte UTF-8 sequence.

## 5. Error catalog

| Condition | `template_render` (strict) | `template_render_lenient` |
|---|---|---|
| Referenced name has no matching key/value | `Err("template: missing key: " + name)` | placeholder renders `""`; rendering continues |
| `{{` without a following `}}` (including a comment) | `Err("template: unterminated placeholder")` | comment/placeholder and the rest of the template are dropped; the prefix before the `{{` is returned |

No other condition produces an `Err`: plain text, lone braces, stray `}}`,
empty names and empty values are all legal. Strict mode stops at the first
problem.

## 6. API signatures (v0.1 surface, unchanged in 0.2.0)

```xi
pub fn template_render(tmpl: Str, keys: &Vec[Str], values: &Vec[Str]) -> Result[Str, Str]
pub fn template_render_lenient(tmpl: Str, keys: &Vec[Str], values: &Vec[Str]) -> Str
pub fn template_keys(tmpl: Str) -> Vec[Str]
pub fn template_needs_keys(tmpl: Str, keys: &Vec[Str]) -> Vec[Str]
```

The v0.2.0 block surface (`xiom.template.blocks`) is specified in §10.3.

Complexity: rendering is O(n) over the template plus O(placeholders x keys)
for the lookups; `template_keys` is O(n x names); `template_needs_keys` is
O(n x names x keys). Output is built in one `xiom.string.builder` buffer
(one allocation per rendered `Str`).

## 7. Test plan

`tests/test_conformance.xi` (module `template_tests`) runs 43 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). t1-t22 pin the v0.1 placeholder surface
(unchanged in 0.2.0); t23-t43 pin the v0.2 block surface
(`xiom.template.blocks`, §10-§13). Every string comparison goes through
`xiom.string.compare`'s `str_compare`; `Result` values are checked through
`is_ok` / `value` / `error`.

### 7.1 v0.1 placeholder surface (t1-t22)

| # | Check | Semantics pinned |
|---|---|---|
| t1 | plain text | no trigger bytes => byte-identical output |
| t2 | single placeholder | `Hello, {{name}}!` substitution |
| t3 | multiple placeholders | three keys in one template |
| t4 | spaces inside braces | `{{ name }}`, `{{name }}`, `{{  name  }}` all match `name` (rule 4) |
| t5 | strict missing key | exact `Err` message (rule 8) |
| t6 | lenient missing key | renders `""` and continues (rule 8) |
| t7 | duplicate key | first match wins (rule 5) |
| t8 | comments | `{{! ... }}`, `{{!note}}`, `{{ ! spaced }}` removed (rule 3) |
| t9 | quadruple braces | `{{{{` => `{{`; inside text; before a name (rule 2) |
| t10 | strict unterminated | exact `Err` for text tail, bare `{{`, unterminated comment (rule 9) |
| t11 | lenient unterminated | tail dropped, prefix kept (rule 9) |
| t12 | adjacent placeholders | `{{a}}{{b}}{{a}}{{b}}` => `1212` |
| t13 | empty template | `""` in both modes; `template_keys("")` empty |
| t14 | empty value | present-but-empty is not "missing" (rule 5) |
| t15 | keys order/dedup | first-seen, dedup, comments and quadruples excluded (rule 10) |
| t16 | needs_keys | missing names in first-seen order; comments excluded (rule 11) |
| t17 | single pass | a value containing `{{b}}` is not re-expanded, even when `b` is a key (rule 7) |
| t18 | empty name | `{{}}` matches the `""` key; strict `Err` and lenient `""` otherwise (rule 4) |
| t19 | whitespace-only name | `{{  }}` behaves as the empty name (rule 4) |
| t20 | non-ASCII | `café {{x}} ✓` passes through byte-exact (rule 12) |
| t21 | key without value | counts as missing for the renderer; `needs_keys` unchanged (rules 5/11) |
| t22 | literal braces | `{b}`, `}{`, `a}}b` verbatim; `{{a}}}` => value + `}` (rule 1) |

### 7.2 v0.2 block surface (t23-t43)

| # | Check | Semantics pinned |
|---|---|---|
| t23 | list iteration | items render in order with `{{.}}`; single-item list |
| t24 | falsy sections | empty list / empty `Str` / `false` skip (strict and lenient) |
| t25 | truthy sections | `true` Bool, non-empty `Str`, dotted group render once |
| t26 | inverted sections | falsy/empty render, truthy skip; a missing key renders in lenient mode |
| t27 | nested + dotted + ancestors | `user` / `user.address` groups, `user.name`, root fallback pinned |
| t28 | list parent context | non-dot keys inside a loop resolve against the parent (loops keep the prefix) |
| t29 | nested lists | the inner list iterates per outer item; `{{.}}` is the innermost item |
| t30 | auto-escape | exact `&lt;&amp;&gt;&quot;&#39;` output for `<&>"'` |
| t31 | raw forms | `{{{v}}}`, `{{&v}}`, `{{ & v }}` stay raw in escape mode |
| t32 | escape off | `{{v}}` and `{{.}}` verbatim when `escape_html=false` |
| t33 | unicode | `café`, `é`, `✓`, `日本` byte-exact incl. loops and escape mode |
| t34 | unterminated sections | exact Errs at the opening offsets (innermost unclosed frame) |
| t35 | mismatched closes | exact Errs at the close offsets (wrong open vs stray) |
| t36 | unclosed interpolation | placeholder, triple and unterminated comment variants |
| t37 | strict unknown keys | interpolation, section, inverted and `.` outside a list |
| t38 | lenient behavior | unknown keys, ignored bad close, virtual EOF closes, unclosed tail dropped |
| t39 | depth cap | 64 nested sections render; the 65th is a strict Err at byte 384 / suppressed in lenient |
| t40 | output cap | strict Err at byte 8; lenient output is exactly 8388608 bytes |
| t41 | KAT page | mixed page (escape + loop + inverted + raw) with hand-computed output |
| t42 | data model | accessors, kind constants, replace-in-place, list copy semantics |
| t43 | conventions | comments, `{{{{`, spaced tags and lone braces keep the v0.1 conventions |

Recorded x2 green (43/43) on XIOM v0.64.5 via
`.\scripts\port.ps1 -Package xiom.template -TimeoutSec 600`; the port
summary line is `port: PASS (passed=43 failed=0 program_exit=0 exit=0)`.

## 8. Known limitations

- v0.1 surface: no sections/conditionals, loops, dotted names, lambdas or
  delimiter changes; no escaping of substituted values. The block module
  covers sections/loops/dotted names/escaping; partials and lambdas stay
  non-goals for both surfaces (§2).
- Block surface: the flat data model is the shipped design decision (no
  recursive or nested objects; §10, §14.1). Only `Str` entries carry
  interpolated text; Bool, list and group interpolations render `""`.
  A list section keeps the parent context for non-dot names (only `{{.}}`
  is the item). Nesting depth and output size are capped (§13).
- Only ASCII spaces are trimmed inside braces; tabs/newlines are part of a
  name.
- Linear entry lookup per resolved name (no map/index acceleration);
  finding a dotted group is a linear prefix scan.
- Strict mode discards partial output and reports only the first problem;
  tags inside skipped sections are still matched structurally.
- `template_needs_keys` sees keys only, not values (rule 11).
- No streaming API; whole-template-in-memory only.
- The v0.1 surface scans bytes with `xiom.string.byte_at`; the runtime
  clamps those reads at 1 MiB (`xiom_runtime.c`: `strnlen(str, 1 << 20)`,
  reads past the clamp return 0) and re-scans per call, so that surface is
  quadratic on large inputs and cannot see bytes past 1 MiB (status quo of
  0.1.2, kept byte-for-byte for compatibility). The block module uses
  raw-pointer reads instead (§14.2) and its 8 MiB output cap is exact.

## 9. Compiler / stdlib notes

The v0.1 module (`src/template.xi`) uses the proven v0.61.3 idioms from the
sibling packages (`xiom.escape`, `xiom.typography`, `xiom.csv`): byte-wise
scanning via `xiom.string.byte_at` normalized as
`(byte_at(s, i) as Int) & 0xFF`, single-allocation output through
`xiom.string.builder`
(`sb_new` / `sb_push_str` / `sb_push_byte` / `sb_to_str`), and free functions
only. Two deliberate workarounds:

- `Ok` / `Err` for `Result[Str, Str]` are constructed only in the leaf
  helpers `_ok_str` / `_err_str` (constructing `Result`s directly inside
  other functions miscompiles on this compiler); `template_render` simply
  forwards the result of the shared `_render`.
- Every string comparison, including key lookup and dedup, goes through
  `xiom.string.compare.str_compare` instead of `==` (BUG 17: `==` on `Str`
  values read from `Vec[Str]` elements lowers to a pointer comparison).

The conformance suite avoids inline lambdas, `mut` patterns, `Vec[fn]`
dispatch and non-exhaustive `match`es by using one explicit `fn` per check
and explicit `main` dispatch, like the sibling suites.

The v0.2 block module adds one more toolchain discipline: bytes are read
through a cached raw pointer (`Str.c_str()` + `unsafe` deref, the
`xiom.string.builder` wave-129 idiom) instead of `string.byte_at`, because
the runtime's `byte_at` re-scans the string per call and clamps at 1 MiB
(§8, §14.2). All raw reads are bounded by the cached length in the same
function.

## 10. Block surface (`xiom.template.blocks`)

### 10.1 Data model

Design decision (2026-10-15): the compiler probe (§14.1) shows the pinned
toolchain is reliable for flat record/vector shapes and risky for
recursive ones, so the block surface ships the conservative flat model
below -- no recursive enums, no structs-with-self, no recursion tricks.

- `TemplateData` is a flat, ordered `Vec[TemplateEntry]`. Entries keep
  first-set order; setting an existing name replaces the value in place.
- A `TemplateEntry` value is exactly one of:

| `kind` | Constant | Fields used | Section behavior |
|---|---|---|---|
| 0 | `TEMPLATE_VALUE_STR` | `text` | truthy once when non-empty; empty is falsy |
| 1 | `TEMPLATE_VALUE_BOOL` | `flag` | truthy once when `true` |
| 2 | `TEMPLATE_VALUE_LIST` | `items` | iterates once per item when non-empty; `{{.}}` is the item |

- Dotted names (`user.address.city`) are plain entry names. A name with no
  exact entry but with dotted children acts as a context group (truthy
  once, pushing the name as context). An exact entry always wins over its
  children.
- `template_data_set_list` copies the items (the caller keeps ownership of
  its vector).

### 10.2 Declared surface

| Function | Returns | Description |
|---|---|---|
| `template_data_new()` | `TemplateData` | empty ordered data |
| `template_data_set_str(d, name, value)` | - | set/replace a `Str` value |
| `template_data_set_bool(d, name, value)` | - | set/replace a `Bool` value |
| `template_data_set_list(d, name, items)` | - | set/replace a `Str`-list value (copied) |
| `template_data_len(d)` | `Int` | entry count |
| `template_data_has(d, name)` | `Bool` | exact-name presence (groups excluded) |
| `template_data_kind(d, name)` | `Int` | `TEMPLATE_VALUE_*` or -1 |
| `template_render_blocks(tmpl, data, escape_html)` | `Result[Str, Str]` | strict block render |
| `template_render_blocks_lenient(tmpl, data, escape_html)` | `Str` | block render that never fails |

### 10.3 Signatures

```xi
pub fn template_data_new() -> TemplateData
pub fn template_data_set_str(d: &mut TemplateData, name: Str, value: Str)
pub fn template_data_set_bool(d: &mut TemplateData, name: Str, value: Bool)
pub fn template_data_set_list(d: &mut TemplateData, name: Str, items: &Vec[Str])
pub fn template_data_len(d: &TemplateData) -> Int
pub fn template_data_has(d: &TemplateData, name: Str) -> Bool
pub fn template_data_kind(d: &TemplateData, name: Str) -> Int
pub fn template_render_blocks(tmpl: Str, data: &TemplateData, escape_html: Bool) -> Result[Str, Str]
pub fn template_render_blocks_lenient(tmpl: Str, data: &TemplateData, escape_html: Bool) -> Str
```

## 11. Block grammar and semantics

Grammar (left-to-right single scan; `SP` = ASCII space):

| Tag | Kind | Semantics |
|---|---|---|
| `{{name}}` | interpolation | substitutes the `Str` value; HTML-escaped when `escape_html` is set |
| `{{{name}}}` | raw interpolation | substitutes the `Str` value; never escaped |
| `{{&name}}` / `{{ & name }}` | raw interpolation | same as triple; leading spaces are skipped before the marker |
| `{{! ... }}` | comment | removed entirely; never a key |
| `{{#key}} ... {{/key}}` | section | iterate a non-empty `Str` list; render once for a truthy Bool / non-empty Str / dotted group; skip when falsy or (lenient) unknown |
| `{{^key}} ... {{/key}}` | inverted | render once when falsy / empty / (lenient) missing; skip when truthy |
| `{{/key}}` | close | must match the innermost open tag name exactly (after trimming) |
| `{{{{` | literal | emits one `{{` (v0.1 rule kept) |

- **Context stack.** A truthy section on `key` pushes the resolved name as
  context; a list section pushes nothing (non-dot names inside a list
  section resolve against the parent context -- only `{{.}}` is the item,
  the innermost list frame winning); an inverted section pushes nothing.
- **Lookup chain.** For `name`, try `inner-prefix + "." + name`, then each
  ancestor frame's prefix, then the root `name`; the first existing entry
  or dotted group wins. Dotted paths resolve against the same chain
  ("current context, then ancestors").
- **`.`** is the innermost list item; outside a list it is unknown (strict
  Err).
- **Interpolation values.** Only `Str` entries carry text; Bool, list and
  group interpolations render `""` (sections consume those).
- **Truthiness.** Non-empty `Str`, `true`, non-empty list or dotted group
  are truthy; empty `Str`, `false`, empty list and missing are falsy.
- **Auto-escape.** `escape_html = true` escapes exactly `& < > " '` as
  `&amp; &lt; &gt; &quot; &#39;` in `{{name}}` / `{{.}}` substitutions;
  `{{{...}}}` and `{{&...}}` stay raw. Template text is never escaped and
  multi-byte UTF-8 passes through byte-exact (all five escaped bytes are
  ASCII). `escape_html = false` copies every value verbatim.
- **Single pass.** Substituted values are never re-scanned; rendering
  cannot recurse.
- **Offsets.** Every Err carries a 0-based byte offset into `tmpl`.
- **Strategy.** One scan with an explicit frame stack; a list section
  re-scans its body from `body_start` per close tag, so no text is copied
  per iteration and no recursive function is used.

## 12. Block error catalog (strict / lenient)

| Condition | `template_render_blocks` (strict) | `template_render_blocks_lenient` |
|---|---|---|
| Unknown name (`{{k}}`, `{{#k}}`, `{{^k}}`, `{{.}}` outside a list) | `Err("template: unknown key: <name> at byte <off>")` at the tag | renders `""`; a section body is skipped; an inverted body is rendered |
| `{{` without a closing `}}` (placeholder, triple, raw or comment) | `Err("template: unclosed interpolation at byte <off>")` at the `{{` | drops the rest of the template (the prefix before the `{{` is kept) |
| Open section with no matching close | `Err("template: unterminated section '<name>' at byte <off>")` at the opening tag of the innermost unclosed frame | completes every open section as if closed at end of template (list sections iterate their remaining items) |
| Close tag with no open section | `Err("template: mismatched close '<name>' at byte <off>")` at the close | ignored |
| Close tag not matching the innermost open tag | `Err("template: mismatched close '<name>' at byte <off> (expected '<open>')")` at the close | ignored |
| Nesting past `TEMPLATE_MAX_DEPTH` | `Err("template: nesting exceeds 64 at byte <off>")` at the opening tag | the section is suppressed (never fails) |
| Output past `TEMPLATE_MAX_OUTPUT` | `Err("template: output exceeds 8388608 bytes at byte <off>")` | the output is truncated at the cap |

Strict mode stops at the first problem and discards partial output. Tags
inside a skipped (falsy or over-depth) section are not evaluated, but in
strict mode they are still matched structurally: a mismatched or unclosed
tag inside a skipped body is still an Err.

## 13. Block limits and complexity

| Cap | Constant | Value | Behavior |
|---|---|---|---|
| Section nesting depth | `TEMPLATE_MAX_DEPTH` | 64 | strict Err / lenient suppression past the cap; suppressed (skipped) frames count toward it |
| Rendered output | `TEMPLATE_MAX_OUTPUT` | 8388608 (8 MiB) | checked before every append, so a strict render never exceeds it and the lenient twin truncates at exactly the cap |

Complexity: one scan plus, per evaluated tag, a context-stack walk and a
linear entry scan -- O(tags x frames x entries) worst case; output
building is O(output) with one allocation per rendered `Str`. Offsets and
cap messages are formatted without an Int-to-Str dependency
(`builder.sb_push_int`).

## 14. Build evidence (XIOM v0.64.5, 2026-10-15)

1. **Data-model probe (required before the renderer was built).** A scratch
   module was compiled and run on the pinned compiler (v0.64.5, installed)
   before any renderer code was written. It verified with no errors:
   `TemplateData { entries: Vec[TemplateEntry] }` with Str/Int/Bool/Vec[Str]
   fields; replace-or-append setters using whole-element assignment; typed
   element reads; `Vec[_Frame]` push/pop/top-read; byte-wise dotted-group
   detection; `builder.sb_push_int` error text; and a strict-fn/contract
   skeleton. Result: `PROBE OK: flat TemplateData + Vec[_Frame] compile and
   behave`. The conservative flat model is therefore the shipped design.
2. **Byte-access probe.** The block suite's first run failed two checks;
   debugging showed the runtime's `xiom_byte_at` clamps reads with
   `strnlen(str, 1 << 20)`: `string.byte_at` at index >= 1 MiB returns 0,
   and each call re-scans up to 1 MiB. The block module now reads bytes
   through a cached raw pointer (the `xiom.string.builder` idiom); a probe
   confirmed exact reads at 0 / 4 MiB / 8 MiB-1 on an 8 MiB string. The
   v0.1 surface is unchanged and keeps its `byte_at` scan (§8).
3. **Suite result.** 43/43 checks green on v0.64.5, twice (see the run
   evidence in the testing section of README.md and the Contracts section
   below).

## Contracts (hardening pass, 2026-10-05; block entries added 2026-10-15)

Runtime-checked contracts; `xiom-verify --check` (Z3 4.13.4 on v0.63.0)
result for the v0.1.2 hardening pass: **0 proven / 0 violated / 11 unknown /
4 errors**. The two port runs of that pass with runtime contract checking
are green (22/22 checks, exit 0), so every v0.1 clause below held on the
paths the suite exercises; the solver line's unknowns are emitter-level
(`Str` payload sorts) and its 4 errors are SMT emitter errors over the
internal helpers `_render` / `_collect_names`, not violations.

| Entry point | Contract | Runtime | Solver |
|---|---|---|---|
| `template_render` | `ensures: tmpl.len() == 0 => result is Ok` | holds | unknown |
| `template_render` | `ensures: result is Err => tmpl.len() > 0` | holds | unknown |
| `template_render_lenient` | `ensures: tmpl.len() == 0 => result.len() == 0` | holds | unknown |
| `template_render_lenient` | `ensures: keys.len() == 0 && values.len() == 0 => result.len() <= tmpl.len()` | holds | unknown |
| `template_keys` | `ensures: result.len() <= tmpl.len()` | holds | unknown |
| `template_keys` | `ensures: tmpl.len() == 0 => result.len() == 0` | holds | unknown |
| `template_needs_keys` | `ensures: result.len() <= tmpl.len()` | holds | unknown |
| `template_needs_keys` | `ensures: tmpl.len() == 0 => result.len() == 0` | holds | unknown |
| `template_render_blocks` | `ensures: tmpl.len() == 0 => result is Ok` | holds | not run (new in 0.2.0) |
| `template_render_blocks` | `ensures: result is Err => tmpl.len() > 0` | holds | not run (new in 0.2.0) |
| `template_render_blocks_lenient` | `ensures: tmpl.len() == 0 => result.len() == 0` | holds | not run (new in 0.2.0) |
| `template_render_blocks_lenient` | `ensures: result.len() <= TEMPLATE_MAX_OUTPUT` | holds | not run (new in 0.2.0) |

No clause was dropped: all eight v0.1 clauses were exercised by the
22-check suite under the runtime evaluator on the first attempt. The four
v0.2.0 clauses above hold under the runtime evaluator on both recorded
43-check port runs (the suite renders empty and non-empty templates and
the 8 MiB truncation path on every run). A `xiom-verify` (Z3) pass over
the new module was not part of this change; the clauses stay annotated for
review/tests, matching the stable-tier rule that contracts are a
correctness floor (docs/PROMOTION.md).

Unasserted/documented: the exact rendered bytes (values copied verbatim,
comments and quadruples removed, single-pass no-rescan), the lookup rules
(`min(keys.len(), values.len())` scan, first match for duplicates, empty
name) and the two `Err` messages are pinned by the 22-check test plan and
sections 3-5. A general output-length relation is deliberately unasserted:
substituted values may be much longer than the template, so no
`result.value.len()` / `result.len()` bound exists beyond the
empty-template cases above; string-content contracts stay out of scope for
the runtime evaluator. The same holds for the v0.2 renderers: the block
byte model, the four error texts and the caps are pinned by t23-t43 and
sections 10-13 (the one expressible bound, `result.len()` <= the output
cap, is annotated and checked at runtime).

## Changelog

- **0.2.0** (2026-10-15): new module `xiom.template.blocks` -- sections
  (`{{#key}}`), inverted sections (`{{^key}}`), loops over `Str` lists with
  `{{.}}`, nested sections with a context stack and dotted paths,
  HTML auto-escaping (`escape_html`) with raw `{{{...}}}` / `{{&...}}`
  forms, typed errors with byte offsets (unknown key, unclosed
  interpolation, unterminated section, mismatched close) and the caps
  `TEMPLATE_MAX_DEPTH = 64` / `TEMPLATE_MAX_OUTPUT = 8388608`; the flat
  `TemplateData` model; the v0.1.x placeholder surface is unchanged
  byte-for-byte. Test suite 22 -> 43 checks (t1-t22 untouched, t23-t43
  new); `port.ps1` x2 green on v0.64.5.
- **0.1.2** (published reference): placeholder surface
  (`template_render` / `template_render_lenient` / `template_keys` /
  `template_needs_keys`), 22-check suite, 8 contract clauses.
- **0.1.x**: the same placeholder surface; unchanged by 0.2.0.

