# xiom.http.middleware -- Specification

Status: `incubating` (implemented, harness-green 22/22 with compiler v0.64.0 on
2026-10-07; not published).
Manifest: `package.xi` (`xiom.http.middleware`, version `0.1.0`).
Module: `src/middleware.xi` (`module xiom.http.middleware`).
Depends on `xiom.std` (`xiom.crypto`, `xiom.string`). No FFI.

## 1. Scope

A pure-XIOM, stdlib-only, envelope-agnostic library of HTTP middleware
helpers over in-memory `Str`/`Int` values. Eight public functions, no public
types:

```xi
pub fn middleware_request_id_new() -> Result[Str, Str]
pub fn middleware_request_id_valid(id: Str) -> Bool
pub fn middleware_access_log_line(request_id: Str, method: Str, path: Str,
                                  status: Int, duration_ms: Int, bytes: Int) -> Str
pub fn middleware_cors_headers(allow_origin: Str, allow_methods: Str,
                               allow_headers: Str, max_age_secs: Int) -> Vec[Str]
pub fn middleware_csrf_token_new() -> Result[Str, Str]
pub fn middleware_csrf_valid(token: Str, expected: Str) -> Bool
pub fn middleware_error_body(status: Int, message: Str) -> Str
pub fn middleware_error_content_type() -> Str
```

Private helpers: `_byte_at_i`, `_hex_digit`, `_hex_lower`, `_int_to_str`,
`_bytes_of`, `_escape_json`. Header lines are a plain `Vec[Str]`; the
`Vec[(Str, Str)]` shape is never used (the live m192 crash class). The
module never compares `Str` values (no `==` on `Str`, no `str_compare`): all
equality work is byte- or length-based. Every `xiom.string.byte_at` read is
widened with `(x as Int) & 0xFF`.

## 2. Non-goals

- **No envelope, transport or server**: no request/response types, no
  sockets, no header parsing, no middleware chain or dispatcher.
- **No full header serialization**: only the four CORS lines; no
  Set-Cookie, no generic header builder, no header escaping.
- **No log sink, clock or formatting config**: `duration_ms` is supplied by
  the caller; the line is returned, not written anywhere.
- **No full JSON encoder**: only the single error-body shape with five
  escapes; other control bytes pass through unchanged.
- **No CSPRNG of its own**: entropy comes from
  `xiom.crypto.secure_random_bytes`, including any platform fallback it
  documents.
- **No token storage, rotation, session binding or origin validation**:
  `middleware_csrf_valid` compares two caller-supplied strings;
  `middleware_cors_headers` passes `*` and every origin through verbatim.
- **No persistence, I/O, FFI or global state.**

## 3. Request ids and CSRF tokens

Generation (`middleware_request_id_new`, `middleware_csrf_token_new`):

1. `crypto.secure_random_bytes(16)` is called; ids and tokens are drawn
   independently per call and per function (the two public functions have
   separate bodies -- neither is an alias of the other).
2. When `bytes.len() != 16`, the result is `Err` (message in section 8).
3. Otherwise the result is `Ok(hex)` where `hex` is the lowercase hex of
   the 16 bytes, two chars per byte, in byte order: exactly 32 chars from
   `[0-9a-f]` (`_hex_lower`).

Validation (`middleware_request_id_valid`): `id.len() == 32` and every byte
in `[0-9a-f]` (bytes 48-57 and 97-102). Uppercase `A-F`, spaces and any
other byte are rejected. The check is shape-only; it cannot prove
provenance.

CSRF validation (`middleware_csrf_valid`):

1. False when `token.len() == 0` or `expected.len() == 0`.
2. False when the lengths differ.
3. Otherwise the raw byte vectors are compared with
   `crypto.constant_time_compare(&a, &b)`: true iff equal, with a running
   time independent of the first mismatching position. Any non-empty
   equal-length byte strings are valid inputs; the 32-hex shape is a
   generation convention, not enforced by `valid`.

## 4. Access-log format

`middleware_access_log_line` builds exactly:

```
request_id=<id> method=<M> path=<p> status=<s> duration_ms=<d> bytes=<b>
```

Six fields joined with single spaces (`0x20`) in the order shown; every
input is copied verbatim except `status`, `duration_ms` and `bytes`, which
render in decimal through `_int_to_str`:

- no leading zeros; `0` is `"0"`;
- negative values get a leading `-`;
- `Int` min renders exactly (`-9223372036854775808`), because the magnitude
  is produced with truncated division and remainder (`x % 10`, sign
  stripped), mirroring the stdlib `int_to_string`.

No field is escaped, quoted, percent-encoded or validated. In particular a
space in `path` splits the line when it is tokenized, so `path` must not
contain spaces (documented contract, not checked). The caller strips the
query string and decides whether `path` is raw or decoded.

## 5. CORS header lines

`middleware_cors_headers` returns complete `Name: value` lines in this fixed
order, each pushed only when its condition holds:

| # | Line | Condition |
|---|---|---|
| 1 | `Access-Control-Allow-Origin: <allow_origin>` | `allow_origin.len() > 0` |
| 2 | `Access-Control-Allow-Methods: <allow_methods>` | `allow_methods.len() > 0` |
| 3 | `Access-Control-Allow-Headers: <allow_headers>` | `allow_headers.len() > 0` |
| 4 | `Access-Control-Max-Age: <max_age_secs>` | `max_age_secs > 0` |

Values are copied verbatim: `*` stays `*`; no origin is echoed, compared or
validated, and no method/header list is parsed. `max_age_secs` renders in
decimal via `_int_to_str` (the condition already excludes `0` and
negatives). An all-empty/all-non-positive call returns an empty vector.
The result is a fresh `Vec[Str]`; each line is a complete header without a
terminating newline.

## 6. Error body and content type

`middleware_error_body(status, message)` returns exactly:

```
{"error":{"status":<status>,"message":"<escaped message>"}}
```

`<status>` is decimal (`_int_to_str`; negatives get `-`). `<escaped
message>` is `message` with this pass applied byte by byte, left to right:

| Input byte | Output |
|---|---|
| `\` (92) | `\\` (two chars) |
| `"` (34) | `\"` (two chars) |
| LF (10) | `\n` (backslash + `n`) |
| CR (13) | `\r` (backslash + `r`) |
| TAB (9) | `\t` (backslash + `t`) |
| any other byte | copied unchanged (one byte) |

Other control bytes and raw UTF-8 bytes are copied byte-for-byte, so
multi-byte UTF-8 sequences survive unchanged while other control bytes make
the result invalid JSON (deliberate minimal-encoder boundary).

`middleware_error_content_type()` returns the literal `application/json`
(no charset parameter), for use as the `Content-Type` of
`middleware_error_body` payloads.

## 7. Test plan

`tests/test_conformance.xi` (module `middleware_tests`) runs 22 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). All `Str` equality goes through
`xiom.string.compare.str_compare` via the local `streq` helper; every Vec
element read is bound to a typed local. Randomized checks compare two live
outputs to each other (validity and difference), never to a fixed
expectation.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | request id new | `Ok`, length 32, passes `middleware_request_id_valid` |
| t2 | request id uniqueness | two consecutive ids are both valid and differ |
| t3 | request id valid accepts | all-digits, all-`f`, mixed `deadbeef...` 32-hex ids |
| t4 | request id valid rejects | empty, 31/33 chars, uppercase `A-F`, `g`, embedded space |
| t5 | access log exact | full six-field line for `GET /users 200 12 345` |
| t6 | access log integers | zeros (`status 204`, `duration 0`, `bytes 0`) and large values (`1234567890`, `1048576`) |
| t7 | cors full | all four headers, exact text and order |
| t8 | cors only origin | `("*", "", "", 0)` -> single line, `*` passed through |
| t9 | cors none | all empty, and negative max-age -> empty vector |
| t10 | cors max-age boundary | `1` present and last; `0` and `-1` skipped (others kept) |
| t11 | cors empty origin skip | origin skipped while methods/headers/max-age keep order |
| t12 | csrf token new | `Ok`, length 32, lowercase hex, two calls differ |
| t13 | csrf self-validates | a fresh token is `true` against itself |
| t14 | csrf mismatch | same-length ids with one changed byte are `false`; equal ids `true` |
| t15 | csrf empty | `("","")`, `(tok,"")`, `("",tok)` are all `false` |
| t16 | csrf length mismatch | 31-vs-32, 32-vs-31, `"a"`-vs-`"aa"` are `false` |
| t17 | error body simple | exact `{"error":{"status":404,"message":"not found"}}` |
| t18 | error body quote/backslash | `a"b\c` -> `\"` and `\\` exactly |
| t19 | error body LF/CR/TAB | `a\nb\rc\td` -> `\n`, `\r`, `\t` exactly |
| t20 | content type | `application/json`, stable across calls |
| t21 | deterministic repeats | access log, cors vector, error body and csrf check are identical for identical inputs |
| t22 | csrf generic bytes | arbitrary non-empty equal-length strings compare directly |

Scripted expectation from the repository root (toolchain v0.64.0 via
`$env:XIOM_COMPILER`; `XIOM_RUNTIME_DIR` is deliberately not set):

```
& .\scripts\port.ps1 -Package xiom.http.middleware -TimeoutSec 60
# port: PASS (passed=22 failed=0 program_exit=0 exit=0)
```

## 8. Error catalog

Every message starts with the literal prefix `middleware: `. Messages are
static strings (no formatted values).

| Message | Raised by | Trigger |
|---|---|---|
| `middleware: id generation failed` | `middleware_request_id_new` | `secure_random_bytes(16).len() != 16` |
| `middleware: token generation failed` | `middleware_csrf_token_new` | `secure_random_bytes(16).len() != 16` |

Both generators are the only fallible functions. The failure arm cannot be
forced by caller input on supported platforms (it depends on the CSPRNG
returning a short vector), so the conformance suite pins the `Ok` path and
the message strings are covered by inspection, not by a test. All other
functions are total: invalid input yields `false` or a verbatim rendering,
never an error.

## 9. Compiler / stdlib notes

The implementation follows the v0.64.0 package idioms:

- Free functions only; no types, no methods, no global state.
- Imports are `xiom.crypto` (used as `crypto.secure_random_bytes`,
  `crypto.constant_time_compare`) and `xiom.string` (used as
  `string.byte_at`, `string.str_slice`). Hex and decimal formatting are
  private helpers over `xiom.string.str_slice`, so `xiom.convert` is not
  imported; the `_int_to_str` algorithm mirrors the stdlib one.
- No `==` on `Str` anywhere; the module performs no `Str` equality at all.
- Header lines are `Vec[Str]`; `Vec[(Str, Str)]` never appears.
- Every byte read goes through `_byte_at_i` with the `& 0xFF` widening;
  every Vec element read is bound to a typed local first.
- Locals are initialized at declaration; `Result` values are constructed
  inline in the two generators.
- No contracts (`requires:`/`ensures:`) are declared in 0.1.0; the 22-check
  suite pins behavior instead.
