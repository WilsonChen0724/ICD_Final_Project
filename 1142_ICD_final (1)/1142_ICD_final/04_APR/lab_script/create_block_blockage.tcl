foreach cell [get_db [get_db insts -if {.base_cell.base_class == block}] .name] {
        set llx [get_db inst:$cell .bbox.ll.x]
        set lly [get_db inst:$cell .bbox.ll.y]
        set urx [get_db inst:$cell .bbox.ur.x]
        set ury [get_db inst:$cell .bbox.ur.y]
        create_route_blockage -name RBKM34 -pg_nets -layers {M3 M4} -rects [list [expr $llx-0.46] [expr $lly -0.46] $llx [expr $ury +0.46]]
        create_route_blockage -name RBKM34 -pg_nets -layers {M3 M4} -rects [list $urx [expr $lly -0.46] [expr $urx + 0.46] [expr $ury +0.46]]
        create_route_blockage -name RBKM2 -pg_nets -layers M2 -rects [list [expr $llx-0.46] $lly $llx $ury]
        create_route_blockage -name RBKM2 -pg_nets -layers M2 -rects [list $urx $lly [expr $urx + 0.46] $ury]
}

