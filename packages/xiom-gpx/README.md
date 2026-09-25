# xiom.gpx

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** GPX 1.1 subset codec: parse and canonical build for waypoints,
> routes, track segments and track points, with fixed-point coordinates.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.compare.str_compare`,
> `xiom.string.builder` and `xiom.convert.int_to_string`). Tests additionally
> use `xiom.test` and `xiom.io`.

## What it is

`xiom.gpx` reads and writes the documented GPX subset described in `SPEC.md`:
the optional `<?xml ...?>` declaration, a `<gpx version creator>` root,
`<wpt lat lon>` waypoints, `<rte>` routes, `<trk>` / `<trkseg>` /
`<trkpt lat lon>` tracks, and the child text elements `name`, `desc`, `sym`,
`type`, `ele` and `time` on waypoints, routes, tracks and track points.
Entity references (`&amp; &lt; &gt; &quot; &apos;` plus numeric `&#NN;` and
`&#xHH;`) are decoded on input and re-escaped on output.

Everything is fixed-point: coordinates are stored as integer microdegrees
(1e-6 degree), never floats, and latitude/longitude literals are validated
lexically against the GPX ranges (-90..90 and -180..180). The parser is
strict: unknown elements, misplaced elements, unquoted attributes, missing
`lat`/`lon`, out-of-range coordinates, bad entities, mismatched tags and
premature end of input all return a deterministic `Err("gpx: ...")` message
instead of silently dropping data.

`gpx_build` emits canonical GPX: an `<?xml version="1.0"
encoding="UTF-8"?>` declaration line, two-space indentation, double-quoted
attributes, escaped text, self-closed empty elements and a trailing newline,
so parse -> build -> parse is stable.

The document model is deliberately flat (parallel `Vec` fields, no
`Vec[StructType]`), which keeps the codec small and safe on this compiler;
see `SPEC.md` for the exact layout and invariants.

## Install / use

```xi
use xiom.gpx;
use xiom.convert;
use xiom.io;

fn main() -> Int {
  let r = gpx_parse("<gpx version=\"1.1\" creator=\"demo\"><wpt lat=\"37.5\" lon=\"-122.4\"><name>Start</name></wpt></gpx>");
  match r {
    Ok(d) => {
      io.println("nodes: " + convert.int_to_string(gpx_node_count(&d)));
      match gpx_lat_udeg(&d, 1) {
        Some(udeg) => { io.println("lat: " + gpx_coord_text(udeg)); },  // 37.5
        None => {},
      }
      match gpx_field(&d, 1, 0) {
        Some(name) => { io.println("name: " + name); },                 // Start
        None => {},
      }
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## API

Node kinds: `0` gpx root, `1` wpt, `2` rte, `3` trk, `4` trkseg, `5` trkpt.
Field kinds: `0` name, `1` desc, `2` sym, `3` type, `4` ele, `5` time.

| Function | Returns | Description |
|---|---|---|
| `gpx_parse(text)` | `Result[GpxDoc, Str]` | Parse a whole document; `Err("gpx: ...")` on malformed input. |
| `gpx_build(d)` | `Str` | Canonical GPX text (idempotent). |
| `gpx_new(version, creator)` | `GpxDoc` | Empty document with a gpx root. |
| `gpx_add_waypoint(d, lat, lon)` | `Int` | Append a wpt; node index or `-1` when a coordinate is out of range. |
| `gpx_add_route(d)` | `Int` | Append an rte under the root. |
| `gpx_add_track(d)` | `Int` | Append a trk under the root. |
| `gpx_add_segment(d, track)` | `Int` | Append a trkseg to a trk; `-1` when `track` is not a trk. |
| `gpx_add_trackpoint(d, seg, lat, lon)` | `Int` | Append a trkpt to a trkseg; `-1` on a bad parent or coordinate. |
| `gpx_set_field(d, node, field, value)` | `Bool` | Set or replace a child text element; `false` when the node or kind is invalid. |
| `gpx_node_count(d)` | `Int` | Number of nodes, including the root. |
| `gpx_kind(d, node)` | `Int` | Node kind; `-1` when out of range. |
| `gpx_parent(d, node)` | `Int` | Parent index (`-1` for the root); `-2` when out of range. |
| `gpx_version(d)` / `gpx_creator(d)` | `Str` | Root attributes (`""` when absent). |
| `gpx_lat_udeg(d, node)` / `gpx_lon_udeg(d, node)` | `Option[Int]` | Microdegrees for wpt/trkpt nodes. |
| `gpx_field(d, node, field)` | `Option[Str]` | Decoded child text (empty element -> `Some("")`). |
| `gpx_has_field(d, node, field)` | `Bool` | Presence test. |
| `gpx_field_count(d, node)` | `Int` | Number of child text elements. |
| `gpx_nodes_of_kind(d, kind)` | `Vec[Int]` | Node indices in document order. |
| `gpx_children(d, node)` | `Vec[Int]` | Direct child node indices in document order. |
| `gpx_coord_parse(text)` | `Option[Int]` | Decimal degrees -> microdegrees; `None` when malformed or outside -180..180. |
| `gpx_coord_text(udeg)` | `Str` | Canonical decimal degrees for a microdegree value. |

## Build from scratch

```xi
use xiom.gpx;
use xiom.io;

fn main() -> Int {
  var d = gpx_new("1.1", "demo");
  let w = gpx_add_waypoint(&mut d, 37500000, -122400000);
  gpx_set_field(&mut d, w, 0, "Start");

  let trk = gpx_add_track(&mut d);
  let seg = gpx_add_segment(&mut d, trk);
  gpx_add_trackpoint(&mut d, seg, 37510000, -122410000);

  io.println(gpx_build(&d));
  return 0;
}
```

Canonical output:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="demo">
  <wpt lat="37.5" lon="-122.4">
    <name>Start</name>
  </wpt>
  <trk>
    <trkseg>
      <trkpt lat="37.51" lon="-122.41"/>
    </trkseg>
  </trk>
</gpx>
```

## Error model

`gpx_parse` returns `Err(msg)` with a deterministic message starting with
`"gpx: "` on the first problem; the full catalog is in `SPEC.md` section 7.
Categories: malformed declaration or unsupported markup, unknown or misplaced
elements, duplicate elements, attribute quoting/duplication errors, missing or
invalid `lat`/`lon`, bad or unterminated entities, mismatched or unexpected
closing tags, unexpected text, and premature end of input. Builder functions
report failure through return values (`-1` node index, `false` from
`gpx_set_field`) instead of panicking.

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.gpx
```

Expected tail: 29 `[PASS]` lines, `xiom.gpx: all tests passed`, then
`port: PASS (passed=29 failed=0 program_exit=0 exit=0)`.

## Limitations

- Documented subset only: no namespaces, CDATA, comments, DTD, processing
  instructions other than a leading `<?xml ...?>`, `<extensions>`, or
  `<rtept>` route points.
- Coordinates are fixed-point microdegrees: extra fraction digits are rounded
  half away from zero to six decimals, and `gpx_build` writes the shortest
  exact form (`37.5`, not `37.500000`).
- Root `version` and `creator` are optional on input and stored as `""`;
  `gpx_build` always emits both attributes.
- Leaf text is preserved byte-for-byte (no trimming); each leaf holds one text
  run and duplicate child elements are rejected.
- A raw `<` inside an attribute value is rejected; `&`, `<` and `>` in text
  and `"` in attributes must be entities.
- No file I/O, no geo math, no schema validation.

See `SPEC.md` for the grammar, semantics, error catalog and test matrix.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
