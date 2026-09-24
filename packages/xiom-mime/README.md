# xiom.mime

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** Media type helpers: normalization, extension mapping, and
> top-level class checks.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice` and `xiom.string.builder`). Tests additionally use
> `xiom.test`, `xiom.io` and `xiom.string.compare`.

## Scope

`xiom.mime` provides small, infallible helpers over media type strings and file
extensions:

- `mime_normalize` -- trim, lowercase, drop parameters after `;`, trim again;
- `mime_type_for_extension` -- curated extension to media type mapping with an
  `application/octet-stream` fallback;
- `mime_extension_for` -- media type to primary extension, `""` when unknown;
- `mime_is_text` / `mime_is_image` / `mime_is_audio` / `mime_is_video` /
  `mime_is_application` -- top-level class checks;
- `mime_type_count` -- number of curated table entries.

All scanning is byte-wise ASCII; there is no FFI, no registry parse and no
dependency beyond `xiom.string`. The accepted syntax and exact table are in
`SPEC.md`.

## API

| Function | Returns | Description |
|---|---|---|
| `mime_normalize(m)` | `Str` | ASCII-trim, lowercase, drop the `;` parameter section, trim again. `""` for empty/parameter-only input. |
| `mime_type_for_extension(ext)` | `Str` | Trimmed, lowercased lookup; leading dots are tolerated (`".PNG"` works). Unknown or empty input yields `"application/octet-stream"`. |
| `mime_extension_for(m)` | `Str` | Normalized lookup of the primary extension (no dot); `""` when the media type is not in the table. |
| `mime_is_text(m)` | `Bool` | True when the normalized value starts with `text/`. |
| `mime_is_image(m)` | `Bool` | True when the normalized value starts with `image/`. |
| `mime_is_audio(m)` | `Bool` | True when the normalized value starts with `audio/`. |
| `mime_is_video(m)` | `Bool` | True when the normalized value starts with `video/`. |
| `mime_is_application(m)` | `Bool` | True when the normalized value starts with `application/` (includes the unknown-extension fallback). |
| `mime_type_count()` | `Int` | Number of curated `(extension, media type)` entries (82 in 0.1.0). |

Class checks test the **top-level type only**: `application/json` is
application-class, not text-class.

## Usage

```xi
use xiom.mime;
use xiom.io;

fn main() -> Int {
  if mime_type_for_extension(".PNG") == "image/png" {
    io.println("png ok");
  }
  if mime_is_image("image/webp; codec=x") {
    io.println("image ok");
  }
  if mime_extension_for("Text/HTML; charset=utf-8") == "html" {
    io.println("html ok");
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.mime
```

Expected tail: 22 `[PASS]` lines, `xiom.mime: all tests passed`, then
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- The mapping is a **curated table** (82 entries), not an IANA registry parse:
  uncommon types and vendor extensions fall back to
  `application/octet-stream` or resolve to `""`.
- Class checks are top-level prefix checks, so `application/json` is not
  text-class and `image/svg+xml` is image-class only.
- Normalization is ASCII-only: non-ASCII bytes pass through lowercased-input
  unchanged, and `;` inside a quoted parameter string still starts the
  parameter section.
- `mime_extension_for` returns one primary extension per media type
  (`image/jpeg` -> `jpg`), not every alias.

See `SPEC.md` for the full rules, the curated table and the test plan.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
