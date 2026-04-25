#!/bin/sh

LOGFILE="/etc/config/maxmai-firstboot.log"
touch "$LOGFILE"
echo "Starting maxmai firstboot at $(date)" >>"$LOGFILE"

if ip link show eth0 >/dev/null 2>&1; then
  echo "eth0 detected" >>"$LOGFILE"
else
  echo "WARNING: eth0 not detected" >>"$LOGFILE"
fi

if ip link show eth1 >/dev/null 2>&1; then
  echo "eth1 detected" >>"$LOGFILE"
else
  echo "WARNING: eth1 not detected" >>"$LOGFILE"
fi

if ! uci show dhcp | grep -q "time.android.com"; then
  uci add dhcp domain
  uci set "dhcp.@domain[-1].name=time.android.com"
  uci set "dhcp.@domain[-1].ip=203.107.6.88"
fi

if uci show firewall | grep -q "zone.*wan"; then
  uci -q set firewall.@zone[1].input='REJECT'
fi

if uci -q get ttyd.@ttyd[0] >/dev/null 2>&1; then
  uci -q delete ttyd.@ttyd[0].interface
  uci commit ttyd
fi

FILE_PATH="/etc/openwrt_release"
if [ -f "$FILE_PATH" ]; then
  sed -i "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='MaxMai N100 dedicated build'/" "$FILE_PATH"
fi

uci commit dhcp
uci commit firewall

echo "Finished maxmai firstboot at $(date)" >>"$LOGFILE"
exit 0
