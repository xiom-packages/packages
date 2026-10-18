// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.segment.segment_file

// Sealed segment file codec (M-D4). A sealed segment is ONE immutable
// collection slice: its vectors, payloads, and (for Hnsw) the graph codec,
// written whole-file + atomically (temp + io.rename) and loaded byte-level
// with a torn-tail-safe prefix. Text format (LF; CRLF accepted on load):
//
//   xvector-segment 1
//   meta <seg_id> <cid> <state_code> <dim> <metric_code> <kind_code> <m> <efc> <efs>
//   v <id> <vector_encode words...>
//   p <id> <payload_encode words...>
//   g <hnsw_encode words...>
//
// Version 2 (Q-a2a, reference study 02; opt-in) appends two sections after
// the graph and is written ONLY when `sealed_segment_enable_sq` armed the
// segment -- a v1 file stays byte-identical otherwise:
//
//   q <vmin words dim> <vstep words dim>     (f32 bit words; trained ranges)
//   c <id> <code words dim>                  (int8 codes 0..255, store order)
//
// On load a v2 file keeps `has_sq` true only when the ranges AND every
// code record of the store order parsed; a torn/partial section is dropped
// (the vectors/payloads/graph prefix survives, exactly like the graph).
//
// Rules: seg_id >= 1, cid >= 1, state in 0..6 -- persist accepts only
// Sealed or Immutable (the engine drives Mutable -> Sealing -> Sealed
// through the real transition table first); dim >= 1; codes are the stable
// metric/kind codes; params valid. The meta line is required. A missing /
// garbage / headerless file is invalid; a truncated or malformed tail
// yields the longest prefix of complete valid records. The graph section is
// best-effort on load (an undecodable graph is dropped -- it is rebuildable
// from the vectors). The file is never handled as a Str (defense in depth,
// the XVC-C-11 family).

use xiom.io;
use xiom.convert;
use xiom.num.float;
use xiom.hash;
use xiom.string.slice;
use xiom.vector.primitives;
use xiom.vector.index.ann_index;
use xiom.vector.index.hnsw;
use xiom.vector.index.quantize;
use xiom.vector.storage.vector_store;
use xiom.vector.payload.payload;
use xiom.vector.segment.segment_state;
use xiom.vector.durability.wal_file;

pub type SealedSegment = {
  valid: Bool;
  seg_id: Int;
  cid: Int;
  state: SegmentStateKind;
  dim: Int;
  metric: DistanceMetric;
  kind: AnnIndexKind;
  m: Int;
  ef_construction: Int;
  ef_search: Int;
  store: VectorIndex;
  payloads: PayloadStore;
  has_graph: Bool;
  graph: HNSWGraph;
  has_sq: Bool;
  sq: SQ8;
  codes: Vec[Int];
  // L-2 integrity footer (`z <count> <crc32>`, optional, always last):
  // loaders tolerate its absence (prefix semantics unchanged); the move
  // path (`engine_attach_segment`) REQUIRES a verified footer so a
  // truncated/corrupt artifact copy cannot attach silently.
  footer_seen: Bool;
  footer_ok: Bool;
  declared_points: Int;
}

pub fn sealed_segment_new(seg_id: Int, cid: Int, dim: Int, metric: DistanceMetric, kind: AnnIndexKind, params: AnnParams) -> SealedSegment
  requires: dim > 0
{
  return SealedSegment{
    valid: false,
    seg_id: seg_id,
    cid: cid,
    state: SegmentStateKind.Mutable,
    dim: dim,
    metric: metric,
    kind: kind,
    m: params.m,
    ef_construction: params.ef_construction,
    ef_search: params.ef_search,
    store: index_new(dim),
    payloads: payload_store_new(),
    has_graph: false,
    graph: hnsw_new(params.m, 4.0),
    has_sq: false,
    sq: SQ8{ dim: dim, vmin: Vec[Float32].new(), vstep: Vec[Float32].new() },
    codes: Vec[Int].new(),
    footer_seen: false,
    footer_ok: false,
    declared_points: 0,
  };
}

// Drive Mutable -> Sealing -> Sealed through the real transition table.
pub fn sealed_segment_seal(ss: &mut SealedSegment) -> Bool {
  if !(ss.state == SegmentStateKind.Mutable) { return false; }
  if !segment_state_can_transition(&ss.state, &SegmentStateKind.Sealing) { return false; }
  ss.state = SegmentStateKind.Sealing;
  if !segment_state_can_transition(&ss.state, &SegmentStateKind.Sealed) { return false; }
  ss.state = SegmentStateKind.Sealed;
  return true;
}

// " " + words + "\n" (linear: appended piecewise into the byte buffer).
fn append_word_list(out: &mut Vec[UInt8], words: &Vec[Int]) {
  var i: Int = 0;
  while i < words.len() {
    append_bytes(out, " ");
    append_bytes(out, convert.int_to_string(words[i]));
    i = i + 1;
  }
  append_bytes(out, "\n");
}

// Opt-in SQ8 section (reference study 02, Q-a2a): train per-dimension
// ranges on the segment's vectors and encode them for the future
// multi-segment read path (D5). False (no change) on an empty store. A
// segment without this stays a byte-identical v1 file.
pub fn sealed_segment_enable_sq(ss: &mut SealedSegment) -> Bool {
  var trained = sq8_train(&ss.store.vectors);
  var got: Bool = false;
  match trained {
    Some(s) => {
      ss.sq = s;
      ss.codes = sq8_encode_store(&ss.store, &ss.sq);
      got = ss.codes.len() == ss.store.ids.len() * ss.dim && ss.store.ids.len() > 0;
    }
    None => {}
  }
  ss.has_sq = got;
  if !got { ss.codes = Vec[Int].new(); }
  return got;
}

// Whole-file atomic write: `<path>.tmp` then io.rename. False (target
// untouched) when the meta is out of range, the state is not Sealed /
// Immutable, or on any IO error. Header version 2 only when the SQ section
// is armed (v1 output otherwise, byte-identical to the pre-Q-a2a codec).
pub fn segment_file_persist(ss: &SealedSegment, path: Str) -> Bool {
  if ss.seg_id < 1 || ss.cid < 1 { return false; }
  if ss.dim < 1 { return false; }
  var sc = segment_state_code(&ss.state);
  if sc != 2 && sc != 4 { return false; }
  var p = AnnParams{ m: ss.m, ef_construction: ss.ef_construction, ef_search: ss.ef_search };
  if !ann_params_valid(&p) { return false; }
  var out = Vec[UInt8].new();
  if ss.has_sq {
    append_bytes(&mut out, "xvector-segment 2\n");
  } else {
    append_bytes(&mut out, "xvector-segment 1\n");
  }
  append_bytes(&mut out, "meta");
  append_bytes(&mut out, " ");
  append_bytes(&mut out, convert.int_to_string(ss.seg_id));
  append_bytes(&mut out, " ");
  append_bytes(&mut out, convert.int_to_string(ss.cid));
  append_bytes(&mut out, " ");
  append_bytes(&mut out, convert.int_to_string(sc));
  append_bytes(&mut out, " ");
  append_bytes(&mut out, convert.int_to_string(ss.dim));
  append_bytes(&mut out, " ");
  append_bytes(&mut out, convert.int_to_string(metric_code(ss.metric)));
  append_bytes(&mut out, " ");
  append_bytes(&mut out, convert.int_to_string(ann_kind_code(ss.kind)));
  append_bytes(&mut out, " ");
  append_bytes(&mut out, convert.int_to_string(ss.m));
  append_bytes(&mut out, " ");
  append_bytes(&mut out, convert.int_to_string(ss.ef_construction));
  append_bytes(&mut out, " ");
  append_bytes(&mut out, convert.int_to_string(ss.ef_search));
  append_bytes(&mut out, "\n");
  var i: Int = 0;
  while i < ss.store.ids.len() {
    var wid = vector_encode(&ss.store.vectors[i]);
    append_bytes(&mut out, "v");
    append_bytes(&mut out, " ");
    append_bytes(&mut out, convert.int_to_string(ss.store.ids[i]));
    append_word_list(&mut out, wid);
    i = i + 1;
  }
  var pi: Int = 0;
  while pi < ss.payloads.entries.len() {
    var pwords = payload_encode(&ss.payloads.entries[pi].payload);
    append_bytes(&mut out, "p");
    append_bytes(&mut out, " ");
    append_bytes(&mut out, convert.int_to_string(ss.payloads.entries[pi].id));
    append_word_list(&mut out, pwords);
    pi = pi + 1;
  }
  if ss.kind == AnnIndexKind.Hnsw && ss.has_graph {
    var gwords = hnsw_encode(&ss.graph);
    append_bytes(&mut out, "g");
    append_word_list(&mut out, gwords);
  }
  if ss.has_sq && ss.sq.dim == ss.dim && ss.codes.len() == ss.store.ids.len() * ss.dim && ss.store.ids.len() > 0 {
    var qw = Vec[Int].new();
    var d: Int = 0;
    while d < ss.sq.dim {
      qw.push(float.float_bits(ss.sq.vmin[d] as Float64));
      d = d + 1;
    }
    d = 0;
    while d < ss.sq.dim {
      qw.push(float.float_bits(ss.sq.vstep[d] as Float64));
      d = d + 1;
    }
    append_bytes(&mut out, "q");
    append_word_list(&mut out, qw);
    var ci: Int = 0;
    while ci < ss.store.ids.len() {
      append_bytes(&mut out, "c");
      append_bytes(&mut out, " ");
      append_bytes(&mut out, convert.int_to_string(ss.store.ids[ci]));
      var cw = Vec[Int].new();
      d = 0;
      while d < ss.sq.dim {
        cw.push(ss.codes[ci * ss.sq.dim + d]);
        d = d + 1;
      }
      append_word_list(&mut out, cw);
      ci = ci + 1;
    }
  }
  // Integrity footer (L-2 move artifacts): declared point count + a crc32
  // over the content bytes BEFORE the footer. Optional to old loaders;
  // attach requires it (and verifies both).
  var foot_crc = hash.crc32_ieee(&out);
  append_bytes(&mut out, "z ");
  append_bytes(&mut out, convert.int_to_string(ss.store.ids.len()));
  append_bytes(&mut out, " ");
  append_bytes(&mut out, convert.int_to_string(foot_crc));
  append_bytes(&mut out, "\n");
  var tmp = path + ".tmp";
  var wres = io.write_file_bytes(tmp, &out);
  match wres {
    Ok(_) => {}
    Err(_) => { return false; }
  }
  var rres = io.rename(tmp, path);
  match rres {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}

// One parsed word run: ok=false on a torn/malformed line; pos = after '\n'.
pub type ParsedWords = {
  ok: Bool;
  words: Vec[Int];
  pos: Int;
}

// Parse space-separated ints up to (and including) the end of the line.
fn parse_words_until_newline(b: &Vec[UInt8], start: Int) -> ParsedWords {
  var out = ParsedWords{ ok: false, words: Vec[Int].new(), pos: start };
  var p: Int = start;
  while true {
    if p >= b.len() { return out; }
    if b[p] == 13 { p = p + 1; }
    if p >= b.len() { return out; }
    if b[p] == 10 {
      out.ok = true;
      out.pos = p + 1;
      return out;
    }
    var r = parse_int_at(b, p);
    if !r.ok { return out; }
    out.words.push(r.value);
    p = r.pos;
    if p < b.len() && b[p] == 32 { p = p + 1; }
  }
}

// Load a sealed segment. valid=true requires the header AND the meta line;
// vector/payload records accumulate as a complete-record prefix; the graph
// is optional (undecodable -> dropped).
pub fn segment_file_load(path: Str) -> SealedSegment {
  var ss = SealedSegment{
    valid: false,
    seg_id: 0,
    cid: 0,
    state: SegmentStateKind.Mutable,
    dim: 0,
    metric: DistanceMetric.Euclidean,
    kind: AnnIndexKind.Flat,
    m: 0,
    ef_construction: 0,
    ef_search: 0,
    store: index_new(1),
    payloads: payload_store_new(),
    has_graph: false,
    graph: hnsw_new(1, 4.0),
    has_sq: false,
    sq: SQ8{ dim: 1, vmin: Vec[Float32].new(), vstep: Vec[Float32].new() },
    codes: Vec[Int].new(),
    footer_seen: false,
    footer_ok: false,
    declared_points: 0,
  };
  if !io.file_exists(path) { return ss; }
  var fsz = io.file_size(path);
  var sz: Int = -1;
  match fsz {
    Some(n) => { sz = n; }
    None => { return ss; }
  }
  // Shortest valid segment: header (18) + minimum meta line (23).
  if sz < 41 { return ss; }
  var rb = io.read_file_bytes(path);
  var b = Vec[UInt8].new();
  match rb {
    Ok(x) => { b = x; }
    Err(_) => { return ss; }
  }
  var hdr = slice.str_bytes("xvector-segment ");
  if b.len() < hdr.len() + 2 { return ss; }
  var hi: Int = 0;
  while hi < hdr.len() {
    if b[hi] != hdr[hi] { return ss; }
    hi = hi + 1;
  }
  var ver: Int = 0;
  if b[hi] == 49 { ver = 1; }
  else if b[hi] == 50 { ver = 2; }
  else { return ss; }
  var pos: Int = hi + 1;
  if pos < b.len() && b[pos] == 13 { pos = pos + 1; }
  if pos >= b.len() || b[pos] != 10 { return ss; }
  pos = pos + 1;
  var meta_done: Bool = false;
  var stop: Bool = false;
  var sq_ranges: Bool = false;
  var codes_done: Int = 0;
  var footer_pos: Int = -1;
  var footer_crc: Int = 0;
  while pos < b.len() && !stop {
    var tag = b[pos];
    if tag == 109 {
      // meta <seg_id> <cid> <state> <dim> <mc> <kc> <m> <efc> <efs>
      if meta_done { stop = true; }
      else if pos + 5 > b.len() { stop = true; }
      else if b[pos + 1] != 101 || b[pos + 2] != 116 || b[pos + 3] != 97 || b[pos + 4] != 32 { stop = true; }
      else {
        var p: Int = pos + 5;
        var vals = Vec[Int].new();
        var bad2: Bool = false;
        var fi: Int = 0;
        while fi < 9 && !bad2 {
          var r = parse_int_at(b, p);
          if !r.ok {
            bad2 = true;
          } else {
            vals.push(r.value);
            p = r.pos;
            if fi < 8 {
              if p < b.len() && b[p] == 32 { p = p + 1; }
              else { bad2 = true; }
            }
          }
          fi = fi + 1;
        }
        if !bad2 {
          if p < b.len() && b[p] == 13 { p = p + 1; }
          if p < b.len() && b[p] == 10 { p = p + 1; }
          else { bad2 = true; }
        }
        var sid: Int = 0;
        var cid: Int = 0;
        var stc: Int = 0;
        var dm: Int = 0;
        var mc: Int = 0;
        var kc: Int = 0;
        if !bad2 {
          sid = vals[0];
          cid = vals[1];
          stc = vals[2];
          dm = vals[3];
          mc = vals[4];
          kc = vals[5];
          if sid < 1 || cid < 1 || stc < 0 || stc > 6 || dm < 1 || mc < 1 || mc > 3 || kc < 1 || kc > 3 {
            bad2 = true;
          }
        }
        var p2 = AnnParams{ m: 0, ef_construction: 0, ef_search: 0 };
        if !bad2 {
          p2.m = vals[6];
          p2.ef_construction = vals[7];
          p2.ef_search = vals[8];
          if !ann_params_valid(&p2) { bad2 = true; }
        }
        if bad2 {
          stop = true;
        } else {
          ss.seg_id = sid;
          ss.cid = cid;
          ss.state = segment_state_from_code(stc);
          ss.dim = dm;
          ss.metric = metric_from_code(mc);
          ss.kind = ann_kind_from_code(kc);
          ss.m = p2.m;
          ss.ef_construction = p2.ef_construction;
          ss.ef_search = p2.ef_search;
          ss.store = index_new(dm);
          ss.payloads = payload_store_new();
          ss.graph = hnsw_new(p2.m, 4.0);
          ss.has_graph = false;
          ss.valid = true;
          meta_done = true;
          pos = p;
        }
      }
    } elif tag == 118 {
      // v <id> <vector words...>
      if !meta_done || pos + 2 > b.len() || b[pos + 1] != 32 {
        stop = true;
      } else {
        var rid = parse_int_at(b, pos + 2);
        if !rid.ok {
          stop = true;
        } else {
          var vid = rid.value;
          var p3: Int = rid.pos;
          if p3 < b.len() && b[p3] == 32 { p3 = p3 + 1; } else { stop = true; }
          var pw = parse_words_until_newline(b, p3);
          if !pw.ok {
            stop = true;
          } else if vid < 0 {
            stop = true;
          } else {
            match vector_decode(&pw.words) {
              Some(v) => {
                if v.dimension != ss.dim {
                  stop = true;
                } else {
                  index_add(&mut ss.store, vid, v);
                  pos = pw.pos;
                }
              }
              None => { stop = true; }
            }
          }
        }
      }
    } elif tag == 112 {
      // p <id> <payload words...>
      if !meta_done || pos + 2 > b.len() || b[pos + 1] != 32 {
        stop = true;
      } else {
        var rid2 = parse_int_at(b, pos + 2);
        if !rid2.ok {
          stop = true;
        } else {
          var pid = rid2.value;
          var p4: Int = rid2.pos;
          if p4 < b.len() && b[p4] == 32 { p4 = p4 + 1; } else { stop = true; }
          var pw2 = parse_words_until_newline(b, p4);
          if !pw2.ok || pid < 0 {
            stop = true;
          } else {
            match payload_decode(&pw2.words) {
              Some(pl) => {
                payload_store_put(&mut ss.payloads, pid, pl);
                pos = pw2.pos;
              }
              None => { stop = true; }
            }
          }
        }
      }
    } elif tag == 103 {
      // g <hnsw words...> (optional, best-effort decode)
      if !meta_done || pos + 1 > b.len() {
        stop = true;
      } else {
        var p5: Int = pos + 1;
        if p5 < b.len() && b[p5] == 32 { p5 = p5 + 1; }
        var pw3 = parse_words_until_newline(b, p5);
        if !pw3.ok {
          stop = true;
        } else {
          match hnsw_decode(&pw3.words) {
            Some(g) => {
              ss.graph = g;
              ss.has_graph = true;
            }
            None => {
              ss.has_graph = false;
            }
          }
          pos = pw3.pos;
        }
      }
    } elif tag == 113 {
      // q <vmin words dim> <vstep words dim> (v2 only; f32 bit words)
      if !meta_done || ver != 2 || sq_ranges || pos + 1 > b.len() {
        stop = true;
      } else {
        var p6: Int = pos + 1;
        if p6 < b.len() && b[p6] == 32 { p6 = p6 + 1; }
        var pw4 = parse_words_until_newline(b, p6);
        if !pw4.ok || pw4.words.len() != ss.dim * 2 {
          stop = true;
        } else {
          var vmin2 = Vec[Float32].new();
          var vstep2 = Vec[Float32].new();
          var okq: Bool = true;
          var dq: Int = 0;
          while dq < ss.dim {
            var vm = float.bits_to_float(pw4.words[dq]) as Float32;
            var vs = float.bits_to_float(pw4.words[ss.dim + dq]) as Float32;
            if !(vs >= 0.0) { okq = false; }
            vmin2.push(vm);
            vstep2.push(vs);
            dq = dq + 1;
          }
          if !okq {
            stop = true;
          } else {
            ss.sq = SQ8{ dim: ss.dim, vmin: vmin2, vstep: vstep2 };
            sq_ranges = true;
            pos = pw4.pos;
          }
        }
      }
    } elif tag == 99 {
      // c <id> <code words dim> (v2 only; store order; codes 0..255)
      if !meta_done || ver != 2 || !sq_ranges || codes_done >= ss.store.ids.len() {
        stop = true;
      } else {
        var rid3 = parse_int_at(b, pos + 2);
        if !rid3.ok {
          stop = true;
        } else {
          var cidw = rid3.value;
          var p7: Int = rid3.pos;
          if p7 < b.len() && b[p7] == 32 { p7 = p7 + 1; } else { stop = true; }
          var pw5 = parse_words_until_newline(b, p7);
          if !pw5.ok || pw5.words.len() != ss.dim {
            stop = true;
          } else if cidw != ss.store.ids[codes_done] {
            stop = true;
          } else {
            var okc: Bool = true;
            var dc: Int = 0;
            while dc < ss.dim {
              var cc = pw5.words[dc];
              if cc < 0 || cc > 255 { okc = false; }
              ss.codes.push(cc);
              dc = dc + 1;
            }
            if !okc {
              stop = true;
            } else {
              codes_done = codes_done + 1;
              pos = pw5.pos;
            }
          }
        }
      }
    } elif tag == 122 {
      // z <count> <crc32> (optional integrity footer; last record only)
      if !meta_done || footer_pos >= 0 {
        stop = true;
      } else {
        var rz = parse_int_at(b, pos + 2);
        if !rz.ok {
          stop = true;
        } else {
          var cz = parse_int_at(b, rz.pos + 1);
          if !cz.ok {
            stop = true;
          } else {
            var pz: Int = cz.pos;
            if pz < b.len() && b[pz] == 13 { pz = pz + 1; }
            if pz < b.len() && b[pz] == 10 { pz = pz + 1; } else { stop = true; }
            if !stop {
              ss.footer_seen = true;
              ss.declared_points = rz.value;
              footer_crc = cz.value;
              footer_pos = pos;
              pos = pz;
            }
          }
        }
      }
    } else {
      stop = true;
    }
  }
  if sq_ranges && ver == 2 && codes_done == ss.store.ids.len() && codes_done > 0 {
    ss.has_sq = true;
  } else {
    ss.has_sq = false;
    ss.codes = Vec[Int].new();
  }
  // Footer verification: crc over everything before the footer line and
  // the declared point count must both match; footer_ok gates attach.
  if footer_pos >= 0 {
    var pre = Vec[UInt8].new();
    var pf: Int = 0;
    while pf < footer_pos {
      pre.push(b[pf]);
      pf = pf + 1;
    }
    if hash.crc32_ieee(&pre) == footer_crc && ss.declared_points == ss.store.ids.len() {
      ss.footer_ok = true;
    }
  }
  return ss;
}
