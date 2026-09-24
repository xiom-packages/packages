# xiom.rpc -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.rpc`, version `0.1.0`).
Module: `src/rpc.xi` (`module xiom.rpc`).
Depends on `xiom.std` (`xiom.string`, `xiom.convert`). No FFI, no network,
no clock access, no sibling-package imports.

This specification describes a JSON-RPC 2.0 **envelope codec**: four builders
that emit compact JSON text and a minimal byte-wise scanner that reads the
`id`, `method`, `code` and `message` members back. It is NOT a JSON parser,
NOT a client/server and NOT a batch-array implementation.

## 1. Scope

Eleven free functions over `Str`:

```xi
pub fn rpc_escape(s: Str) -> Str
pub fn rpc_request(id: Int, method: Str, params_json: Str) -> Str
pub fn rpc_notification(method: Str, params_json: Str) -> Str
pub fn rpc_response(id: Int, result_json: Str) -> Str
pub fn rpc_error(id: Int, code: Int, message: Str, data_json: Str) -> Str
pub fn rpc_is_request(text: Str) -> Bool
pub fn rpc_is_error(text: Str) -> Bool
pub fn rpc_id(text: Str) -> Result[Int, Str]
pub fn rpc_method(text: Str) -> Result[Str, Str]
pub fn rpc_error_code(text: Str) -> Result[Int, Str]
pub fn rpc_error_message(text: Str) -> Result[Str, Str]
```

All scanning is byte-wise. Every byte read through `xiom.string.byte_at` is
widened with `(x as Int) & 0xFF` before comparison or arithmetic. Complexity
is O(n) over the input length for every function. Result values are
constructed only in tiny leaf helpers (`_ok_str`, `_err_str`, `_ok_int`,
`_err_int`).

## 2. Non-goals

- No JSON parser: no nesting, no arrays-as-structures, no full key model,
  no validation of caller-supplied fragments.
- No batch arrays; a top-level array is opaque text.
- No transports, no client/server, no registry, no dispatch, no framing.
- No `xiom.serialize.json` dependency: `params_json`, `result_json` and
  `data_json` are raw text owned by the caller.

## 3. Builder grammar

`escape`, `int`, `str` and `ws` are defined in section 4. Builders emit
compact JSON (no insignificant whitespace) with a fixed key order; members
in brackets are present only when the corresponding argument is non-empty.

```
request(id, method, params) :=
  '{' '"jsonrpc":"2.0","method":"' escape(method) '"'
      [ ',' '"params":' params ]
      ',' '"id":' int(id) '}'

notification(method, params) :=
  '{' '"jsonrpc":"2.0","method":"' escape(method) '"'
      [ ',' '"params":' params ]
  '}'

response(id, result) :=
  '{' '"jsonrpc":"2.0","result":' (result | 'null' when result = "")
      ',' '"id":' int(id) '}'

error(id, code, message, data) :=
  '{' '"jsonrpc":"2.0","error":{' '"code":' int(code)
      ',"message":"' escape(message) '"'
      [ ',' '"data":' data ]
  '},"id":' int(id) '}'
```

Rules:

1. `params` is omitted exactly when `params_json` is empty. A non-empty
   literal such as `null`, `[]` or `{}` is emitted verbatim.
2. `data` follows the same empty-text rule; there is no `null` default.
3. A response must carry a result member, so an empty `result_json` is
   normalized to the JSON literal `null`.
4. `id` and `code` are rendered by `xiom.convert.int_to_string`; every
   signed 64-bit value renders exactly (`-7`, `9007199254740993`, ...).
5. Method and message text is escaped; nothing else is transformed. Raw
   fragments are byte-copied, including any invalid JSON they contain.

## 4. Escape grammar

`rpc_escape` maps each byte of the input:

| Input byte | Output |
|---|---|
| `\` (0x5C) | `\\` |
| `"` (0x22) | `\"` |
| LF (0x0A) | `\n` |
| CR (0x0D) | `\r` |
| TAB (0x09) | `\t` |
| other C0 controls (< 0x20) | `\u00xx` with lowercase hex digits |
| everything else | the byte, verbatim |

Consequences (tested): `/` is not escaped; bytes >= 0x80 pass through
unchanged, so UTF-8 method names stay readable (`München ✓`); `\u0001` and
`\u001f` are produced for bytes 0x01 and 0x1F; empty input yields empty
output.

Inverse direction: the scanner decodes only the five two-character escapes
it produces (`\"`, `\\`, `\n`, `\r`, `\t`). A `\u00xx` sequence is copied
verbatim, including the backslash, so a control byte escaped by
`rpc_escape` is **not** recovered as the original byte by `rpc_method` /
`rpc_error_message`. Round-trips are exact for every input that needs no
`\u00xx` escape (that is, all text except other C0 controls).

## 5. Scanner grammar

```
find(key)   := byte offset just past the closing quote of the FIRST
               occurrence of '"' key '"' anywhere in text; -1 if absent
value(key)  := ws* ':' ws* after find(key)          ; -1 when ':' is missing
integer     := '-'? [0-9]+ terminator
string      := '"' ( '\' any | any-except-'"' )* '"'
terminator  := end-of-text | ws | ',' | '}'
ws          := TAB(9) | LF(10) | CR(13) | space(32)
```

Rules:

1. Key matching is byte-wise and quote-delimited: `"id"` matches neither
   `"valid"` nor `"idea"`. Non-ASCII keys work.
2. First occurrence wins. A `"key"` inside another string value, a nested
   object or a raw params/result/data fragment can match; duplicate keys are
   not resolved.
3. `_skip_ws` also skips whitespace before the `:` and before the value.
   Text ending right after the `:` is an error (`expected ... value`).
4. Integers are optional `-`, then one or more digits, then end-of-text,
   whitespace, `,` or `}`. `12abc` is `malformed`, `"7"` and `null` are
   `expected integer`, a bare `-` is `expected integer`, and magnitudes
   beyond the signed 64-bit range are `integer out of range`.
5. Strings are escape-aware while scanning: a backslash consumes the next
   byte, so `\"` does not terminate the value. The captured text is then
   passed through `_unescape` (section 4 inverse).
6. `rpc_is_request(text)` is the substring conjunction
   `contains(text, "jsonrpc") && contains(text, "method")`; it is true for
   notifications as well. `rpc_is_error(text)` is
   `contains(text, "error")`. Both are probes, not structural tests.

## 6. Error catalog

Every `Err` message starts with the literal prefix `rpc: `.

| Message | Raised by | Condition |
|---|---|---|
| `rpc: key not found: id` | `rpc_id` | no quoted `"id"` in the text. |
| `rpc: key not found: method` | `rpc_method` | no quoted `"method"`. |
| `rpc: key not found: code` | `rpc_error_code` | no quoted `"code"`. |
| `rpc: key not found: message` | `rpc_error_message` | no quoted `"message"`. |
| `rpc: expected integer value` | `rpc_id`, `rpc_error_code` | missing `:`, end-of-text after `:`, or first value byte is not `-`/digit. |
| `rpc: malformed integer value` | `rpc_id`, `rpc_error_code` | a non-digit byte ends the digit run and is not a terminator. |
| `rpc: integer out of range` | `rpc_id`, `rpc_error_code` | magnitude exceeds 2^63 - 1. |
| `rpc: expected string value` | `rpc_method`, `rpc_error_message` | missing `:`, end-of-text, or the value does not start with `"`. |
| `rpc: unterminated string value` | `rpc_method`, `rpc_error_message` | no closing `"` before end-of-text. |

## 7. Test plan

`tests/test_conformance.xi` (module `rpc_tests`) runs 27 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green).

| # | Check | Semantics pinned |
|---|---|---|
| t1 | escape passthrough | plain, empty and UTF-8 text unchanged |
| t2 | escape quote/backslash | `\"` and `\\` |
| t3 | escape LF/TAB/CR | `\n`, `\t`, `\r` |
| t4 | escape C0 controls | lowercase `\u00xx` |
| t5 | request with params | exact pinned envelope |
| t6 | request params omission | empty omitted, `null` kept |
| t7 | request ids | negative and large ids render exactly |
| t8 | notification with params | exact pinned envelope, no `id` |
| t9 | notification omission | empty params omitted |
| t10 | response | exact pinned envelope, unicode result passthrough |
| t11 | response empty | empty result becomes `null`; zero id |
| t12 | error without data | exact pinned envelope |
| t13 | error with data | data included, message escaped |
| t14 | is_request | built request/notification true; response, empty, single-substring false |
| t15 | is_error | built/raw error true; request and empty false; substring semantics pinned |
| t16 | rpc_id | built envelopes, negative, large, whitespace raw fixture |
| t17 | rpc_id errors | missing, `null`, quoted, junk, empty value, bare `-`, overflow |
| t18 | rpc_method | built, raw, escaped and unicode methods |
| t19 | rpc_method errors | missing, non-string, unterminated |
| t20 | rpc_error_code | built errors and raw fixtures |
| t21 | rpc_error_code errors | missing and malformed codes |
| t22 | rpc_error_message | built, raw and escaped messages (escape-aware scan) |
| t23 | rpc_error_message errors | missing, non-string, unterminated |
| t24 | round trip, request | escaped method + `id` recover; envelope pinned |
| t25 | round trip, error/notification | code, message, data and notification method |
| t26 | empty inputs | builders and empty-string extraction |
| t27 | malformed plain text | all readers Err and both probes false |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison). Test constants for builder outputs are independent
literals, so a broken builder or reader fails a pinned check.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.rpc
```

Expected: `port: PASS (passed=27 failed=0 program_exit=0 exit=0)`.

## 8. Known limitations

- Envelope-level only: no transports, registry, dispatch or framing.
- Raw fragments are caller-owned; nothing is parsed or validated.
- First-occurrence key matching; no nesting or duplicate-key semantics.
- `\uXXXX` is not decoded; a control byte escaped as `\u00xx` does not
  round-trip through the scanner.
- `"id":null` is an `Err`, not a null-id representation.
- Batch arrays are not modeled.
- `rpc_is_request` / `rpc_is_error` are substring probes and can produce
  false positives on raw fragments.

## 9. Compiler / stdlib notes

No compiler workarounds beyond the documented v0.61.3 idioms: free
functions only, byte reads widened with `& 0xFF`, Result construction
confined to leaf helpers, and no `==` on `Str`. The module avoids `Vec`
entirely: escaping concatenates into a `Str` and the scanner reads bytes
directly. `xiom.convert.int_to_string` renders ids and codes;
`xiom.string.str_contains` backs the two probes. The tests route every
string comparison through `str_compare` and only take `&` of locals at call
sites, so the E001 aliasing warning does not fire.
