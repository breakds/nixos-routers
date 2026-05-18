# Tailscale Remote Access

`pyrechomper` is configured to run Tailscale and support routing features, but
the advertised routes are intentionally managed manually rather than declared in
NixOS config.

This setup has two separate purposes:

- use `pyrechomper` as a home exit node, so internet services see the home WAN IP
- route the trusted home LAN, `10.77.1.0/24`, so approved users can reach hosts
  such as `ssh 10.77.1.x`

Authorization is enforced by the Tailscale ACL/policy file. The router firewall
only provides the network path.

## Router Setup

Run this on `pyrechomper`:

```bash
sudo tailscale set \
  --advertise-exit-node \
  --advertise-routes=10.77.1.0/24
```

Then approve both advertisements in the Tailscale admin console:

- the exit node capability for `pyrechomper`
- the subnet route `10.77.1.0/24`

Because this is manual Tailscale state, re-run the command if `pyrechomper` is
reset, re-authenticated, or otherwise loses its Tailscale preferences.

## Laptop Client Setup

On a Linux laptop, accept subnet routes:

```bash
sudo tailscale set --accept-routes=true
```

To use the home exit node:

```bash
sudo tailscale set --exit-node=pyrechomper
```

To stop using the exit node:

```bash
sudo tailscale set --exit-node=
```

On macOS or Windows, the same settings can also be selected from the Tailscale
UI: enable subnet routes and choose `pyrechomper` as the exit node.

## Verification

Check LAN subnet access:

```bash
ssh 10.77.1.x
```

Check exit-node egress:

```bash
curl https://ifconfig.me
```

The reported IP should be the home WAN IP.

If the laptop needs to keep access to the network it is physically connected to
while using `pyrechomper` as an exit node, enable local LAN access:

```bash
sudo tailscale set --exit-node-allow-lan-access=true
```
