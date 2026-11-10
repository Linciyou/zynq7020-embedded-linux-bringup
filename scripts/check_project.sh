#!/usr/bin/env bash
# Static repository checks; target hardware results are recorded separately.
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_dir"

git diff --check

for obsolete in \
    linux_driver/fft_dma_drv.c \
    linux_app/fft_dma_test.c \
    linux_app/fft_dma_bench.c \
    linux_app/fft_ethernet_server.c \
    include/uapi/fft_dma_uapi.h \
    buildroot-external/package/fft-dma-driver/fft-dma-driver.mk \
    buildroot-external/package/fft-dma-test/fft-dma-test.mk \
    buildroot-external/package/fft-dma-bench/fft-dma-bench.mk \
    buildroot-external/package/fft-dma-uapi/fft-dma-uapi.mk \
    buildroot-external/package/fft-ethernet-server/fft-ethernet-server.mk; do
    if [[ -e "$obsolete" ]]; then
        echo "Obsolete FFT/DMA path remains: $obsolete" >&2
        exit 1
    fi
done

for required in \
    hardware/vivado/create_zynq7020_bringup.tcl \
    hardware/vivado/jtag_preflight.tcl \
    hardware/vivado/jtag_boot_bringup.tcl \
    buildroot-external/configs/zynq7020_bringup_defconfig \
    buildroot-external/board/zynq7020/zynq7020-bringup.dts \
    buildroot-external/board/zynq7020/rootfs-overlay/etc/init.d/S41ethernet \
    scripts/uart_command.ps1 \
    scripts/verify_media_boot.ps1 \
    scripts/ethernet_uart_stress.sh \
    scripts/ethernet_transfer_server.py \
    scripts/allow_board_ping.ps1 \
    scripts/storage_guard.ps1 \
    scripts/write_sdcard.ps1 \
    scripts/verify_sdcard.ps1 \
    scripts/program_qspi.ps1 \
    scripts/check_boot_payload.py \
    hardware/boot/u-boot-original.sha256 \
    hardware/fsbl/fsbl_hooks.c \
    buildroot-external/board/zynq7020/boot.cmd \
    docs/BOOT_MEDIA.md \
    buildroot-external/patches/linux/0001-net-macb-keep-zynq-gmii-clock-rate-under-pl-control.patch \
    buildroot-external/patches/linux/linux.hash \
    docs/VALIDATION.md; do
    [[ -f "$required" ]] || { echo "Missing required file: $required" >&2; exit 1; }
done

if grep -Eini 'axi_dma|xfft|fft_dma|sample_sim|hp0|dma-engine' \
    hardware/vivado/create_zynq7020_bringup.tcl \
    buildroot-external/configs/zynq7020_bringup_defconfig \
    buildroot-external/board/zynq7020/linux.fragment \
    buildroot-external/board/zynq7020/zynq7020-bringup.dts; then
    echo "Removed accelerator hardware or driver reference found in active bring-up files." >&2
    exit 1
fi

while IFS= read -r -d '' script; do
    bash -n "$script"
done < <(find . -type d \( -name .git -o -name build -o -name .buildroot \) -prune -o \
    -type f -name '*.sh' -print0)

python3 -c 'import ast; from pathlib import Path; [ast.parse(p.read_text()) for p in Path("scripts").glob("*.py")]'

if command -v tclsh >/dev/null 2>&1; then
    while IFS= read -r -d '' script; do
        complete=$(printf 'set f [open {%s} r]\nset s [read $f]\nclose $f\nputs [info complete $s]\n' \
            "$script" | tclsh)
        [[ "$complete" == "1" ]] || { echo "Incomplete Tcl script: $script" >&2; exit 1; }
    done < <(find . -type d \( -name .git -o -name build -o -name .buildroot \) -prune -o \
        -type f -name '*.tcl' -print0)
fi

echo "Static project checks passed. Vivado, Buildroot, and board validation are separate steps."
