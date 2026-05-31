set_db write_stream_text_size 10

set streamOutMapLink /share1/tech/ADFP/Executable_Package/Collaterals/Tech/APR/N16ADFP_APR_Innovus/N16ADFP_APR_Innovus_Gdsout_11M.10a.map

set_db write_stream_text_size 10
if {! [file exists stream_out_map]} {
    set streamOutMapFile [file dirname [file normalize $streamOutMapLink/___]]
    if [file exists $streamOutMapFile] {
       file copy $streamOutMapFile stream_out_map
       set outfile [open stream_out_map a]
       puts  $outfile "CUSTOM_CB CUSTOM 108 250"
       #puts  $outfile "CUSTOM_CB CUSTOM 108 0"
       close $outfile
    }
}

streamOut output/CHIP.gds -mapFile stream_out_map -libName DesignLib \
      -merge { \
           /share1/tech/ADFP/Executable_Package/Collaterals/IP/stdcell/N16ADFP_StdCell/GDS/N16ADFP_StdCell.gds \
           /share1/tech/ADFP/Executable_Package/Collaterals/IP/stdio/N16ADFP_StdIO/GDS/N16ADFP_StdIO.gds \
           /share1/tech/ADFP/Executable_Package/Collaterals/IP/bondpad/N16ADFP_BondPad/GDS/N16ADFP_BondPad.gds \
           /share1/tech/ADFP/Lab_adfp/library/memory/rf_2p_hse.gds \
      } \
      -uniquifyCellNames -unit 1000 -mode all

#create_pin_text -cells aiot_mcu label_loc.txt
