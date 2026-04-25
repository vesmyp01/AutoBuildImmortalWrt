#!/bin/bash
set -euo pipefail

if [ -d "/home/build/immortalwrt" ] && [ -f "/home/build/immortalwrt/shell/custom-packages.sh" ]; then
  BASE_DIR="${BASE_DIR:-/home/build/immortalwrt}"
else
  BASE_DIR="${BASE_DIR:-$(pwd)}"
fi

cd "$BASE_DIR"

CUSTOM_PACKAGES="${CUSTOM_PACKAGES:-}"
source "$BASE_DIR/shell/custom-packages.sh"
source "$BASE_DIR/shell/switch_repository.sh"

FILES_DIR="${FILES_DIR:-$BASE_DIR/files}"
OVERLAY_DIR="${OVERLAY_DIR:-$BASE_DIR/overlay-private}"
ROOTFS_PARTSIZE="${ROOTFS_PARTSIZE:-4096}"
LOGFILE="${LOGFILE:-/tmp/maxmai-n100-build.log}"

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
)

OPTIONAL_PATHS=(
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

echo "Starting MaxMai N100 USB-2 build at $(date)" | tee -a "$LOGFILE"
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
if grep -q "/luci-static/ifit" "$OVERLAY_DIR/files/etc/config/luci"; then
  echo "Overlay LuCI config still references missing ifit theme." >&2
  exit 1
fi

rm -f "$FILES_DIR/etc/uci-defaults/99-custom.sh"
mkdir -p "$FILES_DIR"
cp -a "$OVERLAY_DIR/files/." "$FILES_DIR/"

chmod 600 "$FILES_DIR/etc/shadow"
chmod 600 "$FILES_DIR/etc/dropbear/dropbear_"*"_host_key" 2>/dev/null || true

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

echo "Syncing third-party package store requested by shell/custom-packages.sh..." | tee -a "$LOGFILE"
mkdir -p "$BASE_DIR/extra-packages/luci-app-lucky"
download_with_fallback \
  "https://raw.githubusercontent.com/wukongdaily/store/master/run/x86/luci-app-lucky/luci-app-lucky_1.2.0-r11_all.ipk" \
  "$BASE_DIR/extra-packages/luci-app-lucky/luci-app-lucky_1.2.0-r11_all.ipk"
download_with_fallback \
  "https://raw.githubusercontent.com/wukongdaily/store/master/run/x86/luci-app-lucky/lucky_2.17.8-r8_x86_64.ipk" \
  "$BASE_DIR/extra-packages/luci-app-lucky/lucky_2.17.8-r8_x86_64.ipk"
download_with_fallback \
  "https://raw.githubusercontent.com/wukongdaily/store/master/run/x86/ssrp_x86_64-190_r126.run" \
  "$BASE_DIR/extra-packages/ssrp_x86_64-190_r126.run"
sh "$BASE_DIR/shell/prepare-packages.sh"

echo "Syncing luci-app-socat from kiddin9 feed..." | tee -a "$LOGFILE"
KIDDIN9_BASE="https://dl.openwrt.ai/releases/24.10/packages/x86_64/kiddin9"
download_with_fallback \
  "${KIDDIN9_BASE}/luci-app-socat_1.0-r9_all.ipk" \
  "$BASE_DIR/packages/luci-app-socat_1.0-r9_all.ipk"

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
"

PACKAGES="$(echo "$OFFICIAL_PACKAGES $CUSTOM_PACKAGES" | xargs)"
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
  "wpad-openssl"
  "iw"
  "iwinfo"
  "wireless-regdb"
  "kmod-mac80211"
  "luci-proto-wireguard"
  "wireguard-tools"
  "socat"
  "ddns-go"
  "luci-app-ddns-go"
  "luci-app-ddns"
  "luci-app-lucky"
  "lucky"
  "luci-app-ssr-plus"
  "luci-theme-argon"
  "luci-app-argon-config"
  "luci-i18n-argon-config-zh-cn"
  "luci-theme-aurora"
  "luci-app-aurora-config"
  "luci-i18n-aurora-config-zh-cn"
  "luci-app-tailscale"
  "luci-i18n-tailscale-zh-cn"
  "momo"
  "luci-app-momo"
  "luci-i18n-momo-zh-cn"
  "luci-app-uninstall"
  "luci-app-partexp"
  "luci-i18n-partexp-zh-cn"
  "luci-app-watchdog"
  "luci-i18n-watchdog-zh-cn"
  "luci-app-taskplan"
  "luci-i18n-taskplan-zh-cn"
  "luci-app-bandix"
  "luci-i18n-bandix-zh-cn"
  "luci-app-store"
)

for pkg in "${REQUIRED_MANIFEST_PACKAGES[@]}"; do
  if ! grep -Eq "^${pkg} -" "$MANIFEST"; then
    echo "Generated manifest is missing required package: $pkg" >&2
    exit 1
  fi
done

PROHIBITED_MANIFEST_PACKAGES=(
  "luci-app-openvpn-server"
  "luci-app-nekobox"
  "luci-app-mosdns"
  "luci-app-passwall2"
  "luci-app-openclash"
  "luci-app-zerotier"
  "luci-app-adguardhome"
  "luci-app-turboacc"
  "luci-app-gecoosac"
  "luci-app-unishare"
  "luci-app-appfilter"
  "luci-app-netwizard"
)

for pkg in "${PROHIBITED_MANIFEST_PACKAGES[@]}"; do
  if grep -Eq "^${pkg} -" "$MANIFEST"; then
    echo "Generated manifest contains prohibited package: $pkg" >&2
    exit 1
  fi
done

if find "$FILES_DIR/etc/uci-defaults" -maxdepth 1 -name "99-custom.sh" | grep -q .; then
  echo "Unsafe upstream 99-custom.sh is still present." >&2
  exit 1
fi

echo "Generated manifest passed required package checks: $MANIFEST" | tee -a "$LOGFILE"
echo "Build completed successfully at $(date)" | tee -a "$LOGFILE"
