# xiom.patch

> **Status:** incubating -- implemented and tested locally, NOT published.
> **Scope:** single-file unified diff parsing and application in pure XIOM
> (no FFI, no C, no external processes).
> **Deps:** `xiom.std` only (library: `xiom.string`, `xiom.string.compare`,
> `xiom.string.join`, `xiom.convert`; tests: `xiom.test`, `xiom.io`).

## What it is

`xiom.patch` is a small, auditable engine for the unified diff format:
parse hunk headers, count hunks, extract added/removed lines, and apply a
patch to a `Vec[Str]` of source lines or to whole LF-separated text. It is a
pure-XIOM replacement for the former placeholder (which proposed wrapping C
via FFI). Conflicts are detected, not resolved: an unapplicable hunk returns
a structured `Err` instead of guessing.

## API

| Function | Returns | Description |
|---|---|---|
| `patch_parse_hunk_header(line)` | `Option[(Int, Int, Int, Int)]` | Parse `@@ -old[,n] +new[,m] @@` into `(oldStart, oldCount, newStart, newCount)`; a missing `,count` defaults to 1; `None` when malformed. |
| `patch_count_hunks(text)` | `Int` | Number of lines starting with `@@`. |
| `patch_extract_removed(text)` | `Vec[Str]` | All `-` body lines without the sign; `---` file headers excluded. |
| `patch_extract_added(text)` | `Vec[Str]` | All `+` body lines without the sign; `+++` file headers excluded. |
| `patch_apply(source, patch)` | `Result[Vec[Str], Str]` | Apply hunks in order with full context matching and a +-20 line position fuzz; `Err` on mismatch or malformed header. |
| `patch_apply_text(source, patch)` | `Result[Str, Str]` | `patch_apply` over `Str`: split on `\n`, apply, join with `\n`. |

```xi
use xiom.io;
use xiom.patch;

let src = Vec[Str].new();
src.push("alpha");
src.push("beta");

let r = patch_apply(&src, "@@ -2,1 +2,1 @@\n-beta\n+gamma\n");
match r {
  Ok(v) => { io.println("applied: " + xiom.convert.int_to_string(v.len()) + " lines"); },
  Err(e) => { io.println("failed: " + e); },
};
```

## Testing

```
& .\scripts\port.ps1 -Package xiom.patch
```

Expected: 18 `[PASS]` lines, then `xiom.patch: all tests passed`, and a final
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Limitations

- Single-file unified diffs only; rename/copy/mode/binary headers are not
  interpreted (see `SPEC.md`).
- No binary patches, no CRLF-aware source handling (patch text may be CRLF;
  source lines are compared as given).
- Position fuzz is +-20 lines around the anchored hunk start, nearest-first;
  context lines are never dropped.
- A body line starting with `---` or `+++` is treated as a file-header
  boundary, so removing a line whose content starts with `--` is ambiguous
  and unsupported.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
