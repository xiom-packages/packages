// xiom.ogg.mux -- muxer/demuxer facade over the libogg packet layer (pure
// XIOM; all foreign calls live in xiom.ogg.ffi).
//
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
//   * OggMuxer: packet -> page writer (packetin + pageout/flush), with
//     page checksums computed through the page accessor path
//     (page_checksum_set) whenever a page is serialized to bytes.
//   * OggDemuxer: byte stream -> pages (sync layer).
//   * demux_all: whole-buffer decode of one logical bitstream into pages +
//     reassembled packets (the opus-in-ogg read path).
//
// The pure page layer in `xiom.ogg` is independent and stays the structural
// oracle (page walk + CRC-32) for anything these helpers produce.

module xiom.ogg.mux

use xiom.ogg.ffi;
use xiom.ogg.types;

/// Muxer state: a libogg stream handle plus its serial.
pub type OggMuxer = {
  stream: Int;
  serial: Int;
}

/// Demuxer state: a libogg sync handle.
pub type OggDemuxer = {
  sync: Int;
}

/// Result of demux_all: page count, reassembled packets and stream summary.
pub type Demuxed = {
  pages: Int;
  packets: Vec[PacketOut];
  serialno: Int;
  eos_seen: Bool;
  granulepos_last: Int;
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

/// Serialize a PageOut to its wire bytes (header followed by body). The
/// header already carries the stored checksum written by the muxer.
/// Complexity: O(page).
pub fn page_bytes(pg: &PageOut) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < pg.header.len() {
    out.push(pg.header[i]);
    i = i + 1;
  }
  var j = 0;
  while j < pg.body.len() {
    out.push(pg.body[j]);
    j = j + 1;
  }
  return out;
}

// ---------------------------------------------------------------------------
// OggMuxer
// ---------------------------------------------------------------------------

/// Create a muxer for a logical bitstream with `serial`. Complexity: O(1).
pub fn OggMuxer.create(serial: Int) -> Result[OggMuxer, Str] {
  let r = ffi.stream_init(serial);
  if !r.is_ok {
    return Err(r.error);
  }
  return Ok(OggMuxer{ stream: r.value; serial: serial });
}

/// Submit one packet (owned bytes + granule position + BOS/EOS flags).
/// Complexity: O(packet).
pub fn OggMuxer.add(mx: &OggMuxer, data: &Vec[UInt8], granulepos: Int, b_o_s: Bool, e_o_s: Bool) -> Result[Unit, Str]
  requires: mx.stream != 0
{
  return ffi.stream_packetin(mx.stream, data, b_o_s, e_o_s, granulepos, 0);
}

/// Submit one packet split across two owned buffers (iovec shape).
/// Complexity: O(packet).
pub fn OggMuxer.add_iovec(mx: &OggMuxer, a: &Vec[UInt8], b: &Vec[UInt8], granulepos: Int, e_o_s: Bool) -> Result[Unit, Str]
  requires: mx.stream != 0
{
  return ffi.stream_iovecin(mx.stream, a, b, e_o_s, granulepos);
}

/// Emit a page when the upstream flush thresholds are met (`found` false
/// means "keep queueing packets"). Complexity: O(page).
pub fn OggMuxer.page(mx: &OggMuxer) -> Result[PageOut, Str]
  requires: mx.stream != 0
{
  return ffi.stream_pageout(mx.stream);
}

/// Emit a page with an explicit fill target. Complexity: O(page).
pub fn OggMuxer.page_fill(mx: &OggMuxer, nfill: Int) -> Result[PageOut, Str]
  requires: mx.stream != 0
{
  return ffi.stream_pageout_fill(mx.stream, nfill);
}

/// Force a page out of the muxer (end of stream). Complexity: O(page).
pub fn OggMuxer.flush(mx: &OggMuxer) -> Result[PageOut, Str]
  requires: mx.stream != 0
{
  return ffi.stream_flush(mx.stream);
}

/// Serialize the next emitted page (or the flush) to wire bytes; Err when
/// no page is pending. Complexity: O(page).
pub fn OggMuxer.next_page_bytes(mx: &OggMuxer) -> Result[Vec[UInt8], Str]
  requires: mx.stream != 0
{
  let pr = ffi.stream_pageout(mx.stream);
  if !pr.is_ok {
    return Err(pr.error);
  }
  if !pr.value.found {
    return Err("ogg: muxer has no page pending");
  }
  return Ok(page_bytes(&pr.value));
}

/// Force-flush the muxer and serialize the resulting page. Err when the
/// muxer has nothing buffered. Complexity: O(page).
pub fn OggMuxer.flush_page_bytes(mx: &OggMuxer) -> Result[Vec[UInt8], Str]
  requires: mx.stream != 0
{
  let pr = ffi.stream_flush(mx.stream);
  if !pr.is_ok {
    return Err(pr.error);
  }
  if !pr.value.found {
    return Err("ogg: muxer flush produced no page");
  }
  return Ok(page_bytes(&pr.value));
}

/// True once the stream has seen its EOS flag. Complexity: O(1).
pub fn OggMuxer.eos(mx: &OggMuxer) -> Result[Bool, Str]
  requires: mx.stream != 0
{
  return ffi.stream_eos(mx.stream);
}

/// Reset the muxer (keeps the serial). Complexity: O(1).
pub fn OggMuxer.reset(mx: &OggMuxer) -> Result[Unit, Str]
  requires: mx.stream != 0
{
  return ffi.stream_reset(mx.stream);
}

/// Release the muxer state. Complexity: O(1).
pub fn OggMuxer.destroy(mx: &OggMuxer) {
  let r = ffi.stream_destroy(mx.stream);
  let ignored = r.is_ok;
}

// ---------------------------------------------------------------------------
// OggDemuxer
// ---------------------------------------------------------------------------

/// Create a byte-stream demuxer. Complexity: O(1).
pub fn OggDemuxer.create() -> Result[OggDemuxer, Str] {
  let r = ffi.sync_init();
  if !r.is_ok {
    return Err(r.error);
  }
  return Ok(OggDemuxer{ sync: r.value });
}

/// Feed bytes into the demuxer (buffer + wrote). Complexity: O(chunk).
pub fn OggDemuxer.feed(dx: &OggDemuxer, chunk: &Vec[UInt8]) -> Result[Unit, Str]
  requires: dx.sync != 0
{
  return ffi.sync_feed(dx.sync, chunk);
}

/// Next complete page, or `found` false when more bytes are needed.
/// Complexity: O(page).
pub fn OggDemuxer.next_page(dx: &OggDemuxer) -> Result[PageOut, Str]
  requires: dx.sync != 0
{
  return ffi.sync_pageout(dx.sync);
}

/// Reset the demuxer (drop buffered bytes). Complexity: O(1).
pub fn OggDemuxer.reset(dx: &OggDemuxer) -> Result[Unit, Str]
  requires: dx.sync != 0
{
  return ffi.sync_reset(dx.sync);
}

/// Release the demuxer state. Complexity: O(1).
pub fn OggDemuxer.destroy(dx: &OggDemuxer) {
  let r = ffi.sync_destroy(dx.sync);
  let ignored = r.is_ok;
}

// ---------------------------------------------------------------------------
// whole-buffer demux
// ---------------------------------------------------------------------------

/// Demux one logical bitstream from `data`: walks every page through the
/// sync layer, submits them to a stream for reassembly and drains all
/// complete packets (each copied up to `packet_cap` bytes; `size` reports
/// the full upstream packet size). Complexity: O(data len).
pub fn demux_all(data: &Vec[UInt8], packet_cap: Int) -> Result[Demuxed, Str]
  requires: packet_cap > 0
{
  let dxr = OggDemuxer.create();
  if !dxr.is_ok {
    return Err(dxr.error);
  }
  let dx = dxr.value;
  let fr = OggDemuxer.feed(&dx, data);
  if !fr.is_ok {
    OggDemuxer.destroy(&dx);
    return Err(fr.error);
  }
  var pages = 0;
  var serial = 0;
  var stream_handle = 0;
  var eos_seen = false;
  var granule_last = 0;
  var packets: Vec[PacketOut] = Vec[PacketOut].new();
  var guard = 0;
  while guard < 1000000 {
    let pr = OggDemuxer.next_page(&dx);
    if !pr.is_ok {
      OggDemuxer.destroy(&dx);
      if stream_handle != 0 {
        let ignored = ffi.stream_destroy(stream_handle);
      }
      return Err(pr.error);
    }
    if !pr.value.found {
      guard = 1000000;
    } else {
      let pg = pr.value;
      pages = pages + 1;
      if stream_handle == 0 {
        serial = pg.serialno;
        let sr = ffi.stream_init(serial);
        if !sr.is_ok {
          OggDemuxer.destroy(&dx);
          return Err(sr.error);
        }
        stream_handle = sr.value;
      }
      let inr = ffi.stream_pagein(stream_handle, &pg.header, &pg.body);
      if !inr.is_ok {
        OggDemuxer.destroy(&dx);
        let ignored = ffi.stream_destroy(stream_handle);
        return Err(inr.error);
      }
      if pg.eos {
        eos_seen = true;
      }
      if pg.granulepos >= 0 {
        granule_last = pg.granulepos;
      }
      var inner = 0;
      while inner < 1000000 {
        let kr = ffi.stream_packetout(stream_handle, packet_cap);
        if !kr.is_ok {
          OggDemuxer.destroy(&dx);
          let ignored = ffi.stream_destroy(stream_handle);
          return Err(kr.error);
        }
        if !kr.value.found {
          inner = 1000000;
        } else {
          packets.push(kr.value);
        }
      }
    }
  }
  OggDemuxer.destroy(&dx);
  if stream_handle != 0 {
    let ignored = ffi.stream_destroy(stream_handle);
  }
  return Ok(Demuxed{
    pages: pages;
    packets: packets;
    serialno: serial;
    eos_seen: eos_seen;
    granulepos_last: granule_last;
  });
}
