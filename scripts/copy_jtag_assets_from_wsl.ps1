param(
    [string]$Distro = "Ubuntu-22.04-Buildroot",
    [string]$WslRepo = "/home/builder/work/zynq7020-bringup-jtag"
)

$ErrorActionPreference = "Stop"
$wslImages = "$WslRepo/build/buildroot-zynq7020/images"
$windowsImages = (& wsl.exe -d $Distro --exec wslpath -w $wslImages).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($windowsImages)) {
    throw "Could not resolve the WSL Buildroot image directory. Check the distro and WslRepo parameters."
}

$destination = Join-Path $PSScriptRoot "..\build\linux_images"
$required = @("zImage", "rootfs.cpio.gz", "zynq7020-bringup.dtb", "System.map", "sdcard.img")
foreach ($name in $required) {
    $source = Join-Path $windowsImages $name
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Missing JTAG image: $source. Run make_jtag_assets.sh after Buildroot completes."
    }
}

New-Item -ItemType Directory -Path $destination -Force | Out-Null
foreach ($name in $required) {
    Copy-Item -LiteralPath (Join-Path $windowsImages $name) -Destination $destination -Force
}
Write-Output "Copied JTAG assets to $(Resolve-Path $destination)."
