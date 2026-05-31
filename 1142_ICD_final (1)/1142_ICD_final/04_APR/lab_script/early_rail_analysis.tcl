set_rail_analysis_mode -method era_static -power_switch_eco false -generate_movies false -save_voltage_waveforms false -accuracy xd -power_grid_library techonly.cl -process_techgen_em_rules false -enable_rlrp_analysis false -vsrc_search_distance 50 -ignore_shorts false -enable_manufacturing_effects false -report_via_current_direction false
create_power_pads -net VDD -auto_fetch
create_power_pads -net VDD -vsrc_file CHIP_VDD.pp
create_power_pads -net VSS -auto_fetch
create_power_pads -net VSS -vsrc_file CHIP_VSS.pp
set_pg_nets -net VDD -voltage 0.8 -threshold 0.76
set_pg_nets -net VSS -voltage 0 -threshold 0.04
set_rail_analysis_domain -name PD -pwrnets { VDD} -gndnets { VSS}
set_power_data -reset
set_power_data -format current -scale 1 {static_VDD.ptiavg static_VSS.ptiavg}
set_power_pads -reset
set_power_pads -net VDD -format xy -file CHIP_VDD.pp
set_power_pads -net VSS -format xy -file CHIP_VSS.pp
set_package -reset
set_package -spice {} -mapping {}
set_net_group -reset
set_advanced_rail_options -reset
set_db power_grid_libraries techonly.cl
analyze_rail -type domain -results_directory ./ PD
