# xiom-l10n-currency

> **Status:** PLACEHOLDER — reserved, spec pending. No implementation yet.
> **Scope:** Locale-aware currency amount formatting, symbol resolution, and code/display-name lookup.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `currency_format` | Format monetary amounts with locale symbols and minor units. |
| `currency_symbols` | Resolve ISO 4217 codes to symbols and display names. |
| `currency_codes` | ISO 4217 currency code metadata registry. |
| `currency_round` | Minor-unit and cash-rounding rules per currency. |
