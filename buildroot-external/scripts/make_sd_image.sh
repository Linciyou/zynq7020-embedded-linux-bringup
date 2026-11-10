#!/usr/bin/env bash
# Package software-only SD media. This creates an image, never writes a disk.
set -euo pipefail

images_dir=${1:?Usage: make_sd_image.sh <buildroot-images-dir>}
genimage_bin="$(dirname "$images_dir")/host/bin/genimage"
work_dir=$(mktemp -d "$(dirname "$images_dir")/.genimage-zynq7020.XXXXXX")
trap 'rm -rf -- "$work_dir"' EXIT
root_dir="$work_dir/root"
config_file="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/board/zynq7020/genimage.cfg"

test -x "$genimage_bin" || { echo "Missing Buildroot genimage: $genimage_bin" >&2; exit 1; }
for file in zImage zynq7020-bringup.dtb rootfs.cpio.gz boot.cmd boot.scr; do
    test -f "$images_dir/$file" || { echo "Missing $images_dir/$file" >&2; exit 1; }
done
# Preserved U-Boot executes boot.scr at 0x03000000 while it loads zImage.
if (( $(stat -c %s "$images_dir/zImage") >= 0x01000000 )); then
    echo "zImage would overlap the running U-Boot script at 0x03000000" >&2
    exit 1
fi
if LC_ALL=C grep -q "$(printf '\r')" "$images_dir/boot.cmd"; then
    echo "boot.cmd contains CR characters; refusing an image U-Boot cannot parse" >&2
    exit 1
fi

mkdir -p "$root_dir"
export PATH="$(dirname "$images_dir")/host/bin:$(dirname "$images_dir")/host/sbin:$PATH"
"$genimage_bin" --rootpath "$root_dir" --tmppath "$work_dir/tmp" \
    --inputpath "$images_dir" --outputpath "$images_dir" --config "$config_file"

echo "Created $images_dir/sdcard.img"
