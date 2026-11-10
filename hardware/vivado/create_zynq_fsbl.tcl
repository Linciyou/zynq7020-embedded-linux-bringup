# Build the FSBL used by the QSPI production boot image.
set root_dir [file normalize [file join [file dirname [info script]] .. ..]]
set workspace_dir [file join $root_dir build vitis_zynq]
set xsa_file [file join $root_dir build vivado zynq7020_bringup zynq7020_bringup.xsa]

if {![file exists $xsa_file]} {
    error "XSA not found: $xsa_file"
}

file mkdir $workspace_dir
setws $workspace_dir

set platform_dir [file join $workspace_dir zynq7020_platform]
set fsbl_dir [file join $platform_dir zynq_fsbl]
set fsbl_file [file join $fsbl_dir fsbl.elf]

if {![file exists [file join $platform_dir platform.spr]]} {
    if {[catch {
        platform create -name zynq7020_platform -hw $xsa_file \
            -proc ps7_cortexa9_0 -os standalone
        platform write
        platform generate
    } message]} {
        if {![file exists [file join $fsbl_dir Makefile]]} {
            error $message
        }
        puts "Vitis backend warning after platform generation: $message"
    }
}

set tools_root C:/AMDDesignTools/2025.2
if {[info exists ::env(AMD_TOOLS_ROOT)] && $::env(AMD_TOOLS_ROOT) ne ""} {
    set tools_root [file normalize $::env(AMD_TOOLS_ROOT)]
}
set toolchain_bin [file join $tools_root Vitis gnu aarch32 nt gcc-arm-none-eabi bin]
set gnuwin_bin [file join $tools_root Vitis gnuwin bin]
set make_bin [file join $gnuwin_bin make.exe]
set env(PATH) "$toolchain_bin;$gnuwin_bin;$env(PATH)"
set hooks_file [file join $root_dir hardware fsbl fsbl_hooks.c]
if {![file exists $hooks_file]} { error "Board FSBL hooks not found: $hooks_file" }
file copy -force $hooks_file [file join $fsbl_dir fsbl_hooks.c]
puts [exec $make_bin -C [file join $fsbl_dir zynq_fsbl_bsp] 2>@1]
puts [exec $make_bin -C $fsbl_dir -j 4 2>@1]

if {![file exists $fsbl_file]} {
    error "FSBL build did not produce $fsbl_file"
}
puts "Built QSPI boot FSBL: $fsbl_file"
