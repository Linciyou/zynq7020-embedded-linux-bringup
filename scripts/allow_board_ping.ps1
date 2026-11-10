#Requires -RunAsAdministrator
param([string]$LogPath)

$ErrorActionPreference = "Stop"
if ($LogPath) { Start-Transcript -Path $LogPath -Force | Out-Null }
try {
    $address = @(Get-NetIPAddress -AddressFamily IPv4 -IPAddress '192.168.7.1')
    if ($address.Count -ne 1) { throw "Expected one direct-link adapter at 192.168.7.1" }
    $name = "ZynqDirectLink-ICMPv4-Echo"
    $rule = Get-NetFirewallRule -Name $name -ErrorAction SilentlyContinue
    if ($rule) {
        $filter = $rule | Get-NetFirewallAddressFilter
        if ($filter.LocalAddress -ne '192.168.7.1' -or $filter.RemoteAddress -ne '192.168.7.2') {
            throw "Existing rule has different addresses; it was not changed."
        }
        $rule | Enable-NetFirewallRule
    } else {
        New-NetFirewallRule -Name $name -DisplayName "Zynq direct-link ICMPv4 echo" `
            -Direction Inbound -Action Allow -Protocol ICMPv4 -IcmpType 8 `
            -LocalAddress '192.168.7.1' -RemoteAddress '192.168.7.2' `
            -InterfaceAlias $address[0].InterfaceAlias -Profile Any | Out-Null
    }
    Write-Output "BOARD_PING_FIREWALL: PASS (only 192.168.7.2 -> 192.168.7.1 echo requests)"
} finally {
    if ($LogPath) { Stop-Transcript | Out-Null }
}
