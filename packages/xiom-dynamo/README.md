# xiom.dynamo

> **Status:** `incubating` -- conformance-tested (21/21); published at `v0.1.1` on the XIOM registry.

Pure-XIOM codec for the Amazon DynamoDB JSON (wire) API shapes. It parses,
validates and renders the payloads a DynamoDB client exchanges over its own
HTTPS transport: AttributeValue objects, items, request shapes and response
shapes.

- **No network**: the module never opens a socket.
- **No signing**: SigV4 request signing and credentials are caller concerns.
- **No floats**: numbers stay exact decimal text (`N`/`NS`), capacity units
  are returned as text, so no rounding is introduced anywhere.
- Version: 0.1.0. Tests: 21 conformance checks (`port.ps1` green).

## Surface

| Area | Functions |
|------|-----------|
| Version/limits | `dynamo_version`, `dynamo_max_json_bytes`, `dynamo_item_max_bytes` |
| AttributeValue kinds | `dynamo_av_s`, `dynamo_av_n`, `dynamo_av_b`, `dynamo_av_ss`, `dynamo_av_ns`, `dynamo_av_bs`, `dynamo_av_m`, `dynamo_av_l`, `dynamo_av_null`, `dynamo_av_bool`, `dynamo_av_kind_name`, `dynamo_av_kind_is_set` |
| AttributeValue codec | `dynamo_av_parse`, `dynamo_av_parse_str`, `dynamo_av_render` |
| Number text | `dynamo_number_check`, `dynamo_number_is_valid` |
| Base64 (B/BS) | `dynamo_base64_encode`, `dynamo_base64_decode`, `dynamo_base64_is_valid` |
| Tape builders | `dynamo_value_new`, `dynamo_value_push_string/number/binary/bool/null/set/list/map`, `dynamo_value_merge`, `dynamo_value_render`, `dynamo_value_count` |
| Item codec | `dynamo_item_parse`, `dynamo_item_parse_str`, `dynamo_item_render`, `dynamo_item_new_map`, `dynamo_item_wrap` |
| Item accessors | `dynamo_item_kind`, `dynamo_item_kind_name`, `dynamo_item_string`, `dynamo_item_number_text`, `dynamo_item_number_int_text/frac_text/exp_text`, `dynamo_item_bool`, `dynamo_item_is_null`, `dynamo_item_binary`, `dynamo_item_map_len/key_at/node_at/get_node/get`, `dynamo_item_list_len/node_at/get`, `dynamo_item_set_len/text_at` |
| Requests | `dynamo_get_item_*`, `dynamo_put_item_*`, `dynamo_update_item_*`, `dynamo_delete_item_*`, `dynamo_query_*`, `dynamo_scan_*`, `dynamo_batch_get_*`, `dynamo_batch_write_*`, `dynamo_transact_*` |
| Responses | `dynamo_response_span/has/item/items/last_key/counts/capacity/unprocessed_items/unprocessed_keys/error/is_error` |
| Validation | `dynamo_table_name_check/is_valid`, `dynamo_key_name_check/is_valid`, `dynamo_item_check` |

## Usage

Parsing and reading an item:

```xiom
use xiom.dynamo;
use xiom.string.compare;

let r = dynamo_item_parse_str("{\"uid\":{\"S\":\"ada\"},\"score\":{\"N\":\"12.5\"}}");
if r.is_ok {
  let item: DynamoItem = r.value;
  let uid = dynamo_item_map_get(&item, "uid");
  let name = dynamo_item_string(&uid);            // "ada"
  let score = dynamo_item_map_get(&item, "score");
  let int_part = dynamo_item_number_int_text(&score);   // "12"
  let frac = dynamo_item_number_frac_text(&score);      // "5"
}
```

Rendering a GetItem request body (wire JSON; sign it yourself):

```xiom
let key_r = dynamo_item_parse_str("{\"uid\":{\"S\":\"ada\"}}");
let key: DynamoItem = key_r.value;
var req = dynamo_get_item_new("my_table", key);
req.consistent_read = true;
let body = dynamo_get_item_render(&req);      // Ok({"TableName":...})
```

Reading a response:

```xiom
let resp = /* bytes of the HTTP body */;
let item_r = dynamo_response_item(&resp);     // Ok(DynamoItem)
let cap = dynamo_response_capacity(&resp);    // ConsumedCapacity, table/index breakdown
let err = dynamo_response_error(&resp);       // {__type, message}
```

## Honest limits

- **Response scanning, not full response decoding.** The response helpers
  locate top-level members with a bounded, escape-aware scanner; they do not
  validate the entire response document. `UnprocessedItems` /
  `UnprocessedKeys` values are returned as verbatim JSON text.
- **JSON only.** The wire codec speaks the DynamoDB JSON protocol (the
  `{"S": ...}` envelope form), not the low-level AttributeValue API wire
  format.
- **Caller-owned concerns**: endpoints, SigV4 signing, retries, pagination,
  credential refresh, and DynamoDB semantics (conditional expression
  evaluation) are out of scope.
- Item size validation is a byte-count check against the documented 400KB
  cap; a parsed item larger than `dynamo_max_json_bytes()` is rejected as
  `dynamo: json too large`.
- Attribute names are validated as non-empty and unique inside their map;
  the key/table-name charset rule (3..255, `[a-zA-Z0-9_.-]`) is exposed as
  helper functions and enforced by the request renders, not by item parsing.

See `SPEC.md` for the exact grammar, shapes and the error catalog.
