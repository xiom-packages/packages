# xiom.secret -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.secret` (`src/secret.xi`). Pure XIOM, no FFI.

## 1. Scope

Six free functions over `Str`:

```xi
pub fn secret_luhn_ok(digits: Str) -> Bool
pub fn secret_mask_email(s: Str) -> Str
pub fn secret_contains_email(s: Str) -> Bool
pub fn secret_contains_card(s: Str) -> Bool
pub fn secret_is_sensitive_key(name: Str) -> Bool
pub fn secret_redact(text: Str, placeholder: Str) -> Str
```

All scanning is byte-wise over the UTF-8 representation; multi-byte sequences
are never decoded and only match where the rule set explicitly targets ASCII.
Complexity is O(n) over the input length for every function. The whole API is
error-free: it returns `Bool`/`Str` values only and has no error channel.

## 2. Non-goals

- A full secret scanner: no entropy analysis, no ML/statistical scoring, no
  database of known key formats beyond the documented patterns.
- RFC 5322 email parsing (no quoted local parts, comments, display names,
  internationalized addresses or DNS validation).
- Payment-card issuer validation (only the Luhn checksum and digit count).
- Streaming/incremental APIs, configuration, logging or FFI.
- Any registry integration.

## 3. Building blocks

### 3.1 Luhn (`secret_luhn_ok`)

Input must be non-empty and digits-only (`0x30`-`0x39`). Scan right to left,
doubling every second digit (starting with the second from the right); a
doubled value above 9 has 9 subtracted; the input passes when the sum is a
multiple of 10. Any non-digit byte (space, dash, letter) or the empty string
returns `false`; `"0"` passes arithmetically.

### 3.2 Email tokens (`_email_span`, shared by mask/contains/redact)

An email token starts at a byte that is not an email-local byte (so the local
part is maximal), and is:

| Part | Rule |
|---|---|
| local | 1..64 bytes of `[A-Za-z0-9._%+-]`; no leading dot, no trailing dot, no `..` |
| `@` | exactly one, at `local.len()` |
| domain | 1..255 bytes: dot-separated labels of `[A-Za-z0-9-]`, each label non-empty and not starting/ending with `-`; at least one label (so `a@b` is valid) |

The span ends after the last complete valid label; a trailing dot after the
last label is not part of the token (`a@b.` contains the token `a@b`). A label
that starts or ends with `-` truncates the domain at the previous complete
label. Bytes >= 0x80 never match (ASCII only). `secret_mask_email` requires
the span to equal the whole string and returns
`first-byte + "***" + text-from-@`, so `a@b` -> `a***@b`.

### 3.3 Card-like runs (`secret_contains_card`, redact)

A run starts at a digit that is not inside a digit run (previous byte is
neither a digit nor a separator directly after a digit) and continues over
digits and single space (`0x20`) or dash (`0x2D`) separators; a separator must
sit between two digits, so doubled separators end the run. The run is a card
when it holds 13..19 digits and those digits pass Luhn. Runs of 20+ digits are
skipped whole, so no 13..19 digit sub-run of a longer number is matched.

### 3.4 Sensitive key names (`secret_is_sensitive_key`)

Lowercase the name (ASCII only) and test substring containment of each marker:
`password`, `secret`, `token`, `api_key`, `apikey`, `authorization`,
`private_key`. This is a heuristic screen: `monkey` is not sensitive (contains
no marker), `tokenizer` and `ACCESS_TOKEN` are.

## 4. Redaction patterns (`secret_redact`)

`placeholder` is appended verbatim for each replaced span; it is never
rescanned, so placeholders may themselves look like tokens or emails.

### 4.1 Order of application

At each byte position the patterns are tried in this priority order; the first
non-empty span wins, is replaced, and scanning resumes after it:

| # | Pattern | Span replaced |
|---|---|---|
| 1 | PEM private-key block | `-----BEGIN <label>-----` line through the matching `-----END <same label>-----` line (including CRLF handling; the line terminator after END is kept) |
| 2 | Bearer credential | `Bearer` + one or more spaces + non-empty token of `[A-Za-z0-9+/=_.-]` |
| 3 | AWS access key id | `AKIA` + exactly 16 of `[0-9A-Z]`, with non-token bytes on both sides |
| 4 | Long token run | maximal run of `[A-Za-z0-9+/=_-]` of length >= 32 |
| 5 | Card-like run | maximal 13..19 digit run (see 3.3), separators included |
| 6 | Email address | email token (see 3.2) |

Unmatched bytes are copied verbatim, so text with no match is returned
byte-for-byte unchanged. Note that (4) precedes (6): an email whose local
part is 32+ bytes loses only the local part (documented in Limitations).

### 4.2 Pattern details

- **PEM (1).** Must start at a line start. The BEGIN line is
  `-----BEGIN <label>-----` with a non-empty label ending in `PRIVATE KEY`
  (so `PRIVATE KEY`, `RSA PRIVATE KEY`, `EC PRIVATE KEY`, `OPENSSH PRIVATE
  KEY` match; `CERTIFICATE` does not). The END line must carry the identical
  label. No END line, or a different label, leaves the text untouched.
- **Bearer (2).** Case-sensitive keyword on a token boundary; the whole
  `Bearer <token>` span is replaced (the scheme word is not kept).
- **AKIA (3).** Both boundary bytes must be outside `[A-Za-z0-9+/=_-]`, so a
  longer alphanumeric run is never partially redacted.
- **Long token (4).** Only maximal runs starting on a token boundary are
  measured; a 31-byte run is kept.
- **Card (5).** See 3.3; digit count and Luhn are re-checked on the maximal
  run.
- **Email (6).** See 3.2; the whole token is replaced by `placeholder`
  (`secret_redact` never masks).

## 5. Error-free API

No function returns `Result`/`Option` and none can fail: malformed input
yields `false` (predicates) or the original text (transforms). There is no
error catalog because there are no errors; this matches the heuristic
sanitizer contract (see section 7).

## 6. Test plan

`tests/test_conformance.xi` (module `secret_tests`) runs 20 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | Luhn valid | `79927398713`, `4539578763621486`, `4111111111111111`, `4222222222222` |
| t2 | Luhn invalid | bad check digits, non-digit bytes, spaces, empty |
| t3 | Mask basic | `alice@example.com` -> `a***@example.com`; `a@b`; dotted local |
| t4 | Mask non-emails | `@b`, `a@`, `a@b.`, `a..b@c.d`, embedded address, empty |
| t5 | Contains email | plain, short (`a@b`) and tagged local parts |
| t6 | No email | missing parts, no `@`, leading/trailing dash labels |
| t7 | Card spacing | space-separated 16, contiguous 16, 19-digit |
| t8 | Card dashes | dash-separated 16, contiguous and spaced 13-digit |
| t9 | Card negatives | bad checksum, 12 digits, 20 digits, doubled separators, empty |
| t10 | Redact card | run replaced whole; 12-digit id kept |
| t11 | PEM multiline | whole block replaced, body bytes gone |
| t12 | PEM no/mismatched END | text unchanged |
| t13 | PEM labels | `RSA PRIVATE KEY` redacts; `CERTIFICATE` does not |
| t14 | Bearer | credential replaced; bare/lowercase/glued keyword kept |
| t15 | AKIA | 20-byte id replaced; 19-byte and glued runs kept |
| t16 | Token runs | 32-byte hex and 44-byte base64 runs replaced; 31-byte kept |
| t17 | Card + email | both replaced on one line; email not masked |
| t18 | Multi-secret line | email, AKIA and card each replaced once |
| t19 | Placeholder/clean | placeholder verbatim, empty placeholder deletes, clean/empty text kept |
| t20 | Sensitive keys | seven markers hit; `username`, `monkey`, empty, `card_number` miss |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values can lower to a pointer comparison).

## 7. Known limitations

- **Heuristic, not exhaustive.** Short secrets, unexpectedly formatted keys
  and non-ASCII addresses pass through; there is no entropy analysis and no
  statistical scoring.
- **Priority order effects.** A 32+ byte email local part is redacted by the
  token rule first, leaving `@domain`; overlapping rules resolve by section
  4.1.
- **ASCII-only email subset.** No quoted local parts, no display names, no
  IDN; `café@example.com` is not detected.
- **No nested-block parsing.** PEM matching is line-based and requires the
  matching END label; a mismatched END leaves the whole block in place.
- **Bearer is case-sensitive** (per RFC 6750 spelling) and collapses the
  scheme word into the redacted span.
- Luhn runs of 20+ digits are never cards, even when a 13..19 digit sub-run
  would validate.

## 8. Compiler / stdlib notes

The implementation follows the proven v0.61.3 idioms:

- Free functions only; no methods, no lambdas, no `Vec[StructType]`, no
  `Vec[fn]` dispatch and no `match` arms.
- Byte reads are widened to Int space once, in `_byte_at_i`
  (`(string.byte_at(s, i) as Int) & 0xFF`), so no UInt8 value is compared
  against an integer literal.
- Output bytes are accumulated in `Vec[UInt8]` and materialized with
  `xiom.string.builder.sb_to_str` (one allocation per result `Str`).
- `Str` equality uses `xiom.string.compare.str_compare` (BUG 17).
