# xiom.markdown -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.markdown`, version `0.1.0`).
Module: `src/markdown.xi` (`module xiom.markdown`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.builder`,
`xiom.string.compare`).

## 1. Scope

A pure-XIOM (no FFI) renderer for a documented Markdown subset:

- `markdown_to_html(md)` -- line-based block scan plus an inline scan of the
  text runs, producing HTML;
- `markdown_escape(s)` -- the HTML text escaper used on every emitted text
  run.

The API is infallible: there is no `Result` channel, and text that opens no
recognized construct is rendered literally (escaped).

## 2. Non-goals

- Images (`![alt](url)`), reference links, link titles, autolinks.
- Tables, footnotes, definition lists, task lists.
- Raw inline HTML or HTML blocks (input `<` is always escaped).
- Setext headings (`===` / `---` underlines; `---` alone is `<hr>`).
- Nested lists, list continuation lines, loose/tight list semantics,
  `start` attributes (the ordered-list number is ignored).
- Emphasis nesting (`***x***`, `**a *b* c**` bodies stay literal).
- Entity pass-through (`&amp;` in the input becomes `&amp;amp;`).
- Backslash escapes, hard line breaks, code-fence attributes beyond an
  optional language token, streaming/incremental rendering.

## 3. Block grammar

Input is split on LF; one trailing CR per line is dropped, so CRLF input
behaves like LF input. A trailing LF adds no empty last line; empty input has
zero lines. Each line is classified in this order (the first match wins):

| # | Construct | Recognized when | Rendering |
|---|---|---|---|
| 1 | blank | `str_trim(line) == ""` | skipped |
| 2 | fenced code | line starts with ` ``` ` | `<pre><code[ class="language-X"]>BODY</code></pre>` |
| 3 | heading | 1..6 `#` then a space or end of line | `<h1>`..`<h6>` |
| 4 | thematic break | `line` (right-trimmed) is `---` or `***` | `<hr>` |
| 5 | blockquote | first byte is `>` | `<blockquote>...</blockquote>` |
| 6 | bullet list | `-` or `*`, alone or before a space | `<ul>` with one `<li>` per line |
| 7 | ordered list | digits then `.`, alone or before a space | `<ol>` with one `<li>` per line |
| 8 | paragraph | anything else | `<p>...</p>` |

Block decisions in detail:

1. **Blank lines** separate blocks and produce no output.
2. **Fenced code.** The opening line starts with three backticks. The
   language is the first whitespace-delimited token after them (trimmed, may
   be empty); the rest of the opening line is ignored. Body lines follow
   until a line whose right-trimmed form is exactly ` ``` `; the body is
   joined with LF and escaped. A fence left open at EOF is closed leniently:
   the remaining lines form the body. An empty body renders as
   `<pre><code></code></pre>`.
3. **Headings.** 1..6 `#` followed by a space or end of line. The heading
   text is the remainder, trimmed; bare hashes produce an empty heading
   (`##` -> `<h2></h2>`). Seven or more hashes, or `#` without a following
   space, is a paragraph.
4. **Thematic breaks.** The line, after dropping trailing spaces/tabs, is
   exactly `---` or `***`; `- - -` and `****` are paragraphs.
5. **Blockquotes.** One or more contiguous lines whose first byte is `>`.
   The marker is `> ` (two bytes, one space) or `>`; the rest is the content.
   Contents are joined with LF and rendered recursively as a document, so
   inner headings/lists/code work. Empty inner HTML renders
   `<blockquote></blockquote>`, otherwise `<blockquote>\nINNER\n</blockquote>`.
6. **Bullet lists.** Contiguous `- `/`* ` lines (a lone `-` or `*` is an
   empty item). Each item's text is the remainder after the marker. A
   non-item line ends the list; a blank line then starts a new list.
7. **Ordered lists.** Contiguous lines of digits followed by `.` and either
   a space or end of line. Any digit count is accepted and the number is
   ignored (no `start` attribute, no `<li value=...>`). A lone `1.` is an
   empty item.
8. **Paragraphs.** Maximal runs of lines that are none of the above,
   joined with a single space before inline rendering.

Rendering of multi-line containers uses one LF per line inside the tag:

```
<ul>
<li>one</li>
<li>two</li>
</ul>
```

Consecutive blocks are joined with exactly one `\n`; there is no trailing
newline.

## 4. Inline rules

Applied to heading text, paragraph text, list-item text and the link label
(not to code-fence bodies or code spans, which are literal). Scanning is
left-to-right; a construct that does not open emits its first byte literally
and the scan continues.

| Construct | Recognized when | Rendering |
|---|---|---|
| code span | `` ` `` with a later `` ` `` | `<code>ESCAPED</code>` |
| strong | `**` with a later `**` | `<strong>ESCAPED</strong>` |
| emphasis | `*` with a later `*` (non-empty) | `<em>ESCAPED</em>` |
| link | `[` ... `](` ... `)` | `<a href="URL-ESCAPED">LABEL-INLINE</a>` |

- **No nesting.** The body of a strong/emphasis/code span is escaped literal
  text, never re-parsed. `**bold *and italic* text**` renders
  `<strong>bold *and italic* text</strong>`.
- **Matching is greedy-left.** `**a** and **b**` renders two strong spans.
  Lone or unbalanced markers stay literal (`a * b` has no emphasis).
- **Links.** From `[`, the scanner needs a later `](` and then a `)`. The URL
  is everything between `](` and that `)`; the label is parsed inline
  recursively. Missing `](` or `)` leaves `[` literal. An empty URL is
  allowed (`[x]()` -> `<a href="">x</a>`).
- **Escaping.** Every emitted text run goes through `markdown_escape`:
  `&` -> `&amp;`, `<` -> `&lt;`, `>` -> `&gt;`, `"` -> `&quot;`. Other bytes,
  including UTF-8 sequences, pass through byte-exact. `'` is not escaped.
  Inline-code content is escaped the same way; URLs are escaped into the
  `href` attribute with the same function.

## 5. Rendering examples

| Input | Output |
|---|---|
| `# Title` | `<h1>Title</h1>` |
| `###### Six` | `<h6>Six</h6>` |
| `####### Seven` | `<p>####### Seven</p>` |
| `a\nb` | `<p>a b</p>` |
| `**bold** text` | `<p><strong>bold</strong> text</p>` |
| `*italic*` | `<p><em>italic</em></p>` |
| `` `a < b` `` | `<p><code>a &lt; b</code></p>` |
| `[A & B](x?a=1&b=2)` | `<p><a href="x?a=1&amp;b=2">A &amp; B</a></p>` |
| `[q]("x")` | `<p><a href="&quot;x&quot;">q</a></p>` |
| `- a\n- b` | `<ul>\n<li>a</li>\n<li>b</li>\n</ul>` |
| `1. one\n10. ten` | `<ol>\n<li>one</li>\n<li>ten</li>\n</ol>` |
| bullet item with inline markup: `- **a** and CODE` (CODE = backticked `b`) | `<ul>\n<li><strong>a</strong> and <code>b</code></li>\n</ul>` |
| `> quoted` | `<blockquote>\n<p>quoted</p>\n</blockquote>` |
| `> - a\n> - b` | `<blockquote>\n<ul>\n<li>a</li>\n<li>b</li>\n</ul>\n</blockquote>` |
| `---` | `<hr>` |
| `` ```rust\nfn main() {}\n``` `` | `<pre><code class="language-rust">fn main() {}</code></pre>` |
| `` ```\na < b\n``` `` | `<pre><code>a &lt; b</code></pre>` |
| `""` | `""` |
| `"**bold *and italic* text**"` | `<p><strong>bold *and italic* text</strong></p>` |

Full document (`\n` shown as line breaks):

````
# Title

Intro **bold** and `code`.

> quoted

---

```xi
let x = 1 < 2;
```
````

renders to

```
<h1>Title</h1>
<p>Intro <strong>bold</strong> and <code>code</code>.</p>
<blockquote>
<p>quoted</p>
</blockquote>
<hr>
<pre><code class="language-xi">let x = 1 &lt; 2;</code></pre>
```

## 6. API signatures

```xi
pub fn markdown_to_html(md: Str) -> Str
pub fn markdown_escape(s: Str) -> Str
```

Complexity: the block scan is O(n) over the input bytes; inline scanning is
O(m^2) worst case over a text run of length m (non-nesting, greedy matching);
escaping is O(s.len()).

## 7. Test plan

`tests/test_conformance.xi` (`module markdown_tests`, 27 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Coverage:

| # | Check | Semantics pinned |
|---|---|---|
| t1-t6 | heading levels | `#` .. `######` produce `<h1>` .. `<h6>` |
| t7 | heading edge cases | 7+ hashes and `#x` are paragraphs; `##` is `<h2></h2>` |
| t8 | plain paragraph | single line becomes `<p>` |
| t9 | paragraph joining/splitting | lines join with a space; blank line splits |
| t10 | bold | `**x**` -> `<strong>x</strong>`, repeated spans |
| t11 | italic | `*x*` -> `<em>x</em>`, mid-text span |
| t12 | code span | `` `x + y` `` -> `<code>` |
| t13 | inline escaping | code content and plain text escape `& < > "` |
| t14 | links | URL attribute escaping, `"` escaping, inline label parsing |
| t15 | bullet lists | `-` and `*` items, list ended by a paragraph |
| t16 | ordered lists | multi-digit markers, start number ignored |
| t17 | blockquotes | single line, joined lines, inner list |
| t18 | thematic breaks | `---`, `***`, and between paragraphs |
| t19 | fenced code, tagged | `class="language-rust"` |
| t20 | fenced code, untagged | escaping, multi-line body, lenient EOF close |
| t21 | `markdown_escape` | four metacharacters, empty and plain input |
| t22 | mixed document | every block type in one document |
| t23 | empty input | empty / blank-line / spaces-only render `""` |
| t24 | list item inline | strong, code, link and emphasis inside items |
| t25 | no nesting | `**bold *and italic* text**` keeps inner markers literal |
| t26 | headings + separators | inline markup in a heading; single-LF block join |
| t27 | CRLF input | CRLF parses like LF |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison).

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.markdown
```

Last verified: compiler 0.61.3,
`port: PASS (passed=27 failed=0 program_exit=0 exit=0)`.

## 8. Known limitations

- The subset is fixed and small; anything unrecognized is rendered as
  literal escaped text, never as an error.
- No emphasis nesting; span bodies are literal text.
- No images, reference links, link titles, tables, raw HTML, setext
  headings, nested lists, list continuation lines or task lists.
- Ordered-list numbers are ignored; `start` is not emitted.
- A blank line always ends a list and a paragraph; items are single-line.
- No entity pass-through: `&amp;` in the input becomes `&amp;amp;` (the
  escaper runs on emission, so markdown syntax is recognized on raw input).
- `'` is not escaped (double-quoted attributes only).
- Fenced-code info strings: only the first whitespace-delimited token is
  used; a longer info string is otherwise ignored.
- `markdown_to_html` consumes a whole `Str`; no streaming API.

## 9. Compiler / stdlib notes for v0.61.3

- Block markers are classified byte-wise with `xiom.string.byte_at` and
  ASCII `UInt8` constants; digit ranges are compared after an `as Int` cast.
- All Str equality goes through `xiom.string.compare.str_compare` (BUG 17:
  `==` on Str values read from `Vec[Str]` elements lowers to a pointer
  comparison); `_starts_with` compares bytes directly.
- Renderers build `Vec[UInt8]` and materialize with
  `xiom.string.builder.sb_to_str` (one allocation per Str).
- No `Vec[StructType]`, no `match` on new types, no inline lambdas, no
  `Result`/`Option` returns, free functions only.
- The package declares no `extern "C"` blocks (no FFI).
