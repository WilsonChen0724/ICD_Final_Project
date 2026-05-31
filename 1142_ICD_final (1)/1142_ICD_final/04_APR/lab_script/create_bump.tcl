# delete_routes -shapes iowire  
# delete_obj [get_db bumps]

create_bump -cell PAD80APB_LF_BU -pitch {154 154}  -loc {80 80} -pattern_array {4 4} -name_format "Bump_%c_%r"

setFlipChipMode -routeWidth 12.0
setFlipChipMode -layerChangeTopLayer AP
setFlipChipMode -layerChangeBotLayer AP
setFlipChipMode -connectPowerCellToBump true
setFlipChipMode -multipleConnection multiPadsToBump

unassignBump -all
assignPGBumps -nets VSS -bumps {Bump_3_3 }
assignPGBumps -nets VSS -bumps {Bump_2_2 }
assignPGBumps -nets VSS -bumps {Bump_2_4 }
assignPGBumps -nets VDDPST -bumps {Bump_4_4}
assignPGBumps -nets VDD -bumps {Bump_3_2}
assignPGBumps -nets VDD -bumps {Bump_2_3}
assignPGBumps -nets VDDPST -bumps {Bump_1_2}

# set_db flip_chip_multi_pad_routing_style  star
# set_db flip_chip_honor_bump_connect_target_constraint true
# addBumpConnectTargetConstraint -bump {Bump_2_2 Bump_3_3} -instName CORE_PG4 -pinName VSS

assignBump
# delete_routes -shapes iowire
fcroute -type signal -designStyle pio

#foreach_in_collection net [get_nets -of_objects [get_ports]] {
#    set_dont_touch [get_attr $net full_name]
#    setAttribute -skip_routing true -net [get_attr $net full_name]
#}

