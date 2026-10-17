<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# C-ORBIT-08 repro: enum-in-tuple miscompile (crash) + `[N]UInt8` element cast sign-extension

**Compiler (original):** v0.64.3 (Windows shadow `xiom.new.0643`; WSL `~/.local/bin/xiom`) -- both parts reproduce on both platforms.
**Found by:** the ORBITDB M5.1 typed-values codec (`src/storage/tuple.xi`, 2026-10-11).

## v0.64.5 verdicts (re-verification wave 2026-10-15; official artifacts)

Windows shadow `xiom.new.0645` (`xiom.exe` sha256
`02f0857887e14e48...`, from `xiom-0.64.5-windows-x64.zip` sha256
`bd71e2d357b7a721...` vs SHA256SUMS); WSL canonical `~/.local/share/xiom`
(sha256 `c4aa877a8a4c219f...` == `xiom-0.64.5-linux-x64.tar.gz` `bin/xiom`).
Stock pin (no `XIOM_RUNTIME_DIR` override).

- **PART A -- FIXED for the filed shape (m305, `81e4743c`):**
  `repro_enum_tuple.xi` prints `repro A: n=8` / `repro A: custom=5` /
  `repro A: done`, exit 0, on BOTH platforms (was `0x80000003`/no output on
  v0.64.3). NOTE: the terminal-1 value is `n + 3` = 8 for input 5 -- the
  old "expected n=5" line in this README was a miscomputed expectation; the
  compiler output is CORRECT.
- **PART B -- still fixed (m260):** `repro_u8_cast.xi` prints three
  `248 (expected 248)` lines, exit 0. The `(b[i] as Int) & 0xFF` mask is
  RETIRED from `tuple2_push_f64_le` (v0.64.5 re-verified; suite green).
- **PART C -- STILL RED (sub-shape; filed as C-ORBIT-12 on the bus):**
  `repro_enum_tuple_enum_error.xi` -- a tuple with an enum element inside a
  Result whose ERROR type is ALSO an enum. `Result[(T8Val, Int), T8Err]`
  emits TWO names for one tuple struct and clang hard-fails:

  ```
  xiominput.ll:778:35: error: '%tmp17' defined with type
  '%struct.Tuple__repro_enum_tuple_enum_error.T8Val__Int = type
  { %struct.repro_enum_tuple_enum_error.T8Val, i64 }' but expected
  '%struct.Tuple__T8Val__Int = type
  { %struct.repro_enum_tuple_enum_error.T8Val, i64 }'
  ```

  The Int-error control (`Result[(T8Val, Int), Int]`) compiles and runs
  (sum=110, exit 0). Inside larger programs the same shape emits
  `unknown type 'Tuple__TValue__Int' -- defaulting to i64` and silently
  misdecodes (6 typed-value suite tests failed when the ORBITDB workaround
  was provisionally dropped). **The ORBITDB position-tuple workaround
  therefore STAYS** (`tuple2_read_value` returns `DbResult[TValue]` alone;
  callers advance via `tuple2_value_len`).

## v0.64.6 verdict (2026-10-16/17; official artifacts, pre-adoption)

Windows extract `%LOCALAPPDATA%\xiom.new-20261016-233955` (v0.64.6,
`xiom.exe` sha256 `0ff5c5c471498d8c...`); WSL canonical
`~/.local/share/xiom` (v0.64.6, `bin/xiom` sha256 `855bd7cc82c0f24f...`).

- **PART C -- FIXED for the MINIMAL repro only (m336):**
  `repro_enum_tuple_enum_error.xi` prints `repro C: sum=110 (expected
  110)`, exit 0 on BOTH platforms (was the clang name-mismatch hard
  error). Control green (`n=8`/`custom=5`/`done`); `repro_u8_cast.xi`
  3x `248 (expected 248)` (PART B holds).
- **LARGER-PROGRAM residual STILL RED on v0.64.6 (corrected 2026-10-17):**
  dropping the `DbResult[TValue]` workaround in `src/storage/tuple.xi`
  (natural position tuple) emits `unknown type 'Tuple__TValue__Int' --
  defaulting to i64` and fails 6 typed-value suite tests (154/160).
  Workaround restored; residual filed `REL-20261017-1154-orbitdb` (high);
  acceptance = suite 160/160 WITH the position tuple at the next archive.
  The `release-checks/compiler-compiler-v0.64.6.md` / `-v0.64.7.md` rows
  are corrected to PARTIAL.

## A. `Result[(Enum, Int)]` miscompiles -- hard crash or silently skipped match arms

`repro_enum_tuple.xi` -- `fn pick(c: Color) -> Result[(Color, Int), Int]`
with a payload enum. On v0.64.3 the compiler warned
(`unknown type 'Tuple__Color__Int' -- defaulting to i64`) and observed
output was a hard breakpoint or skipped arms; fixed by m305 (PART A above).

Workaround applied in-tree (still required -- see PART C): never put an enum
in a tuple when the Result's error type is an enum. `tuple2_read_value`
returns `DbResult[TValue]` alone, and the caller advances by
`tuple2_value_len(v)` (no position tuple).

## B. Fixed-size `[N]UInt8` element `as Int` sign-extends

`repro_u8_cast.xi` (v0.64.3):

```
[8]UInt8 array element `as Int`  ->  -8   (0xF8 sign-extended through i8)
Vec[UInt8] element `as Int`      ->  248  (correct zero-extension)
```

Fixed by m260 (verified on v0.64.4 and v0.64.5); the code reading bytes
through fixed-size arrays no longer masks (`tuple2_push_f64_le` retired
`& 0xFF` on 2026-10-15). `Vec[UInt8]` readers were always correct.

## C. `Result[(Enum, Int), Enum]` (tuple + enum ERROR type) still miscompiles

`repro_enum_tuple_enum_error.xi` -- minimal reduction of the ORBITDB
`DbResult[(TValue, Int)]` shape (both `TValue` and `DbError` are enums).
Two variants suffice (`Vn`, `Vi(x: Int)`); no Str/Vec/Float payloads
needed. Expected after fix: prints `repro C: sum=110`, exit 0.

## Files

- `repro_enum_tuple.xi` -- part A (payload enum in a tuple result; FILED).
- `repro_u8_cast.xi` -- part B (array vs vec element casts; FIXED).
- `repro_enum_tuple_enum_error.xi` -- part C (enum error type shape; OPEN).
