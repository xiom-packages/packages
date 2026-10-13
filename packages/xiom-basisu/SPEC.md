# SPEC: xiom.basisu -- basis_universal bindings (vendored C API)

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.basisu` |
| Version | 0.1.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | Basis Universal -- `https://github.com/BinomialLLC/basis_universal` |
| Upstream version pinned | **v2_50** = commit `9bebe16726b3a61c8c213eeee3b7cffb462ef34e` (2026-07-22; lib 2.50) |
| Upstream license | Apache-2.0 (core; + zstd BSD-3-Clause, per-component MIT/BSD in `encoder/3rdparty/`) |
| Package license | MIT OR Apache-2.0 (everything outside `vendor/`) |
| Platform | Windows x64 (vendored path; no platform-specific XIOM code) |
| Compiler pin | v0.64.4 |
| Clone of record | `E:\repos\basis_universal` (shallow; ledger row in `E:\repos\CLEANUP.md`) |

`xiom.ktx2` (separate package) covers libktx's own public surface; this package declares
**only** basis_universal's C API and does not duplicate KTX-Software's API.

## 2. Vendored path (G2 pin)

The pinned upstream tree above is vendored **verbatim** into `vendor/` (113 files,
11,515,373 bytes) and compiled into the test binary via `--c-source` with
`--cxx-standard 17` (no system library, no runtime DLL). The composition follows the
upstream `CMakeLists.txt`:

| Area | Files | Role |
|------|-------|------|
| `vendor/transcoder/**` | 26 | transcoder class + codecs + tables (C++ TU compiled) |
| `vendor/encoder/basisu_wasm_*.{h,cpp}` | 5 | the pinned public C API (transcoder + encoder) |
| `vendor/encoder/**.{cpp,h}` (canonical `ENCODER_LIB_SRC_LIST`) | 61 | encoder library (compiles the `bu_*` entry points) |
| `vendor/encoder/*.inl` | 2 | ASTC pseudoinverse + BC15 SPMD kernel tables |
| `vendor/encoder/3rdparty/**` | 6 | android ASTC decomp (required by encoder TUs), qoi, tinyexr (+ helpers), tinydds |
| `vendor/zstd/**` | 4 | Zstandard amalgamation (KTX2 zstd supercompression) |
| `vendor/LICENSE`, `vendor/NOTICE`, `vendor/LICENSES/**` | 5 | upstream license texts |

`.gitattributes` pins `vendor/** -text`; the bytes below are the canonical blobs from
the upstream clone (all 113 files verified byte-identical on 2026-10-13).

### Build shim

`src/basisu_zstd_all.c` (our code) sets `#define STATIC_BMI2 0` and includes the
vendored `zstd.c`: the xiom link line compiles C sources with baseline x86-64 features,
and zstd's `bits.h` would otherwise take the BMI2 intrinsics path (`_bzhi_u64`) without a
`-mbmi2` target. Same shim and rationale as `xiom.zstd` (`src/zstd_all.c`); the vendored
file is unmodified.

### Pin table (113 files)

| File | Bytes | SHA256 |
|------|-------|--------|
| `vendor/encoder/3rdparty/android_astc_decomp.cpp` | 78,463 | `C4C0A8C87829A764B2066CE6D90F682736E95803136E6A29EDE9C9AC65C9B31F` |
| `vendor/encoder/3rdparty/exr_reader.hh` | 4,645 | `9E0BFEF0487B9C3082165B2A637C75EF91D9FCC4AA55A5F32EB97F77DB19F99B` |
| `vendor/encoder/3rdparty/qoi.h` | 18,732 | `48E138B971F12F0287B132D423C6A96D4677D97A383656C7636777421ED79CBE` |
| `vendor/encoder/3rdparty/streamreader.hh` | 3,782 | `81F2D1502930CA9CA9957E7607C2A7924D3EF2FE4B08B1A4001245DC6D3FEFB6` |
| `vendor/encoder/3rdparty/tinydds.h` | 76,321 | `30290928C699C1F37F99189EB5D71749BDDA953CAACBD3B5A03C834DDF05C888` |
| `vendor/encoder/3rdparty/tinyexr.h` | 372,736 | `9C7F087A54EDD125FB36A2D90DA6C6CB0182A98C673C0ADF9BFDD04BE9EF0141` |
| `vendor/encoder/basisu_astc_hdr_6x6_enc.cpp` | 219,650 | `F6291928074D2876524D7F43A0DB1C3E15560BC7315A21562A45F8406880E4BD` |
| `vendor/encoder/basisu_astc_hdr_6x6_enc.h` | 7,815 | `42886973BEF8906F9E6535542809779489E5A605F19DE54A7F70818122EC012B` |
| `vendor/encoder/basisu_astc_hdr_common.cpp` | 697,282 | `16FED85AA25D9A729075433CD98756A60E85B39F84616843CD40C39D28FF64C5` |
| `vendor/encoder/basisu_astc_hdr_common.h` | 15,870 | `C98B41C66A7F4C010B0FF4CA8BFABC317C882649306A887AC4D8D86D9F0FA427` |
| `vendor/encoder/basisu_astc_ldr_common.cpp` | 199,958 | `FB477E4429442A618D63D24041DFBDAE2B340E4211958FAFC0DBDA00D5AA6C87` |
| `vendor/encoder/basisu_astc_ldr_common.h` | 13,563 | `CC3224D7DD343307B2926C013B172D5A935265415DF7084F2936BB946224B224` |
| `vendor/encoder/basisu_astc_ldr_encode.cpp` | 578,836 | `DE09685B9084549E9CA559EC809C7CD4C9902AAE11D56D8E5775E222E01127D6` |
| `vendor/encoder/basisu_astc_ldr_encode.h` | 6,891 | `59DA8D06A703C3D0C5087B469ED0F1CF57D205F7E63BE2801EA6FE78104E5FE4` |
| `vendor/encoder/basisu_astc_ldr_fencode.cpp` | 203,062 | `23602173069696853E6B62B95E36B3A148A812294B736BB6768DACED89720A50` |
| `vendor/encoder/basisu_astc_ldr_fencode.h` | 10,218 | `9B89D1B5A1C83BF5D393DE14F084937E82A2C553344400C28E385D9050EA5542` |
| `vendor/encoder/basisu_astc_ldr_pseudoinv_tab.inl` | 19,804 | `D1AA5DE6EBC0DDC625D78344C49A59E47E1D9C077B3A65DEE5DBCD536318381C` |
| `vendor/encoder/basisu_backend.cpp` | 64,683 | `E6E470D9AF8A91947F8BE99E5FC0EBDA6DD3433263FEAAC5D89480A771E695EE` |
| `vendor/encoder/basisu_backend.h` | 10,056 | `F54F905F9AFEF880C7D507A05E33636D54EC7D5AC9ED2FC5B7AE043D8643C137` |
| `vendor/encoder/basisu_basis_file.cpp` | 12,974 | `10610C5DF3F4719D7B0359F7FEF4160E7BC4E1AA756EC3553D8AE2F3C488E33F` |
| `vendor/encoder/basisu_basis_file.h` | 2,705 | `40EE6DAE86BE2EAB243EFBA191B5DE3BE44BBD28630F37481E4BB778C7F95E97` |
| `vendor/encoder/basisu_bc15_spmd.cpp` | 22,391 | `0866176EBD3EB710768516B47221D4B42B06E632FA378E52D6759C1B37088134` |
| `vendor/encoder/basisu_bc15_spmd.h` | 5,868 | `02BCA54B54E046A719A984AE37EE63F56914884BD62A6082FE41E7938E1C429B` |
| `vendor/encoder/basisu_bc15_spmd_kernels.inl` | 23,420 | `70D768F5A7E2F5390BB34880219D3613EE95ECB8C56A3706300022E50DC5C142` |
| `vendor/encoder/basisu_bc15_spmd_sse.cpp` | 657 | `EC43DC249C0153FE0CEF53192970DA2FB4897EA0D2F17C000E0C5091BEDFE018` |
| `vendor/encoder/basisu_bc7e_scalar.cpp` | 163,213 | `684B106E6037042BEE065694E5956A97BA91CF2B2417C1A44217E0087A5E808F` |
| `vendor/encoder/basisu_bc7e_scalar.h` | 4,191 | `5395F673CBDB9B4CE5115D18369F36B6002712BF88AC3CE71170CDEACE889B79` |
| `vendor/encoder/basisu_bc7enc.cpp` | 73,403 | `56CB444A02971C4900BAF6A4811F9E4FA5295A7770525C365F26CDBD6205A698` |
| `vendor/encoder/basisu_bc7enc.h` | 4,357 | `221361CDB72AF44085C094D8ADC3F4E6D46523BAC80D8A84A76F33D8A0F1E182` |
| `vendor/encoder/basisu_comp.cpp` | 217,318 | `3C3519D51EB2C8E5D90AF2EEAAA0307CD8A78688FEB33012E0BFC73343FE44AF` |
| `vendor/encoder/basisu_comp.h` | 58,603 | `319CFAA0BEB24F0D903EDB8D8BA767B2FC6D512B7F9EE9BDAA39F5C9A10D8988` |
| `vendor/encoder/basisu_dds_export.cpp` | 21,644 | `4B6B7FA4B7E82FC9D312EFCCE439D0D34545ED007FFE386EE46AE0D003EC69F9` |
| `vendor/encoder/basisu_dds_export.h` | 5,609 | `C102CF5CF9476E69278F48B3840F6868BD302B6988CD36548DFAC3C4B133F006` |
| `vendor/encoder/basisu_enc.cpp` | 160,469 | `33725CB025AD510E2C01EECDBECF5A3D1815F5B568E16758EF0F9FDBD31556CB` |
| `vendor/encoder/basisu_enc.h` | 126,622 | `F286610406F3D8FC33C331B5E8F4EBE34AADDCC59CB1B7DF35AFD6356409C946` |
| `vendor/encoder/basisu_etc.cpp` | 71,016 | `7F4DB9B8E269E6B8D368385C98A218D43766138EFDEAA7D81286A95DA9A549F9` |
| `vendor/encoder/basisu_etc.h` | 34,704 | `F6B343D43CFAA3B502EF8C2A9351A7DA74233B3D49F4285DCB6232B2C8CE4462` |
| `vendor/encoder/basisu_frontend.cpp` | 122,177 | `39B55D58B1DA44273E107B261B89B8F9FC7AFF302C681C252D7AC62D6525D9E8` |
| `vendor/encoder/basisu_frontend.h` | 11,965 | `C16E6080738BA3AFD317AA35A52681E87F54FCDA37EACE678545016E4A6E9723` |
| `vendor/encoder/basisu_gpu_texture.cpp` | 102,353 | `B5D364829DCFB0A00B8161EAC8B0D656831BFBCEA0ECE11F6972F583814FA311` |
| `vendor/encoder/basisu_gpu_texture.h` | 13,083 | `7DCA2C433B059EB1EF17FB3D87F59491670AFD10FA999AC12D27C38FCA3B8E93` |
| `vendor/encoder/basisu_kernels_declares.h` | 2,062 | `8CC894E849BB8634D66AA934336D2E4FCD1FDABB6B8CE27EB0611F0E64BE2FEB` |
| `vendor/encoder/basisu_kernels_imp.h` | 24,188 | `927EE436C23C4E4B9E1F6474746FD2768BD230F06BBDB3EEAF368B436C69D70E` |
| `vendor/encoder/basisu_kernels_sse.cpp` | 3,131 | `C2F597AE8BED9C986E77588B623203854115B9A86AB1B9D44A078BB7D2BD066D` |
| `vendor/encoder/basisu_math.h` | 127,592 | `F6CABD939BE1278ABF317F7818FACB5E3298BF498D32D769D50BE6F37153402F` |
| `vendor/encoder/basisu_miniz.h` | 122,754 | `96BB1CC709EF4465FE76513EE56A10CD56E1643C7898275F18D3CF6960B849E4` |
| `vendor/encoder/basisu_ocl_kernels.h` | 279,806 | `E6260419EE511CF7BD3A2646AB57D521F26DEAB8BD7380E74D5DB8C2E6FA55AD` |
| `vendor/encoder/basisu_opencl.cpp` | 40,159 | `762EEC61F4DBE443FD79F34D6FD622A41BEFEA6C7629D088C0523F8D7A12180D` |
| `vendor/encoder/basisu_opencl.h` | 4,106 | `869CD850E14813DFAC23074B033E45E700DD1E9E0E1699128CB8624820509DE9` |
| `vendor/encoder/basisu_pvrtc1_4.cpp` | 21,669 | `973A229630E42A797D501CD2A5FA49F20DCD739129949F6C3861FAD8EF725043` |
| `vendor/encoder/basisu_pvrtc1_4.h` | 12,627 | `9485683B545782AD6ECC1A9D1C51E339A1DAC1EBC55022A64C8AECEEFA813498` |
| `vendor/encoder/basisu_resample_filters.cpp` | 7,690 | `7ED1324235705AE816B89A94D17E8EEA147A84E5C98194B59B35B5AC23E65688` |
| `vendor/encoder/basisu_resampler.cpp` | 19,635 | `F3BCAF9FACF049B0E3C08D3AD3432A908D8707E68E536140E15D913DD967EC70` |
| `vendor/encoder/basisu_resampler.h` | 4,871 | `0F157726034D750267B3E62C0B001CC2E32057E90AAA26CE25E98D8F7F40C0A2` |
| `vendor/encoder/basisu_resampler_filters.h` | 1,462 | `8975ADBE9656B0094E9EDCB67DFFC98648C774BC6D58826EB553A7E5C2D47778` |
| `vendor/encoder/basisu_ssim.cpp` | 10,029 | `0B80FA019F7400F4D704F835E34F6C24FB0513C267E9E030015C9DCD1ADFB8ED` |
| `vendor/encoder/basisu_ssim.h` | 1,905 | `8EC3677B5BE06844ED5131F44E4E858DD194145CAA805B48898BBC2C0DCEE173` |
| `vendor/encoder/basisu_tinyexr.cpp` | 2,342 | `037FE28FD943AC5AB9EAC3C4C029447842A9A145E1780E613662B7360506244F` |
| `vendor/encoder/basisu_uastc_enc.cpp` | 151,686 | `2F0364EB3C0F0D3291D65D93FD852E8B8464EE0230DE3AD5E7821ED044CA4939` |
| `vendor/encoder/basisu_uastc_enc.h` | 6,310 | `3A9841EBF58A49E0A7FE4CAAE470AC725381495BCC5E6F40272D5AE71290E610` |
| `vendor/encoder/basisu_uastc_hdr_4x4_enc.cpp` | 42,096 | `6D738ACA775B5D1E7F00AD7565B0AF7B90697B9C82FA1CCB67C21D5AFC37CDDE` |
| `vendor/encoder/basisu_uastc_hdr_4x4_enc.h` | 5,502 | `7C61C900802BC3D8DE188A4FC52A1640CE460A42FAB256CC1ED647C64DCA3B20` |
| `vendor/encoder/basisu_wasm_api.cpp` | 7,107 | `C9E1054E41F4F93CF1ED303E10C9B7F7F6C45DF444ECF16654C253794EA313FF` |
| `vendor/encoder/basisu_wasm_api.h` | 1,633 | `A6CCAA426AC04B3F3D2C8C6AA4065396853A1B1E21746239D1A27D0C04CD9E2D` |
| `vendor/encoder/basisu_wasm_api_common.h` | 6,056 | `04F8AB464851405B6B45C706A2570EBE0ED3B153041A565D743C53E8F581C1CF` |
| `vendor/encoder/basisu_wasm_transcoder_api.cpp` | 28,864 | `E668A15DAFDA2A5BED6B40BEA8C71D02F3D67C2689D3047CF8C1C12B018E0C8B` |
| `vendor/encoder/basisu_wasm_transcoder_api.h` | 8,904 | `F7FDE3E1F221455075CF81849AC24A08AE66B9010CC3B094D86C33CDD205D955` |
| `vendor/encoder/basisu_xbc7_encode.cpp` | 137,646 | `00A19D6BE5FA46919671DC3518DE8DB8E9331F31E8348DDBCA4AEA4757268FC5` |
| `vendor/encoder/basisu_xbc7_encode.h` | 10,898 | `CD73BC88BE28BB654C9B79520A18C5538989E4425FAAC2ACC4E7E292CDB46A88` |
| `vendor/encoder/cppspmd_flow.h` | 19,558 | `AF5A6F9DB7662DA6C641F1B809B16FCB5F6C5537719BA22F9CA4D1BF44EB1E45` |
| `vendor/encoder/cppspmd_math.h` | 21,210 | `71EEBD8E258A9BC81E22F40ADBA581270B80E8601CA621976C18FE6CB12801CD` |
| `vendor/encoder/cppspmd_math_declares.h` | 2,977 | `157AAAD9130EB48EAC61FB088B9E7047F8417A1C5E4586FE0A1DA4968BC25907` |
| `vendor/encoder/cppspmd_sse.h` | 81,682 | `0689AA02C266BE917A0C1C9CF2DBA0A2F38E9C56C40603F27C0FD69C90DC949C` |
| `vendor/encoder/cppspmd_type_aliases.h` | 1,431 | `DCFF9416E208031155AA041CD0FFD7350839034F7A5BBB3293CB40FF3DB865A0` |
| `vendor/encoder/jpgd.cpp` | 81,307 | `96B5BDDEE685552CE5365B9FB9216BAB0CCB9BB84860E919FFDF2FA0BE177AEE` |
| `vendor/encoder/jpgd.h` | 13,943 | `9A27AC6BEF93C230A0AA15FE9F31F8E84B5195F4F5AE500696D9177178237EB6` |
| `vendor/encoder/pvpngreader.cpp` | 57,168 | `1BD3CEBA3B1FF9F7D1324F4127D33553F122DE39129059B4D157526DE9FEED93` |
| `vendor/encoder/pvpngreader.h` | 1,560 | `8DFB6B1ECD495D29679C5A0D25B39BEED32D7410F5F880B6B3A0B01926ABFF1C` |
| `vendor/LICENSE` | 11,347 | `065FCF48D6AF21C0B75E23BE5ED5753AEE75C892E1C2CF178FA6736305614A5C` |
| `vendor/LICENSES/Apache-2.0.txt` | 10,273 | `3813A29779A0F57428CDC4A15EEE600A22DC3E3A549106A22826837EF47537CA` |
| `vendor/LICENSES/BSD-3-clause.txt` | 4,978 | `849B4BABF98A7400533C3E359EBD372B3D29B252EB2E466ABFFF80940B480188` |
| `vendor/LICENSES/MIT.txt` | 2,253 | `E6DAB01BED712A1C5C9A627B0D21B86445092C95A15B7F0779D5A471C187C480` |
| `vendor/NOTICE` | 998 | `A710C77F53231533F19FBC00E04A7109077F2DEC74232B62A96F2AC1A1C04C85` |
| `vendor/transcoder/basisu.h` | 24,094 | `2724DD59ACBD332D43DDE5F15A9B546ED851C45C7C2ACBCDCAB4A288C58628E0` |
| `vendor/transcoder/basisu_astc_cfgs.inl` | 100,465 | `2F56D16CC37DDB6A5F361BE42E3AB32ECBEEFD94FD287D5BD46C15E0E1FDB34E` |
| `vendor/transcoder/basisu_astc_hdr_core.h` | 6,425 | `4D1E2B68275C7F402623AB0824722D7E8D6E85ADC2FC747A44C07E5321B366D4` |
| `vendor/transcoder/basisu_astc_helpers.h` | 165,330 | `F698C23506C0E59F3BD4CB645BD3B4D071B06F1112A0CF6A0DE19A19CFF837F8` |
| `vendor/transcoder/basisu_containers.h` | 94,882 | `84A17DCB701DD22A44381AE226E3E9CDC9D361E74EFC640D0CCB8BBBB081EE41` |
| `vendor/transcoder/basisu_containers_impl.h` | 15,282 | `9810BAECA8B39497101997CF309C0CEE153F096AF21F1EB8E12C142410F5EF2A` |
| `vendor/transcoder/basisu_dds_transcoder.inl` | 61,805 | `18F731EBE27B311EFDA2A576B3BC76F1E1B541B25E9A790A9759F76EFFC61833` |
| `vendor/transcoder/basisu_etc1_mods.inl` | 5,171 | `DDF9EFD40F07209C914F4051B94BBE1821915AE61B6CA39D61AAFD0126C6DD0D` |
| `vendor/transcoder/basisu_file_headers.h` | 12,132 | `5988F2D27E41A3F36EF5A2E350675DD30BD1EE2C70853E42A1D796A74D8178A9` |
| `vendor/transcoder/basisu_idct.h` | 40,663 | `0B218CE8A9F72036C1E531387D2A168B950A2AF2D5A40204F08A5EC381A2E4EE` |
| `vendor/transcoder/basisu_transcoder.cpp` | 1,683,389 | `244CF0DA60941C0311FEED5E9C01B9225D6CA796292391D808A4FA3CF9E406F2` |
| `vendor/transcoder/basisu_transcoder.h` | 92,366 | `D60E4D56C7DBC392EC476E484CC5030046ECD378C554A5FFA898CCD0E1EC1B08` |
| `vendor/transcoder/basisu_transcoder_internal.h` | 117,848 | `9E12E4543D2872C4C0BEB91BF9438D5BED1205D52358FD15671B747D8485369F` |
| `vendor/transcoder/basisu_transcoder_tables_astc.inc` | 162,781 | `7DD41C648D3ED8E7D511EB4AF865669C4DD50B8ECEAD62A68FCA471138C46E1A` |
| `vendor/transcoder/basisu_transcoder_tables_astc_0_255.inc` | 187,628 | `F41ACB498BE64349C48600E965664F4BEC1161781169E3EC3411827C490EF4F8` |
| `vendor/transcoder/basisu_transcoder_tables_atc_55.inc` | 166,330 | `4A510A20BFFC3738D85D41E44633D44145931AA5734AFFB390C7836EC8B5DABB` |
| `vendor/transcoder/basisu_transcoder_tables_atc_56.inc` | 167,158 | `94714B54F0C13C2F3BA5481FBFB40B974892048D59AB68419B369222F0A68075` |
| `vendor/transcoder/basisu_transcoder_tables_bc7_m5_alpha.inc` | 17,520 | `4D713B839594F429D95F329D60F8AD495E932619111B5DFDDFFB688E3634B495` |
| `vendor/transcoder/basisu_transcoder_tables_bc7_m5_color.inc` | 178,391 | `E6F63D3EBCE0AC84D801EC54614B6A4EEDA3BE3E994F3ABBFC732377CFE5A531` |
| `vendor/transcoder/basisu_transcoder_tables_dxt1_5.inc` | 166,584 | `500E640B5E6858FD10194EB4845670EB36D3EF9DC117A017632C1104BA3EB9D5` |
| `vendor/transcoder/basisu_transcoder_tables_dxt1_6.inc` | 168,891 | `3D203465F9097845EDDB821943D312BF8CFFB04D8F5CE09C18D4C6DF40519ED3` |
| `vendor/transcoder/basisu_transcoder_tables_pvrtc2_45.inc` | 163,850 | `780711642098A91239EE37B3F9110469EE1C7DA8DD9E440A43C7BA70F992FF9D` |
| `vendor/transcoder/basisu_transcoder_tables_pvrtc2_alpha_33.inc` | 153,900 | `250D389235C0213757266441F72AEE37CBE138A3C2A3F58B590ED53D6FB746FA` |
| `vendor/transcoder/basisu_transcoder_uastc.h` | 11,223 | `8796F8E755B868C56967E3D4D53089C2AAAC7E1F345B03BE1E975016FCBAF11E` |
| `vendor/transcoder/basisu_xbc7_decoder.h` | 51,443 | `7487D5C43FE2FF97ABA5A3CEE87CFCDCB433F003B72C47927D4D4AEEBDE7B2EA` |
| `vendor/transcoder/basisu_xbc7_decoder.inl` | 54,478 | `485B6C4B9297047430EA8124319501D58389D96DA38642F59DAFD974D88D65D1` |
| `vendor/zstd/LICENSE` | 1,530 | `2C1A7FA704DF8F3A606F6FC010B8B5AAEBF403F3AEEC339A12048F1BA7331A0B` |
| `vendor/zstd/zstd.c` | 1,993,264 | `37045A972B773425CE477A218FB7B4167DA83A93BA6FD7E4BAF79F5558C8424F` |
| `vendor/zstd/zstd.h` | 181,748 | `9B4BC8245565C98CCFC61C07749928B57E7C0F6FDDB0530C4F6AA1971893D88B` |
| `vendor/zstd/zstd_errors.h` | 4,278 | `66A8C3F71D12EA6E797E4F622F31F3F8F81C41B36F48CAD4F5DE7D8BFB6AAC0A` |

Cross-check: `vendor/zstd/zstd.h` carries the same SHA256 as `xiom.zstd`'s pin
(`9B4BC824...`), i.e. the same Zstandard 1.5.x single-file header.

### Re-pin procedure

See `PROVENANCE.md` section 6.

## 3. Declared C API surface (export matrix)

The declared surface is **100% of the pinned public C API**: every function declared in
`encoder/basisu_wasm_transcoder_api.h` and `encoder/basisu_wasm_api.h`, plus every
constant in `encoder/basisu_wasm_api_common.h`. All 81 functions are declared in
`basisu.xi`; none are stubbed or skipped.

| Header | Prefix | Count | Declared | Notes |
|--------|--------|-------|----------|-------|
| `encoder/basisu_wasm_transcoder_api.h` | `bt_` | 68 | 68 (100%) | version/init/alloc, 19 format helpers, KTX2 open/close/metadata, per-level getters, transcode |
| `encoder/basisu_wasm_api.h` | `bu_` | 13 | 13 (100%) | version/init/alloc, comp_params lifecycle, image upload, `bu_compress_texture` |
| total | | **81** | **81 (100%)** | |

Constants declared (verbatim values): `BTF_*` (34 payload modes + `BTF_TOTAL_FORMATS`),
`TF_*` (41 transcode targets + `TF_TOTAL_TEXTURE_FORMATS`), `DECODE_FLAGS_*` (9),
`BU_COMP_FLAGS_*` (all, incl. `BU_COMP_FLAGS_VERBOSE`), `BU_QUALITY_*`, `BU_EFFORT_*`.

**C++-only areas excluded (no C entry at the pin)**

| Area | Reason |
|------|--------|
| `basist::ktx2_transcoder` / `basist::basisu_transcoder` classes (`transcoder/basisu_transcoder.h`) | C++ class APIs; the `bt_*` C wrappers are the pinned C projection of the KTX2 class path |
| `basisu::basis_compressor` / `comp_params` (`encoder/basisu_comp.h`) | C++ class API; the `bu_*` C wrappers are the pinned C projection |
| `.basis` (Basis v1) payload transcoding | the C API opens KTX2 only (`bt_ktx2_open`); v1 handling lives only in the C++ class |
| OpenCL acceleration | runtime-optional upstream path, not part of the C surface (`BU_COMP_FLAGS_USE_OPENCL` is declared but the wasm targets build without OpenCL) |
| CLI-tool I/O (TGA/PNG/QOI/EXR/DDS file writers, `basisu_tool.cpp`) | tool-only helpers around the library; not part of the C API |

## 4. Design and safe boundary (G5)

| Module | File | Role |
|--------|------|------|
| `xiom.basisu` | `basisu.xi` | the only module with `extern "C"`: raw 81-function surface + constants, owned-slot readers, flat result structs, safe wrappers |
| buffer bridge | `src/basisu_bridge.cpp` | the only place foreign pointers are touched; handles/transcode state stay inside C |
| zstd shim | `src/basisu_zstd_all.c` | compiles the vendored zstd amalgamation with the intrinsics pin |

Discipline (v0.64.4): no `x as *UInt8` handle casts, no bare `null` to C, no reads
through foreign pointers (B-20/B-24), no pointer arithmetic in XIOM, one owned slot per
out-param, no `&mut` of Result/struct-return temps (B-21), no `Result[Option[T]]` shapes
(flat `Basisu*` structs, B-26), `Str` equality via `string.str_compare` (not needed
here).

Buffer directions:

- C reads XIOM-owned inputs (source RGBA, KTX2 payload, transcode targets) by pointer.
- C writes into XIOM-owned outputs (KTX2 payload bytes, transcode blocks); XIOM reads
  them back byte-indexed.
- The one C-owned region (`comp_params`' compressed bytes) is `memcpy`'d into an
  XIOM-owned slot inside the bridge and never handed out.
- `bt_alloc`/`bu_alloc` regions are written and read **inside C** (allocator probe); they
  never reach XIOM.

Bridge return codes are mapped to typed `Err(Str)` messages by the wrappers:

| Wrapper | Ok | Err |
|---------|----|-----|
| `basisu_encode_ktx2` | `BasisuEncodeResult` (size + copy_ok) | encoder rc-specific messages |
| `basisu_ktx2_info` | `BasisuKtx2Info` | `invalid or truncated KTX2 payload` / bridge rc |
| `basisu_ktx2_level_info` | `BasisuLevelInfo` | invalid payload / start_transcoding failed / level unavailable |
| `basisu_transcode` | `BasisuTranscodeResult` | invalid payload / start failed / transcode failed / `output buffer too small (need N bytes)` |

Owned-slot conventions: scalar probes use one 4-byte little-endian slot per out-param
(read byte-wise). The metadata probes (`xbu_info_probe` 30 slots / 128 bytes,
`xbu_level_probe` 10 slots / 40 bytes) use a slots buffer in which every value has its
own 4-byte slot at a documented offset (layout in `src/basisu_bridge.cpp` and
`basisu.xi`); the bridge capacity-checks the buffer before writing.

Known upstream finding (workaround documented in the bridge): a freshly created
transcode state skips level-0 decompression of KTX2 zstd payloads because the C wrapper
value-initializes `m_uncomp_data_level_index` to 0 instead of -1; the bridge calls
`bt_ktx2_transcode_image_level` with `state_handle = 0` (the internal state cleared by
`ktx2_transcoder::init`) while still covering `bt_ktx2_create_transcode_state` /
`bt_ktx2_destroy_transcode_state`. Details: `PROVENANCE.md` section 4.

## 5. Test matrix (recorded)

| Configuration | Command | Result |
|---------------|---------|--------|
| Vendored C API path (transcoder + encoder + zstd) | `scripts/port.ps1 -Package xiom.basisu -TimeoutSec 1500` | **PASS 30/30 x2** -- versions 250/250, allocator round trip, full format-helper surface, UASTC LDR 4x4 encode (1,696-byte KTX2, 6 mips), metadata + per-level info, BC1 level 0/1 (512/128 bytes), ETC1 (512), ASTC 4x4 (1,024), RGBA32 (4,096, mean abs err 1,745 milli vs source, opaque alpha), corrupt/identifier-only/truncated payloads typed-rejected, ETC1S encode (797 bytes) -> BC1, zstd-supercompressed UASTC (1,115 bytes) -> BC1 (zstd decode path) |

No SKIP path exists (the library is compiled in). `port.args.json` passes 35
`--c-source` TUs plus `--cxx-standard 17`; the packages runner resolves
`${PACKAGE_DIR}`. Wall time ~70-80 s (compile + link dominates); the
`-TimeoutSec 1500` watchdog covers it.

## 6. Scope and non-goals

In scope (0.1.0): runtime KTX2 -> GPU-format transcoding (BC/ETC/PVRTC/ASTC/RGBA via
`TF_*`), full KTX2 metadata and per-level inspection, and cook-time encoding through the
pinned encoder C API (`bu_*`: ETC1S, UASTC LDR/HDR, XUASTC LDR, ASTC LDR/HDR, XUBC7;
mipmap generation; KTX2 output; zstd supercompression).

Non-goals: `.basis` v1 payload transcoding, C++ class-level APIs, OpenCL acceleration,
the CLI tool's image/container I/O, GPU upload (the package stops at bytes), streaming
cursors (KTX2 level index already gives per-level addressing through the API).
