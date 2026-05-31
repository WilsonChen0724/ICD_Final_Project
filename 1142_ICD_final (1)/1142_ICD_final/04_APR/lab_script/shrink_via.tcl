editSelect -shape FOLLOWPIN -via_cell {VIAGEN12* VIAGEN23*}
    editPowerVia -bottom_layer M1 -top_layer M4 -modify_vias 1 -selected_vias 1  -via_scale_height 70 -via_scale_width 130
deselect_obj -all
editSelect -shape FOLLOWPIN -via_cell {VIAGEN34*}
    editPowerVia -bottom_layer M1 -top_layer M4 -modify_vias 1 -selected_vias 1  -via_scale_height 100 -via_scale_width 130

