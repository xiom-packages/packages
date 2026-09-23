# xiom.template -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.template` (`src/template.xi`). Pure XIOM, no FFI.

## 1. Scope

A small, dependency-free Mustache-subset renderer for in-memory `Str`
templates, driven by two parallel vectors (`keys` and `values`):

- render strictly, reporting missing keys and unterminated braces as `Err`
  (`template_render`),
- render leniently, treating both as empty text (`template_render_lenient`),
- list referenced names (`template_keys`) and names missing from a key list
  (`template_needs_keys`).

The v0.1 feature set is intentionally limited to substitution, comments and
literal-brace escaping; sections, loops and partials are non-goals (§2) and
are documented as limitations in README.md.

## 2. Non-goals

- Sections, inverted sections, conditionals, loops (`{{#...}}`, `{{^...}}`,
  `{{/...}}`), partials (`{{>...}}`), blocks, parents, delimiters
  (`{{=...=}}`), dotted names, lambdas, and standalone-line whitespace
  handling.
- Typed or nested values: a value is always a `Str`; there is no context
  stack and no recursion.
- HTML escaping, auto-escaping or any other output transformation; values are
  inserted byte-exact.
- A compile step or a key-value map type: callers pass `&Vec[Str]` pairs and
  can re-render as often as they like.
- Streaming / incremental rendering (one whole `Str` in, one whole `Str` out).
- Any FFI, file I/O, or registry integration.

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

## 6. API signatures

```xi
pub fn template_render(tmpl: Str, keys: &Vec[Str], values: &Vec[Str]) -> Result[Str, Str]
pub fn template_render_lenient(tmpl: Str, keys: &Vec[Str], values: &Vec[Str]) -> Str
pub fn template_keys(tmpl: Str) -> Vec[Str]
pub fn template_needs_keys(tmpl: Str, keys: &Vec[Str]) -> Vec[Str]
```

Complexity: rendering is O(n) over the template plus O(placeholders x keys)
for the lookups; `template_keys` is O(n x names); `template_needs_keys` is
O(n x names x keys). Output is built in one `xiom.string.builder` buffer
(one allocation per rendered `Str`).

## 7. Test plan

`tests/test_conformance.xi` (module `template_tests`) runs 22 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Every string comparison goes through
`xiom.string.compare`'s `str_compare`; `Result` values are checked through
`is_ok` / `value` / `error`.

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

## 8. Known limitations

- No sections/conditionals, loops, partials, dotted names, lambdas or
  delimiter changes (v0.1 scope; see README.md "Limitations").
- No escaping of substituted values; no HTML auto-escaping.
- Only ASCII spaces are trimmed inside braces; tabs/newlines are part of a
  name.
- Linear parallel-vector lookup per placeholder; no map/index acceleration.
- Strict mode discards partial output and reports only the first problem.
- `template_needs_keys` sees keys only, not values (rule 11).
- No streaming API; whole-template-in-memory only.

## 9. Compiler / stdlib notes

The module uses the proven v0.61.3 idioms from the sibling packages
(`xiom.escape`, `xiom.typography`, `xiom.csv`): byte-wise scanning via
`xiom.string.byte_at` normalized as `(byte_at(s, i) as Int) & 0xFF`,
single-allocation output through `xiom.string.builder`
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
