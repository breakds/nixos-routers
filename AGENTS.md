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
| 2026-12-06 ~23:54 PST    | It did. Keep `power-cycle.nix`.                                              |

`machines/pyrechomper/power-cycle.nix` repeats this power-cycle at 04:00 on the 1st and 15th. If power-offs reset the counter, those runs head off both crashes, so no crash by Dec 6 also means it works. Note any other power-offs or reboots here.

### 2026-11-15: scheduled shutdowns failed to wake

Both runs armed `/dev/rtc0` successfully and shut down in about 2 s:

| Date (PST) | Alarm set | Wake due | Journal ended | Next boot |
|------------|-----------|----------|---------------|-----------|
| Nov 1      | 04:00:27  | 04:02:28 | 04:00:29      | 07:13:13  |
| Nov 15     | 04:00:02  | 04:02:03 | 04:00:04      | 07:56:59  |

The October 18 test used Linux 7.0.2, where `rtc_cmos` was `rtc0`.
After the October 22 upgrade to Linux 7.3.0, `acpi-tad` registered as
`rtc0` and CMOS moved to `rtc1`. The service still used rtcwake's default
`rtc0`. ACPI TAD reports capabilities `0xB7`, which lacks both AC and DC
S5 wake bits (6 and 8 in `drivers/acpi/acpi_tad.c`). This explains why
setting the alarm succeeded without powering the router back on.

The fix selects the RTC by its sysfs name (`rtc_cmos rtc_cmos`) and
aborts if it cannot find it or arm its alarm. A supervised power-off/wake
test on the current kernel is still needed; selecting CMOS alone does
not prove S5 wake works on this kernel. Do not run that test unattended.

The extra shutdowns and recoveries also confound the original December
predictions. Record whether recovery involved removing AC power before
drawing conclusions about the 49.7-day counter.
