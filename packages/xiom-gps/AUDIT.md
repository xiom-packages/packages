# xiom.gps -- AUDIT

Copyright (c) 2026 Eleftherios Notas and The XIOM Authors.
SPDX-License-Identifier: MIT OR Apache-2.0.

Compiler pin: **v0.64.5** (`%LOCALAPPDATA%\xiom.new\bin\xiom.exe`,
stdlib `E:\xiom-lang\stdlib` at the pin). Suite entry:
`.\scripts\port.ps1 -Package xiom.gps -TimeoutSec 300`.

## 1. Suite evidence (x2, committed tree)

Run on commit `0110181e` (branch `feat/gps-binding`), both runs
identical:

```
port: xiom.gps
namespace-check: stdlib E:\xiom-lang\stdlib (1954 module namespaces)
  xiom.gps                 OK (1 module(s))
namespace-check: 1 package(s), 1 module(s), 0 conflict(s)
=== xiom.gps conformance tests ===
  ... 28 x [PASS] ...
port: PASS (passed=28 failed=0 program_exit=0 exit=0)
```

The two fixture sweeps and 26 value/error tests cover the declared
surface; the live-daemon leg is exercised as a typed SKIP on this host
(no gpsd listening on 127.0.0.1:2947):

```
[PASS] client-skip: SKIP -- no gpsd on 127.0.0.1:2947
       (gps: connect 127.0.0.1:2947 refused: socket_connect: connect failed)
```

## 2. v0.64.5 compiler findings (all reproduced with scratch probes)

These findings shaped the source and the test discipline; they are
recorded for the next lane that touches struct-heavy parsers.

### 2.1 "use of moved value" (E001) is advisory, not fatal

Passing one heap value to several *exclusive* conditional consumers
(separate `if`s, else-if chains, match arms) emits E001 warnings even
though exactly one consumer runs. Probes (JsonValue values into
differently-typed extractors) always produced correct results, but a
warning-laden compile is poor evidence. The shipped design avoids the
pattern entirely: each JSON entry value is normalized **once** through
`_slot_of` into a `JSlot` struct of primitives, and all extraction
reads local primitives. Final compile of `src/gps.xi` is
warning-free.

### 2.2 Reading struct fields through reference parameters returns garbage

Probe: `fn opt_s_eq(o: &Option[Str], ...)` read `o.value` and compared
lengths -- got an empty string for a present 24-char value.
Probe: `fn _slot_num(sl: &JSlot)` reading `sl.fval` returned
`4.6310479741946e+18` for a decoded `41.574970205`. By-value
parameters with locals-first reads are correct; by-reference field
reads are not.

Consequences in the shipped code: no helper takes `&Struct` and reads
its fields; extraction helpers take primitives
(`_mk_str(ok, s)`, `_mk_num(ok, f)`, `_mk_int(ok, f)`,
`_mk_bool(ok, b)`) with callers passing `sl.kind == _JK_X` plus the
field expression; array payloads are copied into typed locals
(`let sats_v: Vec[JsonValue] = sl.aval;`) before use.

### 2.3 Hoisting many Option-typed struct fields into locals corrupts values

Probe: parse the recorded TPV, bind all 19 fields to typed locals,
then compare `lat`/`lon` -- values were garbage (`4.6e18`) or the
process faulted (`0xC0000005`) at a later read; the same reads
performed one-field-at-a-time directly off the struct expression are
correct (verified for all 11 float fields + ints/strings, including
the 16-satellite SKY walk). The suite therefore passes struct field
expressions straight into helpers and binds only `Bool` results
before `!`/concatenation. This is also why the tests assert through
helper functions (`opt_f_eq(t.lat, ...)`) rather than local copies.

### 2.4 Helper-call results nested in expressions can fault

Probe: `io.println("..." + bs(opt_f_eq(...)))` crashed, while
`let c = opt_f_eq(...);` followed by a separate check ran clean. Test
discipline: every helper result gets a typed local first (all 28
tests follow this).

### 2.5 Other traps observed

- `Bool as Int` is not a supported cast; format booleans with an
  `if/else` returning `"true"`/`"false"`.
- A `let` plus if/else inside a match-arm block as the arm's value
  trips T001 (`expected T, found ()`); restructure so arms end in
  explicit expressions or returns.
- `&struct.field` reference passing must be avoided (documented
  MQTT-lane trap): `gpsd_client_read_line` snapshots `c.buf` into a
  local, works on it, and writes it back before every exit.
- Deref assignment through `&mut Vec[UInt8]` (`*v = nb`) is fine
  (stdlib precedent) and is used for buffer compaction.
- Stdlib engine names are trusted: `xiom.serialize.json`
  (`json_parse`/`json_get`/`JsonValue`) decoded every upstream
  recording; its Object Map iteration gave stable key access.

## 3. Value-rule verification highlights

- Checksum: recomputed 0x7E for the fuzzy-cases GGA; case-insensitive
  hex, CR/LF and post-checksum trailing bytes tolerated (daemon
  parity); mismatch/non-hex/truncated/missing all produce distinct
  error strings.
- Coordinates: recorded `4134.49821229 N` / `09345.03351845 W` decode
  to `41.574970205` / `-93.750558641` (<= 1e-6), matching the daemon's
  `.chk` output; southern hemisphere probe negates.
- Time/date: `132820.60` -> 13:28:20.600; `180320` -> 2020-03-18;
  century edges 1969 (yy=69) and 2068 (yy=68) verified.
- Magvar: `0.0,E` and `0.05,W` -> absent; `10.5,W` -> -10.5.
- GSA: `E` fix type -> 0; PRN `00` skipped, `601` gated, `600` kept;
  PDOP `0.00` and HDOP `99.99` -> absent, VDOP `89.99` kept.
- GSV: empty el/az record keeps both absent while SNR keeps its
  value; `az=360` -> 0; `el=95` -> absent; Quectel two-extra-field
  form decodes signal id + system id (5 accepted, 7 rejected).
- Dispatch: recorded lines produce the declared variants; `GST` ->
  `Other("GST")`; a concatenated multipacket line is rejected.

## 4. Coverage limits (explicit)

- **Live socket read path.** With no gpsd on this host, `open` proves
  the ABSENT classification and `close`/`send`/`read_line` prove the
  closed-client paths; the connected loop (recv framing, buffer
  write-back) is not executed at runtime here. ROADMAP 0.2 adds a
  fixture gpsd server to close this gap; the code is written to the
  documented discipline above.
- **Legacy numeric `activated`** is covered by a single DEVICE line
  (inline, cited); no full old-daemon DEVICES capture was imported.
- **`$STI,` checksum exception** is documented (SPEC 6.3) but not
  implemented -- the sentence is outside the declared set.
- **Aggregate behaviors** (cycle merging, PRN normalization, dedup)
  are out of scope by design (SPEC 6.4).

## 5. Provenance/license audit

gpsd license (BSD-2-Clause) verified from the clone's `COPYING` and
`LICENSE` before study; no upstream code was copied; imported
fixtures are verbatim upstream *data* with in-file attribution and
zero-modification. Details in PROVENANCE.md.
