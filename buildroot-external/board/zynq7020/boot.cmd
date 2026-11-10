# The preserved U-Boot has a 1 GiB ZC702 control DT; this Linux board uses 512 MiB.
# Keep boot allocations below 256 MiB, clear of the resident bootloader.
setenv fdt_high 0x10000000
setenv initrd_high 0x10000000
setenv bootm_low 0x00000000
setenv bootm_size 0x10000000
setenv bootargs console=ttyPS0,115200 rdinit=/init loglevel=8
if fatload mmc 0:1 0x02000000 zImage && fatload mmc 0:1 0x06000000 rootfs.cpio.gz; then
    setenv sd_initrd_size ${filesize}
    if fatload mmc 0:1 0x07000000 zynq7020-bringup.dtb; then
        echo SD_BOOT_512M
        bootz 0x02000000 0x06000000:${sd_initrd_size} 0x07000000
    fi
fi
echo SD_BOOT_FAILED
