#!/bin/bash
# Run from the board's UART shell against ethernet_transfer_server.py.
set -euo pipefail
host=${1:-192.168.7.1}
port=${2:-8080}
rounds=${3:-100}
[[ "$rounds" =~ ^[0-9]+$ ]] && ((rounds >= 1 && rounds <= 1000))
base="http://$host:$port"
tmpdir=$(mktemp -d /tmp/ethernet-probe.XXXXXX)
trap 'rm -f "$tmpdir/payload.bin" "$tmpdir/response"; rmdir "$tmpdir"' EXIT
expected=$(wget -q -T 20 -O - "$base/sha256")
[[ "$expected" =~ ^[a-f0-9]{64}$ ]]
carrier_before=$(cat /sys/class/net/eth0/carrier_changes)
rx_before=$(cat /sys/class/net/eth0/statistics/rx_errors)
tx_before=$(cat /sys/class/net/eth0/statistics/tx_errors)
started=$SECONDS
for ((i=1; i<=rounds; i++)); do
    wget -q -T 20 -O "$tmpdir/payload.bin" "$base/payload.bin"
    actual=$(sha256sum "$tmpdir/payload.bin")
    [[ "${actual%% *}" == "$expected" ]]
    # Send binary bytes, including NULs, without wget's POST string conversion.
    exec 3<>"/dev/tcp/$host/$port"
    printf 'POST /upload HTTP/1.0\r\nHost: %s\r\nContent-Length: 1048576\r\n\r\n' "$host" >&3
    cat "$tmpdir/payload.bin" >&3
    : > "$tmpdir/response"
    while IFS= read -r -t 20 line <&3; do
        printf '%s\n' "$line" >> "$tmpdir/response"
    done
    exec 3>&-
    grep -q "UPLOAD_OK $expected" "$tmpdir/response"
    if (( i % 10 == 0 || i == rounds )); then
        echo "ETH_TRANSFER_ROUND: $i/$rounds PASS (1 MiB each direction, SHA-256 $expected)"
    fi
done
carrier_after=$(cat /sys/class/net/eth0/carrier_changes)
rx_after=$(cat /sys/class/net/eth0/statistics/rx_errors)
tx_after=$(cat /sys/class/net/eth0/statistics/tx_errors)
echo "ETH_COUNTERS: carrier=$carrier_before->$carrier_after rx_errors=$rx_before->$rx_after tx_errors=$tx_before->$tx_after"
[[ "$carrier_before" == "$carrier_after" && "$rx_before" == "$rx_after" && "$tx_before" == "$tx_after" ]]
[[ $(cat /sys/class/net/eth0/carrier) == 1 ]]
speed=$(cat /sys/class/net/eth0/speed)
echo "ETH_STRESS: PASS rounds=$rounds bytes_each_direction=$((rounds * 1048576)) elapsed_seconds=$((SECONDS - started)) speed_mbps=$speed"
