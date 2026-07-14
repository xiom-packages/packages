module xiom.vector.storage.id_map

use xiom.core.ids;

// Maps a logical VectorId to its physical location (segment + offset). This
// indirection lets compaction relocate a point between segments without
// changing its stable id. Phase 5 replaces the linear scan with a hash index.

pub type IdMapEntry = {
  vector_id: Int;
  segment: Int;
  offset: Int;
} derive[Clone]

pub type IdMap = {
  entries: Vec[IdMapEntry];
}

pub fn id_map_new() -> IdMap {
  var entries = Vec[IdMapEntry].new();
  return IdMap{ entries: entries };
}

pub fn id_map_put(m: &mut IdMap, vec_id: Int, segment: Int, offset: Int) {
  var i: Int = 0;
  while i < m.entries.len() {
    if m.entries[i].vector_id == vec_id {
      m.entries[i] = IdMapEntry{ vector_id: vec_id, segment: segment, offset: offset };
      return;
    }
    i = i + 1;
  }
  m.entries.push(IdMapEntry{ vector_id: vec_id, segment: segment, offset: offset });
}

pub fn id_map_lookup(m: &IdMap, vec_id: Int) -> Option[IdMapEntry] {
  var i: Int = 0;
  while i < m.entries.len() {
    if m.entries[i].vector_id == vec_id {
      return Some(m.entries[i]);
    }
    i = i + 1;
  }
  return None;
}

pub fn id_map_remove(m: &mut IdMap, vec_id: Int) -> Bool {
  var i: Int = 0;
  while i < m.entries.len() {
    if m.entries[i].vector_id == vec_id {
      var last: Int = m.entries.len() - 1;
      m.entries[i] = m.entries[last];
      m.entries.pop();
      return true;
    }
    i = i + 1;
  }
  return false;
}

pub fn id_map_len(m: &IdMap) -> Int {
  return m.entries.len();
}
