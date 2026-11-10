# Load the JTAG bring-up images into DDR and hand execution to the Linux zImage.
# This bypasses BootROM, FSBL, and U-Boot; it does not validate the flash boot chain.

set root_dir [file normalize [file join [file dirname [info script]] .. ..]]
proc env_or_default {name default_value} {
    if {[info exists ::env($name)] && $::env($name) ne ""} {
        return [file normalize $::env($name)]
    }
    return $default_value
}

set ps7_init_file [env_or_default JTAG_PS7_INIT_FILE \
    [file join $root_dir build jtag_hw ps7_init.tcl]]
set bit_file [env_or_default JTAG_BIT_FILE \
    [file join $root_dir build vivado zynq7020_bringup zynq7020_bringup.runs impl_1 system_wrapper.bit]]
set images_dir [file join $root_dir build linux_images]
set kernel_file [file join $images_dir zImage]
set initrd_file [file join $images_dir rootfs.cpio.gz]
set dtb_file [env_or_default JTAG_DTB_FILE \
    [file join $images_dir zynq7020-bringup.dtb]]
set system_map_file [file join $images_dir System.map]

set kernel_addr 0x02000000
set initrd_addr 0x06000000
set dtb_addr 0x07000000
set ddr_end 0x20000000

proc lookup_kernel_symbol {map_file requested_symbol} {
    set map_channel [open $map_file r]
    while {[gets $map_channel line] >= 0} {
        if {[regexp {^([0-9a-fA-F]+)\s+\S\s+(\S+)$} $line -> address symbol] &&
            $symbol eq $requested_symbol} {
            close $map_channel
            return 0x$address
        }
    }
    close $map_channel
    error "Kernel symbol not found in System.map: $requested_symbol"
}

foreach file [list $ps7_init_file $bit_file $kernel_file $initrd_file $dtb_file] {
    if {![file exists $file]} {
        error "Required bring-up file not found: $file"
    }
}

puts "JTAG_BITSTREAM: $bit_file"
puts "PS7_INIT: $ps7_init_file"
puts "KERNEL: $kernel_file"
puts "INITRAMFS: $initrd_file"
puts "DTB: $dtb_file"

if {[file size $kernel_file] > $initrd_addr - $kernel_addr} {
    error "zImage overlaps the initramfs load address"
}
if {$initrd_addr + [file size $initrd_file] > $dtb_addr} {
    error "Initramfs overlaps the DTB load address"
}
if {$dtb_addr + [file size $dtb_file] > $ddr_end} {
    error "DTB exceeds the configured 512 MiB DDR range"
}

connect
targets -set -filter {name == "APU"}
rst -system
after 1000
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
stop
source $ps7_init_file
ps7_init
ps7_post_config

# This board wires UART1 through EMIO (PL L17/M17). A JTAG system reset can
# leave an earlier boot image's UART1 MIO 48/49 selection in the SLCR. Release
# those unused MIO pins before Linux initializes the UART receiver.
targets -set -filter {name =~ "APU"}
mwr -force -address-space AP0 0xF8000008 0x0000DF0D
mwr -force -address-space AP0 0xF80007C0 0x00001601
mwr -force -address-space AP0 0xF80007C4 0x00001601
mwr -force -address-space AP0 0xF8000004 0x0000767B
set mio48 [lindex [mrd -value -force -address-space AP0 0xF80007C0 1] 0]
set mio49 [lindex [mrd -value -force -address-space AP0 0xF80007C4 1] 0]
if {$mio48 != 0x1601 || $mio49 != 0x1601} {
    error [format "UART1 EMIO route not established: MIO48=0x%08X MIO49=0x%08X" $mio48 $mio49]
}
puts "UART1_EMIO_MIO_RELEASE: PASS (MIO 48/49 no longer select UART1)"
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
fpga $bit_file

dow -data $kernel_file $kernel_addr
dow -data $initrd_file $initrd_addr
dow -data $dtb_file $dtb_addr

# ARM Linux DT boot protocol: r0=0, r1=~0, r2=physical DTB address.
rst -processor
after 100
rwr r0 0x00000000
rwr r1 0xFFFFFFFF
rwr r2 $dtb_addr
set break_at_entry 0
if {[info exists ::env(JTAG_BREAK_AT_KERNEL_ENTRY)] &&
    $::env(JTAG_BREAK_AT_KERNEL_ENTRY) eq "1"} {
    set break_at_entry 1
}

set trace_kernel_init 0
if {[info exists ::env(JTAG_TRACE_KERNEL_INIT)] &&
    $::env(JTAG_TRACE_KERNEL_INIT) eq "1"} {
    set trace_kernel_init 1
}

if {$break_at_entry && $trace_kernel_init} {
    error "Select either JTAG_BREAK_AT_KERNEL_ENTRY or JTAG_TRACE_KERNEL_INIT, not both"
}

if {$trace_kernel_init} {
    if {![file exists $system_map_file]} {
        error "Kernel progress tracing requires the matching file: $system_map_file"
    }
    set trace_symbols {start_kernel rest_init kernel_init run_init_process}
    set trace_addresses {}
    set trace_breakpoints {}
    foreach symbol $trace_symbols {
        set address [lookup_kernel_symbol $system_map_file $symbol]
        lappend trace_addresses $address
        lappend trace_breakpoints [bpadd -addr $address -type hw]
    }
    set timeout_seconds 120
    if {[info exists ::env(JTAG_BREAK_TIMEOUT_SECONDS)] &&
        [string is integer -strict $::env(JTAG_BREAK_TIMEOUT_SECONDS)]} {
        set timeout_seconds $::env(JTAG_BREAK_TIMEOUT_SECONDS)
    }

    con -addr $kernel_addr -block -timeout $timeout_seconds
    for {set index 0} {$index < [llength $trace_symbols]} {incr index} {
        set pc [rrd pc]
        if {![regexp -nocase {pc:\s*(?:0x)?([0-9a-f]+)} $pc -> pc_hex]} {
            error "Could not read Cortex-A9 PC while tracing kernel startup: $pc"
        }
        scan $pc_hex %x pc_value
        set expected_address [lindex $trace_addresses $index]
        scan [string range $expected_address 2 end] %x expected_value
        if {$pc_value != $expected_value} {
            error [format "Kernel trace stopped at PC=0x%08X, expected %s (%s)" \
                $pc_value [lindex $trace_symbols $index] $expected_address]
        }
        puts [format "KERNEL_STAGE_BREAKPOINT: PASS (%s at 0x%08X)" \
            [lindex $trace_symbols $index] $pc_value]
        bpremove [lindex $trace_breakpoints $index]
        if {$index + 1 < [llength $trace_symbols]} {
            con -block -timeout $timeout_seconds
        }
    }
    puts "LINUX_INIT_LAUNCH: PASS (kernel reached run_init_process; userspace execution is not confirmed)"
    puts "LINUX_USERSPACE: NOT CONFIRMED (JTAG trace stops before the init process runs)"
} elseif {$break_at_entry} {
    bpadd -addr $kernel_addr -type hw -temp
    con -addr $kernel_addr -block -timeout 10
    set cpu_state [state]
    if {![string match "Stopped*" $cpu_state]} {
        error "Core did not stop at the zImage entry breakpoint (state: $cpu_state)"
    }
    set pc [rrd pc]
    if {![regexp -nocase {pc:\s*(?:0x)?([0-9a-f]+)} $pc -> pc_hex]} {
        error "Could not parse Cortex-A9 PC after entry breakpoint: $pc"
    }
    scan $pc_hex %x pc_value
    if {$pc_value != $kernel_addr} {
        error [format "Entry breakpoint stopped at PC=0x%08X, expected 0x%08X" \
            $pc_value $kernel_addr]
    }
    puts "KERNEL_ENTRY_BREAKPOINT: PASS (PC=$pc; core remains halted)"
} else {
    con -addr $kernel_addr
    puts "JTAG_IMAGE_LOAD: PASS (downloads accepted; CPU resumed at zImage address)"
}

puts "BOOTROM_FSBL_UBOOT: NOT TESTED (this script bypasses those stages)"
puts "LINUX_USERSPACE: NOT VERIFIED BY XSCT (check UART or network evidence separately)"
