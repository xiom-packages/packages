// XVC-C-14 repro, module X -- a metrics-consuming module (the role
// observability.metrics played: it imports xiom.metrics and exposes types
// built from the package Counter).
module repro.tally

use xiom.metrics;

pub type Tally = {
  hits: Counter;
}

pub fn tally_new() -> Tally {
  return Tally{ hits: metric_counter_new() };
}

pub fn tally_hit(t: &mut Tally) {
  metric_counter_inc(&mut t.hits);
}

pub fn tally_hits(t: &Tally) -> Int {
  return metric_counter_value(&t.hits);
}
