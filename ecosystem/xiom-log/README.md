# xiom-log

Structured logging library for XIOM with six log levels and dual text/JSON output.

## Installation

```xiom
deps: { "xiom-log": "0.1.0" };
```

## Usage

### Basic Logging

```xiom
let config = log_config_default();
let logger = logger_new(&config);

logger_info(&mut logger, "Server started");
logger_warn(&mut logger, "Disk usage at 85%");
logger_error(&mut logger, "Connection refused");

let output = logger_flush(&logger);
# 0 [INFO]: Server started
# 0 [WARN]: Disk usage at 85%
# 0 [ERROR]: Connection refused
```

### JSON Output

```xiom
let mut config = log_config_default();
config.output_json = true;
let logger = logger_new(&config);

logger_info(&mut logger, "User login");
let json = logger_flush(&logger);
# {"level":"INFO","message":"User login","timestamp":0}
```

### Structured Fields

```xiom
let mut entry = log_entry_new(LogLevel::Info, "Request processed");
entry.fields.push(LogField { key: "method"; value: "GET" });
entry.fields.push(LogField { key: "path"; value: "/api/users" });
entry.fields.push(LogField { key: "status"; value: "200" });

logger_log(&mut logger, entry);
```

### Level Filtering

```xiom
let mut config = log_config_default();
config.min_level = LogLevel::Warn;
let logger = logger_new(&config);

logger_debug(&mut logger, "Debug info");   # discarded
logger_info(&mut logger, "General info");  # discarded
logger_warn(&mut logger, "Warning");       # logged
logger_error(&mut logger, "Error");        # logged
```

### Custom Formatting

```xiom
let entry = log_entry_new(LogLevel::Error, "Something broke");
let compact = format_compact(&entry);  # "ERROR Something broke"
let json = format_json(&entry);        # {"level":"ERROR","message":"Something broke","timestamp":0}
```

## Modules

| Module | Description |
|---|---|
| `xiom.log.types` | LogLevel enum, LogEntry, LogField, LoggerConfig types |
| `xiom.log.logger` | In-memory logger with level filtering and buffered output |
| `xiom.log.format` | Text, JSON, and compact formatters |

## Log Levels

| Level | Ordinal | Typical Use |
|---|---|---|
| Trace | 0 | Fine-grained debug tracing |
| Debug | 1 | Debugging information |
| Info | 2 | General operational messages |
| Warn | 3 | Warning conditions |
| Error | 4 | Error conditions |
| Fatal | 5 | Fatal errors requiring shutdown |

## License

MIT
