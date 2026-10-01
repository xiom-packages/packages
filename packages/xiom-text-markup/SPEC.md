# xiom.text-markup -- Specification

Version: 0.1.0 (incubating, not yet published).
Module: `xiom.text_markup` (`src/text_markup.xi`). Pure XIOM, no FFI, no IO,
no `Vec[StructType]`, no closures, no fn-pointer values, no `Vec[Str]`.

## 1. Scope

A deterministic codec for the inline half of BBCode-style markup:

- five tags -- `[b]`, `[i]`, `[u]`, `[code]`, `[url=target]` (bare `[url]` is
  also valid);
- proper-nesting validation with an exact error catalog;
- text escapes `\[`, `\]`, `\\` and the named entities `&amp;`, `&lt;`,
  `&gt;`, `&quot;`;
- span records over the source text (tag code, open span, close span,
  attribute span);
- a plain-text renderer (tags stripped, escapes and entities decoded, code
  content verbatim);
- a canonical re-serializer that is idempotent and reparse-stable.

## 2. Non-goals

- Block structure (paragraphs, lists, headings, tables): see `xiom.markdown`.
- HTML output: this package emits spans and text, never HTML.
- Tag aliases, case folding or configurable tag sets: the five names are
  exact and lowercase.
- Entities beyond the four named ones, numeric character references and
  re-encoding on output.
- Error recovery: the first error aborts, no partial records are returned.
- Streaming/resumable parsing; the whole document is parsed in one call.

## 3. Tag grammar

```
document   := item*
item       := open | close | text | escape | entity | code-block
open       := '[' name ( '=' attr )? ']'
close      := '[' '/' name ']'
name       := 'b' | 'i' | 'u' | 'code' | 'url'
attr       := any bytes up to the first ']' (at least one byte)
code-block := '[code]' literal* '[/code]'
literal    := any bytes; the first '[/code]' ends the block
escape     := '\' ( '[' | ']' | '\' )
entity     := '&amp;' | '&lt;' | '&gt;' | '&quot;'
text       := any other byte
```

Rules:

- Tag names are matched byte-exactly and case-sensitively; `[B]` is unknown.
- An open tag's name ends at the first `=` (if any) or at `]`. The attribute
  value begins after that `=` and ends at the first `]`; it must be non-empty.
- Only `url` may carry an attribute. `[url]` without `=` is valid and has no
  attribute. A close tag's whole body after `/` is its name, so `[/b=x]` is
  the unknown tag `b=x`.
- The first `]` after `[` terminates the tag; a `[` with no `]` before end of
  input is `unterminated tag`.
- Inside `[code] ... [/code]` nothing is interpreted: tags do not nest, and
  escapes and entities are literal. The block ends at the first byte-exact
  `[/code]`.
- Text bytes outside tags are literal except for the escapes and entities
  above; `\[`, `\]` and `\\` are the only valid escapes.

## 4. Nesting

`markup_parse` keeps a stack of open tags (parallel `Vec[Int]` stacks for the
tag codes and their record indices):

1. An open tag pushes a record with placeholder close positions.
2. A close tag must match the innermost open tag exactly: it pops the stack
   and fills the record's close span. `close_order` records the record indices
   in closing order (ascending close positions).
3. A close tag whose name is not on the stack at all is `stray close tag`.
4. A close tag whose name is on the stack but not at the top is
   `cross-nested tags`, reporting the innermost open name and the close name.
5. At end of input any tag still on the stack is `unclosed tag`, reporting the
   innermost (last opened) tag at its open-tag position.

A successful parse guarantees the stack is empty and every record has a close
span with `open_start <= open_end <= close_start <= close_end`.

## 5. Values

```
Markup = { tags: Vec[Int]; open_starts: Vec[Int]; open_ends: Vec[Int];
           close_starts: Vec[Int]; close_ends: Vec[Int];
           attr_starts: Vec[Int]; attr_ends: Vec[Int];
           close_order: Vec[Int] }
```

Record `i` (parallel index across the first seven vectors):

| Field | Meaning |
|---|---|
| `tags[i]` | `MARKUP_TAG_*` code (1..5). |
| `open_starts[i]` / `open_ends[i]` | Byte span of the opening tag (`[b]`), end exclusive. |
| `close_starts[i]` / `close_ends[i]` | Byte span of the closing tag (`[/b]`), end exclusive. |
| `attr_starts[i]` / `attr_ends[i]` | Raw attribute-value byte span, or `-1`/`-1` when absent. |
| `close_order[k]` | Record index of the k-th closing tag in source order. |

Tag codes: `MARKUP_TAG_NONE=0`, `B=1`, `I=2`, `U=3`, `CODE=4`, `URL=5`.
Accessors are range-safe with defaults (`NONE`, `-1`, `""`).

## 6. Rendering

Both renderers walk the source once, merging open events (`open_starts`,
ascending) with close events (reached through `close_order`, also ascending).
At an event the tag span is skipped (plain) or re-emitted (canonical); between
events a text run is emitted; inside a code span (set at its open event, cleared
at its close event) runs are copied byte-for-byte.

Plain text (`markup_to_plain`):

| Input | Output |
|---|---|
| any tag | nothing |
| `\[` / `\]` / `\\` | `[` / `]` / `\` |
| `&amp;` / `&lt;` / `&gt;` / `&quot;` | `&` / `<` / `>` / `"` |
| any other byte | itself |
| bytes inside `[code]` | themselves (verbatim) |

Canonical text (`markup_to_canonical`): decode escapes and entities exactly as
for plain text, then re-escape `[`, `]` and `\` with a backslash and emit every
other byte (including `& < > "`) bare. Open tags are re-emitted as
`[name]` / `[name=attr]` with the attribute bytes verbatim; close tags as
`[/name]`; code content is copied verbatim. Consequences:

- canonical form is idempotent: `canonical(canonical(s)) == canonical(s)`;
- reparsing canonical form yields the same records and the same plain text;
- `&amp;` normalizes to `&`, while `\[` stays `\[`.

## 7. Error catalog (exact messages)

Positions `P` are 0-based byte offsets.

| Message | Condition | `P` |
|---|---|---|
| `markup: unterminated tag at P` | `[` with no `]` before EOF | the `[` |
| `markup: unknown tag '<name>' at P` | name not in `b i u code url` (case-sensitive; `""` included) | the `[` |
| `markup: bad attribute for '<tag>' at P` | attribute on `b/i/u/code`, or empty `url` attribute | the `[` |
| `markup: invalid escape at P` | `\` before none of `[ ] \` | the `\` |
| `markup: stray close tag '<name>' at P` | close with no matching open on the stack | the `[` |
| `markup: cross-nested tags '<open>' and '<close>' at P` | close matches an open that is not the innermost | the `[` |
| `markup: unclosed tag '<name>' at P` | open still on the stack at EOF | the innermost open `[` |

## 8. Complexity and totality

- `markup_parse`: O(n) bytes; a mismatched close searches the stack, so
  O(n * spans) worst case. Every loop makes progress (each iteration consumes
  at least one byte or closes a tag).
- `markup_to_plain` / `markup_to_canonical`: O(n) bytes plus O(spans).
- Accessors: O(1) except the two source-slice accessors, O(span length).
- No traps: all byte reads are bounds-checked before `xiom.string.byte_at`,
  all record accessors clamp, and `str_slice` clamps its range.

## 9. Conformance plan (26 checks, `tests/test_conformance.xi`)

| Group | Checks |
|---|---|
| Structure | simple tag, `[b][i]` nesting, `[u]` around `[b]`, sibling spans |
| Code | literal content (`a[0] &amp; b`), tag-looking bytes kept verbatim |
| URL | `[url=target]` attribute span, bare `[url]`, first `=` splits the value |
| Escapes/entities | `\[ \] \\`, the four entities, unknown entity pass-through |
| Errors | unclosed, cross-nested, stray close, unknown tag, bad attribute, unterminated, invalid escape |
| Rendering | plain text, canonical identity/idempotence, entity normalization |
| API | range-safe accessors, tag names/codes, `markup_is_valid`, convenience wrappers, determinism |
