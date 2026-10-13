# PIN: vendored FidelityFX-SDK surface

Copied **verbatim** (byte-exact) from the pinned upstream clone at
`E:\repos\FidelityFX-SDK`; nothing was edited after copying.

| Field | Value |
|---|---|
| Upstream | https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK |
| Tag | `v2.3.0` |
| Commit | `60f4ea81909200d8542eca14dccb2628b763a9a3` |
| Commit date | 2026-06-24 |
| Release name | AMD FSR SDK 2.3.0 "Redstone" |
| License | MIT for every vendored file (each is listed by path in `vendor/fidelityfx/LICENSE.md`; AMD's binary-redistribution default applies to non-listed SDK bodies, which are NOT vendored here) |
| Files | 92 |

## Per-file SHA256 (vendor tree)

| File | Bytes | SHA256 |
|---|---|---|
| `LICENSE.md` | 61784 | `F0DA09D71AD5C82759A179E774535D4A829E5C96C49294167C1152402B2CB400` |
| `api/include/ffx_api.h` | 10939 | `91F7F4A9111D18996E3BAE083BF82D47AC6497DE144B352ABFCA44F07D2871C4` |
| `api/include/ffx_api_loader.h` | 3039 | `10795186FD2A8FF53BB13AA0C81079C7FFD4A0B1BB501C629ED0B874C492A20B` |
| `api/include/ffx_api_types.h` | 13892 | `B54FBD96A0EED82662A49C00E28E5368AB69959F9856DAE5C12FED109D123D66` |
| `api/include/dx12/ffx_api_dx12.h` | 11595 | `2082D6C2914E9C2FA9FAE6247D35F64C643CCB703311C83C8DBA9A35356BC711` |
| `api/internal/ffx_assert.h` | 5450 | `81470B9C46CE2F392A35DDC29FFE753BAA9D22714AB7DB50C1E9FC30408D2095` |
| `api/internal/ffx_error.h` | 4339 | `012CCCF08DCC3BA18BE8AEDCA985D6AD2881877012465340CFB45253FD165E24` |
| `api/internal/ffx_interface.h` | 29885 | `692BBB0C8A5C4A549CE4C04D12B57788974CBAA2AC09FF6D2AA945CE8ACC56B3` |
| `api/internal/ffx_internal_types.h` | 51838 | `75F7AED3AF021CDC51AA10F306D208A7A1B6C5A639DD0125A1FB7C3C72CC4041` |
| `api/internal/ffx_message.h` | 3441 | `E7870510725BDEB55C052876E811143EF60F3A246AC24ABEBC5F3E9509562D3F` |
| `api/internal/ffx_util.h` | 7593 | `D9094C48483E83924D7611C8DA9B57C28577F90999F17D7BBC68AFBC1559C1FB` |
| `api/internal/gpu/ffx_common_types.h` | 16722 | `CBB4DD4413F614E01F68473470189D226A4339535C02E1D0C1805D4341F6D764` |
| `api/internal/gpu/ffx_core.h` | 2602 | `A6995CB22C9FF6F09F2E106CD7F8D3D0C3C0DF9952ADE52DD29BBCC15A91716A` |
| `api/internal/gpu/ffx_core_cpu.h` | 15740 | `7F0D8A77B776DB38CE076AF3EA6FDED39DB7DB8FB46AC9A08C993C7CCD9EED9B` |
| `api/internal/gpu/ffx_core_gpu_common.h` | 90463 | `80D6F05489F6A94B90DFC6C809C29B9099FBACE40F82EA39A48B1EB83C60BF3D` |
| `api/internal/gpu/ffx_core_gpu_common_half.h` | 101300 | `57829DA6DC98A2133168EDCAE9336AA1B390F4F4C938CF7DFD7CF7870A01FBBC` |
| `api/internal/gpu/ffx_core_hlsl.h` | 63740 | `357A176CBAF684FE7823749C7734267C58DFB023C68AFE2CBBF0D57955746306` |
| `api/internal/gpu/ffx_core_portability.h` | 1728 | `D52E8195EDB369254BF5FC4F7BC20494C0695B7D9D3CAE9D94639C1946754805` |
| `framegeneration/fsr3/dx12/FrameInterpolationSwapchainDebugPacingPS.h` | 27948 | `E5B7DCDAD6FFAC76CB4861D666A599052A62208ACA03118D2BA3CB1798D4ECE9` |
| `framegeneration/fsr3/dx12/FrameInterpolationSwapchainDebugPacingVS.h` | 22686 | `D798903BAF79F0681310AE7E2C868CDBD4DF11295A4C0C550E01002DAD70EAB9` |
| `framegeneration/fsr3/dx12/FrameInterpolationSwapchainUiCompositionPS.h` | 30409 | `E8AEFED663ACE0EDF9697A306EC3DD59A0C97849601AEE162CDD68ED775011B6` |
| `framegeneration/fsr3/dx12/FrameInterpolationSwapchainUiCompositionPremulPS.h` | 30277 | `8A07E9F12A3BF1E967ECC6F8D38A1D61FDDCB677BB65DB45ACF52A466CBAC506` |
| `framegeneration/fsr3/dx12/FrameInterpolationSwapchainUiCompositionPremulVS.h` | 22638 | `048771EF6898086D1D702BB230C650C5D919451F00FEF1964AF127571A1F932D` |
| `framegeneration/fsr3/dx12/FrameInterpolationSwapchainUiCompositionVS.h` | 22638 | `048771EF6898086D1D702BB230C650C5D919451F00FEF1964AF127571A1F932D` |
| `framegeneration/fsr3/include/ffx_frameinterpolation.h` | 25274 | `6691C32B098E979774259CBAA205F0713AFAFFF8A12DFA51F99B4A6BF797BDB0` |
| `framegeneration/fsr3/include/ffx_opticalflow.h` | 13205 | `C8B4EB3DFF72AD592D995A84048BCA10F3361EEB8DA58291D330466E51F9C146` |
| `framegeneration/fsr3/include/gpu/frameinterpolation/ffx_frameinterpolation.h` | 8368 | `4E6F86C3BADA1F320685B04777072414453D4FEAB733E94D334760844954F936` |
| `framegeneration/fsr3/include/gpu/frameinterpolation/ffx_frameinterpolation_callbacks_hlsl.h` | 32705 | `CA2C3B2EBD79282659BDC8860297964CF07EF879F241B912ADC343593E3E7957` |
| `framegeneration/fsr3/include/gpu/frameinterpolation/ffx_frameinterpolation_common.h` | 16653 | `7B690CA3E4BE5DCA25D69B2295CB27B85988B0E4D59E3AAFBD0076136A171B27` |
| `framegeneration/fsr3/include/gpu/frameinterpolation/ffx_frameinterpolation_compute_game_vector_field_inpainting_pyramid.h` | 4200 | `1AAC4DB380245A69695315A2B98771986DB6F9CC4A8E46DB6539163B0693DEC4` |
| `framegeneration/fsr3/include/gpu/frameinterpolation/ffx_frameinterpolation_compute_inpainting_pyramid.h` | 4182 | `FE3FFE78E5646921F2FEB4F05F542C28AC19D914089141F6FB470C218060C975` |
| `framegeneration/fsr3/include/gpu/frameinterpolation/ffx_frameinterpolation_debug_view.h` | 6315 | `F4BDD050780DF501106E5BF51DA1966A1187488485B27A247858ACD3E15F3668` |
| `framegeneration/fsr3/include/gpu/frameinterpolation/ffx_frameinterpolation_disocclusion_mask.h` | 7512 | `5768901A98F8A5360F2718C0858544724FE42AABFB3F30B84E37DC50DFF0D563` |
| `framegeneration/fsr3/include/gpu/frameinterpolation/ffx_frameinterpolation_game_motion_vector_field.h` | 6924 | `1EF3EF31B6CF6AF5CE19EC09BE2B9717BFF9C1DB8786F13CFAFF9E627191DBC7` |
| `framegeneration/fsr3/include/gpu/frameinterpolation/ffx_frameinterpolation_inpainting.h` | 5432 | `F1EBFF6200F3E560E340CA8F5EAC9905D32D599BB740E55DD5FDC29FE4793B4D` |
| `framegeneration/fsr3/include/gpu/frameinterpolation/ffx_frameinterpolation_optical_flow_vector_field.h` | 5427 | `1B9B2488ED96AD563B48ECC9AC50A16DE23A8B034C375F05A0F12A5724444004` |
| `framegeneration/fsr3/include/gpu/frameinterpolation/ffx_frameinterpolation_reconstruct_dilated_velocity_and_previous_depth.h` | 4906 | `D12BEE54C45F55067698B1F284165C21B0EB83CAC654D3532A704A48F2B5E5B5` |
| `framegeneration/fsr3/include/gpu/frameinterpolation/ffx_frameinterpolation_reconstruct_previous_depth.h` | 3065 | `8FD84ADE28533F8DE5B31614CBCC01E556ABE72F6AFE852C4F70AF60E3AC000C` |
| `framegeneration/fsr3/include/gpu/frameinterpolation/ffx_frameinterpolation_resources.h` | 6738 | `B991AEB3B918BD67A14EB95A7C98B838298A04F8B9E005D7FB0FDA0221978392` |
| `framegeneration/fsr3/include/gpu/frameinterpolation/ffx_frameinterpolation_setup.h` | 2107 | `B6CC980D526BA3C9CEF97C87392B6844AC363BE5CF86B6503B6CBE5B278D1DA0` |
| `framegeneration/fsr3/include/gpu/opticalflow/ffx_opticalflow_callbacks_hlsl.h` | 25643 | `F5912151C47D551FE68E46F38A5204ADC6882E5EC54DAB4CB14795D57801D5F2` |
| `framegeneration/fsr3/include/gpu/opticalflow/ffx_opticalflow_common.h` | 3548 | `AA31EB94614CFD84220AFAB5B67279691D4DFB3AD50E25B2C1188AD8DBECDE50` |
| `framegeneration/fsr3/include/gpu/opticalflow/ffx_opticalflow_compute_luminance_pyramid.h` | 3353 | `552838900F0CE84EAA0420E69040AEC507C83DD604E36DEC59120FC7C13A15B9` |
| `framegeneration/fsr3/include/gpu/opticalflow/ffx_opticalflow_compute_optical_flow_v5.h` | 11166 | `F6CE774EDDCC5C05FB529E1CA4BF16DDE855DC0D9D17E3A0E148D9EB75AD1094` |
| `framegeneration/fsr3/include/gpu/opticalflow/ffx_opticalflow_compute_scd_divergence.h` | 7034 | `7607DE2A006E1D6CF819DE937AACF8310C73132FE4E8BC181F5FD7BF9BD571DE` |
| `framegeneration/fsr3/include/gpu/opticalflow/ffx_opticalflow_filter_optical_flow_v5.h` | 2180 | `AB7BB766E17882779E304FF0588110420DEDBAAD671A64ADF220DB2A3E1C62C6` |
| `framegeneration/fsr3/include/gpu/opticalflow/ffx_opticalflow_generate_scd_histogram.h` | 3744 | `038F5F405EE5CFA85889002A8D3ABAAFBC21C5890EC8293948E527EED50D756F` |
| `framegeneration/fsr3/include/gpu/opticalflow/ffx_opticalflow_prepare_luma.h` | 4083 | `18A5EB0E1B610CF3AAD6C112EB16E84F84DB251F4ABAC8B4280FD41B5B5E67B3` |
| `framegeneration/fsr3/include/gpu/opticalflow/ffx_opticalflow_resources.h` | 3678 | `44F7B2848B85C918A6131835D72699D8050F636FE9F44F41B43D3AAF98AE1D26` |
| `framegeneration/fsr3/include/gpu/opticalflow/ffx_opticalflow_scale_optical_flow_advanced_v5.h` | 3697 | `4679CFFAB5AA7DE1170B8D18388FE6A7A19D754B9772278040E2F1E419ED565E` |
| `framegeneration/fsr3/include/gpu/spd/ffx_spd.h` | 43628 | `6CAB3CE5575509E753BBC73B78BCAAF44BAE67C04D615C1983B8AAF9B5DBF1B7` |
| `framegeneration/include/ffx_framegeneration.h` | 26500 | `83090E298D9D0DB4CDBA76A4E0846ACF80FE863233F7E9ECBFDD97DF5CC646BD` |
| `framegeneration/include/ffx_framegeneration_api_types.h` | 5048 | `F1C60A03A538895FEA26542FB721CA60A7A4C9E91A885FAE3C81FB33C294FBBA` |
| `framegeneration/include/dx12/ffx_api_framegeneration_dx12.h` | 10708 | `8C1DE87E4C6D68908724A8AD71124297A8F7092CDF21AA032D361DE1C747CF26` |
| `upscalers/fsr3/include/ffx_fsr2.h` | 35913 | `BEEBF1A2A2B78A22C2138F42A26F998A83BA281911D2CF8B6562CC3B3A65C3E6` |
| `upscalers/fsr3/include/ffx_fsr3upscaler.h` | 40581 | `A95D91239C325F0227092A93A77669C67F44F5F04BFBF7AEAF3569A0CDA910D3` |
| `upscalers/fsr3/include/ffx_spd.h` | 9400 | `85EC7A9EF08D68F0F414370A8924A9C7C7E3D6B6118C394DEE5D30472C31B280` |
| `upscalers/fsr3/include/gpu/fsr1/ffx_fsr1.h` | 68266 | `0BC32EB11E786EF39360B67E13FC9F49F6BB0AECDBFA84B120E1EBC8D6A2218C` |
| `upscalers/fsr3/include/gpu/fsr2/ffx_fsr2_accumulate.h` | 13373 | `B4671C7CE89773DE94999DA17BB21621EEC2A00E8104F5A298440259EBC12D71` |
| `upscalers/fsr3/include/gpu/fsr2/ffx_fsr2_callbacks_hlsl.h` | 33851 | `7B19B83C5D06798A9E1B90C368ED71A02A8B511222C8C32C3508EA00F7EB2A9C` |
| `upscalers/fsr3/include/gpu/fsr2/ffx_fsr2_common.h` | 20280 | `3A72DA1D1FEA2CA7C5801826A68FF3FB8389460B100A795939BA447B33CC6BCD` |
| `upscalers/fsr3/include/gpu/fsr2/ffx_fsr2_compute_luminance_pyramid.h` | 5585 | `AAEEDD5698D21A7353624525CA361621AB3DFB8A7C519467968C5DA0A6C109F1` |
| `upscalers/fsr3/include/gpu/fsr2/ffx_fsr2_depth_clip.h` | 11637 | `4BE8CB1899B6498D9C2377BFF508F1B41D4F6B6617AD622A0712ADB71F52DED7` |
| `upscalers/fsr3/include/gpu/fsr2/ffx_fsr2_lock.h` | 3803 | `9B6EDA2EA12B866503AB1DCBB2D728B1F645441DD77C773C1CB48DCFE848DCFF` |
| `upscalers/fsr3/include/gpu/fsr2/ffx_fsr2_postprocess_lock_status.h` | 4779 | `401212C0C946718DEDEB041DD58FEC80E14A7F0BF92373B1C123732AB3B5D7B1` |
| `upscalers/fsr3/include/gpu/fsr2/ffx_fsr2_rcas.h` | 3783 | `A1762F8F2F4EFC12C6CB1C90B3161E4A3CBC38128E55DBEB608923A2247A48A9` |
| `upscalers/fsr3/include/gpu/fsr2/ffx_fsr2_reconstruct_dilated_velocity_and_previous_depth.h` | 5622 | `F5C60AF71328E18109D646C7C1BF9482DEB6FD1C69D768D967F142B5ADCD99BA` |
| `upscalers/fsr3/include/gpu/fsr2/ffx_fsr2_reproject.h` | 5485 | `A9BA3F10498ECA590B910A70F476A78BD3B776007101992E004B22FAB7EE45C8` |
| `upscalers/fsr3/include/gpu/fsr2/ffx_fsr2_resources.h` | 7969 | `54D326ABE0A3B97B98F79F495084D3766ED57BB5AF4260BBFAD9A04EECFBFAB3` |
| `upscalers/fsr3/include/gpu/fsr2/ffx_fsr2_sample.h` | 29867 | `87008A8D73083C9F1CD3DE78ED7E2690C59C6F48538C41DC34BF4F25EE96469A` |
| `upscalers/fsr3/include/gpu/fsr2/ffx_fsr2_tcr_autogen.h` | 10969 | `63F69E4FB1B5EBCDBB747EDF258A431924A9D4D7A231AC5A792608C4DE283A8F` |
| `upscalers/fsr3/include/gpu/fsr2/ffx_fsr2_upsample.h` | 21558 | `3ABCDD0EB7297EECC3415543101F6F9EDA61DB100130C294B20DF02CC205F3E4` |
| `upscalers/fsr3/include/gpu/fsr3/ffx_fsr3_callbacks_hlsl.h` | 1277 | `5C3EE60EA0ED700AA75E8ADE5B3B1053B8ACB805ACBB3EC4B77DE3BED96752C2` |
| `upscalers/fsr3/include/gpu/fsr3/ffx_fsr3_common.h` | 1354 | `25E1B3A7E0F6BD86EA9C65DB6533B97172922D4982B4E0AE4F951C6857F4B5D7` |
| `upscalers/fsr3/include/gpu/fsr3/ffx_fsr3_resources.h` | 3047 | `251C34CECD00C69F7B3A908FDEA69C14572DFE080D0951138E5E523089B6DB82` |
| `upscalers/fsr3/include/gpu/fsr3upscaler/ffx_fsr3upscaler_accumulate.h` | 8938 | `7463CB43D91C854CC17E1BF3AD063A50C51497C74C7D10546E362C59D794C677` |
| `upscalers/fsr3/include/gpu/fsr3upscaler/ffx_fsr3upscaler_callbacks_hlsl.h` | 30521 | `04C884B6DBDF44166BF09A78E6391FBFFCE6F4523580A4E8FD211BF835CBA403` |
| `upscalers/fsr3/include/gpu/fsr3upscaler/ffx_fsr3upscaler_common.h` | 13756 | `3011713E784BF794DC415697B167679B7D74FF39FFDC661B67E2425F0812BB97` |
| `upscalers/fsr3/include/gpu/fsr3upscaler/ffx_fsr3upscaler_debug_view.h` | 5888 | `473FE2BD7A4F9FF787D5492E2161BC8E675CD66CB4BDE0E0F80906AC2330FDD0` |
| `upscalers/fsr3/include/gpu/fsr3upscaler/ffx_fsr3upscaler_luma_instability.h` | 5437 | `693E746C50F209AA102ADC25073BFCF2255F2458C1F773E85D13933CAF87556D` |
| `upscalers/fsr3/include/gpu/fsr3upscaler/ffx_fsr3upscaler_luma_pyramid.h` | 6380 | `7DCCB207AD0EF1035C44DA16AE804D3B9A943E25DBA80F2E8A94BC52B4E6DFC7` |
| `upscalers/fsr3/include/gpu/fsr3upscaler/ffx_fsr3upscaler_prepare_inputs.h` | 5992 | `4C9DD501C4D0BB1E0534EEB5AE71B4083D27DD94871FC35179C61A08CF0F07AF` |
| `upscalers/fsr3/include/gpu/fsr3upscaler/ffx_fsr3upscaler_prepare_reactivity.h` | 12746 | `6EF8E3A9B01A0AC7DA351D7BB8AD758A0811973E9CF426F52B0823A5C8A936ED` |
| `upscalers/fsr3/include/gpu/fsr3upscaler/ffx_fsr3upscaler_rcas.h` | 3912 | `DE0E74696BDC1D5B620DC9E519E96985ADE86BF1B5DC966EC94468DADD1A1520` |
| `upscalers/fsr3/include/gpu/fsr3upscaler/ffx_fsr3upscaler_reproject.h` | 3332 | `1530C94D1C3B331BEF6AB956ED93ED622A1F299B84BF5E31E4BA35E14B3B54B5` |
| `upscalers/fsr3/include/gpu/fsr3upscaler/ffx_fsr3upscaler_resources.h` | 7738 | `134142B1B70BD4BE838116CBA05841BA375009AF71404D1851D5DD411921E0E9` |
| `upscalers/fsr3/include/gpu/fsr3upscaler/ffx_fsr3upscaler_sample.h` | 28628 | `BA4F98D81079D08C942912F4988B0D60C068FDC7DF04683DB52573780F70C999` |
| `upscalers/fsr3/include/gpu/fsr3upscaler/ffx_fsr3upscaler_shading_change.h` | 2776 | `1D18CD9BBC3F2C2840AB707BE15101CBB618E908C969132EAEFD76D684624817` |
| `upscalers/fsr3/include/gpu/fsr3upscaler/ffx_fsr3upscaler_shading_change_pyramid.h` | 9764 | `1A00C5257E7B721E8516B9438491287A520D05BA7CDF4531B98DAE92F75BD949` |
| `upscalers/fsr3/include/gpu/fsr3upscaler/ffx_fsr3upscaler_upsample.h` | 29131 | `1DD43D35FBE6A587B6C7C9EC37E4CDFC4B1F0126E948D2F1B83E1A796F2C97E4` |
| `upscalers/fsr3/include/gpu/spd/ffx_spd.h` | 43628 | `6CAB3CE5575509E753BBC73B78BCAAF44BAE67C04D615C1983B8AAF9B5DBF1B7` |
| `upscalers/include/ffx_upscale.h` | 19543 | `F13ABCDD4389E22AA50562A90255BEC9511E004722C7D2BF6F959D92FD78355C` |

Re-carve: fetch the new release tag into `E:\repos\FidelityFX-SDK`, re-copy the
same file set byte-exact, re-run `python tools/gen_fidelityfx.py`, review the diff
(counts, offsets, blob hashes), re-run the suite x2, re-record `STATUS.json`.
