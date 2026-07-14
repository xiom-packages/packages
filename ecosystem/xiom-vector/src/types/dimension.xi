module xiom.vector.types.dimension

use xiom.core.contracts;
use xiom.core.limits;

// Strongly-typed vector dimensionality. Wrapping the raw Int prevents mixing a
// dimension with an arbitrary count and gives one place to enforce the engine
// ceiling (xiom.core.limits.max_dimensions).

pub type Dimension = { value: Int; } derive[Clone, Eq]

pub fn dimension(v: Int) -> Dimension
  requires: v >= 1
{
  return Dimension{ value: v };
}

pub fn dimension_value(d: &Dimension) -> Int {
  return d.value;
}

pub fn dimension_eq(a: &Dimension, b: &Dimension) -> Bool {
  return a.value == b.value;
}

// Delegates to the shared core predicate so vector and non-vector subsystems
// agree on what a valid dimension is.
pub fn dimension_is_valid(v: Int) -> Bool {
  return is_valid_dimension(v);
}

pub fn dimension_within_limit(v: Int) -> Bool {
  return v >= 1 && v <= max_dimensions();
}
