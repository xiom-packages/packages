# xiom.plist

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** an Apple XML property-list (plist) codec for a documented
> subset: parse into a flat node model, query it, and emit canonically.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string`,
> `xiom.string.builder`, `xiom.string.compare` and `xiom.convert`). Tests
> additionally use `xiom.test` and `xiom.io`.

## What it is

`xiom.plist` reads the XML form of Apple property lists for the subset
described in `SPEC.md`: the `<?xml ... ?>` declaration and `<!DOCTYPE ...>`
prolog are skipped, `<plist version="1.0">` is the root, and values are
`<dict>` (alternating `<key>` then a value), `<array>`, `<string>`,
`<integer>`, `<real>`, `<true/>`, `<false/>`, `<data>` and `<date>`. Text is
entity-decoded (`&amp; &lt; &gt; &quot; &apos;` plus numeric `&#NN;` /
`&#xNN;`), comments and processing instructions between elements are skipped,
and every malformed construct is a deterministic `Err("plist: ...")` -- see
the error catalog in `SPEC.md`.

The parser is a recursive-descent byte scanner over one `Str`; it never
touches a C library and every public function is a free function. The
document is *flat*: nodes live in parallel vectors (`kinds`, `texts`,
`keys`, `parents`) and children are one `Vec[Int]` addressed through
`child_starts` / `child_lengths` ranges. This is the ecosystem pattern for
XIOM v0.61.3, where `Vec[StructType]` is unsupported; the index model also
means a node's children are a contiguous slice regardless of nesting.

`<integer>` values are parsed to 64-bit `Int` with bounds checking and
stored canonically (`007` becomes `7`, `-0` becomes `0`). `<real>`, `<data>`
and `<date>` are validated text tokens: no `Vec[Float64]`, no rounding, and
base64 is passed through (whitespace stripped) rather than decoded.
`plist_emit` writes the document back with a deterministic canonical shape
(XML declaration, Apple DOCTYPE, tab indentation, LF line endings, trailing
newline) and `plist_emit` is stable under reparse.

## API

| Function | Returns | Description |
|---|---|---|
| `plist_parse(text)` | `Result[PlistDoc, Str]` | Parse a whole document; `Err("plist: ...")` on malformed input. |
| `plist_emit(d)` | `Str` | Canonical XML text; `""` when `d` has no root value or its vectors disagree. |
| `plist_root(d)` | `Int` | Root value node (only child of node 0); `-1` when absent. |
| `plist_root_kind(d)` | `Int` | Kind of the root value; `-1` when absent. |
| `plist_node_count(d)` | `Int` | Node count including the synthetic document node (empty = 1). |
| `plist_kind(d, node)` | `Int` | `PLIST_KIND_*` value; `-1` when the node is out of range. |
| `plist_parent(d, node)` | `Option[Int]` | Parent index; `Some(-1)` for node 0; `None` out of range. |
| `plist_text(d, node)` | `Str` | Payload of a scalar node; `""` for containers/out of range. |
| `plist_int_value(d, node)` | `Option[Int]` | Parsed `<integer>` value; `None` for another kind. |
| `plist_bool_value(d, node)` | `Option[Bool]` | `<true/>` / `<false/>` value; `None` for another kind. |
| `plist_dict_count(d, node)` | `Int` | Entry count of a dict; `0` for another kind. |
| `plist_dict_key(d, node, index)` | `Option[Str]` | Key of entry `index` (may be `""`); `None` out of range. |
| `plist_dict_get(d, node, key)` | `Option[Int]` | Value node of the first entry with this key; `None` when absent. |
| `plist_array_count(d, node)` | `Int` | Item count of an array; `0` for another kind. |
| `plist_array_get(d, node, index)` | `Option[Int]` | Item node by zero-based position; `None` out of range. |

Kind values: `PLIST_KIND_DICT` 0, `PLIST_KIND_ARRAY` 1, `PLIST_KIND_STRING`
2, `PLIST_KIND_INTEGER` 3, `PLIST_KIND_REAL` 4, `PLIST_KIND_BOOL` 5,
`PLIST_KIND_DATA` 6, `PLIST_KIND_DATE` 7, `PLIST_KIND_DOC` 8 (the synthetic
node 0).

## Quick start

```xi
use xiom.plist;
use xiom.io;

fn main() -> Int {
  let src = "<plist version=\"1.0\"><dict><key>name</key><string>Ada</string><key>ports</key><array><integer>80</integer><integer>443</integer></array></dict></plist>";
  let r = plist_parse(src);
  if !r.is_ok {
    io.println("parse error: " + r.error);
    return 1;
  }
  let d = r.value;
  let root = plist_root(&d);                                // 1 (the <dict>)
  match plist_dict_get(&d, root, "name") {
    Some(node) => { io.println(plist_text(&d, node)); },    // Ada
    None => {},
  }
  match plist_dict_get(&d, root, "ports") {
    Some(node) => {
      // plist_array_count(&d, node) == 2
      match plist_array_get(&d, node, 0) {
        Some(first) => { io.println(plist_text(&d, first)); },  // 80
        None => {},
      }
    },
    None => {},
  }
  io.println(plist_emit(&d));                               // canonical XML
  return 0;
}
```

## Quick start (emitter output)

For the document above, `plist_emit` produces exactly:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
	<dict>
		<key>name</key>
		<string>Ada</string>
		<key>ports</key>
		<array>
			<integer>80</integer>
			<integer>443</integer>
		</array>
	</dict>
</plist>
```

## Error model

Every parse failure is `Err(msg)` with `msg` starting with `"plist: "`; the
parser stops at the first failure and the message is deterministic. The
catalog is in `SPEC.md`; the most common are `plist: bad integer`,
`plist: mismatched tag`, `plist: premature EOF`, `plist: bad entity` and
`plist: key outside dict`. Accessors never panic: out-of-range indices yield
`-1`, `None` or `""`, and kind-strict getters return `None`/`0`/`""` for a
node of the wrong kind.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.plist
```

Expected tail: 22 `[PASS]` lines, `xiom.plist: all tests passed`, then
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- **XML plists only.** Binary plists (`bplist00`), OpenStep/NeXTSTEP plists
  and NSKeyedArchiver semantics are out of scope.
- **No full XML.** Namespaces are not resolved, CDATA sections are rejected
  (`plist: unknown tag`), a DOCTYPE internal subset is not parsed (the first
  `>` ends it), and comments/processing instructions are dropped, not
  preserved. A comment inside a text leaf (`<string>a<!--x-->b</string>`)
  is a mismatched tag because text runs end at the next `<`.
- **Flat namespace of values.** Duplicate dict keys are accepted; lookup
  returns the first match and the emitter preserves both entries.
- **No depth limit.** Deeply nested documents recurse (documented; the
  conformance suite does not pin a maximum).
- **Scalar validation.** `<real>` is a text token (no `Float64`, no value
  range check); `<date>` checks shape and calendar-ish ranges only (day 31
  in any month is accepted); `<data>` validates the base64 alphabet and
  trailing padding only (length/padding-correctness is not enforced and the
  payload is never decoded); `<string>` text is preserved verbatim
  (whitespace included), so the emitter writes it back byte-exact with
  `&`, `<` and `>` escaped.
- **One root value.** A missing or second top-level value, non-whitespace
  text outside text leaves, and any trailing content after `</plist>` are
  errors.
- **Input encoding.** `Str` is treated as a UTF-8 byte buffer and scanning
  is byte-wise; multi-byte sequences pass through untouched, but the input
  is not UTF-8-validated and raw NUL bytes are rejected.
- **No file I/O or streaming.** `plist_parse` consumes a whole `Str`.

See `SPEC.md` for the grammar subset, the API contract, the full error
catalog and the test matrix. License: MIT OR Apache-2.0 (see the repository
root `LICENSE`).
