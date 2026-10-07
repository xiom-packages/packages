# xiom.static -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.64.0 on
2026-10-07; not published).
Manifest: `package.xi` (`xiom.static`, version `0.1.0`).
Module: `src/static.xi` (`module xiom.static`).
Depends on `xiom.std` (`xiom.string`, `xiom.convert`,
`xiom.convert.percent`, `xiom.io`, `xiom.io.fs`, `xiom.net.mime`,
`xiom.time`). No FFI.

## 1. Scope

Static-file response planning for an HTTP server owned by the caller. Four
public types and thirteen public functions:

```xi
pub type StaticHeader = { name: Str; value: Str; }
pub type StaticRange = { valid: Bool; unsatisfiable: Bool; start: Int; end: Int; }
pub type StaticPolicy = { max_age: Int; immutable: Bool; must_revalidate: Bool; no_store: Bool; }
pub type StaticResult = { status: Int; headers: Vec[StaticHeader]; body: Vec[UInt8]; }

pub fn static_mime_of(path: Str) -> Str
pub fn static_etag_stat(size: Int, mtime: Int) -> Str
pub fn static_etag_sha256(data: &Vec[UInt8]) -> Str
pub fn static_etag_matches(etag: Str, if_none_match: Str) -> Bool
pub fn static_http_date(epoch: Int) -> Str
pub fn static_last_modified(epoch: Int) -> StaticHeader
pub fn static_cache_control(p: &StaticPolicy) -> Str
pub fn static_range_parse(header: Str, size: Int) -> StaticRange
pub fn static_content_range(start: Int, end: Int, size: Int) -> StaticHeader
pub fn static_accept_ranges() -> StaticHeader
pub fn static_resolve_path(root: Str, url_path: Str) -> Result[Str, Str]
pub fn static_serve(root: Str, url_path: Str, if_none_match: Str, range_header: Str, is_head: Bool, policy: &StaticPolicy) -> StaticResult
pub fn static_body_ints(body: &Vec[UInt8]) -> Vec[Int]
```

Private helpers: `_byte_at_i`, `_has_prefix`, `_contains_nul_escape`,
`_has_parent_segment`, `_pad2`, `_weekday_name`, `_month_name`,
`_parse_digits`, `_range_invalid`, `_range_unsat`, `_range_ok`, `_hdr`,
`_headers_full`, `_headers_partial`, `_headers_not_modified`,
`_headers_unsatisfiable`, `_not_found`, `_serve_full`.

## 2. Non-goals

- **No streaming, mmap or chunked transfer.** A 200/206 body is a fully
  materialized `Vec[UInt8]`; `fs_read_range` seeks with an `Int32`, so
  resources above 2 GiB - 1 are rejected (404).
- **No multi-range, no gzip/deflate, no directory indexes.**
- **No symlink containment**: the traversal guard is lexical; the OS still
  follows links that live inside the root.
- **No If-Modified-Since parser**: the stdlib exposes no public HTTP-date
  parser, so only `If-None-Match` is evaluated. `Last-Modified` is produced
  for clients and caches.
- **No Str round-trip for bodies**: a `Str` bridge corrupts `0x00` and
  bytes above `0x7A`; `static_body_ints` is the only bridge and it is
  byte-preserving.
- **No auth, cookies, content negotiation, methods or routing**: the
  caller owns the HTTP layer.

## 3. Validators and dates

- `static_mime_of` delegates to `xiom.net.mime.mime_type_of`; unknown
  extensions and extensionless names yield `application/octet-stream`.
- `static_etag_stat(size, mtime)` returns `"<size>-<mtime>"` (quoted
  decimal fields, so `"123-456"`); it is the primary ETag because it costs
  one stat and no read. `static_etag_sha256(data)` returns the quoted
  lowercase SHA-256 hex (`xiom.net.mime.etag_new`; 66 characters).
- `static_etag_matches(etag, if_none_match)` delegates to
  `xiom.net.mime.etag_matches`: `*` matches, list items are whitespace
  trimmed and may carry a `W/` prefix; an empty header matches nothing
  (except `*`, which is not empty).
- `static_http_date(epoch)` is the IMF-fixdate
  `W, DD Mon YYYY HH:MM:SS GMT` in UTC. The stdlib has no HTTP-date
  formatter, so it is hand-rolled: `xiom.time.datetime_from_epoch` splits
  the epoch, the weekday comes from `xiom.time.date_day_of_week(y, m, d)`
  (0 = Sunday; the `DateTime.weekday` field uses a different convention and
  is deliberately not used), `Time.date_day_of_week` names are
  `Sun..Sat`; months are `Jan..Dec`; day/hour/minute/second are
  zero-padded to two digits. Epochs below 0 clamp to 0. Known-answer
  tests: `0 -> "Thu, 01 Jan 1970 00:00:00 GMT"`,
  `784111777 -> "Sun, 06 Nov 1994 08:49:37 GMT"`,
  `1600000000 -> "Sun, 13 Sep 2020 12:26:40 GMT"`.
- `static_last_modified(epoch)` = `StaticHeader{ "Last-Modified",
  static_http_date(epoch) }`.
- `static_cache_control(p)` always emits
  `<public|private>, max-age=<N>` first and then, in order,
  `, immutable` (if), `, must-revalidate` (if), `, no-store` (if).
  `no_store` switches the visibility token to `private`; a negative
  `max_age` clamps to 0. Examples:
  `{3600,false,false,false} -> "public, max-age=3600"`,
  `{31536000,true,false,false} -> "public, max-age=31536000, immutable"`,
  `{0,false,true,false} -> "public, max-age=0, must-revalidate"`,
  `{0,false,false,true} -> "private, max-age=0, no-store"`.

## 4. Range grammar

`static_range_parse(header, size)` accepts exactly one spec after a
case-sensitive `bytes=` prefix; `size < 0` clamps to 0. Bytes outside
`0-9` and `-` (including spaces, `+`, commas) invalidate the header, and at
most one `-` is allowed.

| Input (size 10) | Result |
|---|---|
| `bytes=0-0` | valid, satisfiable, `[0, 0]` |
| `bytes=2-5` | valid, satisfiable, `[2, 5]` |
| `bytes=2-` | valid, satisfiable, `[2, 9]` |
| `bytes=9-100` | valid, satisfiable, `[9, 9]` (end clamped to size - 1) |
| `bytes=-3` | valid, satisfiable, `[7, 9]` (suffix) |
| `bytes=-10`, `bytes=-20` | valid, satisfiable, `[0, 9]` (whole resource) |
| `bytes=10-`, `bytes=10-12` | valid, unsatisfiable (first byte >= size) |
| `bytes=-0` | valid, unsatisfiable (zero-length suffix) |
| `bytes=0-` on an empty resource | valid, unsatisfiable |
| `""`, `bytes=`, `bytes=-`, `bytes=0`, `bytes=x-y`, `bytes=1-2-3`, `bytes=--1`, `bytes=1 -2`, `items=0-1`, `Bytes=0-1`, `bytes=0-1,3-4`, `bytes=+1-2`, `bytes=5-3` | invalid (`valid=false`), caller ignores the header |
| digit strings that overflow `Int` (e.g. `bytes=99999999999999999999-`) | parse saturates at `size`, so they behave as >= size (no wrap) |

`static_content_range(start, end, size)` produces
`Content-Range: bytes <start>-<end>/<size>` for satisfied ranges;
`static_accept_ranges()` produces `Accept-Ranges: bytes`. The 416 form
`Content-Range: bytes */<size>` is built inside `static_serve`.

## 5. Path resolution

`static_resolve_path(root, url_path)` treats `root` as trusted and
`url_path` as hostile, and returns `Ok(joined)` or `Err(message)` in this
exact order:

1. raw `%00` escape -> `static: NUL byte in path`. This runs before
   decoding because `xiom.convert.percent.percent_decode` builds its result
   through a C string and would silently truncate at the NUL
   (`secret%00.txt` must not become `secret`).
2. `percent_decode` failure -> `static: invalid percent-encoding`.
3. any decoded NUL byte -> `static: NUL byte in path` (defense in depth;
   step 1 makes this unreachable through `percent_decode`).
4. empty decoded path -> `static: empty path`.
5. decoded path starting with `/` -> `static: absolute path`.
6. a `..` segment delimited by `/` or `\` (start/end of string count;
   `...` and `a..b` do not) -> `static: parent segment in path`.
7. any `\` -> `static: backslash in path` (the second Windows separator,
   so `..\x` never reaches a filesystem call).
8. any `:` -> `static: drive colon in path` (drive letters and NTFS
   alternate data streams).

`"."` segments are allowed and are not collapsed. The join is manual and
lexical: the result is `root + decoded` when `root` already ends with `/`
or `\`, otherwise `root + "/" + decoded`; an empty root yields
`"/" + decoded`. There is no symlink resolution, no case folding and no
Unicode normalization.

## 6. static_serve pipeline

`static_serve(root, url_path, if_none_match, range_header, is_head,
policy)`:

1. resolve the path; any `Err` -> 404 (no message ever escapes).
2. `io.metadata(path)`; stat error or `!is_file` (directories) -> 404.
3. `size > 2147483647` -> 404 (no streaming; see non-goals).
4. derive `etag = static_etag_stat(size, mtime)`,
   `last_modified = static_http_date(mtime)`,
   `cache = static_cache_control(policy)`, then probe the MIME type.
5. `if_none_match` non-empty and `static_etag_matches(etag, if_none_match)`
   -> **304** with `ETag`, `Last-Modified`, `Cache-Control` (validators win
   over Range).
6. `range_header` empty -> **200** (read via `fs_read`).
7. parse the range; `!valid` -> **200** (the malformed header is ignored).
8. `unsatisfiable` -> **416** with `Content-Range: bytes */<size>` and
   `Accept-Ranges`.
9. satisfiable -> read `[start, end]` via `fs_read_range` **206**.
10. any read error -> 404. `is_head` empties the body of a 200/206 without
    changing status or headers.

Status codes are 200/206/304/404/416 and header order is fixed:

| Status | Headers (order) |
|---|---|
| 200 | `Content-Type`, `Content-Length`, `ETag`, `Last-Modified`, `Cache-Control`, `Accept-Ranges` |
| 206 | `Content-Type`, `Content-Length` (range length), `Content-Range`, `ETag`, `Last-Modified`, `Cache-Control`, `Accept-Ranges` |
| 304 | `ETag`, `Last-Modified`, `Cache-Control` |
| 416 | `Content-Range` (`bytes */size`), `Accept-Ranges` |
| 404 | none |

For HEAD the `Content-Length` always describes the representation the
matching GET would return (full size for 200, range length for 206).

`static_body_ints(body)` returns `out[i] = body[i]` widened to 0..255; it
is the only sanctioned way to hand a body to numeric-only APIs.

## 7. API contract

| Function | Input | Returns | Errors |
|---|---|---|---|
| `static_mime_of(path)` | any path | MIME string or `application/octet-stream` | none |
| `static_etag_stat(size, mtime)` | any Ints | quoted `"<size>-<mtime>"` | none |
| `static_etag_sha256(data)` | bytes | quoted SHA-256 hex, 66 chars | none |
| `static_etag_matches(etag, if_none_match)` | any strings | Bool | none |
| `static_http_date(epoch)` | any Int | IMF-fixdate; negative clamps to 0 | none |
| `static_last_modified(epoch)` | any Int | `Last-Modified` header | none |
| `static_cache_control(p)` | policy | deterministic Cache-Control value | none |
| `static_range_parse(header, size)` | header + size | `StaticRange`; size < 0 clamps to 0 | none |
| `static_content_range(start, end, size)` | any Ints | `Content-Range` header | none |
| `static_accept_ranges()` | none | `Accept-Ranges` header | none |
| `static_resolve_path(root, url_path)` | trusted root + untrusted path | `Ok(joined)` | seven `static: ...` messages, order in section 5 |
| `static_serve(...)` | as section 6 | `StaticResult` 200/206/304/404/416 | none (errors collapse to 404) |
| `static_body_ints(body)` | bytes | `Vec[Int]` 0..255 | none |

Invariants:

- `StaticResult.status` is one of 200/206/304/404/416; 304/404/416 always
  carry an empty body; 404 always carries zero headers.
- A satisfiable `StaticRange` always has `0 <= start <= end <= size - 1`.
- `static_serve` never reads the file when it answers 304.
- The body of a 200 equals the file byte-for-byte; the body of a 206 equals
  the requested inclusive slice byte-for-byte (verified with NUL and bytes
  above 0x7F in the suite).

## 8. Test plan

`tests/test_conformance.xi` (module `static_tests`) runs 25 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). All `Str` equality goes through
`xiom.string.compare.str_compare` via the local `streq` helper; every Vec
element read is bound to a typed local; result/struct Vec payloads are
copied to locals before `&` references. Checks t1-t19 are pure; t20-t25
create fixtures under `fs.fs_temp_dir()` (`xiom_static_bin.bin`,
`xiom_static_head.bin`, `xiom_static_range.bin`, `xiom_static_304.bin`,
`xiom_static_416.bin`, `xiom_static_text.txt`) with `fs_write` /
`fs_write_text` and remove them with `io.remove_file`.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | mime | html/css/jpeg/js/json mappings plus `application/octet-stream` fallback for `.bin` and extensionless names |
| t2 | etag_stat | quoted `<size>-<mtime>` format for (123,456), (0,0), (10,784111777) |
| t3 | etag_sha256 | SHA-256 of `abc` = `ba7816bf...0015ad`, 66 chars, quoted, deterministic |
| t4 | etag_matches | exact, `*`, `W/` prefix, comma list, whitespace padding, miss, empty header |
| t5 | http_date | KATs 0 / 784111777 / 1600000000 and the negative clamp |
| t6 | last_modified | header name and RFC 1123 value, including clamp |
| t7 | cache_control public | `public, max-age=3600`; `immutable`; immutable + must-revalidate order |
| t8 | cache_control private | must-revalidate; `private, ..., no-store`; full flag order; negative max-age clamp |
| t9 | range satisfiable | closed ranges, open-ended range, end clamp |
| t10 | range suffix | `-3`, `-1`, `-10`, `-20` |
| t11 | range unsatisfiable | start >= size, `-0`, empty resource, negative size clamp |
| t12 | range malformed | missing/wrong prefix, multi-range, signs, whitespace, reversed bounds, wrong case |
| t13 | range saturation | 20-digit offsets saturate at size; leading zeros parse |
| t14 | header builders | `Content-Range: bytes 1-3/10`, `Accept-Ranges: bytes` |
| t15 | resolve ok | manual join (slash/backslash roots), decoded `%61`/`%2F`, `.` and non-parent dots |
| t16 | resolve parent | `..`, `a/../b`, `a/..`, `..%2fb`, `%2e%2e/x`, `a/%2E%2E`, `a\..\b` |
| t17 | resolve NUL/escapes | `%00`, `a%00b`, `a%00/../b`; `%zz`, `%2` |
| t18 | resolve rejections | empty, leading `/`, `%2F` absolute, backslash, drive colons |
| t19 | body_ints | `é` -> [195,169], empty -> empty, binary fixture -> exact ints |
| t20 | file 200 | byte-exact binary body (0x00/0x7B/0x80/0xFF), stat ETag, Last-Modified, Content-Type/Length, Accept-Ranges, Cache-Control |
| t21 | file HEAD | empty body with full Content-Length; ranged HEAD keeps 206 headers |
| t22 | file 206 | closed/suffix/open/clamped ranges byte-exact with Content-Range; malformed -> 200 full, no Content-Range |
| t23 | file 304 | exact/`*`/`W/` matches, 304 beats Range, miss -> 200 |
| t24 | file 416/404 | unsatisfied range + `bytes */size`; `-0`; missing file; directory; `../` and absolute traversal |
| t25 | file text | `text/plain`, served body equals the file bytes |

Scripted expectation from the repository root:

```
$env:XIOM_COMPILER = "$env:LOCALAPPDATA\xiom.new\bin\xiom.exe"
& .\scripts\port.ps1 -Package xiom.static -TimeoutSec 60
# port: PASS (passed=25 failed=0 program_exit=0 exit=0)
```

## 9. Error catalog

Only `static_resolve_path` errors; every message starts with the literal
prefix `static: `. Messages are static strings (no numbers are formatted
into them). Precedence is the list in section 5; for example
`"a%00/../b"` reports `static: NUL byte in path` (raw `%00` wins), while
`"a\..\b"` reports `static: parent segment in path` (`..` is checked
before the backslash rule).

| Message | Trigger |
|---|---|
| `static: NUL byte in path` | raw `%00` escape, or a decoded NUL byte |
| `static: invalid percent-encoding` | `percent_decode` returned Err |
| `static: empty path` | decoded path length 0 |
| `static: absolute path` | decoded path starts with byte 47 |
| `static: parent segment in path` | `..` segment delimited by `/` or `\` |
| `static: backslash in path` | any byte 92 |
| `static: drive colon in path` | any byte 58 |

## 10. Compiler / stdlib notes

The implementation follows the v0.64.0 package idioms:

- Free functions only; state travels by value or `&` reference.
- Every byte read via `xiom.string.byte_at` is widened with
  `(x as Int) & 0xFF` before comparison (`_byte_at_i`); `0x00`/`/`/`\`/`:`
  constants enter as 0/47/92/58 through the widened path.
- No `==` on `Str` anywhere and no `Vec[(Str, Str)]` anywhere; byte-level
  comparison handles prefixes, escapes and segments.
- Range digit parsing uses a pre-multiply saturation guard
  (`v > (cap - d) / 10`), so multi-digit overflow cannot wrap.
- The stat ETag keeps `static_serve` O(1) in validators; `static_etag_sha256`
  exists but is not on the serve path (a caller that wants content-stable
  tags uses it directly).
- Body bytes stay in `Vec[UInt8]` from `fs_read`/`fs_read_range` to
  `StaticResult.body`; `static_body_ints` is the only widening bridge.
- The tests create/remove real fixtures in the system temp directory
  (smoke_io2 precedent) and never depend on wall-clock time: expected
  validators are recomputed from `fs_size`/`fs_mtime` of the same file.
- Imports: `xiom.string`, `xiom.convert`, `xiom.convert.percent`,
  `xiom.io`, `xiom.io.fs`, `xiom.net.mime`, `xiom.time`; the tests add
  `xiom.test` and `xiom.string.compare`.
- No contracts (`requires:`/`ensures:`) are declared in 0.1.0; the
  25-check suite pins the behavior instead.

## 11. Known limitations

- **Resource cap.** Files above 2 GiB - 1 answer 404 (`fs_read_range` uses
  an `Int32` fseek; a 200 body is fully materialized).
- **Single range only.** Multi-range requests are malformed by policy and
  are served as a full 200.
- **Lexical containment only.** No symlink resolution; a link inside the
  root can still escape it at the OS level.
- **`If-Modified-Since` unsupported.** No public HTTP-date parser exists in
  the stdlib; only `If-None-Match` is evaluated.
- **Windows-hardened guard on all platforms.** Backslashes and colons are
  rejected even on POSIX, where they can be legal filename bytes; the guard
  is deliberately conservative.
- **No directory redirects** (no `index.html` resolution) and no
  `Content-Encoding` handling.

## 12. Stdlib gaps hit (for the wishlist)

Recorded while building this package; all have local workarounds, none
blocks 0.1.0:

- **HTTP-date formatter**: hand-rolled over
  `datetime_from_epoch` + `date_day_of_week` (as briefed).
- **`percent_decode` NUL truncation**: decoding `%00` silently truncates
  the string (C-string construction), so the guard scans raw input for
  `%00` before decoding.
- **`DateTime.weekday` convention mismatch**: the field is 0 = Monday while
  `date_day_of_week` is 0 = Sunday; the mismatch is undocumented and easy to
  trip over -- this module pins the Zeller convention only.
- **Cross-platform containment helpers**: `io.is_absolute`/`io.join_paths`
  are `/`-only, so drive/backslash/colon guards and the join are manual.
- **`fs` remove parity**: no `fs_remove`; tests use `io.remove_file`.
- **Int32 range reads**: no streaming `read_exact`, so large assets cannot
  be served; documented as a hard 2 GiB boundary.
