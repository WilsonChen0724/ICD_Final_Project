if {[file exists "../design/CHIP-scan.def"]} {
    defIn ../design/CHIP-scan.def
    report_scan_chain
}
