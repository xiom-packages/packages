# xiom.useragent

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** User-Agent heuristics: browser family, version, operating system,
> bot and mobile detection.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string`). Tests additionally
> use `xiom.test`, `xiom.io` and `xiom.string.compare`.

## Scope

`xiom.useragent` classifies a raw `User-Agent` header value with five small,
infallible functions. Every input is lowercased once with `string.str_lower`
and then matched byte-wise against a curated token list, so matching is
case-insensitive by construction. There is no FFI, no allocation beyond the
lowercased copy, and no dependency beyond `xiom.string`.

## API

| Function | Returns | Description |
|---|---|---|
| `ua_browser(ua)` | `Str` | `"Edge"`, `"Opera"`, `"Chrome"`, `"Firefox"`, `"Safari"`, `"curl"`, `"wget"`, `"python-requests"`, or `""` when no token matches. |
| `ua_version(ua)` | `Str` | First dotted number after the detected browser token (`"120.0.0.0"`, `"8.4.0"`); `""` when the browser is unknown or no dotted number follows the token. |
| `ua_os(ua)` | `Str` | `"Windows"`, `"Android"`, `"iOS"`, `"macOS"`, `"Linux"`, or `""` when unknown. |
| `ua_is_bot(ua)` | `Bool` | True when the UA contains any bot token (`bot`, `spider`, `crawler`, `slurp`, `curl/`, `wget/`, `python-requests`, `headless`). |
| `ua_is_mobile(ua)` | `Bool` | True when the UA contains any mobile token (`mobile`, `android`, `iphone`, `ipad`, `ipod`, `windows phone`). |

## Precedence

### Browser (`ua_browser`)

The first token in this order wins; the order matters because Edge, Opera and
Chrome emitters embed tokens of the browsers below them:

| Order | Token (matched in the lowercased UA) | Returns |
|---|---|---|
| 1 | `edg/` | `Edge` |
| 2 | `opr/` | `Opera` |
| 3 | `chrome/` | `Chrome` |
| 4 | `firefox/` | `Firefox` |
| 5 | `safari/` (reached only without a `chrome/` token) | `Safari` |
| 6 | `curl/` | `curl` |
| 7 | `wget/` | `wget` |
| 8 | `python-requests` | `python-requests` |
| -- | no match | `""` |

### Operating system (`ua_os`)

| Order | Token | Returns |
|---|---|---|
| 1 | `windows nt` | `Windows` |
| 2 | `android` | `Android` |
| 3 | `iphone` | `iOS` |
| 4 | `ipad` | `iOS` |
| 5 | `mac os x` | `macOS` |
| 6 | `linux` | `Linux` |
| -- | no match | `""` |

iOS is probed before macOS because an iPhone/iPad UA also carries the
`like Mac OS X` token; Android is probed before Linux for the same reason.

## Usage

```xi
use xiom.useragent;
use xiom.io;

fn main() -> Int {
  let ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";
  if ua_browser(ua) == "Chrome" {
    io.println("chrome " + ua_version(ua) + " on " + ua_os(ua));
  }
  if ua_is_bot("curl/8.4.0") {
    io.println("scripted client");
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.useragent
```

Expected tail: 19 `[PASS]` lines, `xiom.useragent: all tests passed`, then
`port: PASS (passed=19 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Heuristic substring matching:** detection is `str_contains` on a
  lowercased copy, not UA parsing; ordering artifacts are possible (an iPhone
  Safari UA reports Safari's post-token WebKit build, and a Windows Phone UA
  reports Android because its UA embeds an Android token).
- **Spoofable:** the `User-Agent` header is client-controlled, so every result
  is advisory only. Do not use it for access control or security decisions.
- **Curated token list:** only the tokens in `SPEC.md` section 3 are
  recognized (e.g. Chrome on iOS via `CriOS/` is not detected as Chrome, and
  `headless` is treated as a bot token even for otherwise-normal browsers).
- `ua_version` returns the first dotted number after the detected token, not a
  parsed major/minor/patch tuple, and `""` for bare integers (`curl/8`).

See `SPEC.md` for the full token tables, precedence rules and test plan.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
