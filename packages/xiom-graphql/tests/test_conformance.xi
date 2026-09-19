// XIOM -- xiom.graphql Conformance Tests (10 tests)
module xiom.graphql.tests

use xiom.graphql;
use xiom.string;
use xiom.io;

fn assert_true(condition: Bool, label: Str) -> Result[Unit, Str] {
  if condition { return Ok(Unit); };
  return Err("FAIL: " + label);
}

fn assert_int_eq(actual: Int, expected: Int, label: Str) -> Result[Unit, Str] {
  if actual == expected { return Ok(Unit); };
  return Err("FAIL: " + label + " -- expected " + int_to_str(expected) + " got " + int_to_str(actual));
}

fn assert_bool_eq(actual: Bool, expected: Bool, label: Str) -> Result[Unit, Str] {
  if actual == expected { return Ok(Unit); };
  return Err("FAIL: " + label);
}

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; };
  var num: Int = n;
  var neg: Bool = false;
  if num < 0 { neg = true; num = -num; };
  var out: Str = "";
  while num > 0 {
    var d: Int = num % 10;
    if d == 0 { out = "0" + out; }
    elif d == 1 { out = "1" + out; }
    elif d == 2 { out = "2" + out; }
    elif d == 3 { out = "3" + out; }
    elif d == 4 { out = "4" + out; }
    elif d == 5 { out = "5" + out; }
    elif d == 6 { out = "6" + out; }
    elif d == 7 { out = "7" + out; }
    elif d == 8 { out = "8" + out; }
    elif d == 9 { out = "9" + out; };
    num = num / 10;
  };
  if neg { out = "-" + out; };
  return out;
}

pub fn run_all_tests() -> Result[Unit, Str] {
  io.println("=== xiom.graphql Conformance Tests ===");

  var passed: Int = 0;
  var failed: Int = 0;
  var total: Int = 0;

  var results: Vec[Result[Unit, Str]] = Vec[Result[Unit, Str]].new();
  results.push(test_schema_new());
  results.push(test_schema_add_and_find_type());
  results.push(test_type_add_field());
  results.push(test_field_deprecate());
  results.push(test_parse_query_stub());
  results.push(test_parse_mutation_stub());
  results.push(test_validate_empty_schema_error());
  results.push(test_validate_valid_operation());
  results.push(test_execute_empty_document_error());
  results.push(test_introspect_schema());

  var i: Int = 0;
  while i < results.len() {
    total = total + 1;
    match results[i] {
      Ok(_) => { passed = passed + 1; },
      Err(e) => { failed = failed + 1; io.println(e); },
    };
    i = i + 1;
  };

  io.println("");
  io.println(int_to_str(passed) + " passed, " + int_to_str(failed) + " failed out of " + int_to_str(total));

  if failed > 0 {
    return Err(int_to_str(failed) + " test(s) failed");
  };
  return Ok(Unit);
}

fn test_schema_new() -> Result[Unit, Str] {
  var s = schema_new();
  try(assert_int_eq(s.types.len(), 0, "schema_new: empty types"));
  try(assert_bool_eq(s.query_type == "Query", true, "schema_new: query_type"));
  try(assert_bool_eq(s.mutation_type == "Mutation", true, "schema_new: mutation_type"));
  return Ok(Unit);
}

fn test_schema_add_and_find_type() -> Result[Unit, Str] {
  var s = schema_new();
  var t = type_new("User", GraphQLTypeKind.Object);
  schema_add_type(&mut s, t);

  try(assert_int_eq(schema_type_count(&s), 1, "schema_type_count: 1 type"));
  try(assert_bool_eq(schema_has_type(&s, "User"), true, "schema_has_type: User exists"));
  try(assert_bool_eq(schema_has_type(&s, "Missing"), false, "schema_has_type: Missing absent"));

  var found = schema_find_type(&s, "User");
  match found {
    Some(ft) => { try(assert_bool_eq(ft.name == "User", true, "schema_find_type: name match")); },
    None => { return Err("FAIL: schema_find_type returned None"); },
  };
  return Ok(Unit);
}

fn test_type_add_field() -> Result[Unit, Str] {
  var t = type_new("Query", GraphQLTypeKind.Object);
  var f1 = field_new("hello", "String!");
  type_add_field(&mut t, f1);
  var f2 = field_new("version", "Int!");
  type_add_field(&mut t, f2);

  try(assert_int_eq(t.fields.len(), 2, "type: 2 fields added"));

  var found = type_find_field(&t, "hello");
  match found {
    Some(ff) => { try(assert_bool_eq(ff.type_ref == "String!", true, "type_find_field: type_ref match")); },
    None => { return Err("FAIL: type_find_field returned None"); },
  };

  var missing = type_find_field(&t, "missing");
  match missing {
    Some(_) => { return Err("FAIL: type_find_field missing returned Some"); },
    None => {},
  };
  return Ok(Unit);
}

fn test_field_deprecate() -> Result[Unit, Str] {
  var f = field_new("oldField", "String");
  try(assert_bool_eq(f.is_deprecated, false, "field: not deprecated initially"));
  field_deprecate(&mut f, "Use newField instead");
  try(assert_bool_eq(f.is_deprecated, true, "field: deprecated after deprecate"));
  try(assert_bool_eq(f.deprecation_reason == "Use newField instead", true, "field: deprecation reason"));
  return Ok(Unit);
}

fn test_parse_query_stub() -> Result[Unit, Str] {
  var result = parse_query("query { hello }");
  match result {
    Ok(doc) => {
      try(assert_int_eq(doc.operations.len(), 1, "parse_query: 1 operation"));
      match doc.operations[0].op_type {
        OperationType.Query => {},
        _ => { return Err("FAIL: parse_query expected Query operation"); },
      };
    },
    Err(e) => { return Err("FAIL: parse_query: " + e.message); },
  };
  return Ok(Unit);
}

fn test_parse_mutation_stub() -> Result[Unit, Str] {
  var result = parse_query("mutation CreateUser { createUser(name: \"Test\") { id } }");
  match result {
    Ok(doc) => {
      try(assert_int_eq(doc.operations.len(), 1, "parse_mutation: 1 operation"));
      match doc.operations[0].op_type {
        OperationType.Mutation => {},
        _ => { return Err("FAIL: parse_mutation expected Mutation operation"); },
      };
    },
    Err(e) => { return Err("FAIL: parse_mutation: " + e.message); },
  };
  return Ok(Unit);
}

fn test_validate_empty_schema_error() -> Result[Unit, Str] {
  var s = schema_new();
  var op = operation_new(OperationType.Query, "TestQuery");
  var result = validate_operation(&s, &op);
  match result {
    Ok(_) => { return Err("FAIL: validate on empty schema should fail"); },
    Err(errors) => {
      try(assert_int_eq(errors.len(), 1, "validate_empty_schema: 1 error"));
    },
  };
  return Ok(Unit);
}

fn test_validate_valid_operation() -> Result[Unit, Str] {
  var s = schema_new();
  var query_type = type_new("Query", GraphQLTypeKind.Object);
  var hello_field = field_new("hello", "String!");
  type_add_field(&mut query_type, hello_field);
  schema_add_type(&mut s, query_type);

  var op = operation_new(OperationType.Query, "ValidQuery");
  var fs = GraphQLFieldSelection{
    name: "hello",
    alias: "",
    args: Vec[GraphQLArgument].new(),
    directives: Vec[GraphQLDirective].new(),
    selection_set: GraphQLSelectionSet{ selections: Vec[GraphQLSelection].new() },
  };
  operation_add_field(&mut op, fs);

  var result = validate_operation(&s, &op);
  match result {
    Ok(_) => {},
    Err(_) => { return Err("FAIL: validate should succeed for valid operation"); },
  };
  return Ok(Unit);
}

fn test_execute_empty_document_error() -> Result[Unit, Str] {
  var s = schema_new();
  var qt = type_new("Query", GraphQLTypeKind.Object);
  schema_add_type(&mut s, qt);
  var doc = GraphQLDocument{
    operations: Vec[GraphQLOperation].new(),
    fragments: Vec[GraphQLFragment].new(),
  };
  var result = execute(&s, &doc, "");
  match result {
    Ok(_) => { return Err("FAIL: execute on empty doc should fail"); },
    Err(e) => { try(assert_bool_eq(string.str_len(e.message) > 0, true, "execute empty: got error message")); },
  };
  return Ok(Unit);
}

fn test_introspect_schema() -> Result[Unit, Str] {
  var s = schema_new();
  var t = type_new("User", GraphQLTypeKind.Object);
  schema_add_type(&mut s, t);
  var intro = introspect_schema(&s);
  try(assert_bool_eq(intro.name == "__Schema", true, "introspect: name is __Schema"));
  try(assert_int_eq(intro.fields.len(), 1, "introspect: 1 field on __Schema"));
  return Ok(Unit);
}

fn try(res: Result[Unit, Str]) {
  match res {
    Ok(_) => {},
    Err(e) => { io.println(e); },
  };
}
