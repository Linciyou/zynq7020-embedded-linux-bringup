# Build the Zynq-7020 Embedded Linux bring-up hardware platform.
# Run from the repository root in Vivado 2025.2 Tcl mode.

set proj_name zynq7020_bringup
set proj_dir [file normalize ./build/vivado/$proj_name]
set part_name xc7z020clg484-2
set bd_name system
set mdio_iobuf_rtl [file normalize ./hardware/rtl/mdio_iobuf.v]
set uart_xdc [file normalize ./hardware/vivado/zynq7020_emio_uart.xdc]
set rgmii_xdc [file normalize ./hardware/vivado/zynq7020_rgmii.xdc]

foreach source_file [list $mdio_iobuf_rtl $uart_xdc $rgmii_xdc] {
    if {![file exists $source_file]} {
        error "Required source file not found: $source_file"
    }
}

file mkdir $proj_dir
create_project $proj_name $proj_dir -part $part_name -force
set_property target_language Verilog [current_project]
add_files -norecurse $mdio_iobuf_rtl
add_files -fileset constrs_1 -norecurse $uart_xdc
add_files -fileset constrs_1 -norecurse $rgmii_xdc
update_compile_order -fileset sources_1

create_bd_design $bd_name
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7 ps7
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR"} [get_bd_cells ps7]

proc set_ps7_property {name value} {
    set property_name CONFIG.$name
    if {[lsearch -exact [list_property [get_bd_cells ps7]] $property_name] >= 0} {
        set_property -dict [list $property_name $value] [get_bd_cells ps7]
    }
}

# Keep the board's PS memory and peripheral configuration unchanged.
set_ps7_property PCW_PRESET_BANK0_VOLTAGE {LVCMOS 3.3V}
set_ps7_property PCW_PRESET_BANK1_VOLTAGE {LVCMOS 3.3V}
set_ps7_property PCW_UIPARAM_DDR_PARTNO {MT41K256M16 RE-125}
set_ps7_property PCW_UIPARAM_DDR_BUS_WIDTH {16 Bit}
set_ps7_property PCW_UIPARAM_DDR_FREQ_MHZ 533.333313
set_ps7_property PCW_USE_M_AXI_GP0 1
set_ps7_property PCW_USE_FABRIC_INTERRUPT 0
set_ps7_property PCW_EN_CLK0_PORT 1
set_ps7_property PCW_FPGA0_PERIPHERAL_FREQMHZ 100
set_ps7_property PCW_EN_CLK1_PORT 1
set_ps7_property PCW_FPGA1_PERIPHERAL_FREQMHZ 200
set_ps7_property PCW_QSPI_PERIPHERAL_ENABLE 1
set_ps7_property PCW_QSPI_GRP_SINGLE_SS_ENABLE 1
set_ps7_property PCW_SD0_PERIPHERAL_ENABLE 1
set_ps7_property PCW_SD0_GRP_CD_ENABLE 1
set_ps7_property PCW_UART1_PERIPHERAL_ENABLE 1
set_ps7_property PCW_UART1_UART1_IO EMIO
set_ps7_property PCW_EN_EMIO_UART1 1
set_ps7_property PCW_ENET0_PERIPHERAL_ENABLE 1
set_ps7_property PCW_ENET0_ENET0_IO EMIO
set_ps7_property PCW_ENET0_GRP_MDIO_ENABLE 1
set_ps7_property PCW_ENET0_GRP_MDIO_IO EMIO
set_ps7_property PCW_EN_EMIO_ENET0 1

# GEM0 uses EMIO for both GMII and MDIO; the PL bridge drives board RGMII pins.
set_property -dict [list \
    CONFIG.PCW_ENET0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_EN_EMIO_ENET0 {1} \
    CONFIG.PCW_ENET0_GRP_MDIO_ENABLE {1} \
    CONFIG.PCW_ENET0_GRP_MDIO_IO {EMIO} \
] [get_bd_cells ps7]

# UART1 stays available on EMIO as an optional console/debug port.
create_bd_port -dir O ps_uart_tx
create_bd_port -dir I ps_uart_rx
connect_bd_net [get_bd_pins ps7/UART1_TX] [get_bd_ports ps_uart_tx]
connect_bd_net [get_bd_pins ps7/UART1_RX] [get_bd_ports ps_uart_rx]

create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset rst_ps7_200M
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset rst_ps7_100M
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect axi_gp0_interconnect
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio axi_gpio_phy_reset
create_bd_cell -type ip -vlnv xilinx.com:ip:gmii_to_rgmii gmii_to_rgmii_0
create_bd_cell -type module -reference mdio_iobuf mdio_iobuf_0

set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] \
    [get_bd_cells axi_gp0_interconnect]
set_property -dict [list \
    CONFIG.C_GPIO_WIDTH {1} \
    CONFIG.C_ALL_OUTPUTS {1} \
    CONFIG.C_DOUT_DEFAULT {0x00000000} \
] [get_bd_cells axi_gpio_phy_reset]

set_property -dict [list \
    CONFIG.C_EXTERNAL_CLOCK {false} \
    CONFIG.C_USE_IDELAY_CTRL {true} \
    CONFIG.C_PHYADDR {8} \
    CONFIG.RGMII_TXC_SKEW {0} \
    CONFIG.SupportLevel {Include_Shared_Logic_in_Core} \
] [get_bd_cells gmii_to_rgmii_0]

connect_bd_net [get_bd_pins ps7/FCLK_CLK1] [get_bd_pins rst_ps7_200M/slowest_sync_clk]
connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins rst_ps7_200M/ext_reset_in]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins rst_ps7_100M/slowest_sync_clk]
connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins rst_ps7_100M/ext_reset_in]
connect_bd_net [get_bd_pins ps7/FCLK_CLK1] [get_bd_pins gmii_to_rgmii_0/clkin]
connect_bd_net [get_bd_pins rst_ps7_200M/peripheral_reset] [get_bd_pins gmii_to_rgmii_0/tx_reset]
connect_bd_net [get_bd_pins rst_ps7_200M/peripheral_reset] [get_bd_pins gmii_to_rgmii_0/rx_reset]

# Reuse the legacy board reset path, but keep the accelerator and its AXI path removed.
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins ps7/M_AXI_GP0_ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_gp0_interconnect/ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_gp0_interconnect/S00_ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_gp0_interconnect/M00_ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_gpio_phy_reset/s_axi_aclk]
connect_bd_net [get_bd_pins rst_ps7_100M/interconnect_aresetn] [get_bd_pins axi_gp0_interconnect/ARESETN]
connect_bd_net [get_bd_pins rst_ps7_100M/peripheral_aresetn] [get_bd_pins axi_gp0_interconnect/S00_ARESETN]
connect_bd_net [get_bd_pins rst_ps7_100M/peripheral_aresetn] [get_bd_pins axi_gp0_interconnect/M00_ARESETN]
connect_bd_net [get_bd_pins rst_ps7_100M/peripheral_aresetn] [get_bd_pins axi_gpio_phy_reset/s_axi_aresetn]
connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] [get_bd_intf_pins axi_gp0_interconnect/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_gp0_interconnect/M00_AXI] [get_bd_intf_pins axi_gpio_phy_reset/S_AXI]
connect_bd_intf_net [get_bd_intf_pins ps7/GMII_ETHERNET_0] [get_bd_intf_pins gmii_to_rgmii_0/GMII]
connect_bd_intf_net [get_bd_intf_pins ps7/MDIO_ETHERNET_0] [get_bd_intf_pins gmii_to_rgmii_0/MDIO_GEM]

create_bd_port -dir I -from 3 -to 0 eth_rgmii_rxd
create_bd_port -dir I eth_rgmii_rx_ctl
create_bd_port -dir I -type clk -freq_hz 125000000 eth_rgmii_rxc
create_bd_port -dir O -from 3 -to 0 eth_rgmii_txd
create_bd_port -dir O eth_rgmii_tx_ctl
create_bd_port -dir O -type clk eth_rgmii_txc
create_bd_port -dir O eth_mdc
create_bd_port -dir IO eth_mdio
create_bd_port -dir O eth_phy_reset_n

connect_bd_net [get_bd_ports eth_rgmii_rxd] [get_bd_pins gmii_to_rgmii_0/rgmii_rxd]
connect_bd_net [get_bd_ports eth_rgmii_rx_ctl] [get_bd_pins gmii_to_rgmii_0/rgmii_rx_ctl]
connect_bd_net [get_bd_ports eth_rgmii_rxc] [get_bd_pins gmii_to_rgmii_0/rgmii_rxc]
connect_bd_net [get_bd_pins gmii_to_rgmii_0/rgmii_txd] [get_bd_ports eth_rgmii_txd]
connect_bd_net [get_bd_pins gmii_to_rgmii_0/rgmii_tx_ctl] [get_bd_ports eth_rgmii_tx_ctl]
connect_bd_net [get_bd_pins gmii_to_rgmii_0/rgmii_txc] [get_bd_ports eth_rgmii_txc]
connect_bd_net [get_bd_pins gmii_to_rgmii_0/mdio_phy_mdc] [get_bd_ports eth_mdc]
connect_bd_net [get_bd_pins gmii_to_rgmii_0/mdio_phy_o] [get_bd_pins mdio_iobuf_0/mdio_o]
connect_bd_net [get_bd_pins gmii_to_rgmii_0/mdio_phy_t] [get_bd_pins mdio_iobuf_0/mdio_t]
connect_bd_net [get_bd_pins mdio_iobuf_0/mdio_i] [get_bd_pins gmii_to_rgmii_0/mdio_phy_i]
connect_bd_net [get_bd_pins mdio_iobuf_0/mdio_io] [get_bd_ports eth_mdio]
connect_bd_net [get_bd_pins axi_gpio_phy_reset/gpio_io_o] [get_bd_ports eth_phy_reset_n]

assign_bd_address
set_property range 64K [get_bd_addr_segs {ps7/Data/SEG_axi_gpio_phy_reset_Reg}]
set_property offset 0x41210000 [get_bd_addr_segs {ps7/Data/SEG_axi_gpio_phy_reset_Reg}]

validate_bd_design
save_bd_design

# Synthesize the small Ethernet bridge as part of the design, avoiding OOC IP
# report-worker failures seen with gmii_to_rgmii in this Vivado release.
set_property synth_checkpoint_mode None [get_files $proj_dir/$proj_name.srcs/sources_1/bd/$bd_name/$bd_name.bd]
make_wrapper -files [get_files $proj_dir/$proj_name.srcs/sources_1/bd/$bd_name/$bd_name.bd] -top
add_files -norecurse $proj_dir/$proj_name.gen/sources_1/bd/$bd_name/hdl/${bd_name}_wrapper.v
update_compile_order -fileset sources_1

launch_runs impl_1 -to_step write_bitstream -jobs 2
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
if {![string match "*Complete*" $impl_status]} {
    error "Implementation did not complete successfully: $impl_status"
}
open_run impl_1
write_hw_platform -fixed -include_bit -force $proj_dir/${proj_name}.xsa

set bit_file [file join $proj_dir ${proj_name}.runs impl_1 system_wrapper.bit]
set xsa_file [file join $proj_dir ${proj_name}.xsa]
foreach output_file [list $bit_file $xsa_file] {
    if {![file exists $output_file]} {
        error "Expected build output not found: $output_file"
    }
}

puts "Vivado block design validation: PASS"
puts "Bitstream: $bit_file"
puts "XSA: $xsa_file"
