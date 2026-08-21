# xiom-graphql ROADMAP

## v0.1.0 (Current)
- [x] Core type system (GraphQLSchema, GraphQLType, GraphQLField, GraphQLArg)
- [x] AST node types (GraphQLDocument, GraphQLOperation, GraphQLSelectionSet, GraphQLValue)
- [x] Schema builder API (schema_new, schema_add_type, type_add_field, field_new, arg_new)
- [x] Operation builder (operation_new, operation_add_field)
- [x] Value constructors (value_int, value_float, value_string, value_bool, value_null, value_variable)
- [x] Query parser stubs (parse_query with operation keyword detection)
- [x] Operation validator stubs (validate_operation, validate_document with root type + field existence checks)
- [x] Execution stub (execute returns empty data for valid schemas)
- [x] Introspection stub (introspect_schema, schema_type_count)
- [x] Precision-typed error model (ParseError, ValidationError, GraphQLError)
- [x] Conformance test suite (10 tests)

## v0.2.0 -- Full SDL Parser
- [ ] Recursive-descent SDL parser (full GraphQL schema definition language)
- [ ] Scalar type resolution (Int, Float, String, Boolean, ID)
- [ ] Non-null and List type wrapper parsing
- [ ] Enum type definition parsing
- [ ] Input object type definition parsing
- [ ] Interface and Union type definition parsing
- [ ] Directive definition parsing
- [ ] Schema composition from multiple SDL files

## v0.3.0 -- Full Query Parser
- [ ] Recursive-descent query parser (full GraphQL query language)
- [ ] Variable definition parsing
- [ ] Fragment definition and spread parsing
- [ ] Inline fragment parsing
- [ ] Directive parsing (@skip, @include, @deprecated)
- [ ] Alias support
- [ ] Argument parsing with nested values

## v0.4.0 -- Validation Engine
- [ ] Full GraphQL validation rule set
- [ ] Field existence on target type
- [ ] Argument type validation
- [ ] Fragment spread target existence
- [ ] Fragment cycle detection
- [ ] Variable usage validation
- [ ] Operation name uniqueness
- [ ] Lone anonymous operation rule
- [ ] Leaf field selection rule

## v0.5.0 -- Execution Engine
- [ ] Field resolver dispatch
- [ ] Parallel query execution
- [ ] Sequential mutation execution
- [ ] Null propagation
- [ ] Error collection and path tracking
- [ ] Response assembly

## v1.0.0 -- Production Readiness
- [ ] Subscriptions via event streams
- [ ] DataLoader integration for N+1 mitigation
- [ ] Introspection query support (__schema, __type, __typename)
- [ ] Full contract verification on all public functions
- [ ] Transport bridge to xiom-http
- [ ] Performance benchmarks
- [ ] Load testing suite
