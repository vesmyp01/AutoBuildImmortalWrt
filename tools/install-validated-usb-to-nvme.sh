#!/bin/sh
set -eu

if [ $# -ne 2 ]; then
  echo "Usage: $0 /dev/source_usb_disk /dev/target_nvme_disk" >&2
  exit 1
fi

SRC_DISK="$1"
TARGET_DISK="$2"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root." >&2
  exit 1
fi

if [ ! -b "$SRC_DISK" ] || [ ! -b "$TARGET_DISK" ]; then
  echo "Source or target is not a block device." >&2
  exit 1
fi

if [ "$SRC_DISK" = "$TARGET_DISK" ]; then
  echo "Source and target must be different." >&2
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="/root/nvme-preinstall-$STAMP"
mkdir -p "$BACKUP_DIR"

echo "Source: $SRC_DISK"
echo "Target: $TARGET_DISK"
lsblk

echo "Backing up current target metadata to $BACKUP_DIR"
blkid > "$BACKUP_DIR/blkid.txt" || true
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT > "$BACKUP_DIR/lsblk.txt" || true
sfdisk -d "$TARGET_DISK" > "$BACKUP_DIR/partition-table.sfdisk" || true

echo "About to clone validated USB disk onto NVMe target."
echo "Type INSTALL to continue:"
read answer
if [ "$answer" != "INSTALL" ]; then
  echo "Aborted."
  exit 1
fi

sync
dd if="$SRC_DISK" of="$TARGET_DISK" bs=16M conv=fsync status=progress
sync
partprobe "$TARGET_DISK" || true
lsblk

echo "NVMe installation clone complete."
echo "Reboot and choose the internal NVMe boot option."
