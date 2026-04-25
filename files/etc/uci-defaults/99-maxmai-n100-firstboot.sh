#!/bin/sh

LOGFILE="/etc/config/maxmai-firstboot.log"
touch "$LOGFILE"
echo "Starting maxmai firstboot at $(date)" >>"$LOGFILE"
echo "--- link summary before tweaks ---" >>"$LOGFILE"
ip -br link >>"$LOGFILE" 2>&1 || true
ip -br addr >>"$LOGFILE" 2>&1 || true

if ip link show eth0 >/dev/null 2>&1; then
  echo "eth0 detected" >>"$LOGFILE"
  ip -d link show eth0 >>"$LOGFILE" 2>&1 || true
else
  echo "WARNING: eth0 not detected" >>"$LOGFILE"
fi

if ip link show eth1 >/dev/null 2>&1; then
  echo "eth1 detected" >>"$LOGFILE"
  ip -d link show eth1 >>"$LOGFILE" 2>&1 || true
else
  echo "WARNING: eth1 not detected" >>"$LOGFILE"
fi

if ip link show br-lan >/dev/null 2>&1; then
  echo "br-lan detected" >>"$LOGFILE"
  ip -d link show br-lan >>"$LOGFILE" 2>&1 || true
  bridge link >>"$LOGFILE" 2>&1 || true
else
  echo "WARNING: br-lan not detected" >>"$LOGFILE"
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

echo "--- UCI network/dhcp quick dump ---" >>"$LOGFILE"
uci show network.lan >>"$LOGFILE" 2>&1 || true
uci show network.br_lan >>"$LOGFILE" 2>&1 || true
uci show network.WAN >>"$LOGFILE" 2>&1 || true
uci show dhcp.@dnsmasq[0] >>"$LOGFILE" 2>&1 || true

echo "--- service status ---" >>"$LOGFILE"
/etc/init.d/dnsmasq enabled >>"$LOGFILE" 2>&1 || true
/etc/init.d/dnsmasq status >>"$LOGFILE" 2>&1 || true
/etc/init.d/odhcpd enabled >>"$LOGFILE" 2>&1 || true
/etc/init.d/odhcpd status >>"$LOGFILE" 2>&1 || true
/etc/init.d/network enabled >>"$LOGFILE" 2>&1 || true

echo "Finished maxmai firstboot at $(date)" >>"$LOGFILE"
exit 0
