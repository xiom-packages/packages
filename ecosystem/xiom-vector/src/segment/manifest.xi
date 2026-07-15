module xiom.vector.segment.manifest

pub type CollectionId = { value: Int; }
pub type SegmentId = { value: Int; }

fn segment_id_eq(a: &SegmentId, b: &SegmentId) -> Bool {
  return a.value == b.value;
}

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