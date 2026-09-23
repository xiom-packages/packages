module xiom.durable.metrics

// Minimal, allocation-conscious observability primitives shared by every
// subsystem: counters, gauges, histograms, and a registry to hold them.

pub type Counter = {
  name: Str;
  value: Int;
}

pub type Gauge = {
  name: Str;
  value: Int;
}

pub type Histogram = {
  name: Str;
  buckets: Vec[Int];
  counts: Vec[Int];
  total: Int;
}

pub type MetricsRegistry = {
  counters: Vec[Counter];
  gauges: Vec[Gauge];
}

pub fn counter_new(name: Str) -> Counter {
  return Counter{ name: name, value: 0 };
}

pub fn counter_inc(c: &mut Counter) {
  c.value = c.value + 1;
}

pub fn counter_add(c: &mut Counter, delta: Int) {
  c.value = c.value + delta;
}

pub fn gauge_new(name: Str) -> Gauge {
  return Gauge{ name: name, value: 0 };
}

pub fn gauge_set(g: &mut Gauge, value: Int) {
  g.value = value;
}

// bucket_bounds are the inclusive upper edges of each bucket (ascending).
pub fn histogram_new(name: Str, bucket_bounds: Vec[Int]) -> Histogram {
  var counts = Vec[Int].new();
  var i = 0;
  while i < bucket_bounds.len() {
    counts.push(0);
    i = i + 1;
  }
  return Histogram{ name: name, buckets: bucket_bounds, counts: counts, total: 0 };
}

// Record one observation into the first bucket whose upper bound covers it.
// `total` always increments; values above every bound are counted in `total`
// only (an implicit overflow bucket).
pub fn histogram_observe(h: &mut Histogram, value: Int) {
  h.total = h.total + 1;
  var i = 0;
  while i < h.buckets.len() {
    if value <= h.buckets[i] {
      h.counts[i] = h.counts[i] + 1;
      return;
    }
    i = i + 1;
  }
}

pub fn registry_new() -> MetricsRegistry {
  var counters = Vec[Counter].new();
  var gauges = Vec[Gauge].new();
  return MetricsRegistry{ counters: counters, gauges: gauges };
}

pub fn registry_add_counter(r: &mut MetricsRegistry, c: Counter) {
  r.counters.push(c);
}

pub fn registry_add_gauge(r: &mut MetricsRegistry, g: Gauge) {
  r.gauges.push(g);
}
