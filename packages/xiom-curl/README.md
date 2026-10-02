# xiom.curl

> **Status:** `incubating` -- conformance-tested (26/26); not yet published.
> **Scope:** a pure HTTP client **model**: URL parsing/normalization, request
> and response envelopes, redirect semantics, cookies, auth header shapes,
> retry policy and keep-alive pool accounting. No sockets, no FFI, no TLS.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string`,
> `xiom.string.builder`, `xiom.string.compare`, `xiom.convert` and
> `xiom.encoding.base64`). Tests additionally use `xiom.test` and `xiom.io`.

## What it is

`xiom.curl` models the deterministic parts of an HTTP exchange so a caller
can drive its own transport (or a test harness) with well-typed, validated
data. It never opens a socket, never resolves DNS, never negotiates TLS, and
never blocks.

- **URL model** -- absolute-URL lexical parsing (scheme / host / port / path /
  query / fragment), RFC 3986 normalization (lowercasing, default-port
  elision, dot-segment removal), reference resolution (absolute,
  network-path, absolute-path, relative-path, query-only, fragment-only,
  empty) and RFC 3986 percent encoding with a byte offset on every decode
  error.
- **Request model** -- method canonicalization and safe/idempotent
  predicates, an ordered header list with case-insensitive lookup, explicit
  body presence, an origin-form target and a deterministic wire encoder
  (CRLF; no Host header is synthesized for you).
- **Redirect model** -- 301/302/303/307/308 followability, method rewriting
  (303 -> GET except HEAD; 301/302 POST -> GET; 307/308 unchanged), the
  body-retention rule and a bounded depth with a stable error.
- **Cookie model** -- a Set-Cookie subset (`name=value` plus `Domain`,
  `Path`, `Max-Age`, `Secure`, `HttpOnly`; `Expires` accepted and ignored),
  RFC 6265 domain/path matching, Max-Age expiry, a parallel-vector jar with
  replacement and expiry removal, and a `Cookie:` header value builder.
- **Auth helpers** -- HTTP Basic (stdlib base64) and Bearer header shapes,
  scheme detection, Basic decode and `user:password` splitting.
- **Retry policy** -- deterministic exponential backoff with a cap, status
  classification (408/429/5xx flags), delta-seconds `Retry-After` parsing and
  effective-delay selection.
- **Connection pool model** -- keep-alive accounting per
  (scheme, host, port) slot with `max_idle_per_host` and `max_total` bounds.
- **Response model** -- builder, header list, keep-alive decision,
  `Content-Length` accessor, a bounded response-head parser and HTTP
  status/envelope classification.

## Install

```
xiom pkg install xiom.curl@0.1.0
```

## Quick start

```xi
use xiom.curl;
use xiom.io;

fn main() -> Int {
  // Parse and normalize a URL.
  let p = curl_url_parse("HTTP://Example.COM:80/a/./b?q=1#f");
  if !p.is_ok { io.println(p.error); return 1; }
  let u: Url = p.value;
  let nu = curl_url_normalize(&u);
  io.println(curl_url_to_string(&nu));   // http://example.com/a/b?q=1#f

  // Build a request, add headers and a body, then encode it.
  let rq = curl_request_new("post", nu, "HTTP/1.1");
  if !rq.is_ok { io.println(rq.error); return 1; }
  var req: Request = rq.value;
  let h = curl_request_add_header(&mut req, "Content-Type", "text/plain");
  if !h.is_ok { io.println(h.error); return 1; }
  curl_request_set_body(&mut req, "hello");
  io.println(curl_request_encode(&req));

  // Parse a Set-Cookie header into the jar; build the Cookie header later.
  var jar = curl_jar_new();
  let c = curl_cookie_parse("sid=abc; Domain=example.com; Path=/; Max-Age=3600",
                            "www.example.com", "/", 0);
  if !c.is_ok { io.println(c.error); return 1; }
  curl_jar_add(&mut jar, &c.value);
  io.println(curl_jar_cookie_header(&jar, "www.example.com", "/", "https", 10)); // sid=abc

  // Redirect step and retry policy are pure decisions.
  let step = curl_redirect_next_method(302, "POST", 0, CURL_MAX_REDIRECTS);
  if step.is_ok { io.println(step.value); }   // GET
  let pol = curl_retry_default();
  io.println(curl_retry_effective_delay(&pol, 2, 0, false));  // 400 (ms)
  return 0;
}
```

## API

**URL, normalization and percent encoding**

| Function | Returns | Description |
|---|---|---|
| `curl_url_parse(s)` | `Result[Url, Str]` | Absolute URL lexical parse; scheme/host lowercased. |
| `curl_url_to_string(u)` | `Str` | Render exactly as stored. |
| `curl_url_normalize(u)` | `Url` | Lowercase, elide default port, empty path -> `/`, dot-segment removal, drop empty fragment. |
| `curl_url_remove_dot_segments(p)` | `Str` | RFC 3986 section 5.2.4. |
| `curl_url_resolve(base, ref)` | `Result[Url, Str]` | RFC 3986 section 5.2 subset; result normalized. |
| `curl_url_effective_port(u)` | `Int` | Explicit port or scheme default (0 unknown). |
| `curl_url_same_origin(a, b)` | `Bool` | Scheme + host + effective port equality. |
| `curl_scheme_default_port(scheme)` | `Int` | 80 http, 443 https, else 0. |
| `curl_percent_encode_component(s)` | `Str` | Unreserved literal; every other byte `%XX` uppercase. |
| `curl_percent_decode_component(s)` | `Result[Str, Str]` | `%XX` decoded; `+` literal; NUL escapes rejected. |

`Url` fields: `scheme`, `host`, `port`, `port_present`, `path`, `query`,
`query_present`, `fragment`, `fragment_present`.

**Headers, requests, redirects**

| Function | Returns | Description |
|---|---|---|
| `curl_headers_new()` | `HeaderList` | Empty ordered header list. |
| `curl_headers_add(h, name, value)` | `Result[Str, Str]` | Token name + visible-ASCII value; duplicates allowed. |
| `curl_headers_get(h, name)` | `Result[Str, Str]` | First value, case-insensitive. |
| `curl_headers_has(h, name)` / `count` / `name_at` / `value_at` | `Bool` / `Int` / `Str` | Ordered accessors. |
| `curl_headers_remove(h, name)` | `Int` | Marks matching slots dead; returns removed count. |
| `curl_headers_consistent(h)` | `Bool` | Parallel-vector drift guard. |
| `curl_method_canonical(m)` | `Result[Str, Str]` | Token validation + uppercase. |
| `curl_method_is_valid` / `is_safe` / `is_idempotent` | `Bool` | Method predicates. |
| `curl_version_is_supported(v)` | `Bool` | `HTTP/1.0`, `HTTP/1.1`. |
| `curl_request_new(method, url, version)` | `Result[Request, Str]` | Validated builder. |
| `curl_request_add_header` / `remove_header` / `header_get` | see above | Header operations on a request. |
| `curl_request_set_body` / `clear_body` / `has_body` / `body` / `body_len` | -- | Body presence is explicit. |
| `curl_request_target(r)` | `Str` | Origin-form path + query. |
| `curl_request_encode(r)` | `Str` | Request line + live headers + blank line + body. |
| `curl_redirect_is_followable(status)` | `Bool` | 301/302/303/307/308. |
| `curl_redirect_rewrite_method(status, method)` | `Str` | Method-rewrite rules. |
| `curl_redirect_keeps_body(status)` | `Bool` | True only for 307/308. |
| `curl_redirect_next_method(status, method, depth, max_depth)` | `Result[Str, Str]` | One bounded redirect step. |

**Cookies, auth, retry, pool, response**

| Function | Returns | Description |
|---|---|---|
| `curl_cookie_parse(set_cookie, host, req_path, now)` | `Result[Cookie, Str]` | Set-Cookie subset; `now` is the caller's clock (seconds). |
| `curl_cookie_default_path(req_path)` | `Str` | RFC 6265 section 5.1.4 default. |
| `curl_cookie_domain_match` / `path_match` / `is_expired` / `matches` / `sendable` | `Bool` | RFC 6265 matching; `sendable` adds the Secure/https rule. |
| `curl_cookie_to_string(c)` | `Str` | Deterministic Set-Cookie rendering. |
| `curl_jar_new()` | `CookieJar` | Empty parallel-vector jar. |
| `curl_jar_add(j, c)` | -- | Appends; replaces the same (name, domain, path). |
| `curl_jar_remove_expired(j, now)` / `clear(j)` / `count(j)` | `Int` / `--` / `Int` | Jar maintenance and accounting. |
| `curl_jar_cookie_header(j, host, path, scheme, now)` | `Str` | `name=value` pairs joined with `; `; `""` when none. |
| `curl_auth_basic_header(user, password)` | `Result[Str, Str]` | `Basic <base64(user:password)>`. |
| `curl_auth_bearer_header(token)` | `Result[Str, Str]` | `Bearer <token>`. |
| `curl_auth_scheme(h)` / `curl_auth_token(h)` | `Str` | Authorization value split. |
| `curl_auth_header_is_basic` / `is_bearer` | `Bool` | Scheme predicates (case-insensitive). |
| `curl_auth_basic_decode(h)` | `Result[Str, Str]` | Basic value -> `user:password`. |
| `curl_auth_basic_user` / `password(creds)` | `Str` | Credential split at the first `:`. |
| `curl_retry_default()` | `RetryPolicy` | 3 attempts, 200 ms base, 10 s cap, honor Retry-After. |
| `curl_retry_status_retryable` / `should_retry` | `Bool` | Status/attempt decisions. |
| `curl_retry_delay_ms(p, attempt)` | `Int` | base * 2^(attempt-1), capped; no jitter. |
| `curl_retry_parse_retry_after(s)` | `Result[Int, Str]` | Delta-seconds only (HTTP-date unsupported). |
| `curl_retry_effective_delay(p, attempt, retry_after, present)` | `Int` | max(backoff, Retry-After) when honored. |
| `curl_pool_new(max_idle_per_host, max_total)` | `Pool` | Empty pool; `max_total <= 0` unbounded. |
| `curl_pool_acquire(p, scheme, host, port)` | `Int` | 1 reused, 0 new, -1 refused at max_total. |
| `curl_pool_release(p, scheme, host, port)` | `Int` | 1 kept alive, 0 closed. |
| `curl_pool_idle` / `active` / `keep_alive` / totals | `Int` / `Bool` | Accounting accessors. |
| `curl_pool_close_idle(p)` | `Int` | Drops idle connections; returns closed count. |
| `curl_response_new(version, status, reason)` | `Result[Response, Str]` | Validated builder. |
| `curl_response_parse(text)` | `Result[Response, Str]` | Status line + CRLF headers + optional body. |
| `curl_response_encode(r)` | `Str` | Deterministic head encoder. |
| `curl_response_header_get` / `add_header` / `remove_header` | see above | Header operations on a response. |
| `curl_response_is_keep_alive` / `reusable` | `Bool` | Connection reuse decision. |
| `curl_response_content_length(r)` | `Result[Int, Str]` | First live Content-Length. |
| `curl_status_class` / `is_success` / `is_redirect` / `is_retryable` / `class_name` | `Int` / `Bool` / `Str` | Status classification. |
| `curl_envelope_class` / `envelope_name` / `response_envelope` | `Int` / `Str` | Envelope classification (`CURL_ENV_*`). |
| `curl_version()` | `Str` | `"0.1.0"`. |

All functions are free functions and total where documented. Header lists,
cookie jars and pools use parallel `Vec` fields: every push goes to all
sibling vectors in the same function, and `*_consistent` guards drift.

## Error model

Every error message starts with `curl: ` and is stable API. Structural
violations found while parsing text carry the byte offset of the first
violation (`... at offset N`); for cookie values the offset is absolute into
the Set-Cookie header, for percent escapes and URLs it is into the string
being parsed. Representative messages -- the complete catalog lives in
`SPEC.md`:

| Message | Trigger |
|---|---|
| `curl: url must be absolute (scheme://...)` | missing scheme separator. |
| `curl: empty host` / `invalid host character at offset N` | authority host validation. |
| `curl: invalid port at offset N` / `port out of range at offset N` | non-decimal / > 65535. |
| `curl: userinfo not supported` / `IPv6 literals not supported` | documented non-goals. |
| `curl: url path/query/fragment has invalid character at offset N` | byte < 0x21 or > 0x7E. |
| `curl: truncated/bad percent escape at offset N` | malformed `%XX`. |
| `curl: percent escape decodes to NUL at offset N` | `%00` cannot live in a `Str`. |
| `curl: empty method` / `method has invalid character at offset N` | method token. |
| `curl: unsupported version: <v>` | not `HTTP/1.0`/`HTTP/1.1`. |
| `curl: empty header name` / `header name|value has invalid character at offset N` | header validation. |
| `curl: header not found: <name>` | accessor miss. |
| `curl: status is not a redirect: <n>` / `curl: redirect depth exceeded (max <n>)` | redirect step. |
| `curl: empty set-cookie` / `set-cookie must be name=value` | cookie pair. |
| `curl: cookie name|value has invalid character at offset N` | cookie octets. |
| `curl: cookie domain does not match host: <d>` / `empty cookie domain` | Domain attribute. |
| `curl: invalid Max-Age` | not a bounded decimal. |
| `curl: empty token` / `token has invalid character at offset N` | Bearer token. |
| `curl: basic user|password has invalid character at offset N` | Basic credentials. |
| `curl: not a Basic authorization header` / `basic credentials are not valid base64` | Basic decode. |
| `curl: unsupported Retry-After value: <v>` | HTTP-date form or non-digits. |
| `curl: response status line malformed` / `header line malformed at offset N` | response parse. |
| `curl: header folding not supported at offset N` | obs-fold header. |
| `curl: invalid status[: <n>]` / `reason has invalid character at offset N` | status/reason. |
| `curl: invalid Content-Length` | non-decimal or overflow. |

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom-curl -TimeoutSec 60
```

Expected tail: 26 `[PASS]` lines, `xiom.curl: all tests passed`, then
`port: PASS (passed=26 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No transport.** No sockets, DNS, TLS, proxies, HTTP/2, chunked transfer
  decoding or streaming; the caller owns bytes on the wire.
- **HTTP/1.0 and HTTP/1.1 only** in the validated model. HTTP/2 is a
  non-goal; its frames are not modeled.
- **No request parser.** The request model is a builder/encoder; parsing
  inbound requests (a server concern) is out of scope.
- **No date arithmetic.** Cookie `Expires` is accepted and ignored; expiry
  is Max-Age-only and computed against the caller's clock.
- **Cookie subset.** No public-suffix list, no `SameSite`/`Priority`, no
  attribute-value validation beyond the octet subset; userinfo and IPv6 URL
  literals are rejected.
- **Percent normalization is minimal.** Parsing validates raw bytes but does
  not decode/renormalize existing `%XX` sequences; query text is preserved
  as written.
- **Retry is deterministic.** No jitter, no wall-clock scheduling; the
  caller applies the returned delay.
- **Whole-buffer, stateless.** No global state; thread-safety is the
  caller's concern.

See `SPEC.md` for the exact subset, the complete error catalog and the test
matrix. License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
