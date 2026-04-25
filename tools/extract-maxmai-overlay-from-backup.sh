#!/bin/bash
set -euo pipefail

BACKUP_TAR="${1:-/Users/maxmai/Downloads/backup-OpenWrt-2026-04-21.tar.gz}"
OUT_DIR="${2:-$(cd "$(dirname "$0")/.." && pwd)/overlay-private}"

if [ ! -f "$BACKUP_TAR" ]; then
  echo "Backup tar not found: $BACKUP_TAR" >&2
  exit 1
fi

rm -rf "$OUT_DIR/files"
mkdir -p "$OUT_DIR/files"

extract_file() {
  local rel="$1"
  local dest="$OUT_DIR/files/$rel"
  mkdir -p "$(dirname "$dest")"
  tar -xOf "$BACKUP_TAR" "$rel" > "$dest"
}

extract_tree() {
  local prefix="$1"
  local rel
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    local dest="$OUT_DIR/files/$rel"
    mkdir -p "$(dirname "$dest")"
    tar -xOf "$BACKUP_TAR" "$rel" > "$dest"
  done < <(tar -tzf "$BACKUP_TAR" | grep "^${prefix}")
}

REQUIRED_FILES=(
  "etc/config/network"
  "etc/config/firewall"
  "etc/config/dhcp"
  "etc/config/wireless"
  "etc/config/dropbear"
  "etc/config/system"
  "etc/config/socat"
  "etc/config/ddns"
  "etc/config/ddns-go"
  "etc/config/lucky"
  "etc/config/shadowsocksr"
  "etc/crontabs/root"
  "etc/dropbear/authorized_keys"
  "etc/passwd"
  "etc/shadow"
  "etc/group"
)

OPTIONAL_FILES=(
  "etc/firewall.user"
  "etc/hosts"
  "etc/rc.local"
  "etc/sysctl.conf"
  "etc/ddns-go/ddns-go-config.yaml"
  "etc/config/argon"
  "etc/config/luci"
  "etc/config/uhttpd"
  "etc/dropbear/dropbear_ed25519_host_key"
  "etc/dropbear/dropbear_rsa_host_key"
)

for rel in "${REQUIRED_FILES[@]}"; do
  extract_file "$rel"
done

for rel in "${OPTIONAL_FILES[@]}"; do
  if tar -tzf "$BACKUP_TAR" | grep -qx "$rel"; then
    extract_file "$rel"
  fi
done

extract_tree "etc/config/lucky.daji/"

python3 - "$OUT_DIR/files/etc/config/firewall" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()
sections = []
current = []
for line in text.splitlines():
    if line.startswith("config ") and current:
        sections.append(current)
        current = [line]
    else:
        current.append(line)
if current:
    sections.append(current)

blocked_include_tokens = (
    "zerotier",
    "miniupnpd",
    "ipsec",
    "parentcontrol",
    "timecontrol",
    "openclash",
    "passwall",
    "pptpd",
    "unblockmusic",
)

kept = []
for section in sections:
    header = section[0].strip()
    body = "\n".join(section).lower()
    is_include = header.startswith("config include")
    if is_include and any(token in body for token in blocked_include_tokens):
        continue
    kept.append("\n".join(section).rstrip())

path.write_text("\n\n".join(kept).rstrip() + "\n")
PY

chmod 600 "$OUT_DIR/files/etc/shadow"
chmod 600 "$OUT_DIR/files/etc/dropbear/dropbear_"*"_host_key" 2>/dev/null || true

cat > "$OUT_DIR/README.local.txt" <<EOF
Local private overlay generated from:
$BACKUP_TAR

This directory is intentionally gitignored.
Review secrets before pushing any copy of it to a private repository.
EOF

echo "Overlay extracted to: $OUT_DIR"
