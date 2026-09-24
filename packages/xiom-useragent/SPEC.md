# xiom.useragent -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.useragent` (`src/useragent.xi`). Pure XIOM, no FFI.

## 1. Scope

Five infallible functions classify a raw `User-Agent` header value:

- `ua_browser` -- browser family (plus curl/wget/python-requests),
- `ua_version` -- browser version string,
- `ua_os` -- operating system family,
- `ua_is_bot` -- bot/crawler/scripted-client flag,
- `ua_is_mobile` -- mobile-device flag.

Every function lowercases its input once (`string.str_lower`) and matches
byte-wise against the curated token tables below, so matching is
case-insensitive. Functions return `Str`/`Bool`, never `Result`: there is
deliberately no error channel. Unknown input yields `""` or `false`.

## 2. Non-goals

- Full UA parsing (no parsing of names, comments or grammar).
- Client hints (`Sec-CH-UA-*`), device models, GPU or architecture data.
- Version comparison or semver semantics: `ua_version` returns a raw string.
- Detection of browsers not in the token table (e.g. Chrome on iOS `CriOS/`,
  Brave, Vivaldi, Samsung Internet all fall through to their embedded tokens).
- Any security use: the header is client-controlled and spoofable.

## 3. Token tables and precedence

Tokens are matched with `string.str_contains` on the lowercased UA (or with
the byte-wise `_find` scan for `ua_version`). All byte reads go through
`(string.byte_at(s, i) as Int) & 0xFF`, so comparisons happen in Int space.

### 3.1 `ua_browser(ua: Str) -> Str`

First matching token wins, in this order:

| Order | Token | Returns | Why this order |
|---|---|---|---|
| 1 | `edg/` | `"Edge"` | Edge UAs embed `Chrome/`. |
| 2 | `opr/` | `"Opera"` | Opera UAs embed `Chrome/`. |
| 3 | `chrome/` | `"Chrome"` | Chrome UAs embed `Safari/`. |
| 4 | `firefox/` | `"Firefox"` | Firefox UAs carry neither token. |
| 5 | `safari/` | `"Safari"` | Reached only when no `chrome/` matched. |
| 6 | `curl/` | `"curl"` | Scripted client. |
| 7 | `wget/` | `"wget"` | Scripted client. |
| 8 | `python-requests` | `"python-requests"` | Scripted client. |
| -- | none | `""` | Unknown. |

### 3.2 `ua_version(ua: Str) -> Str`

1. Detect the browser token with the section 3.1 precedence.
2. Find the first occurrence of that token in the lowercased UA.
3. Scan forward from the end of the token and return the first *dotted
   number*: one or more digits, then `.`, then a digit, then further digits
   and dot-digit pairs. The scan stops at the first byte that is not a digit
   and not a dot followed by a digit.
4. Return `""` when no browser token is detected, when there is no dotted
   number after the token, or when the only number is a bare integer.

Pinned examples: Chrome/120.0.0.0 -> `"120.0.0.0"`, Firefox/121.0 ->
`"121.0"`, curl/8.4.0 -> `"8.4.0"`, curl/unknown -> `""`, curl/8 -> `""`,
Googlebot/2.1 -> `""` (Googlebot is not a browser token). Note that Safari
reports the post-`Safari/` WebKit build (e.g. `605.1.15`), not the preceding
`Version/` value.

### 3.3 `ua_os(ua: Str) -> Str`

First matching token wins, in this order:

| Order | Token | Returns |
|---|---|---|
| 1 | `windows nt` | `"Windows"` |
| 2 | `android` | `"Android"` |
| 3 | `iphone` | `"iOS"` |
| 4 | `ipad` | `"iOS"` |
| 5 | `mac os x` | `"macOS"` |
| 6 | `linux` | `"Linux"` |
| -- | none | `""` |

iOS precedes macOS because iPhone/iPad UAs contain `like Mac OS X`; Android
precedes Linux because Android UAs contain `Linux`.

### 3.4 `ua_is_bot(ua: Str) -> Bool`

True when the lowercased UA contains any of:

| Token | Family |
|---|---|
| `bot` | Googlebot, bingbot, general `*bot` agents |
| `spider` | Baiduspider and friends |
| `crawler` | generic crawlers |
| `slurp` | Yahoo! Slurp |
| `curl/` | curl CLI |
| `wget/` | wget CLI |
| `python-requests` | python-requests library |
| `headless` | headless browsers |

### 3.5 `ua_is_mobile(ua: Str) -> Bool`

True when the lowercased UA contains any of:

| Token | Family |
|---|---|
| `mobile` | generic mobile marker (`Mobile Safari`, `Mobile/15E148`) |
| `android` | Android devices |
| `iphone` | iPhone |
| `ipad` | iPad |
| `ipod` | iPod touch |
| `windows phone` | Windows Phone |

## 4. API signatures

```xi
pub fn ua_browser(ua: Str) -> Str
pub fn ua_version(ua: Str) -> Str
pub fn ua_os(ua: Str) -> Str
pub fn ua_is_bot(ua: Str) -> Bool
pub fn ua_is_mobile(ua: Str) -> Bool
```

Complexity: O(ua.len()) per token probe; each public function lowercases once
and then probes at most eight constant tokens. No `Vec`, no allocation beyond
the lowercased copy.

## 5. Test plan

`tests/test_conformance.xi` (module `useragent_tests`) runs 19 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | Chrome on Windows | browser/version/os, not bot, not mobile |
| t2 | Edge beats Chrome | `Edg/120.0.0.0` wins over embedded `Chrome/118.0.0.0` |
| t3 | Opera beats Chrome | `OPR/105.0.0.0` wins over embedded `Chrome/118.0.0.0` |
| t4 | Safari on macOS | browser Safari without a Chrome token; `macOS` |
| t5 | Android Chrome | Chrome beats Safari; `Android` and mobile |
| t6 | Firefox on Linux | browser/version/os, not bot, not mobile |
| t7 | iPhone Safari | `iOS`, mobile, version after `Safari/` |
| t8 | iPad | `iOS`, mobile |
| t9 | curl and python-requests | browser names, bot flags, versions |
| t10 | wget | `wget/` bot, `linux-gnu` -> Linux |
| t11 | Googlebot | bot with empty browser/version/os |
| t12 | headless Chrome | `headless` bot token, Chrome and Linux detected |
| t13 | bot token variety | `spider`, `slurp`, `crawler`, `bot` |
| t14 | version pins | Chrome `120.0.0.0`, Firefox `121.0`, curl `8.4.0`, Googlebot `""` |
| t15 | unknown UA | browser/version/os empty, both flags false |
| t16 | empty string | everything empty/false; `curl/8` has no dotted number |
| t17 | mixed case | browser/os/bot/mobile tokens match case-insensitively |
| t18 | partial tokens | `curl/unknown` version empty, bare `Firefox/121.0`, bare `Edg/...` |
| t19 | Windows Phone | mobile true; `android` outranks `mac os x`; Safari token |

All `Str` equality goes through `streq` (`str_compare`), so BUG 17 (`==` on
`Str` values read from `Vec[Str]` elements) cannot apply; the suite uses no
`Vec` at all.

## 6. Known limitations

- Substring heuristics, not parsing: a UA that merely mentions a token is
  classified by it (e.g. `headless` marks a bot, Windows Phone reports
  Android because its UA embeds an Android token).
- Safari's `ua_version` is the post-token WebKit build, not `Version/`.
- Spoofable: the header is fully client-controlled; results are advisory.
- The token list is curated and intentionally small; unknown clients yield
  `""`/`false` rather than a best guess.

## 7. Compiler / stdlib notes

- v0.61.3: free functions only, no self methods, no lambdas, no `Vec`
  values, no `match`, and no struct-returning helpers.
- All helpers use `while`/`if`/`elif`/`else`; byte reads are widened once in
  `_byte_i` so no `UInt8` is compared against an integer literal.
- Stdlib surface used: `string.str_lower`, `string.str_contains`,
  `string.str_compare` and `string.str_slice`.
- Str equality is routed through `string.str_compare` inside the module
  (`_str_eq`) and through `compare.str_compare` in the tests.
