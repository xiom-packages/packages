# xiom.fits

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM FITS header codec: 2880-byte blocks, 80-character
> keyword cards, validated string/logical/integer/real/undefined values,
> COMMENT/HISTORY/blank continuation cards, END handling and space padding.
> **Deps:** `xiom.std` only. The library module imports `xiom.string` and
> `xiom.string.compare`; the tests additionally use `xiom.test`,
> `xiom.io` and `xiom.convert`. No FFI.

## What it is

`xiom.fits` encodes and decodes the *header* part of FITS files (Flexible
Image Transport System, IAU FITS Standard 4.0). A FITS header is a whole
number of 2880-byte blocks of 80-character cards; the last card carries the
reserved keyword `END` and the rest of the block is ASCII space padding.

`fits_parse` validates every card and returns a `FitsHeader`: a flat list of
cards stored as five parallel vectors (raw 80-character text, keyword, kind,
value text, comment text). `fits_encode` writes the raw cards back verbatim,
appends `END` and pads with spaces, so a parsed header re-encodes
byte-for-byte (for the normal case where the source ends in the block that
holds `END`; accepted trailing all-space blocks are not reproduced).
`fits_card_format` builds one canonical fixed-width card, and
the `fits_push_*` helpers append typed cards to a header under construction.

Numeric values are **not** converted to numbers: integer and real fields are
validated lexically and preserved as the exact raw token (`+0042`, `.5`,
`-1.50E+02`, `2.5D-3`), so the codec never loses or rounds a digit.

## Install and use

Declare the dependency in your package manifest:

```xi
deps: { "xiom.std": ">=0.60.0 <1.0.0", "xiom.fits": "0.1.0" };
```

Then import the module:

```xi
use xiom.fits;
```

## Quick start

```xi
use xiom.fits;
use xiom.io;

// Read a header (bytes must be a whole number of 2880-byte blocks).
let parsed = fits_parse(&header_bytes);
match parsed {
  Ok(h) => {
    io.println("cards: " + xiom.convert.int_to_string(fits_card_count(&h)));
    let obj = fits_str_value(&h, "OBJECT");       // Option[Str]
    let naxis = fits_int_token(&h, "NAXIS");      // raw token, Option[Str]
    io.println("comment: " + fits_comment_of(&h, "BITPIX"));
  },
  Err(e) => { io.println("parse error: " + e); },
}

// Build a header and encode it.
var h = fits_new();
fits_push_logical(&mut h, "SIMPLE", true, "file does conform to FITS standard");
fits_push_int(&mut h, "BITPIX", "16", "number of bits per data pixel");
fits_push_str(&mut h, "OBJECT", "M31", "object name");
fits_push_float(&mut h, "EXPTIME", "1.25E+01", "seconds");
fits_push_comment(&mut h, "built by xiom.fits");
let bytes = fits_encode(&h);                       // multiple of 2880
```

## API

| Function | Returns | Description |
|---|---|---|
| `fits_parse(data)` | `Result[FitsHeader, Str]` | Decode whole 2880-byte blocks into a validated header. |
| `fits_encode(h)` | `Vec[UInt8]` | Emit stored cards verbatim, then `END` and space padding. |
| `fits_card_format(keyword, kind, value, comment)` | `Result[Str, Str]` | Format one exactly-80-character card. |
| `fits_new()` | `FitsHeader` | Empty header. |
| `fits_push_card(h, card)` | `Result[Unit, Str]` | Validate and append one 80-character card. |
| `fits_push_str(h, keyword, value, comment)` | `Result[Unit, Str]` | Append a string card. |
| `fits_push_logical(h, keyword, value, comment)` | `Result[Unit, Str]` | Append a `T`/`F` card from a `Bool`. |
| `fits_push_int(h, keyword, token, comment)` | `Result[Unit, Str]` | Append an integer card from a validated token. |
| `fits_push_float(h, keyword, token, comment)` | `Result[Unit, Str]` | Append a real card from a validated token. |
| `fits_push_undefined(h, keyword, comment)` | `Result[Unit, Str]` | Append a card with an empty value field. |
| `fits_push_comment(h, text)` | `Result[Unit, Str]` | Append a `COMMENT` card. |
| `fits_push_history(h, text)` | `Result[Unit, Str]` | Append a `HISTORY` card. |
| `fits_push_blank(h, text)` | `Result[Unit, Str]` | Append a blank-keyword continuation card. |
| `fits_card_count(h)` | `Int` | Number of stored cards (`END` is not stored). |
| `fits_card(h, i)` | `Str` | Raw 80-character text of card `i`; `""` out of range. |
| `fits_keyword(h, i)` | `Str` | Keyword of card `i`; `""` out of range/blank. |
| `fits_kind(h, i)` | `Int` | `FITK_*` kind of card `i`; `-1` out of range. |
| `fits_value(h, i)` | `Option[Str]` | Value text of card `i`; `None` for non-value cards. |
| `fits_comment(h, i)` | `Str` | Comment of card `i` (card text for COMMENT/HISTORY/BLANK). |
| `fits_find(h, keyword)` | `Int` | First matching card index (case-insensitive), else `-1`. |
| `fits_str_value(h, keyword)` | `Option[Str]` | Decoded string value of the first match. |
| `fits_bool_value(h, keyword)` | `Option[Bool]` | Logical value of the first match. |
| `fits_int_token(h, keyword)` | `Option[Str]` | Raw integer token of the first match. |
| `fits_float_token(h, keyword)` | `Option[Str]` | Raw real token of the first match. |
| `fits_comment_of(h, keyword)` | `Str` | Comment of the first match; `""` when absent. |

Kinds: `FITK_STR` (0), `FITK_LOGICAL` (1), `FITK_INT` (2), `FITK_REAL` (3),
`FITK_UNDEFINED` (4), `FITK_COMMENT` (5), `FITK_HISTORY` (6), `FITK_BLANK`
(7).

Errors: `fits: bad block padding`, `fits: missing END`,
`fits: unexpected END`, `fits: card not 80 chars`, `fits: bad keyword`,
`fits: missing '='`, `fits: quote not closed`, `fits: junk after value`,
`fits: bad logical`, `fits: invalid integer`, `fits: invalid real`,
`fits: invalid value`, `fits: bad kind`, `fits: card too long`
(see SPEC.md for the exact conditions).

## Error model

Every fallible function reports a deterministic `Err(Str)` whose message
starts with `fits: `, mirroring the other xiom codec packages. Parsing
validates the block structure, the card structure, the keyword charset and
the value syntax, and stops at the first violation; decoding never returns a
partially validated header. Building functions (`fits_push_*`,
`fits_push_card`, `fits_card_format`) validate before touching the header,
so `h` is byte-for-byte unchanged when they return `Err`. `fits_encode` has
no error channel because every stored card was validated when it was pushed.
Lookup/accessor functions never fail: out-of-range indices yield `""`/`-1`/
`None` and absent keywords yield `-1`/`None`/`""`.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.fits
```

Expected: the section-4 namespace check passes, 20 `[PASS]` lines, and a
final `port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Header only.** There is no data-unit/image array decoding, no BINTABLE
  or other extension-table decoding, and no WCS math. The codec stops at the
  END card.
- **No long-string CONTINUE convention.** A string must be closed within its
  own card. `fits_card_format` accepts at most 68 characters of string
  content without a comment (fewer with one); longer strings are
  `Err("fits: card too long")`.
- **No complex values.** The `(real, real)` complex form is rejected;
  values are strings, logicals, integers, reals or undefined.
- **No HIERARCH / long-keyword convention.** Keywords are the standard 8
  characters in columns 1-8.
- **Numbers stay text.** Integer and real tokens are validated and preserved
  verbatim; converting them to `Int`/`Float64` is the caller's job, so any
  precision or range decision is explicit and outside this package.
- **ASCII model.** Card bytes are copied into strings without UTF-8
  validation; FITS headers are defined as ASCII. Non-ASCII bytes are
  preserved as-is when possible.
- **Text is trimmed in accessors.** Comments and COMMENT/HISTORY/blank card
  text are returned with surrounding spaces removed; the raw 80-character
  card (including exact spacing) is available through `fits_card`.
- **Duplicate keywords are preserved.** `fits_find` is a document-order
  linear scan and the first match wins; there is no canonical-order or
  uniqueness enforcement.
- **Trailing all-space blocks are accepted and dropped.** Parsing tolerates
  blocks that consist only of spaces after the block holding `END`; encoding
  always emits the minimal number of blocks, so those extra bytes are not
  reproduced.
- Header text is stored once per card plus four small parallel fields; a
  header is a plain value type and is not thread-safe.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
