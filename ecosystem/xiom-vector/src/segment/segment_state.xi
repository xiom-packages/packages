module xiom.vector.segment.segment_state

// Segment lifecycle state machine. A segment is the unit of storage, sealing,
// indexing, and compaction. Legal transitions:
//   Mutable    -> Sealing
//   Sealing    -> Sealed
//   Sealed     -> Indexing
//   Indexing   -> Immutable
//   Immutable  -> Compacting | Dropped
//   Compacting -> Immutable | Dropped
//   Dropped    -> (terminal)

pub enum SegmentStateKind {
  Mutable,
  Sealing,
  Sealed,
  Indexing,
  Immutable,
  Compacting,
  Dropped,
}

// Only a Mutable segment accepts new writes.
pub fn segment_state_is_writable(s: &SegmentStateKind) -> Bool {
  match s {
    Mutable => true,
    Sealing => false,
    Sealed => false,
    Indexing => false,
    Immutable => false,
    Compacting => false,
    Dropped => false,
  }
}

// Dropped is the only terminal state.
pub fn segment_state_is_terminal(s: &SegmentStateKind) -> Bool {
  match s {
    Mutable => false,
    Sealing => false,
    Sealed => false,
    Indexing => false,
    Immutable => false,
    Compacting => false,
    Dropped => true,
  }
}

// Dense ordinal used to express the transition table compactly.
pub fn segment_state_code(s: &SegmentStateKind) -> Int {
  match s {
    Mutable => 0,
    Sealing => 1,
    Sealed => 2,
    Indexing => 3,
    Immutable => 4,
    Compacting => 5,
    Dropped => 6,
  }
}

// Enforces the transition table above. Any transition not listed is illegal.
pub fn segment_state_can_transition(from: &SegmentStateKind, to: &SegmentStateKind) -> Bool {
  var f = segment_state_code(from);
  var t = segment_state_code(to);
  if f == 0 { return t == 1; }
  if f == 1 { return t == 2; }
  if f == 2 { return t == 3; }
  if f == 3 { return t == 4; }
  if f == 4 { return t == 5 || t == 6; }
  if f == 5 { return t == 4 || t == 6; }
  return false;
}
