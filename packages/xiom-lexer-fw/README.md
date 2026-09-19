# xiom.lexer-fw

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** Framework for building lexical analyzers and token streams.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `token` | Token type definitions and metadata |
| `lexer` | Core character-scanning engine |
| `patterns` | Regex-free matchers for identifiers, numbers, and strings |
| `keywords` | Keyword table and reserved-word handling |
| `tokens_stream` | Buffered token streaming with lookahead |
| `errors` | Lexical error reporting and recovery |
