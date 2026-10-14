// xiom.ogg -- safe FFI wrappers over the vendored libogg v1.3.6 packet layer.
//
// G5 confinement: this is the ONE module in the package that contains
// `unsafe` blocks; the pure page layer in `xiom.ogg` is unchanged and
// independent.  Library: vendored libogg (BSD-3) compiled from vendor/ogg
// via --c-source (see SPEC.md and PROVENANCE.md for the pin and the
// four-line include rewrite).
//
// Discipline (compiler v0.64.4):
//   * state structs are bridge-allocated; handles are Int (never cast to
//     pointers here -- B-25);
//   * payload bytes cross as owned Vec[UInt8]: inputs .as_ptr(), outputs
//     .as_mut_ptr(); page/packet copy-out fills owned buffers, meta comes
//     from owned slots read byte-indexed (B-20/B-24);
//   * one owned slot per out-param (page info 16 bytes, packet info 32);
//   * flat outcome structs only (B-26).
//
// Error model: upstream return codes are 0 or positive on success and
// negative on error (with `ogg_sync_pageseek` also using negative counts
// as "bytes skipped").  Wrappers return Err("ogg: <context> rc=<code>") on
// negative codes; sentinel-returning bit reads (`pack_look`/`pack_read`)
// return the raw Int where -1 means "not enough bits".
//
// Ownership notes:
//   * `stream_pagein` copies the page payload into the stream state, so the
//     header/body Vecs may be dropped after the call;
//   * `pack_readinit` copies the bytes into a bridge-owned buffer, so
//     `pack_writeclear`/`pack_free` are safe on any pack handle;
//   * `packet_clear` never frees XIOM-owned bytes (the bridge nulls the
//     packet pointer before calling upstream ogg_packet_clear).

module xiom.ogg.ffi

use xiom.ogg.types;

// ---------------------------------------------------------------------------
// internal helpers (leaf Result constructors only; B-26 flat shapes)
// ---------------------------------------------------------------------------

fn _ok_i(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

fn _err_i(m: Str) -> Result[Int, Str] {
  return Err(m);
}

fn _ok_u() -> Result[Unit, Str] {
  return Ok({});
}

fn _err_u(m: Str) -> Result[Unit, Str] {
  return Err(m);
}

fn _ok_b(v: Bool) -> Result[Bool, Str] {
  return Ok(v);
}

fn _err_b(m: Str) -> Result[Bool, Str] {
  return Err(m);
}

fn _ok_p(v: PageOut) -> Result[PageOut, Str] {
  return Ok(v);
}

fn _err_p(m: Str) -> Result[PageOut, Str] {
  return Err(m);
}

fn _ok_pkt(v: PacketOut) -> Result[PacketOut, Str] {
  return Ok(v);
}

fn _err_pkt(m: Str) -> Result[PacketOut, Str] {
  return Err(m);
}

fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

fn rc_err(what: Str, rc: Int) -> Str {
  return "ogg: " + what + " rc=" + rc;
}

fn slot(n: Int) -> Vec[UInt8] {
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < n {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

fn buf_zero(n: Int) -> Vec[UInt8] {
  return slot(n);
}

fn read_i32_at(buf: &Vec[UInt8], pos: Int) -> Int {
  let b0 = buf[pos] as Int;
  let b1 = buf[pos + 1] as Int;
  let b2 = buf[pos + 2] as Int;
  let b3 = buf[pos + 3] as Int;
  let raw = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
  if b3 >= 128 {
    return raw - 4294967296;
  }
  return raw;
}

fn read_i64_at(buf: &Vec[UInt8], pos: Int) -> Int {
  var v: Int = 0;
  var i = 0;
  while i < 7 {
    v = v + ((buf[pos + i] as Int) << (8 * i));
    i = i + 1;
  }
  v = v + (buf[pos + 7] as Int) * 72057594037927936;
  return v;
}

// ---------------------------------------------------------------------------
// generated bridge externs (tools/gen_ogg.py; do not edit inside markers)
// ---------------------------------------------------------------------------

// >>> GENERATED-EXTERNS-BEGIN (tools/gen_ogg.py)
extern "C" {
  fn xo_pack_writeinit() -> Int;
  fn xo_pack_writecheck(p0: Int) -> Int;
  fn xo_pack_writetrunc(p0: Int, p1: Int) -> Int;
  fn xo_pack_writealign(p0: Int) -> Int;
  fn xo_pack_writecopy(p0: Int, p1: *UInt8, p2: Int) -> Int;
  fn xo_pack_reset(p0: Int) -> Int;
  fn xo_pack_writeclear(p0: Int) -> Int;
  fn xo_pack_readinit(p0: Int, p1: *UInt8, p2: Int) -> Int;
  fn xo_pack_write(p0: Int, p1: Int, p2: Int) -> Int;
  fn xo_pack_look(p0: Int, p1: Int) -> Int;
  fn xo_pack_look1(p0: Int) -> Int;
  fn xo_pack_adv(p0: Int, p1: Int) -> Int;
  fn xo_pack_adv1(p0: Int) -> Int;
  fn xo_pack_read(p0: Int, p1: Int) -> Int;
  fn xo_pack_read1(p0: Int) -> Int;
  fn xo_pack_bytes(p0: Int) -> Int;
  fn xo_pack_bits(p0: Int) -> Int;
  fn xo_pack_get_buffer(p0: Int, p1: *UInt8, p2: Int) -> Int;
  fn xo_stream_packetin(p0: Int, p1: Int) -> Int;
  fn xo_stream_iovecin(os: Int, a: *UInt8, a_len: Int, b: *UInt8, b_len: Int, e_o_s: Int, granulepos: Int) -> Int;
  fn xo_stream_pageout(os: Int, page: Int, hdr_out: *UInt8, hdr_cap: Int, body_out: *UInt8, body_cap: Int, info_out: *UInt8) -> Int;
  fn xo_stream_pageout_fill(os: Int, nfill: Int, page: Int, hdr_out: *UInt8, hdr_cap: Int, body_out: *UInt8, body_cap: Int, info_out: *UInt8) -> Int;
  fn xo_stream_flush(os: Int, page: Int, hdr_out: *UInt8, hdr_cap: Int, body_out: *UInt8, body_cap: Int, info_out: *UInt8) -> Int;
  fn xo_stream_flush_fill(os: Int, nfill: Int, page: Int, hdr_out: *UInt8, hdr_cap: Int, body_out: *UInt8, body_cap: Int, info_out: *UInt8) -> Int;
  fn xo_sync_init() -> Int;
  fn xo_sync_clear(p0: Int) -> Int;
  fn xo_sync_reset(p0: Int) -> Int;
  fn xo_sync_destroy(p0: Int) -> Int;
  fn xo_sync_check(p0: Int) -> Int;
  fn xo_sync_buffer(sync: Int, data: *UInt8, size: Int) -> Int;
  fn xo_sync_wrote(p0: Int, p1: Int) -> Int;
  fn xo_sync_pageseek(p0: Int) -> Int;
  fn xo_sync_pageout(sync: Int, page: Int, hdr_out: *UInt8, hdr_cap: Int, body_out: *UInt8, body_cap: Int, info_out: *UInt8) -> Int;
  fn xo_stream_pagein(p0: Int, p1: Int) -> Int;
  fn xo_stream_packetout(os: Int, packet: Int, data_out: *UInt8, cap: Int, info_out: *UInt8) -> Int;
  fn xo_stream_packetpeek(os: Int, packet: Int, data_out: *UInt8, cap: Int, info_out: *UInt8) -> Int;
  fn xo_stream_init(p0: Int) -> Int;
  fn xo_stream_clear(p0: Int) -> Int;
  fn xo_stream_reset(p0: Int) -> Int;
  fn xo_stream_reset_serialno(p0: Int, p1: Int) -> Int;
  fn xo_stream_destroy(p0: Int) -> Int;
  fn xo_stream_check(p0: Int) -> Int;
  fn xo_stream_eos(p0: Int) -> Int;
  fn xo_page_checksum_set(p0: Int) -> Int;
  fn xo_page_version(p0: Int) -> Int;
  fn xo_page_continued(p0: Int) -> Int;
  fn xo_page_bos(p0: Int) -> Int;
  fn xo_page_eos(p0: Int) -> Int;
  fn xo_page_granulepos(p0: Int) -> Int;
  fn xo_page_serialno(p0: Int) -> Int;
  fn xo_page_pageno(p0: Int) -> Int;
  fn xo_page_packets(p0: Int) -> Int;
  fn xo_packet_clear(p0: Int) -> Int;
  // owned struct companions (documented extensions)
  fn xo_pack_free(pack: Int) -> Int;
  fn xo_packet_create() -> Int;
  fn xo_packet_free(packet: Int) -> Int;
  fn xo_packet_set(packet: Int, data: *UInt8, bytes: Int, b_o_s: Int, e_o_s: Int, granulepos: Int, packetno: Int) -> Int;
  fn xo_page_create() -> Int;
  fn xo_page_free(page: Int) -> Int;
  fn xo_page_set(page: Int, header: *UInt8, header_len: Int, body: *UInt8, body_len: Int) -> Int;
}
// <<< GENERATED-EXTERNS-END

// ---------------------------------------------------------------------------
// page/packet struct helpers (bridge-owned structs over caller buffers)
// ---------------------------------------------------------------------------

// Create a page struct filled from owned header/body buffers; returns the
// handle.  Callers must free it with page_free.
fn page_handle(header: &Vec[UInt8], body: &Vec[UInt8]) -> Result[Int, Str] {
  var pg: Int = 0;
  unsafe {
    pg = xo_page_create();
  }
  if pg == 0 {
    return _err_i("ogg: page struct allocation failed");
  }
  var rc: Int = 0;
  unsafe {
    rc = xo_page_set(pg, header.as_ptr(), header.len(), body.as_ptr(), body.len());
  }
  if rc != 0 {
    unsafe {
      let ignored = xo_page_free(pg);
    }
    return _err_i(rc_err("page_set", rc));
  }
  return _ok_i(pg);
}

// ---------------------------------------------------------------------------
// sync layer
// ---------------------------------------------------------------------------

/// Allocate and initialize an ogg_sync_state; returns its handle.
/// Complexity: O(1).
pub fn sync_init() -> Result[Int, Str] {
  var h: Int = 0;
  unsafe {
    h = xo_sync_init();
  }
  if h == 0 {
    return _err_i("ogg: sync state allocation failed");
  }
  return _ok_i(h);
}

/// Release the sync state's internal buffers (struct stays usable after
/// ogg_sync_init semantics; use sync_destroy to free the handle).
pub fn sync_clear(h: Int) -> Result[Unit, Str] {
  var rc: Int = 0;
  unsafe {
    rc = xo_sync_clear(h);
  }
  if rc != 0 {
    return _err_u(rc_err("sync_clear", rc));
  }
  return _ok_u();
}

/// Reset the sync state to "no data buffered". Complexity: O(1).
pub fn sync_reset(h: Int) -> Result[Unit, Str] {
  var rc: Int = 0;
  unsafe {
    rc = xo_sync_reset(h);
  }
  if rc != 0 {
    return _err_u(rc_err("sync_reset", rc));
  }
  return _ok_u();
}

/// 0 when the sync state is valid. Complexity: O(1).
pub fn sync_check(h: Int) -> Result[Int, Str] {
  var rc: Int = 0;
  unsafe {
    rc = xo_sync_check(h);
  }
  if rc != 0 {
    return _err_i(rc_err("sync_check", rc));
  }
  return _ok_i(0);
}

/// Clear and free the sync state handle. Complexity: O(1).
pub fn sync_destroy(h: Int) -> Result[Unit, Str] {
  var rc: Int = 0;
  unsafe {
    rc = xo_sync_destroy(h);
  }
  if rc != 0 {
    return _err_u(rc_err("sync_destroy", rc));
  }
  return _ok_u();
}

/// Submit `chunk` to the sync layer (upstream ogg_sync_buffer + memcpy);
/// returns the byte count the caller must pass to sync_wrote.
/// Complexity: O(chunk len).
pub fn sync_buffer(h: Int, chunk: &Vec[UInt8]) -> Result[Int, Str] {
  var rc: Int = 0;
  unsafe {
    rc = xo_sync_buffer(h, chunk.as_ptr(), chunk.len());
  }
  if rc < 0 {
    return _err_i(rc_err("sync_buffer", rc));
  }
  return _ok_i(rc);
}

/// Commit `bytes` submitted through sync_buffer. Complexity: O(1).
pub fn sync_wrote(h: Int, bytes: Int) -> Result[Unit, Str] {
  var rc: Int = 0;
  unsafe {
    rc = xo_sync_wrote(h, bytes);
  }
  if rc != 0 {
    return _err_u(rc_err("sync_wrote", rc));
  }
  return _ok_u();
}

/// Convenience: submit the whole chunk and commit it in one call.
/// Complexity: O(chunk len).
pub fn sync_feed(h: Int, chunk: &Vec[UInt8]) -> Result[Unit, Str] {
  let br = sync_buffer(h, chunk);
  if !br.is_ok {
    return Err(br.error);
  }
  return sync_wrote(h, br.value);
}

/// Fetch the next page at the current position without buffering: returns
/// the raw upstream code (> 0 page size, 0 need more data, < 0 bytes
/// skipped with a possible resync). Complexity: O(page).
pub fn sync_pageseek(h: Int) -> Result[Int, Str] {
  var rc: Int = 0;
  unsafe {
    rc = xo_sync_pageseek(h);
  }
  if rc < 0 {
    // negative pageseek codes are the documented "bytes skipped" signal
    return _ok_i(rc);
  }
  return _ok_i(rc);
}

/// Pull the next complete page out of the sync state.  `found` is false
/// when more data must be fed (upstream code 0). Complexity: O(page).
pub fn sync_pageout(h: Int) -> Result[PageOut, Str] {
  var pg: Int = 0;
  unsafe {
    pg = xo_page_create();
  }
  if pg == 0 {
    return _err_p("ogg: page struct allocation failed");
  }
  var hdr = buf_zero(282);
  var body = buf_zero(65536);
  var info = slot(16);
  var rc: Int = 0;
  unsafe {
    rc = xo_sync_pageout(h, pg, hdr.as_mut_ptr(), 282, body.as_mut_ptr(), 65536, info.as_mut_ptr());
  }
  let out = page_result(pg, rc, &hdr, &body, &info);
  unsafe {
    let ignored = xo_page_free(pg);
  }
  return out;
}

// Read a page struct + info slot into a flat PageOut outcome and free the
// handle is the caller's job (kept separate so both pageout paths share it).
fn page_result(pg: Int, rc: Int, hdr: &Vec[UInt8], body: &Vec[UInt8], info: &Vec[UInt8]) -> Result[PageOut, Str] {
  if rc < 0 {
    return _err_p(rc_err("pageout", rc));
  }
  let hlen = read_i32_at(info, 0);
  let blen = read_i32_at(info, 4);
  var found = false;
  if rc > 0 {
    found = true;
  }
  var out_header: Vec[UInt8] = Vec[UInt8].new();
  var out_body: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < hlen {
    out_header.push(hdr[i]);
    i = i + 1;
  }
  var j = 0;
  while j < blen {
    out_body.push(body[j]);
    j = j + 1;
  }
  var continued = false;
  var bos = false;
  var eos = false;
  var granule = 0;
  var packets = 0;
  var serialno = read_i32_at(info, 8);
  var pageno = read_i32_at(info, 12);
  if found {
    var a: Int = 0;
    unsafe {
      a = xo_page_continued(pg);
    }
    if a != 0 { continued = true; }
    unsafe {
      a = xo_page_bos(pg);
    }
    if a != 0 { bos = true; }
    unsafe {
      a = xo_page_eos(pg);
    }
    if a != 0 { eos = true; }
    unsafe {
      a = xo_page_granulepos(pg);
    }
    granule = a;
    unsafe {
      a = xo_page_packets(pg);
    }
    packets = a;
  }
  let p = PageOut{
    found: found;
    header: out_header;
    body: out_body;
    serialno: serialno;
    pageno: pageno;
    continued: continued;
    bos: bos;
    eos: eos;
    granulepos: granule;
    packets: packets;
  };
  return _ok_p(p);
}

// ---------------------------------------------------------------------------
// stream layer
// ---------------------------------------------------------------------------

/// Allocate and initialize an ogg_stream_state for `serialno`.
/// Complexity: O(1).
pub fn stream_init(serialno: Int) -> Result[Int, Str] {
  var h: Int = 0;
  unsafe {
    h = xo_stream_init(serialno);
  }
  if h == 0 {
    return _err_i("ogg: stream state allocation failed");
  }
  return _ok_i(h);
}

/// Clear the stream state's internal buffers. Complexity: O(1).
pub fn stream_clear(h: Int) -> Result[Unit, Str] {
  var rc: Int = 0;
  unsafe {
    rc = xo_stream_clear(h);
  }
  if rc != 0 {
    return _err_u(rc_err("stream_clear", rc));
  }
  return _ok_u();
}

/// Reset the stream state (keeps serial). Complexity: O(1).
pub fn stream_reset(h: Int) -> Result[Unit, Str] {
  var rc: Int = 0;
  unsafe {
    rc = xo_stream_reset(h);
  }
  if rc != 0 {
    return _err_u(rc_err("stream_reset", rc));
  }
  return _ok_u();
}

/// Reset the stream state and switch to a new serial.
/// Complexity: O(1).
pub fn stream_reset_serialno(h: Int, serialno: Int) -> Result[Unit, Str] {
  var rc: Int = 0;
  unsafe {
    rc = xo_stream_reset_serialno(h, serialno);
  }
  if rc != 0 {
    return _err_u(rc_err("stream_reset_serialno", rc));
  }
  return _ok_u();
}

/// 0 when the stream state is valid. Complexity: O(1).
pub fn stream_check(h: Int) -> Result[Int, Str] {
  var rc: Int = 0;
  unsafe {
    rc = xo_stream_check(h);
  }
  if rc != 0 {
    return _err_i(rc_err("stream_check", rc));
  }
  return _ok_i(0);
}

/// Nonzero when the stream has seen the end-of-stream flag.
/// Complexity: O(1).
pub fn stream_eos(h: Int) -> Result[Bool, Str] {
  var rc: Int = 0;
  unsafe {
    rc = xo_stream_eos(h);
  }
  if rc < 0 {
    return _err_b(rc_err("stream_eos", rc));
  }
  var v = false;
  if rc != 0 {
    v = true;
  }
  return _ok_b(v);
}

/// Clear and free the stream state handle. Complexity: O(1).
pub fn stream_destroy(h: Int) -> Result[Unit, Str] {
  var rc: Int = 0;
  unsafe {
    rc = xo_stream_destroy(h);
  }
  if rc != 0 {
    return _err_u(rc_err("stream_destroy", rc));
  }
  return _ok_u();
}

/// Submit one page (owned header + body bytes) to the packet reassembler.
/// The bytes are copied into the stream state. Complexity: O(page).
pub fn stream_pagein(h: Int, header: &Vec[UInt8], body: &Vec[UInt8]) -> Result[Unit, Str] {
  var pg: Int = 0;
  unsafe {
    pg = xo_page_create();
  }
  if pg == 0 {
    return _err_u("ogg: page struct allocation failed");
  }
  var rc: Int = 0;
  unsafe {
    rc = xo_page_set(pg, header.as_ptr(), header.len(), body.as_ptr(), body.len());
  }
  if rc != 0 {
    unsafe {
      let ignored = xo_page_free(pg);
    }
    return _err_u(rc_err("page_set", rc));
  }
  var inrc: Int = 0;
  unsafe {
    inrc = xo_stream_pagein(h, pg);
  }
  unsafe {
    let ignored = xo_page_free(pg);
  }
  if inrc != 0 {
    return _err_u(rc_err("stream_pagein", inrc));
  }
  return _ok_u();
}

/// Submit a packet (owned bytes + flags/granulepos) to the muxer stream.
/// The bytes are copied into the stream state. Complexity: O(packet).
pub fn stream_packetin(h: Int, data: &Vec[UInt8], b_o_s: Bool, e_o_s: Bool, granulepos: Int, packetno: Int) -> Result[Unit, Str] {
  var pk: Int = 0;
  unsafe {
    pk = xo_packet_create();
  }
  if pk == 0 {
    return _err_u("ogg: packet struct allocation failed");
  }
  var bosn = 0;
  if b_o_s { bosn = 1; }
  var eosn = 0;
  if e_o_s { eosn = 1; }
  var rc: Int = 0;
  unsafe {
    rc = xo_packet_set(pk, data.as_ptr(), data.len(), bosn, eosn, granulepos, packetno);
  }
  if rc != 0 {
    unsafe {
      let ignored = xo_packet_free(pk);
    }
    return _err_u(rc_err("packet_set", rc));
  }
  var inrc: Int = 0;
  unsafe {
    inrc = xo_stream_packetin(h, pk);
  }
  unsafe {
    let ignored = xo_packet_free(pk);
  }
  if inrc != 0 {
    return _err_u(rc_err("stream_packetin", inrc));
  }
  return _ok_u();
}

/// Submit a packet split across two owned buffers (two-entry scatter-gather
/// shape of ogg_stream_iovecin). Complexity: O(packet).
pub fn stream_iovecin(h: Int, a: &Vec[UInt8], b: &Vec[UInt8], e_o_s: Bool, granulepos: Int) -> Result[Unit, Str] {
  var eosn = 0;
  if e_o_s { eosn = 1; }
  var rc: Int = 0;
  unsafe {
    rc = xo_stream_iovecin(h, a.as_ptr(), a.len(), b.as_ptr(), b.len(), eosn, granulepos);
  }
  if rc != 0 {
    return _err_u(rc_err("stream_iovecin", rc));
  }
  return _ok_u();
}

// Read a packet struct + info slot into a flat PacketOut.
fn packet_result(pk: Int, rc: Int, data: &Vec[UInt8], info: &Vec[UInt8]) -> Result[PacketOut, Str] {
  if rc < 0 {
    return _err_pkt(rc_err("packetout", rc));
  }
  let bytes = read_i32_at(info, 0);
  let bosn = read_i32_at(info, 4);
  let eosn = read_i32_at(info, 8);
  let granule = read_i64_at(info, 16);
  let packetno = read_i64_at(info, 24);
  var found = false;
  if rc > 0 {
    found = true;
  }
  var out_data: Vec[UInt8] = Vec[UInt8].new();
  if found {
    var n = bytes;
    if n > data.len() {
      n = data.len();
    }
    var i = 0;
    while i < n {
      out_data.push(data[i]);
      i = i + 1;
    }
  }
  var b_o_s = false;
  if bosn != 0 { b_o_s = true; }
  var e_o_s = false;
  if eosn != 0 { e_o_s = true; }
  let p = PacketOut{
    found: found;
    data: out_data;
    size: bytes;
    b_o_s: b_o_s;
    e_o_s: e_o_s;
    granulepos: granule;
    packetno: packetno;
  };
  return _ok_pkt(p);
}

/// Pull the next packet out of the reassembled stream; `found` is false
/// when more pages are needed. `cap` limits the copied bytes; `size` reports
/// the full packet size (data.len() < size means truncation).
/// Complexity: O(packet).
pub fn stream_packetout(h: Int, cap: Int) -> Result[PacketOut, Str] {
  var pk: Int = 0;
  unsafe {
    pk = xo_packet_create();
  }
  if pk == 0 {
    return _err_pkt("ogg: packet struct allocation failed");
  }
  var data = buf_zero(cap);
  var info = slot(32);
  var rc: Int = 0;
  unsafe {
    rc = xo_stream_packetout(h, pk, data.as_mut_ptr(), cap, info.as_mut_ptr());
  }
  let out = packet_result(pk, rc, &data, &info);
  unsafe {
    let ignored = xo_packet_free(pk);
  }
  return out;
}

/// Peek the next packet without consuming it. Complexity: O(packet).
pub fn stream_packetpeek(h: Int, cap: Int) -> Result[PacketOut, Str] {
  var pk: Int = 0;
  unsafe {
    pk = xo_packet_create();
  }
  if pk == 0 {
    return _err_pkt("ogg: packet struct allocation failed");
  }
  var data = buf_zero(cap);
  var info = slot(32);
  var rc: Int = 0;
  unsafe {
    rc = xo_stream_packetpeek(h, pk, data.as_mut_ptr(), cap, info.as_mut_ptr());
  }
  let out = packet_result(pk, rc, &data, &info);
  unsafe {
    let ignored = xo_packet_free(pk);
  }
  return out;
}

/// Emit the next page from the muxer stream (upstream pageout thresholds).
/// Complexity: O(page).
pub fn stream_pageout(h: Int) -> Result[PageOut, Str] {
  return stream_page_emit(h, 0, 0);
}

/// pageout with a fill threshold. Complexity: O(page).
pub fn stream_pageout_fill(h: Int, nfill: Int) -> Result[PageOut, Str] {
  return stream_page_emit(h, 1, nfill);
}

/// Flush the muxer stream into a page. Complexity: O(page).
pub fn stream_flush(h: Int) -> Result[PageOut, Str] {
  return stream_page_emit(h, 2, 0);
}

/// flush with a fill threshold. Complexity: O(page).
pub fn stream_flush_fill(h: Int, nfill: Int) -> Result[PageOut, Str] {
  return stream_page_emit(h, 3, nfill);
}

fn stream_page_emit(h: Int, mode: Int, nfill: Int) -> Result[PageOut, Str] {
  var pg: Int = 0;
  unsafe {
    pg = xo_page_create();
  }
  if pg == 0 {
    return _err_p("ogg: page struct allocation failed");
  }
  var hdr = buf_zero(282);
  var body = buf_zero(65536);
  var info = slot(16);
  var rc: Int = 0;
  unsafe {
    if mode == 0 {
      rc = xo_stream_pageout(h, pg, hdr.as_mut_ptr(), 282, body.as_mut_ptr(), 65536, info.as_mut_ptr());
    }
    if mode == 1 {
      rc = xo_stream_pageout_fill(h, nfill, pg, hdr.as_mut_ptr(), 282, body.as_mut_ptr(), 65536, info.as_mut_ptr());
    }
    if mode == 2 {
      rc = xo_stream_flush(h, pg, hdr.as_mut_ptr(), 282, body.as_mut_ptr(), 65536, info.as_mut_ptr());
    }
    if mode == 3 {
      rc = xo_stream_flush_fill(h, nfill, pg, hdr.as_mut_ptr(), 282, body.as_mut_ptr(), 65536, info.as_mut_ptr());
    }
  }
  let out = page_result(pg, rc, &hdr, &body, &info);
  unsafe {
    let ignored = xo_page_free(pg);
  }
  return out;
}

// ---------------------------------------------------------------------------
// page accessors (over owned header/body bytes)
// ---------------------------------------------------------------------------

/// Ogg page structure version (0). Complexity: O(1).
pub fn page_version(header: &Vec[UInt8], body: &Vec[UInt8]) -> Result[Int, Str] {
  let hr = page_handle(header, body);
  if !hr.is_ok {
    return Err(hr.error);
  }
  let pg = hr.value;
  var rc: Int = 0;
  unsafe {
    rc = xo_page_version(pg);
  }
  unsafe {
    let ignored = xo_page_free(pg);
  }
  if rc < 0 {
    return _err_i(rc_err("page_version", rc));
  }
  return _ok_i(rc);
}

/// 1 when the page is a continuation of a packet from the previous page.
/// Complexity: O(1).
pub fn page_continued(header: &Vec[UInt8], body: &Vec[UInt8]) -> Result[Bool, Str] {
  return page_flag(header, body, 0);
}

/// 1 when the page carries the beginning-of-stream flag. Complexity: O(1).
pub fn page_bos(header: &Vec[UInt8], body: &Vec[UInt8]) -> Result[Bool, Str] {
  return page_flag(header, body, 1);
}

/// 1 when the page carries the end-of-stream flag. Complexity: O(1).
pub fn page_eos(header: &Vec[UInt8], body: &Vec[UInt8]) -> Result[Bool, Str] {
  return page_flag(header, body, 2);
}

fn page_flag(header: &Vec[UInt8], body: &Vec[UInt8], which: Int) -> Result[Bool, Str] {
  let hr = page_handle(header, body);
  if !hr.is_ok {
    return Err(hr.error);
  }
  let pg = hr.value;
  var v: Int = 0;
  unsafe {
    if which == 0 {
      v = xo_page_continued(pg);
    }
    if which == 1 {
      v = xo_page_bos(pg);
    }
    if which == 2 {
      v = xo_page_eos(pg);
    }
  }
  unsafe {
    let ignored = xo_page_free(pg);
  }
  if v < 0 {
    return _err_b(rc_err("page flag", v));
  }
  var r = false;
  if v != 0 {
    r = true;
  }
  return _ok_b(r);
}

/// Granule position of the page (upstream ogg_int64_t; the all-ones
/// "no packet finished" value arrives as -1). Complexity: O(1).
pub fn page_granulepos(header: &Vec[UInt8], body: &Vec[UInt8]) -> Result[Int, Str] {
  return page_int(header, body, 0);
}

/// Bitstream serial of the page. Complexity: O(1).
pub fn page_serialno(header: &Vec<UInt8>, body: &Vec[UInt8]) -> Result[Int, Str] {
  return page_int(header, body, 1);
}

/// Page sequence number. Complexity: O(1).
pub fn page_pageno(header: &Vec<UInt8>, body: &Vec<UInt8>) -> Result[Int, Str] {
  return page_int(header, body, 2);
}

/// Number of packets that finish on this page. Complexity: O(1).
pub fn page_packets(header: &Vec<UInt8>, body: &Vec[UInt8]) -> Result[Int, Str] {
  return page_int(header, body, 3);
}

fn page_int(header: &Vec<UInt8>, body: &Vec<UInt8>, which: Int) -> Result[Int, Str] {
  let hr = page_handle(header, body);
  if !hr.is_ok {
    return Err(hr.error);
  }
  let pg = hr.value;
  var v: Int = 0;
  unsafe {
    if which == 0 {
      v = xo_page_granulepos(pg);
    }
    if which == 1 {
      v = xo_page_serialno(pg);
    }
    if which == 2 {
      v = xo_page_pageno(pg);
    }
    if which == 3 {
      v = xo_page_packets(pg);
    }
  }
  unsafe {
    let ignored = xo_page_free(pg);
  }
  if v < 0 {
    return _err_i(rc_err("page int", v));
  }
  return _ok_i(v);
}

/// Recompute and store the page CRC in the owned header bytes (the header
/// Vec must be mutable; the checksum field is patched in place).
/// Complexity: O(page).
pub fn page_checksum_set(header: &mut Vec[UInt8], body: &Vec[UInt8]) -> Result[Unit, Str] {
  var pg: Int = 0;
  unsafe {
    pg = xo_page_create();
  }
  if pg == 0 {
    return _err_u("ogg: page struct allocation failed");
  }
  var rc: Int = 0;
  unsafe {
    rc = xo_page_set(pg, header.as_mut_ptr(), header.len(), body.as_mut_ptr(), body.len());
  }
  if rc != 0 {
    unsafe {
      let ignored = xo_page_free(pg);
    }
    return _err_u(rc_err("page_set", rc));
  }
  var crc: Int = 0;
  unsafe {
    crc = xo_page_checksum_set(pg);
  }
  unsafe {
    let ignored = xo_page_free(pg);
  }
  if crc != 0 {
    return _err_u(rc_err("page_checksum_set", crc));
  }
  return _ok_u();
}

// ---------------------------------------------------------------------------
// packet clear
// ---------------------------------------------------------------------------

/// Clear a packet struct that points at `data`: the XIOM-owned bytes are
/// never freed (the bridge nulls the pointer before calling upstream).
/// Complexity: O(1).
pub fn packet_clear(data: &Vec<UInt8>) -> Result[Unit, Str] {
  var pk: Int = 0;
  unsafe {
    pk = xo_packet_create();
  }
  if pk == 0 {
    return _err_u("ogg: packet struct allocation failed");
  }
  var rc: Int = 0;
  unsafe {
    rc = xo_packet_set(pk, data.as_ptr(), data.len(), 0, 0, 0, 0);
  }
  if rc != 0 {
    unsafe {
      let ignored = xo_packet_free(pk);
    }
    return _err_u(rc_err("packet_set", rc));
  }
  var crc: Int = 0;
  unsafe {
    crc = xo_packet_clear(pk);
  }
  unsafe {
    let ignored = xo_packet_free(pk);
  }
  if crc != 0 {
    return _err_u(rc_err("packet_clear", crc));
  }
  return _ok_u();
}

// ---------------------------------------------------------------------------
// bitpacker (oggpack_buffer)
// ---------------------------------------------------------------------------

/// Allocate and initialize a write bitpacker. Complexity: O(1).
pub fn pack_writeinit() -> Result[Int, Str] {
  var h: Int = 0;
  unsafe {
    h = xo_pack_writeinit();
  }
  if h == 0 {
    return _err_i("ogg: bitpacker allocation failed");
  }
  return _ok_i(h);
}

/// 0 when the bitpacker is healthy. Complexity: O(1).
pub fn pack_writecheck(h: Int) -> Result[Int, Str] {
  var rc: Int = 0;
  unsafe {
    rc = xo_pack_writecheck(h);
  }
  if rc != 0 {
    return _err_i(rc_err("pack_writecheck", rc));
  }
  return _ok_i(0);
}

/// Truncate the written stream to `bits` bits. Complexity: O(1).
pub fn pack_writetrunc(h: Int, bits: Int) -> Result[Unit, Str] {
  var rc: Int = 0;
  unsafe {
    rc = xo_pack_writetrunc(h, bits);
  }
  if rc != 0 {
    return _err_u(rc_err("pack_writetrunc", rc));
  }
  return _ok_u();
}

/// Pad to the next byte boundary. Complexity: O(1).
pub fn pack_writealign(h: Int) -> Result[Unit, Str] {
  var rc: Int = 0;
  unsafe {
    rc = xo_pack_writealign(h);
  }
  if rc != 0 {
    return _err_u(rc_err("pack_writealign", rc));
  }
  return _ok_u();
}

/// Copy `bits` bits from `src` into the bitpacker. Complexity: O(bits).
pub fn pack_writecopy(h: Int, src: &Vec[UInt8], bits: Int) -> Result[Unit, Str] {
  var rc: Int = 0;
  unsafe {
    rc = xo_pack_writecopy(h, src.as_ptr(), bits);
  }
  if rc != 0 {
    return _err_u(rc_err("pack_writecopy", rc));
  }
  return _ok_u();
}

/// Reset the bitpacker to empty (keeps the allocated buffer).
/// Complexity: O(1).
pub fn pack_reset(h: Int) -> Result[Unit, Str] {
  var rc: Int = 0;
  unsafe {
    rc = xo_pack_reset(h);
  }
  if rc != 0 {
    return _err_u(rc_err("pack_reset", rc));
  }
  return _ok_u();
}

/// Free the bitpacker's internal buffer (handle stays usable only after
/// another writeinit/readinit). Complexity: O(1).
pub fn pack_writeclear(h: Int) -> Result[Unit, Str] {
  var rc: Int = 0;
  unsafe {
    rc = xo_pack_writeclear(h);
  }
  if rc != 0 {
    return _err_u(rc_err("pack_writeclear", rc));
  }
  return _ok_u();
}

/// Free the bitpacker handle entirely. Complexity: O(1).
pub fn pack_free(h: Int) -> Result[Unit, Str] {
  var rc: Int = 0;
  unsafe {
    rc = xo_pack_free(h);
  }
  if rc != 0 {
    return _err_u(rc_err("pack_free", rc));
  }
  return _ok_u();
}

/// Initialize the bitpacker for reading from a COPY of `src` (the copy is
/// bridge-owned, so pack_writeclear/pack_free are always safe).
/// Complexity: O(src len).
pub fn pack_readinit(h: Int, src: &Vec[UInt8]) -> Result[Unit, Str] {
  var rc: Int = 0;
  unsafe {
    rc = xo_pack_readinit(h, src.as_ptr(), src.len());
  }
  if rc != 0 {
    return _err_u(rc_err("pack_readinit", rc));
  }
  return _ok_u();
}

/// Write `bits` bits of `value` (LSB-first). Complexity: O(bits).
pub fn pack_write(h: Int, value: Int, bits: Int) -> Result[Unit, Str] {
  var rc: Int = 0;
  unsafe {
    rc = xo_pack_write(h, value, bits);
  }
  if rc != 0 {
    return _err_u(rc_err("pack_write", rc));
  }
  return _ok_u();
}

/// Peek `bits` bits without advancing; -1 when not enough bits remain.
/// Complexity: O(bits).
pub fn pack_look(h: Int, bits: Int) -> Int {
  var rc: Int = 0;
  unsafe {
    rc = xo_pack_look(h, bits);
  }
  return rc;
}

/// Peek one bit; -1 at end of data. Complexity: O(1).
pub fn pack_look1(h: Int) -> Int {
  var rc: Int = 0;
  unsafe {
    rc = xo_pack_look1(h);
  }
  return rc;
}

/// Advance the read cursor by `bits` bits. Complexity: O(1).
pub fn pack_adv(h: Int, bits: Int) -> Result[Unit, Str] {
  var rc: Int = 0;
  unsafe {
    rc = xo_pack_adv(h, bits);
  }
  if rc != 0 {
    return _err_u(rc_err("pack_adv", rc));
  }
  return _ok_u();
}

/// Advance the read cursor by one bit. Complexity: O(1).
pub fn pack_adv1(h: Int) -> Result[Unit, Str] {
  var rc: Int = 0;
  unsafe {
    rc = xo_pack_adv1(h);
  }
  if rc != 0 {
    return _err_u(rc_err("pack_adv1", rc));
  }
  return _ok_u();
}

/// Read `bits` bits (LSB-first); -1 when not enough bits remain.
/// Complexity: O(bits).
pub fn pack_read(h: Int, bits: Int) -> Int {
  var rc: Int = 0;
  unsafe {
    rc = xo_pack_read(h, bits);
  }
  return rc;
}

/// Read one bit; -1 at end of data. Complexity: O(1).
pub fn pack_read1(h: Int) -> Int {
  var rc: Int = 0;
  unsafe {
    rc = xo_pack_read1(h);
  }
  return rc;
}

/// Bytes written (or available for reading). Complexity: O(1).
pub fn pack_bytes(h: Int) -> Int {
  var rc: Int = 0;
  unsafe {
    rc = xo_pack_bytes(h);
  }
  return rc;
}

/// Bits written (or available for reading). Complexity: O(1).
pub fn pack_bits(h: Int) -> Int {
  var rc: Int = 0;
  unsafe {
    rc = xo_pack_bits(h);
  }
  return rc;
}

/// Copy up to `cap` bytes of the internal buffer out; returns the total
/// byte count available. Complexity: O(bytes).
pub fn pack_get_buffer(h: Int, cap: Int) -> Result[Vec[UInt8], Str] {
  var out = buf_zero(cap);
  var rc: Int = 0;
  unsafe {
    rc = xo_pack_get_buffer(h, out.as_mut_ptr(), cap);
  }
  if rc < 0 {
    return _err_bytes(rc_err("pack_get_buffer", rc));
  }
  var n = rc;
  if n > cap {
    n = cap;
  }
  var res: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < n {
    res.push(out[i]);
    i = i + 1;
  }
  return _ok_bytes(res);
}
