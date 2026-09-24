# xiom.password -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.password` (`src/password.xi`). Pure XIOM, no FFI.

## 1. Scope

Ten total functions that score and structurally check a password:

- `password_has_lower` / `password_has_upper` / `password_has_digit` /
  `password_has_symbol` -- the four ASCII byte-class detectors,
- `password_class_count` -- how many of the four classes are used (`0..4`),
- `password_longest_run` -- the longest run of byte-identical bytes,
- `password_score` -- the documented `0..100` heuristic score,
- `password_feedback` -- ordered improvement suggestions,
- `password_is_common` -- case-insensitive match against a caller list,
- `password_recommend_min` -- minimum-length/class policy gate.

All functions are total (no error channel) and use byte-wise scans only: no
floating point, no allocation beyond the returned `Vec[Str]`/`Str`, no I/O.
Dependencies: `xiom.string` (`byte_at`) and `xiom.string.compare`
(`str_eq_ignore_case`) from `xiom.std`.

## 2. Non-goals

- No cryptography of any kind: no hashing, salting, encryption, key
  derivation, random generation, or constant-time verification.
- No bundled dictionary, no breach-list/network lookup, no fuzzy matching:
  the common-password check is an exact match against a caller list.
- No entropy, pattern, keyboard-walk, date, leetspeak or username detection.
- No configuration, localization, custom weights, or user-facing message
  catalog; the suggestion strings are fixed and pinned by tests.
- No Unicode case folding or non-ASCII class detection.

## 3. Byte classes

The password is treated as its raw byte sequence (`xiom.string.byte_at`,
round-14 raw-byte semantics).

| Class | Code | Rule |
|---|---|---|
| lowercase | 1 | byte in `97..122` (`a-z`) |
| uppercase | 2 | byte in `65..90` (`A-Z`) |
| digit | 3 | byte in `48..57` (`0-9`) |
| symbol | 4 | byte in `33..126` and not in the three classes above |

Everything else belongs to no class:

- space (`32`), control bytes (`0..31`, `127`),
- **every non-ASCII byte (`>= 128`), including each byte of a multi-byte
  UTF-8 sequence. Non-ASCII bytes are *not* symbols and *not* letters.**
  Decided explicitly: `password_has_symbol` answers the question "is there
  printable-ASCII punctuation?" and answers false for `é`, `中`, `ß`, etc.

Example: `"caf\u{00E9}"` has byte length 5 (`c a f 0xC3 0xA9`), class count 1
(lowercase), longest run 1, score 30.

### 3.1 `password_has_lower/upper/digit/symbol(pw: Str) -> Bool`

True when at least one byte of `pw` is in class 1/2/3/4 respectively; false
for the empty string. Complexity `O(pw.len())`.

### 3.2 `password_class_count(pw: Str) -> Int`

The number of true results among the four detectors, `0..4`; `0` for the
empty string and for strings of spaces/control/non-ASCII bytes only.

### 3.3 `password_longest_run(pw: Str) -> Int`

The largest `L` such that `L` consecutive bytes of `pw` are equal, or `0`
when `pw` is empty. Comparison is byte equality (case-sensitive, spaces and
non-ASCII bytes included). `"abc"` -> 1, `"aab"` -> 2, `"aAaA"` -> 1,
`"aaabbb"` -> 3.

## 4. Score

### 4.1 `password_score(pw: Str) -> Int`

```
score = clamp( base + class_bonus - run_penalty - digit_penalty, 0, 100 )
```

| Term | Value |
|---|---|
| `base` | `min(4 * pw.len(), 60)` |
| `class_bonus` | `10 * password_class_count(pw)`, i.e. `0..40` |
| `run_penalty` | `5 * (L - 2)` summed over every maximal run of `L >= 3` byte-identical bytes |
| `digit_penalty` | `20` when `pw` is non-empty, every byte is an ASCII digit, and `pw.len() < 8`; else `0` |
| empty | `0` (the terms above already yield 0; pinned explicitly) |
| clamp | the result is clamped into `0..100` |

The maximum possible score is `60 + 40 = 100`. Pinned examples (also in the
conformance suite):

| `pw` | Score | Terms |
|---|---|---|
| `""` | 0 | empty |
| `"a"` | 14 | `4 + 10` |
| `"ab"` | 18 | `8 + 10` |
| `"abc"` | 22 | `12 + 10` |
| `"abcd"` | 26 | `16 + 10` |
| `"ab1"` | 32 | `12 + 20` |
| `"aB3!"` | 56 | `16 + 40` |
| `"aB3!a"` | 60 | `20 + 40` |
| `"aB3!aB3!aB3!aB3!"` | 100 | `60 + 40` |
| `"aa"` | 18 | `8 + 10`, run of 2 is free |
| `"aaa"` | 17 | `12 + 10 - 5` |
| `"aaaa"` | 16 | `16 + 10 - 10` |
| `"aaaaaa"` | 14 | `24 + 10 - 20` |
| `"aabbb"` | 25 | `20 + 10 - 5` |
| `"aaabbb"` | 24 | `24 + 10 - 10` |
| `"aaaaaaaaaaaaaaa"` (15) | 5 | `60 + 10 - 65` |
| `"1234567"` | 18 | `28 + 10 - 20` |
| `"12345678"` | 42 | `32 + 10`, 8 bytes is not `< 8` |
| `"123456"` | 14 | `24 + 10 - 20` |
| `"1"` / `"11"` / `"1111111"` | 0 | all-digit penalty clamps at 0 |
| `"Xk9#mQ2!vL7@pR4$"` | 100 | `60 + 40` |
| `"Tr0ub4dor&3xK9zQw"` | 100 | `60 + 40` |
| `"correct horse battery staple"` | 70 | `60 + 10`, one class only |

Complexity: `O(pw.len())`.

## 5. Feedback

### 5.1 `password_feedback(pw: Str) -> Vec[Str]`

If `password_score(pw) >= 80` the result is an empty vector. Otherwise the
suggestions whose conditions hold are appended, in this fixed order, each at
most once (first-seen order of the checks):

| # | Condition | Suggestion |
|---|---|---|
| 1 | `pw.len() < 8` | `Use at least 8 characters` |
| 2 | `!password_has_lower(pw)` | `Add lowercase letters` |
| 3 | `!password_has_upper(pw)` | `Add uppercase letters` |
| 4 | `!password_has_digit(pw)` | `Add digits` |
| 5 | `!password_has_symbol(pw)` | `Add symbols` |
| 6 | `password_longest_run(pw) >= 3` | `Avoid repeated characters` |
| 7 | non-empty and all bytes ASCII digits | `Avoid all-digit passwords` |

Pinned vectors:

| `pw` | Score | Feedback |
|---|---|---|
| `""` | 0 | `[Use at least 8 characters, Add lowercase letters, Add uppercase letters, Add digits, Add symbols]` |
| `"abc"` | 22 | `[Use at least 8 characters, Add uppercase letters, Add digits, Add symbols]` |
| `"1234"` | 6 | `[Use at least 8 characters, Add lowercase letters, Add uppercase letters, Add symbols, Avoid all-digit passwords]` |
| `"12345678"` | 42 | `[Add lowercase letters, Add uppercase letters, Add symbols, Avoid all-digit passwords]` |
| `"aaaaaaaaaaaaaa"` (14) | 6 | `[Add uppercase letters, Add digits, Add symbols, Avoid repeated characters]` |
| `"Ab3!eF6@gH"` | 80 | `[]` |
| `"Abbb3!eF6@g"` | 79 | `[Avoid repeated characters]` |

Note that the 80-point cutoff takes precedence: a high-scoring password with
a repeated run can still receive an empty feedback vector. Complexity:
`O(pw.len())`.

## 6. Common-password check

### 6.1 `password_is_common(pw: Str, common: &Vec[Str]) -> Bool`

True when some element of `common` equals `pw` under ASCII case folding
(`password_is_common("PASSWORD", ["password"]) == true`). The comparison is
over the whole string and exact otherwise: `"adm"` does not match `"admin"`,
and `"pass word"` does not match `"password"`. An empty list never matches;
an empty entry matches only the empty password. The module bundles no
dictionary of its own. Complexity: `O(common.len() * min(pw.len(), element
length))`.

## 7. Policy gate

### 7.1 `password_recommend_min(pw: Str, min_len: Int, min_classes: Int) -> Bool`

True when `pw.len() >= min_len` **and** `password_class_count(pw) >=
min_classes`, with:

- `min_len <= 0` imposes no length minimum (every length satisfies it),
- `min_classes` is clamped into `0..4`, so values below 0 impose no class
  minimum and values above 4 behave as "all four classes".

Pinned boundaries: `("abc", 3, 1)` -> true, `("abc", 4, 1)` -> false,
`("abc", 3, 2)` -> false, `("", 0, 0)` -> true, `("", 0, 1)` -> false,
`("aB1!", 4, 4)` -> true, `("aB1!", 5, 4)` -> false, `("aB1", 4, 4)` -> false,
`("aB1!", 0, 5)` -> true (clamped), `("abc", 0, 5)` -> false,
`("abc", -3, -1)` -> true. Complexity: `O(pw.len())`.

## 8. API signatures

```xi
pub fn password_has_lower(pw: Str) -> Bool
pub fn password_has_upper(pw: Str) -> Bool
pub fn password_has_digit(pw: Str) -> Bool
pub fn password_has_symbol(pw: Str) -> Bool
pub fn password_class_count(pw: Str) -> Int
pub fn password_longest_run(pw: Str) -> Int
pub fn password_score(pw: Str) -> Int
pub fn password_feedback(pw: Str) -> Vec[Str]
pub fn password_is_common(pw: Str, common: &Vec[Str]) -> Bool
pub fn password_recommend_min(pw: Str, min_len: Int, min_classes: Int) -> Bool
```

## 9. Test plan

`tests/test_conformance.xi` (module `password_tests`) runs 23 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Every `Str` comparison is routed through
`xiom.string.compare.str_compare` (`BUG 17`, see section 11). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | has_lower | `a-z` only; `""`, `A-Z`/digits, `é`, CJK -> false |
| t2 | has_upper | `A-Z` only; `""`, lowercase, `É` -> false |
| t3 | has_digit | `0-9` only; fullwidth digit `U+FF11` -> false |
| t4 | has_symbol | `!`, `~`, `_` true; space, DEL, alnum, `é` false |
| t5 | class_count | 0 (empty/spaces/non-ASCII), 1, 2, 3, 4 |
| t6 | longest_run small | empty 0, singles 1, runs 2..3 |
| t7 | longest_run mixed | case-sensitive, spaces and digits, 4-byte runs |
| t8 | score basics | empty 0; `4` per byte baseline |
| t9 | score classes | `+10` per class; 15-byte run + cap example |
| t10 | score runs | runs of 3+ lose 5 per byte beyond two |
| t11 | score all-digit | `-20` under 8 bytes, exactly 8 unaffected, clamps at 0 |
| t12 | score strong | long mixed strings reach 100; the XKCD passphrase is 70 |
| t13 | score/feedback cutoff | 80 -> `[]`, 79 -> one item |
| t14 | feedback order | length first, then missing classes in order |
| t15 | feedback empty pw | five items (length + four classes) |
| t16 | feedback digits | `1234` and `12345678` vectors with all-digit item |
| t17 | feedback run | 14 `a`s: three class items then the run item |
| t18 | is_common | case-insensitive match, non-match, empty list |
| t19 | is_common exactness | whole-string only; empty entry matches empty pw |
| t20 | recommend_min | length/class boundaries, empty password |
| t21 | recommend_min clamping | `min_classes` 0..4 clamp, `min_len <= 0` free |
| t22 | non-ASCII | `café`: 5 bytes, 1 class, score 30, 4 feedback items |
| t23 | symbol set | punctuation counts; whitespace, tab, alnum do not |

## 10. Known limitations

- The score is a structural heuristic, not NIST SP 800-63B, not zxcvbn, and
  not an entropy estimate; it ignores keyboard walks, dates, leetspeak and
  usernames, and gives `"correct horse battery staple"` only 70.
- No breach awareness and no bundled dictionary.
- No cryptography: scoring/validation only, no storage hashing.
- ASCII-only classes and case folding; non-ASCII bytes count for length and
  runs but for no class.
- Fixed thresholds, penalties and message strings; no configuration or
  localization.
- Case folding covers ASCII letters only, so `"É"` and `"é"` do not fold
  together in `password_is_common`.
- Single pass, linear scans, no index structure, no thread-safety and no
  `async` API.

## 11. Compiler / stdlib notes

- Implementation imports `xiom.string` (`byte_at`, raw-byte round-14
  semantics) and `xiom.string.compare` (`str_eq_ignore_case`); tests import
  `xiom.io`, `xiom.test`, `xiom.password` and `xiom.string.compare`.
- The tests route every `Str` equality through `str_compare`, never `==`
  (`BUG 17`: `==` on `Str` values read from `Vec[Str]` elements lowers to a
  pointer comparison). `password_is_common` compares through
  `str_eq_ignore_case`, so the same bug cannot apply to the library either.
- Byte predicates operate on typed `UInt8` locals from `byte_at` and compare
  against suffixed literals (`48u8`, ...), avoiding widening surprises.
- No `Result`/`Ok`/`Err` values are constructed, so the v0.61.3
  struct-return `Ok`/`Err` codegen bug does not apply. No compiler
  workarounds required.
