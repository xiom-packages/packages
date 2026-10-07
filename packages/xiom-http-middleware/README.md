# xiom.http.middleware

> **Status:** `incubating` -- conformance-tested (22/22); not yet published to the XIOM registry.
> **Scope:** pure-XIOM, stdlib-only, envelope-agnostic HTTP middleware helpers:
> request-id generation/validation, access-log lines, CORS header lines,
> CSRF token generation and constant-time validation, escaped JSON error
> bodies and their content type.
> **Deps:** `xiom.std` only (`xiom.crypto`, `xiom.string`; the tests add
> `xiom.test` and `xiom.io`).

## What it is

`xiom.http.middleware` is a small, deterministic helper module that an HTTP
envelope (or a router package such as `xiom.router`) composes over its own
request/response types. It owns no envelope, no transport and no global
state: every function takes and returns plain values, so the caller decides
where request ids live, how headers travel, what `duration_ms` measures, and
where log lines go.

- **Request ids** -- `middleware_request_id_new` returns 32 lowercase hex
  chars (16 CSPRNG bytes from `xiom.crypto`); `middleware_request_id_valid`
  checks the exact shape (length 32, charset `[0-9a-f]`).
- **Access log** -- `middleware_access_log_line` renders the exact
  single-line format `request_id=<id> method=<M> path=<p> status=<s>
  duration_ms=<d> bytes=<b>`. Fields are not escaped, so `path` must not
  contain spaces.
- **CORS** -- `middleware_cors_headers` returns complete `Name: value`
  header lines in fixed order, skipping empty values and non-positive
  Max-Age; `*` is passed through as-is.
- **CSRF** -- `middleware_csrf_token_new` mints 32-hex tokens;
  `middleware_csrf_valid` is a constant-time comparison over raw bytes
  (`xiom.crypto.constant_time_compare`) that is false for empty or
  different-length inputs.
- **Error bodies** -- `middleware_error_body` produces
  `{"error":{"status":<status>,"message":"<escaped>"}}` with minimal JSON
  string escaping (`\`, `"`, LF, CR, TAB); `middleware_error_content_type`
  returns `application/json`.

The package is deliberately transport-free: no sockets, no request parsing,
no clocks, no file or network I/O, no FFI.

## Install / use

```
xiom pkg install xiom.http.middleware@0.1.0
```

```xi
use xiom.http.middleware;
use xiom.io;

let idr = middleware_request_id_new();
if idr.is_ok {
  let id: Str = idr.value;
  let line = middleware_access_log_line(id, "GET", "/users", 200, 12, 345);
  io.println(line);
}

let cors = middleware_cors_headers("https://app.example", "GET, POST", "Content-Type", 600);
// ["Access-Control-Allow-Origin: https://app.example",
//  "Access-Control-Allow-Methods: GET, POST",
//  "Access-Control-Allow-Headers: Content-Type",
//  "Access-Control-Max-Age: 600"]

let tokr = middleware_csrf_token_new();
if tokr.is_ok {
  let token: Str = tokr.value;
  // later: middleware_csrf_valid(token_from_request, token)
}

let body = middleware_error_body(404, "not found");
// {"error":{"status":404,"message":"not found"}}
```

## API

| Function | Returns | Description |
|---|---|---|
| `middleware_request_id_new()` | `Result[Str, Str]` | New 32-char lowercase hex request id from 16 CSPRNG bytes. `Err("middleware: id generation failed")` only if the byte vector is not 16. |
| `middleware_request_id_valid(id)` | `Bool` | True when `id` is exactly 32 chars of lowercase hex (`[0-9a-f]`). Uppercase hex is invalid. |
| `middleware_access_log_line(request_id, method, path, status, duration_ms, bytes)` | `Str` | Exact line `request_id=<id> method=<M> path=<p> status=<s> duration_ms=<d> bytes=<b>`; single spaces, no escaping, so `path` must not contain spaces. |
| `middleware_cors_headers(allow_origin, allow_methods, allow_headers, max_age_secs)` | `Vec[Str]` | Complete CORS header lines in fixed order; empty values are skipped; `max_age_secs <= 0` skips Max-Age; `*` passes through. |
| `middleware_csrf_token_new()` | `Result[Str, Str]` | New 32-char lowercase hex CSRF token (same generation shape as request ids, separate function). |
| `middleware_csrf_valid(token, expected)` | `Bool` | Constant-time check; false when either is empty or lengths differ. |
| `middleware_error_body(status, message)` | `Str` | Exact JSON `{"error":{"status":<status>,"message":"<escaped message>"}}`. |
| `middleware_error_content_type()` | `Str` | The literal `application/json`. |

## Behavior notes

### Request ids and CSRF tokens

Both generators draw 16 bytes from `xiom.crypto.secure_random_bytes` and
render them as lowercase hex, so every id/token is exactly 32 chars from
`[0-9a-f]`. Their `Err` arms fire only when the CSPRNG does not return
exactly 16 bytes, which has not been observed on supported platforms.
`middleware_request_id_valid` validates shape only -- it cannot prove an id
came from this module -- and is strict about case: `A-F` is rejected.

`middleware_csrf_valid` is false for empty inputs or different lengths and
otherwise compares the raw byte vectors with
`xiom.crypto.constant_time_compare`, so the time does not depend on the
first mismatching byte position. It works for any non-empty equal-length
byte strings (the 32-hex shape is a convention, not enforced).

### Access log format

Fields are joined with single spaces in exactly this order:

```
request_id=<id> method=<M> path=<p> status=<s> duration_ms=<d> bytes=<b>
```

`status`, `duration_ms` and `bytes` render as decimal integers
(`_int_to_str`, same algorithm as the stdlib): no leading zeros, `-` for
negatives, `Int` min rendered exactly. No field is escaped or quoted, so a
space inside `path` (or any other field) makes the line ambiguous -- strip
the query string and keep paths space-free.

### CORS order

`middleware_cors_headers` pushes, in this order, only when present:

1. `Access-Control-Allow-Origin: <allow_origin>`
2. `Access-Control-Allow-Methods: <allow_methods>`
3. `Access-Control-Allow-Headers: <allow_headers>`
4. `Access-Control-Max-Age: <max_age_secs>` (only when `max_age_secs > 0`)

An empty string skips its header; `max_age_secs <= 0` skips Max-Age. An
all-empty call returns an empty vector. Values are passed through verbatim,
including `*`; no origin is echoed or validated here.

### JSON error body

`middleware_error_body(status, message)` emits exactly

```
{"error":{"status":<status>,"message":"<escaped message>"}}
```

with this minimal escape pass, left to right over the message bytes:
`\` -> `\\`, `"` -> `\"`, LF -> `\n`, CR -> `\r`, TAB -> `\t`. Every other
byte -- including other control bytes and raw UTF-8 -- is copied unchanged,
so the result is not valid JSON for those bytes (documented boundary, not a
full JSON encoder). `status` is decimal, with `-` for negative values.

## Error catalog

Every message starts with `middleware: `.

| Message | Raised by | Trigger |
|---|---|---|
| `middleware: id generation failed` | `middleware_request_id_new` | `secure_random_bytes(16)` did not return exactly 16 bytes. |
| `middleware: token generation failed` | `middleware_csrf_token_new` | `secure_random_bytes(16)` did not return exactly 16 bytes. |

No other function has an error channel: validation failures are `false`,
and formatting functions are total.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.http.middleware -TimeoutSec 60
```

Expected: the namespace check passes, 22 `[PASS]` lines, and a final
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No envelope, no request/response types.** The caller owns headers,
  cookies, status codes and where the id/token travel.
- **No header parsing or serialization beyond the CORS lines.** No cookie
  serialization, no Set-Cookie, no full header block builder.
- **No escaping of access-log fields.** `path` must not contain spaces;
  nothing is quoted or percent-encoded.
- **Minimal JSON escaping only.** Five escapes (`\`, `"`, LF, CR, TAB);
  other control bytes pass through, so the body is not guaranteed valid
  JSON for arbitrary bytes. No HTML/JS escaping.
- **No CSPRNG fallback policy.** Ids/tokens come from
  `xiom.crypto.secure_random_bytes`; whatever entropy guarantees that
  function offers (and any documented degraded mode) apply here unchanged.
- **No token storage, rotation or session binding.** `middleware_csrf_valid`
  compares two strings the caller supplies.
- **In-memory, O(n) over inputs.** No caches, no indexes, no global state.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
