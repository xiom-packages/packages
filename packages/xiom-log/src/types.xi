module xiom.log.types

pub enum LogLevel { Trace, Debug, Info, Warn, Error, Fatal }

pub type LogField = { key: Str; value: Str; }

pub type LogEntry = {
  level: LogLevel;
  message: Str;
  module: Str;
  timestamp: Int;
  fields: Vec[LogField];
}

pub type LoggerConfig = {
  min_level: LogLevel;
  include_timestamp: Bool;
  include_module: Bool;
  output_json: Bool;
}

pub fn log_config_default() -> LoggerConfig {
  LoggerConfig {
    min_level: LogLevel.Info,
    include_timestamp: true,
    include_module: true,
    output_json: false,
  }
}

pub fn log_level_to_str(level: &LogLevel) -> Str {
  match level {
    Trace => "TRACE",
    Debug => "DEBUG",
    Info => "INFO",
    Warn => "WARN",
    Error => "ERROR",
    Fatal => "FATAL",
  }
}

pub fn log_level_ordinal(level: &LogLevel) -> Int {
  match level {
    Trace => 0,
    Debug => 1,
    Info => 2,
    Warn => 3,
    Error => 4,
    Fatal => 5,
  }
}

pub fn log_entry_new(level: LogLevel, message: Str) -> LogEntry {
  LogEntry {
    level: level,
    message: message,
    module: "",
    timestamp: 0,
    fields: Vec[LogField].new(),
  }
}
