# xiom.curl -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.curl` (`src/curl.xi`). Pure XIOM, no FFI, no transport.
Manifest: `package.xi` (deps: `xiom.std >=0.60.0 <1.0.0`; the module imports
`xiom.string`, `xiom.string.builder`, `xiom.string.compare`, `xiom.convert`
and `xiom.encoding.base64` -- the last one only for Basic auth).

## 1. Scope

A deterministic HTTP client **model**. It builds and validates the data an
HTTP exchange is made of -- URLs, request/response envelopes, redirects,
cookies, auth headers, retry decisions and pool accounting -- and performs no
I/O of any kind.

Covered surface:

1. absolute-URL lexical parsing, normalization and reference resolution;
2. RFC 3986 percent encoding/decoding for components;
3. request model (method/URL/version/headers/body) and wire encoding;
4. redirect-chain model (301/302/303/307/308, method rewriting, depth);
5. cookie model (Set-Cookie subset, matching, expiry, jar);
6. auth helpers (Basic/Bearer header shapes);
7. retry/backoff policy (deterministic);
8. connection-pool keep-alive accounting;
9. response model (status/headers/body, head parser, envelope class).

**Non-goals:** sockets, DNS, TLS, proxies, HTTP/2, chunked transfer decoding,
streaming, multipart/form bodies, date arithmetic, public-suffix lists,
userinfo and IPv6 URL literals, server-side request parsing, timers or
actual sleeping. See section 13.

## 2. Notation

- **Byte** values are read widened: `(byte_at(s, i) as Int) & 0xFF`, so every
  comparison below is in 0..255.
- **Offset** errors are 0-based byte offsets. URL errors carry an offset into
  the URL text; percent errors into the decoded string; cookie name/value
  errors into the whole Set-Cookie header; header name/value errors into the
  name or value being checked; response-parse structural errors into the
  response text.
- `ALPHA`, `DIGIT`, `tchar`, `unreserved` follow RFC 5234 / RFC 7230 /
  RFC 3986: `unreserved = ALPHA / DIGIT / "-" / "." / "_" / "~"`;
  `tchar = "!" / "#" / "$" / "%" / "&" / "'" / "*" / "+" / "-" / "." / "^" /
  "_" / "`" / "|" / "~" / DIGIT / ALPHA`.
- Empty `Str` means "absent" unless a field or function says otherwise.

## 3. URL model (`Url`)

```xi
pub type Url = {
  scheme: Str; host: Str; port: Int; port_present: Bool;
  path: Str; query: Str; query_present: Bool;
  fragment: Str; fragment_present: Bool;
}
```

### 3.1 `curl_url_parse(s) -> Result[Url, Str]`

Absolute form only: `scheme "://" authority [ path ] [ "?" query ]
[ "#" fragment ]`.

| Step | Rule | Error |
|---|---|---|
| separator | first `://` at index >= 1 | `curl: url must be absolute (scheme://...)`; empty input: `curl: empty url` |
| scheme | 1+ bytes, first ALPHA, rest ALPHA/DIGIT/`+`/`-`/`.`; lowercased | `curl: scheme must start with a letter`, `curl: invalid scheme character at offset N` |
| authority | bytes up to the first `/`, `?` or `#` (or end) | -- |
| userinfo | any `@` in the authority | `curl: userinfo not supported` |
| IPv6 | any `[` in the authority | `curl: IPv6 literals not supported` |
| port | after the first `:`, DIGIT+ only, <= 65535; `port_present` set | `curl: empty port at offset N`, `curl: invalid port at offset N`, `curl: port out of range at offset N` |
| host | 1+ bytes of ALPHA/DIGIT/`-`/`.`/`_`; lowercased | `curl: empty host`, `curl: invalid host character at offset N` |
| path | bytes 0x21..0x7E; stored exactly as written (may be empty) | `curl: url path has invalid character at offset N` |
| query | after the first `?` up to `#`/end; bytes 0x21..0x7E | `curl: url query has invalid character at offset N` |
| fragment | after the first `#`; bytes 0x21..0x7E | `curl: url fragment has invalid character at offset N` |

A `#` terminates both path and query; a `?` inside the fragment is literal.
Percent escapes are *not* decoded at parse time (they are stored as written).
`curl_url_to_string` renders exactly as stored:
`scheme://host[:port]path[?query][#fragment]`.

### 3.2 Normalization (`curl_url_normalize`)

1. lowercase `scheme` and `host`;
2. elide the port when it equals the scheme default (http 80, https 443);
3. empty path becomes `/`;
4. `curl_url_remove_dot_segments` on the path (RFC 3986 section 5.2.4);
5. if the path becomes empty it is `/`; an empty fragment clears
   `fragment_present`.

Query text is preserved byte-for-byte; percent escapes are not re-canonicalized.

### 3.3 Reference resolution (`curl_url_resolve(base, reference)`)

| Reference form | Result |
|---|---|
| absolute (`scheme:...`) | parsed and normalized |
| network-path (`//host/...`) | base scheme + parsed reference, normalized |
| absolute-path (`/...`) | base scheme/host/port + dot-removed reference path |
| relative-path (`g`, `../g`) | base path merged at its last `/`, dot-removed |
| query-only (`?y`) | base path + reference query |
| fragment-only (`#s`) | base path + base query (if any) + reference fragment |
| empty | base normalized, fragment cleared |

Notes: the merge case takes the query from the reference; the empty-path case
keeps the base query; `#` alone yields a present-but-empty fragment before
normalization clears it. Other URI schemes are parsed but not specialized
(no mailto/file semantics).

### 3.4 Percent encoding

- `curl_percent_encode_component(s)`: one pass; `unreserved` bytes literal,
  every other byte `%` + two **uppercase** hex digits. Total; empty -> `""`.
- `curl_percent_decode_component(s)`: one pass; `%XX` (case-insensitive hex)
  becomes the byte `0xXX`; `+` stays literal; all other bytes are copied
  verbatim (so UTF-8 byte sequences survive intact).

| Error | Trigger |
|---|---|
| `curl: truncated percent escape at offset N` | input ends after `%` or one hex digit |
| `curl: bad percent escape at offset N` | `%` followed by a non-hex byte |
| `curl: percent escape decodes to NUL at offset N` | `%00` cannot live in a NUL-terminated XIOM `Str` |

Round trip: `decode(encode(x)) == Ok(x)` for every `x` without raw NUL bytes;
encode(decode(x)) == x for canonical `x`.

### 3.5 Scheme, origin and ports

- `curl_scheme_default_port(scheme)`: 80 (`http`), 443 (`https`), else 0;
  case-insensitive.
- `curl_url_effective_port(u)`: explicit port, else scheme default.
- `curl_url_same_origin(a, b)`: scheme, host and effective port all equal
  (scheme/host case-insensitive).

## 4. Request model

```xi
pub type HeaderList = { names: Vec[Str]; values: Vec[Str]; alive: Vec[Int]; }
pub type Request = {
  method: Str; url: Url; version: Str;
  headers: HeaderList; body: Str; body_present: Bool;
}
```

`alive[i]` is 1 for a live slot and 0 after removal; dead slots stay
allocated (no vector reallocation tricks). `curl_headers_consistent` and
`curl_request_consistent` verify `names.len() == values.len() == alive.len()`.

### 4.1 Methods and versions

- `curl_method_canonical(m)`: every byte must be `tchar`, then ASCII
  uppercased. Errors: `curl: empty method`,
  `curl: method has invalid character at offset N`.
- `curl_method_is_valid(m)`: non-empty tchar token, length <= 32.
- `curl_method_is_safe(m)`: GET/HEAD/OPTIONS/TRACE (case-insensitive).
- `curl_method_is_idempotent(m)`: safe plus PUT/DELETE.
- Supported versions: exactly `HTTP/1.0` and `HTTP/1.1`.
  `curl_request_new` / `curl_response_new` reject anything else with
  `curl: unsupported version: <v>`.

### 4.2 Headers

- `curl_headers_add(h, name, value)`: name is a non-empty `tchar` token;
  value bytes are HTAB (0x09) or 0x20..0x7E. Duplicates are allowed, order is
  preserved. Errors: `curl: empty header name`,
  `curl: header name has invalid character at offset N`,
  `curl: header value has invalid character at offset N`.
- `curl_headers_get(h, name)`: first live value, case-insensitive; miss ->
  `curl: header not found: <name>`.
- `curl_headers_has` is the predicate form; `curl_headers_remove` marks all
  case-insensitive matches dead and returns the count.
- `curl_headers_name_at(h, i)` / `value_at(h, i)` index **live** entries in
  order and return `""` out of range.

### 4.3 Wire encoding (`curl_request_encode`)

```
request-line = method SP target SP version CRLF
target       = path ("/" when empty) [ "?" query ]
headers      = *( name ": " value CRLF )
CRLF body?
```

Only live headers are emitted, in insertion order. No `Host` header is
synthesized and no `Content-Length` is computed: header management is the
caller's. The body is appended only when `body_present` is true (an explicitly
empty body emits nothing after the blank line).

## 5. Redirect model

| Status | Followable | Follow-up method | Body |
|---|---|---|---|
| 301, 302 | yes | POST -> GET; anything else unchanged | dropped |
| 303 | yes | HEAD -> HEAD; anything else -> GET | dropped |
| 307, 308 | yes | unchanged | kept |
| anything else | no | -- | -- |

`curl_redirect_next_method(status, method, depth, max_depth)` returns the
follow-up method or:

- `curl: status is not a redirect: <n>` for a non-followable status;
- `curl: redirect depth exceeded (max <n>)` when `depth >= max_depth`
  (`CURL_MAX_REDIRECTS` is 10).

The model resolves the `Location` value with `curl_url_resolve`; only the
method/body/depth decisions are codified here.

## 6. Cookie model

```xi
pub type Cookie = {
  name: Str; value: Str; domain: Str; path: Str; host_only: Bool;
  secure: Bool; http_only: Bool; max_age: Int; max_age_present: Bool;
  created_at: Int;
}
```

### 6.1 `curl_cookie_parse(set_cookie, host, req_path, now)`

Grammar accepted: `name "=" value *( ";" OWS attribute )`. Attributes are
case-insensitive; unknown attributes are ignored.

| Part | Rule |
|---|---|
| name | non-empty tchar token |
| value | RFC 6265 cookie-octet subset: 0x21, 0x23..0x2B, 0x2D..0x3A, 0x3C..0x5B, 0x5D..0x7E (visible ASCII except space, `"` and `,`; `;` ends the value) |
| Domain | optional leading `.` stripped, lowercased, non-empty; must domain-match `host` (exact, or host ends with `"." + domain`; IPv4-looking hosts require exact equality) |
| Path | used only when it starts with `/`; otherwise ignored |
| Max-Age | optional `-`, 1+ digits, magnitude <= 2147483647; `<= 0` means already expired |
| Secure / HttpOnly | flag attributes (a value after `=` is ignored) |
| Expires | accepted syntactically and **ignored** (no date arithmetic) |

Missing Domain -> `host_only` cookie with `domain = lower(host)`. Missing or
invalid Path -> `curl_cookie_default_path(req_path)` (RFC 6265 section 5.1.4:
`""` or no `/` -> `/`; else the text up to the last `/`). `created_at` is the
caller's `now`.

Errors: `curl: empty set-cookie`, `curl: empty cookie host`,
`curl: set-cookie must be name=value` (missing `=` or empty name),
`curl: cookie name has invalid character at offset N`,
`curl: cookie value has invalid character at offset N` (offset absolute into
`set_cookie`), `curl: empty cookie domain`,
`curl: cookie domain does not match host: <d>`, `curl: invalid Max-Age`.

### 6.2 Matching and rendering

- `curl_cookie_domain_match`: host-only -> exact case-insensitive equality;
  Domain cookie -> suffix rule of 6.1.
- `curl_cookie_path_match` (RFC 6265 5.1.4): exact, or prefix ending at a `/`
  boundary.
- `curl_cookie_is_expired(c, now)`: false without Max-Age; true when
  `max_age <= 0` or `now >= created_at + max_age`.
- `curl_cookie_matches` = domain + path + not expired.
- `curl_cookie_sendable` = matches + (`Secure` requires scheme `https`).
- `curl_cookie_to_string`:
  `name=value[; Domain=d][; Path=p][; Max-Age=n][; Secure][; HttpOnly]`.

### 6.3 Cookie jar (`CookieJar`)

Eleven parallel vectors (`names`, `values`, `domains`, `paths`, `host_only`,
`secure`, `http_only`, `max_ages`, `max_age_present`, `created`, `alive`) with
`curl_jar_consistent` as the drift guard. Flag vectors store 0/1 Ints.

- `curl_jar_add(j, c)`: appends; a live cookie with the same name
  (case-sensitive), domain (case-insensitive) and path (case-sensitive) is
  marked dead first, so replacement moves the cookie to the end of the
  iteration order.
- `curl_jar_remove_expired(j, now)`: marks expired live cookies dead, returns
  the count. `curl_jar_clear` marks all dead. `curl_jar_count` counts live
  entries; `curl_jar_slots` counts physical slots.
- `_at(j, i)` accessors are physical-index reads and return `""`/0/false for
  a dead or out-of-range slot (callers can gate with `curl_jar_alive_at`).
- `curl_jar_cookie_header(j, host, path, scheme, now)`: live, sendable
  cookies in slot order joined with `"; "`; `""` when none.

## 7. Auth helpers

- `curl_auth_basic_header(user, password)`: `user` bytes 0x20..0x7E except
  `:`, `password` bytes 0x20..0x7E; both empty allowed. Produces
  `"Basic " + base64(user + ":" + password)` (stdlib
  `xiom.encoding.base64`). Errors: `curl: basic user has invalid character at
  offset N`, `curl: basic password has invalid character at offset N`.
- `curl_auth_bearer_header(token)`: non-empty visible ASCII with no
  whitespace: `"Bearer " + token`. Errors: `curl: empty token`,
  `curl: token has invalid character at offset N`.
- `curl_auth_scheme(h)`: bytes before the first SP/HTAB; `curl_auth_token(h)`:
  the remainder with surrounding OWS trimmed.
- `curl_auth_header_is_basic` / `is_bearer`: scheme equality,
  case-insensitive.
- `curl_auth_basic_decode(h)`: Basic scheme required
  (`curl: not a Basic authorization header`), then stdlib base64 decode of
  the token (`curl: basic credentials are not valid base64` on failure).
- `curl_auth_basic_user` / `curl_auth_basic_password`: split at the first
  `:`; no colon -> the whole string is the user and the password is `""`.

## 8. Retry policy

```xi
pub type RetryPolicy = {
  max_attempts: Int; base_delay_ms: Int; max_delay_ms: Int;
  retry_5xx: Int; retry_429: Int; retry_408: Int; honor_retry_after: Int;
}
```

`curl_retry_default()` = `{3, 200, 10000, 1, 1, 1, 1}`. Flags are 1/0.

- `curl_retry_status_retryable(p, status)`: 408 when `retry_408`, 429 when
  `retry_429`, 500..599 when `retry_5xx`.
- `curl_retry_should_retry(p, status, attempt)`: attempt 1-based; false when
  `attempt < 1` or `attempt >= max_attempts`, else the status decision.
- `curl_retry_delay_ms(p, attempt)`: `attempt <= 0` -> 0; else
  `min(base * 2^(attempt-1), max_delay_ms)` computed with a bounded loop, no
  jitter, no randomness.
- `curl_retry_parse_retry_after(s)`: DIGIT+ only, value <= 2147483647;
  otherwise `curl: unsupported Retry-After value: <v>` (the HTTP-date form is
  a documented non-goal).
- `curl_retry_effective_delay(p, attempt, retry_after, present)`: backoff,
  raised to `retry_after` when `present && honor_retry_after == 1`.

## 9. Connection-pool model

```xi
pub type Pool = {
  schemes: Vec[Str]; hosts: Vec[Str]; ports: Vec[Int];
  idle: Vec[Int]; active: Vec[Int];
  max_idle_per_host: Int; max_total: Int;
}
```

One slot per (scheme, host, port) key (scheme/host compared
case-insensitively). `curl_pool_consistent` checks vector alignment.

- `curl_pool_acquire(p, scheme, host, port)` -> **1** when an idle connection
  is reused (idle--, active++), **0** when a new connection starts (new slot
  when the key is unknown), **-1** when a new connection would exceed
  `max_total` (`max_total > 0`; `<= 0` means unbounded).
- `curl_pool_release(p, scheme, host, port)` -> active-- (never below zero),
  then **1** when kept alive as idle (idle < `max_idle_per_host`), **0**
  otherwise or for an unknown key.
- `curl_pool_idle` / `curl_pool_active` per key (-1 unknown),
  `curl_pool_idle_total`, `curl_pool_active_total`, `curl_pool_total`,
  `curl_pool_slot_count`, `curl_pool_keep_alive` (whether a release would
  keep the connection), `curl_pool_close_idle` (zeroes idle, returns closed).

## 10. Response model

```xi
pub type Response = { version: Str; status: Int; reason: Str;
                      headers: HeaderList; body: Str; }
```

### 10.1 Builder and encoder

`curl_response_new(version, status, reason)`: version must be supported,
status 100..599, reason bytes HTAB or 0x20..0x7E. Errors:
`curl: unsupported version: <v>`, `curl: invalid status: <n>`,
`curl: reason has invalid character at offset N`. Headers use the same
validation and accessors as requests (`curl_response_add_header`,
`remove_header`, `header_get`, `headers_count`, `header_name_at`,
`header_value_at`, `consistent`).

`curl_response_encode` emits `version SP status SP reason CRLF`, live headers
in order, CRLF, body.

### 10.2 `curl_response_parse(text)`

```
status-line = "HTTP/1.0" | "HTTP/1.1" SP 3DIGIT [ SP reason ] CRLF
*( name ":" OWS value CRLF )
CRLF body?
```

- The first CRLF must exist; the status must be exactly three digits in
  100..599; the reason is kept verbatim (internal spacing preserved).
- Header values are trimmed of leading/trailing SP/HTAB; header folding
  (a line starting with SP/HTAB) is rejected; non-ASCII bytes are rejected.
- The body is everything after the first empty CRLF line; with no empty line
  the body is `""`.

Errors: `curl: response status line malformed`,
`curl: unsupported version: <v>`, `curl: invalid status` /
`curl: invalid status: <n>`, `curl: reason has invalid character at offset N`,
`curl: header line malformed at offset N`,
`curl: header folding not supported at offset N`, plus the header
name/value validation errors.

### 10.3 Connection semantics

- `curl_response_is_keep_alive`: first live `Connection` value decides
  (`close` -> false, `keep-alive` -> true); otherwise HTTP/1.1 -> true,
  HTTP/1.0 -> false. Only the first value is consulted (no comma-list
  splitting).
- `curl_response_reusable`: alias of the keep-alive decision.
- `curl_response_content_length`: first live `Content-Length`, DIGIT+,
  <= 2147483647; `curl: header not found: Content-Length` or
  `curl: invalid Content-Length`.
- `curl_response_body_len`: body byte length.

## 11. Status and envelope classification

- `curl_status_class(status)`: `status / 100` for 100..599, else 0.
- `curl_status_is_informational/success/redirect/client_error/server_error`.
- `curl_status_is_retryable(status)`: 408, 429, 500, 502, 503, 504.
- `curl_status_class_name(status)`: `"informational"`, `"success"`,
  `"redirect"`, `"client error"`, `"server error"`, `"unknown"`.
- `curl_envelope_class(status)`: `CURL_ENV_NONE` (0) or
  `CURL_ENV_INFORMATIONAL/SUCCESS/REDIRECT/CLIENT_ERROR/SERVER_ERROR`
  (1..5); `curl_envelope_name(kind)` and `curl_response_envelope(r)`.

Constants: `CURL_DEFAULT_PORT_HTTP` (80), `CURL_DEFAULT_PORT_HTTPS` (443),
`CURL_MAX_REDIRECTS` (10), `CURL_ENV_*` (0..5).

## 12. Complete error catalog

Every message begins with `curl: ` and is stable API.

| Message | Raised by |
|---|---|
| `curl: empty url` | url parse |
| `curl: url must be absolute (scheme://...)` | url parse |
| `curl: empty scheme` | scheme validation |
| `curl: scheme must start with a letter` | scheme validation |
| `curl: invalid scheme character at offset N` | scheme validation |
| `curl: empty host` | url parse |
| `curl: invalid host character at offset N` | url parse |
| `curl: empty port at offset N` | url parse |
| `curl: invalid port at offset N` | url parse |
| `curl: port out of range at offset N` | url parse |
| `curl: userinfo not supported` | url parse |
| `curl: IPv6 literals not supported` | url parse |
| `curl: url path has invalid character at offset N` | url parse |
| `curl: url query has invalid character at offset N` | url parse |
| `curl: url fragment has invalid character at offset N` | url parse |
| `curl: truncated percent escape at offset N` | percent decode |
| `curl: bad percent escape at offset N` | percent decode |
| `curl: percent escape decodes to NUL at offset N` | percent decode |
| `curl: empty method` | method canonical |
| `curl: method has invalid character at offset N` | method canonical |
| `curl: unsupported version: <v>` | request/response build, response parse |
| `curl: empty header name` | header add, request/response parse |
| `curl: header name has invalid character at offset N` | header add, response parse |
| `curl: header value has invalid character at offset N` | header add, response parse |
| `curl: header not found: <name>` | header/Content-Length get |
| `curl: status is not a redirect: <n>` | redirect next |
| `curl: redirect depth exceeded (max <n>)` | redirect next |
| `curl: empty set-cookie` | cookie parse |
| `curl: empty cookie host` | cookie parse |
| `curl: set-cookie must be name=value` | cookie parse |
| `curl: cookie name has invalid character at offset N` | cookie parse |
| `curl: cookie value has invalid character at offset N` | cookie parse |
| `curl: empty cookie domain` | cookie parse |
| `curl: cookie domain does not match host: <d>` | cookie parse |
| `curl: invalid Max-Age` | cookie parse |
| `curl: empty token` | bearer header |
| `curl: token has invalid character at offset N` | bearer header |
| `curl: basic user has invalid character at offset N` | basic header |
| `curl: basic password has invalid character at offset N` | basic header |
| `curl: not a Basic authorization header` | basic decode |
| `curl: basic credentials are not valid base64` | basic decode |
| `curl: unsupported Retry-After value: <v>` | retry parse |
| `curl: response status line malformed` | response parse |
| `curl: header line malformed at offset N` | response parse |
| `curl: header folding not supported at offset N` | response parse |
| `curl: invalid status` / `curl: invalid status: <n>` | response build/parse |
| `curl: reason has invalid character at offset N` | response build/parse |
| `curl: invalid Content-Length` | content-length accessor |

Functions that validate return `Ok("")` on success (`curl_headers_add`,
`curl_method_canonical`, checks), `Ok(value)` for value-returning ones, and
`Ok(0)`/`Ok(v)` for Int results.

## 13. API contract

| Function group | Errors | Complexity |
|---|---|---|
| `curl_url_parse` / `curl_url_resolve` | section 3 | O(total text) |
| `curl_url_normalize` / `curl_url_remove_dot_segments` / `curl_url_to_string` | none | O(path) |
| `curl_percent_encode_component` | none (total) | O(n) |
| `curl_percent_decode_component` | section 3.4 | O(n) |
| `curl_headers_*` | add/get only | O(headers) |
| `curl_method_*`, `curl_version_*` | canonical only | O(method) |
| `curl_request_*` | new/add | O(headers) + O(body) |
| `curl_redirect_*` | next | O(method) |
| `curl_cookie_parse` | section 6.1 | O(set-cookie) |
| `curl_cookie_*` predicates | none | O(host/path) |
| `curl_jar_*` | none | O(cookies) per accessor/header |
| `curl_auth_*` | builders/decode | O(input) |
| `curl_retry_*` | parse only | O(attempt) / O(input) |
| `curl_pool_*` | none | O(slots) |
| `curl_response_new/encode/accessors` | new only | O(headers) + O(body) |
| `curl_response_parse` | section 10.2 | O(text) |
| `curl_status_*`, `curl_envelope_*` | none | O(1) |

Determinism guarantees: no randomness (retry has no jitter), no clock, no
global mutable state; every function returns the same result for the same
arguments. Round-trip guarantees pinned by the suite:

- `curl_percent_decode_component(curl_percent_encode_component(x)) == Ok(x)`
  for ASCII, UTF-8 and reserved-character inputs (NUL excluded by design).
- `curl_url_to_string(curl_url_normalize(u))` is canonical for
  lowercase/default-port/empty-path/dot-segment inputs.
- `parse(curl_cookie_to_string(c))` reproduces the cookie's fields (same
  host/path/clock context).
- `curl_request_encode` / `curl_response_encode` produce the pinned CRLF
  byte sequences.
- `curl_auth_basic_decode(curl_auth_basic_header(u, p)) == Ok(u + ":" + p)`.

## 14. Test matrix

`tests/test_conformance.xi` (module `curl_tests`) runs 26 named checks, one
`fn` per check, through `assert(cond, "name")`; `main` prints `[PASS]`/`[FAIL]`
and returns the failure count (0 = green).

| # | Check | Semantics pinned |
|---|---|---|
| t1 | url parse fields | scheme/host lowercasing, explicit port, path/query/fragment, to_string |
| t2 | url parse default port | absent port, effective port, no-path form |
| t3 | url parse error catalog | 12 error prefixes with offsets |
| t4 | percent encode | unreserved literal, space `%20`, reserved set, UTF-8 bytes |
| t5 | percent decode errors | decode, lowercase hex, truncated/bad/NUL offsets |
| t6 | url normalize | default-port elision, dot segments, empty path, empty fragment |
| t7 | dot segment removal | RFC 5.2.4 vectors |
| t8 | url resolve | 8 RFC 3986 reference forms incl. `//g` and absolute |
| t9 | same origin | default-port equivalence, scheme/port mismatch |
| t10 | method canonical | uppercase, token validation, safe/idempotent predicates |
| t11 | headers add and lookup | order, duplicates, ci get, remove, drift guard, errors |
| t12 | request build and encode | canonical method, target, exact CRLF wire, version error |
| t13 | redirect method rewriting | 301/302/303/307/308 rules and body rule |
| t14 | redirect depth and errors | depth bound, non-redirect status, default limit |
| t15 | cookie parse attributes | Domain/Path/Max-Age/Secure/HttpOnly, defaults |
| t16 | cookie parse error catalog | 7 errors with offsets, default paths |
| t17 | cookie matching and expiry | domain/path rules, host-only, Secure, Max-Age boundaries |
| t18 | cookie render and round-trip | deterministic Set-Cookie text, parse(to_string) |
| t19 | cookie jar | add/replace, expiry removal, header building, secure filtering |
| t20 | auth basic and bearer | pinned base64, decode/split, scheme predicates, errors |
| t21 | retry policy | defaults, status/attempt decisions, backoff cap, Retry-After |
| t22 | connection pool accounting | reuse, keep-alive cap, max_total refuse, close_idle |
| t23 | response build and encode | validations, headers, body, Content-Length, wire |
| t24 | response parse | fields, keep-alive variants, 6 parse errors |
| t25 | status and envelope classification | classes, predicates, names, constants |
| t26 | accessors and version | method/version accessors, body presence, constants |

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom-curl -TimeoutSec 60
```

Last verified: compiler 0.62.2,
`port: PASS (passed=26 failed=0 program_exit=0 exit=0)` (port x2).

## 15. Compiler / stdlib notes (v0.62.2)

- Free functions only; no methods, no lambdas, no `match` in the library, no
  `Vec[StructType]` and no `Vec[Float64]`; header lists, jars and pools use
  parallel `Vec` fields pushed together in single functions, with
  `*_consistent` drift guards.
- `Ok`/`Err` construction for every `Result` type is confined to the leaf
  helpers `_c_ok_*` / `_c_err_*`.
- Every byte read from a `Str` or `Vec[UInt8]` is widened once with
  `(byte_at(..) as Int) & 0xFF` before comparison or arithmetic; widened
  constants (e.g. `%`) are compared as Ints.
- No `Str` value is compared with `==`; equality goes through
  `xiom.string.compare.str_compare` / `str_eq_ignore_case`, and `Str` values
  read out of structs, `Vec[Str]` or `Result` fields are bound to typed
  locals first. `&struct.field` is bound to a local before it reaches a
  `&HeaderList` parameter.
- `&mut` write-through is used only for `Vec` pushes and `Vec` element writes
  inside `&mut` struct parameters (`alive[i] = 0`, `idle[idx] = ...`); there
  are no `&mut Int` out-parameters.
- Every scan loop is bounded by the input length with a single advancing
  counter; no `break`/`continue`; `xiom.string.builder` output is never fed a
  NUL byte (percent NUL escapes are rejected and cookie/header validation is
  ASCII-only).
- `xiom.encoding.base64` is reused for Basic auth (`base64_encode_str` /
  `base64_decode_str`). Percent encoding is implemented in-module instead of
  delegating to `xiom.encoding.percent` because URL parsing needs byte-exact
  offsets in decode errors, a NUL-escape guard and byte-wise (not
  code-point-wise) encoding of raw slices.

## 16. Known limitations

- No transport, TLS, DNS, proxies, HTTP/2, chunked decoding or streaming.
- No request parsing (builder/encoder only); no form/multipart bodies.
- No date arithmetic: cookie `Expires` is accepted and ignored; expiry is
  Max-Age-only.
- No public-suffix list; Domain matching is the RFC 6265 suffix rule with an
  IPv4-exact special case.
- No `SameSite`/`Priority`/`Partitioned` cookie attributes.
- Userinfo and IPv6 URL literals are rejected; percent escapes are not
  decoded or re-canonicalized during URL parsing.
- `Connection` handling reads only the first header value (no comma lists);
  keep-alive accounting is a model, not a live socket pool.
- Retry policy returns delays; it never sleeps or schedules.
- No global state; thread-safety is the caller's concern.
