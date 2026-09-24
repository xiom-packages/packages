# xiom.html

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** a tolerant HTML sanitizer: tag allowlist, href/title attribute
> policy, and script/style block removal.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string`,
> `xiom.string.builder` and `xiom.string.compare`). Tests additionally use
> `xiom.test` and `xiom.io`.

## What it is

`xiom.html` reduces untrusted HTML to a small, allowlisted subset in one
byte-wise pass: a caller-supplied tag allowlist decides which tags survive,
`script` and `style` elements are removed together with their content, and
kept tags are reduced to `href` and `title` attributes with `javascript:`
and `data:` hrefs dropped. Text, entities and stray `<` passes are preserved
verbatim.

The module never touches a C library: scanning is byte-wise over the input
`Str`, output bytes are collected in a `Vec[UInt8]` with
`xiom.string.builder`, and every public function is a free function.

The sanitizer is deliberately *tolerant*: it does not parse a DOM, does not
rebalance tags and does not decode entities (see `SPEC.md` for the exact
scanner rules and `Limitations` below).

## API

| Function | Returns | Description |
|---|---|---|
| `html_default_allowed_tags()` | `Vec[Str]` | The 21 default tags (`a`, `b`, `blockquote`, `br`, `code`, `em`, `h1`-`h6`, `hr`, `i`, `li`, `ol`, `p`, `pre`, `strong`, `u`, `ul`), lowercase and sorted. |
| `html_sanitize(input, allowed_tags)` | `Str` | Tolerant single-pass sanitizer; keeps only allowlisted tags with safe `href`/`title` attributes, drops script/style blocks with their content, comments and declarations. |
| `html_strip_tags(input)` | `Str` | `html_sanitize` with an empty allowlist: all tags and script/style content removed, text and entities kept. |
| `html_is_safe(input, allowed_tags)` | `Bool` | True when `html_sanitize(input, allowed_tags)` is byte-identical to `input` (not a safety verdict -- only a "nothing changed" check). |

Attribute policy (all functions): attribute names are matched
case-insensitively; only `href` and `title` survive, the first of each wins,
`on*` handlers and every other attribute are dropped, and an `href` whose
scheme (after lowercasing and tab/LF/CR stripping) is `javascript:` or
`data:` is dropped.

## Usage

```xi
use xiom.html;
use xiom.io;

fn main() -> Int {
  let tags = html_default_allowed_tags();
  let dirty = "<p onclick=\"x\">hi <script>evil()</script><a href=\"javascript:bad()\">l</a></p>";
  io.println(html_sanitize(dirty, &tags));   // <p>hi <a>l</a></p>
  io.println(html_strip_tags("<b>Hello</b> <i>world</i>"));  // Hello world
  if html_is_safe("<p>ok</p>", &tags) {
    io.println("clean");                     // clean
  }
  return 0;
}
```

`html_default_allowed_tags()` returns a fresh vector: push extra tags to
extend the allowlist, or start from `Vec[Str].new()` for an empty one.
`script` and `style` are never kept, even when listed.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.html
```

Expected: the section-4 namespace check passes, 22 `[PASS]` lines, then
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Tolerant, not rebalancing.** Tags are kept or dropped independently; the
  output is not guaranteed to be well-formed HTML and mismatched tags pass
  through. A stray `<` with no tag end passes through verbatim, so an
  unterminated tag fragment can re-form a tag if the output is later
  concatenated into a larger document -- only feed well-formed input, or
  treat the output as text, not as a document.
- **Allowlist-based, not a parser.** There is no DOM, no tokenizer state
  machine beyond the rules in `SPEC.md`, no namespace handling, no SVG/MathML
  awareness and no attribute-value canonicalization.
- **No CSS or full URL normalization.** `style` attributes and `<style>`
  blocks are removed, but URL values are not decoded, normalized or resolved:
  the only URL check is the `javascript:` / `data:` scheme prefix. An
  entity-encoded scheme (e.g. `&#106;avascript:`) is not detected.
- **No entity decoding.** Entities in text and attribute values are copied
  byte-for-byte (`&amp;` stays `&amp;`); raw `"` and `<` inside kept
  attribute values are re-encoded as `&quot;` / `&lt;` so the emitted
  quoting stays intact.
- **Unbalanced input.** A closing tag is emitted only when its name is
  allowlisted; there is no cross-check against the opening stack.
- **Byte-oriented.** Input is treated as bytes that pass through unchanged;
  no UTF-8 validation, normalization or case folding beyond ASCII.
- **Unclosed constructs run to EOF.** A comment (`<!--`), a raw-text block
  (`script`/`style`) or a dropped declaration without its terminator is
  dropped through end of input.
- **Duplicate attributes.** The first `href` and the first `title` win; later
  duplicates are ignored (a dangerous first `href` also suppresses later
  duplicates).

See `SPEC.md` for the scanner rules, attribute policy, dropped-block rules
and the test plan. License: MIT OR Apache-2.0 (see the repository root
`LICENSE`).
