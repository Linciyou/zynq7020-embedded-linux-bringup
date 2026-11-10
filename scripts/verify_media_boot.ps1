param(
    [string]$Port = 'COM13',
    [string]$LogPath = 'build/media-boot.log',
    [switch]$Reboot,
    [ValidateRange(30, 600)][int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$serial = [IO.Ports.SerialPort]::new($Port, 115200, 'None', 8, 'One')
$serial.WriteTimeout = 2000
$output = ''
$stage = 0
$sendAt = [DateTime]::MaxValue
try {
    $serial.Open()
    if ($Reboot) { $serial.Write("reboot`r") }
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $chunk = $serial.ReadExisting()
        if ($chunk) {
            [Console]::Write($chunk)
            $output += $chunk
        }
        # Do not send anything during U-Boot's countdown.
        if ($stage -eq 0 -and $output.Contains('buildroot login:')) {
            $serial.Write("root`r")
            $sendAt = [DateTime]::UtcNow.AddSeconds(3)
            $stage = 1
        }
        if ($stage -eq 1 -and [DateTime]::UtcNow -ge $sendAt) {
            $serial.Write("id; bash --version | head -n 1; cat /sys/class/net/eth0/speed; ping -c 3 -W 2 192.168.7.1; printf '\nMEDIA_%s\n' PROBE_DONE`r")
            $stage = 2
        }
        if ($stage -eq 2 -and $output.Contains("MEDIA_PROBE_DONE")) {
            if (!$output.Contains('SD_BOOT_512M') -or !$output.Contains('uid=0(root)') -or
                !$output.Contains('3 packets received')) {
                throw 'Capture finished but media boot, shell or gateway ping did not meet acceptance.'
            }
            Write-Host "`nMEDIA_BOOT_PASS (cold boot only if power was physically cycled during capture)"
            return
        }
        Start-Sleep -Milliseconds 50
    }
    throw 'Boot capture timed out; inspect the log before intervening.'
} finally {
    if ($serial.IsOpen) { $serial.Close() }
    $serial.Dispose()
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($LogPath), $output)
}
