module xiom.db.query.planner
use xiom.db.query.query;
use xiom.db.index.btree;

// SCAFFOLD (Phase 3). The planner chooses HOW a `Query` runs. Today the engine
// always performs a full scan; the planner will inspect the conditions and,
// when a condition constrains the indexed key, emit a bounded `IndexRange` plan
// that pushes the predicate into `btree_range_query` for O(log n + k) access
// instead of O(n). The plan is a value so it can be logged, cached, and tested.

pub enum PlanKind {
  FullScan,
  IndexRange,
  PointLookup,
}

pub type QueryPlan = {
  kind: PlanKind;
  low: Int;
  high: Int;
  has_bounds: Bool;
  estimated_rows: Int;
}

pub fn query_plan_full_scan() -> QueryPlan {
  return QueryPlan{
    kind: PlanKind.FullScan,
    low: 0, high: 0, has_bounds: false,
    estimated_rows: 0,
  };
}

// Select an execution plan for `q` against `tree`.
// TODO(Phase 3): derive tight [low, high] bounds from Lt/Lte/Gt/Gte/Eq
// conditions on the key column, detect point lookups, and cost each candidate
// against `btree_size`. For now every query degrades to a safe full scan.
pub fn plan_query(q: &Query, tree: &BTree) -> QueryPlan {
  // TODO(Phase 3): real cost-based plan selection.
  var plan = query_plan_full_scan();
  plan.estimated_rows = btree_size(tree);
  return plan;
}

// Execute a plan. Currently delegates to the scan-based `query_execute`.
// TODO(Phase 3): honour IndexRange/PointLookup by calling btree_range_query /
// btree_search directly, then applying residual predicates.
pub fn execute_plan(plan: &QueryPlan, q: &Query, tree: &BTree) -> Vec[Int] {
  match plan.kind {
    FullScan => query_execute(q, tree)
    IndexRange => {
      // TODO(Phase 3): btree_range_query(tree, plan.low, plan.high) + residual filter.
      query_execute(q, tree)
    }
    PointLookup => {
      // TODO(Phase 3): btree_search on the equality key.
      query_execute(q, tree)
    }
  }
}
