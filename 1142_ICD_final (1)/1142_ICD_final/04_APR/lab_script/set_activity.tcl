set_power_analysis_mode -method static
set_power_analysis_mode -corner max
set_power_analysis_mode -create_binary_db true
set_power_analysis_mode -write_static_currents true
set_power_analysis_mode -honor_negative_energy true
set_power_analysis_mode -ignore_control_signals true

set_default_switching_activity -reset
set_default_switching_activity -input_activity 0.2 -period 8.0
read_activity_file -reset
read_activity_file -format TCF -scope CHIP ./sim/pre_sim/CHIP.tcf
# read_activity_map_file -rtl_to_gate ../genus/name_map.rpt

#set_power -reset
#set_dynamic_power_simulation -reset
#set_power_analysis_mode -power_grid_library techonly.cl

