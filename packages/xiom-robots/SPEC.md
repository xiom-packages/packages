# xiom.robots -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.robots` (`src/robots.xi`). Pure XIOM, no FFI, no file I/O, no
network fetching.

## 1. Scope

A small, dependency-free robots.txt codec for in-memory `Str` documents:

- `robots_parse` -- document -> `Result[Robots, Str]`,
- `robots_emit` -- `Robots` -> canonical robots.txt text,
- accessors -- group count, agents, rule count, rule path/allow, crawl delay,
  sitemap count and values,
- matching helpers -- `robots_path_matches` (one path pattern),
  `robots_agent_matches` (one User-agent token),
  `robots_matching_group` (group selection) and `robots_is_allowed` (the
  longest-match decision for one path).

The documented subset covers `User-agent`, `Allow`, `Disallow`,
`Crawl-delay` and `Sitemap` lines, `#` comments, blank lines and LF/CRLF
input; see sections 3-6.

## 2. Non-goals

- No fetching, no crawling, no HTTP, no file I/O: the module only transforms
  `Str` values already in memory.
- No HTML `<meta name="robots">` handling.
- No Google-specific extensions or other vendor directives (`Host`,
  `Clean-param`, `Request-rate`, ...): unknown fields are rejected.
- No URL decoding, percent-decoding or normalization of any kind.
- No request-rate scheduling: `Crawl-delay` is recorded, never acted upon.
- No UTF-8 validation and no BOM stripping (bytes pass through).
- No mutable editing API: a document is produced by `robots_parse` and read
  through accessors. (`robots_new` exists for an empty document.)

## 3. Data model

```xi
pub type Robots = {
  agent_start: Vec[Int];   // index into agents of group i's first agent
  agent_count: Vec[Int];   // number of agents of group i
  agents: Vec[Str];        // all User-agent tokens, grouped in source order
  rule_start: Vec[Int];    // index into rule_path/rule_allow of group i's first rule
  rule_count: Vec[Int];    // number of rules of group i
  rule_path: Vec[Str];     // rule patterns, in source order
  rule_allow: Vec[Int];    // 1 = Allow rule, 0 = Disallow rule
  crawl_delay: Vec[Int];   // -1 = unset, otherwise the recorded delay
  sitemaps: Vec[Str];      // document-global Sitemap URLs, in source order
}
```

Invariants for a parsed document:

- `agent_start.len() == agent_count.len() == rule_start.len() ==
  rule_count.len() == crawl_delay.len()` (the group count); the emitter and
  every accessor additionally clamp to those lengths and to `agents.len()`,
  `rule_path.len()` and `rule_allow.len()`, so a manually built value cannot
  cause an out-of-bounds read.
- `agents` has `sum(agent_count)` elements; `rule_path` and `rule_allow`
  have `sum(rule_count)` elements and the same length.
- Group `g` owns the agent range `[agent_start[g], agent_start[g] +
  agent_count[g])` and the rule range `[rule_start[g], rule_start[g] +
  rule_count[g])`; both ranges are contiguous because directives are appended
  in source order.

`Vec[StructType]` is not usable in this compiler, so the model is deliberately
flat (parallel homogeneous vectors) instead of a list of group/rule structs.

## 4. Line grammar

```
document  = *( line )                          ; LF or CRLF terminated
line      = *( byte except CR/LF ) [ CR ]      ; final line may lack LF
directive = ws* name ws* ":" ws* value ws*  [ "#" *( byte except LF ) ]
name      = "user-agent" / "allow" / "disallow" / "crawl-delay" / "sitemap"
            (ASCII case-insensitive)
value     = *( byte except LF / "#" )          ; trimmed
```

Decisions (each is covered by the conformance suite):

1. **Lines.** LF ends a line; one CR immediately before the LF is stripped,
   so CRLF input parses identically to LF input. A final line without a
   newline is still a line.
2. **Comments.** `#` starts a comment anywhere on a line -- inside a value,
   inside a URL, or at line start -- and runs to the end of the line. The
   comment text is parsed and dropped; emit never writes comments. A line that
   is empty after comment stripping is skipped.
3. **Whitespace.** The line is trimmed, then the name and value are trimmed
   individually (`str_trim`; in practice space and TAB). `User-agent : foo` is
   a valid User-agent directive.
4. **Field names.** `user-agent`, `allow`, `disallow`, `crawl-delay` and
   `sitemap` are recognized ASCII case-insensitively. Any other name is
   `Err("robots: unknown field: <name>")`; unknown fields are **rejected**,
   never preserved.
5. **Colon.** Every non-blank, non-comment line must contain a `:`; otherwise
   `Err("robots: missing ':' in line: <line>")`. An empty name (`: value`) is
   `Err("robots: missing field name in line: <line>")`. The value runs from
   the first `:` to the end of the (comment-stripped) line and is trimmed.
6. **Groups.** A `User-agent` directive appends its token to the current
   group when that group has no recorded rule (Allow/Disallow/Crawl-delay)
   yet; otherwise it starts a new group. The first `User-agent` line starts
   group 0. An empty token (`User-agent:`) is
   `Err("robots: empty user-agent token: <line>")`. Tokens are stored
   verbatim; the only wildcard is the exact token `*` (see section 5).
7. **Rules.** `Allow` and `Disallow` values are rule patterns stored in
   source order, with the Allow/Disallow kind. An empty value is stored as an
   empty pattern; it matches nothing, so `Disallow:` is the documented
   allow-all. Allow, Disallow and Crawl-delay before any `User-agent` line
   are `Err("robots: rule before any user-agent: <line>")`.
8. **Crawl-delay.** The value must be one or more ASCII digits (`0`-`9`),
   with the decimal value at most 2147483647; leading zeros are accepted
   (`007` is 7). Anything else is `Err("robots: bad crawl-delay: <value>")`.
   The last Crawl-delay of a group wins; a Crawl-delay closes the group's
   agent list.
9. **Sitemap.** The value must be an absolute http/https URL: the scheme
   `http://` or `https://` matched ASCII case-insensitively followed by at
   least one byte. Anything else (including a relative path, another scheme,
   or a bare `https://`) is
   `Err("robots: sitemap must be an absolute http or https URL: <value>")`.
   Accepted URLs are stored verbatim, in source order, document-globally.
   Sitemap lines may appear before the first group or between directives and
   never affect group formation.
10. **Control bytes.** Input is rejected with
    `Err("robots: control byte in input")` when it contains any C0 control
    byte other than LF or TAB, a CR that is not immediately followed by LF,
    or DEL (0x7F). This check runs before parsing, so it applies to comments
    as well. (`Str` is NUL-terminated on this toolchain, so a NUL byte cannot
    occur in ordinary `Str` values; the check is defensive for NUL and
    effective for the other control bytes.)
11. **Encoding.** Input is treated as a UTF-8 byte buffer and all scanning is
    byte-wise; no byte sequence is validated, split or rewritten. Bytes
    >= 0x80 pass through verbatim.
12. **Round-trip.** `robots_parse(robots_emit(d))` succeeds for every
    document `d` that `robots_parse` produced, preserving groups, agents
    (verbatim), rule order, kinds and patterns, crawl delays and sitemaps.
    Comments, blank lines, field-name casing and field order are
    canonicalized away. `robots_emit` is idempotent: emitting the reparse of
    an emitted document yields the identical text.

## 5. Matching algorithm and tie rules

### 5.1 Path patterns (`robots_path_matches`)

- Matching is byte-wise and **case-sensitive**.
- `*` matches any byte run, including the empty run; several `*` may appear.
- A trailing `$` anchors the pattern to the end of the path; `$` anywhere
  else is a literal byte.
- Without a trailing `$` the pattern is a **prefix match**: it succeeds as
  soon as the pattern is exhausted, even when the path continues.
- An empty pattern matches nothing (this is what makes an empty `Disallow:`
  allow-all). `$` alone matches only the empty path.
- A pattern need not start with `/`; it is matched literally (real request
  paths start with `/`, so only `/...` patterns are useful in practice).

Examples: `/fish` matches `/fish`, `/fish.html`, `/fish/salmon.html` and
`/fishheads`, but not `/Fish`; `/*.php` matches `/index.php` and
`/a/b/index.php`; `/fish$` matches `/fish` only.

### 5.2 User-agent tokens (`robots_agent_matches`)

- The exact token `*` matches every crawler.
- Any other token matches when it is an ASCII case-insensitive prefix of the
  crawler's user-agent string (`googlebot` matches `Googlebot/2.1`).
- `*` is only special when it is the whole token; a token such as `*bot` is a
  literal prefix string.
- An empty token never matches.

### 5.3 Group selection (`robots_matching_group`)

- Each group's specificity is the byte length of its longest matching token,
  except that a matching `*` token weighs 0 (fallback).
- The group with the highest specificity wins; the earliest group wins ties,
  so a later duplicate group is inert but preserved.
- `-1` means no group matches. In that case `robots_is_allowed` returns true.

### 5.4 Rule precedence (`robots_is_allowed`)

1. Select the group with `robots_matching_group`; no group -> allowed.
2. Among the group's rules whose pattern matches the path, the rule with the
   **longest pattern** (raw byte length, including any `*` and `$` as
   written) wins.
3. When several matching rules share the longest pattern length, **Allow
   wins** (regardless of source order).
4. When no rule matches (including a group whose only rules are empty
   patterns), the path is allowed.

Ties are decided by pattern length, not by rule order; source order only
determines storage order and canonical emit order.

## 6. API contract

```xi
pub fn robots_parse(text: Str) -> Result[Robots, Str]
pub fn robots_new() -> Robots
pub fn robots_group_count(r: &Robots) -> Int
pub fn robots_agent_count(r: &Robots, group: Int) -> Int
pub fn robots_agent(r: &Robots, group: Int, index: Int) -> Str
pub fn robots_rule_count(r: &Robots, group: Int) -> Int
pub fn robots_rule_path(r: &Robots, group: Int, index: Int) -> Str
pub fn robots_rule_allow(r: &Robots, group: Int, index: Int) -> Bool
pub fn robots_crawl_delay(r: &Robots, group: Int) -> Option[Int]
pub fn robots_sitemap_count(r: &Robots) -> Int
pub fn robots_sitemap(r: &Robots, index: Int) -> Str
pub fn robots_path_matches(pattern: Str, path: Str) -> Bool
pub fn robots_agent_matches(token: Str, user_agent: Str) -> Bool
pub fn robots_matching_group(r: &Robots, user_agent: Str) -> Int
pub fn robots_is_allowed(r: &Robots, user_agent: Str, path: Str) -> Bool
pub fn robots_emit(r: &Robots) -> Str
```

- `robots_parse` is O(total input length).
- `robots_path_matches` is O(|path| * |pattern|) worst case;
  `robots_agent_matches` is O(|token|).
- `robots_matching_group` is O(agent token count * |user_agent|).
- `robots_is_allowed` is O(rules of the selected group * |path| *
  |pattern|).
- Accessors are O(1); `robots_emit` is O(total output length).
- Every accessor is total: out-of-range indexes yield `""`, `false` or
  `None` (see each doc comment). No accessor traps, including on a manually
  built `Robots` whose parallel vectors disagree.
- `robots_emit` writes values verbatim and assumes LF/control-byte-free
  values; that holds for every document produced by `robots_parse`.

### Canonical emitter

`robots_emit` writes LF-separated lines with no trailing LF:

1. each group, in order: one `User-agent: <token>` line per agent, then its
   rules in source order as `Allow: <pattern>` / `Disallow: <pattern>` (an
   empty pattern emits the bare field, for example `Disallow:`), then
   `Crawl-delay: <value>` when set;
2. one blank line between consecutive groups;
3. when any group was written, one blank line, then the `Sitemap: <url>`
   lines in source order;
4. an empty document emits `""`.

Canonical field spellings are `User-agent`, `Allow`, `Disallow`,
`Crawl-delay`, `Sitemap`, each followed by `:` and a single space before a
non-empty value.

## 7. Error catalog

All parse failures are `Err(msg)` where `msg` starts with `"robots: "`:

| Message | Trigger |
|---|---|
| `robots: control byte in input` | C0 control byte (not LF/TAB), lone CR, or DEL anywhere in the input, including comments |
| `robots: missing ':' in line: <line>` | non-blank, non-comment line without a `:` |
| `robots: missing field name in line: <line>` | line whose name before `:` is empty after trimming (`: x`) |
| `robots: unknown field: <name>` | any field name other than the five documented ones, including BOM-prefixed first lines |
| `robots: rule before any user-agent: <line>` | `Allow`, `Disallow` or `Crawl-delay` before the first `User-agent` line |
| `robots: empty user-agent token: <line>` | `User-agent:` with an empty (or comment-only) value |
| `robots: bad crawl-delay: <value>` | empty, non-digit, signed, fractional, or > 2147483647 Crawl-delay value |
| `robots: sitemap must be an absolute http or https URL: <value>` | empty, relative, other-scheme, or scheme-only Sitemap value |

Error messages are deterministic. `<line>` is the comment-stripped, trimmed
line text; `<value>` is the trimmed value; `<name>` is the trimmed field
name as written. The first error in source order is returned, except that a
control byte anywhere in the input is reported before any other error.

## 8. Test plan

`tests/test_conformance.xi` (module `robots_tests`) runs 29 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | one group | agent + Allow/Disallow order, kinds, paths |
| t2 | several agents | `User-agent` lines append; name casing |
| t3 | group termination | a `User-agent` after a rule starts a new group |
| t4 | empty patterns | empty Disallow/Allow stored, matches nothing, allow-all |
| t5 | comments/blanks/CRLF | `#` inline, blank lines, CRLF, whitespace trim |
| t6 | name casing | `USER-AGENT`, `ALLOW`, `DISALLOW`, `CrAwL-DeLaY`, `SiTeMaP` |
| t7 | crawl-delay values | `0`, leading zeros, last-wins, 2147483647 cap |
| t8 | crawl-delay scope | per group, no leak, `None` when unset |
| t9 | sitemaps | order, verbatim, no rule/group side effects |
| t10 | sitemap first | valid before any `User-agent` |
| t11 | rule before agent | Disallow/Allow/Crawl-delay, message and line text |
| t12 | empty agent | bare, whitespace-only and comment-only tokens |
| t13 | bad crawl-delay | `abc`, `-1`, `1.5`, `5s`, empty, cap+1, 20 digits |
| t14 | control bytes | lone CR, DEL, `\u{0001}`, vertical tab, `\u{001F}` |
| t15 | prefix matching | case-sensitive prefix semantics |
| t16 | wildcard | `*` runs including empty; `/*` vs `/` and `""` |
| t17 | anchor | trailing `$`, literal `$` elsewhere, lone `$`, `$$` |
| t18 | longest match | more specific Allow beats broader Disallow and `/*` |
| t19 | ties | Allow wins at equal length in either source order |
| t20 | group selection | longest token; prefix; case-insensitive; no group -> allow |
| t21 | specificity | specific group replaces `*`; first duplicate group wins |
| t22 | canonical emit | exact text, blank-line blocks, sitemap last, no trailing LF |
| t23 | round-trip | parse(emit) preserves and emit is idempotent |
| t24 | empty documents | `""`, comment-only and `robots_new` emit `""` |
| t25 | bounded accessors | negative/absent indexes return `""`/`false`/`None` |
| t26 | sitemap validation | relative, `ftp://`, `https://` rejected; uppercase kept |
| t27 | unknown/malformed | unknown fields, `FOO`, missing `:`, missing name |
| t28 | comment data | `#` never part of an agent token or rule pattern |
| t29 | agent matching | `*`, empty, exact, prefix, longer-token, `*xx` literal |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison).

## 9. Compiler / stdlib notes

No unsafe code and no FFI. The implementation follows the pure-parser idioms
of `xiom.ini`/`xiom.cidr` (byte-wise scanning with `xiom.string.byte_at`,
`Vec[UInt8]` accumulation with `xiom.string.builder`) and documents these
compiler-driven choices:

- `Vec[StructType]` is unsupported, so the document is a flat record of
  parallel vectors; groups are stored as ranges.
- `Ok`/`Err` for `Result[Robots, Str]` are constructed only in the leaf
  helpers `_rb_ok`/`_rb_err`.
- Str equality between `Vec[Str]` elements goes through
  `xiom.string.compare.str_compare` (BUG 17); element values are bound to
  typed locals before use, and their lengths come from `xiom.string.str_len`.
- `Vec[Int]` element reads are bound to typed locals before use.
- Every byte read goes through `_rb_byte`, which widens with `& 0xFF`, so no
  UInt8 value is ever compared against a >= 128 constant.
- Run-flag reads use `r.rule_allow[i] != 0` because `Vec[Bool]` element
  semantics are not exercised elsewhere in this harness.
- `robots_parse` owns the per-line loop; `robots_emit` pops the final LF byte
  instead of special-casing the last line.
- Tests dispatch directly (`t1()` ... `t29()`); no `Vec[fn]` indexed calls,
  no inline lambdas, no `mut` match patterns, and every `match` is
  exhaustive.

## 10. Known limitations

- Comments, blank lines and the original field-name casing/order do not
  survive a round trip; emit is canonical.
- `#` cannot appear in a pattern or URL: it always starts a comment (URL
  fragments are therefore lost, and no URL decoding exists).
- Unknown fields are rejected, so real-world files using vendor directives
  must be narrowed to the documented subset first.
- A UTF-8 BOM is not stripped: it turns the first field name into an unknown
  field (and is included in the error message).
- User-agent matching is prefix-based, not substring-based, and the only
  wildcard is the exact token `*`.
- Only one Crawl-delay value per group is kept (last wins); duplicates are
  not preserved.
- Rule precedence is by pattern length then Allow; source order is not a
  tie-breaker.
- No fetching, no HTTP, no request pacing, no `<meta>` robots, no URL
  normalization, no percent-decoding, no sitemap content parsing.
- Errors carry no line/column numbers (the offending line text is included).
- `robots_emit` assumes values without LF or control bytes; hand-built
  `Robots` values bypassing `robots_parse` are not validated.
