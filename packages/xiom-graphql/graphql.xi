// XIOM — GraphQL Engine (Pure-XIOM Schema, Query Parser & Validator Stubs)
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.

module xiom.graphql

use xiom.string;
use xiom.convert;

// ─── Types ──────────────────────────────────────────────────────────────────

pub type GraphQLSchema = {
  types: Vec[GraphQLType];
  query_type: Str;
  mutation_type: Str;
  subscription_type: Str;
} derive[Clone]

pub type GraphQLType = {
  name: Str;
  kind: GraphQLTypeKind;
  fields: Vec[GraphQLField];
  interfaces: Vec[Str];
} derive[Clone]

pub enum GraphQLTypeKind {
  Scalar,
  Object,
  Interface,
  Union,
  Enum,
  InputObject,
  List,
  NonNull,
} derive[Clone]

pub type GraphQLField = {
  name: Str;
  type_ref: Str;
  args: Vec[GraphQLArg];
  is_deprecated: Bool;
  deprecation_reason: Str;
} derive[Clone]

pub type GraphQLArg = {
  name: Str;
  type_ref: Str;
  default_value: Option[Str];
} derive[Clone]

// ─── Operation Types ──────────────────────────────────────────────────────

pub enum OperationType {
  Query,
  Mutation,
  Subscription,
} derive[Clone]

// ─── AST Nodes ──────────────────────────────────────────────────────────────

pub type GraphQLDocument = {
  operations: Vec[GraphQLOperation];
  fragments: Vec[GraphQLFragment];
} derive[Clone]

pub type GraphQLOperation = {
  op_type: OperationType;
  name: Str;
  variable_defs: Vec[GraphQLVariableDef];
  directives: Vec[GraphQLDirective];
  selection_set: GraphQLSelectionSet;
} derive[Clone]

pub type GraphQLVariableDef = {
  name: Str;
  type_ref: Str;
  default_value: Option[Str];
} derive[Clone]

pub type GraphQLFragment = {
  name: Str;
  type_condition: Str;
  directives: Vec[GraphQLDirective];
  selection_set: GraphQLSelectionSet;
} derive[Clone]

pub type GraphQLSelectionSet = {
  selections: Vec[GraphQLSelection];
} derive[Clone]

pub enum GraphQLSelection {
  Field(selection: GraphQLFieldSelection),
  FragmentSpread(selection: GraphQLFragmentSpread),
  InlineFragment(selection: GraphQLInlineFragment),
} derive[Clone]

pub type GraphQLFieldSelection = {
  name: Str;
  alias: Str;
  args: Vec[GraphQLArgument];
  directives: Vec[GraphQLDirective];
  selection_set: GraphQLSelectionSet;
} derive[Clone]

pub type GraphQLFragmentSpread = {
  name: Str;
  directives: Vec[GraphQLDirective];
} derive[Clone]

pub type GraphQLInlineFragment = {
  type_condition: Str;
  directives: Vec[GraphQLDirective];
  selection_set: GraphQLSelectionSet;
} derive[Clone]

pub type GraphQLArgument = {
  name: Str;
  value: GraphQLValue;
} derive[Clone]

pub enum GraphQLValue {
  IntValue(value: Int),
  FloatValue(value: Float64),
  StringValue(value: Str),
  BooleanValue(value: Bool),
  NullValue,
  EnumValue(value: Str),
  ListValue(items: Vec[GraphQLValue]),
  ObjectValue(fields: Vec[GraphQLObjectField]),
  Variable(name: Str),
} derive[Clone]

pub type GraphQLObjectField = {
  name: Str;
  value: GraphQLValue;
} derive[Clone]

pub type GraphQLDirective = {
  name: Str;
  args: Vec[GraphQLArgument];
} derive[Clone]

// ─── Error Types ────────────────────────────────────────────────────────────

pub type GraphQLError = {
  message: Str;
  path: Vec[Str];
  locations: Vec[GraphQLLocation];
} derive[Clone]

pub type GraphQLLocation = {
  line: Int;
  column: Int;
} derive[Clone]

pub type ParseError = {
  message: Str;
  line: Int;
  column: Int;
} derive[Clone]

pub type ValidationError = {
  message: Str;
  rule: Str;
  path: Vec[Str];
} derive[Clone]

// ─── Execution Result ───────────────────────────────────────────────────────

pub type ExecutionResult = {
  data: Option[GraphQLValue];
  errors: Vec[GraphQLError];
} derive[Clone]

// ─── Schema Builder ─────────────────────────────────────────────────────────

pub fn schema_new() -> GraphQLSchema {
  return GraphQLSchema{
    types: Vec[GraphQLType].new(),
    query_type: "Query",
    mutation_type: "Mutation",
    subscription_type: "Subscription",
  };
}

pub fn schema_add_type(schema: &mut GraphQLSchema, t: GraphQLType) {
  schema.types.push(t);
}

pub fn schema_find_type(schema: &GraphQLSchema, name: Str) -> Option[GraphQLType] {
  var i: Int = 0;
  while i < schema.types.len() {
    if schema.types[i].name == name {
      return Some(schema.types[i]);
    };
    i = i + 1;
  };
  return None;
}

pub fn schema_has_type(schema: &GraphQLSchema, name: Str) -> Bool {
  var t = schema_find_type(schema, name);
  match t {
    Some(_) => { return true; },
    None => { return false; },
  };
}

// ─── Type Builder ───────────────────────────────────────────────────────────

pub fn type_new(name: Str, kind: GraphQLTypeKind) -> GraphQLType {
  return GraphQLType{
    name: name,
    kind: kind,
    fields: Vec[GraphQLField].new(),
    interfaces: Vec[Str].new(),
  };
}

pub fn type_add_field(t: &mut GraphQLType, field: GraphQLField) {
  t.fields.push(field);
}

pub fn type_find_field(t: &GraphQLType, name: Str) -> Option[GraphQLField] {
  var i: Int = 0;
  while i < t.fields.len() {
    if t.fields[i].name == name {
      return Some(t.fields[i]);
    };
    i = i + 1;
  };
  return None;
}

// ─── Field Builder ──────────────────────────────────────────────────────────

pub fn field_new(name: Str, type_ref: Str) -> GraphQLField {
  return GraphQLField{
    name: name,
    type_ref: type_ref,
    args: Vec[GraphQLArg].new(),
    is_deprecated: false,
    deprecation_reason: "",
  };
}

pub fn field_add_arg(field: &mut GraphQLField, arg: GraphQLArg) {
  field.args.push(arg);
}

pub fn field_deprecate(field: &mut GraphQLField, reason: Str) {
  field.is_deprecated = true;
  field.deprecation_reason = reason;
}

// ─── Arg Builder ────────────────────────────────────────────────────────────

pub fn arg_new(name: Str, type_ref: Str) -> GraphQLArg {
  return GraphQLArg{
    name: name,
    type_ref: type_ref,
    default_value: None,
  };
}

// ─── Operation Builder ──────────────────────────────────────────────────────

pub fn operation_new(op_type: OperationType, name: Str) -> GraphQLOperation {
  var empty_set = GraphQLSelectionSet{
    selections: Vec[GraphQLSelection].new(),
  };
  return GraphQLOperation{
    op_type: op_type,
    name: name,
    variable_defs: Vec[GraphQLVariableDef].new(),
    directives: Vec[GraphQLDirective].new(),
    selection_set: empty_set,
  };
}

pub fn operation_add_field(op: &mut GraphQLOperation, field: GraphQLFieldSelection) {
  var sel = GraphQLSelection.Field(field);
  op.selection_set.selections.push(sel);
}

// ─── Value Builder ──────────────────────────────────────────────────────────

pub fn value_int(n: Int) -> GraphQLValue { return GraphQLValue.IntValue(n); }
pub fn value_float(n: Float64) -> GraphQLValue { return GraphQLValue.FloatValue(n); }
pub fn value_string(s: Str) -> GraphQLValue { return GraphQLValue.StringValue(s); }
pub fn value_bool(b: Bool) -> GraphQLValue { return GraphQLValue.BooleanValue(b); }
pub fn value_null() -> GraphQLValue { return GraphQLValue.NullValue; }
pub fn value_variable(name: Str) -> GraphQLValue { return GraphQLValue.Variable(name); }

// ─── Query Parser Stubs ─────────────────────────────────────────────────────

pub fn parse_query(source: Str) -> Result[GraphQLDocument, ParseError]
  requires: string.str_len(source) > 0
{
  if string.str_len(source) == 0 {
    return Err(ParseError{
      message: "empty query string",
      line: 1,
      column: 1,
    });
  };

  var doc = GraphQLDocument{
    operations: Vec[GraphQLOperation].new(),
    fragments: Vec[GraphQLFragment].new(),
  };

  // Stub: detect first non-whitespace word as operation type
  if string.str_len(source) >= 5 {
    if string.str_starts_with(source, "query") {
      var op = operation_new(OperationType.Query, "");
      doc.operations.push(op);
      return Ok(doc);
    };
    if string.str_starts_with(source, "mutation") {
      var op = operation_new(OperationType.Mutation, "");
      doc.operations.push(op);
      return Ok(doc);
    };
    if string.str_starts_with(source, "subscription") {
      var op = operation_new(OperationType.Subscription, "");
      doc.operations.push(op);
      return Ok(doc);
    };
  };

  // Stub: treat as anonymous query
  var op = operation_new(OperationType.Query, "");
  doc.operations.push(op);
  return Ok(doc);
}

// ─── Query Validator Stubs ──────────────────────────────────────────────────

pub fn validate_operation(
  schema: &GraphQLSchema,
  op: &GraphQLOperation,
) -> Result[Unit, Vec[ValidationError]]
  requires: schema.types.len() > 0
{
  var errors: Vec[ValidationError] = Vec[ValidationError].new();

  var query_type_name: Str = match op.op_type {
    OperationType.Query => schema.query_type,
    OperationType.Mutation => schema.mutation_type,
    OperationType.Subscription => schema.subscription_type,
  };

  var root_type = schema_find_type(schema, query_type_name);
  match root_type {
    None => {
      var err = ValidationError{
        message: string.str_concat("schema has no ", query_type_name),
        rule: "root_type_check",
        path: Vec[Str].new(),
      };
      errors.push(err);
      return Err(errors);
    },
    Some(_) => {},
  };

  // Stub: validate each selection exists on root type
  var root: GraphQLType;
  match root_type {
    Some(rt) => { root = rt; },
    None => {
      var err = ValidationError{
        message: string.str_concat("schema has no ", query_type_name),
        rule: "root_type_check",
        path: Vec[Str].new(),
      };
      errors.push(err);
      return Err(errors);
    },
  };
  var i: Int = 0;
  while i < op.selection_set.selections.len() {
    match op.selection_set.selections[i] {
      GraphQLSelection.Field(fs) => {
        var found = type_find_field(&root, fs.name);
        match found {
          None => {
            var err = ValidationError{
              message: string.str_concat("Cannot query field '", string.str_concat(fs.name, "' on type '")),
              rule: "field_check",
              path: Vec[Str].new(),
            };
            err.message = string.str_concat(err.message, string.str_concat(root.name, "'"));
            errors.push(err);
          },
          Some(_) => {},
        };
      },
      GraphQLSelection.FragmentSpread(_) => {},
      GraphQLSelection.InlineFragment(_) => {},
    };
    i = i + 1;
  };

  if errors.len() > 0 {
    return Err(errors);
  };
  return Ok(());
}

pub fn validate_document(
  schema: &GraphQLSchema,
  doc: &GraphQLDocument,
) -> Result[Unit, Vec[ValidationError]]
  requires: schema.types.len() > 0
{
  var all_errors: Vec[ValidationError] = Vec[ValidationError].new();
  var i: Int = 0;
  while i < doc.operations.len() {
    var result = validate_operation(schema, &doc.operations[i]);
    match result {
      Err(errs) => {
        var j: Int = 0;
        while j < errs.len() {
          all_errors.push(errs[j]);
          j = j + 1;
        };
      },
      Ok(_) => {},
    };
    i = i + 1;
  };
  if all_errors.len() > 0 {
    return Err(all_errors);
  };
  return Ok(());
}

// ─── Execution Stubs ────────────────────────────────────────────────────────

pub fn execute(
  schema: &GraphQLSchema,
  doc: &GraphQLDocument,
  op_name: Str,
) -> Result[ExecutionResult, GraphQLError] {
  if doc.operations.len() == 0 {
    return Err(GraphQLError{
      message: "no operations in document",
      path: Vec[Str].new(),
      locations: Vec[GraphQLLocation].new(),
    });
  };

  // Stub: always returns empty data + no errors for recognized schema
  if !schema_has_type(schema, schema.query_type) {
    return Err(GraphQLError{
      message: "schema missing root query type",
      path: Vec[Str].new(),
      locations: Vec[GraphQLLocation].new(),
    });
  };

  return Ok(ExecutionResult{
    data: Some(GraphQLValue.ObjectValue(Vec[GraphQLObjectField].new())),
    errors: Vec[GraphQLError].new(),
  });
}

// ─── Introspection Stubs ────────────────────────────────────────────────────

pub fn introspect_schema(schema: &GraphQLSchema) -> GraphQLType {
  var intro = type_new("__Schema", GraphQLTypeKind.Object);
  var types_field = field_new("types", "[__Type!]!");
  type_add_field(&mut intro, types_field);
  return intro;
}

pub fn schema_type_count(schema: &GraphQLSchema) -> Int {
  return schema.types.len();
}
