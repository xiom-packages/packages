# xiom.ogg -- ROADMAP

## 0.1.x (shipped, pure XIOM)

* Page walk, page fields, Ogg CRC-32 (`ogg_parse_pages`, `ogg_crc32`,
  `ogg_page_crc_ok`); 22-check suite, published on the registry.

## 0.2.0 (landed)

* Vendored libogg v1.3.6 packet layer: 53/53 declared functions bound
  (sync/stream/page/packet/oggpack), zero skips; `OggMuxer`/`OggDemuxer` +
  `demux_all` facade; opus-in-ogg fixture (`tests/fixtures/tone.ogg`)
  generated with the sibling `xiom.opus` and demuxed in-suite; 34/34 green
  twice on v0.64.4.

## 0.3.x candidates (consumer-pulled only)

1. **Ogg Opus reader helper** (the `opusfile` subset the engine needs):
   `OpusHead`/`OpusTags` parsing, pre-skip/gain handling, per-packet
   `decode_float` via `xiom.opus`, granulepos -> sample mapping for
   seeking. Keep it in consumer code or a new module if a second consumer
   appears; the container and codec halves are both shipped now.
2. **Seek primitives**: bisection over pages using `sync_pageseek` +
   `page_granulepos` (canonical libvorbisfile/opusfile algorithm) exposed
   as `OggDemuxer.seek_to_granule(data, target)`.
3. **Multiplexed streams**: demux several serials in parallel (per-serial
   stream handles); `demux_all` currently follows one logical bitstream.
4. **Write-side conveniences**: page-targeted muxing (`page_fill` strategy
   presets for "one page per N ms" streaming profiles) and Ogg Skeleton
   metadata if a consumer asks.
5. **Vorbis**: still out of scope; the wave-B pin (`v1.3.7`) is retained in
   `E:\repos\vorbis` as a fallback if legacy `.ogg` music becomes a hard
   consumer requirement.
