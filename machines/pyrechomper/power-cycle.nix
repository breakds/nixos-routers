# Power-cycle the router every ~2 weeks.
#
# This board resets itself about 2^32 ms (~49.7 days) after its last
# power-on, with no log. Warm reboots don't reset the counter behind
# it. Experiment with powering off and waking by CMOS RTC alarm;
# whether this resets the counter is still unproven. See AGENTS.md.

{ pkgs, ... }:

{
  config = {
    systemd.services.power-cycle = {
      description = "Power off and wake by RTC alarm";
      serviceConfig.Type = "oneshot";
      script = ''
        # The kernel upgrade moved CMOS from rtc0 to rtc1. ACPI TAD now
        # occupies rtc0 but cannot wake this board from power-off (S5).
        for rtc in /sys/class/rtc/rtc*; do
          if [ "$(cat "$rtc/name")" = "rtc_cmos rtc_cmos" ]; then
            # Leave time for shutdown before the alarm fires.
            ${pkgs.util-linux}/bin/rtcwake -d "/dev/''${rtc##*/}" -m no -s 120
            ${pkgs.systemd}/bin/systemctl poweroff
            exit 0
          fi
        done
        echo "CMOS RTC not found; refusing to power off" >&2
        exit 1
      '';
    };

    # The 1st and 15th are at most 17 days apart.
    systemd.timers.power-cycle = {
      wantedBy = [ "timers.target" ];
      timerConfig.OnCalendar = "*-*-01,15 04:00:00";
    };
  };
}
