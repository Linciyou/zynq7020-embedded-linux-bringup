# JTAG Debugging

## Target And DDR Preflight

Run:

```powershell
& 'C:\AMDDesignTools\2025.2\Vitis\bin\xsct.bat' .\hardware\vivado\jtag_preflight.tcl
```

The script lists the JTAG targets, selects the Zynq APU/Cortex-A9 #0, applies PS initialization, tests DDR at `0x1FF00000`, restores the two words it used, and resumes/halts the ARM core once. A `PASS` from this script verifies JTAG access, PS initialization, DDR read/write, and the basic debug-control path only.

## Image Download

`jtag_boot_bringup.tcl` checks required files and ranges, loads the bitstream, downloads all three software images, sets the ARM Linux entry registers, and resumes Cortex-A9 #0. Its `JTAG_IMAGE_LOAD: PASS` means the XSCT transfers were accepted and execution was resumed. The script deliberately reports Linux user space as unconfirmed.

On 2026-10-22, a live UART capture on COM13 at 115200 8N1 showed `/init`, the Buildroot login prompt, RTL8211E binding at MDIO address 1, and network diagnostics. Logging in as `root` and running `echo UART_COMMAND_OK; id` returned the marker and `uid=0(root)`. See [Validation Record](VALIDATION.md) for current status.

## UART Input Diagnosis

In [the board schematic](../ZYNQ-7000原理图V2.0.pdf), page 3 shows CH340E TXD (pin 8) on `CH340_UART_TX` and RXD (pin 9) on `CH340_UART_RX`; its VCC and V3 are tied to 3.3 V. Page 7 connects `CH340_UART_TX` directly to `PS_UART_RX` at Zynq M17 and `CH340_UART_RX` directly to `PS_UART_TX` at L17. There is no UART-select jumper or series component on these two nets. SW3 is on the QSPI boot-mode nets, not the UART path.

The XDC maps RX to M17 and TX to L17. A synthesized-netlist inspection showed the M17 input buffer output and the PS7 `UART1_RX` pin on the same net segments. The PS7 configuration selects UART1 EMIO. The final DTB maps `serial0` to UART1 (`0xe0001000`), and Buildroot starts getty on `ttyPS0`.

To inspect UART1 configuration without halting Linux:

```powershell
& 'C:\AMDDesignTools\2025.2\Vitis\bin\xsct.bat' .\hardware\vivado\jtag_uart_inspect.tcl
```

The original failure was caused by the Device Tree inheriting ZC702's `pinctrl_uart1_default`. That group selects MIO 48/49 for UART1, overriding this board's EMIO wiring. Live SLCR reads showed `MIO_PIN_48=0x2E0` and `MIO_PIN_49=0x2E1` while the UART FIFO remained empty. The board DTS now removes `pinctrl-names` and `pinctrl-0` from `&uart1`; the JTAG boot script also releases any stale MIO 48/49 selection before starting Linux. After the corrected boot, both MIO registers stayed at `0x1601`, and a fresh synchronized RX probe read `0x55` from the UART1 FIFO (`SR=0x00000008`).

The PS UART local-loopback test and an ILA capture after the M17 input buffer were useful during diagnosis. The ILA saw 866-867 samples per bit at 100 MHz, consistent with 115200 baud. The normal bitstream was restored after capture. The decisive distinction was that valid PL input activity alone did not prove the PS UART was routed to EMIO.

The one-off ILA, FIFO injection and loopback scripts were removed after diagnosis. The normal bitstream, UART register inspection and direct JTAG Linux recovery flow are retained.

If UART RX regresses, check the live `MIO_PIN_48` (`0xF80007C0`) and `MIO_PIN_49` (`0xF80007C4`) values before blaming the CH340. The [Zynq-7000 MIO pin definition](https://docs.amd.com/r/en-US/ug585-zynq-7000-SoC-TRM/Register-MIO_PIN_49-Details) identifies MIO 49's UART1 RX selection. A successful XSCT download alone is not a UART input test.

## Locate The Kernel Entry

To load the images and stop at the raw zImage entry, run the boot script with the optional environment flag:

```powershell
$env:JTAG_BREAK_AT_KERNEL_ENTRY = '1'
& 'C:\AMDDesignTools\2025.2\Vitis\bin\xsct.bat' .\hardware\vivado\jtag_boot_bringup.tcl
Remove-Item Env:JTAG_BREAK_AT_KERNEL_ENTRY
```

The script checks that the Cortex-A9 halted at `0x02000000`. This confirms control reached the first zImage instruction; it does not confirm decompression, `start_kernel`, or user space. Without the flag, the script resumes the core as usual.

To trace kernel startup through the attempt to execute `/init`, first rebuild and copy the matching `System.map` with the JTAG images, then run:

```powershell
& .\buildroot-external\scripts\bootstrap_buildroot.sh
& .\scripts\copy_jtag_assets_from_wsl.ps1
$env:JTAG_TRACE_KERNEL_INIT = '1'
& 'C:\AMDDesignTools\2025.2\Vitis\bin\xsct.bat' .\hardware\vivado\jtag_boot_bringup.tcl
Remove-Item Env:JTAG_TRACE_KERNEL_INIT
```

The trace resolves `start_kernel`, `rest_init`, `kernel_init`, and `run_init_process` from the matching `System.map`, sets hardware breakpoints, and checks the PC at each stage. Reaching `run_init_process` confirms the kernel attempted to launch `/init`; it does not by itself prove the initramfs program executed successfully or that UART/Ethernet works.

For a manual hardware breakpoint at the raw zImage entry after loading the images:

```tcl
connect
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
stop
bpadd -addr 0x02000000
con -addr 0x02000000
rrd
```

The core should stop at the breakpoint before executing the first zImage instruction. `rrd` displays the register state. Remove the breakpoint with `bpremove <id>` and resume with `con`.

## Kernel Symbols

Buildroot retains the unstripped `vmlinux` alongside the kernel build tree. With the target stopped after the decompressor has entered the linked kernel address space, load symbols without downloading the ELF over the running image:

```tcl
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
memmap -file <path-to-vmlinux>
bpadd -addr &start_kernel
con
```

Use `bplist`, `rrd`, `bt`, `stop`, and `help breakpoint` in XSCT. Symbol resolution depends on the kernel's relocation/MMU stage; a breakpoint at `start_kernel` is not evidence that user space later started. AMD's XSDB guide documents `memmap -file` for an already-running target, and the Linux ARM boot protocol defines the entry register contract: [AMD XSDB Reference Guide](https://docs.amd.com/r/2025.2-English/ug1725-xsdb-reference-guide/Debugging-a-Program-Already-Running-on-the-Target), [Linux ARM booting](https://docs.kernel.org/arch/arm/booting.html).

This configuration keeps kernel symbol tables and frame pointers for address-level debugging, but does not include DWARF source information; source-line and local-variable inspection are therefore not available.

## What JTAG Does Not Provide

JTAG is used here to access the debug target, initialize DDR, program volatile PL configuration, transfer files, inspect registers/memory, and control the core. UART is the Linux console. The [UART-to-Ethernet debug story](UART_ETHERNET_DEBUG_STORY.md) records interactive login and network commands from the serial shell, with results independent of JTAG transfer success.
