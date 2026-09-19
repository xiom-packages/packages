# xiom.autoscale

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** Auto-scaling policies, capacity decisions, and scaling actions for compute targets.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `policy` | Scaling policy definition |
| `metric_source` | Utilization metric collection |
| `decision` | Scale up/down decision logic |
| `action` | Scale action execution and cooldown |
| `schedule` | Scheduled and predicted scaling |
