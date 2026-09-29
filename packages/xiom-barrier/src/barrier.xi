// XIOM -- xiom.barrier: reusable multiparty barrier as a deterministic state machine
// Port task: replace the xiom.barrier placeholder with a real, tested,
// pure-XIOM package (no FFI, no threads, no clock).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: a reusable multiparty barrier as a pure, deterministic state
// machine -- the semantic core that a thread scheduler, atomics backend or
// blocking runtime would drive. There are no threads, no atomics, no clock
// and no I/O here: the caller (or a future backend) owns the concurrency and
// every function is a total transition over plain values.
//
// Semantics: a barrier is parameterized by `parties` (N >= 1) and advances
// one generation per completed rendezvous. barrier_arrive records one party's
// arrival in the current generation and reports whether that arrival tripped
// the barrier (N arrivals) and whether the caller is the leader (the last
// arriver). A trip increments the generation, clears the arrival set and
// releases all N waiters; the per-arrival generation records pin every waiter
// to the generation it joined, and the sense-reversal flag flips on every
// trip so a waiter can distinguish "my generation completed" from "a new
// generation has begun". barrier_reset restores the initial state and is
// refused while parties are mid-generation.
//
// Every error string is stable and prefixed `barrier: `; every error leaves
// the state completely unchanged.
//
// Language notes (XIOM v0.62.1): free functions only; Ok/Err are constructed
// only inside the _ok_*/_err_* leaf helpers; Vec[Int] element reads are bound
// with a typed `let`; no Vec[StructType], no FFI, no threads, no `log`-named
// function. `arrivals` and `arrival_gens` are parallel Vec[Int] fields kept
// mirrored by every mutation.

module xiom.barrier

use xiom.string;
use xiom.convert;

/// Reusable multiparty barrier state. Every field is an internal
/// implementation detail; callers must go through the barrier_* free
/// functions.
///
/// `parties` is the required arrivals per generation (fixed at construction,
/// >= 1). `generation` is the current generation index (0-based, one
/// increment per completed trip; it equals `trips` at all times).
/// `sense` is the sense-reversal flag (0 or 1), flipped by every trip so
/// waiters can tell a completed generation from the next one. `arrivals`
/// holds the party IDs that have arrived in the current generation, in
/// arrival order (index 0 = first arriver) and `arrival_gens` the parallel
/// Vec recording the generation each arrival joined. `arrivals_total` counts
/// successful barrier_arrive calls, `trips` counts completed generations and
/// `released` counts waiters released by trips (always `trips * parties`).
/// `last_trip_generation`, `last_trip_leader` and `last_trip_parties` are the
/// last-trip metadata: the generation index that tripped last (-1 before the
/// first trip), the ID of its last arriver (-1 before the first trip) and
/// the IDs released by it in arrival order (empty before the first trip).
pub type Barrier = {
  parties: Int;
  generation: Int;
  sense: Int;
  arrivals: Vec[Int];
  arrival_gens: Vec[Int];
  arrivals_total: Int;
  trips: Int;
  released: Int;
  last_trip_generation: Int;
  last_trip_leader: Int;
  last_trip_parties: Vec[Int];
}

/// Outcome of one barrier_arrive call. `tripped` is true when this arrival
/// completed the generation; `leader` is true for the last arriver (the trip
/// leader), which in this model is exactly the tripping arrival. `position`
/// is the 0-based arrival position in the generation that was joined (N-1
/// for the leader). `generation` is the generation index the arrival joined
/// and `sense` is the sense flag observed after the call (flipped when the
/// call tripped).
pub type BarrierArrival = {
  tripped: Bool;
  leader: Bool;
  position: Int;
  generation: Int;
  sense: Int;
}

// ---------------------------------------------------------------------------
// Result constructors (leaf helpers only; see the header comment)
// ---------------------------------------------------------------------------

fn _ok_barrier(v: Barrier) -> Result[Barrier, Str] { return Ok(v); }
fn _err_barrier(m: Str) -> Result[Barrier, Str] { return Err(m); }
fn _ok_arrival(v: BarrierArrival) -> Result[BarrierArrival, Str] { return Ok(v); }
fn _err_arrival(m: Str) -> Result[BarrierArrival, Str] { return Err(m); }
fn _ok_reset(v: Int) -> Result[Int, Str] { return Ok(v); }
fn _err_reset(m: Str) -> Result[Int, Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

// True when `id` has already arrived in the current generation.
fn _arrivals_have(b: &Barrier, id: Int) -> Bool {
  var i = 0;
  while i < b.arrivals.len() {
    let queued: Int = b.arrivals[i];
    if queued == id { return true; }
    i = i + 1;
  }
  return false;
}

// Trip the barrier: snapshot the participants, publish the last-trip
// metadata, release every waiter, flip the sense, advance the generation and
// clear the arrival set. `leader` is the trip-causing last arriver and `gen`
// the generation index that completed. Returns the leader's outcome.
fn _trip(b: &mut Barrier, leader: Int, gen: Int) -> BarrierArrival {
  var parts = Vec[Int].new();
  var i = 0;
  while i < b.arrivals.len() {
    let who: Int = b.arrivals[i];
    parts.push(who);
    i = i + 1;
  }
  b.last_trip_parties = parts;
  b.last_trip_generation = gen;
  b.last_trip_leader = leader;
  b.trips = b.trips + 1;
  b.released = b.released + b.parties;
  b.sense = 1 - b.sense;
  b.generation = gen + 1;
  b.arrivals = Vec[Int].new();
  b.arrival_gens = Vec[Int].new();
  let new_sense: Int = b.sense;
  return BarrierArrival{
    tripped: true;
    leader: true;
    position: b.parties - 1;
    generation: gen;
    sense: new_sense;
  };
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

/// Create a barrier that trips after `parties` distinct arrivals.
/// Params: parties - required arrivals per generation, must be >= 1.
/// Returns: Ok(Barrier) in generation 0 with sense 0, no arrivals and zero
/// stats; Err("barrier: parties must be >= 1") otherwise.
/// Complexity: O(1).
pub fn barrier_new(parties: Int) -> Result[Barrier, Str] {
  if parties < 1 {
    return _err_barrier("barrier: parties must be >= 1");
  }
  return _ok_barrier(Barrier{
    parties: parties;
    generation: 0;
    sense: 0;
    arrivals: Vec[Int].new();
    arrival_gens: Vec[Int].new();
    arrivals_total: 0;
    trips: 0;
    released: 0;
    last_trip_generation: -1;
    last_trip_leader: -1;
    last_trip_parties: Vec[Int].new();
  });
}

// ---------------------------------------------------------------------------
// Arrival
// ---------------------------------------------------------------------------

/// Record the arrival of party `id` in the current generation.
///
/// The arrival joins the wait set, pinned to the generation it joined; when
/// it is the Nth distinct arrival the barrier trips: the generation
/// increments, the arrival set is cleared, all N waiters are released, the
/// sense flag flips and the last-trip metadata is published. The tripping
/// arrival is the leader.
/// Params: b - the barrier; id - caller-assigned party ID, >= 0, unique
///         within the current generation (reusable in later generations).
/// Returns: Ok(BarrierArrival) with the arrival outcome; Err("barrier:
/// parties must be >= 1") when the barrier's party count is unknown/zero,
/// Err("barrier: party id must be >= 0") for a negative ID, or Err("barrier:
/// duplicate party id in generation") when `id` already arrived in this
/// generation -- in every Err case the state is unchanged (counters too).
/// A successful arrival increments the arrivals_total counter.
/// Complexity: O(arrivals) (duplicate scan); O(arrivals + parties) on a trip.
pub fn barrier_arrive(b: &mut Barrier, id: Int) -> Result[BarrierArrival, Str] {
  if b.parties < 1 {
    return _err_arrival("barrier: parties must be >= 1");
  }
  if id < 0 {
    return _err_arrival("barrier: party id must be >= 0");
  }
  if _arrivals_have(b, id) {
    return _err_arrival("barrier: duplicate party id in generation");
  }
  let gen: Int = b.generation;
  b.arrivals.push(id);
  b.arrival_gens.push(gen);
  b.arrivals_total = b.arrivals_total + 1;
  let count: Int = b.arrivals.len();
  if count == b.parties {
    return _ok_arrival(_trip(b, id, gen));
  }
  return _ok_arrival(BarrierArrival{
    tripped: false;
    leader: false;
    position: count - 1;
    generation: gen;
    sense: b.sense;
  });
}

// ---------------------------------------------------------------------------
// Reset
// ---------------------------------------------------------------------------

/// Restore the barrier to its freshly-constructed state (parties preserved,
/// generation 0, sense 0, empty arrival set, cleared last-trip metadata,
/// zero stats).
/// An explicit reset is only meaningful between rendezvous: it is refused
/// while parties are mid-generation (the arrival set is non-empty), so a
/// reset can never strand a waiter or silently drop arrivals.
/// Params: b - the barrier.
/// Returns: Ok(0) -- the generation after the reset -- or Err("barrier:
/// cannot reset mid-generation") when arrivals.len() > 0 (state unchanged).
/// Complexity: O(1).
pub fn barrier_reset(b: &mut Barrier) -> Result[Int, Str] {
  if b.arrivals.len() > 0 {
    return _err_reset("barrier: cannot reset mid-generation");
  }
  b.generation = 0;
  b.sense = 0;
  b.arrivals = Vec[Int].new();
  b.arrival_gens = Vec[Int].new();
  b.arrivals_total = 0;
  b.trips = 0;
  b.released = 0;
  b.last_trip_generation = -1;
  b.last_trip_leader = -1;
  b.last_trip_parties = Vec[Int].new();
  return _ok_reset(0);
}

// ---------------------------------------------------------------------------
// Sense-reversal probe
// ---------------------------------------------------------------------------

/// True when a waiter that joined generation `generation` has been released,
/// i.e. the barrier has advanced past it. This is the deterministic form of
/// the sense-reversal test: a waiter records the generation (and therefore
/// the sense) it arrived in and is released exactly when the generation
/// counter moves on -- never by re-reading a reused count.
/// Params: b - the barrier; generation - the recorded generation index.
/// Returns: b.generation > generation (a negative generation is always in
/// the past, so it returns true).
/// Complexity: O(1).
pub fn barrier_waiter_released(b: &Barrier, generation: Int) -> Bool {
  return b.generation > generation;
}

// ---------------------------------------------------------------------------
// Accessors (read-only)
// ---------------------------------------------------------------------------

/// Required arrivals per generation (fixed at construction). O(1).
pub fn barrier_parties(b: &Barrier) -> Int {
  return b.parties;
}

/// Current generation index (0-based; equals the trip count). O(1).
pub fn barrier_generation(b: &Barrier) -> Int {
  return b.generation;
}

/// Sense-reversal flag (0 or 1), flipped by every trip. O(1).
pub fn barrier_sense(b: &Barrier) -> Int {
  return b.sense;
}

/// Number of parties that have arrived in the current generation. O(1).
pub fn barrier_arrived_count(b: &Barrier) -> Int {
  return b.arrivals.len();
}

/// Party ID at arrival position `index` in the current generation, or -1
/// when out of range. O(1).
pub fn barrier_arrived_id_at(b: &Barrier, index: Int) -> Int {
  if index < 0 { return -1; }
  if index >= b.arrivals.len() { return -1; }
  let id: Int = b.arrivals[index];
  return id;
}

/// Recorded generation of the arrival at position `index`, or -1 when out of
/// range. O(1).
pub fn barrier_arrived_gen_at(b: &Barrier, index: Int) -> Int {
  if index < 0 { return -1; }
  if index >= b.arrival_gens.len() { return -1; }
  let gen: Int = b.arrival_gens[index];
  return gen;
}

/// Copy of the pending party IDs, in arrival order (index 0 = first
/// arriver). O(arrivals).
pub fn barrier_arrived_ids(b: &Barrier) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < b.arrivals.len() {
    let id: Int = b.arrivals[i];
    out.push(id);
    i = i + 1;
  }
  return out;
}

/// Wait-queue trace: the pending waiters as `id@generation` pairs in arrival
/// order, comma-separated; "" when the arrival set is empty. Since arrivals
/// are cleared on every trip, every rendered generation is the current one
/// -- the trace exists to show, for tests and debugging, exactly which
/// parties are still waiting and which generation pins them.
/// Complexity: O(arrivals).
pub fn barrier_wait_trace(b: &Barrier) -> Str {
  var out = "";
  var i = 0;
  while i < b.arrivals.len() {
    let id: Int = b.arrivals[i];
    let gen: Int = b.arrival_gens[i];
    if i > 0 { out = out + ","; }
    out = out + convert.int_to_string(id);
    out = out + "@";
    out = out + convert.int_to_string(gen);
    i = i + 1;
  }
  return out;
}

/// Successful barrier_arrive calls since construction or the last reset.
/// O(1).
pub fn barrier_arrivals_total(b: &Barrier) -> Int {
  return b.arrivals_total;
}

/// Completed generations (trips) since construction or the last reset.
/// O(1).
pub fn barrier_trip_count(b: &Barrier) -> Int {
  return b.trips;
}

/// Waiters released by trips (always trips * parties). O(1).
pub fn barrier_released_count(b: &Barrier) -> Int {
  return b.released;
}

/// Generation index that tripped last, or -1 before the first trip. O(1).
pub fn barrier_last_trip_generation(b: &Barrier) -> Int {
  return b.last_trip_generation;
}

/// ID of the last arriver of the most recent trip, or -1 before the first
/// trip. O(1).
pub fn barrier_last_trip_leader(b: &Barrier) -> Int {
  return b.last_trip_leader;
}

/// Copy of the party IDs released by the most recent trip, in arrival order
/// (leader last); empty before the first trip. O(parties).
pub fn barrier_last_trip_parties(b: &Barrier) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < b.last_trip_parties.len() {
    let id: Int = b.last_trip_parties[i];
    out.push(id);
    i = i + 1;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Invariant check
// ---------------------------------------------------------------------------

/// Structural invariant of a barrier:
/// parties >= 1; generation >= 0 and equal to trips; sense is exactly
/// trips % 2; `arrivals` and `arrival_gens` have equal length, arrivals.len()
/// < parties, every pending ID is >= 0 and unique, and every recorded
/// generation is the current one; released == trips * parties;
/// arrivals_total == trips * parties + arrivals.len(); before the first trip
/// the last-trip metadata is at its -1/empty sentinels, and afterwards it
/// describes generation trips - 1 with exactly `parties` participants and a
/// non-negative leader.
/// Complexity: O(arrivals^2) (pairwise ID uniqueness).
pub fn barrier_check_invariant(b: &Barrier) -> Bool {
  if b.parties < 1 { return false; }
  if b.generation < 0 { return false; }
  if b.generation != b.trips { return false; }
  if b.sense != 0 && b.sense != 1 { return false; }
  if b.sense != b.trips % 2 { return false; }
  if b.arrivals.len() != b.arrival_gens.len() { return false; }
  if b.arrivals.len() >= b.parties { return false; }
  if b.released != b.trips * b.parties { return false; }
  if b.arrivals_total != b.trips * b.parties + b.arrivals.len() { return false; }
  if b.trips == 0 {
    if b.last_trip_generation != -1 { return false; }
    if b.last_trip_leader != -1 { return false; }
    if b.last_trip_parties.len() != 0 { return false; }
  } else {
    if b.last_trip_generation != b.trips - 1 { return false; }
    if b.last_trip_leader < 0 { return false; }
    if b.last_trip_parties.len() != b.parties { return false; }
  }
  var i = 0;
  while i < b.arrivals.len() {
    let id: Int = b.arrivals[i];
    let gen: Int = b.arrival_gens[i];
    if id < 0 { return false; }
    if gen != b.generation { return false; }
    var j = i + 1;
    while j < b.arrivals.len() {
      let other: Int = b.arrivals[j];
      if other == id { return false; }
      j = j + 1;
    }
    i = i + 1;
  }
  return true;
}
