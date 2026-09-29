# xiom.sectest

> **Status:** `incubating` -- conformance-tested (22/22); not yet published to the XIOM registry.
> **Scope:** HTTP security-header verification: parse a response header block,
> check the documented hardening policy, report deterministic findings.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string`,
> `xiom.string.compare` and `xiom.convert`). Tests additionally use
> `xiom.test` and `xiom.io`.

## What it is

`xiom.sectest` audits the security headers a caller already captured. It
parses an HTTP response header block into a flat `HeaderSet` and runs the
documented policy from `SPEC.md` over it: HSTS (`max-age`, one-year minimum,
`includeSubDomains`), CSP (`unsafe-inline`, `unsafe-eval`), nosniff,
`X-Frame-Options`, `Referrer-Policy` tokens, `Permissions-Policy` presence,
the deprecated `X-XSS-Protection`, and server-identifying headers. Each
finding carries a rule id, a severity (`high`/`medium`/`low`/`info`) and a
stable message; findings come back in a fixed rule order, and
`sectest_summary` turns a report into a deterministic one-liner.

The package never sends a request, never follows redirects and never
validates certificates: it is a pure text auditor for headers captured by a
test harness. Only the `headers` branch of the placeholder inventory is
implemented; fuzzing, TLS scanning and payload generation are non-goals.

## API

| Function | Returns | Description |
|---|---|---|
| `sectest_headers_parse(text)` | `Result[HeaderSet, Str]` | Parse `Name: value` lines (LF/CRLF); rejects malformed and folded lines. |
| `sectest_header_count(h)` | `Int` | Number of headers. |
| `sectest_header_name(h, i)` | `Str` | Name of header `i`; `""` out of range. |
| `sectest_header_value(h, i)` | `Str` | Value of header `i`; `""` out of range. |
| `sectest_header_get(h, name)` | `Str` | First value of a header, case-insensitive; `""` when absent. |
| `sectest_header_count_named(h, name)` | `Int` | Occurrences of a header name. |
| `sectest_check(h)` | `SectestReport` | Run the full documented policy. |
| `sectest_finding_count(r)` | `Int` | Number of findings. |
| `sectest_finding_rule(r, i)` | `Str` | Rule id of finding `i`. |
| `sectest_finding_severity(r, i)` | `Str` | `high` / `medium` / `low` / `info`. |
| `sectest_finding_message(r, i)` | `Str` | Stable message of finding `i`. |
| `sectest_count_severity(r, sev)` | `Int` | Findings with a severity. |
| `sectest_passed(r)` | `Bool` | True when no high and no medium finding. |
| `sectest_summary(r)` | `Str` | `no findings` or `N findings: H high, M medium, L low, I info`. |

## Usage

```xi
use xiom.sectest;
use xiom.io;

fn main() -> Int {
  let block = "Strict-Transport-Security: max-age=3600\nServer: nginx\n";
  let r = sectest_headers_parse(block);
  match r {
    Ok(h) => {
      let rep = sectest_check(&h);
      io.println(sectest_summary(&rep));
      // e.g. "6 findings: 2 high, 2 medium, 2 low, 0 info"
      io.println(sectest_finding_message(&rep, 0));
      // "HSTS max-age 3600 is below 31536000"
      io.println(sectest_passed(&rep));   // false
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.sectest
```

Expected tail: 22 `[PASS]` lines, `xiom.sectest: all tests passed`, then
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- Header block only: no request line, status line, body or HTTP/2
  pseudo-headers; a line without a colon is an error.
- Obs-fold continuation lines (leading SP/TAB) are rejected, not unfolded.
- The policy is the fixed set in `SPEC.md`; thresholds (one-year HSTS,
  allowed Referrer-Policy tokens, deprecation of X-XSS-Protection) are
  documented opinions, not fetched standards.
- `X-Frame-Options` is checked independently of a CSP `frame-ancestors`
  directive; the report does not cross-reference them.
- Duplicate headers are preserved, but checks use the first occurrence only.
- No request is made and no redirect is followed: the caller supplies the
  captured headers.
- In-memory only: no FFI, no file I/O.

See `SPEC.md` for the exact grammar, policy table and test matrix. License:
MIT OR Apache-2.0 (see the repository root `LICENSE`).
