# Power-cycle the router every ~2 weeks.
#
# This board resets itself about 2^32 ms (~49.7 days) after its last
# power-on, with no log, and needs a manual power-off afterwards.
# Warm reboots don't reset the counter behind it, so instead we power
# off and let the RTC alarm power the router back on, well before 49.7
# days. See AGENTS.md for the evidence and the experiment that checks
# this works.

{ config, lib, pkgs, ... }:

{
  config = {
    systemd.services.power-cycle = {
      description = "Power off and wake by RTC alarm";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = [
          # 120s leaves room for a slow shutdown. If the alarm fires
          # before the power is off, the router stays off.
          "${pkgs.util-linux}/bin/rtcwake -m no -s 120"
          "${pkgs.systemd}/bin/systemctl poweroff"
        ];
      };
    };

    # The 1st and 15th are at most 17 days apart.
    systemd.timers.power-cycle = {
      wantedBy = [ "timers.target" ];
      timerConfig.OnCalendar = "*-*-01,15 04:00:00";
    };
  };
}
