setEcoMode -honorFixedStatus false
proc swap_io_hv {toHV args} {
    set orgHV H
    if { $toHV == "H" } { 
        set orgHV "V" 
    } elseif { $toHV == "V" } { 
        set orgHV "H"
    } else {
        puts
        puts "swap_io_hv \[H V\]"
        puts "    Swap selected insts from/to XXX_H and XXX_V"
        puts "swap_io_hv \[H V\] inst1 inst2 ..."
        puts "    Swap listed insts from/to XXX_H and XXX_V"
        return
    }
    if {[llength $args] == 0} {
        set insts [get_db selected .name]
    } else {
        set insts $args
    }

    foreach cell $insts {
        if {[llength [get_db insts $cell]]} {
            set base_cell_org [get_db  inst:$cell .base_cell.name]
            if [ regexp "(.*)_$orgHV$" $base_cell_org whole sub1 ] {
                puts "change $cell from $base_cell_org to ${sub1}_${toHV}"
                ecoChangeCell -inst $cell -cell ${sub1}_${toHV}
            }
        }
    }
}

proc do_swap_io {} {
    set llx [get_db designs .bbox.ll.x]
    set lly [get_db designs .bbox.ll.y]
    set urx [get_db designs .bbox.ur.x]
    set ury [get_db designs .bbox.ur.y]
    deselect_obj -all
    gui_select -line "[expr $llx +1] $lly [expr $llx+1] $ury"
    swap_io_hv H
    deselect_obj -all
    gui_select -line "[expr $urx -1] $lly [expr $urx-1] $ury"
    swap_io_hv H
    deselect_obj -all
    gui_select -line "$llx [expr $ury-1] $urx [expr $ury-1]"
    swap_io_hv V
    deselect_obj -all
    gui_select -line "$llx [expr $lly+1] $urx [expr $lly+1]"
    swap_io_hv V
    deselect_obj -all
}

# do_swap_io 
