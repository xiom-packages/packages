# xiom.xml2

> **Status:** `incubating` -- conformance-tested (24/24); published at `v0.1.0` on the XIOM registry.

Pure-XIOM **XML model** -- no FFI, no libxml2, no external dependencies beyond
`xiom.std`. This package replaces the old `xiom.xml2` placeholder (which
promised libxml2 bindings) with a self-contained XML toolkit: a strict parser
subset, a DOM tree over parallel vectors, a canonical serializer, scoped
namespace resolution and an XPath-LITE evaluator. Everything is implemented
in XIOM and covered by an inline conformance suite.

> **Scope.** This is a deliberately bounded XML subset for configuration,
> document and message payloads, not a validating XML processor. There is no
> DTD internal subset, no external entity loading, no XInclude, no full XPath
> 1.0 and no XML-DSig/canonicalization. The exact subset, the error catalog
> and the non-goals are specified in [SPEC.md](SPEC.md).

## Status

* Package `xiom.xml2` 0.1.0, module `xiom.xml2` (`src/xml2.xi`).
* Conformance suite: 24 checks, all fixtures inline
  (`tests/test_conformance.xi`). Run `.\scripts\port.ps1 -Package xiom-xml2`
  from the repository root.
* Latest harness line: `port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Implemented

* **Parser subset** (`xml2_parse`): elements, attributes (double or single
  quoted), character data, CDATA sections, comments, processing instructions
  (an XML declaration is stored as a PI named `xml`), and a DOCTYPE subset --
  `<!DOCTYPE name>`, `SYSTEM "lit"`, `PUBLIC "pub" "sys"`. An internal DTD
  subset (`[...]`) is rejected explicitly.
* **Entity decoding**: the five predefined entities (`&amp; &lt; &gt; &quot;
  &apos;`) plus `&#NN;` and `&#xHH;` numeric references, encoded to UTF-8
  (surrogates, NUL and values above U+10FFFF are invalid). Unknown, malformed
  and unterminated references are strict errors, not lenient pass-throughs.
* **Well-formedness errors with byte offsets**: bad names, stray `<`,
  unclosed/malformed tags and attribute values, duplicate attributes,
  mismatched/unexpected closing tags, text outside the root, multiple roots,
  unclosed comments/CDATA/PIs, malformed DOCTYPEs.
* **Bounded work**: 1 MiB input, depth 64, 16384 nodes, 256 attributes per
  element (constants `XML2_MAX_*`).
* **DOM tree over parallel vectors**: every node carries parent,
  first-child, last-child and next-sibling links (`xml2_parent`,
  `xml2_first_child`, `xml2_last_child`, `xml2_next_sibling`,
  `xml2_child_count`, `xml2_child_at`, `xml2_child_by_name`, `xml2_depth`).
  Node 0 is the synthetic document node; its child chain holds the
  document-level nodes (DOCTYPE, comments, PIs and the root element).
* **Node kinds**: `XML2_KIND_ELEMENT` 0, `XML2_KIND_TEXT` 1,
  `XML2_KIND_CDATA` 2, `XML2_KIND_COMMENT` 3, `XML2_KIND_PI` 4,
  `XML2_KIND_DOCTYPE` 5.
* **Text access**: `xml2_text` (direct text/CDATA children), `xml2_text_deep`
  (all descendant character data), `xml2_node_string` (scalar value of any
  kind), `xml2_node_raw_bytes` (verbatim source span).
* **Queries**: `xml2_find` / `xml2_find_first` (exact qualified name),
  `xml2_find_local` (namespace-agnostic local name), attribute accessors
  (`xml2_attr`, `xml2_attr_or`, `xml2_has_attr`, `xml2_attr_count`,
  `xml2_attr_name_at`, `xml2_attr_value_at`).
* **Serializer** (`xml2_serialize`, `xml2_serialize_node`): documented
  escaping (text: `&` `<` `>`; attributes: `&` `<` `"`), always
  double-quoted attributes, canonical attribute order (ascending byte order
  by name) and stable round trips. `xml2_escape_text` / `xml2_escape_attr`
  expose the escaping rules directly.
* **Namespaces**: prefix/local split (`xml2_qname_prefix` /
  `xml2_qname_local`), scoped resolution through `xmlns` /
  `xmlns:prefix` declarations (`xml2_ns_resolve`), element URIs
  (`xml2_ns_element_uri`), attribute URIs (`xml2_ns_attr_uri`), declaration
  listing (`xml2_ns_decl_count` / `xml2_ns_decl_prefix_at` /
  `xml2_ns_decl_uri_at`), the fixed `xml` prefix and unbound-prefix errors.
  Unprefixed attributes are in no namespace, per Namespaces in XML.
* **XPath-LITE** (`xml2_xpath_eval` plus the `xml2_xpath_nodes` /
  `xml2_xpath_first` / `xml2_xpath_count` / `xml2_xpath_string`
  convenience wrappers):
  * absolute (`/r/a/b`) and relative (`a/b`) child paths;
  * name tests: unprefixed matches the local name, `prefix:local` resolves
    the prefix and compares namespace URI and local name;
  * `@attr` steps (final step only) returning attribute values with their
    owner elements;
  * `text()` selecting text and CDATA children;
  * positional predicates `[n]` (1-based, applied per context node);
  * attribute equality predicates `[@a='v']` / `[@a="v"]`.
  Everything else -- `//`, `*`, `..`, `.`, unions, functions, comparisons
  other than attribute equality -- is a documented error or non-goal.

## Example

```xiom
use xiom.xml2;

let res = xml2_parse("<r xmlns:p=\"urn:p\"><p:a id=\"x1\"/><a id=\"x2\"/></r>");
if res.is_ok {
  let d = res.value;
  let n = xml2_xpath_first(&d, 0, "/r/p:a");       // element step
  let s = xml2_xpath_string(&d, 0, "/r/p:a/@id");  // "x1"
  let r = xml2_ns_element_uri(&d, 2);              // Ok("urn:p")
  let out = xml2_serialize(&d);
}
```

## Errors

Parse errors are `Err("xml2: ... at offset N")` where `N` is a byte offset
into the input. Namespace and XPath errors are `Err("xml2: ...")` without
offsets. See SPEC.md section 9 for the complete catalog.

## Limits (documented, enforced)

| Limit | Value | Constant |
|-------|-------|----------|
| Input size | 1 MiB | `XML2_MAX_INPUT` |
| Nesting depth | 64 | `XML2_MAX_DEPTH` |
| Nodes (incl. node 0) | 16384 | `XML2_MAX_NODES` |
| Attributes per element | 256 | `XML2_MAX_ATTRS` |

## Non-goals (summary)

No DTD internal subset or external entity resolution; no XML NameStartChar
validation beyond the documented byte rules; no character-encoding
conversion (UTF-8 bytes pass through); no namespace fixup on serialization;
no node editing; no full XPath 1.0; no canonicalization/XML-DSig. See
SPEC.md section 10.

## Testing

`.\scripts\port.ps1 -Package xiom-xml2` compiles the module and runs the
24-check inline suite. No files are read at test time; every fixture is a
string literal.
