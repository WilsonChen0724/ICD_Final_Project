set h_offset 6
set h_space 8

set v_offset 6
set v_space 8

delete_relative_floorplan -all

# left top side
create_relative_floorplan -ref_type core_boundary -horizontal_edge_separate "1  [expr -1 *$v_offset]  1" -vertical_edge_separate "0  $h_offset  0" -ref aiot_mcu -place u_IDCT/tposemem_Bisted_RF_2P_ADV64x16_RF_2P_ADV64x16_u0_i_rf_2p_SRAM_i0  -orient R0
create_relative_floorplan -ref_type object -horizontal_edge_separate "1  0  1" -vertical_edge_separate "2  $h_space  0" -ref u_IDCT/tposemem_Bisted_RF_2P_ADV64x16_RF_2P_ADV64x16_u0_i_rf_2p_SRAM_i0 -place u_IDCT/tposemem_Bisted_RF_2P_ADV64x16_RF_2P_ADV64x16_u0_i_rf_2p_SRAM_i1 -orient R0
create_relative_floorplan -ref_type object -horizontal_edge_separate "3  [expr -1 * $v_space]  1" -vertical_edge_separate "0 0  0" -ref u_IDCT/tposemem_Bisted_RF_2P_ADV64x16_RF_2P_ADV64x16_u0_i_rf_2p_SRAM_i0 -place u_IDCT/tposemem_Bisted_RF_2P_ADV64x16_RF_2P_ADV64x16_u0_i_rf_2p_SRAM_i3 -orient R0
create_relative_floorplan -ref_type object -horizontal_edge_separate "1  0  1" -vertical_edge_separate "2  $h_space  0" -ref u_IDCT/tposemem_Bisted_RF_2P_ADV64x16_RF_2P_ADV64x16_u0_i_rf_2p_SRAM_i3 -place u_IDCT/tposemem_Bisted_RF_2P_ADV64x16_RF_2P_ADV64x16_u0_i_rf_2p_SRAM_i2 -orient R0


##== set macro  orientation
#set_db inst:u_IDCT/tposemem_Bisted_RF_2P_ADV64x16_RF_2P_ADV64x16_u0_i_rf_2p_SRAM_i0 .orient R0
#set_db inst:u_IDCT/tposemem_Bisted_RF_2P_ADV64x16_RF_2P_ADV64x16_u0_i_rf_2p_SRAM_i1 .orient R0
#set_db inst:u_IDCT/tposemem_Bisted_RF_2P_ADV64x16_RF_2P_ADV64x16_u0_i_rf_2p_SRAM_i2 .orient R0
#set_db inst:u_IDCT/tposemem_Bisted_RF_2P_ADV64x16_RF_2P_ADV64x16_u0_i_rf_2p_SRAM_i3 .orient R0


##== fix placed macro
#delete_relative_floorplan -all
set_db [get_db insts -if {.name=="u_IDCT/tposemem_Bisted_RF_2P_ADV64x16_RF_2P_ADV64x16_u0_i_rf_2p_SRAM_i*"}] .place_status fixed
