module xiom.vector.segment.manifest

use xiom.core.ids;

// The manifest is the durable list of a collection's live segments plus the LSN
// at which it was last updated. On recovery the engine replays the WAL up to
// last_lsn and rebuilds in-memory indexes from the listed segments. SCAFFOLD:
// in-memory only until the manifest is persisted through the WAL in Phase 2.

pub type Manifest = {
  collection: CollectionId;
  active_segments: Vec[SegmentId];
  last_lsn: Int;
}

pub fn manifest_new(collection: CollectionId) -> Manifest {
  var segs = Vec[SegmentId].new();
  return Manifest{ collection: collection, active_segments: segs, last_lsn: 0 };
}

pub fn manifest_add_segment(m: &mut Manifest, seg: SegmentId) {
  // TODO(Phase 2): persist a ManifestUpdate WAL record before exposing the
  // segment to readers.
  m.active_segments.push(seg);
}

pub fn manifest_remove_segment(m: &mut Manifest, seg: SegmentId) -> Bool {
  var i: Int = 0;
  while i < m.active_segments.len() {
    if segment_id_eq(&m.active_segments[i], &seg) {
      var last: Int = m.active_segments.len() - 1;
      m.active_segments[i] = m.active_segments[last];
      m.active_segments.pop();
      return true;
    }
    i = i + 1;
  }
  return false;
}

pub fn manifest_set_lsn(m: &mut Manifest, lsn: Int) {
  m.last_lsn = lsn;
}

pub fn manifest_segment_count(m: &Manifest) -> Int {
  return m.active_segments.len();
}
