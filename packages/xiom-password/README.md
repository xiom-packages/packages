# xiom.password

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** password strength scoring and structural checks: ASCII character
> classes, byte-identical runs, a documented 0..100 heuristic score, ordered
> feedback suggestions, a caller-supplied "common password" check, and a
> minimum-length/class policy gate.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at` and
> `xiom.string.compare.str_eq_ignore_case`). Tests additionally use
> `xiom.test` and `xiom.io`.

## What it is

`xiom.password` is a small, dependency-free password *strength estimator*
with zero I/O: no hashing, no encryption, no key derivation, no bundled
dictionary, no network or breach-list lookups. It inspects the raw bytes of
a `Str` and answers structural questions:

- which of the four ASCII classes the password uses (lowercase, uppercase,
  digits, printable symbols),
- how long its longest run of byte-identical bytes is,
- a documented `0..100` heuristic score with pinned, testable rules,
- an ordered list of human-readable improvement suggestions,
- whether the password exactly matches (case-insensitively) an entry in a
  caller-supplied list of common passwords,
- whether the password meets a caller's minimum length and class count.

Every entry point is infallible (no `Result` channel). All comparisons of
`Str` values read from `Vec[Str]` elements go through
`xiom.string.compare` (`BUG 17`: the compiler lowers `==` on such values to a
pointer comparison).

### Byte classes

| Class | Rule |
|---|---|
| lowercase | byte in `97..122` (`a-z`) |
| uppercase | byte in `65..90` (`A-Z`) |
| digit | byte in `48..57` (`0-9`) |
| symbol | byte in `33..126` that is not alphanumeric |

Space (`32`), control bytes (`0..31`, `127`) and **non-ASCII bytes (`>= 128`,
including every byte of a multi-byte UTF-8 sequence) belong to no class**.
For example `"caf\u{00E9}"` has 5 bytes and one class (lowercase); the `é`
bytes count toward length and runs but never toward a class, and they do
**not** count as symbols.

## API

| Function | Returns | Description |
|---|---|---|
| `password_has_lower(pw)` | `Bool` | Any ASCII `a-z` byte. |
| `password_has_upper(pw)` | `Bool` | Any ASCII `A-Z` byte. |
| `password_has_digit(pw)` | `Bool` | Any ASCII `0-9` byte. |
| `password_has_symbol(pw)` | `Bool` | Any byte in `33..126` that is not alphanumeric. |
| `password_class_count(pw)` | `Int` | `0..4`, how many of the four classes are present. |
| `password_longest_run(pw)` | `Int` | Longest maximal run of identical bytes; `0` for empty, `1` for repeat-free. |
| `password_score(pw)` | `Int` | `0..100` heuristic score (formula below). |
| `password_feedback(pw)` | `Vec[Str]` | Ordered suggestions; empty when the score is already `>= 80`. |
| `password_is_common(pw, common)` | `Bool` | Case-insensitive exact match against the caller's `&Vec[Str]`. |
| `password_recommend_min(pw, min_len, min_classes)` | `Bool` | Policy gate: length `>= min_len` and classes `>= min_classes` (clamped). |

## Score formula

```
score = clamp( min(4 * len(pw), 60) + 10 * class_count - penalties, 0, 100 )
```

| Term | Contribution |
|---|---|
| length base | `min(4 * len(pw), 60)` |
| class bonus | `10 * password_class_count(pw)` (`0..40`) |
| run penalty | `-5 * (L - 2)` for every maximal run of `L >= 3` byte-identical bytes |
| all-digit penalty | `-20` when `pw` is non-empty, every byte is an ASCII digit, and `len < 8` |
| empty password | `0` |

Pinned examples:

| Password | Score | Why |
|---|---|---|
| `""` | 0 | empty |
| `"a"` | 14 | `4 + 10` |
| `"abc"` | 22 | `12 + 10` |
| `"aB3!"` | 56 | `16 + 40` |
| `"aB3!aB3!aB3!aB3!"` | 100 | length base caps at 60 |
| `"aaaaaa"` | 14 | `24 + 10 - 20` (run of 6) |
| `"aaabbb"` | 24 | two runs of 3 |
| `"1234567"` | 18 | `28 + 10 - 20` (all-digit, short) |
| `"12345678"` | 42 | 8 digits: no all-digit penalty |
| `"1111111"` | 0 | penalties clamp at 0 |
| `"Xk9#mQ2!vL7@pR4$"` | 100 | `60 + 40` |
| `"correct horse battery staple"` | 70 | `60 + 10`; even a famous passphrase scores 70 here |

## Feedback

`password_feedback` returns the suggestions whose conditions hold, in this
fixed order, each at most once, and an **empty vector when
`password_score(pw) >= 80`**:

| # | Condition | Suggestion |
|---|---|---|
| 1 | `len < 8` | `Use at least 8 characters` |
| 2 | no lowercase | `Add lowercase letters` |
| 3 | no uppercase | `Add uppercase letters` |
| 4 | no digit | `Add digits` |
| 5 | no symbol | `Add symbols` |
| 6 | longest run `>= 3` | `Avoid repeated characters` |
| 7 | non-empty and all ASCII digits | `Avoid all-digit passwords` |

For example `"1234"` yields `["Use at least 8 characters", "Add lowercase
letters", "Add uppercase letters", "Add symbols", "Avoid all-digit
passwords"]`; `"Ab3!eF6@gH"` (score 80) yields `[]`.

## Usage

```xi
use xiom.password;
use xiom.convert.int;
use xiom.io;

fn main() -> Int {
  io.println(int_to_string(password_score("Xk9#mQ2!vL7@pR4$")));  // 100
  io.println(int_to_string(password_score("123456")));            // 14
  io.println(int_to_string(password_score("")));                  // 0

  var common = Vec[Str].new();
  common.push("password");
  common.push("qwerty");
  if password_is_common("PASSWORD", &common) {
    io.println("known common password");
  }

  let fb = password_feedback("abc");
  var i = 0;
  while i < fb.len() {
    io.println(fb[i]);
    i = i + 1;
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.password
```

Expected: the namespaced module passes the section-4 namespace rule, 23
`[PASS]` lines, `xiom.password: all tests passed`, and a final
`port: PASS (passed=23 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Heuristic, not authoritative.** The score is a small structural formula
  (length, classes, runs, short all-digit strings). It is **not** NIST
  SP 800-63B guidance, not zxcvbn, not an entropy or pattern-aware estimate,
  and it does not model keyboard walks, dates, leetspeak or usernames.
- **No breach awareness.** There is no bundled dictionary and no network
  access; `password_is_common` only checks the caller-supplied list.
- **No cryptography.** The package never hashes, salts, encrypts, generates
  or verifies passwords; it is a scoring/validation helper only. Store
  passwords with a dedicated hashing library and policy server.
- **ASCII-only classes.** Non-ASCII bytes (each byte of a UTF-8 sequence)
  belong to no class, so accented or CJK characters increase length but
  never the class count; they are not symbols either.
- **Fixed policy thresholds.** The 8-byte threshold, the 80-point feedback
  cutoff, the `-5`/`-20` penalties and the exact suggestion wording are
  pinned by tests; there is no configuration, localization or custom
  weighting.
- **Feedback is coarse.** At most one suggestion per rule, in the fixed
  order; it is empty above the cutoff even if a run remains (for example a
  score-80+ password may still contain a repeated run).
- **A famous passphrase scores 70.** The XKCD passphrase scores `60 + 10`
  under this heuristic, which shows the formula's length-vs-classes
  trade-off; raise the score with symbols/digits or more length.
- Single-pass, allocation-light scans; no index, no thread-safety, no
  `async` API.

See `SPEC.md` for the exact rules, the pinned examples and the full test
plan. License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
