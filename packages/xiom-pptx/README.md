# xiom.pptx

> **Status:** `incubating` -- conformance-tested (26/26); published at `v0.1.0` on the XIOM registry.
> **Scope:** pure-XIOM PowerPoint OpenXML (PPTX) reading and writing for a
> minimal PresentationML subset: presentation/slide model, rectangular
> text-box shapes with integer-EMU geometry, all inside a self-implemented
> ZIP container. No rendering, no themes, no images, no slide masters and
> no charts.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.compare`,
> `xiom.string.builder`, `xiom.convert`, `xiom.compress.deflate`,
> `xiom.compress.gzip`). No C, no FFI.

## What it is

`xiom.pptx` ports the `pptx-read`, `pptx-write` and `pptx-slide` trio as one
module with three layers:

1. **ZIP container** -- writer (local headers, central directory, EOCD;
   STORED or DEFLATE entries with CRC-32) and reader (EOCD scan with archive
   comments, strict central-directory walk, local-header cross-checks,
   STORED + DEFLATE decode). See `SPEC.md` for the exact supported subset.
2. **Presentation model** -- flat, `Vec[Int]`-only slide/shape storage with
   a shared UTF-8 text pool; integer EMU geometry (1 in = 914400,
   1 mm = 36000, 1 pt = 12700).
3. **PresentationML subset** -- writes `[Content_Types].xml`, `_rels/.rels`,
   `ppt/presentation.xml`, `ppt/_rels/presentation.xml.rels` and
   `ppt/slides/slideN.xml`; reads the same parts back, resolving slides
   through `p:sldId -> r:id -> relationship Target`.

DEFLATE payloads are produced by `xiom.compress.deflate`
(fixed-Huffman blocks up to 64 KiB, stored blocks above) and decoded with
`deflate_decompress_capped` first, falling back to a local STORED +
fixed-Huffman decoder. Dynamic-Huffman (BTYPE 2) read support is the one
documented gap.

## Libs inventory

| Lib | Description |
|-----|-------------|
| `pptx-read` | EOCD/central-directory ZIP reader plus PresentationML parser (`zip_read`, `zip_entry_*`, `pptx_presentation_from_bytes`) |
| `pptx-write` | ZIP writer and part serializer (`zip_writer_*`, `pptx_presentation_to_bytes`, `pptx_presentation_to_bytes_stored`) |
| `pptx-slide` | Slide layout and shape model (`PptxPresentation`, `pptx_add_slide`, `pptx_add_text_box`, geometry + accessors) |

## API

| Group | Functions |
|---|---|
| model | `pptx_presentation_new/new_default`, `pptx_add_slide`, `pptx_add_text_box` |
| accessors | `pptx_slide_count`, `pptx_shape_count`, `pptx_slide_shape_count`, `pptx_slide_shape`, `pptx_shape_slide/kind/kind_name/x/y/width/height/text`, `pptx_presentation_width/height` |
| geometry | `pptx_mm_to_emu`, `pptx_emu_to_mm`, `pptx_inches_to_emu`, `pptx_emu_to_inches`, `pptx_points_to_emu`, `pptx_emu_to_points` |
| serialize | `pptx_presentation_to_bytes`, `pptx_presentation_to_bytes_stored`, `pptx_presentation_to_bytes_method` |
| parse | `pptx_presentation_from_bytes` |
| zip write | `zip_writer_new`, `zip_writer_add`, `zip_writer_entry_count`, `zip_writer_finish` |
| zip read | `zip_read`, `zip_entry_count/find/name/method/crc/size/compressed_size/local_offset/data`, `zip_crc32` |
| inflate | `zip_inflate_fixed` |

```xiom
use xiom.pptx;

fn main() -> Int {
  var p = pptx_presentation_new_default();
  let s = pptx_add_slide(&mut p);
  let b = pptx_add_text_box(&mut p, 0, 914400, 457200, 3657600, 914400, "Hello");
  let r = pptx_presentation_to_bytes(&p);
  // r.value is a Vec[UInt8]; pptx_presentation_from_bytes(&r.value) parses it back
  return 0;
}
```

## Verification

```
& .\scripts\port.ps1 -Package xiom-pptx
```

runs `tests/test_conformance.xi` (26 fixture-free checks) from the
repository root.

## License

MIT OR Apache-2.0.
