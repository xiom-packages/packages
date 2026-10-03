# xiom.auth

> **Status:** `incubating` -- conformance-tested (24/24); published at `v0.1.3` on the XIOM registry.
> **Scope:** HTTP authentication header codecs (RFC 7235 / 7617 / 7616 /
> 6750). Pure XIOM: no FFI, no network, no crypto, no session management.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.builder`,
> `xiom.string.compare`, `xiom.encoding.base64`).

## What it is

`xiom.auth` is a **structure codec** for the HTTP authentication header
fields. It parses and builds the wire grammar of `Authorization`,
`Proxy-Authorization`, `WWW-Authenticate` and `Proxy-Authenticate` values:

* generic scheme + credentials grammar (token68 or auth-param list) with
  byte-offset spans and a consumed count for every parse;
* Basic, Digest and Bearer helpers layered on top of the generic parser;
* unknown schemes (Negotiate, AWS4-HMAC-SHA256, ...) survive the same
  generic accessors, raw spans included.

It does **not** compute digests, verify credentials, issue tokens, or talk to
a network. Digest responses are checked structurally (field presence, `nc`
shape, offered `qop`, algorithm match); the response hash itself is the
caller's concern.

## Install / manifest

```xiom
package xiom_auth {
  name: "xiom.auth";
  version: "0.1.0";
  modules: ["xiom.auth"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
```

## Usage

Parse an Authorization value and read its parts:

```xiom
use xiom.auth;
use xiom.string.compare;

let r = auth_parse_authorization("Digest realm=\"r\", nonce=\"n\", qop=\"auth\"");
if r.is_ok {
  let h: AuthHeader = r.value;
  // auth_header_scheme(&h)              -> "Digest"
  // auth_header_param_get(&h, "NONCE")  -> Ok("n")   (case-insensitive)
  // auth_header_consumed(&h)            -> bytes consumed
  // auth_header_slice(value, &h)        -> the raw text
}
```

Parse a challenge list (multiple challenges are comma-separated per
RFC 7235):

```xiom
let c = auth_parse_www_authenticate("Newauth realm=\"apps\", type=1, Basic realm=\"simple\"");
if c.is_ok {
  let l: AuthChallenges = c.value;
  // auth_challenge_count(&l) -> 2
  // auth_challenge_pick(&l, "Basic") -> 1
}
```

Basic credentials:

```xiom
let e = auth_basic_encode("user", "pass");      // Ok("Basic dXNlcjpwYXNz")
let d = auth_basic_decode("YTpiOmM=");          // Ok(... user "a", password "b:c")
```

Digest challenge/response validation (no hashing):

```xiom
// h = challenge header, r = parsed response
let ok = auth_digest_validate_response(&r, &challenge);
```

Bearer:

```xiom
let t = auth_bearer_token("Bearer YWJjZA==");   // Ok("YWJjZA==")
let b = auth_bearer_parse_challenge(&h);        // realm / scope / error fields
```

## API areas

| Area | Examples |
|------|----------|
| Generic parse | `auth_parse_authorization`, `auth_parse_header_at`, `auth_parse_www_authenticate` |
| Header accessors | `auth_header_scheme`, `auth_header_consumed`, `auth_header_param_get`, `auth_header_slice` |
| Challenge accessors | `auth_challenge_count`, `auth_challenge_pick`, `auth_challenge_param_get`, `auth_challenge_slice` |
| Basic | `auth_basic_encode`, `auth_basic_decode`, `auth_basic_decode_strict`, `auth_basic_parse`, `auth_basic_charset_ok` |
| Digest | `auth_digest_parse_challenge`, `auth_digest_challenge_build`, `auth_digest_parse_response`, `auth_digest_response_check`, `auth_digest_validate_response` |
| Bearer | `auth_bearer_token`, `auth_bearer_authorization`, `auth_bearer_parse_challenge`, `auth_bearer_challenge_build` |

## Testing

```powershell
.\scripts\port.ps1 -Package xiom.auth
```

The suite (`tests/test_conformance.xi`, 24 checks) is built from synthetic
headers: Basic padding variants, Digest full/minimal/invalid, multi-challenge
`WWW-Authenticate`, Bearer error forms, quoted-string escapes and malformed
inputs. `SPEC.md` documents the grammar, the error catalog and a coverage map.

## Notes

The module targets XIOM compiler v0.61.3 and follows the free-function,
parallel-Vec, leaf-`Ok`/`Err` style of its siblings (`xiom.oauth`,
`xiom.quotedprintable`). See `SPEC.md` section 11 for the documented
relaxations (relaxed raw parameter values, strict challenge lists).

## License

MIT OR Apache-2.0
