#!/usr/bin/env sh
set -eu

images_dir="$1"
sed 's/\r$//' "$BR2_EXTERNAL_ZYNQ7020_PATH/board/zynq7020/boot.cmd" > "$images_dir/boot.cmd"
mkimage_bin=${MKIMAGE_BIN:-"$(dirname "$images_dir")/host/bin/mkimage"}
"$mkimage_bin" -A arm -O linux -T script -C none -n "Zynq SD Linux 512M" \
    -d "$images_dir/boot.cmd" "$images_dir/boot.scr"
bash "$BR2_EXTERNAL_ZYNQ7020_PATH/scripts/make_jtag_assets.sh" "$images_dir"
bash "$BR2_EXTERNAL_ZYNQ7020_PATH/scripts/make_sd_image.sh" "$images_dir"
