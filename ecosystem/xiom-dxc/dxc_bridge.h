#ifndef XIOM_DXC_BRIDGE_H_
#define XIOM_DXC_BRIDGE_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int64_t xiom_dxc_create_instance(int64_t clsid_ptr, int64_t iid_ptr, int64_t ppv_ptr);

int64_t xiom_dxc_clsid_compiler(void);
int64_t xiom_dxc_clsid_utils(void);
int64_t xiom_dxc_clsid_library(void);
int64_t xiom_dxc_clsid_validator(void);
int64_t xiom_dxc_clsid_linker(void);
int64_t xiom_dxc_clsid_assembler(void);
int64_t xiom_dxc_clsid_container_reflection(void);
int64_t xiom_dxc_clsid_optimizer(void);
int64_t xiom_dxc_clsid_container_builder(void);
int64_t xiom_dxc_clsid_compiler_args(void);

int64_t xiom_dxc_iid_compiler3(void);
int64_t xiom_dxc_iid_utils(void);
int64_t xiom_dxc_iid_result(void);
int64_t xiom_dxc_iid_blob(void);
int64_t xiom_dxc_iid_blob_encoding(void);
int64_t xiom_dxc_iid_blob_utf8(void);
int64_t xiom_dxc_iid_blob_wide(void);
int64_t xiom_dxc_iid_include_handler(void);
int64_t xiom_dxc_iid_operation_result(void);
int64_t xiom_dxc_iid_validator(void);
int64_t xiom_dxc_iid_validator2(void);
int64_t xiom_dxc_iid_linker(void);
int64_t xiom_dxc_iid_assembler(void);
int64_t xiom_dxc_iid_container_reflection(void);
int64_t xiom_dxc_iid_container_builder(void);
int64_t xiom_dxc_iid_compiler_args(void);
int64_t xiom_dxc_iid_extra_outputs(void);
int64_t xiom_dxc_iid_version_info(void);
int64_t xiom_dxc_iid_version_info2(void);
int64_t xiom_dxc_iid_version_info3(void);
int64_t xiom_dxc_iid_optimizer_pass(void);
int64_t xiom_dxc_iid_optimizer(void);
int64_t xiom_dxc_iid_pdb_utils(void);
int64_t xiom_dxc_iid_pdb_utils2(void);

#ifdef __cplusplus
}
#endif

#endif
