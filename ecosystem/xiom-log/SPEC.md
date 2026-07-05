# xiom-log SPEC

## Package Overview
`xiom-log` is a structured, leveled logging library for the XIOM language. It supports six log levels, text and JSON output formats, configurable filtering, and field-based structured data.

## Modules

### `xiom.log.types` — Log Types and Configuration
**Enum:** `LogLevel { Trace, Debug, Info, Warn, Error, Fatal }`

| Type | Fields |
|---|---|
| `LogEntry` | `level: LogLevel; message: Str; module: Str; timestamp: Int; fields: Vec[LogField];` |
| `LogField` | `key: Str; value: Str;` |
| `LoggerConfig` | `min_level: LogLevel; include_timestamp: Bool; include_module: Bool; output_json: Bool;` |

**Constructors and Utilities:**
| Function | Signature | Description |
|---|---|---|
| `log_config_default` | `() -> LoggerConfig` | Info level, timestamps on, module on, text output |
| `log_level_to_str` | `(level: &LogLevel) -> Str` | Converts level to uppercase string |
| `log_level_ordinal` | `(level: &LogLevel) -> Int` | Trace=0 ... Fatal=5 |
| `log_entry_new` | `(level: LogLevel, message: Str) -> LogEntry` | Entry with empty module, timestamp=0, no fields |

### `xiom.log.logger` — Logger Implementation
**Type:** `Logger = { config: LoggerConfig; entries: Vec[LogEntry]; }`

| Function | Signature | Description |
|---|---|---|
| `logger_new` | `(config: &LoggerConfig) -> Logger` | Creates logger from config |
| `logger_log` | `(logger: &mut Logger, entry: LogEntry)` | Logs entry if level >= min_level |
| `logger_trace` | `(logger: &mut Logger, msg: Str)` | Convenience for Trace level |
| `logger_debug` | `(logger: &mut Logger, msg: Str)` | Convenience for Debug level |
| `logger_info` | `(logger: &mut Logger, msg: Str)` | Convenience for Info level |
| `logger_warn` | `(logger: &mut Logger, msg: Str)` | Convenience for Warn level |
| `logger_error` | `(logger: &mut Logger, msg: Str)` | Convenience for Error level |
| `logger_fatal` | `(logger: &mut Logger, msg: Str)` | Convenience for Fatal level |
| `logger_flush` | `(logger: &Logger) -> Str` | Formats all buffered entries as text or JSON |
| `logger_clear` | `(logger: &mut Logger)` | Clears all buffered entries |

**Level Filtering:**
Entries below `config.min_level` are silently discarded. Comparison uses ordinal values: Trace(0) < Debug(1) < Info(2) < Warn(3) < Error(4) < Fatal(5).

### `xiom.log.format` — Output Formatters
| Function | Signature | Description |
|---|---|---|
| `format_text` | `(entry: &LogEntry, config: &LoggerConfig) -> Str` | Standard text format with optional timestamp and module |
| `format_json` | `(entry: &LogEntry) -> Str` | JSON object with level, message, module, timestamp, fields |
| `format_compact` | `(entry: &LogEntry) -> Str` | Single-line: `LEVEL message` |

**Text Format Example:**
```
1700000000 [INFO] my_module: Operation completed key=value status=ok
```

**JSON Format Example:**
```json
{"level":"INFO","message":"Operation completed","module":"my_module","timestamp":1700000000,"fields":{"key":"value","status":"ok"}}
```

## Error Handling
No fallible operations. All functions return direct values. The logger is append-only in memory; `logger_flush` serializes the buffer without clearing it.

## Dependencies
- `xiom-std` (0.1.0): Vec, Int, Str, Bool types and basic operations.

## Design Constraints
- No `for` loops — iteration over entries and fields uses tail-recursive helpers.
- No `self` methods — logger state is passed explicitly as `&Logger` or `&mut Logger`.
- `Match` uses bare variant names in pattern arms.
- String building uses `+` concatenation; no mutable string buffers in pure formatters.
