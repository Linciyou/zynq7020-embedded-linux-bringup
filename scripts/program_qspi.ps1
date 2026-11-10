[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
param(
    [Parameter(Mandatory = $true)][switch]$ConfirmErase,
    [string]$BackupPath = "$PSScriptRoot\..\build\flash-backup\qspi-boot-before.bin",
    [ValidatePattern('^/[A-Za-z0-9_./-]+$')][string]$HttpPath = '/BOOT_QSPI.bin'
)
$ErrorActionPreference = "Stop"
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (!$ConfirmErase) { throw 'Explicit -ConfirmErase is required' }
& python (Join-Path $PSScriptRoot 'check_boot_payload.py')
if ($LASTEXITCODE -ne 0) { throw 'Flash payload validation failed' }
$backup = Get-Item -LiteralPath $BackupPath
if ($backup.Length -ne 6291456) { throw 'A complete 6 MiB boot-partition backup is required' }
$image = Get-Item (Join-Path $root 'build\flash_images\BOOT_QSPI.bin')
$sha = (Get-FileHash $image.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
$backupSha = (Get-FileHash $backup.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
if (!$PSCmdlet.ShouldProcess('Zynq /dev/mtd0, qspi-boot, 6 MiB', 'Erase, program and verify boot image')) { return }
$command = @'
bash -c 'set -euo pipefail; test "$(cat /sys/class/mtd/mtd0/name)" = qspi-boot; test "$(cat /sys/class/mtd/mtd0/size)" -eq 6291456; old=$(head -c 6291456 /dev/mtd0 | sha256sum); test "${old%% *}" = "%BACKUP%"; wget -T 20 -O /tmp/BOOT_QSPI.bin http://192.168.7.1:8080/BOOT_QSPI.bin; echo "%SHA%  /tmp/BOOT_QSPI.bin" | sha256sum -c -; test "$(wc -c < /tmp/BOOT_QSPI.bin)" -eq %BYTES%; busybox flashcp -v /tmp/BOOT_QSPI.bin /dev/mtd0; actual=$(head -c %BYTES% /dev/mtd0 | sha256sum); test "${actual%% *}" = "%SHA%"; echo QSPI_WRITE_VERIFY_PASS'
'@
$command = $command.Replace('http://192.168.7.1:8080/BOOT_QSPI.bin', 'http://192.168.7.1:8080' + $HttpPath)
$command = $command.Replace('%BACKUP%', $backupSha).Replace('%SHA%', $sha).Replace('%BYTES%', [string]$image.Length)
& (Join-Path $PSScriptRoot 'uart_command.ps1') -Command $command -TimeoutSeconds 300 `
    -LogPath (Join-Path $root 'build\qspi-program-uart.log')
