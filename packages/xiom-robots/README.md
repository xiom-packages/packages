# xiom.robots

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** robots.txt parsing, canonical emitting and rule matching over
> in-memory `Str` values; no fetching, no file I/O.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.str_trim`, `xiom.string.str_len`,
> `xiom.string.builder` and `xiom.string.compare.str_compare`; the emitter
> also uses `xiom.convert.int_to_string`). Tests additionally use `xiom.test`
> and `xiom.io`.

## Overview

`xiom.robots` is a small, dependency-free codec for the documented robots.txt
subset:

- `User-agent:` groups -- one or more agent lines per group, with the `*`
  wildcard;
- `Allow:` / `Disallow:` rules in source order, including the documented
  empty `Disallow:` (allow-all);
- `Crawl-delay:` -- a non-negative integer per group;
- `Sitemap:` -- absolute http/https URLs recorded separately, document-wide;
- `#` comments to end of line and blank lines;
- field names matched ASCII case-insensitively;
- unknown fields rejected with a deterministic error.

A parsed document is a flat record of parallel vectors (groups as ranges),
plus matching helpers that implement longest-match precedence with `*`
wildcards, `$` end-anchors and the documented allow-wins tie rule. The
emitter produces canonical LF text and `robots_parse(robots_emit(d))`
round-trips every parsed document.

## Quick start

```xi
use xiom.robots;
use xiom.io;

fn main() -> Int {
  let r = robots_parse("# example\nUser-agent: *\nDisallow: /private\nAllow: /private/public\nSitemap: https://example.com/sitemap.xml\n");
  match r {
    Ok(d) => {
      io.println(robots_agent(&d, 0, 0));                    // *
      if robots_is_allowed(&d, "Googlebot/2.1", "/private/x") {
        io.println("allowed");
      } else {
        io.println("blocked");                               // blocked
      }
      io.println(robots_emit(&d));
      // User-agent: *
      // Disallow: /private
      // Allow: /private/public
      //
      // Sitemap: https://example.com/sitemap.xml
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## API

| Function | Returns | Description |
|---|---|---|
| `robots_parse(text)` | `Result[Robots, Str]` | Parse a whole document; `Err("robots: ...")` on the catalogued errors. |
| `robots_new()` | `Robots` | An empty document; emits `""`. |
| `robots_group_count(r)` | `Int` | Number of groups. |
| `robots_agent_count(r, group)` | `Int` | User-agent tokens in a group. |
| `robots_agent(r, group, index)` | `Str` | One token, verbatim. |
| `robots_rule_count(r, group)` | `Int` | Allow/Disallow rules in a group. |
| `robots_rule_path(r, group, index)` | `Str` | One rule pattern, verbatim. |
| `robots_rule_allow(r, group, index)` | `Bool` | True for Allow, false for Disallow. |
| `robots_crawl_delay(r, group)` | `Option[Int]` | Recorded delay, or `None`. |
| `robots_sitemap_count(r)` | `Int` | Document-wide Sitemap count. |
| `robots_sitemap(r, index)` | `Str` | One Sitemap URL, verbatim. |
| `robots_path_matches(pattern, path)` | `Bool` | One pattern: prefix match, `*` wildcards, trailing `$` anchor, case-sensitive. |
| `robots_agent_matches(token, user_agent)` | `Bool` | `*` matches all; otherwise a case-insensitive prefix. |
| `robots_matching_group(r, user_agent)` | `Int` | Index of the most specific group, or `-1`. |
| `robots_is_allowed(r, user_agent, path)` | `Bool` | Longest-match decision with allow-wins ties. |
| `robots_emit(r)` | `Str` | Canonical LF text, no trailing LF. |

Accessors never trap: an out-of-range group/index yields `""`, `false` or
`None`.

### Matching in one paragraph

A path pattern matches when the pattern is a prefix of the path (`*` matches
any byte run, a trailing `$` anchors to the end, matching is case-sensitive,
an empty pattern matches nothing). The group is the one whose longest
User-agent token matches the crawler prefix-insensitively (`*` weighs 0 and
is the fallback); among that group's matching rules the longest pattern wins
and equal lengths resolve to Allow; nothing matching means allowed.

## Error model

Every parse failure is `Err(msg)` with a deterministic message starting with
`"robots: "`:

| Message | Trigger |
|---|---|
| `robots: control byte in input` | C0 control byte (not LF/TAB), lone CR, or DEL anywhere |
| `robots: missing ':' in line: <line>` | non-blank, non-comment line without a `:` |
| `robots: missing field name in line: <line>` | `: value` (empty name) |
| `robots: unknown field: <name>` | any field other than the five documented ones |
| `robots: rule before any user-agent: <line>` | Allow/Disallow/Crawl-delay before the first `User-agent` |
| `robots: empty user-agent token: <line>` | `User-agent:` with an empty value |
| `robots: bad crawl-delay: <value>` | non-digit, signed, fractional or > 2147483647 delay |
| `robots: sitemap must be an absolute http or https URL: <value>` | relative, other-scheme or empty Sitemap |

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.robots
```

Expected tail: 29 `[PASS]` lines, `xiom.robots: all tests passed`, then
`port: PASS (passed=29 failed=0 program_exit=0 exit=0)`.

## Install / publish

```
xiom pkg install xiom.robots@0.1.0     # consumer
xiom pkg publish                       # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## Limitations

- Comments, blank lines (and field-name casing/order) do not survive a round
  trip: `robots_emit` is canonical.
- `#` always starts a comment, so it cannot appear in a pattern or URL (URL
  fragments are lost); there is no URL decoding or normalization.
- Unknown/vendor fields (`Host:`, `Clean-param:`, ...) are rejected rather
  than preserved.
- A UTF-8 BOM is not stripped and makes the first field unknown.
- User-agent matching is case-insensitive prefix matching; the only wildcard
  is the exact token `*` (`*bot` is literal).
- One `Crawl-delay` per group (the last one wins); `Crawl-delay` is recorded,
  never enforced.
- Only one group applies per decision (most specific, earliest on ties); the
  first duplicate group is the effective one.
- No fetching, no HTTP, no `<meta name="robots">`, no sitemap-content
  parsing, no Google/vendor extensions.
- Errors carry the offending line text but no line/column numbers.

See `SPEC.md` for the full grammar, matching algorithm, error catalog and
test plan. License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
