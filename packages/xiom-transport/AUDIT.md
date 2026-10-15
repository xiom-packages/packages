# xiom.transport -- Audit

Package: `xiom.transport` 0.1.0 (incubating). Toolchain: XIOM v0.64.5
(pinned by the repo harness), stdlib `E:\xiom-lang\stdlib`. Windows notes
apply (see SPEC.md sec. 11). No upstream code, no FFI to any upstream
library, no bridge C; PROVENANCE.md carries the independent declaration.

## Verification record

Required harness command (run from the packages repo root):

```
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/port.ps1 -Package xiom.transport -TimeoutSec 900
```

Run 1 (2026-10-15, this session):

```
port: PASS (passed=36 failed=0 program_exit=0 exit=0)
```

Run 2 (identical command, immediately after):

```
port: PASS (passed=36 failed=0 program_exit=0 exit=0)
```

Both runs: same N (36 checks), 0 failures, program exit 0, harness exit 0.
The suite prints one `[PASS]`/`[FAIL]` line per check
(`tests/test_conformance.xi` drives five suites; 7 + 8 + 10 + 6 + 5 = 36).

## Socket probe record (pre-implementation, 127.0.0.1)

Scratch probes were run before writing the package to verify the stdlib
transport surface (per the task's VERIFY requirement):

| probe | checks | result |
|---|---|---|
| A | `socket_udp` create, `socket_bind` (two endpoints 47921/47922), `socket_send_to` | PASS (send_to OK, 9 bytes) |
| B | `socket_set_nonblocking` + `socket_poll_read` after send | PASS (ready=1 within 2 s) |
| C | stdlib `socket_recv_from` + 3-tuple destructure `(Vec[UInt8], Str, Int)` | **BROKEN** (garbage fields, access violation; see TB-1) |
| D | user-level 3-tuple `(Vec[UInt8], Str, Int)` roundtrip | BROKEN independent of sockets (TB-1 confirmed as a compiler issue) |
| E | tuple matrix `(Str,Int)`, `(Vec,Int)`, `(Vec,Str)`, `(Int,Int)` | PASS |
| F | `socket_recv` on a bound (unconnected) UDP socket | PASS (payload received; no peer address) |
| G | raw runtime `xiom_socket_recvfrom` extern with pointer out-parameters | PASS (payload byte-exact, peer `127.0.0.1:47941` correct) |
| H | `&mut` of a struct field through a `&mut` parameter, deref assignment | PASS |
| I | `xiom.test.assert` + `TestResult.name` in a plain module | PASS |
| J | 4-field enum variant pattern matching | PASS |

Outcome: the stdlib socket surface is usable for this package except the
tuple-returning `socket_recv_from` wrapper; the runtime primitive itself
is sound (probe G), so `xiom.transport.udp` declares that runtime entry
point directly (the package's only extern) and wraps it byte-safely.

## Toolchain findings (reproduced and minimized before working around)

### TB-1: mixed-element tuples are miscompiled (blocker, worked around)

- The stdlib wrapper `socket_recv_from` returns
  `Result[(Vec[UInt8], Str, Int), Str]`. On the pinned compiler this
  lowers with `warning: unknown type 'Tuple__Vec[UInt8]__Str__Int' --
  defaulting to i64` and produces garbage fields and access violations
  (probe C; reproduced fully in user code, probe D, without sockets).
- The same defect hit this package's own code: sim's internal
  `(Int, Int, Bool, Bool)` decision tuple produced a clang link-time type
  clash (`'%struct.Tuple__Int__Int__Int__Int' but expected
  '%struct.Tuple__Int__Int__Bool__Bool'`) during the first full build.
- Workaround (package-wide discipline): no tuple crosses a function
  boundary anywhere in `xiom.transport`; mixed facts travel in named
  structs (`SimDecision`, `SimRelease`, `ReasmOutcome`, ...). 2-element
  homogeneous tuples remain unused too. AUDIT keeps this visible for the
  toolchain lane: once tuples are fixed, the sim decisions can collapse
  back and the stdlib `socket_recv_from` wrapper can replace the runtime
  declaration (ROADMAP item 7).

### TB-2: ambiguous bare `assert` mis-resolves to `xiom.core.assert`

- When this package's suite modules were compiled through the package
  harness, bare `assert(...)` calls inside modules of certain namespaces
  (e.g. `xiom.transport.*`, `xiom.aaa.*`, `xiom.zzz.*`) bound to
  `xiom.core.assert` (a void function) instead of `xiom.test.assert`
  (returns `TestResult`), yielding `zeroinitializer` results -- every
  check "failed" with an empty name, and printing the garbage name could
  access-violate. Minimized to a two-file probe; qualifying the call as
  `test.assert(...)` resolves deterministically.
- Workaround: every suite calls `test.assert` qualified (recorded in
  test_conformance.xi's header comment). The package's non-test code does
  not reference `assert` at all.
- Note: `xiom-redis` passes on the same toolchain with bare `assert`
  (verified in-session), so this is name/order dependent, not universal;
  the qualification is a no-op under a fixed resolver.

### TB-3: moved-value warnings (fixed in-package)

`--emit-ir` warned (`E001: use of moved value`) on patterns like
"assign a struct into a vector, then read its fields again". All such
patterns in the package were restructured to fresh copies (`_reasm_place`
reads through re-bound locals; `sim` copies the capture record explicitly;
`delivered_info` borrows the poll). No E001 warnings remain in the final
build.

## Adversarial checks already in the suite

- Truncation/garbage frames: typed errors with exact offsets
  (suite_frames f5/f6), hard caps (f7).
- Far-future / stale sequences refused with counters (suite_reliable r4/r6).
- Foreign `conn_id` refused (session path `TX_ERR_CONN_ID`); unknown
  channel refused (`TX_ERR_CHANNEL`, suite_session s4).
- Version mismatch refuses with a FIN report and a Closed state
  (suite_session s3); sends after close are typed refusals.
- Duplicate fragments suppressed; a partial message is never delivered or
  acked (suite_session s6/s8).
- Reliability timeouts produce typed events plus a draining transition,
  never a hang (suite_session s9).

## Known limitations and open risks

- **File sizes**: `session.xi` (882 lines), `reliable.xi` (749) and
  `suite_session.xi` (726) exceed the 400-600 line guidance. The module
  names and the one-file-per-module layout are fixed by the design
  (nine modules); splitting would either add modules beyond the declared
  list or fragment cohesive state machines. Disclosed rather than hidden.
- **Root facade handle** carries placeholder structs for the unselected
  backends (documented in transport.xi); only the kind-selected member is
  ever read. A variant payload enum was avoided deliberately (mutation
  through reference-matched payloads is unproven on this toolchain).
- **UDP readability gate**: `udp_poll` treats non-blocking recvfrom -1 as
  end-of-drain (would-block and error are indistinguishable on this
  runtime). A genuine receive error is therefore surfaced as an empty
  poll rather than `UDP_ERR_RECV`; the readiness gate and drain bound keep
  this honest and bounded. Documented in SPEC.md sec. 11.
- **Zero-length datagrams** are legal on this path (send returns OK 0,
  receive yields an empty payload) and are covered by suite_udp u5.
- **SKIP paths**: if the UDP port ranges are exhausted, four checks print
  an explicit `SKIP` line inside the check name (counted as passes by the
  harness, never fake-passing a live roundtrip). None of the two recorded
  runs took a SKIP path (all five UDP checks executed against
  `127.0.0.1`); the honest-SKIP mechanism is the `xiom-redis`
  `suite_live` convention.
- **No STATUS.json** was written by design: package status registration
  belongs to `scripts/status.ps1` (the harness prints the exact command;
  see the README/ROADMAP for the human-run step).
