# xiom.micropython

> **Status:** `incubating` -- conformance-tested on the compiler pin
> **v0.65.0** (19/19 x2); the live-device leg is a typed **SKIP** on hosts
> without `XIOM_MICROPYTHON_PORT`. **Published 2026-10-25** as single tag
> `xiom-micropython/v0.1.0` (sha256 `c25c2014...`).
> **Scope (phase 1):** the documented MicroPython **raw REPL** host side:
> Ctrl-A enter, Ctrl-B friendly exit, Ctrl-C interrupt, Ctrl-D exec/soft
> reset, `OK` + stdout + `0x04` + stderr + `0x04` + `>` framing, traceback
> pass-through and the `print(EXPR)` / `print(repr(EXPR))` eval helpers.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.builder`); tests add
> `xiom.io`, `xiom.string.compare` and `xiom.encoding.hex`. No FFI, no serial
> or socket dependency, no vendored C.

## What it is

`xiom.micropython` is the host half of MicroPython's programmable raw REPL,
written as a pure byte protocol. It builds the exact bytes a host must write
to a board and parses the exact bytes the board returns. A UART, USB-CDC, TCP
socket or a test fixture only has to move `Vec[UInt8]` between the two sides;
the package itself is transport-agnostic.

The protocol is taken from the upstream documentation and device state
machine (pin below): entering raw mode with `0x01`, interrupting with `0x03`,
executing with a command followed by `0x04`, parsing `OK`/EOT-framed output,
and returning to the friendly REPL with `0x02`. Error payloads are pass-through
tracebacks, never silently interpreted.

Upstream reference (UPSTREAM-FIRST): **micropython/micropython** @
`b70ae1aca657bb93e2857dac4e2a2d21a3803200`, license **MIT**. Nothing is
vendored; see PROVENANCE.md for the clone pin, consulted files and the
fixture policy.

## Surface

| Function | Returns | Description |
|---|---|---|
| `mp_repl_enter_request()` | `Vec[UInt8]` | `0x01`. |
| `mp_repl_exit_request()` | `Vec[UInt8]` | `0x02`. |
| `mp_repl_interrupt_request()` | `Vec[UInt8]` | `0x03`. |
| `mp_repl_soft_reset_request()` | `Vec[UInt8]` | `0x04`. |
| `mp_repl_exec_request(code)` | `Result[Vec[UInt8], MpError]` | code + `0x04`; embedded EOT rejected. |
| `mp_eval_request(expr)` | `Result[Vec[UInt8], MpError]` | `print(EXPR)` + `0x04`. |
| `mp_eval_repr_request(expr)` | `Result[Vec[UInt8], MpError]` | `print(repr(EXPR))` + `0x04`. |
| `mp_parse_enter(trace)` | `Result[Int, MpError]` | Banner + `>` prompt; returns consumed bytes. |
| `mp_parse_exit(trace)` | `Result[Int, MpError]` | Friendly banner + `>>> ` prompt. |
| `mp_parse_exec(trace)` | `Result[MpExec, MpError]` | Full `OK ... 04 ... 04 >` frame; soft reset recognized. |
| `mp_exec_ok(r)` | `Bool` | Not a soft reset and no stderr. |
| `mp_eval_value(r)` | `Result[Str, MpError]` | Eval output with trailing CR/LF removed. |
| `mp_output_lines(r)` | `Vec[Str]` | stdout framed into lines. |
| `mp_error_lines(r)` | `Vec[Str]` | stderr/traceback framed into lines. |
| `mp_lines(text)` | `Vec[Str]` | CRLF-normalizing line split. |

`MpExec { output, error, soft_reset, consumed }` and
`MpError { kind, message }` are the two public types. Error kinds:
`MP_ERR_FRAMING` (0), `MP_ERR_EXEC` (1), `MP_ERR_ARG` (2).

## Quick use

```xiom
use xiom.micropython;

// Build the host bytes for one command.
let fr = mp_repl_exec_request("print('hello')");
if fr.is_ok {
  let bytes: Vec[UInt8] = fr.value;   // write these to UART/USB-CDC/TCP
  let _ = bytes;
}

// Parse the complete reply trace: OK + stdout + 0x04 + stderr + 0x04 + '>'.
let tr = mp_parse_exec(&trace);
if tr.is_ok {
  let r: MpExec = tr.value;
  let failed = r.error.len() > 0;
  if failed {
    let errs = mp_error_lines(r);     // traceback lines, untouched
    let _ = errs;
  } else {
    let lines = mp_output_lines(r);   // stdout lines
    let _ = lines;
  }
}
```

`MpExec` is consumed by `mp_exec_ok`, `mp_eval_value`, `mp_output_lines`
and `mp_error_lines` (the by-value shape keeps struct field reads reliable on
the pinned compiler); parse twice or inspect `r.output`/`r.error` directly
when both views are needed.

Because the package never owns a file descriptor, a transport adapter is just
a loop: write `request`, append received bytes, call the matching parser, keep
`consumed` bytes accounted for.

## Tests

`tests/test_conformance.xi` (run by
`.\scripts\port.ps1 -Package xiom.micropython -TimeoutSec 300`) is driven by
`tests/fixtures/*.trace` byte scripts: `>HEX` host bytes, `<HEX` device bytes.
The suite covers every request builder, both enter banners, `OK`/EOT frames,
tracebacks, a Ctrl-C interrupted frame, the soft-reset shape, every framing
failure, line framing and eval extraction. With no
`XIOM_MICROPYTHON_PORT` configured the transport leg reports a typed SKIP and
the suite stays green without hardware.

## Docs

SPEC.md (wire rules + 100% coverage table), ROADMAP.md (transport adapters,
raw-paste, file transfer), PROVENANCE.md (upstream pin, MIT license, consulted
files), AUDIT.md (compiler pin, suite evidence, gaps).
