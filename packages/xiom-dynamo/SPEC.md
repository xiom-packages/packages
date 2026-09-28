# xiom.dynamo -- specification

Specification of `src/dynamo.xi` (package `xiom.dynamo` 0.1.0) as actually
implemented and exercised by `tests/test_conformance.xi` (21 checks). The
module is a pure payload codec: no sockets, no signing, no credentials, no
DynamoDB semantics (expression evaluation, pagination, retries).

## 1. Wire scope -- the DynamoDB JSON protocol

The module speaks the **DynamoDB JSON** envelope form (as used by the AWS
SDKs' HTTP bodies), not the low-level `AttributeValue` API wire format:

```
AttributeValue = { TYPE : VALUE }          ; exactly one member
TYPE           = "S" | "N" | "B" | "SS" | "NS" | "BS" | "M" | "L"
               | "NULL" | "BOOL"
item           = { attribute-name : AttributeValue *("," ...) }
```

Bare items (`dynamo_item_parse`) are map bodies; attribute values
(`dynamo_av_parse`) are the one-member envelopes.

## 2. JSON scanner

All parsing and response lookup use one bounded raw-byte scanner over
`Vec[UInt8]`:

- **Bound**: inputs longer than `dynamo_max_json_bytes()` (1 048 576 bytes)
  are rejected with `dynamo: json too large`. Item size validation uses the
  documented 400KB cap separately (section 8).
- **Escape-aware strings**: `\"  \\  \/  \b  \f  \n  \r  \t  \uXXXX` are
  decoded; `\uXXXX` encodes UTF-8, surrogate pairs are combined, NUL
  (`\u0000`) and lone surrogates are errors. Bytes `>= 0x20` pass through
  (UTF-8), so decoded strings hold the same text the wire carried.
- **Boundary-checked**: every byte read is guarded by an explicit
  `pos < end` check; malformed endings produce offset-bearing errors.
- **Raw control bytes** (below `0x20`, except TAB/LF/CR as JSON whitespace)
  are rejected with their offset.
- Outside strings, whitespace (space, TAB, LF, CR) is skipped between
  tokens; inside strings it is literal.

## 3. AttributeValue kind ids

| Kind | id | Wire form | Stored |
|------|----|-----------|--------|
| S | 1 | `{"S":"text"}` | decoded text |
| N | 2 | `{"N":"-1.5e3"}` | validated number text |
| B | 3 | `{"B":"AQI="}` | validated base64 text |
| SS | 4 | `{"SS":["a","b"]}` | child S leaves |
| NS | 5 | `{"NS":["1","2.5"]}` | child N leaves |
| BS | 6 | `{"BS":["AQI="]}` | child B leaves |
| M | 7 | `{"M":{"k":{...}}}` | child key/value node pairs |
| L | 8 | `{"L":[{...},...]}` | child nodes |
| NULL | 9 | `{"NULL":true}` | flag 1 (only `true` accepted) |
| BOOL | 10 | `{"BOOL":true\|false}` | flag 0/1 |
| KEY | 11 | internal map-key leaf | key text |

Map keys are stored as `KEY` leaves interleaved with value nodes, so
`children` is `[key0, value0, key1, value1, ...]`.

## 4. Node tape

`DynamoValue` is a flat, post-order node arena with parallel vectors:
`kinds`, `texts`, `flags`, `starts`, `counts`, `children`. Node `n` owns the
contiguous children `children[starts[n] .. starts[n] + counts[n])`. A
`DynamoItem` pairs a tape with a root `node` (-1 = absent). There is no
`Vec[StructType]` anywhere; `dynamo_value_merge` appends one tape to another
by shifting node indices and child spans, so expression-attribute values,
batch keys and transact items share one tape per request.

### 4.1 Builders

`dynamo_value_push_string/number/binary/bool/null` push leaves;
`push_set/push_list/push_map` push containers over existing nodes.
`push_number` and `push_binary` validate, `push_set` requires SS/NS/BS, at
least one member, no duplicates and per-kind member validation; `push_map`
requires equal-length key/node vectors, non-empty unique keys and valid node
indices. Builders validate before they mutate the tape.

## 5. Canonical render

`dynamo_av_render` / `dynamo_value_render` / `dynamo_item_render` emit
compact JSON: no whitespace, fixed member order, string escapes (`\"`,
`\\`, `\b`, `\f`, `\n`, `\r`, `\t`, `\u00XX` for other C0 bytes), raw UTF-8
for everything else. Numbers and base64 text render verbatim; sets render in
parse/insertion order. `dynamo_item_render` emits the bare map body for an
M root (the item wire form) and falls back to `dynamo_av_render` otherwise.
Parsing a canonical render and rendering again is stable (tested).

## 6. Item codec

`dynamo_item_parse(data, a, b)` / `dynamo_item_parse_str` parse a map body
into a `DynamoItem` of root kind M. Attribute names must decode to non-empty
text and must be unique inside their map. `dynamo_item_binary` decodes a B
leaf through the local base64 helper.

Typed accessors: `dynamo_item_kind`, `dynamo_item_kind_name`,
`dynamo_item_string`, `dynamo_item_number_text`,
`dynamo_item_number_int_text` (sign + integer digits), `_frac_text` (digits
after `.`), `_exp_text` (sign + digits after `e`/`E`), `dynamo_item_bool`,
`dynamo_item_is_null`, `dynamo_item_set_len/text_at` (SS/NS/BS),
`dynamo_item_map_len/key_at/node_at/get_node/get` (M),
`dynamo_item_list_len/node_at/get` (L). Accessors return neutral values on a
kind mismatch/absence ("" / 0 / false / -1); callers dispatch on
`dynamo_item_kind`.

## 7. Number and base64 rules

Numbers: optional `+`/`-`, one or more digits, optional `.` + digits,
optional `e`/`E` + optional sign + digits. Bare signs, missing fraction or
exponent digits, whitespace, `NaN`, `Inf`, hex and underscores are rejected
with offsets. Precision/range limits (38 significant digits, exponent
[-130,125]) are **not** enforced; the text is kept exact.

Base64 (standard alphabet, B/BS): alphabet bytes only, at most two trailing
`=` pads, no `body % 4 == 1`; padded and unpadded inputs are both accepted
by decode; encode always pads. Decoded bytes may contain NUL; strings built
from decoded JSON text may not (`\u0000` is rejected).

## 8. Validation helpers

| Function | Rule |
|----------|------|
| `dynamo_table_name_check/is_valid` | length 3..255, charset `[a-zA-Z0-9_.-]`, offset errors |
| `dynamo_key_name_check/is_valid` | same rule, "key name" in errors |
| `dynamo_item_check(data, a, b)` | `b - a <= 409600`, else `dynamo: item exceeds 400KB (409600 bytes) at offset 409600` |
| `dynamo_item_max_bytes()` | 409600 |
| `dynamo_max_json_bytes()` | 1048576 |

The name rule is enforced by request renders (`TableName`); item parsing
itself only enforces non-empty unique attribute names.

## 9. Request shapes (render field order)

All renders validate `TableName` and the key/item payloads and produce
`Result[Str, Str]`. Absent optionals are omitted; defaults are never
emitted unless explicit.

| Request | Fixed order | Notes |
|---------|-------------|-------|
| `dynamo_get_item_render` | TableName, Key, ConsistentRead, ProjectionExpression, ReturnConsumedCapacity | ConsistentRead only when true |
| `dynamo_put_item_render` | TableName, Item, ConditionExpression, ReturnValues | |
| `dynamo_update_item_render` | TableName, Key, UpdateExpression \| AttributeUpdates, ReturnValues | UpdateExpression wins; else has_attribute_updates; neither is an error |
| `dynamo_delete_item_render` | TableName, Key, ConditionExpression, ReturnValues | |
| `dynamo_query_render` | TableName, IndexName, KeyConditionExpression, ExpressionAttributeNames, ExpressionAttributeValues, Limit, ExclusiveStartKey, ScanIndexForward, Select | Limit > 0; ScanIndexForward only when `scan_index_forward_set` |
| `dynamo_scan_render` | TableName, IndexName, FilterExpression, ExpressionAttributeNames, ExpressionAttributeValues, Limit, ExclusiveStartKey, Select, ConsistentRead | ConsistentRead only when true |
| `dynamo_batch_get_render` | `{"RequestItems":{table:{"Keys":[...],"ConsistentRead":...,"ProjectionExpression":...}}}` | tables before keys; at least one table and one key per table |
| `dynamo_batch_write_render` | `{"RequestItems":{table:[{"PutRequest":{"Item":...}}\|{"DeleteRequest":{"Key":...}}]}}` | at least one table and one request per table |
| `dynamo_transact_write_render` | `{"TransactItems":[{"Put"\|"Update"\|"Delete"\|"ConditionCheck":{TableName,(Item\|Key),Expression}}]}` | Update requires UpdateExpression; ConditionCheck requires ConditionExpression |

`DynamoAttributeUpdates` renders `{"name":{"Value":<av>,"Action":"PUT"}}`
with actions PUT/DELETE/ADD and unique names. `DynamoNameMap` renders
`{"#alias":"name"}`; `DynamoValueMap` renders `{":placeholder":<av>}` with
merged value tapes.

## 10. Response shapes

`dynamo_response_span(data, key)` returns the byte span of the **first
top-level member** `key` of the response object (nesting- and
escape-aware). Missing keys are `Err("dynamo: json key not found: <key>")`.

| Parser | Result |
|--------|--------|
| `dynamo_response_item` | `Result[DynamoItem, Str]` for `Item` (root M) |
| `dynamo_response_items` | `Result[DynamoItems, Str]` for `Items` (`tape` + `nodes`, `dynamo_items_count/get/node_at`) |
| `dynamo_response_last_key` | `DynamoLastKey {present, item}`; absent or malformed -> present false |
| `dynamo_response_counts` | `DynamoCounts {count, count_present, scanned_count, scanned_present}` in 32-bit signed range |
| `dynamo_response_capacity` | `DynamoCapacity` from `ConsumedCapacity` (object or first array element): TableName, CapacityUnits, Read/WriteCapacityUnits kept as text; `Table` breakdown; `GlobalSecondaryIndexes` + `LocalSecondaryIndexes` collected as parallel `index_names/index_units/index_read_units/index_write_units` |
| `dynamo_response_unprocessed_items` | `DynamoUnprocessed {present, table_names, payloads}` from `UnprocessedItems` (payload verbatim) |
| `dynamo_response_unprocessed_keys` | same for `UnprocessedKeys` |
| `dynamo_response_error` | `DynamoApiError {has_error, error_type, message}` from `__type` / `message` |
| `dynamo_response_is_error` | predicate wrapper |

## 11. Error catalog (message -> meaning)

Format rule: `<context> at offset <N>` with N a byte offset into the input.
Offset-less errors are noted.

Scanner/parse:

| Message | Meaning |
|---------|---------|
| `dynamo: bad span at offset N` | a < 0, b > len or a > b |
| `dynamo: json too large` | input above 1 MiB |
| `dynamo: nesting too deep at offset N` | depth > 32 |
| `dynamo: attribute value must be an object at offset N` | expected `{` |
| `dynamo: truncated attribute value at offset N` | ended after `{` |
| `dynamo: attribute value object is empty at offset N` | `{}` |
| `dynamo: unknown attribute value type: <T> at offset N` | unregistered type member |
| `dynamo: expected ':' at offset N` | missing type/value colon |
| `dynamo: expected true or false at offset N` | NULL/BOOL payload |
| `dynamo: NULL must be true at offset N` | `{"NULL":false}` |
| `dynamo: attribute value must close with '}' at offset N` | trailing member/truncation |
| `dynamo: trailing bytes after attribute value at offset N` | extra input after the value |
| `dynamo: trailing bytes after item at offset N` | extra input after the item |

String decoding (context is the call site, e.g. `string value`,
`attribute value type`, `map key`, `set member`):

| Message | Meaning |
|---------|---------|
| `<ctx> truncated at offset N` / `<ctx> expected string at offset N` | missing/absent string |
| `<ctx> unterminated string at offset N` | no closing quote |
| `<ctx> truncated escape at offset N` | `\` at end |
| `<ctx> bad escape at offset N` | unknown escape letter |
| `<ctx> truncated unicode escape at offset N` | short `\uXXXX` |
| `<ctx> bad unicode escape at offset N` | non-hex `\uXXXX` |
| `<ctx> unicode escape is NUL at offset N` | `\u0000` (cannot live in a Str) |
| `<ctx> truncated surrogate pair at offset N` | high surrogate then end |
| `<ctx> lone surrogate at offset N` | unpaired high/low surrogate |
| `<ctx> control byte in string at offset N` | raw byte < 0x20 inside string |

Sets/lists/maps/items:

| Message | Meaning |
|---------|---------|
| `dynamo: set must be an array at offset N` | NS/SS/BS payload not `[` |
| `dynamo: empty set at offset N` | `[]` (DynamoDB forbids empty sets) |
| `dynamo: truncated set at offset N` | unterminated set |
| `dynamo: expected ',' or ']' in set at offset N` | syntax |
| `dynamo: duplicate set member at offset N` | repeated member |
| `dynamo: list must be an array at offset N` | L payload not `[` |
| `dynamo: truncated list at offset N` | unterminated list |
| `dynamo: expected ',' or ']' in list at offset N` | syntax |
| `dynamo: map must be an object at offset N` | M payload not `{` |
| `dynamo: empty attribute name at offset N` | `""` key |
| `dynamo: duplicate attribute name at offset N` | repeated key in one map |
| `dynamo: expected ':' in map at offset N` | syntax |
| `dynamo: truncated map at offset N` | unterminated map |
| `dynamo: expected ',' or '}' in map at offset N` | syntax |

Numbers/base64: the catalogs of section 7.

Builders:

| Message | Meaning |
|---------|---------|
| `dynamo: set kind must be SS, NS or BS` | push_set kind |
| `dynamo: empty set` / `dynamo: duplicate set member` | push_set contents |
| `dynamo: list item is not a node index` | node out of range |
| `dynamo: map keys/values length mismatch` / `dynamo: empty map key` / `dynamo: duplicate map key` / `dynamo: map value is not a node index` | push_map contents |

Requests: `<what> is missing` / `<what> must be a map item` for `GetItem
Key`, `PutItem Item`, `UpdateItem Key`, `DeleteItem Key`, `Query
ExclusiveStartKey`, `Scan ExclusiveStartKey`; `dynamo: UpdateItem needs an
UpdateExpression or AttributeUpdates`; `dynamo: empty attribute name`;
`dynamo: attribute update action must be PUT, DELETE or ADD`; `dynamo:
attribute update value is missing`; `dynamo: duplicate attribute update:
<name>`; `dynamo: empty expression attribute name placeholder`; `dynamo:
duplicate expression attribute name placeholder: <k>`; `dynamo: empty
expression attribute value placeholder`; `dynamo: expression attribute
value is missing`; `dynamo: duplicate expression attribute value
placeholder: <k>`; `dynamo: duplicate batch table: <name>`; `dynamo: batch
request has no tables`; `dynamo: batch table has no keys: <name>`; `dynamo:
batch table has no requests: <name>`; `dynamo: batch key needs a table
first`; `dynamo: batch key must be a map item`; `dynamo: batch item must be
a map item`; `dynamo: batch request needs a table first`; `dynamo: transact
item must be a map item`; `dynamo: transact key must be a map item`;
`dynamo: transact update needs an UpdateExpression`; `dynamo: transact
condition check needs a ConditionExpression`; `dynamo: transact request has
no items`; `dynamo: value is not a B attribute value`.

Response helpers: `dynamo: json empty key`; `dynamo: json too large`;
`dynamo: response is not a JSON object at offset N`; `dynamo: json control
byte at offset N`; `dynamo: json key not found: <key>`; `dynamo: json
expected ':' after key at offset N`; `dynamo: json bad value at offset N`;
`dynamo: json truncated escape at offset N`; `dynamo: json unterminated
string at offset N`; `dynamo: json unterminated value at offset N`;
`dynamo: Items must be an array at offset N`; `dynamo: truncated Items
array at offset N`; `dynamo: expected ',' or ']' in Items at offset N`;
`dynamo: expected JSON object at offset N`; `dynamo: empty response key at
offset N`; `dynamo: expected ':' in object at offset N`; `dynamo: truncated
object at offset N`; `dynamo: expected ',' or '}' in object at offset N`;
`dynamo: expected integer at offset N`; `dynamo: integer out of range at
offset N`.

## 12. Not implemented (honest limits)

- SigV4 signing, endpoints, retries, pagination, credential handling.
- Conditional expression evaluation or expression syntax validation
  (`KeyConditionExpression` etc. are opaque strings).
- Full response schema validation: response helpers locate members rather
  than validate the whole document; `LastEvaluatedKey` and counts silently
  report `present = false` when malformed.
- Number precision/range enforcement (38 digits, exponent limits), set size
  limits and duplicate handling beyond parse-time duplicate rejection.
- `ReturnConsumedCapacity` / `ReturnValues` value vocabulary is not
  validated (rendered as given when non-empty).
