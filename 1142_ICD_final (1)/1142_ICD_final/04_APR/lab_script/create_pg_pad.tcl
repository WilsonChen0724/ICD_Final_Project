if {[llength [get_db insts CORE_PG*]] == 0} {
    addInst -cell PVDD2CDGM_V -inst IO_PG1  
    addInst -cell PVDD2CDGM_H -inst IO_PG2  
    addInst -cell PVDD2CDGM_V -inst IO_PG3  
    addInst -cell PVDD2CDGM_H -inst IO_PG4  
    addInst -cell PVDD1CDGM_V -inst CORE_PG1
    addInst -cell PVDD1CDGM_H -inst CORE_PG2
    addInst -cell PVDD1CDGM_V -inst CORE_PG3
    addInst -cell PVDD1CDGM_H -inst CORE_PG4
}
if {[llength [get_db insts CORNER*]] == 0} {
    addInst -cell PCORNER -inst CORNERTL
    addInst -cell PCORNER -inst CORNERTR
    addInst -cell PCORNER -inst CORNERBL
    addInst -cell PCORNER -inst CORNERBR
}

#connect_pin -inst IO_PG1   -pin RTE -net io_rte
#connect_pin -inst IO_PG2   -pin RTE -net io_rte
#connect_pin -inst IO_PG3   -pin RTE -net io_rte
#connect_pin -inst IO_PG4   -pin RTE -net io_rte
#connect_pin -inst CORE_PG1 -pin RTE -net io_rte
#connect_pin -inst CORE_PG2 -pin RTE -net io_rte
#connect_pin -inst CORE_PG3 -pin RTE -net io_rte
#connect_pin -inst CORE_PG4 -pin RTE -net io_rte
#connect_pin -inst CORNERTL -pin RTE -net io_rte
#connect_pin -inst CORNERTR -pin RTE -net io_rte
#connect_pin -inst CORNERBL -pin RTE -net io_rte
#connect_pin -inst CORNERBR -pin RTE -net io_rte
