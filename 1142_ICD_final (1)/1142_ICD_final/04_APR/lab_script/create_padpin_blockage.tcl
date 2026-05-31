foreach powerpad [get_db insts -if {.base_cell.name == PVDD1CDGM_* }] {
    set llx [get_db $powerpad .bbox.ll.x]
    set lly [get_db $powerpad .bbox.ll.y]
    set urx [get_db $powerpad .bbox.ur.x]
    set ury [get_db $powerpad .bbox.ur.y]
    set orient [get_db $powerpad .orient]
    puts "$powerpad $llx $lly $urx $ury $orient"
    if { $orient == "r0" } { #bottom
        set core_lly [get_db designs .core_bbox.ll.y]
        create_route_blockage -name RBKPADPIN -pg_nets -rects [list [expr $llx +2] $ury [expr $urx -7] [expr $core_lly -0.5]] -layer {1 2 3 4 5 6 }
    } elseif { $orient == "my" } { #bottom
        set core_lly [get_db designs .core_bbox.ll.y]
        create_route_blockage -name RBKPADPIN -pg_nets -rects [list [expr $llx +7] $ury [expr $urx -2] [expr $core_lly -0.5]] -layer {1 2 3 4 5 6 }
    } elseif { $orient == "r90" } { #right
        set core_urx [get_db designs .core_bbox.ur.x]
        create_route_blockage -name RBKPADPIN -pg_nets -rects [list [expr $core_urx+0.5] [expr $lly + 2] $llx [expr $ury -7]] -layer {1 2 3 4 5 6 }
    } elseif { $orient == "my90" } { #right
        set core_urx [get_db designs .core_bbox.ur.x]
        create_route_blockage -name RBKPADPIN -pg_nets -rects [list [expr $core_urx+0.5] [expr $lly + 7] $llx [expr $ury -2]] -layer {1 2 3 4 5 6 }
    } elseif { $orient == "r180" } { #top
        set core_ury [get_db designs .core_bbox.ur.y]
        create_route_blockage -name RBKPADPIN -pg_nets -rects [list [expr $llx +7] [expr $core_ury + 0.5] [expr $urx -2] $lly] -layer {1 2 3 4 5 6 }
    } elseif { $orient == "mx" } { #top
        set core_ury [get_db designs .core_bbox.ur.y]
        create_route_blockage -name RBKPADPIN -pg_nets -rects [list [expr $llx +2] [expr $core_ury + 0.5] [expr $urx -7] $lly] -layer {1 2 3 4 5 6 }
    } elseif { $orient == "r270" } { #left
        set core_llx [get_db designs .core_bbox.ll.x]
        create_route_blockage -name RBKPADPIN -pg_nets -rects [list $urx  [expr $lly + 7] [expr $core_llx -0.5] [expr $ury -2]] -layer {1 2 3 4 5 6 }
    } elseif { $orient == "mx90" } { #left
        set core_llx [get_db designs .core_bbox.ll.x]
        create_route_blockage -name RBKPADPIN -pg_nets -rects [list $urx  [expr $lly + 2] [expr $core_llx -0.5] [expr $ury -7]] -layer {1 2 3 4 5 6 }
    }
}

#delete_obj [get_db route_blockages RBKPADPIN]
