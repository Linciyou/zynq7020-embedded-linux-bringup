"""Verify that a bootgen image contains the preserved U-Boot binary unchanged."""
import hashlib
import json
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
image = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "build/flash_images/BOOT_QSPI.bin"
uboot = root / "build/linux_images/u-boot.bin"
expected = (root / "hardware/boot/u-boot-original.sha256").read_text().split()[0]
original = uboot.read_bytes()
if hashlib.sha256(original).hexdigest() != expected:
    raise SystemExit("U-Boot differs from the preserved binary; refusing this deployment")
data = image.read_bytes()
offset = data.find(original)
if not 0 < len(data) <= 6 * 1024 * 1024 or offset < 0:
    raise SystemExit("Invalid boot image size or preserved U-Boot payload not found")
print(json.dumps({"image": str(image), "bytes": len(data),
                  "sha256": hashlib.sha256(data).hexdigest(),
                  "uboot_sha256": expected, "uboot_offset": offset}))
