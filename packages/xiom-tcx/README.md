# xiom.tcx

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** Garmin TCX (Training Center XML) subset codec: parse and
> canonical build for activities, laps and trackpoints, with numeric values
> kept as validated text tokens.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.compare.str_compare` and
> `xiom.string.builder`). Tests additionally use `xiom.test` and `xiom.io`.

## What it is

`xiom.tcx` reads and writes the documented TCX subset described in `SPEC.md`:
the optional `<?xml ...?>` declaration, a `<TrainingCenterDatabase>` root,
`<Activities>`, `<Activity Sport="...">` entries with an `<Id>` and one or
more `<Lap StartTime="...">` records, lap scalar elements
(`TotalTimeSeconds`, `DistanceMeters`, `MaximumSpeed`, `Calories`,
`AverageHeartRateBpm/Value`) and an optional `<Track>` of `<Trackpoint>`
entries (`Time`, optional `Position/LatitudeDegrees/LongitudeDegrees`,
`AltitudeMeters`, `DistanceMeters`, `HeartRateBpm/Value`, `Cadence` and
`SensorState`). Attribute values must be quoted; entity references
(`&amp; &lt; &gt; &quot; &apos;` plus numeric `&#NN;` and `&#xHH;`) are
decoded on input and re-escaped on output.

Numbers are never parsed into machine numbers: `TotalTimeSeconds`,
`DistanceMeters`, `MaximumSpeed`, `AltitudeMeters` and latitude/longitude are
validated decimal literals; `Calories`, `Cadence` and heart-rate `Value` are
unsigned decimal integers; `SensorState` is `Present` or `Absent`. The
tokens are stored and re-emitted exactly (after whitespace trimming), so
there is no float rounding, no unit conversion and no GPS math anywhere in
the module. The parser is strict: unknown elements, misplaced elements,
missing required elements or attributes, unquoted attributes, duplicate
single-instance children, malformed numeric tokens, bad entities, mismatched
tags and premature end of input all return a deterministic `Err("tcx: ...")`
message instead of silently dropping data.

`tcx_build` emits canonical TCX: an `<?xml version="1.0" encoding="UTF-8"?>`
declaration line, two-space indentation, double-quoted attributes in fixed
order (`Sport`, then `StartTime`), canonical child order, escaped text,
omitted empty optional elements and a trailing newline, so parse -> build ->
parse is stable.

The document model is deliberately flat (eighteen parallel vectors with
per-record ranges, no `Vec[StructType]`), which keeps the codec small and
safe on this compiler; see `SPEC.md` for the exact layout and invariants.

## Install / use

```xi
use xiom.tcx;
use xiom.io;

fn main() -> Int {
  let r = tcx_parse("<TrainingCenterDatabase><Activities><Activity Sport=\"Running\"><Id>2026-01-01T00:00:00Z</Id><Lap StartTime=\"2026-01-01T00:00:00Z\"><TotalTimeSeconds>2400</TotalTimeSeconds><DistanceMeters>10000</DistanceMeters><Calories>700</Calories></Lap></Activity></Activities></TrainingCenterDatabase>");
  match r {
    Ok(d) => {
      io.println(tcx_activity_sport(&d, 0));        // Running
      io.println(tcx_lap_total_time(&d, 0));        // 2400
      io.println(tcx_lap_distance(&d, 0));          // 10000
      io.println(tcx_build(&d));                    // canonical TCX
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## API

| Function | Returns | Description |
|---|---|---|
| `tcx_parse(text)` | `Result[TcxDoc, Str]` | Parse a whole document; `Err("tcx: ...")` on malformed input. |
| `tcx_build(d)` | `Str` | Canonical TCX text (stable for parsed documents). |
| `tcx_new()` | `TcxDoc` | Empty document; build emits a self-closed `<Activities/>`. |
| `tcx_activity_count(d)` | `Int` | Number of activities. |
| `tcx_lap_count(d)` | `Int` | Total laps over all activities. |
| `tcx_trackpoint_count(d)` | `Int` | Total trackpoints over all laps. |
| `tcx_activity_sport(d, a)` | `Str` | `Sport` attribute (`""` when out of range). |
| `tcx_activity_id(d, a)` | `Str` | `Id` text (`""` when out of range). |
| `tcx_activity_lap_count(d, a)` | `Int` | Laps owned by activity `a` (`0` when out of range). |
| `tcx_lap_activity(d, l)` | `Int` | Owning activity of lap `l` (`-1` when out of range). |
| `tcx_lap_start_time(d, l)` | `Str` | `StartTime` attribute. |
| `tcx_lap_total_time(d, l)` | `Str` | `TotalTimeSeconds` token. |
| `tcx_lap_distance(d, l)` | `Str` | `DistanceMeters` token. |
| `tcx_lap_max_speed(d, l)` | `Str` | `MaximumSpeed` token (`""` when absent). |
| `tcx_lap_calories(d, l)` | `Str` | `Calories` token. |
| `tcx_lap_avg_hr(d, l)` | `Str` | `AverageHeartRateBpm/Value` (`""` when absent). |
| `tcx_lap_trackpoint_count(d, l)` | `Int` | Trackpoints owned by lap `l`. |
| `tcx_lap_has_track(d, l)` | `Bool` | True when lap `l` has a `Track`. |
| `tcx_trackpoint_lap(d, t)` | `Int` | Owning lap of trackpoint `t` (`-1` when out of range). |
| `tcx_trackpoint_time(d, t)` | `Str` | `Time` text. |
| `tcx_trackpoint_lat(d, t)` | `Str` | `LatitudeDegrees` token (`""` when no `Position`). |
| `tcx_trackpoint_lon(d, t)` | `Str` | `LongitudeDegrees` token (`""` when no `Position`). |
| `tcx_trackpoint_has_position(d, t)` | `Bool` | True when the trackpoint has a `Position`. |
| `tcx_trackpoint_alt(d, t)` | `Str` | `AltitudeMeters` token (`""` when absent). |
| `tcx_trackpoint_distance(d, t)` | `Str` | Trackpoint `DistanceMeters` token. |
| `tcx_trackpoint_hr(d, t)` | `Str` | `HeartRateBpm/Value` (`""` when absent). |
| `tcx_trackpoint_cadence(d, t)` | `Str` | `Cadence` token (`""` when absent). |
| `tcx_trackpoint_sensor(d, t)` | `Str` | `SensorState` token (`""` when absent). |

Out-of-range `Str` accessors return `""`; `-1` marks an unknown owner and
`0`/`false` mark empty counts and absence. No accessor panics.

## Error model

`tcx_parse` returns `Err(msg)` with a deterministic message starting with
`"tcx: "` on the first problem; the full catalog is in `SPEC.md` section 7.
Categories: malformed declaration or unsupported markup, unknown or
misplaced elements, missing required elements, missing/empty/duplicate
attributes, unquoted or malformed attributes, duplicate single-instance
children, empty elements, malformed numeric tokens, bad or unterminated
entities, mismatched or unexpected closing tags, unexpected text, and
premature end of input. Unknown attributes (namespace declarations included)
are accepted and ignored.

## Model

Element kinds are flat records with ranges: activity `a` owns laps
`[act_lap_start[a], act_lap_start[a+1])` and lap `l` owns trackpoints
`[lap_tp_start[l], lap_tp_start[l+1])`. See `SPEC.md` section 5 for the full
`TcxDoc` field table and invariants.

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.tcx
```

Expected tail: 23 `[PASS]` lines, `xiom.tcx: all tests passed`, then
`port: PASS (passed=23 failed=0 program_exit=0 exit=0)`.

## Limitations

- Documented subset only: no courses, workouts, extensions, creator/author
  blocks, activity-type payload elements, comments, CDATA, DTD, namespaces
  semantics or `<?...?>` processing instructions other than the declaration.
- Numeric tokens stay text: no parsing to numbers, no ranges, no unit
  conversion, no arithmetic; `+1.5`, `-0.0` and leading zeros are preserved.
- Timestamps (`Id`, `Time`, `StartTime`) are opaque text, never normalized.
- Unknown attributes are accepted and ignored, and `tcx_build` does not
  reproduce them, so output is canonical rather than a byte-copy.
- An `Activities` element must contain at least one `Activity`, and each
  `Activity` at least one `Lap`; the emitter's empty-`Activities` skeleton
  therefore does not re-parse (documented by design).
- A raw `<` inside an attribute value is rejected; `&`, `<` and `>` in text
  and `"` in attributes must be entities. Leaf text is trimmed and holds one
  text run.
- No file I/O, no streaming parser, no GPS math, no schema validation.

See `SPEC.md` for the grammar, semantics, error catalog and test matrix.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
