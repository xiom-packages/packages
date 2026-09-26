# xiom.mkv

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.mkv`, version `0.1.0`).
Module: `src/mkv.xi` (`module xiom.mkv`).
Depends on `xiom.std`; the library module imports `xiom.string.builder`,
`xiom.string.compare` and `xiom.utf8` from it.

A pure-XIOM (no FFI) reader for Matroska/WebM (EBML) containers.

## Scope

- EBML element ID and size VINT decoding: IDs keep their marker bits (the
  classic table values, e.g. `Segment` `0x18538067`), sizes strip them, and
  the all-ones "unknown size" encoding is reported as `-1`. VINTs wider than
  8 bytes (first byte `0x00`) and the reserved ID encoding whose data bits are
  all zero (`0x80`, `0x4000`, ...) are rejected.
- EBML header fields: `EBMLVersion`, `EBMLReadVersion`, `EBMLMaxIDLength`,
  `EBMLMaxSizeLength`, `DocType` (`"matroska"` or `"webm"` only),
  `DocTypeVersion`, `DocTypeReadVersion`.
- `Info`: `TimestampScale` (default 1000000), `Duration`, `MuxingApp`,
  `WritingApp`, `Title` (validated UTF-8).
- `Tracks`: one entry per `TrackEntry` with `TrackNumber`, `TrackUID`,
  `TrackType` (1 video, 2 audio, 3 complex, 17 subtitle), `CodecID`, `Name`,
  `Language`, `LanguageIETF`, video `PixelWidth`/`PixelHeight` and audio
  `SamplingFrequency`/`Channels`. Records live in parallel vectors (no
  `Vec[StructType]`) behind free accessors.
- `Cluster` spans: sized clusters are skipped by their declared size and
  never decoded; unknown-size clusters are skipped to the next recognised
  Segment-level element ID whose own size VINT validates, falling back to the
  Segment/buffer end.

## Non-goals

- Writing, muxing, repairing or re-saving Matroska/WebM files.
- Block/BlockGroup decoding, frame payloads, lacing, timestamps, seek heads,
  cues, chapters, attachments, tags, codec-private data.
- Byte-exact `Duration` floats: values are decoded into integer milli-units
  (times 1000, rounded half away from zero) with documented truncation in the
  derived nanosecond/millisecond accessors.
- Multiple Segments: parsing stops after the first Segment; trailing bytes
  are ignored.
- Streaming/incremental parsing: the whole buffer is parsed in one call.

## Usage

```xiom
use xiom.io;
use xiom.mkv;
use xiom.string.compare;

fn describe(bytes: &Vec[UInt8]) -> Int {
  if !mkv_is_file(bytes) {
    io.println("not an EBML stream");
    return 1;
  }
  let r = mkv_parse(bytes);
  if !r.is_ok {
    io.println("mkv: " + r.error);
    return 1;
  }
  let f = r.value;
  io.println("doctype:  " + mkv_doctype(&f));
  io.println("scale ns: " + mkv_timestamp_scale(&f));
  io.println("tracks:   " + mkv_track_count(&f));
  io.println("clusters: " + mkv_cluster_count(&f));
  var i = 0;
  while i < mkv_track_count(&f) {
    io.println("  track " + mkv_track_number(&f, i)
      + " type " + mkv_track_type(&f, i)
      + " codec " + mkv_track_codec_id(&f, i));
    if mkv_track_video_width(&f, i) > 0 {
      io.println("    video " + mkv_track_video_width(&f, i)
        + "x" + mkv_track_video_height(&f, i));
    }
    if mkv_track_audio_sampling_millihz(&f, i) > 0 {
      io.println("    audio " + mkv_track_audio_sampling_millihz(&f, i)
        + " milliHz, " + mkv_track_audio_channels(&f, i) + " ch");
    }
    i = i + 1;
  }
  var c = 0;
  while c < mkv_cluster_count(&f) {
    io.println("  cluster " + c + ": [" + mkv_cluster_offset(&f, c)
      + ", " + mkv_cluster_end_offset(&f, c) + ")");
    c = c + 1;
  }
  return 0;
}
```

A complete synthetic fixture (header + Info + Tracks + clusters) is built
in `tests/test_conformance.xi`; run it with:

```powershell
.\scripts\port.ps1 -Package xiom.mkv
```

## API summary

- Sniff/parse: `mkv_is_file`, `mkv_parse`.
- VINT primitives: `mkv_vint_width`, `mkv_vint_id`, `mkv_vint_id_width`,
  `mkv_vint_size`, `mkv_vint_size_width`.
- Header: `mkv_segment_offset`, `mkv_segment_size`, `mkv_ebml_version`,
  `mkv_ebml_read_version`, `mkv_ebml_max_id_length`,
  `mkv_ebml_max_size_length`, `mkv_doctype`, `mkv_doctype_version`,
  `mkv_doctype_read_version`.
- Info: `mkv_info_offset`, `mkv_timestamp_scale`,
  `mkv_duration_milli_units`, `mkv_duration_nanos`, `mkv_duration_millis`,
  `mkv_muxing_app`, `mkv_writing_app`, `mkv_title`.
- Tracks: `mkv_track_count`, `mkv_track_offset`, `mkv_track_number`,
  `mkv_track_uid`, `mkv_track_type`, `mkv_track_codec_id`, `mkv_track_name`,
  `mkv_track_language`, `mkv_track_language_ietf`, `mkv_track_video_width`,
  `mkv_track_video_height`, `mkv_track_audio_sampling_millihz`,
  `mkv_track_audio_channels`.
- Clusters: `mkv_cluster_count`, `mkv_cluster_offset`,
  `mkv_cluster_data_offset`, `mkv_cluster_size`, `mkv_cluster_end_offset`,
  `mkv_cluster_is_unknown_size`.

See `SPEC.md` for the byte layouts, validation policies, error catalog and
test plan.
