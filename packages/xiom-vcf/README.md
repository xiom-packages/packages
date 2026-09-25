# xiom.vcf

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** an RFC 6350-subset vCard text codec: content lines with optional
> groups and parameters, CRLF folding/unfolding, text-value escaping,
> BEGIN:VCARD/END:VCARD cards (VERSION 3.0 or 4.0), multi-card streams, card
> building and re-serialization; in-memory `Str` only.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.builder.sb_to_str` and
> `xiom.string.compare.str_compare`). Tests additionally use `xiom.test` and
> `xiom.io`.

## Scope

`xiom.vcf` reads and writes vCard text. `vcf_parse_card` parses exactly one
card into a flat `VCard` (parallel vectors for groups, uppercased property
names, raw parameter sections, unescaped values and the original logical
lines); `vcf_parse_stream` parses a one-or-more-card stream into a
`VCardStream` with per-card `firsts`/`counts`. `vcf_write` serializes a parsed
card back to CRLF text folded at 75 bytes, and `vcf_build_card` builds a card
from the common FN/N/ORG/TEL/EMAIL/ADR fields. Values are escaped and
unescaped with `vcf_escape` / `vcf_unescape` (and `vcf_escape_component` for
structured N/ADR components).

It intentionally does **not** decode binary PHOTO payloads, convert charsets,
or implement vCard 2.1 quirks -- see Limitations.

## API

| Function | Returns | Description |
|---|---|---|
| `vcf_escape(value)` | `Str` | Escape a text value: `\`, CR/LF (as `\n`), `;` and `,`. |
| `vcf_escape_component(value)` | `Str` | Escape one N/ADR component: `\`, CR/LF and `,`; `;` passes through. |
| `vcf_unescape(value)` | `Str` | Decode `\\`, `\n`/`\N`, `\;`, `\,`; unknown `\X` becomes `X`. |
| `vcf_parse_card(text)` | `Result[VCard, Str]` | Parse exactly one card; `Err("vcf: ...")` on malformed input. |
| `vcf_parse_stream(text)` | `Result[VCardStream, Str]` | Parse one or more cards separated by blank lines. |
| `vcf_property_count(v)` | `Int` | Number of stored properties (BEGIN/VERSION/END excluded). |
| `vcf_property(v, i)` | `VcfProperty` | Property `i`; the all-empty property when out of range. |
| `vcf_prop_index(v, name)` | `Int` | First property index with `name` (case-insensitive); -1 when absent. |
| `vcf_prop_value(v, name)` | `Option[Str]` | First value of `name`; `None` when absent. |
| `vcf_props_all(v, name)` | `Vec[Str]` | Every value of `name`, in document order (a fresh copy). |
| `vcf_param_value(v, i, pname)` | `Option[Str]` | First value of parameter `pname` on property `i`. |
| `vcf_stream_count(s)` | `Int` | Number of cards in a stream. |
| `vcf_stream_version(s, i)` | `Str` | Version of card `i`; `""` when out of range. |
| `vcf_stream_property_count(s, i)` | `Int` | Property count of card `i`; 0 when out of range. |
| `vcf_stream_property(s, i, j)` | `VcfProperty` | Property `j` of card `i`; all-empty when out of range. |
| `vcf_build_n(family, given, additional, prefix, suffix)` | `Str` | Escaped `;`-joined N value. |
| `vcf_build_adr(pobox, ext, street, locality, region, code, country)` | `Str` | Escaped `;`-joined ADR value. |
| `vcf_build_card(version, formatted_name, n, org, tel, email, adr)` | `Result[Str, Str]` | Build a CRLF card from fields; `Err("vcf: ...")` on a bad version or empty FN. |
| `vcf_write(v)` | `Str` | Serialize a parsed card (folded, CRLF, re-escaped). |
| `vcf_write_stream(s)` | `Str` | Serialize every card of a stream in order. |

`VcfProperty` = `{ group, name, params, value, raw }`; `VCard` =
`{ version, groups, names, params, values, raws }`; `VCardStream` =
`{ versions, firsts, counts, groups, names, params, values, raws }`.

## Usage

```xi
use xiom.vcf;
use xiom.io;

fn main() -> Int {
  let text = "BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada Lovelace\r\nN:Lovelace;Ada;;;\r\nTEL;TYPE=WORK:+44 20 7946 0958\r\nEND:VCARD\r\n";
  match vcf_parse_card(text) {
    Ok(card) => {
      match vcf_prop_value(&card, "fn") {
        Some(name) => { io.println(name); },   // Ada Lovelace
        None => {},
      }
      let tel_index = vcf_prop_index(&card, "TEL");
      match vcf_param_value(&card, tel_index, "TYPE") {
        Some(kind) => { io.println(kind); },   // WORK
        None => {},
      }
      io.println(vcf_write(&card));            // canonical CRLF card
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

Building a card from fields:

```xi
let r = vcf_build_card("4.0", "Ada Lovelace", vcf_build_n("Lovelace", "Ada", "", "", ""), "Analytical Engines", "", "ada@example.com", "");
match r {
  Ok(text) => { io.println(text); },
  Err(e) => { io.println(e); },
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.vcf
```

Expected tail: 24 `[PASS]` lines, `xiom.vcf: all tests passed`, then
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No binary payload handling**: `PHOTO`, `LOGO` and friends are ordinary
  text values; base64 or `data:` payloads pass through as strings and are not
  decoded, re-encoded or validated.
- **No charset conversion**: `Str` is a UTF-8 byte buffer; non-ASCII bytes
  pass through untouched and `CHARSET` parameters are not interpreted.
- **No vCard 2.1 support**: VERSION must be 3.0 or 4.0; 2.1 cards are
  rejected with `vcf: unsupported version: 2.1`. The only 2.1-era tolerances
  are bare parameter segments, LF/CR line endings and a leading BOM.
- **No property-specific semantics**: values are never decomposed into
  components (N, ADR, GEO, ORG stay `;`-joined strings), no date/phone/geo
  validation, no RFC 6868 parameter caret-decoding, no group semantics.
- **Parameter values** do not unescape quoted strings beyond removing the
  surrounding double quotes, and only the first comma-separated value of a
  parameter is returned.
- **Text escaping is canonical**: escaped/unescaped distinctions are
  normalized (`\n` becomes a real LF in the model, re-encoded on write), so a
  parse -> write pass is model-preserving, not byte-preserving.
- **Folding is byte-based**: a long line is split every 75 bytes and may
  split a multi-byte UTF-8 sequence.
- **Errors carry no line numbers** (the offending line text is included).

See `SPEC.md` for the exact grammar, folding and escaping rules, the error
catalog and the test matrix. License: MIT OR Apache-2.0 (see the repository
root `LICENSE`).
