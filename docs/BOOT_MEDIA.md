# Flash And SD Deployment

Written and read back on 2026-11-09. U-Boot was not rebuilt or trimmed.

```text
QSPI: FSBL -> PL bitstream -> preserved U-Boot
                                  |
SD FAT: boot.scr -> zImage + Device Tree + rootfs.cpio.gz
                                  |
                           DDR -> Linux -> UART / Ethernet
```

The SD card contains software only. The initramfs is read from SD and unpacked into RAM; this is not a persistent ext4 root filesystem. There is no BOOT.BIN or FPGA bitstream on SD.

## Recorded Images

| Image | Bytes | SHA-256 |
| --- | ---: | --- |
| QSPI BOOT_QSPI.bin | 5,237,336 | a20e082c2928668972f8243858d7aa416b03e91f48c08e096bc1ac9a8a3585b6 |
| SD sdcard.img | 67,109,376 | 017f3de64df807c58ccf507b2aeafa811f693cc0cec34a4e8297a9668c69c3b5 |
| Preserved u-boot.bin | 1,087,512 | d23950f2ceb504da6263de559f0b587f2fbf7b116dba971f2b3d39e283cde94b |

The preserved U-Boot bytes occur at offset 4,149,824 in both the old QSPI backup and the new boot image. `scripts/check_boot_payload.py` checks the preserved hash and its presence in the packaged image. The original U-Boot's countdown, device support and default environment behavior remain unchanged.

## QSPI

The original 6 MiB `qspi-boot` partition was backed up through Linux MTD and transferred to the PC. Both sides reported SHA-256 `e39dbde52f5ffc9caa13d7da07929ddebac21e16ae64e12a73eacad38250c9d5`. The backup is retained at `build/flash-backup/qspi-boot-before.bin`; do not discard it before normal boot has been verified.

The new FSBL was generated from the current XSA with Vitis 2025.2. The platform backend timed out after generating its sources, but the script's native BSP/FSBL make steps completed and produced `fsbl.elf`. Bootgen packaged that ELF, the existing bring-up bitstream, and the original U-Boot.

AMD program_flash's no-erase/no-program verification did not complete with the board strapped for QSPI boot. That attempt was canceled without programming. The actual write used BusyBox `flashcp` from the JTAG-loaded Linux system:

1. Check `/dev/mtd0` is named `qspi-boot` and is 6 MiB.
2. Compare the current contents with the saved backup before erasing.
3. Download the boot image and verify its SHA-256.
4. Run `flashcp`, which erases, writes and verifies the required sectors.
5. Independently read the programmed 5,237,336 bytes and compare SHA-256.

Result: `QSPI_WRITE_VERIFY_PASS`. Only the first 80 erase blocks were rewritten, ending at `0x00500000`; the remainder of the 6 MiB boot partition and the separate data/environment area were not erased.

Build/package commands:

```powershell
& 'C:\AMDDesignTools\2025.2\Vitis\bin\xsct.bat' hardware/vivado/create_zynq_fsbl.tcl
# Keep the preserved u-boot.bin at build/linux_images/u-boot.bin.
& 'C:\AMDDesignTools\2025.2\Vitis\bin\xsct.bat' hardware/vivado/package_qspi_boot.tcl
python scripts/check_boot_payload.py
```

To program, first create a fresh verified backup and ensure the UART root shell and Ethernet work. Serve `build/flash_images` on the PC with `python -m http.server 8080 --bind 192.168.7.1 --directory build/flash_images`, then run `scripts/program_qspi.ps1 -ConfirmErase`. Its confirmation prompt and backup comparison are intentional. Stop the HTTP server afterward. Never put this operation in an init script.

## SD Card

The verified target was USB Disk 1, Generic STORAGE DEVICE, serial `000000000819`, capacity 15,931,539,456 bytes. Disk 0 was the Windows system disk and was not modified. These are observations from this workstation, not portable disk-selection defaults.

The image has one 64 MiB FAT partition; the remaining card capacity is unallocated. Contents:

```text
/zImage
/zynq7020-bringup.dtb
/rootfs.cpio.gz
/boot.scr
```

The writer validates USB/non-system status, serial and capacity, locks target volumes, and uses sector-aligned native Windows I/O. This avoids the unsupported offline operation for removable cards and .NET FileStream length queries on raw disks. A complete byte-for-byte readback verified all 67,109,376 image bytes.

After correcting the boot script, the final image above was downloaded to `/tmp` on the running board and written to its unmounted `/dev/mmcblk0`. Before writing, the command checked RAM rootfs, no mounted MMC filesystem, 31,116,288 sectors and card CID `035344534331364780428c9a8c019300`. A complete 67,109,376-byte raw readback produced the same SHA-256 as the PC image. This was a board-side update; the SD was no longer in the USB reader.

Run the write/verify utilities in administrator PowerShell only after reviewing `Get-Disk`. Pass `-ExpectedSerialNumber` and `-ExpectedSizeBytes` from that reviewed target; do not reuse Disk 1 blindly. `-WhatIf` is supported by the writer. `storage_guard.ps1` contains the shared guard and native I/O implementation.

## Boot Validation

| Check | Result |
| --- | --- |
| Preserved U-Boot matches old flash backup and new image | PASS |
| QSPI programming plus independent readback SHA-256 | PASS |
| SD writing plus complete byte-for-byte readback | PASS |
| Automatic warm reset -> Flash bootloader -> SD Linux -> UART root shell | PASS: final SD image, no JTAG download or manual U-Boot commands |
| UART Bash / Ethernet after media boot | PASS: Bash 5.2.37, 1000 Mb/s, gateway ping 3/3 |
| Physical power-on with final QSPI and SD images | PASS: user confirmed physical power cycle; UART captured automatic SD boot, root/Bash, 1 Gbps and gateway ping 3/3 |

Programming and readback do not establish cold-boot success. The direct JTAG Linux recovery path remains available.

Capture a new physical power cycle with `scripts/verify_media_boot.ps1`. It opens COM13 and sends nothing during U-Boot; after the Linux login prompt it logs in as root and checks Bash, link speed and gateway ping. `-Reboot` instead performs a Linux warm reboot; that is not cold-boot evidence. Logs are saved even on timeout and the UART handle is always closed.

## Boot Debug Record

1. The first physical power-on found the SD but parsed CRLF in extlinux as `/zImage\r`; image retrieval failed. Generated `boot.cmd` is now normalized to LF and checked before packaging. The final card uses compiled `boot.scr`, not extlinux.
2. With that fixed, the unchanged U-Boot's ZC702 control DT described 1 GiB and placed initramfs at `0x2fb90000`, outside Linux's 512 MiB memory node. Linux disabled initrd and panicked. The SD script sets `fdt_high`, `initrd_high` and `bootm_size` to `0x10000000`, with `bootm_low=0`, keeping relocation below 256 MiB. Kernel/initial initramfs/DTB loads are `0x02000000`, `0x06000000`, `0x07000000`. The successful log places initrd at `0x0fb90000` and runs `/init`.
3. A spurious UART RX byte stopped autoboot at `Zynq>`. The tracked FSBL `BeforeHandoff` hook restores EMIO routing, resets RX FIFO and clears pending UART status after PL setup, without changing TX/baud. After repackaging and verifying QSPI, the countdown proceeded automatically on two warm boots.

The original U-Boot still prints its ZC702 model/1 GiB description, bad environment CRC, missing PHY at address 7, and failed QSPI/JTAG script searches before finding SD. Those warnings were not hidden or fixed by rebuilding U-Boot. Linux uses the board DT, 512 MiB memory and PHY address 1; Linux Ethernet passed. Do not infer that U-Boot Ethernet works from Linux networking.

Local evidence: `build/qspi-program-uart.log`, `build/sd-final-write.log`, `build/media-final-autoboot.log`, and `build/media-final-coldboot.log`. The last capture was started before the user confirmed a physical power cycle; no JTAG load or manual U-Boot command was sent. It establishes one successful cold boot, not repeated-power-cycle reliability. These are generated observations, not fabricated sample boot logs.

The [cold-boot capture](evidence/cold-boot.txt) and [network check](evidence/network.txt) are preserved in this repository. Full programming logs and recovery backups remain local under `build/`; never delete a flash backup as part of source cleanup.
