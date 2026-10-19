# xiom.micropython -- AUDIT

Copyright (c) 2026 Eleftherios Notas and The XIOM Authors.
SPDX-License-Identifier: MIT OR Apache-2.0.

Compiler pin: **v0.64.7** (`E:\xiom-lang\xiom\target\release\xiom.exe`,
stdlib `E:\xiom-lang\stdlib`, 2006 module namespaces). Suite entry:
`.\scripts\port.ps1 -Package xiom.micropython -TimeoutSec 300`.

## 1. Suite evidence (x2, committed tree)

Feature commit: the commit carrying this file; the tested hash is recorded
in `STATUS.json` `tests.commit` (record commit follows the tested feature
commit, as usual for the lane).

Both runs are identical and warning-free:

```
port: xiom.micropython
  compiler: 0.64.7 (repo-release)
  stdlib:   E:\xiom-lang\stdlib
namespace-check: stdlib E:\xiom-lang\stdlib (2006 module namespaces)
  xiom.micropython         OK (1 module(s))
  suite:    tests/test_conformance.xi
=== xiom.micropython conformance tests ===
  [PASS] constants: control bytes, banner/prompt/OK texts, decoder/error kinds
  [PASS] frames: Ctrl-C, Ctrl-A, CR+Ctrl-A flush, Ctrl-B, Ctrl-D soft reset
  [PASS] frames: exec/eval/repr exact bytes; empty input -> INVALID_ARG
  [PASS] fixture: enter -> print(123) -> exit (host bytes + decode)
  [PASS] fixture: bare-OK slice with CRLF/CR line framing
  [PASS] fixture: ValueError traceback pass-through + eval error
  [PASS] fixture: compile SyntaxError keeps the OK + EOF framing
  [PASS] fixture: Ctrl-C mid-exec -> KeyboardInterrupt in stderr frame
  [PASS] fixture: eval helper returns 42 (frame + extract)
  [PASS] fixture: repr eval helper returns the Python literal
  [PASS] fixture: empty stdout decodes cleanly; eval reports no output
  [PASS] fixture: UTF-8 stdout bytes survive the framing
  [PASS] line framing: CRLF/LF/CR, blanks, trailing newline, traceback line
  [PASS] decoder: one-byte chunks, reset/reuse, two-byte chunks
  [PASS] decoder: PRELUDE -> OK -> STDOUT -> STDERR -> DONE, tail ignored
  [PASS] decoder: incomplete, bad OK, oversized banner, ERROR state
  [PASS] decoder: bare OK, prompt-only, soft-reboot and CRLF-padded preludes
  [PASS] errors: names, message prefix, skip classification
  [PASS] absent transport: SKIP -- no link/port in this environment; typed MP_ERR_ABSENT SKIP path verified
xiom.micropython: all tests passed
  exit code: 0
port: PASS (passed=19 failed=0 program_exit=0 exit=0)
```

`XIOM_MICROPYTHON_PORT` was unset in both runs, so the absent-transport
leg took its typed SKIP branch. No hardware, socket or serial device was
opened by any test: every protocol assertion is a byte fixture.

## 2. What the evidence proves

* **Frames:** exact bytes for Ctrl-C, Ctrl-A, CR+Ctrl-A, Ctrl-B, Ctrl-D
  soft reset, exec termination, eval and repr-eval wrappers; empty input
  rejected before a frame is produced.
* **Framing:** banner/prompt preludes (including a soft-reset boot log),
  bare-`OK` response slices, `OK` + stdout EOF + stderr EOF + trailing
  prompt, and ignored post-EOF bytes.
* **Traceback pass-through:** the ValueError error string is asserted
  byte-for-byte (`\r\n` preserved), and syntax errors and
  `KeyboardInterrupt` follow the same two-EOF shape.
* **Chunking:** the enter/print fixture decodes when fed one byte at a
  time; the traceback fixture decodes in two-byte chunks; reset/reuse is
  checked on the same decoder.
* **Errors:** incomplete response, bad `OK`, oversized prelude, feed
  after failure, and `mp_eval` on malformed input all return
  `MP_ERR_PROTOCOL`; INVALID_ARG and EXEC paths are pinned.
* **SKIP safety:** `mp_error_absent` / `mp_error_is_skip` classify an
  absent link as SKIP, and the suite stays green without one.

## 3. Compiler-pin findings (v0.64.7)

### 3.1 A UTF-8 BOM on a module source silently removes it from the catalog

The first build failed with `unresolved import 'xiom.micropython'` even
though `--graph` discovered the module and `--emit-ir` on the source
passed. Root cause: the source file began `EF BB BF` (UTF-8 BOM). The
catalog's fast header reader (`xiom-check` `read_module_header`) skips
whitespace/comments then expects a preamble keyword or `module`; the BOM
is an unexpected character, so the header is `None` and the file is never
indexed. The graph's lexer tolerates the BOM, hence the split brain.

Fix: save module sources **without BOM**. After stripping the BOM the
same tree builds and runs. The persistent catalog index
(`%USERPROFILE%\.xiom\catidx-<version>-<os>-<arch>.txt`) had cached the
bad entry with header `-`; the size change from the rewrite invalidates
it and the next compile re-scans. Recommendation to the compiler lane:
treat a leading BOM as whitespace in `read_module_header` (or reject it
with an explicit diagnostic instead of a silent unresolved import).
Repro: prefix any compiled package module with BOM and observe the
import fail while `--graph` still shows the module.

### 3.2 Catalog/diagnostic split (observed, no action required here)

`--graph` resolves the module from `package.xi`/`src` even when the
catalog cannot index it (finding 3.1). This is useful for diagnosis:
graph success plus unresolved import means "catalog did not index",
not "module missing".

No other compiler issues were hit. The source compiled warning-free on
the first non-BOM run, including `Vec[UInt8]` mutation, struct-result
returns and by-reference reads.

## 4. Coverage

The 100% table in `SPEC.md` sec. 5 maps every public function and
constant to a test label. There are no declared-but-untested symbols.
The only non-running branch is a live transport, which is out of scope
for 0.1.0 and represented by the typed SKIP path; the suite executes the
classification rather than skipping the assertion.

## 5. Reproduce

```
git checkout <feature commit>
.\scripts\port.ps1 -Package xiom.micropython -TimeoutSec 300   # x2
```

Expected: `PASS (passed=19 failed=0 program_exit=0 exit=0)` twice.
No environment variables are required; `XIOM_MICROPYTHON_PORT` must stay
unset to exercise the absent-transport SKIP note.
