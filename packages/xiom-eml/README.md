# xiom.eml

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** RFC 5322/MIME message structure: unfolded headers, body split,
> and multipart boundaries; in-memory `Str` only.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.str_starts_with`,
> `xiom.string.builder.sb_to_str` and
> `xiom.string.compare.str_compare`). Tests additionally use `xiom.test` and
> `xiom.io`.

## Scope

`xiom.eml` parses the *structure* of an internet message: it reads the
header block into a flat `Email` (two parallel `Vec[Str]`: lowercased field
names and unfolded field values, plus the raw body), and splits a multipart
body on its boundary delimiters. Header folding is undone with a single
space, duplicate headers keep their document order, and the body is preserved
verbatim. Malformed header lines return `Err("eml: ...")`.

It intentionally does **not** decode transfer encodings, parse addresses or
dates, or interpret nested multipart trees -- see Limitations.

## API

| Function | Returns | Description |
|---|---|---|
| `eml_parse(text)` | `Result[Email, Str]` | Parse a whole message; `Err("eml: ...")` on a malformed header line. |
| `eml_header(e, name)` | `Option[Str]` | First value of `name` (case-insensitive); `None` when absent. |
| `eml_headers_all(e, name)` | `Vec[Str]` | Every value of `name`, in document order (a fresh copy). |
| `eml_header_count(e)` | `Int` | Number of header fields, duplicates counted. |
| `eml_is_multipart(e)` | `Bool` | True when the first Content-Type starts with `multipart/`. |
| `eml_content_type_boundary(e)` | `Option[Str]` | The `boundary=` parameter of the first Content-Type, quoted or bare. |
| `eml_split_parts(e, boundary)` | `Vec[Str]` | Raw part payloads split on `--<boundary>` lines. |

## Usage

```xi
use xiom.eml;
use xiom.io;

fn main() -> Int {
  let text = "Content-Type: multipart/mixed; boundary=b\r\n\r\n--b\r\nHello\r\n--b--\r\n";
  let r = eml_parse(text);
  match r {
    Ok(msg) => {
      match eml_content_type_boundary(&msg) {
        Some(b) => {
          let parts = eml_split_parts(&msg, b);
          if parts.len() == 1 {
            let first: Str = parts[0];
            io.println(first);   // Hello
          }
        },
        None => {},
      }
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.eml
```

Expected tail: 24 `[PASS]` lines, `xiom.eml: all tests passed`, then
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Structure only**: no transfer-decoding. Base64, quoted-printable, 7bit
  and 8bit part payloads are returned exactly as they appear in the body.
- **No address parsing**: `From`, `To`, `Cc` values are returned as raw
  strings; no display-name / mailbox decomposition.
- No date parsing, no MIME parameter decoding (RFC 2231), no charset
  conversion, no nested multipart recursion.
- Boundary matching is byte-exact after the line terminator: a delimiter line
  with transport padding (trailing spaces/tabs) is not recognized.
- Header values are whitespace-trimmed (`OWS` around the value and at fold
  points is not preserved).
- Errors carry the offending line text but no line/column numbers.

See `SPEC.md` for the full grammar, unfolding and boundary rules, the error
catalog and the test plan. License: MIT OR Apache-2.0 (see the repository
root `LICENSE`).
