# xiom.sectest -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.sectest` (`src/sectest.xi`). Pure XIOM, no FFI, no network.

## 1. Scope

An in-memory auditor for captured HTTP response headers:

- `sectest_headers_parse` reads a header block into a flat `HeaderSet`;
- lookups expose count, positional name/value, case-insensitive first value
  and occurrence counting;
- `sectest_check` runs the documented hardening policy and returns a
  `SectestReport` of findings;
- report accessors expose rule, severity, message, per-severity counts, a
  pass gate and a deterministic one-line summary.

Only the `headers` branch of the package's placeholder inventory is
implemented. `fuzz`, `tlscheck` and `payload` remain non-goals.

## 2. Non-goals

- **No network activity**: no requests, redirects, sockets or certificates.
  The caller supplies the captured header block.
- **No full HTTP parsing**: no request/status line, no body, no chunking,
  no HTTP/2 pseudo-headers, no message framing.
- **No obs-fold unfolding**: a line beginning with SP/TAB is rejected.
- **No cross-directive logic**: CSP `frame-ancestors` does not excuse a
  missing `X-Frame-Options`, and no other rule cross-references exist.
- **No policy configurability**: thresholds and token sets are fixed (this
  section documents them); changing them means changing the package.
- No FFI, no file I/O, no registry integration; in-memory only.

## 3. Data model

```xi
pub type HeaderSet = {
  names: Vec[Str];   // trimmed, original case
  values: Vec[Str];  // trimmed, original case; may be empty
}

pub type SectestReport = {
  rules: Vec[Str];       // finding rule ids, in fixed order
  severities: Vec[Str];  // "high" | "medium" | "low" | "info"
  messages: Vec[Str];    // stable human-readable text
}
```

The three report vectors are index-aligned; every accessor operates on their
shortest length. `HeaderSet` keeps insertion order and duplicates; the
lookups return the first occurrence.

## 4. Header block grammar

```
block  = *( blank / header )
blank  = *( SP / TAB )
header = name ":" value
```

- Lines are split on LF; one trailing CR per line is dropped (LF and CRLF
  both work).
- A line whose trimmed text is empty is skipped.
- A non-blank line beginning with SP/TAB is an obs-fold continuation and is
  rejected (rule 4).
- The first `:` separates name and value. SP/TAB is trimmed from both; the
  value may be empty. A line without a colon, or with an empty name, is
  malformed.
- Names are compared case-insensitively (ASCII) by all lookups; values are
  compared case-insensitively only where the policy says so.
- `""` parses to a `HeaderSet` with zero headers.

## 5. Policy

`sectest_check` emits findings in this fixed rule order; within a rule the
listed condition order applies. A finding is one (rule, severity, message)
triple, and a report may hold several findings for one rule.

| # | Rule | Condition | Severity | Exact message |
|---|---|---|---|---|
| 1 | `hsts` | header absent | high | `missing Strict-Transport-Security` |
| 2 | `hsts` | present, no `max-age` directive | medium | `HSTS without max-age` |
| 3 | `hsts` | `max-age` present but malformed | medium | `HSTS max-age is not a number` |
| 4 | `hsts` | `max-age < 31536000` | medium | `HSTS max-age <n> is below 31536000` |
| 5 | `hsts` | `includeSubDomains` absent (case-insensitive) | low | `HSTS without includeSubDomains` |
| 6 | `csp` | header absent | high | `missing Content-Security-Policy` |
| 7 | `csp` | value contains `'unsafe-inline'` | medium | `CSP allows 'unsafe-inline'` |
| 8 | `csp` | value contains `'unsafe-eval'` | medium | `CSP allows 'unsafe-eval'` |
| 9 | `x-content-type-options` | header absent | medium | `missing X-Content-Type-Options` |
| 10 | `x-content-type-options` | present, value is not `nosniff` (case-insensitive) | medium | `X-Content-Type-Options is not nosniff` |
| 11 | `x-frame-options` | header absent | medium | `missing X-Frame-Options` |
| 12 | `x-frame-options` | present, value is not `DENY`/`SAMEORIGIN` (case-insensitive) | medium | `X-Frame-Options is not DENY or SAMEORIGIN` |
| 13 | `referrer-policy` | header absent | low | `missing Referrer-Policy` |
| 14 | `referrer-policy` | present, value not a documented token (case-insensitive) | low | `Referrer-Policy value is not recognized` |
| 15 | `permissions-policy` | header absent | low | `missing Permissions-Policy` |
| 16 | `x-xss-protection` | header present (any value) | info | `X-XSS-Protection is deprecated` |
| 17 | `disclosure` | `Server` present | low | `information disclosure via Server` |
| 18 | `disclosure` | `X-Powered-By` present | low | `information disclosure via X-Powered-By` |

Rule details:

1. **HSTS max-age parsing.** The first case-insensitive occurrence of
   `max-age` in the value is used. After it, optional SP/TAB, then `=` is
   required (missing `=` is malformed), then optional SP/TAB, then a decimal
   digit run (empty or non-digit is malformed; values above 1,000,000,000
   are malformed by the overflow guard). Leading zeros are accepted.
2. **HSTS presence.** Rules 2-5 apply only when the header is present; a
   present header can produce up to two findings (a max-age finding and the
   `includeSubDomains` one).
3. **CSP tokens.** `'unsafe-inline'` and `'unsafe-eval'` are matched
   case-sensitively (CSP keywords are lowercase) and independently; both can
   fire for one value.
4. **Referrer-Policy tokens.** The accepted set is `no-referrer`,
   `no-referrer-when-downgrade`, `origin`, `origin-when-cross-origin`,
   `same-origin`, `strict-origin`, `strict-origin-when-cross-origin`,
   `unsafe-url` (case-insensitive).
5. **Deprecation.** Any `X-XSS-Protection` header yields one info finding;
   the value is not interpreted.
6. **Disclosure.** `Server` and `X-Powered-By` each yield their own low
   finding, in that order.

`sectest_passed` is true when the report has zero high and zero medium
findings; low and info findings do not fail it.

## 6. Error catalog

| Condition | Exact message |
|---|---|
| Non-blank line without `:` or with an empty name | `sectest: malformed header line <n>` |
| Non-blank line beginning with SP/TAB | `sectest: folded header line <n>` |

`<n>` is the 1-based line number. Policy problems are findings, never `Err`.

## 7. API contract

```xi
pub fn sectest_headers_parse(text: Str) -> Result[HeaderSet, Str]
pub fn sectest_header_count(h: &HeaderSet) -> Int
pub fn sectest_header_name(h: &HeaderSet, i: Int) -> Str
pub fn sectest_header_value(h: &HeaderSet, i: Int) -> Str
pub fn sectest_header_get(h: &HeaderSet, name: Str) -> Str
pub fn sectest_header_count_named(h: &HeaderSet, name: Str) -> Int
pub fn sectest_check(h: &HeaderSet) -> SectestReport
pub fn sectest_finding_count(r: &SectestReport) -> Int
pub fn sectest_finding_rule(r: &SectestReport, i: Int) -> Str
pub fn sectest_finding_severity(r: &SectestReport, i: Int) -> Str
pub fn sectest_finding_message(r: &SectestReport, i: Int) -> Str
pub fn sectest_count_severity(r: &SectestReport, severity: Str) -> Int
pub fn sectest_passed(r: &SectestReport) -> Bool
pub fn sectest_summary(r: &SectestReport) -> Str
```

Out-of-range accessors return `""` or `0`. `sectest_summary` returns
`"no findings"` for an empty report, else
`"<n> findings: <high> high, <medium> medium, <low> low, <info> info"`.
`get` cannot distinguish an absent header from an empty value; use
`count_named` for that. Complexity: parsing is O(input length); `check` is
O(headers * value length); lookups are O(headers); report accessors O(1)
except the severity counts, which are O(findings).

## 8. Test matrix

`tests/test_conformance.xi` (module `sectest_tests`) runs 22 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). All string comparisons go through `str_compare`;
per-rule checks isolate one rule by rewriting the hardened baseline with
`str_replace_all`.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | basic parse | section 4 |
| t2 | CRLF, blanks, OWS, empty values | section 4 |
| t3 | case-insensitive lookups, first duplicate | section 3 |
| t4 | malformed/folded errors | section 6 |
| t5 | HSTS absent | rule 1 |
| t6 | hardened block | policy baseline |
| t7 | HSTS low max-age | rule 4 |
| t8 | HSTS missing/malformed max-age | rules 2, 3 |
| t9 | HSTS without includeSubDomains | rule 5 |
| t10 | CSP absent/unsafe tokens | rules 6-8 |
| t11 | XCTO nosniff | rules 9, 10 |
| t12 | XFO values | rules 11, 12 |
| t13 | Referrer-Policy tokens | rules 13, 14 |
| t14 | Permissions-Policy presence | rule 15 |
| t15 | X-XSS-Protection deprecation | rule 16 |
| t16 | disclosure headers | rules 17, 18 |
| t17 | fixed finding order (8 findings) | section 5 order |
| t18 | severity counts + summary text | section 7 |
| t19 | pass gate on hardened block | section 5 |
| t20 | empty blocks, out-of-range accessors | section 7 |
| t21 | duplicate headers, first wins | section 3 |
| t22 | name/directive case-insensitivity | sections 4, 5 |

## 9. Known limitations

- No request/status line, body, chunking or HTTP/2 framing.
- Obs-fold lines are rejected rather than unfolded.
- Policy is fixed and opinionated; no configuration or standards lookup.
- Checks use only the first occurrence of a duplicated header.
- `X-Frame-Options` is not cross-checked against CSP `frame-ancestors`.
- HSTS parses only the first `max-age` occurrence and no other directive
  semantics (`preload` is ignored beyond presence of `includeSubDomains`).
- No scoring beyond the high/medium pass gate and severity counts.

## 10. Compiler / stdlib notes (v0.62.1)

Free functions only; flat parallel `Vec`s instead of `Vec[StructType]`;
`Result` construction confined to the leaf helpers `_ok_headers` /
`_err_headers`; every `Str` element read is bound to a typed local and
compared with `str_compare`; widened bytes are masked
(`(b as Int) & 0xFF`). The tests use `xiom.string.str_replace_all` to derive
single-rule variants from the hardened baseline, which keeps the expected
finding indices stable. No compiler workarounds beyond the documented
patterns were required; the suite is green on v0.62.1 with
`program_exit=0`.
