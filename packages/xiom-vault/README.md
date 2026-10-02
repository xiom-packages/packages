# xiom.vault

> **Status:** `incubating` -- conformance-tested (28/28); published at `v0.1.0` on the XIOM registry.
> **Scope:** secret-vault integration MODEL (Vault-shaped). Pure XIOM: no
> HTTP, no FFI, no cryptography, no token generation, no I/O.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.builder`,
> `xiom.string.compare`, `xiom.encoding.hex`).

## What it is

`xiom.vault` models the deterministic structure of a Hashicorp-Vault-style
secret backend integration:

* **API client model** (`xiom.vault.client`): request method codes, path
  normalization, query strings, case-insensitive headers with the
  `X-Vault-Token` header, a flat JSON-ish body builder with string escaping,
  and a response envelope (status + verbatim body).
* **Raw key lookup** (`xiom.vault.json`): a bounded flat-JSON scanner with a
  depth cap, typed getters (`get_str`, `get_raw`, `get_int`, `get_bool`,
  `get_strs`) and byte offsets for every failure.
* **KV secrets engine** (`xiom.vault.kv`): v1/v2 path builders
  (`data` / `metadata` / `delete` / `undelete` / `destroy`), the
  `version=N` read query, a `{"versions":[...]}` body, ready-to-send request
  builders, and a per-version **state ledger** for the soft-delete model
  (absent -> live -> soft-deleted -> live; destroy is terminal and
  irreversible; delete/undelete/destroy are idempotent where Vault is).
* **Unseal and Shamir sharing** (`xiom.vault.unseal`): GF(256) arithmetic
  modulo `0x11B`, split with caller-supplied coefficients or a deterministic
  seed, Lagrange recombination at x = 0, hex rendering, and an unseal
  progress counter with rejected-share reset.
* **Auth models** (`xiom.vault.auth`): token payload parsing
  (client_token / accessor / token_type / policies / lease_duration /
  renewable / entity_id), policy membership and root detection, lookup /
  renew / revoke request builders, AppRole UUID validation, the
  `auth/<mount>/login` request body, and parsing the nested `auth` object of
  a login response.
* **Policy management** (`xiom.vault.policy`): capability bitmasks
  (create/read/update/delete/list/sudo/deny/patch), policy rules as parallel
  vectors, glob matching (`*` any run, `+` within one segment) with an
  iterative DP matcher, and longest-prefix rule resolution where DENY wins.
* **Composed client** (`xiom.vault`, the entry module): health / seal-status /
  mounts requests and KV v2 CRUD + AppRole login builders with token-header
  plumbing.

It does **not** send requests, compute hashes or signatures, generate tokens,
manage leases, or encode URLs. Secrets are carried as bytes or hex strings;
no `Vec[Float64]` and no floating point appear anywhere.

## Install / manifest

```xiom
package xiom_vault {
  name: "xiom.vault";
  version: "0.1.0";
  modules: ["xiom.vault", "xiom.vault.kv", "xiom.vault.unseal",
            "xiom.vault.auth", "xiom.vault.policy", "xiom.vault.client",
            "xiom.vault.json", "xiom.vault.core"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
```

## Usage

Build a KV v2 read with a pinned version and a token header:

```xiom
use xiom.vault;

let r = vault_kv2_read("secret", "app/config", 2, "s.mytoken");
if r.is_ok {
  // request method GET, target "/secret/data/app/config?version=2",
  // X-Vault-Token attached
}
```

Look up a field in a raw response body:

```xiom
use xiom.vault.json;

let b = "{\"auth\":{\"client_token\":\"s.abc\",\"lease_duration\":60}}";
let r = vault_json_get_int(b, "lease_duration");   // Ok(60)
```

Split and recombine a secret (known-answer friendly):

```xiom
use xiom.vault.unseal;

let shares = vault_shamir_split(&secret_bytes, 5, 3, 42);
let back = vault_shamir_combine(&shares, secret_bytes.len());
```

Evaluate a policy decision:

```xiom
use xiom.vault.policy;

var p = vault_policy_new();
vault_policy_add(&mut p, "secret/*", VAULT_CAP_READ | VAULT_CAP_LIST);
vault_policy_can(&p, "secret/data/app", VAULT_CAP_READ);   // true
```

## API areas

| Area | Module | Examples |
|------|--------|----------|
| Requests / body | `xiom.vault.client` | `vault_request_new`, `vault_request_set_query`, `vault_request_set_header`, `vault_body_add_str`, `vault_body_render`, `vault_response_new` |
| JSON lookup | `xiom.vault.json` | `vault_json_lookup`, `vault_json_get_str`, `vault_json_get_int`, `vault_json_get_strs` |
| KV engine | `xiom.vault.kv` | `vault_kv2_data_path`, `vault_kv2_read_request`, `vault_kv2_versions_body`, `vault_kv_versions_apply` |
| Shamir / unseal | `xiom.vault.unseal` | `vault_gf_mul`, `vault_shamir_split`, `vault_shamir_combine`, `vault_unseal_submit` |
| Auth | `xiom.vault.auth` | `vault_token_parse`, `vault_token_is_root`, `vault_token_renew_request`, `vault_approle_login_request` |
| Policy | `xiom.vault.policy` | `vault_capability_set`, `vault_policy_add`, `vault_policy_path_matches`, `vault_policy_decision` |
| Composed | `xiom.vault` | `vault_health_request`, `vault_kv2_read`, `vault_kv2_write`, `vault_kv2_soft_delete`, `vault_approle_login` |

## Testing

```powershell
.\scripts\port.ps1 -Package xiom.vault -TimeoutSec 60
```

The suite (`tests/test_conformance.xi`, 28 checks) is fully deterministic and
uses no external files: method/path/header/body codecs, JSON scanner spans and
escapes, KV path shapes, the version state machine, GF(256) known answers,
Shamir reconstruct-from-any-threshold plus duplicate/zero-share rejection,
unseal progress, token/AppRole models, capability sets and glob/decision
tables. `SPEC.md` documents the exact semantics, the error catalog and the
coverage map.

## Notes

The module targets XIOM compiler v0.62.2 and follows the package family style:
free functions, parallel `Vec` fields instead of vectors of structs, leaf
`Ok`/`Err` helpers, and hex/byte-oriented secrets. Two compiler facts shaped
the layout: child modules cannot import their parent on v0.62.2 (so base code
lives in sibling modules and only the entry module imports downward), and
local `Vec[Str]` pushes are used in place of module-level vectors.

## License

MIT OR Apache-2.0
