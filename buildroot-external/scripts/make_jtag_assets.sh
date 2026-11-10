#!/usr/bin/env bash
# Add the externally loaded initramfs range to the Buildroot-generated DTB.
set -euo pipefail

images_dir=${1:?Usage: make_jtag_assets.sh <buildroot-images-dir>}
build_dir=$(dirname "$images_dir")
fdtput_bin=${FDT_PUT_BIN:-"$build_dir/host/bin/fdtput"}
if [[ ! -x "$fdtput_bin" ]]; then
	fdtput_bin=$(command -v fdtput || true)
fi
fdtget_bin=${FDT_GET_BIN:-"$build_dir/host/bin/fdtget"}
if [[ ! -x "$fdtget_bin" ]]; then
	fdtget_bin=$(command -v fdtget || true)
fi
kernel_file="$images_dir/zImage"
initrd_file="$images_dir/rootfs.cpio.gz"
dtb_file="$images_dir/zynq7020-bringup.dtb"
system_map_file="$build_dir/build/linux-custom/System.map"
kernel_addr=$((0x02000000))
initrd_addr=$((0x06000000))
dtb_addr=$((0x07000000))
ddr_end=$((0x20000000))

for file in "$fdtput_bin" "$fdtget_bin" "$kernel_file" "$initrd_file" "$dtb_file" "$system_map_file"; do
	test -f "$file" || { echo "Missing required JTAG asset: $file" >&2; exit 1; }
done
test -x "$fdtput_bin" || { echo "fdtput is not executable: $fdtput_bin" >&2; exit 1; }
test -x "$fdtget_bin" || { echo "fdtget is not executable: $fdtget_bin" >&2; exit 1; }

kernel_size=$(stat -c %s "$kernel_file")
initrd_size=$(stat -c %s "$initrd_file")
dtb_size=$(stat -c %s "$dtb_file")
initrd_end=$((initrd_addr + initrd_size))
dtb_end=$((dtb_addr + dtb_size))

if ((kernel_addr + kernel_size > initrd_addr)); then
	echo "zImage overlaps the initramfs load region" >&2
	exit 1
fi
if ((initrd_end > dtb_addr)); then
	echo "Initramfs overlaps the DTB load region; reduce the image or choose new addresses" >&2
	exit 1
fi
if ((dtb_end > ddr_end)); then
	echo "DTB lies outside the configured 512 MiB DDR range" >&2
	exit 1
fi

printf -v initrd_start_hex '0x%08x' "$initrd_addr"
printf -v initrd_end_hex '0x%08x' "$initrd_end"
"$fdtput_bin" -t x "$dtb_file" /chosen linux,initrd-start "$initrd_start_hex"
"$fdtput_bin" -t x "$dtb_file" /chosen linux,initrd-end "$initrd_end_hex"
bootargs=$("$fdtget_bin" -t s "$dtb_file" /chosen bootargs)
stdout_path=$("$fdtget_bin" -t s "$dtb_file" /chosen stdout-path)
if [[ "$bootargs" != *"console=ttyPS0,115200"* || "$stdout_path" != "serial0:115200n8" ]]; then
	echo "DTB console configuration is stale or incorrect: bootargs='$bootargs', stdout-path='$stdout_path'" >&2
	exit 1
fi
uart_status=$("$fdtget_bin" -t s "$dtb_file" /axi/serial@e0001000 status)
if [[ "$uart_status" != "okay" ]]; then
	echo "DTB UART1 node is not enabled: status='$uart_status'" >&2
	exit 1
fi
if "$fdtget_bin" -t x "$dtb_file" /axi/serial@e0001000 pinctrl-0 >/dev/null 2>&1; then
	echo "DTB still routes UART1 through the ZC702 MIO pinctrl group; this board uses EMIO" >&2
	exit 1
fi
phy_address=$("$fdtget_bin" -t x "$dtb_file" /axi/ethernet@e000b000/mdio/ethernet-phy@1 reg)
bridge_address=$("$fdtget_bin" -t x "$dtb_file" /axi/ethernet@e000b000/mdio/gmii-to-rgmii@8 reg)
gem_clocks=$("$fdtget_bin" -t s "$dtb_file" /axi/ethernet@e000b000 clock-names)
if [[ "$gem_clocks" != "pclk hclk tx_clk" ]]; then
	echo "DTB must retain the GEM TX gate even with a PL-sourced GMII clock: $gem_clocks" >&2
	exit 1
fi
if (( 0x$phy_address != 1 || 0x$bridge_address != 8 )); then
	echo "DTB Ethernet MDIO addresses are incorrect: PHY=$phy_address bridge=$bridge_address" >&2
	exit 1
fi
cp "$system_map_file" "$images_dir/System.map"
dtb_size=$(stat -c %s "$dtb_file")
dtb_end=$((dtb_addr + dtb_size))
if ((dtb_end > ddr_end)); then
	echo "Final DTB exceeds the configured 512 MiB DDR range" >&2
	exit 1
fi

printf 'JTAG assets checked: zImage=%#x (%s bytes), initramfs=%#x-%#x (%s bytes), DTB=%#x (%s bytes), console=%s, System.map copied\n' \
	"$kernel_addr" "$kernel_size" "$initrd_addr" "$initrd_end" "$initrd_size" "$dtb_addr" "$dtb_size" "$bootargs"
