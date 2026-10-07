# xiom.mime -- Specification

Version: 0.1.2 (stable; published on the XIOM registry).
Module: `xiom.mime` (`src/mime.xi`). Pure XIOM, no FFI.

## 1. Scope

A small, dependency-free set of helpers over media type strings and file
extensions:

- `mime_normalize` -- canonicalize a media type string,
- `mime_type_for_extension` -- extension to media type mapping,
- `mime_extension_for` -- media type to primary extension mapping,
- `mime_is_text` / `mime_is_image` / `mime_is_audio` / `mime_is_video` /
  `mime_is_application` -- top-level class checks,
- `mime_type_count` -- size of the curated table.

All functions return `Str`, `Bool` or `Int`; there is deliberately no error
channel and no `Result`. Scanning is byte-wise ASCII over the input `Str`, and
all byte reads are widened once (`(string.byte_at(s, i) as Int) & 0xFF`).

## 2. Non-goals

- Parsing the IANA media type registry at runtime; the table is curated
  (section 3.2).
- Full RFC 7231 media type grammar: no quoted-string parameters, no comments
  or folding whitespace, no structured suffix negotiation, no case folding of
  non-ASCII bytes.
- Content sniffing, charset handling, file-content detection.
- Path handling: `mime_type_for_extension` accepts a bare extension (with or
  without dots and surrounding spaces), not `dir/file.ext`.
- FFI, file I/O, registry integration.

## 3. Rules

### 3.1 `mime_normalize(m: Str) -> Str`

1. Trim leading/trailing ASCII whitespace (TAB, LF, VT, FF, CR, space).
2. Lowercase ASCII `A-Z`; other bytes pass through.
3. Drop everything from the first `;` to the end (the parameter section).
4. Trim ASCII whitespace again.
5. The result is `""` for empty, whitespace-only or parameter-only input.

Examples: `"Text/HTML"` -> `"text/html"`;
`"  Application/JSON ; boundary=xyz  "` -> `"application/json"`;
`"text/plain;charset=utf-8;q=0.5"` -> `"text/plain"`;
`"; charset=utf-8"` -> `""`.

### 3.2 `mime_type_for_extension(ext: Str) -> Str`

1. Trim ASCII whitespace, lowercase ASCII, strip every leading `.`
   (`"...png"` -> `"png"`).
2. Look up the extension in the curated table (section 4).
3. Unknown or empty input returns `"application/octet-stream"`.

Examples: `"PNG"`, `".PNG"`, `".Png"`, `"  .png  "` all yield `"image/png"`;
`"jpeg"` yields `"image/jpeg"`; `"tar.gz"`, `"PNG."`, `""` and `"xyz"` fall
back to `"application/octet-stream"`.

### 3.3 `mime_extension_for(m: Str) -> Str`

1. Normalize with the exact rules of `mime_normalize` (so parameters and case
   are handled: `"Text/HTML; charset=utf-8"` -> `"html"`).
2. Scan the table in order and return the extension of the first pair whose
   media type matches. This makes the extension listed first for a media type
   its **primary** extension: `image/jpeg` -> `jpg`, `application/yaml` ->
   `yaml`, `audio/ogg` -> `ogg`, `audio/midi` -> `midi`, `image/tiff` ->
   `tiff`, `application/octet-stream` -> `bin`.
3. Unknown or empty input returns `""` (no fallback).

### 3.4 Class checks

Each check normalizes `m` with `mime_normalize` and tests for the top-level
type prefix:

| Function | Prefix |
|---|---|
| `mime_is_text(m)` | `text/` |
| `mime_is_image(m)` | `image/` |
| `mime_is_audio(m)` | `audio/` |
| `mime_is_video(m)` | `video/` |
| `mime_is_application(m)` | `application/` |

The checks test the top-level type only: `mime_is_text("application/json")` is
false, `mime_is_application("application/octet-stream")` is true. Every check
returns false for `""`, and for the non-matching classes.

### 3.5 `mime_type_count() -> Int`

Returns `table.len() / 2` for the curated table: 82 in this version. The
value is derived from the table, so it cannot drift from the mappings.

## 4. Curated table (82 entries, extension -> media type)

Primary extensions are shown in the order used for `mime_extension_for`.

| Extension | Media type |
|---|---|
| txt, text, log, ini, cfg, conf | text/plain |
| csv | text/csv |
| tsv | text/tab-separated-values |
| html, htm | text/html |
| css | text/css |
| js, mjs | text/javascript |
| md | text/markdown |
| xml | application/xml |
| json | application/json |
| jsonl, ndjson | application/x-ndjson |
| yaml, yml | application/yaml |
| toml | application/toml |
| sh | application/x-sh |
| sql | application/sql |
| pdf | application/pdf |
| doc | application/msword |
| docx | application/vnd.openxmlformats-officedocument.wordprocessingml.document |
| xls | application/vnd.ms-excel |
| xlsx | application/vnd.openxmlformats-officedocument.spreadsheetml.sheet |
| ppt | application/vnd.ms-powerpoint |
| pptx | application/vnd.openxmlformats-officedocument.presentationml.presentation |
| rtf | application/rtf |
| epub | application/epub+zip |
| png | image/png |
| jpg, jpeg | image/jpeg |
| gif | image/gif |
| webp | image/webp |
| svg | image/svg+xml |
| ico | image/x-icon |
| bmp | image/bmp |
| ppm | image/x-portable-pixmap |
| tiff, tif | image/tiff |
| avif | image/avif |
| wav | audio/wav |
| mp3 | audio/mpeg |
| ogg, oga | audio/ogg |
| flac | audio/flac |
| aac | audio/aac |
| m4a | audio/mp4 |
| midi, mid | audio/midi |
| mp4 | video/mp4 |
| m4v | video/x-m4v |
| webm | video/webm |
| mkv | video/x-matroska |
| avi | video/x-msvideo |
| mov | video/quicktime |
| mpg, mpeg | video/mpeg |
| ogv | video/ogg |
| zip | application/zip |
| gz | application/gzip |
| tar | application/x-tar |
| bz2 | application/x-bzip2 |
| xz | application/x-xz |
| zst | application/zstd |
| 7z | application/x-7z-compressed |
| rar | application/vnd.rar |
| wasm | application/wasm |
| exe, dll | application/vnd.microsoft.portable-executable |
| bin, so | application/octet-stream |
| iso | application/x-iso9660-image |
| woff | font/woff |
| woff2 | font/woff2 |
| ttf | font/ttf |
| otf | font/otf |
| parquet | application/vnd.apache.parquet |
| sqlite | application/vnd.sqlite3 |

## 5. API signatures

```xi
pub fn mime_normalize(m: Str) -> Str
pub fn mime_type_for_extension(ext: Str) -> Str
pub fn mime_extension_for(m: Str) -> Str
pub fn mime_is_text(m: Str) -> Bool
pub fn mime_is_image(m: Str) -> Bool
pub fn mime_is_audio(m: Str) -> Bool
pub fn mime_is_video(m: Str) -> Bool
pub fn mime_is_application(m: Str) -> Bool
pub fn mime_type_count() -> Int
```

Complexity: every function is O(s.len() + table_size); the table has 82
entries, so lookups are O(1) with a small constant.

## 6. Test plan

`tests/test_conformance.xi` (module `mime_tests`) runs 22 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | normalize trim/case | trim + lowercase on mixed-case input |
| t2 | normalize parameters | `; charset=...`, spaces around `;`, multiple parameters |
| t3 | normalize empties | `""`, whitespace-only, `";"`, parameter-only |
| t4 | extension dot/case | `txt` / `.txt` / `TXT` / `.JpG` / `..Json` / spaced |
| t5 | core text mapping | html, css, js, json, xml, csv, tsv, md |
| t6 | documents/images | pdf, png, gif, webp, svg, ico, bmp, ppm |
| t7 | audio/video | wav, mp3, ogg, flac, mp4, webm, mkv |
| t8 | archives/exec/blobs | zip, gz, tar, wasm, toml, yaml, yml, ini, sh, exe, dll, bin |
| t9 | unknown fallback | `xyz`, `""`, `.`, `...`, `tar.gz`, `PNG.` -> octet-stream |
| t10 | extension_for basics | parameters/case/spaces normalize before lookup |
| t11 | primary extension | jpg, yaml, ogg, midi, tiff, bin, jsonl |
| t12 | extension_for unknown | `""`, spaces, parameter-only, unknown types -> `""` |
| t13 | round-trip | 26 primary `(ext -> type -> ext)` pairs |
| t14 | class text | `text/*` true (with parameters); others false; `""` false |
| t15 | class image | `image/*` true; text/pdf/`""` false |
| t16 | class audio | `audio/*` true; video/text/`""` false |
| t17 | class video | `video/*` true; audio/image/`""` false |
| t18 | class application | `application/*` (incl. octet-stream) true; others false |
| t19 | class checks normalization | parameters, case and surrounding spaces |
| t20 | count pinned | `mime_type_count() == 82`, `>= 45`, stable across calls |
| t21 | empty inputs | every API's empty-input result |
| t22 | mandatory extension list | all 37 task-named extensions resolve; only `bin` is octet-stream |

All `Str` equality goes through `xiom.string.compare.str_compare` (BUG 17:
`==` on `Str` values read from `Vec[Str]` elements lowers to a pointer
comparison). Table-driven checks bind `Vec[Str]` reads to explicitly typed
locals before use.

## 7. Known limitations

- Curated table, not a registry parse (section 2); new mappings require a code
  change.
- One primary extension per media type; aliases are reachable only in the
  extension -> type direction.
- ASCII-only normalization and class checks; non-ASCII bytes pass through.
- `;` always starts the parameter section, even inside a quoted parameter.

## 8. Compiler / stdlib notes

- v0.61.3: free functions only; no self methods, lambdas, match arms,
  `Vec[fn]` dispatch or struct values, so none of the known codegen traps
  apply.
- Every byte read goes through `_mime_byte_at` (`(string.byte_at(s, i) as
  Int) & 0xFF`), so no `UInt8` value is compared against an integer literal.
- Fresh `Str` values are built with `xiom.string.builder.sb_to_str`; slices
  use `xiom.string.str_slice`.
- No `Ok`/`Err` is constructed anywhere (no `Result`-returning API).

## Contracts (hardening pass, 2026-10-07)

Runtime-checkable `ensures:` clauses added to `src/mime.xi` (compiler
v0.64.0; no version bump). 20 clauses across the nine public entry points
(3/3/3/2/2/2/2/2/1). Every function is total and returns `Str`, `Bool` or
`Int` only, so there is no error channel: no `requires:` clauses and no
`Result` shapes. All clauses are positive-form guard-pairs, exact formulas
or bounds. All table-derived constants (24, 8, 73, 7, 2, 82) are inline
literals; the private `_mime_*` helpers and module consts are never
referenced inside a clause. Two consecutive
`.\scripts\port.ps1 -Package xiom.mime -TimeoutSec 60` runs ended
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)` with the clauses
active and no clause trapped (13.08 s / 12.06 s).

Classes: **Z3-provable** = pure scalar formula (the plan's Z class; literals
inlined); **runtime-checked** = the clause's truth depends on a called
`_mime_*` helper or a built/sliced `Str` and is enforced by the v0.64.0
runtime evaluator.

| Entry point | Contract | Class |
|---|---|---|
| `mime_normalize` | `ensures: m.len() == 0 => result.len() == 0`; `ensures: result.len() > 0 => m.len() > 0`; `ensures: result.len() <= m.len()` | Runtime-checked (empty-in/empty-out guard pair; trim/lower/slice/trim never extends the string) |
| `mime_type_for_extension` | `ensures: ext.len() == 0 => result.len() == 24`; `ensures: result.len() >= 8`; `ensures: result.len() <= 73` | Runtime-checked (octet-stream fallback is 24; shortest curated type "text/csv" is 8; longest is pptx at 73) |
| `mime_extension_for` | `ensures: m.len() == 0 => result.len() == 0`; `ensures: result.len() <= 7`; `ensures: result.len() == 0 \|\| result.len() >= 2` | Runtime-checked (normalize("") is ""; longest primary extension "parquet" is 7; shortest primaries "js"/"md"/… are 2) |
| `mime_is_text` | `ensures: m.len() < 5 => !result`; `ensures: result => m.len() >= 5` | Runtime-checked (prefix "text/" needs 5 bytes and normalize only shortens) |
| `mime_is_image` | `ensures: m.len() < 6 => !result`; `ensures: result => m.len() >= 6` | Runtime-checked (prefix "image/" needs 6 bytes) |
| `mime_is_audio` | `ensures: m.len() < 6 => !result`; `ensures: result => m.len() >= 6` | Runtime-checked (prefix "audio/" needs 6 bytes) |
| `mime_is_video` | `ensures: m.len() < 6 => !result`; `ensures: result => m.len() >= 6` | Runtime-checked (prefix "video/" needs 6 bytes) |
| `mime_is_application` | `ensures: m.len() < 12 => !result`; `ensures: result => m.len() >= 12` | Runtime-checked (prefix "application/" needs 12 bytes) |
| `mime_type_count` | `ensures: result == 82` | Z3-provable (pure scalar; `table.len() / 2`, pinned to the 82-entry table in section 3.5) |

The bounds mirror the curated table (section 4): the fallback and every
mapped media type are 8..73 bytes, and every primary extension is 2..7
bytes. Excluded by rule: `Str`-content comparisons (BUG 17), calls to the
contract callee's own wrappers (the class checks call `mime_normalize`, so
no clause on them calls back into the module), and `Result`/tuple/struct
payload shapes (none exist). The 22-check suite exercises every entry point,
including empty and parameter-only inputs, with the clauses active.
