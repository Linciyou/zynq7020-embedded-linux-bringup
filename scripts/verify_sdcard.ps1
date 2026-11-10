#Requires -RunAsAdministrator
param(
    [Parameter(Mandatory = $true)][int]$DiskNumber,
    [string]$ImagePath,
    [string]$ExpectedSerialNumber,
    [uint64]$ExpectedSizeBytes
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot 'storage_guard.ps1')
if (!$ImagePath) { $ImagePath = Join-Path $PSScriptRoot '..\build\linux_images\sdcard.img' }
$image = Get-Item -LiteralPath $ImagePath
$disk = Get-ConfirmedUsbDisk $DiskNumber $ExpectedSerialNumber $ExpectedSizeBytes
if ($image.Length -lt 512 -or $image.Length % 512 -ne 0 -or $disk.Size -lt $image.Length) {
    throw 'Invalid image length for this disk'
}
Start-Transcript -LiteralPath (Join-Path $PSScriptRoot '..\build\sd_verify.log') -Force | Out-Null
$source = $null
$target = $null
try {
    $source = [IO.File]::OpenRead($image.FullName)
    $target = [ZynqDiskIO]::OpenDisk("\\.\PhysicalDrive$DiskNumber", $false)
    $sourceBuffer = New-Object byte[] 4194304
    $targetBuffer = New-Object byte[] 4194304
    $offset = 0L
    while (($count = $source.Read($sourceBuffer, 0, $sourceBuffer.Length)) -gt 0) {
        [ZynqDiskIO]::ReadExact($target, $targetBuffer, $count)
        if (![ZynqDiskIO]::Equal($sourceBuffer, $targetBuffer, $count)) {
            throw "Verification failed in block at byte $offset"
        }
        $offset += $count
    }
    Write-Output "Verified $offset bytes on Disk $DiskNumber."
} finally {
    if ($target) { $target.Dispose() }
    if ($source) { $source.Dispose() }
    Stop-Transcript | Out-Null
}
