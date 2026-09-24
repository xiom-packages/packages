# xiom.secret

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** secret redaction for logs and text -- emails, credentials,
> private keys, token runs and card-like digits.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string`,
> `xiom.string.builder` and `xiom.string.compare`). Tests additionally use
> `xiom.test` and `xiom.io`.

## What it is

`xiom.secret` is a small, dependency-light toolkit for keeping secrets out of
logs and free text. Every function is a free function over `Str`; there is no
FFI, and the only allocations are the returned `Str` values (plus one
lowercase copy in `secret_is_sensitive_key`).

- **`secret_luhn_ok`** validates digits-only strings with the Luhn checksum.
- **`secret_mask_email`** masks a whole-string address as `a***@b` (first byte
  of the local part kept).
- **`secret_contains_email`** / **`secret_contains_card`** detect email
  addresses and Luhn-valid card-like runs anywhere in a text.
- **`secret_is_sensitive_key`** screens config/key names against the
  `password`/`secret`/`token`/`api_key`/`apikey`/`authorization`/
  `private_key` markers.
- **`secret_redact`** replaces PEM private-key blocks, `Bearer` credentials,
  AWS `AKIA` access key ids, 32+ byte token runs, card-like runs and email
  addresses with a verbatim placeholder in one left-to-right pass.

All rules are heuristics (see Limitations); the API is error-free by design.
The exact patterns, their priority order and the test plan are in `SPEC.md`.

## API

| Function | Returns | Description |
|---|---|---|
| `secret_luhn_ok(digits)` | `Bool` | True when a digits-only, non-empty string passes the Luhn checksum. |
| `secret_mask_email(s)` | `Str` | Whole-string email masked as `a***@b` (first byte kept); anything else unchanged. |
| `secret_contains_email(s)` | `Bool` | True when an ASCII email token appears anywhere in `s`. |
| `secret_contains_card(s)` | `Bool` | True for a Luhn-valid 13..19 digit run with optional single spaces/dashes. |
| `secret_is_sensitive_key(name)` | `Bool` | True when the lowercased name contains one of the seven sensitive markers. |
| `secret_redact(text, placeholder)` | `Str` | One-pass redaction of PEM blocks, Bearer credentials, AKIA ids, 32+ byte token runs, cards and emails. |

## Usage

```xi
use xiom.secret;
use xiom.io;

fn main() -> Int {
  io.println(secret_mask_email("alice@example.com"));   // a***@example.com
  io.println(secret_luhn_ok("4539578763621486"));      // true
  io.println(secret_contains_card("pay 4539 5787 6362 1486")); // true
  io.println(secret_is_sensitive_key("DB_PASSWORD"));   // true

  let log = "user a@b.com key AKIAIOSFODNN7EXAMPLE card 4539 5787 6362 1486";
  io.println(secret_redact(log, "<redacted>"));
  // user <redacted> key <redacted> card <redacted>
  return 0;
}
```

`placeholder` is inserted verbatim for every replaced span and is never
rescanned, so a placeholder like `<redacted>` or `***` can contain
token-like or email-like text itself.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.secret
```

Expected tail: 20 `[PASS]` lines, `xiom.secret: all tests passed`, then
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Heuristic patterns, not a grammar.** Redaction works on byte patterns
  (ASCII email subset, `AKIA` prefix, `Bearer` + spaces, PEM labels ending in
  `PRIVATE KEY`). Anything outside those shapes is left alone.
- **No entropy analysis.** `secret_redact` does not estimate randomness;
  32+ byte token runs, Luhn-valid 13..19 digit runs and email-like text are
  redacted, while a short high-entropy secret (`hunter2`, an 8-char API key)
  is NOT detected. Feed it known-bad shapes, not raw guessing.
- **Long tokens win over emails.** A token run of 32+ bytes is
  replaced before the email rule, so an address whose local part is that long
  leaves the `@domain` tail in place.
- **Emails are replaced, not masked,** by `secret_redact`
  (`a@b.com` -> `placeholder`); use `secret_mask_email` when a masked form is
  wanted.
- **`Bearer` is case-sensitive** and needs one or more spaces before a
  non-empty token of `[A-Za-z0-9+/=_.-]` (the whole `Bearer <token>` span is
  replaced). PEM redaction requires a matching `-----END <same label>-----`;
  a missing or mismatched END leaves the block untouched.
- **Card detection spans separators.** A 20+ digit run, doubled separators
  and runs of 12 or fewer digits are never treated as cards, and a wrong
  check digit fails Luhn.
- The API never fails: malformed or empty input is handled by returning
  `false`/the original text.

See `SPEC.md` for the exact patterns, the order of application and the test
plan. License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
