select_obj [get_db gui_rects  -if {.gui_layer_name == CUSTOM_CB}]
deleteSelectedFromFPlan
set diearea [get_db designs .bbox]

#set chipboundary [get_computed_shapes $diearea SIZE 4.8]
#add_gui_shape -layer CUSTOM_CB -rect $chipboundary
add_gui_shape -layer CUSTOM_CB -rect $diearea

set_layer_preference CUSTOM_CB -stipple none

#draw left-bottom corner marker
#set cllx [get_db designs .bbox.ll.x]
#set clly [get_db designs .bbox.ll.y]
#add_shape -rect "[expr $cllx -16] [expr $clly -6] [expr $cllx+7] [expr $clly-3]" -layer AP
#add_shape -rect "[expr $cllx -6] [expr $clly -16] [expr $cllx-3] [expr $clly+7]" -layer AP

