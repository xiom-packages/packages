# xiom.xml

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** an XML subset parser with a flat node model, document queries,
> and escaping helpers.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string`,
> `xiom.string.builder` and `xiom.string.compare`). Tests additionally use
> `xiom.test` and `xiom.io`.

## What it is

`xiom.xml` parses a practical XML subset into a flat, allocation-friendly
node model and answers structural questions about it: `xml_root`, child
access, `xml_find` / `xml_find_first` / `xml_text_of`, and attribute lookup
with `xml_attr`. It never touches a C library: scanning is byte-wise over the
input `Str`, entities are decoded into a `Vec[UInt8]` builder, and every
public function is a free function.

Parsed documents are *flat*: nodes live in parallel vectors (`kinds`,
`names`, `texts`, `parents`) instead of a recursive tree, and attributes live
in a parallel association list (`attr_names`, `attr_values`, `attr_owners`).
This is the ecosystem pattern for XIOM v0.61.3, where `Vec[StructType]` is
unsupported.

## API

| Function | Returns | Description |
|---|---|---|
| `xml_parse(text)` | `Result[XmlDoc, Str]` | Parse a whole document; `Err("xml: ...")` on malformed input. |
| `xml_root(d)` | `Int` | First element child of the synthetic root; `-1` when none. |
| `xml_node_count(d)` | `Int` | Node count including the synthetic root (empty doc = 1). |
| `xml_kind(d, node)` | `Int` | `0` element, `1` text; `-1` when the node is out of range. |
| `xml_name(d, node)` | `Str` | Tag name; `""` for text nodes / out of range. |
| `xml_text(d, node)` | `Str` | Concatenated direct text children of `node`. |
| `xml_child_count(d, node)` | `Int` | Direct children (elements + text nodes). |
| `xml_child(d, node, index)` | `Option[Int]` | Child node by zero-based position; `None` out of range. |
| `xml_attr(d, node, name)` | `Option[Str]` | First attribute value with this name; `None` when missing. |
| `xml_find(d, tag)` | `Vec[Int]` | All element nodes with this tag, document order. |
| `xml_find_first(d, tag)` | `Option[Int]` | First element node with this tag. |
| `xml_text_of(d, tag)` | `Option[Str]` | `xml_text` of the first element with this tag. |
| `xml_escape(s)` | `Str` | Escape `& < > " '` as `&amp; &lt; &gt; &quot; &apos;`. |
| `xml_unescape(s)` | `Str` | Decode those named entities plus `&#NN;` / `&#xHH;`. |

Errors: single catalog of `Err("xml: ...")` strings (see SPEC.md); the three
most common are `xml: mismatched closing tag`, `xml: unclosed tag` and
`xml: stray '<'`.

## Usage

```xi
use xiom.xml;
use xiom.io;

fn main() -> Int {
  let res = xml_parse("<doc><item id=\"7\">hello</item></doc>");
  if !res.is_ok {
    io.println("parse error: " + res.error);
    return 1;
  }
  let d = res.value;
  let first = xml_find_first(&d, "item");
  match first {
    Some(node) => {
      io.println(xml_text(&d, node));            // hello
      let id = xml_attr(&d, node, "id");
      match id {
        Some(v) => { io.println("id=" + v); },   // id=7
        None => {},
      }
    },
    None => {},
  }
  io.println(xml_escape("a<b&c"));               // a&lt;b&amp;c
  return 0;
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.xml
```

Expected: the section-4 namespace check passes, 24 `[PASS]` lines, then
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No DTD / DOCTYPE and no CDATA.** Any `<!` construct other than a comment
  is rejected with `Err("xml: unsupported markup")`.
- **No namespaces.** `:` is an ordinary name byte; qualified names are not
  resolved and prefixes are not checked.
- **Entity subset.** Only `&amp; &lt; &gt; &quot; &apos;`, `&#NN;` and
  `&#xHH;` are decoded; unknown or malformed references (including bare `&`)
  stay verbatim. `&#0;` and codepoints above U+10FFFF stay verbatim too.
- **No document serialization.** The module parses, queries and escapes; it
  does not write XML back out.
- **Lenient names.** Tag/attribute names must be non-empty and must avoid
  whitespace and `<>/=`, but are not validated against the XML `Name`
  production.
- **Verbatim text.** Text between markup is preserved exactly (including
  whitespace) as one text node per run, so indentation shows up as text
  nodes; comments split text runs (`a<!--x-->b` = text `a` + text `b`).
- **One root element.** Non-whitespace text outside the root, and a second
  top-level element, are errors.
- **Duplicate attributes keep the first occurrence** (no error; matches
  `xml_attr`'s documented behavior).
- In-memory only: `xml_parse` consumes a whole `Str`; no streaming API, no
  UTF-8 validation of the input (bytes pass through, only markup bytes are
  interpreted).

See `SPEC.md` for the grammar subset, the full error catalog and the test
plan. License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
