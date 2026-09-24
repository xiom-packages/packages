# xiom.rpc

> **Status:** `incubating` -- implemented and green on the local harness
> (compiler v0.61.3, 27 checks), NOT yet published to the XIOM registry.
> **Scope:** JSON-RPC 2.0 envelope codec: builds compact request /
> notification / response / error envelopes and scans them back with a
> minimal byte-wise scanner. No JSON parser, no transports, no batch arrays.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.convert`; tests add
> `xiom.io`, `xiom.test`, `xiom.string.compare`).

## What it is

`xiom.rpc` is an envelope-level codec for JSON-RPC 2.0 text. It has two
halves:

- **Builders** (`rpc_request`, `rpc_notification`, `rpc_response`,
  `rpc_error`) emit compact JSON with a fixed key order. Method names and
  error messages are escaped by `rpc_escape`; everything else is inserted
  **verbatim**.
- **Scanner** (`rpc_is_request`, `rpc_is_error`, `rpc_id`, `rpc_method`,
  `rpc_error_code`, `rpc_error_message`) reads members back with the
  documented subset grammar described below. It is **not** a JSON parser.

`params_json`, `result_json` and `data_json` are RAW JSON text supplied by
the caller: they are never validated, parsed or re-encoded. Composing them
is the caller's responsibility (pair this package with a real JSON encoder
if you need one).

## API

| Function | Returns | Description |
|---|---|---|
| `rpc_escape(s)` | `Str` | Escape `\`, `"`, LF, CR, TAB and other C0 control bytes (`\u00xx`); raw UTF-8 passes through. |
| `rpc_request(id, method, params_json)` | `Str` | `{"jsonrpc":"2.0","method":M[,"params":P],"id":I}`; params omitted when empty. |
| `rpc_notification(method, params_json)` | `Str` | Same as `rpc_request` without the `id` member. |
| `rpc_response(id, result_json)` | `Str` | `{"jsonrpc":"2.0","result":R,"id":I}`; empty result becomes `null`. |
| `rpc_error(id, code, message, data_json)` | `Str` | `{"jsonrpc":"2.0","error":{"code":C,"message":M[,"data":D]},"id":I}`; data omitted when empty. |
| `rpc_is_request(text)` | `Bool` | Substring probe: text contains `jsonrpc` **and** `method`. |
| `rpc_is_error(text)` | `Bool` | Substring probe: text contains `error`. |
| `rpc_id(text)` | `Result[Int, Str]` | Signed 64-bit `"id"` integer (first `"id"` occurrence). |
| `rpc_method(text)` | `Result[Str, Str]` | `"method"` string; `\"`, `\\`, `\n`, `\r`, `\t` decoded. |
| `rpc_error_code(text)` | `Result[Int, Str]` | Signed 64-bit `"code"` integer. |
| `rpc_error_message(text)` | `Result[Str, Str]` | `"message"` string; same escape rules as `rpc_method`. |

Every error string starts with the literal prefix `rpc: `:

| Message | Raised by |
|---|---|
| `rpc: key not found: <key>` | any reader, when the quoted key is absent. |
| `rpc: expected integer value` | `rpc_id`, `rpc_error_code`: no `:` after the key, or the value does not start with `-`/a digit (includes `null` and quoted numbers). |
| `rpc: malformed integer value` | `rpc_id`, `rpc_error_code`: a non-digit byte interrupts the number and is not a terminator. |
| `rpc: integer out of range` | `rpc_id`, `rpc_error_code`: magnitude beyond the signed 64-bit range. |
| `rpc: expected string value` | `rpc_method`, `rpc_error_message`: the value is not a quoted string. |
| `rpc: unterminated string value` | `rpc_method`, `rpc_error_message`: the closing quote is missing. |

## Envelope examples

```xi
use xiom.rpc;

rpc_request(1, "subtract", "[42,23]")
// {"jsonrpc":"2.0","method":"subtract","params":[42,23],"id":1}

rpc_request(2, "ping", "")
// {"jsonrpc":"2.0","method":"ping","id":2}

rpc_notification("log", "{\"level\":\"info\"}")
// {"jsonrpc":"2.0","method":"log","params":{"level":"info"}}

rpc_response(1, "42")
// {"jsonrpc":"2.0","result":42,"id":1}

rpc_response(3, "")
// {"jsonrpc":"2.0","result":null,"id":3}

rpc_error(4, -32601, "Method not found", "")
// {"jsonrpc":"2.0","error":{"code":-32601,"message":"Method not found"},"id":4}
```

Reading them back:

```xi
let req = rpc_request(1, "subtract", "[42,23]");
let id = rpc_id(req);            // Ok(1)
let m = rpc_method(req);         // Ok("subtract")
let is_req = rpc_is_request(req); // true (substring probe)

let err = rpc_error(4, -32601, "Method not found", "");
let code = rpc_error_code(err);       // Ok(-32601)
let msg = rpc_error_message(err);     // Ok("Method not found")
```

## Scanner subset

The scanner is byte-wise and deliberately minimal (full rules in `SPEC.md`):

- It finds the **first** occurrence of the quoted `"key"` anywhere in the
  text -- including inside another string value, a nested object or raw
  params/result/data. There is no notion of "top level".
- It expects `:` (whitespace allowed around it), then reads either a signed
  integer (`-?[0-9]+`, terminated by end-of-text, whitespace, `,` or `}`) or
  a quoted string.
- String scanning is escape-aware (`\"` does not terminate the value), and
  the two-character escapes `\"`, `\\`, `\n`, `\r`, `\t` are decoded.
  `\uXXXX` is returned **verbatim, including the backslash**.
- `rpc_is_request` / `rpc_is_error` are substring probes, not structural
  tests: `errors` matches `rpc_is_error`, and a `method` inside raw result
  text can match `rpc_is_request`.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.rpc
```

Expected: the section-4 namespace check passes, 27 `[PASS]` lines, and a
final `port: PASS (passed=27 failed=0 program_exit=0 exit=0)`.

The suite pins every builder output as an exact string (including negative
and large ids, empty params/data and escaping) and exercises each reader
against built envelopes and fixed raw fixtures, including malformed input.

## Limitations

- **Envelope-level only.** No client/server, no transports, no procedure
  registry, no dispatch, no framing. This package emits and inspects text.
- **Raw params/result/data text.** The caller supplies JSON fragments; the
  module does not parse, validate or re-encode them.
- **The scanner is not a JSON parser**: no nesting, no duplicate-key
  semantics, no `\uXXXX` decoding, first-occurrence key matching only.
- **No batch arrays.** Only single envelopes are modeled; a batch array is
  treated as opaque text (the scanner's first-occurrence rules may still
  match members inside it, but no array semantics are provided).
- `rpc_id` does not accept `null` ids; a JSON-RPC peer that uses
  `"id":null` yields `Err`.
- Pure XIOM: no FFI, no network, no clock access.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
