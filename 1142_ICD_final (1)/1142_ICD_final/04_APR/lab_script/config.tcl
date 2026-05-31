
#set_db net:io_rte .skip_routing true
#setPlaceMode -place_detail_legalization_inst_gap 2

remove_assigns
set init_no_new_assigns 1

setDesignMode -process 16
setNanoRouteMode -routeTopRoutingLayer 9
setNanoRouteMode -routeBottomRoutingLayer 2

createBasicPathGroups -reset
createBasicPathGroups -expanded

setAnalysisMode -analysisType onChipVariation
setAnalysisMode -cppr both
set_timing_derate -max -early 0.8 -late 1.0
set_timing_derate -min -early 1.0 -late 1.1

setTieHiLoMode -maxFanout 10
setTieHiLoMode -maxDistance 100
setTieHiLoMode -cell {TIEHBWP20P90 TIELBWP20P90 }

setFillerMode -preserveUserOrder true
setFillerMode -core {FILL64BWP16P90 DCAP32BWP16P90 DCAP16BWP16P90 DCAP8BWP16P90 DCAP4BWP16P90 FILL2BWP16P90 FILL2BWP16P90LVT FILL1BWP16P90 FILL1BWP16P90LVT}

#setNanoRouteMode -routeInsertAntennaDiode true
#setNanoRouteMode -routeAntennaCellName {}

source -quiet lab_script/set_activity.tcl
set_power_analysis_mode -write_profiling_db false
set_power_analysis_mode -write_static_currents false

setDesignMode -earlyClockFlow true
