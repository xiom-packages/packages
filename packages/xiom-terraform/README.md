# xiom.terraform

Pure-XIOM infrastructure-as-code workflow model: an HCL subset parser, an
execution plan graph with per-attribute diffs, an apply/destroy state machine
with revision IDs, a state model (lineage + serial) and a provider registry.

There is **no** networking, no real provider, no FFI, no clock and no file
access. Everything is a deterministic transition over plain values, so a
configuration string plus a state value always produce the same plan and the
same state.

## Modules

| Module | Description |
|--------|-------------|
| `xiom.terraform` | HCL subset parsing, plan graph, state machine, provider registry |

## Install

```
xiom pkg add xiom.terraform
```

Depends on `xiom.std` (`>=0.60.0 <1.0.0`), which is a platform dependency and
excluded from the registry install closure.

## Quick start

```xiom
use xiom.terraform;

fn main() -> Int {
  let r = hcl_parse(
    "resource \"aws_instance\" \"web\" {\n  ami = \"ami-123\"\n}\n"
  );
  match r {
    Ok(cfg) => {
      let p = config_block_index(&cfg, "resource", "aws_instance/web");
      io.println(config_resource_address(&cfg, 0));
      let plan = plan_new();
      let e = plan_add_change(&mut plan, "aws_instance.web", TF_ACTION_CREATE, "new");
      let s = state_new("lineage-1");
      match s {
        Ok(st) => { /* state_apply_plan(&mut st, &plan) ... */ },
        Err(e) => { io.println(e); },
      }
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## API surface

* **HCL** -- `hcl_parse`, `hcl_kind`, `hcl_is_interp`, `hcl_ref_root`,
  `hcl_split_list`, `hcl_list_count`, `hcl_list_item`, `hcl_map_count`,
  `hcl_map_key`, `hcl_map_value`, `hcl_map_get`, `hcl_quote`.
* **Config** -- `config_block_count`, `config_block_type`,
  `config_block_labels`, `config_block_label_count`, `config_block_label`,
  `config_block_label_list`, `config_block_line`, `config_block_parent`,
  `config_block_index`, `config_nth_block`, `config_block_attr_count`,
  `config_block_attr_name`, `config_block_attr_kind`,
  `config_block_attr_value`, `config_attr_count`, `config_attr_name`,
  `config_attr_kind`, `config_attr_value`, `config_attr_line`,
  `config_attr_owner`, `config_attr_index`, `config_attr_get`,
  `config_attr_get_kind`, `config_resource_count`,
  `config_resource_address`, `config_render`.
* **Plan** -- `plan_new`, `plan_add_change`, `plan_add_diff`, `plan_add_dep`,
  `plan_count`, `plan_addr`, `plan_action`, `plan_action_name`, `plan_reason`,
  `plan_diff_count`, `plan_change_diff_count`, `plan_diff_owner`,
  `plan_diff_attr`, `plan_diff_before`, `plan_diff_after`, `plan_order`,
  `plan_has_cycle`, `plan_summary`, `plan_render`.
* **State** -- `state_new`, `state_add_resource`, `state_count`,
  `state_live_count`, `state_addr`, `state_status`, `state_rev`,
  `state_serial`, `state_lineage`, `state_index`, `state_has`,
  `state_status_name`, `state_can_transition`, `state_transition`,
  `state_apply_plan`, `state_destroy_plan`, `state_destroy_all`,
  `state_render`.
* **Providers** -- `providers_new`, `provider_register`, `provider_count`,
  `provider_index`, `provider_name`, `provider_source`, `provider_version`,
  `provider_is_initialized`, `provider_init`, `provider_init_all`,
  `provider_init_count`, `provider_is_ready`, `providers_from_config`,
  `provider_missing_from_config`, `provider_apply_config`, `provider_render`.

The supported HCL subset and the full error catalog are documented in
[SPEC.md](SPEC.md).

## Conformance

`tests/test_conformance.xi` (24 checks) is deterministic and uses inline HCL
fixtures only. Run it with the porter:

```
.\scripts\port.ps1 -Package xiom-terraform -TimeoutSec 60
```
