
set floorplan_file "CHIP.fp"
#write_io_file CHIP.save.io

if {[file exists $floorplan_file]} {
    read_floorplan $floorplan_file
    set_db  [get_db insts -if {.base_cell.base_class == pad}] .place_status  fixed
    set_instance_placement_status -all_hard_macros -status fixed
} else {
#== Lab step 10 ==
    loadIoFile ../design/CHIP.io
    floorPlan -site core -r 1 0.7 80.0 80.0 80.0 80.0
    loadIoFile ../design/CHIP.io -noAdjustDieSize
    source my_apr_script/swap_io_hv.tcl
    do_swap_io
    #floorPlan -site core -b 0.0 0.0 614.43 613.704 50.04 49.968 564.39 563.664 130.05 129.984 484.38 483.648
    floorPlan -site core -b 0.0 0.0 627.39 626.496 50.04 49.968 577.35 576.48 130.05 129.984 497.34 496.32

    loadIoFile ../design/CHIP.io -noAdjustDieSize
    checkFPlan 
    snapFPlan -all
    checkFPlan -outFile check_floorplan.log
    saveDesign dbs/floorplan.enc

#== Lab step 11 ==
    #set_db inst:IO_PG4 .orient MY90
    #set_db inst:CORE_PG2 .orient MX90
    #set_db inst:CORE_PG3 .orient MY
    #set_db inst:IO_PG2 .orient MX90
#== Lab step 12 ==
    source my_apr_script/create_bump.tcl
    source my_apr_script/delete_bump.tcl
#== Lab step 13 ==
#== Lab step 14 ==
    source my_apr_script/add_io_fillers.tcl
    #fix io
    set_db  [get_db insts -if {.base_cell.base_class == pad}] .place_status  fixed
    addHaloToBlock {0.96 0.96 0.96 0.96} -allBlock
    addRoutingHalo -allBlocks -space 0.18 -bottom M1 -top M9
    if {[file exists golden_mimic_power_mesh.tcl]} {
        puts "use golden_mimic_power_mesh.tcl"
        source golden_mimic_power_mesh.tcl
    } else {
        set_macro_place_constraint -pg_resource_model "M1 0.1 M2 0.1 M3 0.1 M4 0.1 M5 0.1 M6 0.1 M7 0.1 M8 0.1 M9 0.1"
    }
#== Lab step 15 ==
    source my_apr_script/create_relative_floorplan.tcl
#== Lab step 16 ==
    source my_apr_script/set_macro_place_constraint.tcl
    place_design -concurrent_macros
#== Lab step 17 ==
    # place_macro_detail
    #pack_align_macros
    #source my_apr_script/snap_block_to_raw.tcl
    #fix sram
    setInstancePlacementStatus -allHardMacros -status fixed
    delete_relative_floorplan -all
#== Lab step 18 ==
    set_db finish_floorplan_active_objs   [list macro soft_blockage core]
    finishFloorplan  -fillPlaceBlockage soft 20.0
    set_db [get_db insts -if {.base_cell.class == core}] .place_status unplaced
    saveDesign dbs/floorplan.enc
    #write_db  -oa_lib_cell_view {implementation CHIP before_pns}
#== Lab step 19 ~ step 30 ==
    source my_apr_script/pns.tcl
    runPGPlan
#== Lab step 31 ==
    saveDesign dbs/powerplan.enc
    #write_db  -oa_lib_cell_view {implementation CHIP pns}
    write_floorplan $floorplan_file
    #place_design
}

