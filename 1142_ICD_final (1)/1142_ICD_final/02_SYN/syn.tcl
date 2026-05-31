set ProjRoot "/share1/tech/ADFP" 

set company {NTUEE}
set designer {Student}

set search_path [concat  [list . $ProjRoot/Executable_Package/Collaterals/IP/stdcell/N16ADFP_StdCell/CCS .] $search_path]
set target_library [list "N16ADFP_StdCellss0p72v125c_ccs.db"]
set link_library [list "dw_foundation.sldb" "N16ADFP_StdCellss0p72v125c_ccs.db"]
set symbol_library [list "generic.sdb"]
set synthetic_library [list "dw_foundation.sldb"]
set default_schematic_options {-size infinite}

set hdlin_translate_off_skip_text "TRUE"
set edifout_netlist_only "TRUE"
set verilogout_no_tri true
set hdlin_enable_presto_for_vhdl "TRUE"
set hdlin_auto_save_templates "TRUE"
set sh_enable_line_editing true
set sh_line_editing_mode emacs
set compile_fix_multiple_port_nets "TRUE"

sh mkdir -p Netlist
sh mkdir -p Report

set DESIGN "core"

# Import Design
analyze -format verilog "../01_RTL/core.v"
elaborate $DESIGN
current_design $DESIGN
uniquify
link

source -echo -verbose ./core.sdc
set high_fanout_net_threshold 0
set_fix_multiple_port_nets -all -buffer_constants [get_designs *]
check_design
# Compile Design
compile_ultra -no_autoungroup

# Dump Report
report_area > "./Report/${DESIGN}_syn.area"
report_timing -max_path 20 -delay_type max > "Report/${DESIGN}_syn.max.timing"
report_timing -max_path 20 -delay_type min > "Report/${DESIGN}_syn.min.timing"
report_timing > "./Report/${DESIGN}_syn.timing"

# Output Design
set bus_inference_style {%s[%d]}
set bus_naming_style {%s[%d]}
set hdlout_internal_busses true
change_names -hierarchy -rule verilog
define_name_rules name_rule -allowed {a-z A-Z 0-9 _} -max_length 255 -type cell
define_name_rules name_rule -allowed {a-z A-Z 0-9 _[]} -max_length 255 -type net
define_name_rules name_rule -map {{"\\*cell\\*" "cell"}}
define_name_rules name_rule -case_insensitive

remove_unconnected_ports -blast_buses [get_cells -hierarchical *]
set verilogout_higher_designs_first true
write -format ddc     -hierarchy -output "./Netlist/${DESIGN}_syn.ddc"
write -format verilog -hierarchy -output "./Netlist/${DESIGN}_syn.v"
write_sdf -version 2.1 ./Netlist/${DESIGN}_syn.sdf
write_sdc ./Netlist/${DESIGN}_syn.sdc

check_design
report_timing
report_area
exit
