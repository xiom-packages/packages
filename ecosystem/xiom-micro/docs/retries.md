# Retries

> Status: Design stage — specification only, not yet implemented.

Retries are the most misused resilience primitive: done naively, they turn a small downstream blip into a self-inflicted retry storm that keeps the failing service down. `xiom-micro` treats retries as a budgeted, explicit policy rather than an automatic behavior. The `retry.xi` module owns the policy and stop conditions; `backoff.xi` owns the timing (exponential growth, max delay, and jitter).

The first rule is **safety classification**. A call is only eligible for retry if it is idempotent or otherwise safe to repeat. This is enforced by contract at the call boundary — you cannot silently retry a non-idempotent `POST` just because it failed. Pairing retries with idempotency keys (see [idempotency.md](idempotency.md)) makes even at-least-once delivery safe against duplicates.

The second rule is **budgets**. Every retry policy requires a `RetryBudget`: a bounded pool of retry tokens shared across calls to a dependency. When the budget is exhausted, retries stop, even if the per-call attempt count has not been reached. This caps the *aggregate* retry amplification a client can inflict, which is what actually prevents cascading failure. Individual policies also stop after a bounded number of attempts (`RetryPolicy.exponential(max_attempts)`).

The third rule is **jitter and visibility**. Backoff always adds jitter so retrying clients desynchronize instead of retrying in lockstep. And retries are never hidden from metrics — every attempt, budget draw, and give-up is observable. In XIOM terms: retry decisions are typed, budgeted, and contract-checked, so "the system quietly retried 40 times" can never be a surprise you discover in production.
