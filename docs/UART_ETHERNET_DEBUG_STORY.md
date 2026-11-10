# UART-to-Ethernet Debug Story

The UART and Ethernet tests below were run on 2026-11-09 with JTAG-loaded Linux 6.18.10-xilinx, Buildroot 2026.05, and the board's RTL8211E, before persistent media programming. The later Flash/SD cold-boot check is recorded separately in [Flash and SD Boot](BOOT_MEDIA.md).

## UART First

COM13 uses 115200 baud, 8N1, without flow control. At `buildroot login:`, enter `root`. The default shell is BusyBox sh; enter `bash` for Bash.

The earlier receive failure came from the inherited ZC702 Device Tree: its UART1 pinctrl selected MIO48/49, but this board wires UART1 through EMIO to L17/M17. The board DTS removes those pinctrl properties, and the JTAG loader releases stale MIO selections. Live JTAG reads returned `0x1601` on both pins.

A separate PC-side failure was caused by an old diagnostic process holding COM13 in an unbounded read loop. That process was stopped. `scripts/uart_command.ps1` now has a deadline and closes the port in `finally`, on success or failure.

The helper was also tested with a command returning exit status 1 and with a one-second timeout on a three-second sleep. Both reported failure and released COM13; a subsequent command returned `UART_REOPEN_OK`. A timeout does not cancel the remote command, so wait for it to finish or interrupt it from the serial console before sending another command.

Bash initially disappeared from the resolved Buildroot configuration because `BR2_PACKAGE_BUSYBOX_SHOW_OTHERS` was not selected. Both options are now set, and bootstrap checks the resolved configuration rather than trusting the defconfig text.

Actual interactive UART output after the final JTAG load:

```text
# bash
# echo UART_BASH_INPUT_OK; echo $BASH_VERSION; id
UART_BASH_INPUT_OK
5.2.37(1)-release
uid=0(root) gid=0(root) groups=0(root),10(wheel)
```

Close other serial terminals before using the command helper. It expects an already logged-in shell:

```powershell
.\scripts\uart_command.ps1 -Command 'id; ethtool eth0; ip route' -LogPath build/uart-check.log
```

## Keep The GEM Clock Gate

The data path is PS GEM0 -> EMIO GMII -> PL GMII-to-RGMII -> RTL8211E. The bridge takes FCLK1 at approximately 200 MHz and generates the GMII transmit clocks internally. See [AMD PG160](https://docs.amd.com/r/en-US/pg160-gmii-to-rgmii/Core-Functionality-Tab).

Linux originally printed `unable to generate target frequency: 125000000 Hz`. Debugfs showed `gem0_emio_mux` as an orphan clock with a reported rate of zero. The actual source is the PL bridge, not the PS divider that MACB was trying to program.

Removing the optional `tx_clk` from GEM0's DTS was a failed experiment, not the final fix:

| Experiment | Result |
| --- | --- |
| Omit GEM0 tx_clk | FAIL: PHY still reported 1 Gbps, but TCP could not reach the PC |
| Read GEM0_CLK_CTRL after unused-clock shutdown | `0x00100140`: the gate was disabled |
| Diagnostic re-enable to `0x00100141` | Binary download immediately worked and its SHA-256 matched |

The final DTS retains `pclk`, `hclk`, and `tx_clk`. A small downstream [MACB patch](../buildroot-external/patches/linux/0001-net-macb-keep-zynq-gmii-clock-rate-under-pl-control.patch) skips rate programming only for Zynq GMII. MACB still enables/disables the clock gate normally; the Xilinx bridge driver still sets the speed through MDIO. The PHY and bridge drivers are otherwise unchanged. This patch has not been submitted upstream.

The final boot had no target-frequency warnings. UART readback returned `GEM0_CLK_CTRL=0x00100141`, and binary transfers worked at both 100 and 1000 Mbps. The diagnostic devmem write is not part of startup.

## Direct PC Connection

The board uses `192.168.7.2/24`; the PC USB Ethernet adapter uses `192.168.7.1/24`. Windows `ZynqUsbNat` forwards that subnet through Wi-Fi. There is no DHCP server on this link, so the init script uses its static fallback. Public ping and DNS tests are not run during init.

Initially the board could transfer TCP data and access the Internet, but the PC did not answer ICMP echo requests. Running the following in an administrator PowerShell created a rule restricted to this adapter and these two addresses:

```powershell
.\scripts\allow_board_ping.ps1
```

Afterward the board received 5/5 replies from the PC. The script does not disable the firewall or expose a board shell. To remove this lab rule later, run `Remove-NetFirewallRule -Name ZynqDirectLink-ICMPv4-Echo` as administrator.

## Binary Transfers

Start the bounded test server on the PC:

```powershell
python -u scripts/ethernet_transfer_server.py --seconds 600
```

From the UART shell:

```sh
wget -q -T 20 -O /tmp/ethernet-stress.sh http://192.168.7.1:8080/stress.sh
bash /tmp/ethernet-stress.sh 192.168.7.1 8080 100
```

Or run the same command using `uart_command.ps1` with `-TimeoutSeconds 300 -LogPath build/uart_eth_stress.log`.

Each round downloads a random 1 MiB binary payload, verifies its SHA-256, then uploads the same bytes. The PC verifies the complete upload before returning success. Bash's TCP redirection preserves embedded NUL bytes; the earlier BusyBox wget POST test had truncated a binary payload.

Two 100-round runs passed at 1 Gbps; a five-round run also passed after deliberately advertising only 100 Mbps. The PC server counted 205 downloads, 205 valid uploads, and zero bad uploads: 410 MiB total across the tests.

Final 100-round output:

```text
ETH_COUNTERS: carrier=13->13 rx_errors=0->0 tx_errors=0->0
ETH_STRESS: PASS rounds=100 bytes_each_direction=104857600 elapsed_seconds=15 speed_mbps=1000
```

Payload SHA-256: `38ad4b0d038cb1d9fdaba3c1b87a2500703b05dde9c4503fe158d88279c90d71`. Each server invocation generates a new payload and hash.

## Stability And Limits

After restoring the original advertised speeds and pause capabilities, Windows received 180/180 replies from the board. During a 184-second UART observation the carrier-change counter stayed at 13. Public ping received 179/180 replies and DNS resolved IPv4/IPv6 addresses. BusyBox rounded that loss to 0%; the actual count is one missing reply, about 0.56%. Its location in the PC/Wi-Fi/Internet path was not isolated.

The final handoff check extended the observation to 601 seconds: uptime advanced from 225.62 to 826.58 seconds while the carrier counter remained 13 and RX/TX errors remained zero. This interval included the ping test, another binary transfer run, and idle time; it was not ten minutes of continuous bulk load.

Changing advertised speeds caused multiple link-training down/up transitions before the final stable interval. This test does not establish that every cable, USB adapter, or repeated renegotiation is reliable, and the clock-warning fix is not proof of a physical-link fix. A 24-hour test and repeated cold boots remain NOT TESTED.

These transfer tests used Linux loaded into DDR by JTAG, not the persistent boot chain. Flash and a software-only SD card were subsequently programmed and read back. One physical power cycle then reached Linux, Bash, gateway ping and Internet/DNS without JTAG loading; see [Boot Media](BOOT_MEDIA.md) and the [captured output](evidence/cold-boot.txt). The preserved U-Boot still prints ZC702/PHY-address-7 messages; its network driver is not the tested Linux MACB/RTL8211E path.

Local evidence files are under ignored `build/`: `uart_eth_final_boot.log`, `uart_bash_interactive.log`, `uart_eth_stress_final.log`, `pc_eth_stability.log`, `uart_eth_stability_excerpt.log` (final capture chunk only), `uart_eth_final_state.log`, and `uart_eth_handoff.log`. The temporary HTTP server was stopped after the tests.
