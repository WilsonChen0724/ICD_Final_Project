globalNetConnect VDD -type pg_pin -pin VDD -instanceBasename *
globalNetConnect VSS -type pg_pin -pin VSS -instanceBasename *
globalNetConnect VDD -type pg_pin -pin VPP -instanceBasename *
globalNetConnect VSS -type pg_pin -pin VBB -instanceBasename *
globalNetConnect VDDPST -type pg_pin -pin VDDPST -instanceBasename *
globalNetConnect VDD -type pg_pin  -pin VDDPE -instanceBasename *
globalNetConnect VDD -type pg_pin  -pin VDDCE -instanceBasename *
globalNetConnect VSS -type pg_pin  -pin VSSE -instanceBasename *
globalNetConnect VDD -type tie_hi -instanceBasename *
globalNetConnect VSS -type tie_lo -instanceBasename *

#if {[llength [get_db nets ESD]] == 0} {
#    create_net -ground -name ESD
#}
#if {[llength [get_db nets POCCTRL]] == 0} {
#    create_net -ground -name POCCTRL
#}
#connect_global_net ESD -type pg_pin -pin_base_name ESD -inst_base_name *
#connect_global_net POCCTRL -type pg_pin -pin_base_name POCCTRL -inst_base_name *
#set_db net:ESD .skip_routing true
#set_db net:POCCTRL .skip_routing true

 
