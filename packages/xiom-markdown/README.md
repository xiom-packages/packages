# xiom.markdown

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** render a documented Markdown subset (blocks + inline) from a
> whole `Str` to an HTML `Str`.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string`,
> `xiom.string.builder` and `xiom.string.compare`). Tests additionally use
> `xiom.test` and `xiom.io`.

## What it is

`xiom.markdown` is a small, dependency-free Markdown-to-HTML renderer for
in-memory documents. It scans the input line by line for block constructs
(headings, paragraphs, lists, blockquotes, thematic breaks, fenced code) and
then scans each text run for the inline subset (`**bold**`, `*italic*`,
`` `code` ``, `[text](url)`). No C library is involved: the renderer is
byte-wise over the input `Str` and writes into `Vec[UInt8]` builders. Every
text run placed into HTML -- including inline-code content and link URLs --
passes through the same escaper, so `&`, `<`, `>` and `"` from the input can
never appear literally in the output.

The exact subset, the rendering tables, and every deliberate deviation are in
`SPEC.md`.

## API

| Function | Returns | Description |
|---|---|---|
| `markdown_to_html(md)` | `Str` | Render the block + inline subset to HTML. Blocks appear in document order separated by a single LF; empty/whitespace-only input renders `""`. |
| `markdown_escape(s)` | `Str` | Escape `&`, `<`, `>`, `"` as `&amp;`, `&lt;`, `&gt;`, `&quot;`; all other bytes pass through. |

## Rendering summary

| Input | Output |
|---|---|
| `# H` .. `###### H` | `<h1>H</h1>` .. `<h6>H</h6>` |
| paragraph lines (blank-line separated) | `<p>line1 line2</p>` (lines joined with one space) |
| `- a` / `* a` lines | `<ul>\n<li>a</li>\n<li>b</li>\n</ul>` |
| `1. a` lines (any digits) | `<ol>\n<li>a</li>\n<li>b</li>\n</ol>` |
| `> quote` lines | `<blockquote>\n<p>quote</p>\n</blockquote>` |
| `---` / `***` alone | `<hr>` |
| ` ```lang ` fenced block | `<pre><code class="language-lang">...</code></pre>` |
| ` ``` ` fenced block | `<pre><code>...</code></pre>` |
| `**b**`, `*i*`, `` `c` ``, `[t](u)` | `<strong>`, `<em>`, `<code>`, `<a href="u">t</a>` |

## Usage

```xi
use xiom.markdown;
use xiom.io;

fn main() -> Int {
  let html = markdown_to_html("# Title\n\nIntro **bold** and `code`.\n\n- one\n- two");
  io.println(html);
  // <h1>Title</h1>
  // <p>Intro <strong>bold</strong> and <code>code</code>.</p>
  // <ul>
  // <li>one</li>
  // <li>two</li>
  // </ul>
  io.println(markdown_escape("a < b & c"));   // a &lt; b &amp; c
  return 0;
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.markdown
```

Expected tail: 27 `[PASS]` lines, `xiom.markdown: all tests passed`, then
`port: PASS (passed=27 failed=0 program_exit=0 exit=0)`.

## Limitations

- Documented subset only: no images, no reference links, no link titles, no
  tables, no raw inline HTML, no setext headings, no nested lists, no list
  continuation lines.
- Emphasis does not nest: the body of a `**`/`*`/`` ` `` span is literal
  (escaped) text, never re-parsed; `**bold *and italic* text**` keeps the
  inner `*` markers literal.
- Line-based blocks: a blank line always ends a list/paragraph; list items
  are single-line; leading indentation is not significant.
- HTML escaping happens on emission, so markdown syntax is recognized on the
  raw input and there is no entity pass-through: an input `&amp;` becomes
  `&amp;amp;` in the output.
- No error channel: unrecognized syntax is treated as literal text.
- In-memory only: the whole document is one `Str`; no streaming API.

See `SPEC.md` for the grammar, the decision list, the rendering examples and
the test plan. License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
