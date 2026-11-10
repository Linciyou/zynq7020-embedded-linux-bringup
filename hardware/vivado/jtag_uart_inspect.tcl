# Read PS UART1 configuration while Linux is running.
# This script does not halt/reset the CPU and does not read the RX FIFO.

connect
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
puts "CORE0_STATE: [state]"
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #1"}
puts "CORE1_STATE: [state]"
targets -set -filter {name =~ "APU"}

set registers {
    {CR 0xE0001000}
    {MR 0xE0001004}
    {ISR 0xE0001014}
    {BAUDGEN 0xE0001018}
    {MODEMCR 0xE0001024}
    {MODEMSR 0xE0001028}
    {STATUS 0xE000102C}
    {BAUDDIV 0xE0001034}
}

foreach item $registers {
    lassign $item name address
    set value [lindex [mrd -value -force -address-space AP0 $address 1] 0]
    puts [format "UART1_%s (%s) = %s" $name $address $value]
}

foreach item {{MIO48 0xF80007C0} {MIO49 0xF80007C4}} {
    lassign $item name address
    set value [lindex [mrd -value -force -address-space AP0 $address 1] 0]
    puts [format "UART1_ROUTE_%s (%s) = %s" $name $address $value]
}
