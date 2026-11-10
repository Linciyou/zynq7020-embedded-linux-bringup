param(
    [string]$XsaPath = (Join-Path $PSScriptRoot "..\build\vivado\zynq7020_bringup\zynq7020_bringup.xsa"),
    [string]$OutputPath = (Join-Path $PSScriptRoot "..\build\jtag_hw\ps7_init.tcl")
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem

$xsa = (Resolve-Path -LiteralPath $XsaPath).Path
$destination = [System.IO.Path]::GetFullPath($OutputPath)
$destinationDirectory = [System.IO.Path]::GetDirectoryName($destination)
New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null

$archive = [System.IO.Compression.ZipFile]::OpenRead($xsa)
try {
    $entry = $archive.GetEntry("ps7_init.tcl")
    if ($null -eq $entry) {
        throw "XSA does not contain the Vivado-generated ps7_init.tcl: $xsa"
    }

    $inputStream = $entry.Open()
    $outputStream = [System.IO.File]::Create($destination)
    try {
        $inputStream.CopyTo($outputStream)
    }
    finally {
        $outputStream.Dispose()
        $inputStream.Dispose()
    }
}
finally {
    $archive.Dispose()
}

Write-Output "Extracted Vivado-generated PS initialization: $destination"
