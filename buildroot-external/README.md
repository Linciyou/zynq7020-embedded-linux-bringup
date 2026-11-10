# Buildroot Bring-up Image

`configs/zynq7020_bringup_defconfig` builds a minimal ARM Cortex-A9 Linux image for direct JTAG loading:

- Linux `zImage` plus the matching unstripped `vmlinux` in the kernel build tree for symbol-based debug.
- Device Tree `zynq7020-bringup.dtb` for PS GEM0, MDIO, GMII-to-RGMII, QSPI, SD0, DDR, and the UART1 console.
- BusyBox root filesystem with Bash and ethtool, packaged as `rootfs.cpio.gz`. The login shell remains BusyBox sh; run `bash` explicitly.
- Built-in kernel support for MACB/GEM, PHYLIB/RTL8211E, Xilinx GMII-to-RGMII, and PS UART.
- Initramfs Ethernet setup that waits for carrier, tries DHCP, falls back to a direct-link static address, and prints interface/route details. Public Internet checks are run from UART, not during init.
- A downstream MACB patch for the Zynq GMII external transmit clock. It keeps `tx_clk` enabled for the GEM gate while leaving clock-rate selection to the PL bridge. `patches/linux/linux.hash` records the validated source archive hash.

Buildroot runs from a Linux-native WSL2 directory. The first-stage JTAG flow uses only the kernel, DTB, and initramfs; it does not mount an SD root filesystem. `make_jtag_assets.sh` records the initramfs DDR range in `/chosen` after checking the image bounds.

The post-image hook also creates a software-only FAT SD image containing kernel, DTB, initramfs and boot.scr (compiled from boot.cmd with host mkimage). U-Boot is not rebuilt, and there is no ext4 partition. The SD script limits boot-time allocations below 256 MiB because the preserved bootloader describes 1 GiB while Linux uses 512 MiB. Flash packaging reuses the preserved U-Boot binary separately. Building does not program either medium; see [Boot Media](../docs/BOOT_MEDIA.md) for explicit deployment and validation.
