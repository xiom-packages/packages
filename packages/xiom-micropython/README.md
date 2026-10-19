# xiom.micropython

> **Status:** `incubating` -- conformance-tested (**19/19 x2** on the
> compiler pin **v0.64.7**; the absent-transport leg is a typed **SKIP**
> and the suite stays green) -- not yet published.
> **Scope (0.1.0):** host-side, pure-XIOM client for the standard
> **MicroPython raw REPL** wire protocol: enter (Ctrl-A), friendly exit
> (Ctrl-B), interrupt (Ctrl-C), exec framing (UTF-8 code + Ctrl-D, `OK`
> acknowledgement, stdout/stderr `0x04` EOF frames), soft reset (Ctrl-D
> with empty input), incremental response decoding, output/error line
> framing, traceback pass-through, eval helpers and typed errors.
> **Transport-agnostic:** the package never opens a UART, USB or socket.
> Callers write the returned frames to their link and feed received bytes
> back into the decoder; an absent link is a typed `MP_ERR_ABSENT` SKIP.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.encoding`); tests use
> `xiom.io`, `xiom.string.compare`, `xiom.os.process`.

## What it is

`xiom.micropython` speaks the **standard raw REPL** documented by
MicroPython -- the byte protocol used by `tools/pyboard.py` and
`mpremote` to run code on a board without echo, auto-indent or prompt
noise. Nothing is vendored: the package re-derives the wire behavior from
the upstream documentation and `pyexec.c` state machine (pin below) and
ships no C, no FFI and no transport backend.

Upstream reference (UPSTREAM-FIRST): **micropython/micropython** @
`b70ae1aca657bb93e2857dac4e2a2d21a3803200`, license **MIT**. See
`PROVENANCE.md` for the clone, the exact reference files/lines and what
was verified; `SPEC.md` for the declared subset and the 100% coverage
table.

## Wire protocol

| Host write | Device response | Meaning |
|---|---|---|
| `0x01` (Ctrl-A) | `[CRLF]raw REPL; CTRL-B to exit\r\n>` | Enter raw REPL (leading CRLF when leaving the friendly REPL). |
| code bytes + `0x04` (Ctrl-D) | `OK` + stdout + `0x04` + stderr + `0x04` + `>` | Exec. `OK` acknowledges input reception, then the code compiles and runs. |
| `0x03` (Ctrl-C) | interrupt traceback inside the current response | Interrupt a running program; idle REPL silently clears the pending line. |
| `0x02` (Ctrl-B) | friendly banner + `>>> ` | Leave raw mode. |
| `0x04` with empty input | `OK\r\n` then reset | Soft reset (exposed separately; `mp_exec_frame` rejects empty code). |

A successful exec therefore ends with **two** consecutive `0x04` bytes
(empty stderr frame). An uncaught exception -- including a syntax error
and `KeyboardInterrupt` -- is printed to stderr and framed the same way;
the full traceback is preserved verbatim.

## API

### Frames (host -> device)

| Function | Returns | Description |
|---|---|---|
| `mp_interrupt_frame()` | `Vec[UInt8]` | Ctrl-C (`0x03`). |
| `mp_enter_raw_frame()` | `Vec[UInt8]` | Ctrl-A (`0x01`). |
| `mp_enter_raw_flush_frame()` | `Vec[UInt8]` | CR + Ctrl-A (pyboard.py-compatible enter). |
| `mp_exit_raw_frame()` | `Vec[UInt8]` | Ctrl-B (`0x02`). |
| `mp_soft_reset_frame()` | `Vec[UInt8]` | Ctrl-D alone (`0x04`). |
| `mp_exec_frame(code)` | `Result[Vec[UInt8], MpError]` | UTF-8 code + Ctrl-D; empty code is `INVALID_ARG`. |
| `mp_eval_frame(expr)` | `Result[Vec[UInt8], MpError]` | `print(<expr>)\n` + Ctrl-D. |
| `mp_eval_repr_frame(expr)` | `Result[Vec[UInt8], MpError]` | `print(repr(<expr>))\n` + Ctrl-D. |

### Decoding

| Function | Returns | Description |
|---|---|---|
| `mp_decoder_new()` | `MpDecoder` | Fresh decoder in `MP_DEC_PRELUDE`. |
| `mp_decoder_feed(&d, chunk)` | `Result[Unit, MpError]` | Feed a received chunk; protocol violation -> `MP_ERR_PROTOCOL`. |
| `mp_decoder_done(&d)` | `Bool` | Both EOF frames consumed. |
| `mp_decoder_state(&d)` | `Int` | `MP_DEC_PRELUDE`/`OK`/`STDOUT`/`STDERR`/`DONE`/`ERROR`. |
| `mp_decoder_banner(&d)` | `Str` | Prelude bytes seen (banner + `>`), for diagnostics. |
| `mp_decoder_result(&d)` | `Result[MpExecResult, MpError]` | Typed result once complete. |
| `mp_decoder_reset(&d)` | `Unit` | Clear for the next response. |
| `mp_decode_trace(bytes)` | `Result[MpExecResult, MpError]` | Decode one complete response slice. |
| `mp_parse_exec_response(bytes)` | `Result[MpExecResult, MpError]` | Wire-level alias of `mp_decode_trace`. |
| `mp_frame_is_complete(bytes)` | `Bool` | Non-panicking completeness check. |

The decoder accepts a slice that starts at the banner/prompt **or**
directly at `OK`, tolerates a soft-reset boot log before the banner, and
ignores trailing friendly bytes after the second EOF.

### Results, lines, tracebacks, eval

`MpExecResult` holds `ok` (stderr frame empty), `output`, `error`,
`output_lines` and `error_lines`.

| Function | Returns | Description |
|---|---|---|
| `mp_split_lines(text)` | `Vec[Str]` | Split CRLF/LF/CR; one trailing newline is not a phantom line. |
| `mp_traceback_is_present(error)` | `Bool` | Detect the MicroPython traceback header. |
| `mp_traceback_exception(error)` | `Str` | Final non-empty line (`ValueError: bad`), trimmed; full text stays in `error`. |
| `mp_eval_extract(&res)` | `Result[Str, MpError]` | Last non-empty stdout line; device traceback -> `MP_ERR_EXEC`. |
| `mp_eval(bytes)` | `Result[Str, MpError]` | `mp_decode_trace` + `mp_eval_extract`. |

### Typed errors

`MpError { kind, message }`; `message` starts with `micropython: `.

| Kind | Value | Meaning |
|---|---|---|
| `MP_ERR_ABSENT` | 0 | No link/transport -> **SKIP** (`mp_error_is_skip`). |
| `MP_ERR_IO` | 1 | Transport I/O failure. |
| `MP_ERR_TIMEOUT` | 2 | No complete response within the caller's deadline. |
| `MP_ERR_PROTOCOL` | 3 | Bad/missing `OK`, missing EOF frames, no prompt, oversized prelude. |
| `MP_ERR_INVALID_ARG` | 4 | Empty/whitespace input rejected before a frame is built. |
| `MP_ERR_EXEC` | 5 | Device traceback or eval produced no value; traceback passes through. |

Helpers: `mp_error(kind, detail)`, `mp_error_name(kind)`,
`mp_error_absent(transport)`, `mp_error_is_skip(&err)`.

## Quick use

```xiom
use xiom.micropython;

// link = your UART / USB CDC / socket; these functions return bytes only.
let enter = mp_enter_raw_frame();          // write to link
let frame = mp_exec_frame("print(123)");
// write frame, collect bytes until the response ends, then:
let r = mp_decode_trace(&response);
if r.is_ok {
  let res: MpExecResult = r.value;
  if res.ok {
    // res.output / res.output_lines
  } else {
    // res.error is the full traceback (pass-through)
  }
}
let intr = mp_interrupt_frame();           // Ctrl-C a running program
let bye = mp_exit_raw_frame();             // back to the friendly REPL
```

No transport: classify and skip instead of failing.

```xiom
let e = mp_error_absent("COM7");
if mp_error_is_skip(&e) {
  // device-fleet SKIP path
}
```

## Tests

`tests/test_conformance.xi` is fixture-driven and hardware-free:
`tests/fixtures/*.trace` are direction-aware byte scripts (`W` host
writes, `R` device reads; hex bytes and quoted text with escapes). The
suite pins every frame byte, decodes happy/traceback/syntax/interrupt/
empty/UTF-8 traces, feeds one-byte chunks, exercises reset/reuse and
every decoder error branch, pins line/traceback framing and the typed
error catalog, and proves the absent-transport SKIP classification.

```
.\scripts\port.ps1 -Package xiom.micropython -TimeoutSec 300
# 19/19 x2 on v0.64.7
```

## Docs

`SPEC.md` (wire rules, declared surface, 100% coverage table, limits),
`ROADMAP.md` (raw-paste mode, live adapters, file transfer),
`PROVENANCE.md` (clone pin, MIT license, reference lines, synthetic
vectors), `AUDIT.md` (suite evidence and compiler-pin findings).
