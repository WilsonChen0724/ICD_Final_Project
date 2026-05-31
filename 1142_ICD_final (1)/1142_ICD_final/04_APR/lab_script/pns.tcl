
proc createPowerStripeRail { direction layer nets offset width spacing pitch RTopLayer RBotLayer BTopLayer BBotLayer} {
    variable curRegionBKG

    set direction [expr {$direction eq "H" ? "horizontal" : "vertical" }]
   
    set_db add_stripes_ignore_block_check false
    set_db add_stripes_break_at none
    set_db add_stripes_route_over_rows_only false
    set_db add_stripes_rows_without_stripes_only false
    set_db add_stripes_extend_to_closest_target ring
    set_db add_stripes_stop_at_last_wire_for_area false
    set_db add_stripes_partial_set_through_domain false
    set_db add_stripes_ignore_non_default_domains false
    set_db add_stripes_trim_antenna_back_to_shape none
    set_db add_stripes_spacing_type edge_to_edge
    set_db add_stripes_spacing_from_block 0
    set_db add_stripes_stripe_min_length stripe_width
    set_db add_stripes_stacked_via_top_layer M5
    set_db add_stripes_stacked_via_bottom_layer M1
    set_db add_stripes_via_using_exact_crossover_size false
    set_db add_stripes_split_vias false
    set_db add_stripes_orthogonal_only true
    set_db add_stripes_allow_jog { block_ring }
    set_db add_stripes_skip_via_on_pin {  Block standardcell }
    set_db add_stripes_skip_via_on_wire_shape {  noshape Stripe  }
    addStripe -nets $nets -layer $layer -direction $direction -width $width -spacing $spacing -set_to_set_distance $pitch  -start_from bottom -start_offset $offset -switch_layer_over_obs false -padcore_ring_top_layer_limit $RTopLayer -padcore_ring_bottom_layer_limit $RBotLayer -block_ring_top_layer_limit $BTopLayer -block_ring_bottom_layer_limit $BBotLayer -use_wire_group 0 -snap_wire_center_to_grid none -uda "manual_rail"
}

proc createPowerStripe { direction layer nets offset width spacing pitch snap} {

    set LayerNum [get_db layer:$layer .route_index] 
    if {$LayerNum > 1} {
        set botLayerNum [expr $LayerNum - 1]
    }
    if {$LayerNum < 11} {
        set topLayerNum [expr $LayerNum + 1]
    }
    set botLayer    [get_db layer:$botLayerNum .name]
    set topLayer    [get_db layer:$topLayerNum .name]

    set direction [expr {$direction eq "H" ? "horizontal" : "vertical" }]
   
    set_db add_stripes_ignore_block_check false
    set_db add_stripes_break_at none
    set_db add_stripes_route_over_rows_only false
    set_db add_stripes_rows_without_stripes_only false
    set_db add_stripes_extend_to_closest_target ring
    set_db add_stripes_stop_at_last_wire_for_area false
    set_db add_stripes_partial_set_through_domain false
    set_db add_stripes_ignore_non_default_domains false
    set_db add_stripes_trim_antenna_back_to_shape none
    set_db add_stripes_spacing_type edge_to_edge
    set_db add_stripes_spacing_from_block 0
    set_db add_stripes_stripe_min_length stripe_width
    set_db add_stripes_stacked_via_top_layer $topLayer
    set_db add_stripes_stacked_via_bottom_layer $botLayer
    set_db add_stripes_via_using_exact_crossover_size false
    set_db add_stripes_split_vias false
    set_db add_stripes_orthogonal_only true
    set_db add_stripes_allow_jog { block_ring }
    set_db add_stripes_skip_via_on_pin {  standardcell }
    set_db add_stripes_skip_via_on_wire_shape {  noshape   }
    addStripe -nets $nets -layer $layer -direction $direction -width $width -spacing $spacing -set_to_set_distance $pitch -start_from bottom -start_offset $offset -switch_layer_over_obs false -max_same_layer_jog_length 2 -padcore_ring_top_layer_limit $topLayer -padcore_ring_bottom_layer_limit $botLayer -block_ring_top_layer_limit $topLayer -block_ring_bottom_layer_limit $botLayer -use_wire_group 0 -snap_wire_center_to_grid $snap 
}

proc createSelectBlockStripe { direction layer nets offset width spacing pitch snap} {

    set LayerNum [get_db layer:$layer .route_index] 
    if {$LayerNum > 1} {
        set botLayerNum [expr $LayerNum - 1]
    }
    if {$LayerNum < 11} {
        set topLayerNum [expr $LayerNum + 1]
    }
    set botLayer    [get_db layer:$botLayerNum .name]
    set topLayer    [get_db layer:$topLayerNum .name]

    set direction [expr {$direction eq "H" ? "horizontal" : "vertical" }]
    set_db add_stripes_ignore_block_check false
    set_db add_stripes_break_at none
    set_db add_stripes_route_over_rows_only false
    set_db add_stripes_rows_without_stripes_only false
    set_db add_stripes_extend_to_closest_target ring
    set_db add_stripes_stop_at_last_wire_for_area false
    set_db add_stripes_partial_set_through_domain false
    set_db add_stripes_ignore_non_default_domains false
    set_db add_stripes_trim_antenna_back_to_shape none
    set_db add_stripes_spacing_type edge_to_edge
    set_db add_stripes_spacing_from_block 0
    set_db add_stripes_stripe_min_length stripe_width
    set_db add_stripes_stacked_via_top_layer $topLayer
    set_db add_stripes_stacked_via_bottom_layer $botLayer
    set_db add_stripes_via_using_exact_crossover_size false
    set_db add_stripes_split_vias false
    set_db add_stripes_orthogonal_only true
    set_db add_stripes_allow_jog none
    set_db add_stripes_skip_via_on_pin {  standardcell }
    set_db add_stripes_skip_via_on_wire_shape {  noshape   }
    addStripe -nets $nets -layer $layer -direction $direction -width $width -spacing $spacing -set_to_set_distance $pitch -over_power_domain 1 -start_from bottom -start_offset $offset -switch_layer_over_obs false -max_same_layer_jog_length 2 -padcore_ring_top_layer_limit $topLayer -padcore_ring_bottom_layer_limit $botLayer -block_ring_top_layer_limit $topLayer -block_ring_bottom_layer_limit $botLayer -use_wire_group 0 -snap_wire_center_to_grid $snap
}

proc createRegionStripe { direction layer nets offset width spacing pitch region} {

    if { $region == "Core" } {
        set area [get_db designs .core_bbox]
    } elseif {$region == "Die" } {
        set area [get_db designs .bbox]
    } else {
        puts "unknow region"
        return;
    }

    set LayerNum [get_db layer:$layer .route_index] 
    set botLayerNum [expr $LayerNum - 1]
    if {$botLayerNum < 1 } {
        set botLayerNum 1
    }
    set topLayerNum [expr $LayerNum + 1]
    if {$topLayerNum > 11} {
        set topLayerNum 11
    } 
    set botLayer    [get_db layer:$botLayerNum .name]
    set topLayer    [get_db layer:$topLayerNum .name]

    set direction [expr {$direction eq "H" ? "horizontal" : "vertical" }]
   
    set_db add_stripes_ignore_block_check false
    set_db add_stripes_break_at none
    set_db add_stripes_route_over_rows_only false
    set_db add_stripes_rows_without_stripes_only false
    set_db add_stripes_extend_to_closest_target none
    set_db add_stripes_stop_at_last_wire_for_area false
    set_db add_stripes_partial_set_through_domain false
    set_db add_stripes_ignore_non_default_domains false
    set_db add_stripes_trim_antenna_back_to_shape none
    set_db add_stripes_spacing_type edge_to_edge
    set_db add_stripes_spacing_from_block 0
    set_db add_stripes_stripe_min_length stripe_width
    set_db add_stripes_stacked_via_top_layer $topLayer
    set_db add_stripes_stacked_via_bottom_layer $botLayer
    set_db add_stripes_via_using_exact_crossover_size false
    set_db add_stripes_split_vias false
    set_db add_stripes_orthogonal_only true
    set_db add_stripes_allow_jog { block_ring }
    set_db add_stripes_skip_via_on_pin {  standardcell }
    set_db add_stripes_skip_via_on_wire_shape {  noshape   }
    addStripe -nets $nets -layer $layer -direction $direction -width $width -spacing $spacing -set_to_set_distance $pitch -start_from bottom -start_offset $offset -switch_layer_over_obs false -max_same_layer_jog_length 2 -padcore_ring_top_layer_limit $topLayer -padcore_ring_bottom_layer_limit $botLayer -block_ring_top_layer_limit $topLayer -block_ring_bottom_layer_limit $botLayer -use_wire_group 0 -snap_wire_center_to_grid none -area $area
}


proc createPowerRing { nets hlayer vlayer width spacing offset wire_group } {
    set vLayerNum [get_db layer:$vlayer .route_index] 
    set hLayerNum [get_db layer:$hlayer .route_index] 
    if { $vLayerNum > $hLayerNum } {
        set botLayerNum $hLayerNum
        set topLayerNum $vLayerNum
    } else {
        set botLayerNum $vLayerNum
        set topLayerNum $hLayerNum
    }

    if {$botLayerNum >= 1} {
        set botLayerNum [expr $botLayerNum - 1]
    }
    if {$topLayerNum < 11} {
        set topLayerNum [expr $topLayerNum + 1]
    }
    set botLayer    [get_db layer:$botLayerNum .name]

    set_db add_rings_target default
    set_db add_rings_extend_over_row 0
    set_db add_rings_ignore_rows 0
    set_db add_rings_avoid_short 0
    set_db add_rings_skip_shared_inner_ring none
    set_db add_rings_stacked_via_top_layer $topLayerNum
    set_db add_rings_stacked_via_bottom_layer $botLayerNum
    set_db add_rings_via_using_exact_crossover_size 1
    set_db add_rings_orthogonal_only true
    set_db add_rings_skip_via_on_pin {  standardcell }
    set_db add_rings_skip_via_on_wire_shape {  noshape }
    addRing -nets $nets -type core_rings -follow core -layer [list top $hlayer bottom $hlayer left $vlayer right $vlayer] -width [list top $width bottom $width left $width right $width] -spacing [list top $spacing bottom $spacing left $spacing right $spacing] -offset [list top $offset bottom $offset left $offset right $offset] -center 0 -threshold 0 -jog_distance 0 -snap_wire_center_to_grid none -use_wire_group 1 -use_wire_group_bits $wire_group -use_interleaving_wire_group 1
    
}

#proc initializePG {} {
#    editDelete -physical_pin -use POWER
#    editDelete -use POWER
#}
#
#proc initializeRegionBKG {} {
#    variable curRegionBKG
#    array unset curRegionBKG
#
#    set Die  [dbget top.fplan.box -e]
#    set Core [dbget top.fplan.coreBox -e]
#    set STD  [dbget top.fplan.rows.box -e]
#
#    set curRegionBKG(Core) [dbshape $Die ANDNOT $Core -output rect]
#    set curRegionBKG(STD)  [dbshape $Die ANDNOT [dbShape $STD SIZEY 0.1] -output rect]
#}

proc runPGPlan {} {

#== Lab step 20 ==
    #=== core power ring
    #createPowerRing  nets      TBlayer LRlayer width spacing offset wire_group  
    #createPowerRing   {VDD VSS}   M10    M11     2.1     1       1.7    13
    #createPowerRing   {VDD VSS}   M8    M9      2.1     1       1.7    13
    #createPowerRing   {VDD VSS}   M8    M9      2     1.1       0.8    13
    createPowerRing   {VDD VSS}   M8     M7     2     1.1       0.8    13
    createPowerRing   {VDD VSS}   M6     M5     2     1.1      0.8    13
    editTrim -nets {VDD VSS} -layers {M8 M7 M6 M5}
    
#== Lab step 21 ==
    #=== sroute pad pin
    set_db route_special_via_connect_to_shape { ring }
    sroute -connect pad_pin -layerChangeRange { M1(1) M9(9) } -blockPinTarget nearestTarget -padPinPortConnect {allPort allGeom} -padPinTarget nearestTarget -padPinLayerRange { M1(1) M4(4) } -allowJogging 0 -crossoverViaLayerRange { M1(1) M9(9) } -nets { VDD VSS } -allowLayerChange 1 -targetViaLayerRange { M1(1) M9(9) }

#== Lab step 22 ==
    source my_apr_script/create_padpin_blockage.tcl

#== Lab step 23 ==
    #createPowerRing   {VDD VSS}   M4     M3     2     1.1      0.8    13

##== Lab step 24 ==
#    #=== block ring , to terminate followpin
#    add_rings -nets {VDD VSS} -type block_rings -around each_block -layer {top M4 bottom M4 left M3 right M3} -width {top 0.12 bottom 0.12 left 0.12 right 0.12} -spacing {top 0.1 bottom 0.1 left 0.1 right 0.1} -offset {top 0.6 bottom 0.6 left 0.6 right 0.6} -center 0 -threshold 0 -jog_distance 0 -snap_wire_center_to_grid none
#    add_rings -nets {VDD VSS} -type block_rings -around each_block -layer {top M4 bottom M4 left M5 right M5} -width {top 0.12 bottom 0.12 left 0.12 right 0.12} -spacing {top 0.1 bottom 0.1 left 0.1 right 0.1} -offset {top 0.6 bottom 0.6 left 0.6 right 0.6} -center 0 -threshold 0 -jog_distance 0 -snap_wire_center_to_grid none
#    
#== Lab step 25 ==
   source my_apr_script/create_block_blockage.tcl

#== Lab step 26 ==
    #=== power strape
    #createPowerStripe dir layer nets           offset width spacing pitch  snap
    createPowerStripe  "V" "M9" [list VDD VSS]    1.8   1.8   1.8      7.2 "none"
    createPowerStripe  "H" "M8"  [list VDD]      0      0.864  0    2.88 "half_grid"
    createPowerStripe  "H" "M8"  [list VSS]      1.44   0.864  0    2.88 "half_grid"
    createPowerStripe  "V" "M7"  [list VDD]     7.2      0.24  0     7.2    "grid"
    createPowerStripe  "V" "M7"  [list VSS]     3.6    0.24  0       7.2    "grid"
    createPowerStripe  "H" "M6"  [list VDD]     0      0.24  0       7.2    "grid"
    createPowerStripe  "H" "M6"  [list VSS]     3.6    0.24  0       7.2    "grid"
    createPowerStripe  "V" "M5"  [list VDD]     0      0.24  0       7.2    "grid"
    createPowerStripe  "V" "M5"  [list VSS]     3.6    0.24  0       7.2    "grid"

#== Lab step 27 ==
##create stripe on block
#deselect_obj -all 
#select_obj [get_db insts -if {.base_cell.base_class == block}]
#set_db add_stripes_domain_offset_from_core true
##createSelectBlockStripe dir layer nets         offset width spacing pitch  snap
#createSelectBlockStripe "H" "M6"  [list VSS]     1.2    0.24  0       7.2    "grid"
#createSelectBlockStripe "H" "M6"  [list VDD]     2.4      0.24  0      7.2    "grid"
#createSelectBlockStripe "V" "M5"  [list VSS]     1.2      0.24  0      3.6    "grid"
#createSelectBlockStripe "V" "M5"  [list VDD]     2.4      0.24  0      3.6    "grid"
#edit_trim_routes -nets {VDD VSS} -layers {M9 M8 M7 M6 M5 M4 M3}


    #check_power_vias
   #== expand via3 ~ via6
   #set corebox [get_db designs .core_bbox]
   #select_obj [get_obj_in_area -are $corebox -obj_type special_via -layers {VIA3 VIA4 VIA5 VIA6}]
   #update_power_vias -skip_via_on_pin standardcell -bottom_layer M3 -selected_vias 1 -via_scale_height 180 -update_vias 1 -via_scale_width 180 -top_layer M7
saveDesign dbs/powerplan.enc

#== Lab step 28 ==
    #=== followpin
    set_db [get_db insts -if {.base_cell.class == core}] .place_status unplaced
    set_db route_special_via_connect_to_shape { ring stripe }
    sroute -connect corePin -layerChangeRange { M1(1) M5(5) } -blockPinTarget nearestTarget -corePinTarget firstAfterRowEnd -allowJogging 0 -crossoverViaLayerRange { M1(1) M5(5) } -nets { VDD VSS } -allowLayerChange 1 -targetViaLayerRange { M1(1) M5(5) } 
    
    #=== shrink via
editSelect -shape FOLLOWPIN -via_cell {VIAGEN12* VIAGEN23*}
    editPowerVia -bottom_layer M1 -top_layer M4 -modify_vias 1 -selected_vias 1  -via_scale_height 70 -via_scale_width 130
deselect_obj -all 
editSelect -shape FOLLOWPIN -via_cell {VIAGEN34*}
    editPowerVia -bottom_layer M1 -top_layer M4 -modify_vias 1 -selected_vias 1  -via_scale_height 100 -via_scale_width 130
    
    
#== Lab step 29 ==
    #=== M2 rail
#createPowerStripeRail  direction layer nets offset width spacing pitch RTopLayer RBotLayer BTopLayer BBotLayer
    createPowerStripeRail  "H" "M2" [list VSS]   0.544  0.064 0   1.152  3    1    2    1
    createPowerStripeRail  "H" "M2" [list VDD]  -0.032  0.064 0   1.152  3    1    2    1
    
#== Lab step 30 ==
    deleteRouteBlk -name {RBKM34 RBKM2}
    deleteRouteBlk -name RBKPADPIN
    create_pg_model_for_macro_place -file golden_mimic_power_mesh.tcl
    #saveDesign dbs/followpin.enc
    verify_drc
    fixVia -minStep
}

#runPGPlan
