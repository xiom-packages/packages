# xiom.xml2 -- specification

Package `xiom.xml2`, version 0.1.0, module `xiom.xml2` (`src/xml2.xi`).
Pure XIOM; depends only on `xiom.std`. This document is the precise
definition of the supported subset, the canonicalization rules, the error
catalog and the non-goals. Where this document and the code disagree, this
document is the bug report.

---

## 1. Position and model

`xiom.xml2` is a bounded, non-validating XML processor for configuration,
document and message payloads. It parses a document into an immutable DOM
made of parallel vectors, serializes it canonically, resolves namespaces
and evaluates an XPath-LITE subset. There is no FFI and no libxml2.

The unit of interest is a **node**. Nodes are addressed by an `Int` index
into the document's parallel vectors. Node `0` is always the synthetic
**document node**; its children are the document-level nodes.

### 1.1 Node kinds

| Constant | Value | Meaning |
|----------|-------|---------|
| `XML2_KIND_ELEMENT` | 0 | element (root, document node) |
| `XML2_KIND_TEXT` | 1 | character data outside CDATA |
| `XML2_KIND_CDATA` | 2 | CDATA section (content stored raw) |
| `XML2_KIND_COMMENT` | 3 | comment |
| `XML2_KIND_PI` | 4 | processing instruction / XML declaration |
| `XML2_KIND_DOCTYPE` | 5 | DOCTYPE declaration |

### 1.2 Parallel vectors (`XmlDoc`)

| Field | Meaning |
|-------|---------|
| `kinds[i]` | node kind of node `i` |
| `names[i]` | element qualified name; PI target; DOCTYPE name; `""` otherwise |
| `texts[i]` | text/CDATA content; comment body; PI data; DOCTYPE external identifier; `""` otherwise |
| `parents[i]` | parent index; `-1` only for node 0 |
| `first_child[i]` / `last_child[i]` | child-chain ends; `-1` when childless |
| `next_sibling[i]` | next sibling; `-1` when last |
| `opens[i]` / `closes[i]` | source span `[opens[i], closes[i])` |
| `attr_names[k]` / `attr_values[k]` / `attr_owners[k]` | flat attribute association list: attribute `k` belongs to node `attr_owners[k]` |
| `src` | the whole input as bytes, for `xml2_node_raw_bytes` |

Invariants (enforced by construction, checked by tests):

* all vectors have the same length and index the same node;
* node 0 exists in every parsed document and has parent `-1`;
* every other node's parent is a valid element/document index and the
  child chains agree with `parents` (`first_child`/`next_sibling` traversal
  visits exactly the nodes whose `parents` entry equals the container);
* `opens[i] <= closes[i]` for every node except an element left unclosed,
  which cannot occur in an `Ok` document;
* attributes are stored in source order and duplicate names cannot occur;
* `nodes.len() == values.len() == count` for attribute `XPathResult`s.

Node 0's `opens`/`closes` cover the whole input; `names`/`texts` are `""`.

### 1.3 Accessor safety

Every accessor validates its index and returns a neutral value instead of
trapping: `-1` for indices, `""` for strings, an empty vector for byte
accessors. The parser only produces consistent documents; the guards cover
hand-passed out-of-range indices.

---

## 2. Document constraints

* Exactly one root **element**; it is the first element-kind child of node 0.
* Text outside the root is allowed only when it is XML whitespace
  (space, TAB, CR, LF), and is discarded (no node is created).
* Comments, PIs and the DOCTYPE may appear before the root; comments and
  PIs may also appear after the root. A DOCTYPE must precede the root and
  may occur at most once.
* A second element at document level is an error.
* The input must be a `Str`; a `Str` cannot contain a NUL byte, so NUL can
  never appear in a document (numeric references to NUL are rejected).

---

## 3. Parser subset (grammar)

```text
document   := prolog element misc*
prolog     := (xmldecl | comment | pi | doctype)*
xmldecl    := pi with target "xml"                    (stored as a PI)
misc       := comment | pi | ws
element    := start_tag content* end_tag
            | start_tag (empty, self-closing)

start_tag  := '<' Name (S Name S? '=' S? AttValue)* S? ('>' | '/>')
end_tag    := '</' Name S? '>'
AttValue   := '"' [^"]* '"' | "'" [^']* "'"           (entities decoded)

content    := text | element | comment | pi | cdata
text       := [^<]+                                   (entities decoded)
cdata      := '<![CDATA[' .*? ']]>'                   (content raw)
comment    := '<!--' body '-->'                       (body must not contain "--")
pi         := '<?' Name (S data)? '?>'                (data = up to '?>')
doctype    := '<!DOCTYPE' S Name S? ('>' | SYSTEM S? lit | PUBLIC S? lit S? lit) S? '>'
lit        := '"' [^"]* '"' | "'" [^']* "'"           (no entity decoding)

Name       := non-empty run with every byte > 0x20 and none of
              '<' '>' '/' '=' '"' "'" '[' ']' '@' '#'
S          := (space | TAB | CR | LF)+
```

Notes:

* Case is significant everywhere (`SYSTEM`, `CDATA`, `DOCTYPE` and tag
  names are exact byte comparisons).
* Attribute values may use either quote style; the closing quote must
  match the opening one.
* Attribute names are matched exactly and duplicates are rejected.
* An element with no children is serialized self-closing; a parsed
  `<a></a>` and a parsed `<a/>` are the same document.
* Whitespace *inside* elements is preserved as text nodes, including
  indentation.
* The XML declaration is not distinguished from a PI: it is stored as a PI
  node with target `xml`. No version/encoding/standalone validation is
  performed.
* PI data has leading whitespace trimmed; trailing whitespace is part of
  the data (as in `<?pi data ?>`).

---

## 4. Entity decoding

Recognized, in text and attribute values only:

| Form | Result |
|------|--------|
| `&amp;` | `&` |
| `&lt;` | `<` |
| `&gt;` | `>` |
| `&quot;` | `"` |
| `&apos;` | `'` |
| `&#DDD;` | decimal codepoint, UTF-8 encoded |
| `&#xHHH;` / `&#XHHH;` | hexadecimal codepoint, UTF-8 encoded |

Strictness (deliberately different from some lenient readers):

* an unknown name is `xml2: unknown entity`;
* a reference without `;` within 11 bytes is `xml2: unterminated entity`;
* a malformed numeric body, value `0`, a surrogate (`U+D800..U+DFFF`) or a
  value above `U+10FFFF` is `xml2: invalid character reference`;
* CDATA sections, comments, PIs and DOCTYPE literals are **not** decoded.

---

## 5. Namespaces

The parser stores qualified names verbatim and does not reject unbound
prefixes. Resolution happens on demand:

* `xmlns="uri"` declares the default namespace for element names in scope;
  it does **not** apply to unprefixed attributes.
* `xmlns:p="uri"` declares prefix `p`.
* Declarations are scoped: a declaration on a node overrides the same
  prefix on ancestors (nearest wins).
* The reserved prefix `xml` is always bound to
  `http://www.w3.org/XML/1998/namespace`; resolving `xmlns` is an error.
* `xml2_ns_resolve(d, node, "")` returns the default namespace (or `""`);
  a non-empty prefix with no declaration in scope is
  `xml2: unbound namespace prefix`.
* An unprefixed attribute URI is always `""`; a prefixed attribute URI is
  the URI bound to its prefix in the **element's** scope.
* `xml2_ns_decl_count` / `xml2_ns_decl_prefix_at` / `xml2_ns_decl_uri_at`
  list only the declarations **on the node itself**, in source order; the
  prefix of a default declaration is `""`.
* Namespace undeclaration (`xmlns=""`) is supported and yields `""`.

The serializer does no namespace fixup: prefixes, declarations and
qualified names are emitted exactly as stored (attributes sorted, see
section 6). It can therefore serialize a document that a namespace-aware
consumer would reject.

---

## 6. Serializer (canonical form)

`xml2_serialize(d)` serializes the child chain of node 0;
`xml2_serialize_node(d, node)` serializes one node (its subtree for
elements). The canonical form is:

1. **Elements.** `<name` + attributes + (`/>` when childless, else
   `>` children `</name>`). No whitespace is inserted anywhere.
2. **Attribute order.** Attributes are emitted in ascending byte order of
   their names, compared with `xiom.string.compare.str_compare`
   (equivalently: byte-wise lexicographic, shorter prefix first). Because
   duplicate names are rejected at parse time, the order is total and
   deterministic. Namespace declarations are ordinary attributes under
   this rule, so `xmlns` sorts before `xmlns:p`, which sorts before most
   `z...` names.
3. **Attribute quoting.** Always double quotes. Values escape `&` `<` `"`
   (as `&amp;` `&lt;` `&quot;`); `>` and `'` are emitted verbatim.
4. **Text.** Escapes `&` `<` `>` (as `&amp;` `&lt;` `&gt;`); quotes pass
   through.
5. **CDATA.** `<![CDATA[` content `]]>`; every occurrence of `]]>` inside
   the content is split as `]]]]><![CDATA[>`, so the result re-parses to
   the same character data (possibly as two adjacent CDATA nodes).
6. **Comment.** `<!--` body `-->` verbatim (the parser guarantees the body
   contains no `--`).
7. **PI.** `<?target?>` when the data is empty, else `<?target data?>`
   (data verbatim; the parser guarantees it contains no `?>`).
8. **DOCTYPE.** `<!DOCTYPE name>` when there is no external identifier;
   else `<!DOCTYPE name ` external-id `>`. The external identifier is
   stored canonically as `SYSTEM "lit"` or `PUBLIC "pub" "sys"`, re-quoted
   with double quotes unless the literal itself contains a double quote
   (then single quotes are used).
9. **Document-level whitespace** (whitespace-only text between document
   nodes) is not a node and is not reproduced. Whitespace inside elements
   is a text node and is preserved.

Round-trip property tested by the suite:
`parse(serialize(d))` yields a document with the same kinds, names, scalar
strings and attributes, and `serialize` is idempotent from the first
serialization on.

---

## 7. XPath-LITE

### 7.1 Grammar

```text
path       := relpath | '/' relpath
relpath    := step ('/' step)*
step       := nametest pred* | '@' Name | 'text()' pred*
nametest   := Name | Name ':' Name            (prefix must be non-empty too)
pred       := '[' S? integer S? ']'
            | '[' S? '@' Name S? '=' S? quoted S? ']'
quoted     := '"' [^"]* '"' | "'" [^']* "'"
```

### 7.2 Semantics

* **Absolute** paths start at the synthetic document node; `/r/a`
  therefore selects `a` children of the root element `r`.
* **Relative** paths start at the caller's context node, which must be an
  element or the document node (node 0).
* A **name test** selects element children of each context node.
  * Unprefixed (`a`): matches by **local name**, namespace-agnostic.
  * Prefixed (`p:a`): the prefix is resolved in the context node's scope
    (falling back to the candidate's scope when the context node cannot
    resolve it, e.g. the document node at the start of an absolute path)
    and the candidate's own prefix is resolved in its scope; both the URI
    and the local name must match.
* **`@attr`** collects the attribute with the exact qualified name from
  each element in the working set. It is allowed only as the **final**
  step; predicates on attribute steps are not supported. The result is an
  attribute result: `values[k]` is the value and `nodes[k]` the owner
  element of match `k`.
* **`text()`** selects text (kind 1) and CDATA (kind 2) children.
* **Predicates** are applied per context node, left to right:
  * `[n]`: keep the n-th candidate (1-based) of the current list of that
    context node; `n = 0` or out of range keeps nothing. After each
    predicate the list is re-indexed.
  * `[@a='v']` / `[@a="v"]`: keep candidates with an attribute whose
    exact qualified name and decoded value match. No entity decoding,
    escaping or case folding is applied to the predicate literal.
  * Whitespace is allowed around the predicate, the name and `=`.
* Multiple predicates may follow one step; results of all context nodes
  are concatenated in context order, preserving document order within
  each context.

### 7.3 Deliberate deviations from XPath 1.0

* Unprefixed name tests match by local name instead of "no namespace".
* Prefix resolution uses the document context node, not a stylesheet
  context.
* `//`, `*`, `..`, `.`, unions, functions (other than `text()`), numeric
  or string comparisons other than attribute equality, and multiple
  predicates combined per filter axis are out of scope (most are explicit
  errors; see section 9).

Predicate position semantics for `a[1]` are per parent (XPath 1.0 child
axis semantics), not global across the result set.

---

## 8. Limits

| Limit | Value | Constant | On exceed |
|-------|-------|----------|-----------|
| Input size | 1,048,576 bytes | `XML2_MAX_INPUT` | `xml2: document too large` |
| Nesting depth | 64 open elements | `XML2_MAX_DEPTH` | `xml2: nesting too deep` |
| Node count | 16,384 (incl. node 0) | `XML2_MAX_NODES` | `xml2: too many nodes` |
| Attributes per element | 256 | `XML2_MAX_ATTRS` | `xml2: too many attributes` |

Depth 64 is accepted; a 65th open element is rejected. The serializer and
`xml2_text_deep` recurse, but the parse-time depth cap bounds them for any
document produced by `xml2_parse`.

---

## 9. Error catalog

Parse errors are `Err("xml2: <message> at offset <N>")` where `N` is a
byte offset into the input. The offset generally points at the byte just
after the offending token; for text/comment/entity constructs it points at
the start of the offending run or reference, as noted below.

| Message | Trigger |
|---------|---------|
| `xml2: document too large` | input beyond `XML2_MAX_INPUT` |
| `xml2: stray '<'` | `<` with no name and no markup form |
| `xml2: unclosed tag` | EOF inside a start/end tag or after `<` |
| `xml2: malformed tag` | bad tag name bytes or malformed `/` sequence |
| `xml2: malformed attribute` | bad attribute name, missing `=`, unquoted value |
| `xml2: duplicate attribute` | same attribute name twice on one element |
| `xml2: too many attributes` | more than `XML2_MAX_ATTRS` |
| `xml2: unclosed attribute value` | EOF before the closing quote |
| `xml2: unterminated entity` | `&` with no `;` within 11 bytes |
| `xml2: unknown entity` | named entity other than the five predefined |
| `xml2: invalid character reference` | bad numeric body, `0`, surrogate, `> U+10FFFF` |
| `xml2: unclosed comment` | `<!--` with no `-->` |
| `xml2: double hyphen in comment` | `--` inside a comment body (offset: first `--`) |
| `xml2: unclosed CDATA section` | `<![CDATA[` with no `]]>` |
| `xml2: unclosed processing instruction` | `<?` with no `?>` |
| `xml2: malformed processing instruction` | empty or invalid PI target |
| `xml2: malformed DOCTYPE` | bad name, missing whitespace, bad external id, missing `>` |
| `xml2: unsupported internal DTD subset` | `[` after the DOCTYPE name |
| `xml2: DOCTYPE after root element` | DOCTYPE after the root started |
| `xml2: multiple DOCTYPE declarations` | a second DOCTYPE |
| `xml2: unsupported markup declaration` | `<!` that is not DOCTYPE/comment/CDATA |
| `xml2: mismatched closing tag` | close name differs from the open name |
| `xml2: unexpected closing tag` | close tag with no open element |
| `xml2: text outside root element` | non-whitespace text at document level (offset: run start) |
| `xml2: multiple root elements` | a second top-level element |
| `xml2: nesting too deep` | depth beyond `XML2_MAX_DEPTH` |
| `xml2: too many nodes` | node count beyond `XML2_MAX_NODES` |
| `xml2: unclosed element` | EOF with open elements |
| `xml2: no root element` | document without a top-level element |

Namespace errors (`Err`, no offset):

| Message | Trigger |
|---------|---------|
| `xml2: namespace lookup on non-element` | resolution on a bad/non-element node |
| `xml2: reserved namespace prefix` | resolving `xmlns` |
| `xml2: unbound namespace prefix` | prefixed resolution with no declaration in scope |
| `xml2: attribute not found` | `xml2_attr*` / `xml2_ns_attr_uri` miss |

XPath errors (`Err("xml2: xpath: ...")`, no offsets):

| Message | Trigger |
|---------|---------|
| `empty expression` | `""` (also `"/"`) |
| `descendant axis '//' is not supported` | `//` |
| `empty step` | `a//b`, leading/trailing doubled separators |
| `trailing '/'` | expression ends with `/` |
| `unexpected ']'` | `]` outside a predicate |
| `unterminated quote` | quote opened but not closed |
| `unterminated predicate` | `[` without `]` |
| `nested predicates are not supported` | `[` inside a predicate |
| `unsupported function` | any function call other than `text()` |
| `malformed node test` | empty/invalid name test |
| `malformed predicate` | not `[n]` or `[@a='v']` |
| `attribute step must be last` | `@` step followed by more steps |
| `malformed attribute step` | `@` with an invalid/absent name |
| `predicates on attribute steps are not supported` | `@a[1]` |
| `no document root` | absolute path on a rootless document |
| `context node out of range` | relative path with a bad context index |
| `context node is not an element` | relative path on a text/comment/... node |

---

## 10. Non-goals

* **No validation**: no DTD, no internal subset, no content models, no
  schema, no well-formedness beyond the catalog above.
* **No external entities**: only the five predefined and numeric
  character references; no entity declarations, no loading.
* **No XML NameStartChar validation**: names are validated with the
  documented byte rules (section 3), not the full Unicode production.
* **No encoding conversion**: bytes pass through; the parser interprets
  only markup bytes and produces UTF-8 for numeric references. UTF-16
  input, BOM handling and encoding declarations are not implemented.
* **No node mutation**: the DOM is immutable; there is no builder or
  editor API (the serializer composes strings).
* **No namespace fixup** on serialization (section 5).
* **No full XPath 1.0** (section 7.3): no `//`, `*`, `..`, unions,
  functions, axes, or general comparisons.
* **No XML-DSig / canonicalization**: no c14n, exclusive c14n, comments
  stripping or digest support. `xiom.saml` covers XML-DSig structure if
  needed.
* **No pretty printing**: the serializer is canonical, not formatted.
* **No streaming**: the whole document is held in memory; limits bound it.

---

## 11. Version history

* 0.1.0 -- initial pure-XIOM implementation replacing the libxml2 FFI
  placeholder: parser subset, DOM tree, serializer, namespaces,
  XPath-LITE, 24-check inline conformance suite.
