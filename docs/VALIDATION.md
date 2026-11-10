# Validation Record

Status meanings: `PASS` means the step was run and met its criterion; `FAIL` means it was run and did not; `NOT TESTED` means no result is available. Update this file only with observed results.

| Test | Acceptance criterion | Status | Evidence |
| --- | --- | --- | --- |
| Vivado design | `validate_bd_design` reports no errors | PASS | Vivado 2025.2; implementation and routed timing report completed |
| Bitstream and XSA | Both expected output files exist after successful implementation | PASS | `system_wrapper.bit` and `zynq7020_bringup.xsa` generated under `build/vivado/zynq7020_bringup/` |
| Buildroot | Kernel, initramfs, DTB and SD image pass packaging checks | PASS | Final 2026-11-09 media: zImage 5,480,024 bytes; initramfs 4,650,898 bytes; DTB 17,567 bytes; SD image 67,109,376 bytes. Matching System.map copied; no JTAG load-range overlap |
| JTAG target | Zynq APU and Cortex-A9 #0 are selectable | PASS | XSCT 2025.2 `jtag_preflight.tcl` selected APU and Cortex-A9 #0 |
| DDR access | Test words read back and original contents are restored | PASS | Read/write at `0x1FF00000`; original two words restored |
| Core control | Cortex-A9 resumes and can be halted | PASS | XSCT resumed and halted the core; PC was readable |
| JTAG image load | Bitstream and software image downloads are accepted | PASS | XSCT 2025.2 loaded the final bitstream, zImage at `0x02000000`, initramfs at `0x06000000`, and DTB at `0x07000000`, then resumed Cortex-A9 #0 |
| Kernel entry | Cortex-A9 reaches the zImage entry breakpoint | PASS | A separate breakpoint run hit `0x02000000` and XSCT PC readback matched; the full boot run then resumed the core into Linux |
| Linux user space | `/init` runs and a login prompt is observed | PASS | COM13 at 115200 8N1 captured `Run /init as init process`, Buildroot service startup, `Welcome to Buildroot`, and `buildroot login:` after JTAG loading |
| UART board-to-PC console | Kernel log and login prompt reach the connected PC | PASS | COM13 captured the live log and login prompt |
| UART RX pad waveform | COM13 115200 8N1 activity reaches constrained PL input M17 | PASS | Vivado ILA triggered on repeated `0x55`; observed 866-867 100 MHz samples per bit (about 8.67 us) |
| UART RX buffered net | COM13 activity is present after the M17 IBUF and routed to PS7 `UART1_RX` | PASS | 2026-10-22 synthesized net segments connect `ps_uart_rx_IBUF_inst/O` to PS7 `UART1_RX`; ILA on the buffered net captured 866-867 100 MHz samples per bit |
| UART1 software configuration | UART1 is enabled for Linux console and RX | PASS | DT alias `serial0` maps to UART1 at `0xe0001000`; Buildroot getty uses `ttyPS0`; PS7 handoff selects UART1 EMIO; JTAG read CR=`0x114`, MR=`0x20`, BRGR=`124`, BDIV=`6` |
| UART1 MIO/EMIO routing | Linux leaves UART1 on this board's EMIO path | PASS | Board DTS removes inherited ZC702 UART1 MIO pinctrl; after JTAG boot, live `MIO_PIN_48` and `MIO_PIN_49` both read `0x1601` |
| UART1 internal local loopback | PS UART1 can transmit and receive one byte internally | PASS | JTAG loopback returned `0x55` through RX FIFO; original mode was restored and both A9 cores resumed |
| UART PC-to-board RX path | A byte sent on COM13 reaches the PS UART1 RX FIFO | PASS | Fresh synchronized test after RX FIFO reset: sent `0x55` while both A9 cores were halted; RX FIFO returned `0x55`, SR=`0x00000008`; cores resumed |
| UART shell command input | Root login and interactive Bash input work | PASS | Final JTAG boot: entered bash; BASH_VERSION=5.2.37(1)-release and uid=0(root). COM13 closed after bounded command tests |
| GEM MAC address | Interface uses a reproducible locally administered address | PASS | Final UART log: `eth0 ... (02:00:00:70:20:01)`; this is a lab address, not a factory-assigned MAC |
| PHY reset control | Linux applies the DT reset GPIO delays | PASS | Current image binds the PHY after the 10 ms assert / 50 ms deassert delays; electrical waveform at `PHYRSTB` was not measured |
| PHY reset wiring/timing | H17 toggles the actual PHY `PHYRSTB` pin with compliant timing | NOT TESTED | Schematic marks R46 NC; no continuity check or oscilloscope capture was made |
| Schematic-derived PHY address 3 | PHY responds at the address implied by R33/R34/R41 | FAIL | Linux did not find a PHY at address 3; the tested RTL8211E bound at address 1 instead, so the schematic/assembly discrepancy remains open |
| GEM0 PHY probe at address 1 | RTL8211E binds to PHYLIB | PASS | UART: `PHY [e000b000.ethernet-ffffffff:01] driver [RTL8211E Gigabit Ethernet]` |
| Ethernet link | RTL8211E negotiates with the PC USB adapter | PASS | Final boot: 1000Mb/s, full duplex, PHY address 1; Windows also reported 1 Gbps |
| DHCP on direct link | Host provides an address lease | FAIL | Expected here: Windows NAT has no DHCP server. Static fallback succeeded: 192.168.7.2/24, gateway 192.168.7.1, DNS 1.1.1.1 |
| PC-to-board connectivity | PC pings 192.168.7.2 | PASS | 2026-11-09: 180 sent, 180 received, 0 lost; 0-15 ms |
| Board-to-PC gateway ICMP | Board pings 192.168.7.1 | PASS | Scoped Windows ICMP rule added: 5 sent, 5 received. Before that rule, 3/0 despite working TCP transfers |
| Board Internet IPv4 | Board reaches a public IPv4 address through NAT | PASS | 180 sent to 1.1.1.1, 179 received, one lost (0.56%). Average 10.254 ms. Reachability only, not loss-free Internet validation |
| Board DNS | Linux resolves a public DNS name | PASS | UART shell `nslookup example.com` via `1.1.1.1` returned A and AAAA records |
| UART Ethernet debug command set | Inspect addresses, routes, PHY and clocks | PASS | Bash 5.2.37, ethtool, BusyBox ip, dmesg, sysfs counters and debugfs clk_summary |
| PC-to-board TCP file transfer | Binary downloads pass SHA-256 verification | PASS | Two 100-round runs at 1 Gbps, 1 MiB per download. Hash 38ad4b0d038cb1d9fdaba3c1b87a2500703b05dde9c4503fe158d88279c90d71 |
| Board-to-PC TCP file transfer | PC verifies complete binary uploads | PASS | Same runs: 1 MiB per upload through Bash TCP redirection; all hashes matched, including embedded NUL bytes |
| Ethernet counters | No new carrier changes or RX/TX errors during final transfer run | PASS | Final 100 rounds: carrier 13->13, rx_errors 0->0, tx_errors 0->0; 100 MiB each direction in 15 seconds |
| SSH | Remote shell is available over Ethernet | NOT TESTED | No SSH server is included or tested in this bring-up image |
| GEM clock gate/rate handling | Keep gate enabled without programming the PL clock through the PS divider | PASS | GEM0_CLK_CTRL=0x00100141; zero target-frequency warnings. Omitting tx_clk was a failed experiment, not the final DTS |
| 100 Mbps fallback | Data transfers after deliberate speed renegotiation | PASS | Five rounds with matching hashes; original advertisement restored, 1 Gbps re-established |
| Bounded link stability | No carrier changes during observation | PASS | 601 seconds (uptime 225.62->826.58): carrier 13->13, errors zero. Ping, transfers and idle time; not continuous bulk load. Manual advertisement changes before this window caused repeated training transitions |
| Extended reliability | 24-hour operation and repeated cold boots | NOT TESTED | Bounded tests do not establish long-term or cold-boot reliability |
| Automatic media warm boot | Flash bootloader loads SD Linux without JTAG or manual commands | PASS | Final SD image; `build/media-final-autoboot.log`: countdown, boot.scr, SD_BOOT_512M, /init, root login, Bash 5.2.37, 1 Gbps and gateway ping 3/3 |
| BootROM/FSBL/U-Boot cold boot | Final images boot after physical power removal | PASS | User confirmed physical power cycle during capture; build/media-final-coldboot.log shows original U-Boot, SD boot.scr, Linux /init, root/Bash, 1 Gbps and gateway ping 3/3; no JTAG download or U-Boot intervention. BootROM/FSBL are inferred from the persistent path, not independently instruction-traced |
| Preserved U-Boot | Same bytes in old backup and new boot image | PASS | SHA-256 d23950f2ceb504da6263de559f0b587f2fbf7b116dba971f2b3d39e283cde94b; not rebuilt or trimmed |
| QSPI write | Program and independently read back boot image | PASS | 5,237,336 bytes in mtd0; flashcp and readback SHA-256 a20e082c2928668972f8243858d7aa416b03e91f48c08e096bc1ac9a8a3585b6 passed; includes FSBL UART handoff hook |
| SD write | Full image readback matches image | PASS | Final update from RAM-root Linux to guarded, unmounted mmcblk0; 67,109,376 bytes; SHA-256 017f3de64df807c58ccf507b2aeafa811f693cc0cec34a4e8297a9668c69c3b5 |
| Internet after final cold boot | Public IPv4 and DNS work over PC NAT | PASS | build/media-coldboot-internet.log: 1.1.1.1 ping 5/5, example.com A/AAAA lookup succeeds, RX/TX error counters both 0 |
| Original SD extlinux attempt | Kernel can be retrieved | FAIL | CRLF became /zImage\\r; replaced by LF-normalized boot.cmd and generated boot.scr |
| Original initrd relocation | Initramfs remains inside Linux memory | FAIL | Preserved U-Boot relocated above 512 MiB; final SD script limits boot allocations below 256 MiB; corrected boot runs /init |

Earlier Linux user-space and Ethernet stress results used JTAG-loaded Linux. The final media warm-boot checks above are separate UART observations after Linux reboot, without JTAG downloads. XSCT reports image transfers and core resume only; it does not provide a serial console. See [Boot Media](BOOT_MEDIA.md) for the failed attempts and fixes.

Schematic pages 3 and 7 show CH340 TXD directly connected to Zynq M17; SW3 only controls QSPI boot straps. The earlier RX failure was a pinctrl conflict, not an XDC pin swap: the inherited ZC702 UART1 pinctrl reassigned RX to MIO 49. The board DTS now deletes that inherited pinctrl, and the JTAG boot script clears stale MIO 48/49 routing before Linux starts. The post-fix login, shell command, FIFO byte, and live MIO readback (`0x1601` on both pins) were all observed on 2026-10-22.

During the earlier PHY@3/no-reset failure, a read-only XSCT snapshot returned `0` for GEM0 NCR, NCFGR, NSR, and MAN. No MDIO transaction was issued, and the GEM clock/reset state was not independently established, so that snapshot is inconclusive. It predates the successful PHY@1 build and is not evidence against the final link test.

The earlier Vivado build had zero DRC errors, WNS +0.240 ns and TNS 0.000 ns. This repair reused that bitstream; Vivado was not rebuilt in this session. Its existing IP clock-constraint and REQP-1577 warnings remain. The final kernel retains the GEM clock gate and includes a downstream MACB rate-handling patch; no target-frequency warning appeared in the new boot. See [UART-to-Ethernet Debug Story](UART_ETHERNET_DEBUG_STORY.md) for the failed experiment and final tests.
