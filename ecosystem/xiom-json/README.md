# xiom-json

> Pure XIOM JSON parser, serializer, and manipulation library. Zero dependencies.

[![XIOM](https://img.shields.io/badge/XIOM-v0.22.1-blue)](https://github.com/xiom-lang/XIOM)
[![License](https://img.shields.io/badge/license-MIT%2FApache--2.0-blue.svg)](LICENSE)

## Overview

xiom-json is a production-grade JSON library written entirely in pure XIOM. It provides a complete recursive descent parser, pretty-printer, JSONPath query engine, and schema validator — all guarded by compile-time contracts for zero-crash safety.

## Installation

```bash
xiom install xiom-json
```

Or add to your `package.xi`:
```xiom
deps: {
  "xiom-json": "0.1.0"
}
```

## Quick Start

```xiom
use xiom.json;

fn main() -> Int {
  let input = "{\"name\": \"XIOM\", \"version\": 1}";
  let value = json_parse(input).unwrap();
  let name = json_get(&value, "name").unwrap();
  return 0;
}
```

## API Reference

### Types
| Type | Description |
|------|-------------|
| `JsonValue` | Enum: Null, Bool, Number, String, Array, Object |
| `JsonEntry` | Key-value pair for Object entries |
| `ParseError` | Parse error with message and position |
| `JsonPath` | JSONPath query path (dot/bracket notation) |
| `JsonType` | Enum for type checking |

### Parsing & Serialization
| Function | Description |
|----------|-------------|
| `json_parse(input: Str)` | Parse JSON string → JsonValue |
| `json_stringify(value: &JsonValue)` | Compact JSON output |
| `json_stringify_pretty(value, config)` | Indented JSON output |
| `json_validate(input: Str)` | Validate JSON without building tree |

### Manipulation
| Function | Description |
|----------|-------------|
| `json_get(obj, key)` | Get value by key from Object |
| `json_get_path(root, path)` | Get value by JSONPath |
| `json_set(obj, key, value)` | Set key in Object |
| `json_set_path(root, path, value)` | Set value by JSONPath |
| `json_remove(obj, key)` | Remove key from Object |
| `json_has_key(obj, key)` | Check if key exists |
| `json_is_type(value, expected)` | Runtime type check |
| `json_merge(base, overlay)` | Deep merge two objects |
| `json_schema_validate(value, schema)` | Validate against JSON Schema (basic) |

### Constructors
| Function | Description |
|----------|-------------|
| `json_null()` | Create Null value |
| `json_bool(v)` | Create Bool value |
| `json_number(v)` | Create Number value |
| `json_string(v)` | Create String value |
| `json_array()` | Create empty Array |
| `json_object()` | Create empty Object |
| `json_array_push(arr, value)` | Append to Array |
| `json_object_put(obj, key, value)` | Insert into Object |

## Safety Contracts

Every public function is guarded by compile-time contracts:
- `json_parse`: requires input.len() > 0
- `json_get`: requires key.len() > 0
- `json_set`: requires key.len() > 0
All FFI boundaries are validated before execution.

## Production Readiness

| Feature | Status |
|---------|--------|
| JSON parse (RFC 8259) | ✅ Complete |
| JSON stringify (compact) | ✅ Complete |
| JSON stringify (pretty-print) | ✅ Complete |
| JSONPath query | ✅ Complete |
| JSON Schema validation (basic) | ✅ Complete |
| Deep merge | ✅ Complete |
| String escape sequences | ✅ Complete |
| Number parsing (int/float/sci) | ✅ Complete |
| Line/column error tracking | ✅ Complete |
| Streaming parser | ❌ Not yet |
| JSON Patch (RFC 6902) | ❌ Not yet |
| JSON Pointer (RFC 6901) | ❌ Not yet |

### What's Left for v1.0
1. **JSON Patch** — RFC 6902 operations (add/remove/replace/move/copy/test)
2. **JSON Pointer** — RFC 6901 pointer syntax for path access
3. **Streaming parser** — Parse large files incrementally
4. **Full JSON Schema** — Draft 2020-12 compliance (allOf, anyOf, oneOf, etc.)

## Dependencies

**None.** Pure XIOM. No C libraries, no FFI, no runtime dependencies.

## Links

- **Organization**: [github.com/xiom-lang](https://github.com/xiom-lang)
- **Language**: [github.com/xiom-lang/XIOM](https://github.com/xiom-lang/XIOM)
- **Issues**: [github.com/xiom-lang/xiom-json/issues](https://github.com/xiom-lang/xiom-json/issues)

## License

MIT OR Apache-2.0
