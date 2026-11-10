#!/usr/bin/env bash
# Run from a Linux-native checkout, not from /mnt/c.
set -euo pipefail

# WSL inherits Windows PATH entries containing spaces. Buildroot rejects those
# entries, so use only the standard Linux tool locations for the build.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
buildroot_dir="$root_dir/.buildroot/buildroot-2026.05"
output_dir="$root_dir/build/buildroot-zynq7020"
network_init="$root_dir/buildroot-external/board/zynq7020/rootfs-overlay/etc/init.d/S41ethernet"

if [[ "$root_dir" == /mnt/* ]]; then
    echo "Move this repository under your Linux home directory before building." >&2
    exit 1
fi

chmod 0755 "$network_init"

if [ ! -d "$buildroot_dir/.git" ]; then
    mkdir -p "$(dirname "$buildroot_dir")"
    git clone --depth 1 --branch 2026.05 https://gitlab.com/buildroot.org/buildroot.git "$buildroot_dir"
fi

make -C "$buildroot_dir" O="$output_dir" \
    BR2_EXTERNAL="$root_dir/buildroot-external" zynq7020_bringup_defconfig

for option in BR2_PACKAGE_BASH BR2_PACKAGE_ETHTOOL BR2_TARGET_ROOTFS_CPIO_GZIP; do
    if ! grep -qx "$option=y" "$output_dir/.config"; then
        echo "Required option was not selected by Kconfig: $option" >&2
        exit 1
    fi
done

kernel_source="$output_dir/build/linux-custom"
if [ -f "$kernel_source/.stamp_patched" ] &&
    ! grep -q 'Zynq GMII takes its TX clock from PL' "$kernel_source/drivers/net/ethernet/cadence/macb_main.c"; then
    echo "Existing kernel tree predates the GMII clock patch." >&2
    echo "Run: make -C '$output_dir' linux-dirclean; then rerun this script." >&2
    exit 1
fi

# Buildroot does not notice changes to external DTS/config fragments by itself.
external_dts="$root_dir/buildroot-external/board/zynq7020/zynq7020-bringup.dts"
staged_dts="$output_dir/build/linux-custom/arch/arm/boot/dts/$(basename "$external_dts")"
kernel_fragment="$root_dir/buildroot-external/board/zynq7020/linux.fragment"
configured_stamp="$output_dir/build/linux-custom/.stamp_configured"
if [ -f "$configured_stamp" ] && [ "$kernel_fragment" -nt "$configured_stamp" ]; then
    make -C "$output_dir" linux-reconfigure
elif [ -f "$staged_dts" ] && [ "$external_dts" -nt "$staged_dts" ]; then
    make -C "$output_dir" linux-rebuild
fi

busybox_fragment="$root_dir/buildroot-external/board/zynq7020/busybox.fragment"
for stamp in "$output_dir"/build/busybox-*/.stamp_configured; do
    if [[ -f "$stamp" && "$busybox_fragment" -nt "$stamp" ]]; then
        make -C "$output_dir" busybox-reconfigure
    fi
done

make -C "$output_dir"

echo "Build complete: $output_dir/images"
echo "Expected JTAG files: zImage, rootfs.cpio.gz, zynq7020-bringup.dtb"
