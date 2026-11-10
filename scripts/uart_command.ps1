param(
    [Parameter(Mandatory = $true)][string]$Command,
    [string]$Port = "COM13",
    [ValidateRange(1, 600)][int]$TimeoutSeconds = 15,
    [string]$LogPath
)

$ErrorActionPreference = "Stop"
$serial = [System.IO.Ports.SerialPort]::new($Port, 115200, 'None', 8, 'One')
$serial.WriteTimeout = 2000
$marker = "UART_DONE_" + [guid]::NewGuid().ToString("N")
$output = ""
try {
    $serial.Open()
    $serial.DiscardInBuffer()
    # Split the marker so terminal echo cannot be mistaken for completion.
    $suffix = $marker.Substring(10)
    $serial.Write($Command + "; rc=`$?; printf '\nUART_DONE_%s:%s\n' '$suffix' `"`$rc`"`r")
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $chunk = $serial.ReadExisting()
        if ($chunk) {
            [Console]::Write($chunk)
            $output += $chunk
            if ($output -match ([regex]::Escape($marker) + ':(\d+)')) {
                if ([int]$Matches[1] -ne 0) { throw "Target command failed: $($Matches[1])" }
                return
            }
        }
        Start-Sleep -Milliseconds 50
    }
    throw "UART command timed out after $TimeoutSeconds seconds; the target command may still be running."
} finally {
    if ($serial.IsOpen) { $serial.Close() }
    $serial.Dispose()
    if ($LogPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($LogPath), $output) }
}
