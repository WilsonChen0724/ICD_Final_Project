deleteEmptyModule

saveNetlist output/CHIP_pr.v
set DECAP_CELL_LIST [get_db [get_db base_cells DCAP*] .name]
set PVDD_CELL_LIST [get_db [get_db base_cells PVDD*] .name]
set FILLER_CELL_LIST [get_db [get_db base_cells FILL*] .name]
set PFILLER_CELL_LIST [get_db [get_db base_cells PFILL*] .name]
set PCORNER_CELL_LIST [get_db [get_db base_cells PCORNER*] .name]
saveNetlist -includePowerGround  -includePhysicalCell "$DECAP_CELL_LIST $PVDD_CELL_LIST" -excludeCellInst "$FILLER_CELL_LIST $PFILLER_CELL_LIST $PCORNER_CELL_LIST" -excludeLeafCell output/CHIP_pg.v

