// B-03 minimal shape: a facade const that aliases a sibling module's const
// (`pub const A: Int = other_module.B;`). On v0.64.0 this recursed the
// resolver (stack overflow) when a consumer referenced the alias.
module probe.constalias

use probe.constalias.leaf;

pub const FACADE_VALUE: Int = leaf.LEAF_VALUE;
