# xiom.xml -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.xml`, version `0.1.0`).
Module: `src/xml.xi` (`module xiom.xml`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.builder`,
`xiom.string.compare`).

## Scope

A pure-XIOM (no FFI) XML parser for a documented subset, plus read-only
document queries and escaping helpers:

- `xml_parse` builds a flat node model (`XmlDoc`) from a whole `Str`;
- queries: root, node count/kind/name, direct text, child count/child by
  index, attribute lookup, tag search (`xml_find`, `xml_find_first`,
  `xml_text_of`);
- `xml_escape` / `xml_unescape` for the predefined entities and numeric
  character references;
- a deterministic `Err("xml: ...")` catalog for malformed input.

## Non-goals

- DTDs, `DOCTYPE` declarations, external/internal entities, parameter
  entities, entity declarations.
- XML namespaces (prefixes are not resolved; `:` is an ordinary name byte).
- CDATA sections (rejected as unsupported markup).
- Processing-instruction semantics: `<?...?>` is skipped wholesale; the
  `<?xml ... ?>` declaration is the expected use.
- Document serialization / pretty-printing (parse + query + escape only).
- Streaming / incremental parsing; validation against a schema; xml:base /
  xml:lang / xml:space semantics.
- Full XML `Name` production validation (names are checked only for
  non-emptiness and delimiter boundaries).
- UTF-16 input, BOM handling, and Unicode normalization.

## Grammar subset

Informal EBNF over bytes; `WS` is space, tab, CR or LF:

```
document   = prolog content* element content* EOF            (see below)
prolog     = ( WS | comment | pi )*
comment    = "<!--" ... "-->"                                 (non-nested)
pi         = "<?" ... "?>"                                    (skipped)
element    = start_tag | self_closing_tag
start_tag  = "<" name ( WS attr )* WS? ">"
self_close = "<" name ( WS attr )* WS? "/>"
end_tag    = "</" name WS? ">"
attr       = name WS? "=" WS? ( '"' [^"]* '"' | "'" [^']* "'" )
text       = ( [^<&] | entity )+                              (one node per run)
entity     = "&amp;" | "&lt;" | "&gt;" | "&quot;" | "&apos;"
           | "&#" digits ";" | "&#x" hexdigits ";" | "&#X" hexdigits ";"
```

Document-level rules:

- content at depth 0 is `WS | comment | pi | element`; non-whitespace text
  and a second element are errors;
- inside an element, every byte run up to the next `<` becomes one text
  node (after entity decoding), including whitespace-only runs;
- entity decoding applies in text nodes and attribute values; unknown,
  malformed or unterminated references contribute a literal `&` and scanning
  continues (no error);
- numeric references decode UTF-8 code points `1..0x10FFFF`; `&#0;` and
  out-of-range values stay verbatim;
- tag names are non-empty byte runs excluding `WS`, `<`, `>`, `/`, `=`; the
  same rule applies to attribute names;
- attribute values must be quoted (double or single quotes); there is no
  unquoted-value form and no attribute-value normalization beyond entity
  decoding;
- `</name>` must match the innermost open element exactly (byte comparison);
- comments and processing instructions may appear wherever markup is
  allowed (text positions split the text run).

## Node model

`XmlDoc` is flat; node 0 is always the synthetic document root (element,
empty name, parent `-1`). Every element and every text run appends one node
in document order; a node's children always have higher indices than the
node itself.

| Field | Meaning |
|---|---|
| `kinds[i]` | `0` = element, `1` = text node. |
| `names[i]` | Element tag name; `""` for text nodes (and the root). |
| `texts[i]` | Text node content (decoded); `""` for elements. |
| `parents[i]` | Owning node index; `-1` only for node 0. |
| `attr_names[k]` | Attribute name of flat attribute `k`. |
| `attr_values[k]` | Decoded attribute value of flat attribute `k`. |
| `attr_owners[k]` | Node index owning attribute `k`. |

Consequences: `xml_text(d, node)` concatenates `texts[i]` over direct text
children, so it is `""` for a text node itself (read `texts[i]` directly for
a text node's own content); `xml_child` counts elements and text nodes;
`xml_child_count` includes text nodes.

## API semantics

`xml_parse(text)`
: `Ok(doc)`: node 0 is the synthetic root; the root element (if any) is a
  child of node 0. `Err(msg)`: the first malformed construct, with `msg`
  from the catalog below.

`xml_root(d)`
: `-1` when the document has no element at depth 0 (empty, whitespace-only
  or comment-only documents).

`xml_kind(d, node)`
: `0`/`1` for valid indices, `-1` when `node < 0` or out of range.

`xml_name(d, node)`
: `""` for text nodes, the synthetic root and out-of-range indices.

`xml_text(d, node)`
: Direct text children only, in document order; `""` for out-of-range
  indices, text nodes and elements without text children. Nested element
  text is not included.

`xml_child_count(d, node)` / `xml_child(d, node, index)`
: Counts/returns direct children of any kind. `xml_child` returns `None` for
  negative or out-of-range indices and for any node index that has no such
  child.

`xml_attr(d, node, name)`
: `Some(value)` for the first attribute whose name compares byte-equal to
  `name`; `None` otherwise. Duplicate names keep the first. Attribute lists
  of text nodes are always empty.

`xml_find` / `xml_find_first`
: Element nodes only (text nodes never match; the synthetic root's empty
  name is not special-cased). Byte-exact, case-sensitive comparison.

`xml_text_of(d, tag)`
: `Some(xml_text(d, first match))` — `Some("")` is possible; `None` when no
  element matches.

`xml_escape(s)`
: `&`, `<`, `>`, `"`, `'` become named entities; all other bytes (including
  UTF-8 sequences) pass through.

`xml_unescape(s)`
: The inverse decoding (as `xml_parse` performs in text/attribute values):
  named entities, `&#NN;`, `&#xHH;` / `&#XHH;`; unknown or malformed
  references pass through verbatim. `xml_unescape(xml_escape(s)) == s`.

## Error string catalog

All errors are `Err("xml: ...")`.

| Condition | Error text |
|---|---|
| `<` followed by a byte that cannot start a tag name (WS, `=`, `>`, EOF...) | `xml: stray '<'` |
| EOF with open elements, or EOF inside a tag / after `<` | `xml: unclosed tag` |
| Quoted attribute value runs to EOF | `xml: unclosed attribute value` |
| `<!--` without `-->` | `xml: unclosed comment` |
| `<?` without `?>` | `xml: unclosed processing instruction` |
| `<!` not starting a comment (DOCTYPE, CDATA, ...) | `xml: unsupported markup` |
| `/` without `>` after a self-closing marker, or junk before `>` in a close tag | `xml: malformed tag` |
| Attribute name missing `=`, or unquoted attribute value | `xml: malformed attribute` |
| `</b>` closing an open `<a>` | `xml: mismatched closing tag` |
| `</b>` with no open element | `xml: unexpected closing tag` |
| Non-whitespace text at document level | `xml: text outside root element` |
| Second element at document level | `xml: multiple root elements` |

## Complexity

| Operation | Complexity |
|---|---|
| `xml_parse` | O(n) over the document bytes (amortized; entity decoding is linear) |
| `xml_root` / `xml_find` / `xml_find_first` / `xml_text` / `xml_child_count` / `xml_child` | O(nodes), plus text bytes for `xml_text` |
| `xml_kind` / `xml_name` / `xml_node_count` | O(1) |
| `xml_attr` | O(attributes) |
| `xml_escape` / `xml_unescape` | O(s.len()) |

## Test plan

`tests/test_conformance.xi` (`module xml_tests`, 24 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Coverage:

1. single element: root index, kinds, name, text, node count;
2. attributes with double and single quotes (plus missing attribute `None`);
3. nested elements: child indices, parents, child counts, out-of-range child;
4. text nodes as children, `texts[]` content and `xml_text` concatenation;
5. self-closing tags as childless elements (with attributes);
6. `<?xml ... ?>` declaration and comments (including markup inside a
   comment) are skipped;
7. entity decoding: named, decimal and hex; bare `&` and unknown names stay
   literal;
8. `xml_escape` output and full `xml_unescape(xml_escape(s))` round-trip;
9. `xml_find`: multiple matches in document order, single match, no match;
10. `xml_find_first`: first match and `None`;
11. `xml_text_of`: first match, empty text, `None`, comment-split text;
12. `Err("xml: mismatched closing tag")` for `</b>` closing `<a>`;
13. `Err("xml: unclosed tag")` for EOF with open elements / inside a tag;
14. `Err("xml: stray '<'")` for `<` followed by space, `<` or `>`;
15. empty input: one node (synthetic root), no children, no text;
16. `xml_root == -1` for empty / whitespace-only / comment-only documents;
17. `xml_attr` `None` cases (other name, empty name, text node, out of range)
    and first-of-duplicates;
18. out-of-range accessors: `xml_kind == -1`, `xml_name == ""`, empty text,
    0 children, `None` children;
19. `Err("xml: text outside root element")` (before/after root, entity-only);
    whitespace around the root is accepted;
20. `Err("xml: multiple root elements")`;
21. unclosed comment, DOCTYPE, CDATA and unclosed PI errors; a closed PI is
    skipped (`<?pi data?><a/>` parses);
22. whitespace/newline preservation inside elements and whitespace text
    nodes between children;
23. attribute values decode predefined and numeric entities with both quote
    styles;
24. `Err("xml: unclosed attribute value")` and
    `Err("xml: malformed attribute")` for unquoted / `=`-less attributes;
    adjacent attributes parse.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.xml
```

Last verified: compiler 0.61.3,
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Known limitations

- No DTD/DOCTYPE, CDATA, namespaces, schema validation or entity
  declarations; `<!` non-comment markup is a hard error.
- Names are only checked for emptiness/delimiters, not for the XML `Name`
  production.
- Text nodes preserve whitespace verbatim (no `xml:space` handling); a
  comment splits a text run into two nodes.
- One root element; non-whitespace text outside it is an error.
- Unknown/malformed entity references are passed through verbatim rather
  than rejected; `&#0;` and `> U+10FFFF` are not decoded.
- Duplicate attributes are accepted and `xml_attr` returns the first.
- No serialization API; no streaming; input UTF-8 is not validated.
- `xml_parse` builds all nodes in memory (no SAX-style callbacks).

## Compiler / stdlib notes for v0.61.3

- The document is a flat node list (parallel `Vec` fields) because
  `Vec[StructType]` is unsupported in this compiler.
- `Ok`/`Err` for `Result[XmlDoc, Str]` are constructed only in the leaf
  helpers `_ok_doc`/`_err_doc` (constructing Results directly elsewhere
  miscompiles in this compiler).
- All Str equality uses `xiom.string.compare.str_compare` (BUG 17: `==` on
  Str values read from `Vec[Str]` elements lowers to a pointer comparison).
- Str materialization from bytes uses the stdlib
  `xiom.string.builder.sb_to_str` (single allocation, ownership transfer);
  the package declares no `extern "C"` blocks (no FFI).
- The parse loop sets a failure flag + message and stops at the first error
  (`_fail`), so there is exactly one `Err` construction site reachable from
  the loop.
