#set_db check_drc_limit 10000
#check_drc

set errors [get_db current_design .markers -if {.subtype == Cut_Spacing }]
foreach marker $errors {
   #puts $marker
   set mbox [get_db $marker .bbox]
   editDelete -area $mbox -object_type Via -subclass "VIA12_Manual"
}


