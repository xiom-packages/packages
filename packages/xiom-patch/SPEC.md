# xiom.patch -- SPEC

Status: incubating (0.1.0). Pure XIOM, no FFI. All functions are free
functions in `module xiom.patch` (see `src/patch.xi`).

## 1. Scope

Parse and apply **single-file unified diffs**:

- hunk-header parsing (`patch_parse_hunk_header`),
- hunk counting (`patch_count_hunks`),
- added/removed line extraction (`patch_extract_added` / `patch_extract_removed`),
- hunk application to a `Vec[Str]` of lines (`patch_apply`) and to
  LF-separated text (`patch_apply_text`),
- conflict **detection** via typed `Err` strings.

## 2. Non-goals

- No binary patches (`GIT binary patch`, `Binary files ... differ`).
- No rename/copy/mode/`index` metadata interpretation; such preamble lines
  are skipped, not honored.
- No multi-file application: only the hunks of one file are applied, in
  order.
- No patch generation, no three-way merge, no conflict resolution.
- No CRLF normalization of **source** lines (patch text may be CRLF: a single
  trailing `\r` is stripped from parsed patch lines).
- No context-dropping fuzz levels (GNU `--fuzz=N`); the workaround is a
  position window, see section 4.

## 3. Accepted grammar

Patch text is split on `\n`. A hunk starts at any line whose first two bytes
are `@@`; a line starting with `@@` that does not parse is a hard error.

Hunk header (spaces are the only separator and are optional between tokens):

```
"@@" [SP]* "-" uint ["," uint] [SP]* "+" uint ["," uint] [SP]* ["@@" rest]
```

- `uint` is one or more ASCII digits (`0-9`); no sign, no overflow check.
- An omitted `,count` defaults to `1`.
- The trailing `@@` is optional; when present, any following text (git
  function context) is ignored. Any other trailing text is malformed.
- Examples accepted: `@@ -1,5 +2,6 @@`, `@@ -0,0 +1,3 @@`,
  `@@ -3 +7 @@`, `@@ -10,1 +10,1 @@ fn main() {`, `@@ -1,5 +2,6`.
- Examples rejected: `@@ 1,5 +2,6 @@`, `@@ -1,5 2,6 @@`, `@@ -x +1 @@`,
  `@@ -1 + @@`, `@@ -1,5 +2,6 junk`.

Hunk body lines (until the next `@@` line, a `---`/`+++` line, a line that
starts with none of the recognized prefixes, or end of text):

| Prefix | Meaning |
|---|---|
| `' '` | context line: old and new |
| `'-'` | removed line: old only |
| `'+'` | added line: new only |
| `'\'` | `\ No newline at end of file` marker: ignored |
| empty | separator: ignored (an empty context line is written as `" "`) |

Because body parsing is prefix-based (hunk counts are not enforced), a body
line starting with `---` or `+++` terminates the hunk -- removing a line whose
content itself starts with `--` is therefore ambiguous and unsupported.

## 4. Apply algorithm and fuzz policy

`patch_apply(source, patch)`:

1. Copy `source` into a working vector. Empty patch text (or text without
   `@@` lines) returns `Ok(copy)` unchanged.
2. Scan patch lines. Non-`@@` lines outside a hunk are skipped (diff
   preamble). `@@` starts hunk `N` (1-based, in file order); a malformed
   header aborts with `Err("patch: malformed hunk header")`.
3. Collect the hunk body into `old_lines` (context + `-`) and `new_lines`
   (context + `+`).
4. Anchor: 0-based index `oldStart - 1`, or `oldStart` when the header's
   `oldCount == 0` (git `-U0` convention: a pure insertion goes *after* old
   line `oldStart`). The anchor is shifted by the accumulated line delta
   `offset` of previously applied hunks, so later hunk positions refer to the
   original file coordinates as in standard unified diffs.
5. Match `old_lines` in full (context lines are never dropped) against the
   working vector at the exact candidate; on failure try `candidate +-1`
   through `candidate +-20`, nearest distance first, lower index before higher
   within a distance. First match wins.
6. No match: `Err("patch: hunk N failed to apply at line L")` where `L` is
   the hunk's `oldStart`; nothing is mutated (the working copy is discarded).
   Match: splice `old_lines` -> `new_lines` and add
   `new_lines.len() - old_lines.len()` to `offset`.

Fuzz policy summary: full-context matching, position-only fuzz of **+-20
lines**, no context dropping. Two identical candidate matches prefer the
nearest, then the lowest index.

`patch_apply_text(source, patch)` splits `source` on `\n`, calls
`patch_apply`, and joins the result with `\n` (a trailing newline in `source`
survives as a trailing empty element).

## 5. Error strings

| Condition | Result |
|---|---|
| malformed `@@` header | `Err("patch: malformed hunk header")` |
| unapplicable hunk | `Err("patch: hunk <N> failed to apply at line <oldStart>")` |
| empty / hunk-less patch | `Ok(source copy)` |

## 6. Test plan

`tests/test_conformance.xi` (18 checks, harness `xiom --run`):

1. header with explicit counts (4 shapes), 2. missing `,count` defaults (3
shapes), 3. malformed headers -> `None` (7 shapes), 4. `count_hunks`,
5. `extract_removed` skips `---`, 6. `extract_added` skips `+++`, 7. pure
insertion at start, 8. pure deletion, 9. replacement, 10. multi-hunk across a
line-count shift, 11. context mismatch -> `Err` with exact message, 12.
malformed header -> `Err` with exact message, 13. empty/hunk-less patch
unchanged, 14. `apply_text` split/join incl. trailing newline, 15. source
shorter than hunk -> `Err`, 16. fuzz relocates within +-20, 17. mismatch
beyond the fuzz window -> `Err`, 18. zero-count insertion anchors after
`oldStart`.

Result vectors are compared element-wise with `str_compare` (BUG 17: `==` on
`Str` read from `Vec[Str]` elements is a pointer comparison).

## 7. Known compiler workarounds

- `Ok`/`Err` are constructed only inside the `_ok_*`/`_err_*` helpers, never
  directly in the public bodies (XIOM v0.61.3 miscompiles direct Result
  construction in struct-returning functions; kept uniform here).
- No `Vec[StructType]`, so hunks are consumed streaming instead of collected
  into a `Vec[Hunk]`.
- `patch_parse_hunk_header` returns a 4-tuple `Option[(Int, Int, Int, Int)]`
  rather than a struct, avoiding struct-in-Option lowering.

## 8. Known limitations

- Single file, unified format only; unsupported metadata is ignored, which
  can silently mis-apply a multi-file patch (only its hunks are applied, in
  order, to the one source vector).
- `---`/`+++`-prefixed body content ambiguity (section 3).
- Removing a line that consists of three or more dashes/pluses at the start
  of patch line is not representable.
- No enforcement of declared hunk counts; a lying header is matched by its
  body, not its numbers.
- Large files and pathological fuzz searches are O(hunks * 41 * hunk size).
