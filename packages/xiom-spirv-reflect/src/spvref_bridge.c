/* xiom.spirv-reflect probe bridge -- MIT OR Apache-2.0 (this file), XIOM Authors.
 *
 * The vendored SPIRV-Reflect sources (Vulkan SDK 1.4.350.0 export; Apache-2.0)
 * are compiled via port.args.json in C (meshopt pattern); this file adds the
 * `extern "C"` probe surface the XIOM module (spirvreflect.xi) calls.
 *
 * ABI discipline (B-11..B-20): every out-param is an XIOM-owned byte slot
 * written little-endian (wr_u32 / copy_str); strings are copied INTO owned
 * slots, never read back through foreign pointers from XIOM (B-20). All
 * reflection data (structs, binding pointer arrays, entry-point arrays) stays
 * inside this file; only scalars and copied strings cross the boundary.
 *
 * Resolve surface: kApi[] pins one function pointer per public C API function
 * so the suite can prove link-time resolution (resolved=N/N) in addition to
 * the functional probes below.
 *
 * Fixtures: two SPIR-V modules assembled once with
 *   "C:\VulkanSDK\1.4.350.0\Bin\spirv-as.exe" --target-env spv1.0
 * from tests/fixtures/minimal_frag.spvasm (fragment + input uv @location 0 +
 * output outColor + combined image sampler set 0/binding 0 + spec constant
 * "sc" SpecId 0) and tests/fixtures/ubo_frag.spvasm (uniform block "UBOBlock"
 * at set 0/binding 0). The words are embedded verbatim below so the suite
 * needs no file I/O; spvReflect* then reflects them at runtime.
 *
 * Probe surface (all return 0; out-params may be NULL):
 *   xspv_api_count            -> public C API function count (table size)
 *   xspv_resolve_all          -> table size + NULL-pointer count
 *   xspv_create_probe         -> create rc, stage/model/entry/code-size/lang/
 *                                version/generator, entry point "main"
 *   xspv_create2_probe        -> CreateShaderModule2 with NO_COPY flag
 *   xspv_descriptor_probe     -> binding/set enumeration counts + binding 0
 *   xspv_variable_probe       -> input/output/interface counts + fields
 *   xspv_entrypoint_probe     -> entry-point enumerate/get family
 *   xspv_get_probe            -> Get* family (rc + NULL behavior)
 *   xspv_alias_probe          -> deprecated aliases (GetShaderModule etc.)
 *   xspv_change_probe         -> Change* family + re-lookup after mutation
 *   xspv_spec_probe           -> specialization constant enumeration
 *   xspv_strings_probe        -> spvReflectSourceLanguage + type-name strings
 *   xspv_error_probe          -> bad SPIR-V paths (magic/size), NULL module
 *   xspv_free_chain_probe     -> create/destroy chain + destroy of empty
 */

#include "../vendor/spirv_reflect.h"

#include <string.h>

/* The 45-function surface intentionally includes the deprecated aliases
 * (they are part of the pinned C API); silence the headers' deprecation
 * attribute so the bridge builds warning-clean. */
#if defined(__clang__)
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#elif defined(_MSC_VER)
#pragma warning(disable : 4996)
#endif

/* tests/fixtures/minimal_frag.spvasm (148 words, 592 bytes). */
static const unsigned int kFragSpirv[148] = {
	0x07230203u, 0x00010000u, 0x00070000u, 0x00000015u, 0x00000000u, 0x00020011u, 0x00000001u, 0x0003000eu,
	0x00000000u, 0x00000001u, 0x0007000fu, 0x00000004u, 0x00000001u, 0x6e69616du, 0x00000000u, 0x00000002u,
	0x00000003u, 0x00030010u, 0x00000001u, 0x00000007u, 0x00030003u, 0x00000002u, 0x000001c2u, 0x00040005u,
	0x00000001u, 0x6e69616du, 0x00000000u, 0x00030005u, 0x00000002u, 0x00007675u, 0x00050005u, 0x00000003u,
	0x4374756fu, 0x726f6c6fu, 0x00000000u, 0x00030005u, 0x00000004u, 0x00786574u, 0x00030005u, 0x00000005u,
	0x00006373u, 0x00040047u, 0x00000002u, 0x0000001eu, 0x00000000u, 0x00040047u, 0x00000003u, 0x0000001eu,
	0x00000000u, 0x00040047u, 0x00000004u, 0x00000022u, 0x00000000u, 0x00040047u, 0x00000004u, 0x00000021u,
	0x00000000u, 0x00040047u, 0x00000005u, 0x00000001u, 0x00000000u, 0x00020013u, 0x00000006u, 0x00030021u,
	0x00000007u, 0x00000006u, 0x00030016u, 0x00000008u, 0x00000020u, 0x00040015u, 0x00000009u, 0x00000020u,
	0x00000000u, 0x00040017u, 0x0000000au, 0x00000008u, 0x00000002u, 0x00040017u, 0x0000000bu, 0x00000008u,
	0x00000004u, 0x00040020u, 0x0000000cu, 0x00000001u, 0x0000000au, 0x0004003bu, 0x0000000cu, 0x00000002u,
	0x00000001u, 0x00040020u, 0x0000000du, 0x00000003u, 0x0000000bu, 0x0004003bu, 0x0000000du, 0x00000003u,
	0x00000003u, 0x00090019u, 0x0000000eu, 0x00000008u, 0x00000001u, 0x00000000u, 0x00000000u, 0x00000000u,
	0x00000001u, 0x00000000u, 0x0003001bu, 0x0000000fu, 0x0000000eu, 0x00040020u, 0x00000010u, 0x00000000u,
	0x0000000fu, 0x0004003bu, 0x00000010u, 0x00000004u, 0x00000000u, 0x00040032u, 0x00000009u, 0x00000005u,
	0x0000002au, 0x0004002bu, 0x00000008u, 0x00000011u, 0x3f800000u, 0x0007002cu, 0x0000000bu, 0x00000012u,
	0x00000011u, 0x00000011u, 0x00000011u, 0x00000011u, 0x00050036u, 0x00000006u, 0x00000001u, 0x00000000u,
	0x00000007u, 0x000200f8u, 0x00000013u, 0x0004003du, 0x0000000fu, 0x00000014u, 0x00000004u, 0x0003003eu,
	0x00000003u, 0x00000012u, 0x000100fdu, 0x00010038u,
};

/* tests/fixtures/ubo_frag.spvasm (82 words, 328 bytes). */
static const unsigned int kUboSpirv[82] = {
	0x07230203u, 0x00010000u, 0x00070000u, 0x00000009u, 0x00000000u, 0x00020011u, 0x00000001u, 0x0003000eu,
	0x00000000u, 0x00000001u, 0x0005000fu, 0x00000004u, 0x00000001u, 0x6e69616du, 0x00000000u, 0x00030010u,
	0x00000001u, 0x00000007u, 0x00030003u, 0x00000002u, 0x000001c2u, 0x00040005u, 0x00000001u, 0x6e69616du,
	0x00000000u, 0x00050005u, 0x00000002u, 0x424f4255u, 0x6b636f6cu, 0x00000000u, 0x00050006u, 0x00000002u,
	0x00000000u, 0x6c616373u, 0x00000065u, 0x00030005u, 0x00000003u, 0x006f6275u, 0x00030047u, 0x00000002u,
	0x00000002u, 0x00050048u, 0x00000002u, 0x00000000u, 0x00000023u, 0x00000000u, 0x00040047u, 0x00000003u,
	0x00000022u, 0x00000000u, 0x00040047u, 0x00000003u, 0x00000021u, 0x00000000u, 0x00020013u, 0x00000004u,
	0x00030021u, 0x00000005u, 0x00000004u, 0x00030016u, 0x00000006u, 0x00000020u, 0x0003001eu, 0x00000002u,
	0x00000006u, 0x00040020u, 0x00000007u, 0x00000002u, 0x00000002u, 0x0004003bu, 0x00000007u, 0x00000003u,
	0x00000002u, 0x00050036u, 0x00000004u, 0x00000001u, 0x00000000u, 0x00000005u, 0x000200f8u, 0x00000008u,
	0x000100fdu, 0x00010038u,
};

#define XSPV_FRAG_BYTES ((int)(sizeof(kFragSpirv)))
#define XSPV_UBO_BYTES  ((int)(sizeof(kUboSpirv)))

static void wr_u32(unsigned char* dst, unsigned int v)
{
	if (dst == NULL) {
		return;
	}
	dst[0] = (unsigned char)(v & 0xFFu);
	dst[1] = (unsigned char)((v >> 8) & 0xFFu);
	dst[2] = (unsigned char)((v >> 16) & 0xFFu);
	dst[3] = (unsigned char)((v >> 24) & 0xFFu);
}

/* C copies a string INTO an XIOM-owned slot (never the other direction);
 * returns the byte length, or -1 when the source is NULL. */
static int copy_str(unsigned char* dst, int cap, const char* src)
{
	int n = 0;
	if (cap <= 0) {
		return -1;
	}
	dst[0] = 0;
	if (src == NULL) {
		return -1;
	}
	while (src[n] != 0 && n + 1 < cap) {
		dst[n] = (unsigned char)src[n];
		n = n + 1;
	}
	dst[n] = 0;
	return n;
}

static void zero_module(SpvReflectShaderModule* m)
{
	memset(m, 0, sizeof(*m));
}

/* One pointer per public C API function: the link-time resolve surface. */
static const void* const kApi[] = {
	(const void*)&spvReflectBlockVariableTypeName,
	(const void*)&spvReflectChangeDescriptorBindingNumber,
	(const void*)&spvReflectChangeDescriptorBindingNumbers,
	(const void*)&spvReflectChangeDescriptorSetNumber,
	(const void*)&spvReflectChangeInputVariableLocation,
	(const void*)&spvReflectChangeOutputVariableLocation,
	(const void*)&spvReflectCreateShaderModule,
	(const void*)&spvReflectCreateShaderModule2,
	(const void*)&spvReflectDestroyShaderModule,
	(const void*)&spvReflectEnumerateDescriptorBindings,
	(const void*)&spvReflectEnumerateDescriptorSets,
	(const void*)&spvReflectEnumerateEntryPointDescriptorBindings,
	(const void*)&spvReflectEnumerateEntryPointDescriptorSets,
	(const void*)&spvReflectEnumerateEntryPointInputVariables,
	(const void*)&spvReflectEnumerateEntryPointInterfaceVariables,
	(const void*)&spvReflectEnumerateEntryPointOutputVariables,
	(const void*)&spvReflectEnumerateEntryPointPushConstantBlocks,
	(const void*)&spvReflectEnumerateInputVariables,
	(const void*)&spvReflectEnumerateInterfaceVariables,
	(const void*)&spvReflectEnumerateOutputVariables,
	(const void*)&spvReflectEnumeratePushConstantBlocks,
	(const void*)&spvReflectEnumeratePushConstants,
	(const void*)&spvReflectEnumerateSpecializationConstants,
	(const void*)&spvReflectGetCode,
	(const void*)&spvReflectGetCodeSize,
	(const void*)&spvReflectGetDescriptorBinding,
	(const void*)&spvReflectGetDescriptorSet,
	(const void*)&spvReflectGetEntryPoint,
	(const void*)&spvReflectGetEntryPointDescriptorBinding,
	(const void*)&spvReflectGetEntryPointDescriptorSet,
	(const void*)&spvReflectGetEntryPointInputVariableByLocation,
	(const void*)&spvReflectGetEntryPointInputVariableBySemantic,
	(const void*)&spvReflectGetEntryPointOutputVariableByLocation,
	(const void*)&spvReflectGetEntryPointOutputVariableBySemantic,
	(const void*)&spvReflectGetEntryPointPushConstantBlock,
	(const void*)&spvReflectGetInputVariable,
	(const void*)&spvReflectGetInputVariableByLocation,
	(const void*)&spvReflectGetInputVariableBySemantic,
	(const void*)&spvReflectGetOutputVariable,
	(const void*)&spvReflectGetOutputVariableByLocation,
	(const void*)&spvReflectGetOutputVariableBySemantic,
	(const void*)&spvReflectGetPushConstant,
	(const void*)&spvReflectGetPushConstantBlock,
	(const void*)&spvReflectGetShaderModule,
	(const void*)&spvReflectSourceLanguage,
};

int xspv_api_count(void)
{
	return (int)(sizeof(kApi) / sizeof(kApi[0]));
}

int xspv_resolve_all(unsigned char* api_count, unsigned char* null_count)
{
	int n = (int)(sizeof(kApi) / sizeof(kApi[0]));
	int nulls = 0;
	int i = 0;
	for (i = 0; i < n; ++i) {
		if (kApi[i] == NULL) {
			nulls = nulls + 1;
		}
	}
	wr_u32(api_count, (unsigned int)n);
	wr_u32(null_count, (unsigned int)nulls);
	return 0;
}

int xspv_create_probe(unsigned char* rc, unsigned char* stage, unsigned char* model,
	unsigned char* entry_count, unsigned char* code_size, unsigned char* source_lang,
	unsigned char* source_version, unsigned char* generator, unsigned char* code_nonnull,
	unsigned char* entry_nonnull, unsigned char* name_len, unsigned char* name)
{
	SpvReflectShaderModule m;
	SpvReflectResult r;
	const SpvReflectEntryPoint* ep;
	zero_module(&m);
	r = spvReflectCreateShaderModule((size_t)XSPV_FRAG_BYTES, kFragSpirv, &m);
	wr_u32(rc, (unsigned int)r);
	if (r == SPV_REFLECT_RESULT_SUCCESS) {
		wr_u32(stage, (unsigned int)m.shader_stage);
		wr_u32(model, (unsigned int)m.spirv_execution_model);
		wr_u32(entry_count, (unsigned int)m.entry_point_count);
		wr_u32(code_size, (unsigned int)spvReflectGetCodeSize(&m));
		wr_u32(source_lang, (unsigned int)m.source_language);
		wr_u32(source_version, (unsigned int)m.source_language_version);
		wr_u32(generator, (unsigned int)m.generator);
		wr_u32(code_nonnull, spvReflectGetCode(&m) != NULL ? 1u : 0u);
		ep = spvReflectGetEntryPoint(&m, "main");
		wr_u32(entry_nonnull, ep != NULL ? 1u : 0u);
		wr_u32(name_len, (unsigned int)copy_str(name, 32, m.entry_point_name));
	}
	spvReflectDestroyShaderModule(&m);
	return 0;
}

int xspv_create2_probe(unsigned char* rc, unsigned char* stage, unsigned char* flags_out)
{
	SpvReflectShaderModule m;
	SpvReflectResult r;
	zero_module(&m);
	r = spvReflectCreateShaderModule2(SPV_REFLECT_MODULE_FLAG_NO_COPY,
		(size_t)XSPV_FRAG_BYTES, kFragSpirv, &m);
	wr_u32(rc, (unsigned int)r);
	if (r == SPV_REFLECT_RESULT_SUCCESS) {
		wr_u32(stage, (unsigned int)m.shader_stage);
		wr_u32(flags_out, (unsigned int)m._internal->module_flags);
		spvReflectDestroyShaderModule(&m);
	}
	return 0;
}

int xspv_descriptor_probe(unsigned char* enum_rc, unsigned char* bind_count,
	unsigned char* bind_rc, unsigned char* set_count, unsigned char* set_rc,
	unsigned char* binding_number, unsigned char* set_number, unsigned char* descriptor_type)
{
	SpvReflectShaderModule m;
	SpvReflectResult r;
	uint32_t count = 0;
	SpvReflectDescriptorBinding* binds[4];
	SpvReflectDescriptorSet* sets[4];
	zero_module(&m);
	r = spvReflectCreateShaderModule((size_t)XSPV_FRAG_BYTES, kFragSpirv, &m);
	wr_u32(enum_rc, (unsigned int)r);
	if (r != SPV_REFLECT_RESULT_SUCCESS) {
		spvReflectDestroyShaderModule(&m);
		return 0;
	}
	count = 0;
	spvReflectEnumerateDescriptorBindings(&m, &count, NULL);
	wr_u32(bind_count, count);
	count = (count <= 4u) ? count : 4u;
	memset(binds, 0, sizeof(binds));
	wr_u32(bind_rc, (unsigned int)spvReflectEnumerateDescriptorBindings(&m, &count, binds));
	if (count >= 1u && binds[0] != NULL) {
		wr_u32(binding_number, binds[0]->binding);
		wr_u32(set_number, binds[0]->set);
		wr_u32(descriptor_type, (unsigned int)binds[0]->descriptor_type);
	}
	count = 0;
	spvReflectEnumerateDescriptorSets(&m, &count, NULL);
	wr_u32(set_count, count);
	count = (count <= 4u) ? count : 4u;
	memset(sets, 0, sizeof(sets));
	wr_u32(set_rc, (unsigned int)spvReflectEnumerateDescriptorSets(&m, &count, sets));
	spvReflectDestroyShaderModule(&m);
	return 0;
}

int xspv_variable_probe(unsigned char* in_rc, unsigned char* in_count, unsigned char* out_rc,
	unsigned char* out_count, unsigned char* iface_rc, unsigned char* iface_count,
	unsigned char* in_location, unsigned char* in_format, unsigned char* out_location,
	unsigned char* out_format, unsigned char* name_matches_uv, unsigned char* name_len,
	unsigned char* name)
{
	SpvReflectShaderModule m;
	SpvReflectResult r;
	uint32_t count = 0;
	SpvReflectInterfaceVariable* vars[4];
	zero_module(&m);
	r = spvReflectCreateShaderModule((size_t)XSPV_FRAG_BYTES, kFragSpirv, &m);
	if (r != SPV_REFLECT_RESULT_SUCCESS) {
		spvReflectDestroyShaderModule(&m);
		return 0;
	}
	count = 0;
	spvReflectEnumerateInputVariables(&m, &count, NULL);
	wr_u32(in_count, count);
	count = (count <= 4u) ? count : 4u;
	memset(vars, 0, sizeof(vars));
	wr_u32(in_rc, (unsigned int)spvReflectEnumerateInputVariables(&m, &count, vars));
	if (count >= 1u && vars[0] != NULL) {
		wr_u32(in_location, vars[0]->location);
		wr_u32(in_format, (unsigned int)vars[0]->format);
		wr_u32(name_matches_uv, (vars[0]->name != NULL && strcmp(vars[0]->name, "uv") == 0) ? 1u : 0u);
		wr_u32(name_len, (unsigned int)copy_str(name, 32, vars[0]->name));
	}
	count = 0;
	spvReflectEnumerateOutputVariables(&m, &count, NULL);
	wr_u32(out_count, count);
	count = (count <= 4u) ? count : 4u;
	memset(vars, 0, sizeof(vars));
	wr_u32(out_rc, (unsigned int)spvReflectEnumerateOutputVariables(&m, &count, vars));
	if (count >= 1u && vars[0] != NULL) {
		wr_u32(out_location, vars[0]->location);
		wr_u32(out_format, (unsigned int)vars[0]->format);
	}
	count = 0;
	spvReflectEnumerateInterfaceVariables(&m, &count, NULL);
	wr_u32(iface_count, count);
	count = (count <= 4u) ? count : 4u;
	memset(vars, 0, sizeof(vars));
	wr_u32(iface_rc, (unsigned int)spvReflectEnumerateInterfaceVariables(&m, &count, vars));
	spvReflectDestroyShaderModule(&m);
	return 0;
}

int xspv_entrypoint_probe(unsigned char* ep_model, unsigned char* ep_stage,
	unsigned char* bind_count, unsigned char* bind_rc, unsigned char* set_count,
	unsigned char* in_count, unsigned char* out_count, unsigned char* iface_count,
	unsigned char* push_count, unsigned char* spec_count, unsigned char* bind_get_ok,
	unsigned char* set_get_ok, unsigned char* in_location_get_ok,
	unsigned char* out_location_get_ok, unsigned char* in_semantic_rc,
	unsigned char* out_semantic_rc, unsigned char* push_rc, unsigned char* dep_enum_push_rc,
	unsigned char* dep_enum_push_count, unsigned char* push_blocks_rc,
	unsigned char* push_blocks_count)
{
	SpvReflectShaderModule m;
	SpvReflectResult r;
	SpvReflectResult gr = SPV_REFLECT_RESULT_SUCCESS;
	uint32_t count = 0;
	const SpvReflectEntryPoint* ep;
	SpvReflectDescriptorBinding* binds[4];
	SpvReflectDescriptorSet* sets[4];
	SpvReflectInterfaceVariable* vars[4];
	SpvReflectBlockVariable* blocks[4];
	SpvReflectSpecializationConstant* specs[4];
	zero_module(&m);
	r = spvReflectCreateShaderModule((size_t)XSPV_FRAG_BYTES, kFragSpirv, &m);
	if (r != SPV_REFLECT_RESULT_SUCCESS) {
		spvReflectDestroyShaderModule(&m);
		return 0;
	}
	ep = spvReflectGetEntryPoint(&m, "main");
	wr_u32(ep_model, ep != NULL ? (unsigned int)ep->spirv_execution_model : 0xFFFFFFFFu);
	wr_u32(ep_stage, ep != NULL ? (unsigned int)ep->shader_stage : 0u);

	count = 0;
	spvReflectEnumerateEntryPointDescriptorBindings(&m, "main", &count, NULL);
	wr_u32(bind_count, count);
	count = (count <= 4u) ? count : 4u;
	memset(binds, 0, sizeof(binds));
	wr_u32(bind_rc, (unsigned int)spvReflectEnumerateEntryPointDescriptorBindings(&m, "main", &count, binds));

	count = 0;
	spvReflectEnumerateEntryPointDescriptorSets(&m, "main", &count, NULL);
	wr_u32(set_count, count);
	count = (count <= 4u) ? count : 4u;
	memset(sets, 0, sizeof(sets));
	spvReflectEnumerateEntryPointDescriptorSets(&m, "main", &count, sets);

	count = 0;
	spvReflectEnumerateEntryPointInputVariables(&m, "main", &count, NULL);
	wr_u32(in_count, count);
	count = (count <= 4u) ? count : 4u;
	memset(vars, 0, sizeof(vars));
	spvReflectEnumerateEntryPointInputVariables(&m, "main", &count, vars);

	count = 0;
	spvReflectEnumerateEntryPointOutputVariables(&m, "main", &count, NULL);
	wr_u32(out_count, count);
	count = (count <= 4u) ? count : 4u;
	memset(vars, 0, sizeof(vars));
	spvReflectEnumerateEntryPointOutputVariables(&m, "main", &count, vars);

	count = 0;
	spvReflectEnumerateEntryPointInterfaceVariables(&m, "main", &count, NULL);
	wr_u32(iface_count, count);
	count = (count <= 4u) ? count : 4u;
	memset(vars, 0, sizeof(vars));
	spvReflectEnumerateEntryPointInterfaceVariables(&m, "main", &count, vars);

	count = 0;
	spvReflectEnumerateEntryPointPushConstantBlocks(&m, "main", &count, NULL);
	wr_u32(push_count, count);
	count = (count <= 4u) ? count : 4u;
	memset(blocks, 0, sizeof(blocks));
	spvReflectEnumerateEntryPointPushConstantBlocks(&m, "main", &count, blocks);

	count = 0;
	spvReflectEnumerateSpecializationConstants(&m, &count, NULL);
	wr_u32(spec_count, count);
	count = (count <= 4u) ? count : 4u;
	memset(specs, 0, sizeof(specs));
	spvReflectEnumerateSpecializationConstants(&m, &count, specs);

	gr = SPV_REFLECT_RESULT_SUCCESS;
	wr_u32(bind_get_ok, spvReflectGetEntryPointDescriptorBinding(&m, "main", 0, 0, &gr) != NULL ? 1u : 0u);
	gr = SPV_REFLECT_RESULT_SUCCESS;
	wr_u32(set_get_ok, spvReflectGetEntryPointDescriptorSet(&m, "main", 0, &gr) != NULL ? 1u : 0u);
	gr = SPV_REFLECT_RESULT_SUCCESS;
	wr_u32(in_location_get_ok, spvReflectGetEntryPointInputVariableByLocation(&m, "main", 0, &gr) != NULL ? 1u : 0u);
	gr = SPV_REFLECT_RESULT_SUCCESS;
	wr_u32(out_location_get_ok, spvReflectGetEntryPointOutputVariableByLocation(&m, "main", 0, &gr) != NULL ? 1u : 0u);
	gr = SPV_REFLECT_RESULT_SUCCESS;
	spvReflectGetEntryPointInputVariableBySemantic(&m, "main", "NOPE", &gr);
	wr_u32(in_semantic_rc, (unsigned int)gr);
	gr = SPV_REFLECT_RESULT_SUCCESS;
	spvReflectGetEntryPointOutputVariableBySemantic(&m, "main", "NOPE", &gr);
	wr_u32(out_semantic_rc, (unsigned int)gr);
	gr = SPV_REFLECT_RESULT_SUCCESS;
	spvReflectGetEntryPointPushConstantBlock(&m, "main", &gr);
	wr_u32(push_rc, (unsigned int)gr);

	count = 0;
	wr_u32(dep_enum_push_rc, (unsigned int)spvReflectEnumeratePushConstants(&m, &count, NULL));
	wr_u32(dep_enum_push_count, count);

	count = 0;
	wr_u32(push_blocks_rc, (unsigned int)spvReflectEnumeratePushConstantBlocks(&m, &count, NULL));
	wr_u32(push_blocks_count, count);

	spvReflectDestroyShaderModule(&m);
	return 0;
}

int xspv_get_probe(unsigned char* bind_rc, unsigned char* bind_ok, unsigned char* set_rc,
	unsigned char* set_ok, unsigned char* in_rc, unsigned char* in_ok, unsigned char* out_rc,
	unsigned char* out_ok, unsigned char* in_semantic_rc, unsigned char* out_semantic_rc,
	unsigned char* push_rc)
{
	SpvReflectShaderModule m;
	SpvReflectResult r;
	SpvReflectResult gr;
	zero_module(&m);
	r = spvReflectCreateShaderModule((size_t)XSPV_FRAG_BYTES, kFragSpirv, &m);
	if (r != SPV_REFLECT_RESULT_SUCCESS) {
		spvReflectDestroyShaderModule(&m);
		return 0;
	}
	gr = SPV_REFLECT_RESULT_SUCCESS;
	wr_u32(bind_ok, spvReflectGetDescriptorBinding(&m, 0, 0, &gr) != NULL ? 1u : 0u);
	wr_u32(bind_rc, (unsigned int)gr);
	gr = SPV_REFLECT_RESULT_SUCCESS;
	wr_u32(set_ok, spvReflectGetDescriptorSet(&m, 0, &gr) != NULL ? 1u : 0u);
	wr_u32(set_rc, (unsigned int)gr);
	gr = SPV_REFLECT_RESULT_SUCCESS;
	wr_u32(in_ok, spvReflectGetInputVariableByLocation(&m, 0, &gr) != NULL ? 1u : 0u);
	wr_u32(in_rc, (unsigned int)gr);
	gr = SPV_REFLECT_RESULT_SUCCESS;
	wr_u32(out_ok, spvReflectGetOutputVariableByLocation(&m, 0, &gr) != NULL ? 1u : 0u);
	wr_u32(out_rc, (unsigned int)gr);
	gr = SPV_REFLECT_RESULT_SUCCESS;
	spvReflectGetInputVariableBySemantic(&m, "NOPE", &gr);
	wr_u32(in_semantic_rc, (unsigned int)gr);
	gr = SPV_REFLECT_RESULT_SUCCESS;
	spvReflectGetOutputVariableBySemantic(&m, "NOPE", &gr);
	wr_u32(out_semantic_rc, (unsigned int)gr);
	gr = SPV_REFLECT_RESULT_SUCCESS;
	spvReflectGetPushConstantBlock(&m, 0, &gr);
	wr_u32(push_rc, (unsigned int)gr);
	spvReflectDestroyShaderModule(&m);
	return 0;
}

int xspv_alias_probe(unsigned char* create_rc, unsigned char* stage, unsigned char* in_ok,
	unsigned char* out_ok, unsigned char* push_rc, unsigned char* change_rc,
	unsigned char* code_size)
{
	SpvReflectShaderModule m;
	SpvReflectResult r;
	SpvReflectResult gr;
	const SpvReflectDescriptorBinding* gb;
	zero_module(&m);
	r = spvReflectGetShaderModule((size_t)XSPV_FRAG_BYTES, kFragSpirv, &m);
	wr_u32(create_rc, (unsigned int)r);
	if (r != SPV_REFLECT_RESULT_SUCCESS) {
		spvReflectDestroyShaderModule(&m);
		return 0;
	}
	wr_u32(stage, (unsigned int)m.shader_stage);
	wr_u32(code_size, (unsigned int)spvReflectGetCodeSize(&m));
	gr = SPV_REFLECT_RESULT_SUCCESS;
	wr_u32(in_ok, spvReflectGetInputVariable(&m, 0, &gr) != NULL ? 1u : 0u);
	gr = SPV_REFLECT_RESULT_SUCCESS;
	wr_u32(out_ok, spvReflectGetOutputVariable(&m, 0, &gr) != NULL ? 1u : 0u);
	gr = SPV_REFLECT_RESULT_SUCCESS;
	spvReflectGetPushConstant(&m, 0, &gr);
	wr_u32(push_rc, (unsigned int)gr);
	gr = SPV_REFLECT_RESULT_SUCCESS;
	gb = spvReflectGetDescriptorBinding(&m, 0, 0, &gr);
	wr_u32(change_rc, (unsigned int)spvReflectChangeDescriptorBindingNumber(&m, gb, 4, 1));
	spvReflectDestroyShaderModule(&m);
	return 0;
}

int xspv_change_probe(unsigned char* chg_bind_rc, unsigned char* get_after_rc,
	unsigned char* get_after_ok, unsigned char* new_binding, unsigned char* new_set,
	unsigned char* chg_set_rc, unsigned char* get_set_after_ok, unsigned char* chg_in_rc,
	unsigned char* in_loc_after_ok, unsigned char* chg_out_rc, unsigned char* out_loc_after_ok)
{
	SpvReflectShaderModule m;
	SpvReflectResult r;
	SpvReflectResult gr;
	const SpvReflectDescriptorBinding* gb;
	const SpvReflectDescriptorSet* gs;
	const SpvReflectInterfaceVariable* var;
	zero_module(&m);
	r = spvReflectCreateShaderModule((size_t)XSPV_FRAG_BYTES, kFragSpirv, &m);
	if (r != SPV_REFLECT_RESULT_SUCCESS) {
		spvReflectDestroyShaderModule(&m);
		return 0;
	}
	gr = SPV_REFLECT_RESULT_SUCCESS;
	gb = spvReflectGetDescriptorBinding(&m, 0, 0, &gr);
	wr_u32(chg_bind_rc, (unsigned int)spvReflectChangeDescriptorBindingNumbers(&m, gb, 5, 3));
	gr = SPV_REFLECT_RESULT_SUCCESS;
	gb = spvReflectGetDescriptorBinding(&m, 5, 3, &gr);
	wr_u32(get_after_rc, (unsigned int)gr);
	wr_u32(get_after_ok, gb != NULL ? 1u : 0u);
	if (gb != NULL) {
		wr_u32(new_binding, gb->binding);
		wr_u32(new_set, gb->set);
	}
	gr = SPV_REFLECT_RESULT_SUCCESS;
	gs = spvReflectGetDescriptorSet(&m, 3, &gr);
	wr_u32(chg_set_rc, (unsigned int)spvReflectChangeDescriptorSetNumber(&m, gs, 7));
	gr = SPV_REFLECT_RESULT_SUCCESS;
	gs = spvReflectGetDescriptorSet(&m, 7, &gr);
	wr_u32(get_set_after_ok, gs != NULL ? 1u : 0u);
	gr = SPV_REFLECT_RESULT_SUCCESS;
	var = spvReflectGetInputVariableByLocation(&m, 0, &gr);
	wr_u32(chg_in_rc, (unsigned int)spvReflectChangeInputVariableLocation(&m, var, 4));
	gr = SPV_REFLECT_RESULT_SUCCESS;
	var = spvReflectGetInputVariableByLocation(&m, 4, &gr);
	wr_u32(in_loc_after_ok, var != NULL ? 1u : 0u);
	gr = SPV_REFLECT_RESULT_SUCCESS;
	var = spvReflectGetOutputVariableByLocation(&m, 0, &gr);
	wr_u32(chg_out_rc, (unsigned int)spvReflectChangeOutputVariableLocation(&m, var, 6));
	gr = SPV_REFLECT_RESULT_SUCCESS;
	var = spvReflectGetOutputVariableByLocation(&m, 6, &gr);
	wr_u32(out_loc_after_ok, var != NULL ? 1u : 0u);
	spvReflectDestroyShaderModule(&m);
	return 0;
}

int xspv_spec_probe(unsigned char* enum_rc, unsigned char* spec_count,
	unsigned char* constant_id, unsigned char* default_size, unsigned char* name_len,
	unsigned char* name)
{
	SpvReflectShaderModule m;
	SpvReflectResult r;
	uint32_t count = 0;
	SpvReflectSpecializationConstant* specs[4];
	zero_module(&m);
	r = spvReflectCreateShaderModule((size_t)XSPV_FRAG_BYTES, kFragSpirv, &m);
	wr_u32(enum_rc, (unsigned int)r);
	if (r != SPV_REFLECT_RESULT_SUCCESS) {
		spvReflectDestroyShaderModule(&m);
		return 0;
	}
	count = 0;
	spvReflectEnumerateSpecializationConstants(&m, &count, NULL);
	wr_u32(spec_count, count);
	count = (count <= 4u) ? count : 4u;
	memset(specs, 0, sizeof(specs));
	spvReflectEnumerateSpecializationConstants(&m, &count, specs);
	if (count >= 1u && specs[0] != NULL) {
		wr_u32(constant_id, specs[0]->constant_id);
		wr_u32(default_size, specs[0]->default_value_size);
		wr_u32(name_len, (unsigned int)copy_str(name, 32, specs[0]->name));
	}
	spvReflectDestroyShaderModule(&m);
	return 0;
}

int xspv_strings_probe(unsigned char* lang_len, unsigned char* lang,
	unsigned char* type_name_len, unsigned char* type_name, unsigned char* null_name_is_null)
{
	SpvReflectShaderModule m;
	SpvReflectResult r;
	const SpvReflectDescriptorBinding* gb;
	const SpvReflectDescriptorSet* gs;
	SpvReflectResult gr;
	zero_module(&m);
	r = spvReflectCreateShaderModule((size_t)XSPV_FRAG_BYTES, kFragSpirv, &m);
	if (r != SPV_REFLECT_RESULT_SUCCESS) {
		spvReflectDestroyShaderModule(&m);
		return 0;
	}
	wr_u32(lang_len, (unsigned int)copy_str(lang, 32, spvReflectSourceLanguage(m.source_language)));
	spvReflectDestroyShaderModule(&m);
	zero_module(&m);
	r = spvReflectCreateShaderModule((size_t)XSPV_UBO_BYTES, kUboSpirv, &m);
	if (r != SPV_REFLECT_RESULT_SUCCESS) {
		spvReflectDestroyShaderModule(&m);
		return 0;
	}
	gr = SPV_REFLECT_RESULT_SUCCESS;
	gb = spvReflectGetDescriptorBinding(&m, 0, 0, &gr);
	gs = spvReflectGetDescriptorSet(&m, 0, &gr);
	(void)gs;
	if (gb != NULL) {
		wr_u32(type_name_len, (unsigned int)copy_str(type_name, 32, spvReflectBlockVariableTypeName(&gb->block)));
	}
	wr_u32(null_name_is_null, spvReflectBlockVariableTypeName(NULL) == NULL ? 1u : 0u);
	spvReflectDestroyShaderModule(&m);
	return 0;
}

int xspv_error_probe(unsigned char* magic_rc, unsigned char* magic_null, unsigned char* short_rc,
	unsigned char* short_null, unsigned char* trunc_rc, unsigned char* trunc_null)
{
	SpvReflectShaderModule m;
	SpvReflectResult r;
	unsigned int garbage[8] = { 0x11111111u, 0x22222222u, 0x33333333u, 0x44444444u, 1u, 2u, 3u, 4u };
	unsigned int garbage_short[4] = { 1u, 2u, 3u, 4u };

	zero_module(&m);
	r = spvReflectCreateShaderModule(sizeof(garbage), garbage, &m);
	wr_u32(magic_rc, (unsigned int)r);
	wr_u32(magic_null, m._internal == NULL ? 1u : 0u);
	spvReflectDestroyShaderModule(&m);

	zero_module(&m);
	r = spvReflectCreateShaderModule(sizeof(garbage_short), garbage_short, &m);
	wr_u32(short_rc, (unsigned int)r);
	wr_u32(short_null, m._internal == NULL ? 1u : 0u);
	spvReflectDestroyShaderModule(&m);

	zero_module(&m);
	r = spvReflectCreateShaderModule(3u, kFragSpirv, &m);
	wr_u32(trunc_rc, (unsigned int)r);
	wr_u32(trunc_null, m._internal == NULL ? 1u : 0u);
	spvReflectDestroyShaderModule(&m);
	return 0;
}

int xspv_free_chain_probe(unsigned char* c1, unsigned char* c2, unsigned char* stage2,
	unsigned char* empty_destroy_ok)
{
	SpvReflectShaderModule m;
	SpvReflectResult r;
	zero_module(&m);
	r = spvReflectCreateShaderModule((size_t)XSPV_FRAG_BYTES, kFragSpirv, &m);
	wr_u32(c1, (unsigned int)r);
	spvReflectDestroyShaderModule(&m);

	zero_module(&m);
	r = spvReflectCreateShaderModule((size_t)XSPV_UBO_BYTES, kUboSpirv, &m);
	wr_u32(c2, (unsigned int)r);
	wr_u32(stage2, (unsigned int)m.shader_stage);
	spvReflectDestroyShaderModule(&m);

	zero_module(&m);
	spvReflectDestroyShaderModule(&m);
	wr_u32(empty_destroy_ok, 1u);
	return 0;
}
