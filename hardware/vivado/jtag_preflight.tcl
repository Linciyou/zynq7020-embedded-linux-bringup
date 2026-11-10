# Check JTAG target selection, PS DDR access, and ARM core halt/resume.
# The test restores the two words it uses at 0x1FF00000.

set root_dir [file normalize [file join [file dirname [info script]] .. ..]]
set ps7_init_file [file join $root_dir build jtag_hw ps7_init.tcl]
if {![file exists $ps7_init_file]} {
    error "Missing generated PS initialization file: $ps7_init_file"
}

connect
targets
targets -set -filter {name == "APU"}
rst -system
after 1000
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
stop
source $ps7_init_file
ps7_init
ps7_post_config

set scratch 0x1FF00000
set old0 [lindex [mrd -value -force -address-space PA $scratch 1] 0]
set old1 [lindex [mrd -value -force -address-space PA [expr {$scratch + 4}] 1] 0]
mwr -force -address-space PA $scratch 0xA55A3CC3
mwr -force -address-space PA [expr {$scratch + 4}] 0x5AA5C33C
set got0 [lindex [mrd -value -force -address-space PA $scratch 1] 0]
set got1 [lindex [mrd -value -force -address-space PA [expr {$scratch + 4}] 1] 0]
mwr -force -address-space PA $scratch $old0
mwr -force -address-space PA [expr {$scratch + 4}] $old1
if {$got0 != 0xA55A3CC3 || $got1 != 0x5AA5C33C} {
    error [format "DDR test failed: read back 0x%08X and 0x%08X" $got0 $got1]
}
puts "DDR_READ_WRITE: PASS at 0x1FF00000 (original contents restored)"

con
after 250
stop
set pc [rrd pc]
puts "ARM_CORE_HALT_RESUME: PASS (core stopped again; PC=$pc)"
