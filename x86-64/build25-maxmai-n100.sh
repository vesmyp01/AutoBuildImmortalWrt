#!/bin/bash
set -euo pipefail

if [ -d "/home/build/immortalwrt" ]; then
  BASE_DIR="${BASE_DIR:-/home/build/immortalwrt}"
else
  BASE_DIR="${BASE_DIR:-$(pwd)}"
fi

cd "$BASE_DIR"

if [ -f "$BASE_DIR/repositories.conf" ] && [ -f "$BASE_DIR/shell/switch_repository.sh" ]; then
  source "$BASE_DIR/shell/switch_repository.sh"
else
  echo "repositories.conf not present in this 25.12 imagebuilder; keeping default repositories"
fi

FILES_DIR="${FILES_DIR:-$BASE_DIR/files}"
OVERLAY_DIR="${OVERLAY_DIR:-$BASE_DIR/overlay-private}"
ROOTFS_PARTSIZE="${ROOTFS_PARTSIZE:-4096}"
LOGFILE="${LOGFILE:-/tmp/maxmai-n100-build25.log}"

REQUIRED_FILES=(
  "files/etc/config/network"
  "files/etc/config/firewall"
  "files/etc/config/dhcp"
  "files/etc/config/wireless"
  "files/etc/config/dropbear"
  "files/etc/config/system"
  "files/etc/config/socat"
  "files/etc/config/ddns"
  "files/etc/config/ddns-go"
  "files/etc/config/lucky"
  "files/etc/config/shadowsocksr"
  "files/etc/config/luci"
  "files/etc/crontabs/root"
  "files/etc/dropbear/authorized_keys"
  "files/etc/passwd"
  "files/etc/shadow"
  "files/etc/group"
  "files/etc/init.d/maxmai-ssr-bridge"
  "files/usr/bin/maxmai-ssr-bridge-rules"
)

OPTIONAL_PATHS=(
  "files/etc/config/tailscale"
  "files/etc/firewall.user"
  "files/etc/hosts"
  "files/etc/rc.local"
  "files/etc/sysctl.conf"
  "files/etc/ddns-go/ddns-go-config.yaml"
  "files/etc/config/lucky.daji"
  "files/etc/config/argon"
  "files/etc/config/uhttpd"
  "files/etc/dropbear/dropbear_ed25519_host_key"
  "files/etc/dropbear/dropbear_rsa_host_key"
)

echo "Starting MaxMai N100 USB-2 25.12 build at $(date)" | tee -a "$LOGFILE"
echo "Base directory: $BASE_DIR" | tee -a "$LOGFILE"
echo "Overlay directory: $OVERLAY_DIR" | tee -a "$LOGFILE"
echo "Rootfs partsize: ${ROOTFS_PARTSIZE} MB" | tee -a "$LOGFILE"

if [ ! -d "$OVERLAY_DIR" ]; then
  echo "Overlay directory not found: $OVERLAY_DIR" >&2
  exit 1
fi

for rel in "${REQUIRED_FILES[@]}"; do
  if [ ! -e "$OVERLAY_DIR/$rel" ]; then
    echo "Missing required overlay path: $rel" >&2
    exit 1
  fi
done

grep -q "option mediaurlbase '/luci-static/argon'" "$OVERLAY_DIR/files/etc/config/luci"
grep -q "option Argon '/luci-static/argon'" "$OVERLAY_DIR/files/etc/config/luci"
grep -q "option Aurora '/luci-static/aurora'" "$OVERLAY_DIR/files/etc/config/luci"
grep -q "config device 'br_lan'" "$OVERLAY_DIR/files/etc/config/network"
grep -q "option name 'br-lan'" "$OVERLAY_DIR/files/etc/config/network"
grep -q "list ports 'eth0'" "$OVERLAY_DIR/files/etc/config/network"
grep -q "option macaddr 'e4:3a:6e:84:35:2d'" "$OVERLAY_DIR/files/etc/config/network"
grep -q "option device 'br-lan'" "$OVERLAY_DIR/files/etc/config/network"
grep -q "option device 'eth1'" "$OVERLAY_DIR/files/etc/config/network"
grep -q "config interface 'tailscale'" "$OVERLAY_DIR/files/etc/config/network"
grep -q "tailscale" "$OVERLAY_DIR/files/etc/config/firewall"
grep -q "list Interface 'tailscale'" "$OVERLAY_DIR/files/etc/config/shadowsocksr"
grep -q "100.64.0.0/10" "$OVERLAY_DIR/files/etc/config/shadowsocksr"
grep -q "maxmai-ssr-bridge-rules" "$OVERLAY_DIR/files/etc/firewall.user"
grep -q "option disabled '1'" "$OVERLAY_DIR/files/etc/config/wireless"
if grep -q "/luci-static/ifit" "$OVERLAY_DIR/files/etc/config/luci"; then
  echo "Overlay LuCI config still references missing ifit theme." >&2
  exit 1
fi

rm -f "$FILES_DIR/etc/uci-defaults/99-custom.sh"
mkdir -p "$FILES_DIR"
cp -a "$OVERLAY_DIR/files/." "$FILES_DIR/"

chmod 600 "$FILES_DIR/etc/shadow"
chmod 600 "$FILES_DIR/etc/dropbear/dropbear_"*"_host_key" 2>/dev/null || true
chmod +x "$FILES_DIR/etc/init.d/maxmai-ssr-bridge"
chmod +x "$FILES_DIR/usr/bin/maxmai-ssr-bridge-rules"

for rel in "${OPTIONAL_PATHS[@]}"; do
  if [ -e "$OVERLAY_DIR/$rel" ]; then
    echo "Optional overlay path present: $rel" | tee -a "$LOGFILE"
  fi
done

download_with_fallback() {
  local url="$1"
  local output="$2"
  local encoded
  encoded="${url#https://}"

  if curl -fL --retry 3 --retry-delay 3 "$url" -o "$output"; then
    return 0
  fi

  echo "Primary download failed, trying gh-proxy for: $url" | tee -a "$LOGFILE"
  curl -fL --retry 3 --retry-delay 3 "https://gh-proxy.com/https://${encoded}" -o "$output"
}

clone_with_fallback() {
  local url="$1"
  local dest="$2"
  local encoded
  encoded="${url#https://}"

  if git clone --depth=1 "$url" "$dest"; then
    return 0
  fi

  echo "Primary clone failed, trying gh-proxy for: $url" | tee -a "$LOGFILE"
  git clone --depth=1 "https://gh-proxy.com/https://${encoded}" "$dest"
}

MAXMAI_APK_PACKAGES="
luci-theme-aurora
luci-app-aurora-config
luci-i18n-aurora-config-zh-cn
luci-app-partexp
luci-i18n-partexp-zh-cn
bandix
luci-app-bandix
luci-i18n-bandix-zh-cn
nikki
luci-app-nikki
luci-i18n-nikki-zh-cn
"

echo "Syncing third-party APK package store..." | tee -a "$LOGFILE"
rm -rf /tmp/store-apk-repo "$BASE_DIR/extra-packages" "$BASE_DIR/packages"
clone_with_fallback "https://github.com/wukongdaily/apk.git" /tmp/store-apk-repo
mkdir -p "$BASE_DIR/extra-packages"
cp -r /tmp/store-apk-repo/run/x86/* "$BASE_DIR/extra-packages/"
sh "$BASE_DIR/shell/apk-prepare-packages.sh"

echo "Preparing OpenClash core and rule data..." | tee -a "$LOGFILE"
mkdir -p "$FILES_DIR/etc/openclash/core" "$FILES_DIR/etc/openclash"
download_with_fallback \
  "https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-amd64-v1.tar.gz" \
  "$BASE_DIR/clash-linux-amd64-v1.tar.gz"
tar xOzf "$BASE_DIR/clash-linux-amd64-v1.tar.gz" > "$FILES_DIR/etc/openclash/core/clash_meta"
chmod +x "$FILES_DIR/etc/openclash/core/clash_meta"
download_with_fallback \
  "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" \
  "$FILES_DIR/etc/openclash/GeoIP.dat"
download_with_fallback \
  "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" \
  "$FILES_DIR/etc/openclash/GeoSite.dat"

OFFICIAL_PACKAGES="
ca-bundle
ca-certificates
curl
jq
luci
luci-i18n-base-zh-cn
luci-i18n-firewall-zh-cn
luci-i18n-package-manager-zh-cn
luci-i18n-ttyd-zh-cn
luci-theme-argon
luci-app-argon-config
luci-i18n-argon-config-zh-cn
luci-app-filemanager
luci-i18n-filemanager-zh-cn
luci-proto-wireguard
kmod-wireguard
wireguard-tools
socat
luci-app-ddns
luci-app-ddns-go
ddns-go
ddns-scripts
ddns-scripts-cloudflare
openssh-sftp-server
qrencode
iw
iwinfo
wpad-openssl
wireless-regdb
kmod-mac80211
kmod-ath9k
kmod-ath10k
ath10k-firmware-qca6174
ath10k-firmware-qca988x
ath10k-firmware-qca9888
kmod-mt76x2
kmod-mt7921e
kmod-rtw88
kmod-rtw88-pci
kmod-rtw88-8822ce
rtl8822ce-firmware
kmod-iwlwifi
iwlwifi-firmware-ax200
iwlwifi-firmware-ax201
iwlwifi-firmware-ax210
iwlwifi-firmware-iwl8265
iwlwifi-firmware-iwl9260
tailscale
luci-app-openclash
luci-app-passwall
luci-i18n-passwall-zh-cn
luci-app-homeproxy
luci-i18n-homeproxy-zh-cn
mosdns
sing-box
xray-core
hysteria
dns2socks
ipt2socks
shadowsocks-rust-sslocal
redsocks2
ipset
"

PACKAGES="$(echo "$OFFICIAL_PACKAGES $MAXMAI_APK_PACKAGES" | xargs)"
echo "Package set: $PACKAGES" | tee -a "$LOGFILE"

make image PROFILE="generic" \
  PACKAGES="$PACKAGES" \
  FILES="$FILES_DIR" \
  ROOTFS_PARTSIZE="$ROOTFS_PARTSIZE"

MANIFEST="$(find "$BASE_DIR/bin/targets/x86/64" -maxdepth 1 -name "*.manifest" | head -n 1)"
if [ -z "$MANIFEST" ]; then
  echo "Unable to locate generated image manifest." >&2
  exit 1
fi

REQUIRED_MANIFEST_PACKAGES=(
  "luci-app-openclash"
  "luci-app-passwall"
  "luci-app-homeproxy"
  "nikki"
  "luci-app-nikki"
  "mosdns"
  "sing-box"
  "xray-core"
  "hysteria"
  "dns2socks"
  "ipt2socks"
  "shadowsocks-rust-sslocal"
  "tailscale"
  "luci-proto-wireguard"
  "wireguard-tools"
  "socat"
  "ddns-go"
  "luci-app-ddns-go"
  "luci-app-ddns"
  "luci-theme-argon"
  "luci-app-argon-config"
  "luci-i18n-argon-config-zh-cn"
  "luci-theme-aurora"
  "luci-app-aurora-config"
  "luci-i18n-aurora-config-zh-cn"
  "wpad-openssl"
  "iw"
  "iwinfo"
  "wireless-regdb"
  "kmod-mac80211"
)

for pkg in "${REQUIRED_MANIFEST_PACKAGES[@]}"; do
  if ! grep -Eq "^${pkg} -" "$MANIFEST"; then
    echo "Generated manifest is missing required package: $pkg" >&2
    exit 1
  fi
done

PROHIBITED_MANIFEST_PACKAGES=(
  "luci-i18n-dockerman-zh-cn"
  "luci-app-openvpn-server"
  "luci-app-zerotier"
  "luci-app-adguardhome"
  "luci-app-turboacc"
  "luci-app-easytier"
  "luci-app-appfilter"
  "luci-app-netwizard"
)

for pkg in "${PROHIBITED_MANIFEST_PACKAGES[@]}"; do
  if grep -Eq "^${pkg} -" "$MANIFEST"; then
    echo "Generated manifest contains prohibited package: $pkg" >&2
    exit 1
  fi
done

test -x "$FILES_DIR/etc/init.d/maxmai-ssr-bridge"
test -x "$FILES_DIR/usr/bin/maxmai-ssr-bridge-rules"
test -x "$FILES_DIR/etc/openclash/core/clash_meta"
test -s "$FILES_DIR/etc/openclash/GeoIP.dat"
test -s "$FILES_DIR/etc/openclash/GeoSite.dat"

if find "$FILES_DIR/etc/uci-defaults" -maxdepth 1 -name "99-custom.sh" | grep -q .; then
  echo "Unsafe upstream 99-custom.sh is still present." >&2
  exit 1
fi

echo "Generated manifest passed required package checks: $MANIFEST" | tee -a "$LOGFILE"
echo "Build completed successfully at $(date)" | tee -a "$LOGFILE"
