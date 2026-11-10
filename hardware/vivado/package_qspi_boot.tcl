# Package the FSBL, PL bitstream, and U-Boot for QSPI offset 0.
# Linux kernel, DTB and initramfs remain on SD, loaded through boot.scr.
set root_dir [file normalize [file join [file dirname [info script]] .. ..]]
set output_dir [file join $root_dir build flash_images]
set fsbl_file [file join $root_dir build vitis_zynq zynq7020_platform zynq_fsbl fsbl.elf]
set bit_file [file join $root_dir build vivado zynq7020_bringup zynq7020_bringup.runs impl_1 system_wrapper.bit]
set uboot_file [file join $root_dir build linux_images u-boot.bin]
set bif_file [file join $output_dir zynq7020_qspi_boot.bif]
set boot_file [file join $output_dir BOOT_QSPI.bin]
set tools_root C:/AMDDesignTools/2025.2
if {[info exists ::env(AMD_TOOLS_ROOT)] && $::env(AMD_TOOLS_ROOT) ne ""} {
    set tools_root [file normalize $::env(AMD_TOOLS_ROOT)]
}
set bootgen_file [file join $tools_root Vitis bin bootgen.bat]

foreach file [list $fsbl_file $bit_file $uboot_file $bootgen_file] {
    if {![file exists $file]} {
        error "Required file not found: $file"
    }
}

file mkdir $output_dir
set bif_handle [open $bif_file w]
puts $bif_handle "the_ROM_image:"
puts $bif_handle "{"
puts $bif_handle [format {  [bootloader] %s} [file nativename $fsbl_file]]
puts $bif_handle [file nativename $bit_file]
puts $bif_handle [format {  [load=0x04000000, startup=0x04000000] %s} [file nativename $uboot_file]]
puts $bif_handle "}"
close $bif_handle

exec $bootgen_file -arch zynq -image $bif_file -w -o $boot_file
puts "Created QSPI boot image: $boot_file"
if {[file size $boot_file] > 0x00600000} {
    error "QSPI image exceeds the 6 MiB boot partition; do not program it"
}
puts "Linux payload remains on SD: zImage, zynq7020-bringup.dtb, rootfs.cpio.gz"
