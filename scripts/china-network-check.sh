#!/usr/bin/env bash
set -euo pipefail

# Endpoint naming follows xykt/NetQuality's province/provider list. These
# third-party endpoints are samples, not verified residential connections.
# No code or endpoint lists are downloaded at runtime.
if [[ $# -gt 1 || ${1:-} == -* ]]; then
  echo "Usage: bash $0 [new-report-directory]" >&2
  exit 2
fi
if ((BASH_VERSINFO[0] < 5)); then
  echo 'Bash 5 or later is required for connection timing.' >&2
  exit 1
fi
for tool in bash awk timeout getent ip traceroute date hostname mkdir tee sleep dirname; do
  command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 1; }
done
report=${1:-"/tmp/china-network-$(date -u +%Y%m%dT%H%M%SZ)"}
mkdir -- "$report" # Refuse to overwrite an existing report.
exec > >(tee "$report/report.txt") 2>&1
printf 'China network baseline — %s\nHost: %s\n' "$(date -u --iso-8601=seconds)" "$(hostname)"
echo 'IPv4 TCP connection timing; 5 attempts, 4-second timeout. Ports are in samples.tsv.'
echo 'Times include local process overhead. Failures are connection failures, not packet loss.'
echo 'Traceroutes use UDP; TCP routes may differ. Missing hops do not prove loss.'
echo 'No uploads, speed tests, external IP lookup, or automatic installation.'
echo 'Endpoints see your public IP. Reports contain local addresses and route hops.'
echo
ip -4 route get 1.1.1.1 || true
echo
printf 'region\tcarrier\thost\tip\tattempt\tconnect_ms\tport\n' > "$report/samples.tsv"
printf '%-12s %-10s %-16s %7s %10s\n' REGION CARRIER IP SUCCESS AVG_MS

while read -r region carrier host port; do
    [[ -z $region || $region == \#* ]] && continue
    address=$(timeout 8 getent ahostsv4 "$host" | awk 'NR == 1 {print $1}' || true)
    if [[ ! $address =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      printf '%-12s %-10s %s\n' "$region" "$carrier" 'DNS lookup failed'
      printf '%s\t%s\t%s\t-\t0\tDNS_FAILED\t%s\n' "$region" "$carrier" "$host" "$port" >> "$report/samples.tsv"
      continue
    fi
    for attempt in 1 2 3 4 5; do
      # A TCP handshake only: no HTTP request or payload. Timeout closes it.
      elapsed=$(timeout 4 bash -c '
        start=$EPOCHREALTIME
        exec 3<>"/dev/tcp/$1/$2" || exit 1
        end=$EPOCHREALTIME
        awk -v start="$start" -v end="$end" "BEGIN {printf \"%.2f\", (end-start)*1000}"
      ' bash "$address" "$port" 2>/dev/null) || elapsed=FAILED
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$region" "$carrier" "$host" "$address" "$attempt" "$elapsed" "$port" >> "$report/samples.tsv"
      sleep 0.2
    done
    awk -F '\t' -v region="$region" -v carrier="$carrier" -v address="$address" '
      $1 == region && $2 == carrier && $6 ~ /^[0-9]+[.][0-9]+$/ {sum += $6; n++}
      END {printf "%-12s %-10s %-16s %5d/5 %10s\n", region, carrier, address, n, n ? sprintf("%.2f",sum/n) : "-"}
    ' "$report/samples.tsv"
    # One probe per hop, bounded even if the destination filters probes.
    (
      if timeout 40 traceroute -m 30 -q 1 -w 1 "$address" > "$report/$region-$carrier-route.txt" 2>&1; then
        :
      else
        echo 'Trace incomplete or unavailable; see output above.' >> "$report/$region-$carrier-route.txt"
      fi
    ) &
done < "$(dirname -- "${BASH_SOURCE[0]}")/china-network-targets.tsv"
wait
printf '\nReports: %s\n' "$report"
