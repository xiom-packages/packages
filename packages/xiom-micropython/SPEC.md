# SPEC: xiom.micropython -- host-side MicroPython raw-REPL protocol client

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.micropython` |
| Version | 0.1.0 |
| Kind | pure-XIOM protocol client (no FFI, no vendored code, no transport) |
| Target protocol | MicroPython standard **raw REPL** (Ctrl-A / Ctrl-B / Ctrl-C / Ctrl-D + `OK` + EOF frames) |
| Implementation oracle | micropython/micropython @ `b70ae1aca657bb93e2857dac4e2a2d21a3803200` (MIT): `docs/reference/repl.rst`, `shared/runtime/pyexec.c`, `tools/pyboard.py` |
| Package license | MIT OR Apache-2.0 |
| Compiler pin | v0.64.7 (stdlib 2006 module namespaces; namespace check OK) |
| Landing | bindings lane MCU Phase-1 wave, 2026-10-19 |
| Suite | `tests/test_conformance.xi` (19 checks, x2) |

## 2. Scope decision: standard raw REPL only, transport-agnostic

`pyexec.c` implements two programmatic modes: the **standard raw REPL**
(code is accumulated until Ctrl-D, then compiled and executed) and
**raw-paste mode** (Ctrl-E `A` Ctrl-A with a flow-control window). 0.1.0
implements the standard mode only. Raw-paste mode, file transfer and
friendly-REPL line editing are explicit non-goals (`ROADMAP.md`).

The package owns framing, not I/O. No serial/socket/FFI backend is
imported or linked: the caller writes frame bytes to its link and feeds
received bytes into the incremental decoder. This keeps the protocol
reusable over UART, USB CDC, Wi-Fi sockets or an in-memory trace, and lets
the conformance suite run without hardware.

## 3. Wire protocol (byte exact)

Oracle: `repl.rst` sec. "Raw mode and raw-paste mode" (lines 206-216);
`pyexec.c` `pyexec_raw_repl_process_char` (event-driven, 357-406) and
`pyexec_raw_repl` (blocking, 552-617); `parse_compile_execute`
(EXEC_FLAG_PRINT_EOF, 60, 143-158, 222-223); `tools/pyboard.py`
`enter_raw_repl` 400-443, `follow` 447-463, `exec_raw_no_follow`
497-536, `eval` 538-547.

### 3.1 Enter raw mode

Host writes `0x01`. Device writes:

```
["\r\n"] "raw REPL; CTRL-B to exit\r\n" ">"
```

The leading `\r\n` is emitted when the transition starts at the friendly
REPL prompt; re-entering from raw mode emits the banner without it. The
decoder accepts an arbitrary prelude ending at the first `>`, bounded by
`MP_PRELUDE_MAX` (4096 bytes). `mp_enter_raw_flush_frame()` additionally
prefixes CR, matching `pyboard.py` `b"\r\x01"`.

### 3.2 Exec

Host writes the UTF-8 code bytes followed by `0x04`. Device writes:

```
"OK" stdout 0x04 stderr 0x04 [">"]
```

* `OK` is written when Ctrl-D is received, before compilation/execution.
* The first EOF terminates stdout; the second terminates stderr. A
  successful exec therefore ends `... 0x04 0x04`.
* An uncaught exception (runtime or compile) prints its traceback to
  stderr between the two EOFs. `KeyboardInterrupt` follows the same shape.
* The final `>` is the next raw prompt. Bytes after the second EOF are
  trailing prompt/friendly bytes and are ignored by the decoder.

`mp_exec_frame` rejects empty code (`MP_ERR_INVALID_ARG`), because Ctrl-D
with empty input is the soft-reset path (`pyexec.c` `line.len == 0`).
`mp_soft_reset_frame()` exposes `0x04` alone; the device answers
`OK\r\n` and restarts, with no exec stdout/stderr frames.

### 3.3 Interrupt / exit

* `0x03` (Ctrl-C) raises `KeyboardInterrupt` in running code; the
  traceback arrives in the current response's stderr frame. When the REPL
  is idle, Ctrl-C only clears the pending input line and produces no
  response -- callers must not wait for a frame after an idle interrupt.
* `0x02` (Ctrl-B) leaves raw mode; the device prints its friendly banner
  and `>>> `. `mp_exit_raw_frame()` emits the single byte.

### 3.4 Framing limits

* `0x04` is a terminator, not escaped. A payload byte equal to `0x04`
  cannot be represented in stdout/stderr; MicroPython does not escape it
  either. Binary payloads must be encoded (e.g. base64/hex) by the code
  running on the device.
* Console bytes are decoded as UTF-8 (`Str::from_utf8`). Invalid UTF-8 is
  not a protocol error; callers needing raw bytes must encode on-device.
* No timeout lives in the package: the caller owns its link deadline and
  maps expiry to `MP_ERR_TIMEOUT`.
* A prelude may contain a soft-reset boot log before the raw banner
  (`MPY: soft reboot`, filesystem sync lines); anything before the first
  `>` is accepted and exposed by `mp_decoder_banner`.

## 4. Declared surface (0.1.0)

### 4.1 Types

| Type | Fields / meaning |
|---|---|
| `MpError` | `kind: Int`, `message: Str` ("micropython: " prefix). |
| `MpExecResult` | `ok: Bool` (stderr empty), `output`, `error` (verbatim traceback pass-through), `output_lines`, `error_lines`. |
| `MpDecoder` | `state`, `pre`, `okbuf`, `out`, `err`, `tail` (all decoder-owned). |

### 4.2 Constants

`MP_CTRL_A` 1, `MP_CTRL_B` 2, `MP_CTRL_C` 3, `MP_CTRL_D` 4,
`MP_CTRL_E` 5; `MP_RAW_BANNER`, `MP_RAW_PROMPT` ">",
`MP_FRIENDLY_PROMPT` ">>> ", `MP_OK` "OK", `MP_PRELUDE_MAX` 4096;
`MP_DEC_PRELUDE` 0, `MP_DEC_OK` 1, `MP_DEC_STDOUT` 2,
`MP_DEC_STDERR` 3, `MP_DEC_DONE` 4, `MP_DEC_ERROR` 5;
`MP_ERR_ABSENT` 0, `MP_ERR_IO` 1, `MP_ERR_TIMEOUT` 2,
`MP_ERR_PROTOCOL` 3, `MP_ERR_INVALID_ARG` 4, `MP_ERR_EXEC` 5.

### 4.3 Functions (27)

Frames: `mp_interrupt_frame`, `mp_enter_raw_frame`,
`mp_enter_raw_flush_frame`, `mp_exit_raw_frame`, `mp_soft_reset_frame`,
`mp_exec_frame`, `mp_eval_frame`, `mp_eval_repr_frame`.
Decoding: `mp_decoder_new`, `mp_decoder_reset`, `mp_decoder_feed`,
`mp_decoder_done`, `mp_decoder_state`, `mp_decoder_banner`,
`mp_decoder_result`, `mp_decode_trace`, `mp_parse_exec_response`,
`mp_frame_is_complete`.
Text/results: `mp_split_lines`, `mp_traceback_is_present`,
`mp_traceback_exception`, `mp_eval_extract`, `mp_eval`.
Errors: `mp_error`, `mp_error_name`, `mp_error_is_skip`,
`mp_error_absent`.

## 5. 100% coverage table

Every public symbol maps to at least one assertion in
`tests/test_conformance.xi`. Test names are the `[PASS]` labels.

| Symbol | Covered by |
|---|---|
| `MP_CTRL_A/B/C/D/E`, `MP_RAW_BANNER`, `MP_RAW_PROMPT`, `MP_FRIENDLY_PROMPT`, `MP_OK`, `MP_PRELUDE_MAX`, `MP_DEC_*`, `MP_ERR_*` | constants: control bytes, banner/prompt/OK texts, decoder/error kinds |
| `mp_interrupt_frame` | frames: Ctrl-C, Ctrl-A, CR+Ctrl-A flush, Ctrl-B, Ctrl-D soft reset; fixture: Ctrl-C mid-exec |
| `mp_enter_raw_frame` | frames: Ctrl-C, Ctrl-A, CR+Ctrl-A flush, Ctrl-B, Ctrl-D soft reset |
| `mp_enter_raw_flush_frame` | frames: Ctrl-C, Ctrl-A, CR+Ctrl-A flush, Ctrl-B, Ctrl-D soft reset |
| `mp_exit_raw_frame` | frames: Ctrl-C, Ctrl-A, CR+Ctrl-A flush, Ctrl-B, Ctrl-D soft reset; fixture: enter -> print(123) -> exit |
| `mp_soft_reset_frame` | frames: Ctrl-C, Ctrl-A, CR+Ctrl-A flush, Ctrl-B, Ctrl-D soft reset |
| `mp_exec_frame` | frames: exec/eval/repr exact bytes; empty input -> INVALID_ARG |
| `mp_eval_frame` | frames: exec/eval/repr exact bytes; fixture: eval helper returns 42 |
| `mp_eval_repr_frame` | frames: exec/eval/repr exact bytes; fixture: repr eval helper |
| `MpError`, `mp_error`, `mp_error_name`, `mp_error_is_skip`, `mp_error_absent` | errors: names, message prefix, skip classification; absent transport: SKIP |
| `MpDecoder`, `mp_decoder_new`, `mp_decoder_reset`, `mp_decoder_feed`, `mp_decoder_state`, `mp_decoder_banner`, `mp_decoder_result`, `mp_decoder_done` | decoder: one-byte chunks, reset/reuse, two-byte chunks; decoder: PRELUDE -> OK -> STDOUT -> STDERR -> DONE, tail ignored; decoder: incomplete, bad OK, oversized banner, ERROR state |
| `mp_decode_trace` | every fixture decode; decoder: bare OK, prompt-only, soft-reboot and CRLF-padded preludes |
| `mp_parse_exec_response` | fixture: enter -> print(123) -> exit |
| `mp_frame_is_complete` | fixture: enter -> print(123) -> exit; decoder: incomplete, bad OK, oversized banner, ERROR state |
| `MpExecResult`, `mp_split_lines` | line framing: CRLF/LF/CR, blanks, trailing newline, traceback line; every fixture decode |
| `mp_traceback_is_present`, `mp_traceback_exception` | fixture: ValueError traceback pass-through; fixture: compile SyntaxError; line framing |
| `mp_eval_extract`, `mp_eval` | fixture: eval helper returns 42; fixture: repr eval helper; fixture: ValueError traceback pass-through; fixture: empty stdout |

Coverage notes:

* All public functions and constants are exercised; `mp_decoder_feed`
  covers every state transition and both error returns.
* The only intentionally host-dependent leg is transport presence: the
  suite uses `XIOM_MICROPYTHON_PORT` as the trigger and asserts the typed
  `MP_ERR_ABSENT` SKIP path when unset. No hardware or live adapter is
  required for any protocol assertion.
* Fixtures are synthetic wire traces written from the framing rules in
  sec. 3 (not copied from upstream tests); see `PROVENANCE.md` sec. 4.

## 6. Error mapping

| Condition | Kind |
|---|---|
| Caller's transport open fails / no link | `MP_ERR_ABSENT` (SKIP) |
| Link read/write failure | `MP_ERR_IO` |
| Caller deadline expires | `MP_ERR_TIMEOUT` |
| No `OK` after Ctrl-D | `MP_ERR_PROTOCOL` |
| Missing first/second `0x04`, no prompt, prelude > 4096 bytes, feed after error | `MP_ERR_PROTOCOL` |
| Empty exec/eval expression | `MP_ERR_INVALID_ARG` |
| Device traceback, eval with no value | `MP_ERR_EXEC` (traceback in message) |

## 7. Deliberate deviations / limits

1. **No raw-paste mode.** The Ctrl-E `A` Ctrl-A negotiation and its flow
   control window are documented in `repl.rst` but not implemented in
   0.1.0. Standard raw REPL is the compatibility baseline.
2. **No soft-reset dance on enter.** `pyboard.py` sends Ctrl-C, drains,
   Ctrl-A and optionally Ctrl-D for a soft reset. The package separates
   the primitives (`mp_interrupt_frame`, `mp_enter_raw_flush_frame`,
   `mp_soft_reset_frame`); the caller decides whether to reset.
3. **`ok` reflects the stderr frame.** A program that writes to
   `sys.stderr` without raising is reported `ok == false`; the text is
   still available in `error` and `error_lines`.
4. **Prelude recognition** ends at the first `>` byte. A boot log that
   prints `>` before the raw banner would confuse a caller that feeds the
   whole log in one slice; feed the decoder only the enter-response
   stream (as the fixtures do).
5. **UTF-8 console text**, no binary payload passthrough (sec. 3.4).

## 8. Re-pin procedure

1. `git -C E:\repos\micropython fetch --depth 1 origin`; record the new
   tip in `PROVENANCE.md` and re-check `LICENSE` is still MIT.
2. Re-read `docs/reference/repl.rst` sec. "Raw mode", `pyexec.c`
   (`pyexec_raw_repl*`, `parse_compile_execute` EOF flags) and
   `pyboard.py` (`enter_raw_repl`/`exit_raw_repl`/`follow`/`exec_raw`);
   update sec. 3 and `PROVENANCE.md` if any byte changes.
3. Update the fixtures only when upstream framing changed (never to paper
   over a package bug).
4. Run `scripts/port.ps1 -Package xiom.micropython -TimeoutSec 300` x2 and
   record `STATUS.json` in the same touch.
