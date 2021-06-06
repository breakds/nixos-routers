{ pkgs, ... }:

pkgs.writeShellScriptBin "wan-online" ''
  target_nic=$1                      
  state_file=$2
  current_time=$(date)
  assigned_ip=$(ip a show dev ''${target_nic} | grep '\inet\s' | sed 's|inet\s\([^ ]*\)\s.*|\1|')
  if [ ''${#assigned_ip} -lt 5 ]; then
    echo "''${current_time} offline" >> ''${state_file}
  fi
''
