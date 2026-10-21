# China network baseline

Run from a home LAN machine, without a VPN exit node:

```sh
bash scripts/china-network-check.sh
```

Uses existing Bash 5+, GNU coreutils, awk, getent, iproute2, and traceroute.
It installs nothing and needs no root privileges. The current home workstation
already supplies these tools through NixOS. No flake dependencies are added.

The script tests five IPv4 TCP handshakes per endpoint, using the ports in
`scripts/china-network-targets.tsv`. Province samples cover Jiangsu (`js`),
Zhejiang (`zj`), Shanghai, Beijing, and Guangdong. Province endpoints are not
assumed to be in the provincial capital.

Additional city-labelled samples cover Hangzhou Telecom and Mobile, Nanjing
Telecom, and Nanjing University's public test service (`nju`). The university
sample is separate from commercial carrier samples; it does not establish
which upstream network a particular connection uses.
Hangzhou entries come from NetQuality's speedtest server list; the Nanjing
Telecom hostname identifies a city-specific speedtest endpoint, but its current
physical location is not independently verified.
[NJU documents its public endpoint here](https://doc.nju.edu.cn/books/07cdf).
These tests only connect to their ports; they do not run a speed test.
`ct`, `cu`, and `cm` mean China Telecom, China Unicom, and China Mobile.
The naming scheme comes from [NetQuality](https://github.com/xykt/NetQuality),
but this is an independent implementation, not a copy of its shell code.
DNS answers and endpoint ownership can change; labels are not verified.

Each target also gets a bounded UDP traceroute. A run can take several minutes.
Results stay in a new directory under `/tmp`, or a new directory supplied as
the first argument. `samples.tsv` contains all attempts and resolved addresses;
`report.txt` summarizes successful handshakes; separate files contain traces.
The script does not download code, upload reports, or run throughput tests.
DNS resolvers and probe destinations receive requests. Destinations see your
public IP; local reports contain your local IP and route hops.

Connection failures are not a packet-loss measurement. Filtering, refused
connections, and timeouts all count as failures. Averages exclude failures.
TCP timings include local overhead; UDP traces may take different paths.
Missing intermediate hops often reflect filtered diagnostic traffic.

These are outbound paths from California with round-trip timing, not traces
from China. They cannot establish performance at a particular residential
connection, classify CN2 GIA reliably, or predict a prospective VPS's route.
Repeat from the same machine and at China evening peak hours for comparison.
