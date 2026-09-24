# xiom.validation

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** Format validators for email, IPv4/IPv6, hex, UUID, slug, dates and
> ports.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`). Tests
> additionally use `xiom.test` and `xiom.io`.

## Scope

`xiom.validation` provides small, infallible `Bool` validators for common
text formats. Every function scans the input byte-wise, is ASCII-centric and
performs no allocation; the accepted syntaxes are the documented pragmatic
subsets in `SPEC.md` (not full RFC 5322 email or RFC 4291 IPv6). There is no
FFI and no dependency beyond `xiom.string`.

## API

| Function | Returns | Description |
|---|---|---|
| `valid_is_email(s)` | `Bool` | One `@`; 1..64 byte local part of `[A-Za-z0-9._%+-]` without leading/trailing/consecutive dots; dotted domain labels of `[A-Za-z0-9-]` without leading/trailing `-`; TLD of >= 2 letters; ASCII only. |
| `valid_is_ipv4(s)` | `Bool` | Exactly four decimal octets `0..255`, no leading zeros unless the part is `"0"`. |
| `valid_is_ipv6(s)` | `Bool` | 1..4 hex digits per group, 2..8 groups, at most one `::` standing for one or more zero groups, no stray single `:`. |
| `valid_is_hex(s)` | `Bool` | Non-empty and only `[0-9A-Fa-f]`. |
| `valid_is_uuid(s)` | `Bool` | Exactly `8-4-4-4-12` hex with hyphens; case-insensitive. |
| `valid_is_slug(s)` | `Bool` | Non-empty `[a-z0-9]` words joined by single `-`; no leading, trailing or doubled dash. |
| `valid_is_date_ymd(y, m, d)` | `Bool` | Proleptic Gregorian date; year >= 1; February 29 only in leap years (2000/2024 yes, 1900/2100 no). |
| `valid_is_port(n)` | `Bool` | `1..65535` inclusive. |

## Usage

```xi
use xiom.validation;
use xiom.io;

fn main() -> Int {
  if valid_is_email("ada@example.com") {
    io.println("email ok");
  }
  if !valid_is_ipv4("256.0.0.1") {
    io.println("bad address rejected");
  }
  if valid_is_date_ymd(2024, 2, 29) {
    io.println("leap day ok");
  }
  if valid_is_uuid("550e8400-e29b-41d4-a716-446655440000") {
    io.println("uuid ok");
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.validation
```

Expected tail: 24 `[PASS]` lines, `xiom.validation: all tests passed`, then
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- Pragmatic ASCII validators, **not** full RFC 5322 / RFC 4291: quoted local
  parts, comments, address literals, IDN/Unicode domains, IPv6 zone IDs and
  embedded dotted-quad IPv6 tails are all out of scope.
- Byte-oriented: any byte >= 0x80 fails the email, slug, hex and UUID checks.
- `valid_is_date_ymd` checks calendar validity only (not time zones, not
  RFC 3339 strings); `valid_is_port` checks the numeric range only.
- No normalization, DNS/MX lookup or uniqueness checks.

See `SPEC.md` for the full per-validator rules and test plan. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
