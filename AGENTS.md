# Agent Notes

## Known issue: pyrechomper resets every ~49.7 days

pyrechomper (Celeron N5105, board JK4LV105) resets itself at about 2^32 ms (4,294,967 s) of uptime. There is no log, no panic, and no shutdown. It boots back up on its own within 0.5–2 min.

| Ended      | Uptime at last log         | Kernel        |
|------------|----------------------------|---------------|
| 2025-11-19 | 4,294,015 s                | 6.10.7-xanmod |
| 2026-03-27 | 8,589,461 s (2 × 2^32 ms)  | 6.10.7-xanmod |
| 2026-07-05 | 4,261,826 s (counted from the previous cold boot, ≈ 2^32 ms) | 7.0.2 |
| 2026-08-23 | 4,294,987 s                | 7.0.2         |
| 2026-10-12 | 4,294,719 s                | 7.0.2         |

It happens on both kernels and on both sides of the 25.11 upgrade, so the cause is likely firmware or hardware (BIOS/EC, NVMe, or NIC), not this config.

When the router reboots unexpectedly, check the uptime of the previous boot first:

```sh
journalctl -b -1 -n 1 -o short-monotonic
```

A value near a multiple of 4294967 means this issue.

### The counter survives reboots

The crash comes 0–60 s after 2^32 ms counted from the last real power-on, not from the last boot. Warm reboots and clean power-offs (boot -3 on 2026-08-23) did not reset it. So the counter likely lives in standby-powered firmware (EC or Intel ME). A scheduled `systemctl reboot` won't help.

### Experiment: does a power-off with RTC wake reset it?

On 2026-10-18 07:50 PDT the router was powered off and woken by the RTC:

```sh
sudo rtcwake -m no -s 20 && sudo systemctl poweroff
```

(`rtcwake -m off` calls `/sbin/shutdown`, which NixOS lacks.) Power-off took 2 s, and the router came back without help.

| Next crash at            | Means                                                                       |
|--------------------------|-----------------------------------------------------------------------------|
| 2026-12-01 ~07:41 PST    | The power-off didn't reset the counter. Cut AC power with a smart plug.     |
| 2026-12-06 ~23:54 PST    | It did. Power-cycle with `rtcwake` from a timer on the 1st and 15th.        |

Avoid other power-offs and reboots until then, or note them here.
