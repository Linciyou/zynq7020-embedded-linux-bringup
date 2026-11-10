#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
param(
    [Parameter(Mandatory = $true)][int]$DiskNumber,
    [string]$ImagePath,
    [Parameter(Mandatory = $true)][switch]$ConfirmErase,
    [string]$ExpectedSerialNumber,
    [uint64]$ExpectedSizeBytes
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot 'storage_guard.ps1')
if (!$ConfirmErase) { throw "Pass -ConfirmErase only for the reviewed target SD card" }
if (!$ImagePath) { $ImagePath = Join-Path $PSScriptRoot '..\build\linux_images\sdcard.img' }
$image = Get-Item -LiteralPath $ImagePath
$disk = Get-ConfirmedUsbDisk $DiskNumber $ExpectedSerialNumber $ExpectedSizeBytes
if ($disk.IsOffline -or $disk.IsReadOnly) { throw 'Target disk is offline or read-only' }
if ($image.Length -lt 512 -or $disk.Size -lt $image.Length -or $image.Length % 512 -ne 0) { throw 'Image size is invalid for this disk' }
if (!$PSCmdlet.ShouldProcess("\\.\PhysicalDrive$DiskNumber", "Erase SD layout and write $($image.FullName)")) { return }

Start-Transcript -LiteralPath (Join-Path $PSScriptRoot '..\build\sd_write.log') -Force | Out-Null
$locks = [Collections.Generic.List[IO.FileStream]]::new()
$source = $null
$target = $null
try {
    # Removable SD media cannot be set offline. Lock every mounted target volume
    # before dismounting; never force-dismount a volume whose lock failed.
    $volumes = @(Get-Partition -DiskNumber $DiskNumber | Get-Volume -ErrorAction SilentlyContinue)
    foreach ($volume in $volumes) {
        if (!$volume.Path) { continue }
        $handle = [IO.File]::Open($volume.Path.TrimEnd('\'), 'Open', 'ReadWrite', 'ReadWrite')
        $locks.Add($handle)
        [ZynqDiskIO]::Control($handle, 0x00090018)
        [ZynqDiskIO]::Control($handle, 0x00090020)
    }
    $null = Get-ConfirmedUsbDisk $DiskNumber $disk.SerialNumber $disk.Size
    Write-Output "Target: Disk $DiskNumber, serial=$($disk.SerialNumber.Trim()), bytes=$($disk.Size)"
    Write-Output "Image SHA256: $((Get-FileHash -LiteralPath $image.FullName -Algorithm SHA256).Hash)"
    $source = [IO.File]::OpenRead($image.FullName)
    $target = [ZynqDiskIO]::OpenDisk("\\.\PhysicalDrive$DiskNumber", $true)
    $buffer = New-Object byte[] 65536
    $offset = 0L
    # Keep the MBR write separate from partition data and every transfer sector-aligned.
    $count = $source.Read($buffer, 0, 512)
    if ($count -ne 512) { throw 'Short MBR read' }
    [ZynqDiskIO]::Write($target, $buffer, $count)
    $offset += $count
    while (($count = $source.Read($buffer, 0, $buffer.Length)) -gt 0) {
        if ($count % 512 -ne 0) { throw "Unaligned source read at $offset" }
        try { [ZynqDiskIO]::Write($target, $buffer, $count) } catch {
            throw "SD write failed at offset $offset, count $count : $($_.Exception.InnerException.Message)"
        }
        $offset += $count
    }
    [ZynqDiskIO]::Flush($target)
    Write-Output "Wrote $($image.Length) bytes to Disk $DiskNumber; run verify_sdcard.ps1 before accepting."
} finally {
    if ($target) { $target.Dispose() }
    if ($source) { $source.Dispose() }
    foreach ($handle in $locks) { $handle.Dispose() }
    Stop-Transcript | Out-Null
}
Update-Disk -Number $DiskNumber -ErrorAction Stop
