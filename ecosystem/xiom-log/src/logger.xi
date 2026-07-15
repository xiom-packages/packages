module xiom.log.logger

use xiom.log.types;
use xiom.log.format;

pub type Logger = {
  config: LoggerConfig;
  entries: Vec[LogEntry];
}

pub fn logger_new(config: &LoggerConfig) -> Logger {
  Logger {
    config: LoggerConfig {
      min_level: config.min_level,
      include_timestamp: config.include_timestamp,
      include_module: config.include_module,
      output_json: config.output_json,
    },
    entries: Vec[LogEntry].new(),
  }
}

fn logger_should_log(logger: &Logger, entry: &LogEntry) -> Bool {
  log_level_ordinal(&entry.level) >= log_level_ordinal(&logger.config.min_level)
}

pub fn logger_log(logger: &mut Logger, entry: LogEntry) {
  if logger_should_log(logger, &entry) {
    logger.entries.push(entry);
  }
}

pub fn logger_trace(logger: &mut Logger, msg: Str) {
  let entry = log_entry_new(LogLevel.Trace, msg);
  logger_log(logger, entry);
}

pub fn logger_debug(logger: &mut Logger, msg: Str) {
  let entry = log_entry_new(LogLevel.Debug, msg);
  logger_log(logger, entry);
}

pub fn logger_info(logger: &mut Logger, msg: Str) {
  let entry = log_entry_new(LogLevel.Info, msg);
  logger_log(logger, entry);
}

pub fn logger_warn(logger: &mut Logger, msg: Str) {
  let entry = log_entry_new(LogLevel.Warn, msg);
  logger_log(logger, entry);
}

pub fn logger_error(logger: &mut Logger, msg: Str) {
  let entry = log_entry_new(LogLevel.Error, msg);
  logger_log(logger, entry);
}

pub fn logger_fatal(logger: &mut Logger, msg: Str) {
  let entry = log_entry_new(LogLevel.Fatal, msg);
  logger_log(logger, entry);
}

pub fn logger_flush(logger: &Logger) -> Str {
  logger_flush_entries(logger, 0, "")
}

fn logger_flush_entries(logger: &Logger, idx: Int, acc: Str) -> Str {
  if idx >= logger.entries.len() {
    acc
  } else {
    let entry = &logger.entries[idx];
    let formatted = if logger.config.output_json {
      format_json(entry)
    } else {
      format_text(entry, &logger.config)
    };
    let new_acc = if acc.len() > 0 { acc + "\n" + formatted } else { formatted };
    logger_flush_entries(logger, idx + 1, new_acc)
  }
}

pub fn logger_clear(logger: &mut Logger) {
  logger.entries = Vec[LogEntry].new();
}
