# xiom.html -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.html`, version `0.1.0`).
Module: `src/html.xi` (`module xiom.html`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.builder`,
`xiom.string.compare`).

## Scope

A pure-XIOM (no FFI) tolerant HTML sanitizer:

- `html_default_allowed_tags` returns the default tag allowlist;
- `html_sanitize(input, allowed_tags)` performs one byte-wise pass that keeps
  allowlisted tags (reduced to `href`/`title`), drops everything else, and
  removes `script`/`style` blocks together with their content;
- `html_strip_tags(input)` is the same pass with an empty allowlist;
- `html_is_safe(input, allowed_tags)` reports whether sanitizing would change
  the input at all.

## Non-goals

- Full HTML parsing: no DOM, no tree building, no rebalancing, no error
  reporting (the API is infallible).
- CSS sanitization: `<style>` blocks and `style` attributes are dropped, not
  filtered or rewritten.
- URL resolution or normalization: only the `javascript:` / `data:` scheme
  prefix is checked; relative URLs, protocol-relative URLs, `vbscript:` and
  entity-encoded schemes are not interpreted.
- Entity decoding or re-encoding: entities are copied verbatim (except the
  minimal `"`/`<` re-encoding inside emitted attribute values, below).
- Namespaces (SVG/MathML), CDATA, template contents, character-set handling
  or UTF-8 validation; a byte is a byte.
- Streaming: the whole input `Str` is scanned into one output `Str`.

## Scanner rules (single pass)

The scanner walks the input once. Outside markup, each byte is copied to the
output verbatim; at every `<` it consumes one markup construct:

1. **Markup starts only after `<` followed by an ASCII letter, `/`, `!` or
   `?`.** Every other `<` (followed by space, a digit, `>`, EOF, ...) is
   emitted as text and scanning resumes at the next byte.
2. **Comment**: `<!--` is dropped through the first `-->`; without a
   terminator it is dropped to EOF.
3. **Declaration / processing instruction**: `<!` (other than a comment) and
   `<?` are dropped through the first `>` (not quote-aware); without a `>` the
   `<` is emitted as text (rule 6).
4. **Closing tag**: `</` + a letter scans the name to `>`; the tag is dropped
   unless the name is allowlisted, in which case `</name>` is emitted with an
   ASCII-lowercased name. A closing tag with a `<` in its body or no `>` is
   stray (rule 6).
5. **Opening tag**: `<` + a letter scans for the tag end, defined as the
   first `>` *outside* single- or double-quoted runs (so `title="a>b"` does
   not end the tag). If there is no such `>`, or a `<` occurs inside the tag
   body, the `<` is stray (rule 6). Otherwise the name is scanned (ending at
   whitespace, `/`, `>` or `<`) and:
   - `script` or `style` (case-insensitive) starts a dropped block
     (see "Dropped-block rules");
   - an allowlisted name is re-emitted as `<name ...>` (see "Attribute
     policy");
   - any other name is dropped entirely; its text content is kept (the
     scanner simply resumes after the tag's `>`).
   A `/` seen where an attribute would start marks the tag self-closing and
   is re-emitted as `/>`.
6. **Stray `<`**: when a tag-like construct cannot find its tag end, the `<`
   is emitted as text and scanning resumes with the following byte (so the
   remainder of the fragment is treated as text). This is the documented
   tolerant behavior; it also means an unterminated tag fragment passes
   through verbatim.

Comments, declarations, dropped tags and stray `<` never contribute to the
output; text bytes and entities are never modified.

## Attribute policy

While re-emitting an allowlisted opening tag:

- Attribute names are scanned to whitespace, `=`, `/`, `>` or `<` and matched
  case-insensitively against `href` and `title`; the canonical lowercase name
  is emitted.
- Values may be double-quoted, single-quoted or unquoted. Quoted values end
  at the matching quote (an unterminated quote ends at the tag end, which the
  quote-aware tag scan already prevents); unquoted values end at whitespace,
  `/`, `>` or `<`. A single- or double-quoted attribute without `=` is a
  valueless attribute and is dropped.
- Emitted values keep their bytes (entities included) except `"` -> `&quot;`
  and `<` -> `&lt;`, so the emitted double-quoted value cannot terminate the
  attribute or open markup.
- The **first** `href` and the **first** `title` win; later duplicates are
  ignored. A dropped (dangerous) first `href` also suppresses later `href`
  attributes.
- An `href` value is dropped when, after skipping leading whitespace and
  skipping tab/LF/CR anywhere, its ASCII-lowercased bytes start with
  `javascript:` or `data:`. Spaces inside the scheme are not skipped, so
  `java script:` does not match; an entity-encoded scheme does not match
  either (documented limitation).
- Every other attribute -- all `on*` handlers, `class`, `id`, `style`,
  `src`, `data-*`, ... -- is dropped, whether or not it has a value.

## Dropped-block rules

- An opening `script` or `style` tag (case-insensitive, any attributes,
  self-closing marker ignored) removes the tag and everything up to and
  including the next `</script`/`</style` (case-insensitive) followed by the
  next `>`; without that closing tag everything to EOF is removed.
- The rule is unconditional: `script` and `style` are removed even when a
  caller lists them in `allowed_tags`.
- `html_strip_tags` is `html_sanitize` with an empty allowlist, so it drops
  all tags but applies the same dropped-block rules.
- Comments (`<!-- -->`) and declarations/processing instructions (`<! ... >`,
  `<? ... >`) are dropped but their content is not otherwise treated as
  markup.

## API semantics

`html_default_allowed_tags()`
: A fresh `Vec[Str]` with exactly 21 lowercase, sorted tags: `a`, `b`,
  `blockquote`, `br`, `code`, `em`, `h1`, `h2`, `h3`, `h4`, `h5`, `h6`, `hr`,
  `i`, `li`, `ol`, `p`, `pre`, `strong`, `u`, `ul`. Callers own the vector.

`html_sanitize(input, allowed_tags)`
: The sanitized `Str`. `allowed_tags` is matched case-insensitively; an empty
  list drops every tag (equivalent to `html_strip_tags`). Never fails.

`html_strip_tags(input)`
: `html_sanitize(input, &empty)`.

`html_is_safe(input, allowed_tags)`
: `str_compare(html_sanitize(input, allowed_tags), input) == 0`. A false
  result means only that sanitizing changes something.

## Complexity

| Operation | Complexity |
|---|---|
| `html_sanitize` | O(input bytes) amortized (tag/comment scans are linear; allowlist checks are O(tags) per tag) |
| `html_strip_tags` | O(input bytes) |
| `html_is_safe` | O(input bytes) |
| `html_default_allowed_tags` | O(1) (21 pushes) |

## Test plan

`tests/test_conformance.xi` (`module html_tests`, 22 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line and
returns the failure count). Coverage:

1. allowed `p`/`b` pass through unchanged;
2. disallowed `div`/`span` stripped, text content kept, closed-only disallowed
   tag dropped;
3. script blocks dropped with their content (plain, nested in an allowed tag,
   and when `script` is explicitly allowlisted);
4. unterminated script block dropped to EOF; script with `src` dropped with
   content;
5. style blocks dropped with their content;
6. `onclick` / `onmouseover` dropped while a safe `href` on the same tag
   survives;
7. `class`, `id`, `style`, `data-*` dropped while `title` survives;
8. `javascript:` hrefs dropped (mixed case, leading whitespace);
9. `data:` hrefs dropped (mixed case);
10. safe `href` kept, entities in the value preserved;
11. `title` kept, including a `javascript:` title (only `href` is
    scheme-checked);
12. uppercase tag and attribute names normalized;
13. comments and `<!DOCTYPE>` dropped, including markup inside a comment and
    an unterminated comment;
14. self-closing `br`/`hr` kept, whitespace before `/` normalized;
15. nested allowlisted tags kept in place;
16. text and entities preserved verbatim;
17. stray `<` passes through (`1 < 2`, `a <3 b`, `x<p`, `a <> b`);
18. unbalanced tags pass through unchanged (no rebalancing);
19. `html_is_safe` true for clean input, false for dirty input, true for
    empty input; sanitize is idempotent for a dirty example;
20. `html_strip_tags` keeps text and entities, drops tags and script content;
21. empty input yields empty output for sanitize/strip/is_safe;
22. the default allowlist is exactly the 21 required tags, sorted, without
    `div`/`script`/`style`/`img`.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.html
```

Last verified: compiler 0.61.3,
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Tolerant by construction: no rebalancing, no DOM, no error channel; stray
  `<` and unterminated tags pass through verbatim.
- Allowlist only: anything not listed (including `img`, `span`, `div`, tables
  and lists other than `ul`/`ol`/`li`) loses its tag while its text survives.
- URLs are not decoded or normalized; only the `javascript:`/`data:` prefix
  check is applied and entity-encoded schemes defeat it.
- Attribute values are not CSS- or URL-sanitized; `style`/`src` attributes
  are simply dropped.
- Entities are never decoded, so comparisons against entity-encoded payloads
  are not possible; kept values may therefore still contain entities.
- Raw `"` and `<` in kept values are re-encoded as `&quot;`/`&lt;` (the only
  bytes this module rewrites); all other bytes are copied.
- First-attribute-wins duplicates; self-closing markers on non-void tags are
  preserved as `/>` without semantics.
- No UTF-8 validation: multi-byte sequences pass through byte-exact.
- No streaming API; one `Str` in, one `Str` out.

## Compiler / stdlib notes for v0.61.3

- Free functions only; no methods, no closures, no `Vec[StructType]`.
- All byte predicates work in `Int` space (`(byte as Int) & 0xFF`) and cast
  back with `as UInt8` on pushes, so no direct comparison of `byte_at`
  against `UInt8` constants at or above `0x80` is needed.
- All `Str` comparisons go through `xiom.string.compare.str_compare`
  (BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
  pointer comparison).
- Output bytes are materialized once per result with
  `xiom.string.builder.sb_to_str`; the package declares no `extern "C"`
  blocks (no FFI).
- The scanner always advances (`_scan_markup` returns an index greater than
  the `<` it consumed), so the single loop cannot stall.
