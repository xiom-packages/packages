# xiom-alerting

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** Alert rules, evaluation, deduplication, and notification routing.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `rule` | Alert rule definition and conditions |
| `evaluate` | Threshold and expression evaluation |
| `dedupe` | Grouping and deduplication |
| `notify` | Notification channel dispatch |
| `status` | Incident state and acknowledgement |
