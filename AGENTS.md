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
