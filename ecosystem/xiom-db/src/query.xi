module xiom.db.query

pub enum QueryOp {
  Eq,
  Neq,
  Lt,
  Lte,
  Gt,
  Gte,
}

pub type QueryCondition = {
  op: QueryOp;
  value: Int;
}

pub type Query = {
  conditions: Vec[QueryCondition];
  limit: Int;
  offset: Int;
}

pub fn query_new() -> Query {
  var conditions = Vec[QueryCondition].new();
  return Query{ conditions: conditions, limit: 0, offset: 0 };
}

pub fn query_where(q: &mut Query, op: QueryOp, value: Int) {
  var cond = QueryCondition{ op: op, value: value };
  q.conditions.push(cond);
}

pub fn query_limit(q: &mut Query, limit: Int)
  requires: limit > 0
{
  q.limit = limit;
}

pub fn query_offset(q: &mut Query, offset: Int)
  requires: offset >= 0
{
  q.offset = offset;
}

pub fn query_execute(q: &Query, tree: &BTree) -> Vec[Int] {
  var all_values = btree_to_vec(tree);
  var results = Vec[Int].new();

  var start_idx = q.offset;
  var count = 0;

  var i = 0;
  while i < all_values.len() {
    if matches_all_conditions(all_values[i], q.conditions) {
      if count >= start_idx {
        results.push(all_values[i]);
      }
      count = count + 1;
    }
    i = i + 1;
  }

  if q.limit > 0 && results.len() > q.limit {
    var limited = Vec[Int].new();
    var j = 0;
    while j < q.limit {
      limited.push(results[j]);
      j = j + 1;
    }
    return limited;
  }
  return results;
}

fn matches_all_conditions(value: Int, conditions: &Vec[QueryCondition]) -> Bool {
  var i = 0;
  while i < conditions.len() {
    if !test_condition(value, conditions[i].op, conditions[i].value) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn test_condition(value: Int, op: QueryOp, target: Int) -> Bool {
  match op {
    Eq => value == target,
    Neq => value != target,
    Lt => value < target,
    Lte => value <= target,
    Gt => value > target,
    Gte => value >= target,
  }
}

pub fn query_condition_count(q: &Query) -> Int {
  return q.conditions.len();
}

pub fn query_has_limit(q: &Query) -> Bool {
  return q.limit > 0;
}

pub fn query_has_offset(q: &Query) -> Bool {
  return q.offset > 0;
}

pub fn query_reset(q: &mut Query) {
  var empty = Vec[QueryCondition].new();
  q.conditions = empty;
  q.limit = 0;
  q.offset = 0;
}
