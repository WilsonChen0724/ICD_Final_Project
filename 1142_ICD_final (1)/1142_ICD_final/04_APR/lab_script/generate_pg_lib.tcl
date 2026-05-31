# voltus -batch -file lab_script/generate_pg_lib.tcl
# read_lib -lef \
#   ../library/lef/N16ADFP_APR_Innovus_11M.10a.tlef \
#   ../library/lef/N16ADFP_StdCell.lef \
#   ../library/lef/N16ADFP_StdIO.lef \
#   ../library/lef/N16ADFP_BondPad.lef \
#   ../library/memory/rf_2p_hse.lef 
set_pg_library_mode -celltype techonly \
                    -power_pins {VDD 0.8 VDDCE 0.8 VDDPE 0.8} \
                    -ground_pins {VSS VSSE} \
                    -extraction_tech_file ../library/ADFP_Collaterals/Tech/RC/N16ADFP_QRC/worst/qrcTechFile \
                    -temperature 0
#                    -lef_layermap ../library/fireice/lefdef.layermap 
                    #-filler_cells FILLCELL* \
                    #-decap_cells
generate_pg_library
                    
