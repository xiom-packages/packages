# xiom.ntriples

> **Status:** `incubating` -- implemented and conformance-tested; NOT published yet.
> **Scope:** a pure-XIOM RDF 1.1 N-Triples codec: parse triple lines into flat
> parallel vectors, read terms through accessors, and emit a stable canonical
> form.
> **Deps:** `xiom.std` only (uses `xiom.string`, `xiom.string.builder`,
> `xiom.string.compare` and `xiom.convert`).

## What it is

`xiom.ntriples` reads and writes [RDF 1.1 N-Triples](https://www.w3.org/TR/n-triples/):
line-based `<subject> <predicate> <object> .` statements with IRIs in angle
brackets, blank nodes `_:label`, and literals `"text"`, `"text"@lang` or
`"text"^^<datatype>`. It parses escape sequences in literals and IRIs, skips
blank lines and `#` comments, and round-trips through a canonical emitter
whose hex escapes are uppercase.

The document model is deliberately flat:

```
NtDocument {
  s_kinds, s_texts,          // subject: "iri" | "bnode", and its text
  p_texts,                   // predicate: always an IRI text
  o_kinds, o_texts,          // object: "iri" | "bnode" | "literal", and text
  o_langs, o_dts, o_flags    // @lang, ^^datatype, literal flavor (0/1/2)
}
```

There is one slot per triple in each vector (XIOM cannot hold
`Vec[StructType]`), so triple `i` is read with `nt_subject_kind(&doc, i)`,
`nt_object_text(&doc, i)`, and so on. Documents are treated as read-only:
build them with `nt_parse` or `nt_add_triple`, read them with the accessors.

## API

| Function | Signature | Description |
|---|---|---|
| `nt_new` | `() -> NtDocument` | Empty document (zero triples). |
| `nt_add_triple` | `(d, s_kind, s_text, p_text, o_kind, o_text, o_lang, o_dt) -> Bool` | Append a triple without parsing; validates kinds, labels, language tags and lang/datatype exclusivity. `false` = rejected, nothing mutated. |
| `nt_parse` | `(text: Str) -> Result[NtDocument, Str]` | Parse a whole document; first error wins. |
| `nt_emit` | `(d: &NtDocument) -> Str` | Stable canonical text: one line per triple, single spaces, uppercase hex escapes, final LF; `""` for an empty document. |
| `nt_triple_count` | `(d) -> Int` | Number of triples. |
| `nt_subject_kind` | `(d, i) -> Str` | `"iri"` or `"bnode"`; `""` out of range. |
| `nt_subject_text` | `(d, i) -> Str` | IRI text (no brackets) or label (no `_:`). |
| `nt_predicate` | `(d, i) -> Str` | Predicate IRI text. |
| `nt_object_kind` | `(d, i) -> Str` | `"iri"`, `"bnode"` or `"literal"`. |
| `nt_object_text` | `(d, i) -> Str` | Term text; literal lexical form with escapes decoded. |
| `nt_object_lang` | `(d, i) -> Str` | Language tag, preserved as written; `""` when absent. |
| `nt_object_datatype` | `(d, i) -> Str` | Datatype IRI text; `""` when absent (or explicitly `^^<>`). |
| `nt_object_has_datatype` | `(d, i) -> Bool` | `true` for any `^^`-tagged literal, including `^^<>`. |

## Install / use

```
xiom pkg install xiom.ntriples@0.1.0   # consumer
xiom pkg publish                       # maintainer (needs XIOM_REGISTRY_TOKEN)
```

Then import the module with `use xiom.ntriples;`. The package depends only on
`xiom.std` (`>=0.60.0 <1.0.0`).

## Quick start

```xi
use xiom.ntriples;
use xiom.io;

fn main() -> Int {
  let text = "# a tiny graph\n"
    + "<http://example.org/s> <http://example.org/p> \"42\"^^<http://www.w3.org/2001/XMLSchema#integer> .\n"
    + "_:b0 <http://example.org/label> \"héllo\\nworld\"@en .\n";

  match nt_parse(text) {
    Ok(doc) => {
      io.println(nt_object_text(&doc, 0));      // 42
      io.println(nt_object_datatype(&doc, 0));  // http://www.w3.org/2001/XMLSchema#integer
      io.println(nt_subject_kind(&doc, 1));     // bnode
      io.println(nt_object_lang(&doc, 1));      // en
      io.print(nt_emit(&doc));                  // canonical, comments dropped
    },
    Err(e) => {
      io.println(e);                            // "ntriples: ... at <byte offset>"
    },
  };
  return 0;
}
```

Programmatic construction works the same way:

```xi
var doc = nt_new();
let ok = nt_add_triple(&mut doc, "iri", "http://example.org/s", "http://example.org/p",
                       "literal", "hello", "en", "");
// ok == true, nt_triple_count(&doc) == 1
// nt_emit(&doc) == "<http://example.org/s> <http://example.org/p> \"hello\"@en .\n"
```

## Error model

Every failure is `Err("ntriples: <reason> at <pos>")`, where `<pos>` is a
0-based byte offset into the whole input. `nt_parse` validates UTF-8 first
(`invalid UTF-8 byte`), then stops at the first problem: `unterminated
IRI` / `unterminated literal`, `missing '<'` / `missing '>'` / `missing '.'`,
`bad escape` (unknown escape, malformed `\u`/`\U`, surrogate `U+D800-U+DFFF`,
above `U+10FFFF`, `U+0000`), `bad language tag`, `invalid blank node label`,
`raw control byte in literal`, `extra term`, `unexpected end of line` and
`unexpected byte`. The full condition/position table is in
[SPEC.md](SPEC.md#7-error-catalog).

## Escapes

Literals decode `\n`, `\t`, `\r`, `\"`, `\\`, `\uXXXX` and `\UXXXXXXXX`; IRIs
decode `\uXXXX` and `\UXXXXXXXX` (the only escapes `IRIREF` allows). Hex
digits are case-insensitive on input. `nt_emit` writes escapes with uppercase
hex and leaves raw UTF-8 and raw TAB bytes alone. `\b`, `\f` and `\'` are
valid RDF 1.1 escapes but are outside this subset and are rejected as bad
escapes.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.ntriples
```

Expected tail: `port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

Equivalent raw compiler invocation from `packages/xiom-ntriples/`:

```
xiom --run tests/test_conformance.xi
```

## Limitations

- **Documented subset.** Blank node labels are ASCII `[A-Za-z0-9_.-]` (no
  Unicode `PN_CHARS`, no `:` inside labels); `\b`, `\f` and `\'` are rejected.
  See SPEC.md section 2 for the full list of non-goals.
- **No RDF semantics.** No datatype interpretation, no blank node identity
  across documents, no IRI resolution or validity checking beyond the
  `IRIREF` character set; an empty IRI `<>` is accepted as-is.
- **No Unicode normalization.** Code points are stored exactly as decoded;
  language tags and datatypes keep their original case.
- **Not byte-identical to W3C canonical N-Triples.** Layout and hex case
  match, but this emitter also escapes TAB as `\t` and other C0 controls as
  `\u00XX` (W3C canonical would leave them raw).
- **Whole-document parsing.** No streaming, no error recovery (first error
  only) and no line/column numbers, only byte offsets.
- **No BOM handling**: a leading UTF-8 BOM is an `unexpected byte` error.
- Input must be well-formed UTF-8 and cannot contain an embedded NUL byte
  (XIOM `Str` semantics), so `\u0000` is rejected.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
