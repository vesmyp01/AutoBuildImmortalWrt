#!/bin/zsh
set -euo pipefail

if [[ $# -lt 1 || $# -gt 4 ]]; then
  echo "Usage: $0 /dev/diskN [root@host] [source_disk] [ssh_key]" >&2
  exit 1
fi

TARGET_DISK="$1"
OPENWRT_HOST="${2:-root@10.10.10.5}"
SOURCE_DISK="${3:-/dev/nvme0n1}"
SSH_KEY="${4:-$HOME/.ssh/openwrt_ed25519}"

if [[ ! "$TARGET_DISK" =~ ^/dev/disk[0-9]+$ ]]; then
  echo "Target must be a whole disk device like /dev/disk4" >&2
  exit 1
fi

if [[ ! -f "$SSH_KEY" ]]; then
  echo "SSH key not found: $SSH_KEY" >&2
  exit 1
fi

KNOWN_HOSTS="/tmp/openwrt-clone-known_hosts"
EFI_GUID="C12A7328-F81F-11D2-BA4B-00A0C93EC93B"
WORK_DIR="$(mktemp -d /tmp/openwrt-usb-clone.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT

SRC_BASE="$(basename "$SOURCE_DISK")"
REMOTE_INFO="$WORK_DIR/source-partitions.txt"
ssh -i "$SSH_KEY" \
  -o StrictHostKeyChecking=accept-new \
  -o UserKnownHostsFile="$KNOWN_HOSTS" \
  "$OPENWRT_HOST" \
  "parted -s '$SOURCE_DISK' unit s print && echo --- && cat /sys/class/block/$SRC_BASE/size" \
  > "$REMOTE_INFO"

PARTED_INFO="$(sed '/^---$/q' "$REMOTE_INFO")"
SRC_SECTORS="$(tail -n 1 "$REMOTE_INFO" | tr -d '[:space:]')"
SRC_BYTES="$(( SRC_SECTORS * 512 ))"
TARGET_BYTES="$(diskutil info -plist "$TARGET_DISK" | plutil -extract TotalSize raw -)"
TARGET_SECTORS="$(( TARGET_BYTES / 512 ))"

integer P1_START=0 P1_END=0 P2_START=0 P2_END=0 P3_START=0 P3_END=0 P128_START=0 P128_END=0
SOURCE_P2_PARTUUID=""

while IFS= read -r line; do
  set -- ${(z)line}
  if [[ $# -lt 4 ]]; then
    continue
  fi
  case "$1" in
    128)
      P128_START="${2%s}"
      P128_END="${3%s}"
      ;;
    1)
      P1_START="${2%s}"
      P1_END="${3%s}"
      ;;
    2)
      P2_START="${2%s}"
      P2_END="${3%s}"
      ;;
    3)
      P3_START="${2%s}"
      P3_END="${3%s}"
      ;;
  esac
done < <(printf '%s\n' "$PARTED_INFO")

if (( P1_END == 0 || P2_END == 0 || P3_END == 0 )); then
  echo "Failed to parse source partition layout from $OPENWRT_HOST:$SOURCE_DISK" >&2
  exit 1
fi

LAST_USED_END="$P3_END"
if (( TARGET_SECTORS <= LAST_USED_END + 34 )); then
  echo "Target disk cannot fit the used source partition range." >&2
  echo "Used source end sector: $LAST_USED_END" >&2
  echo "Target sectors: $TARGET_SECTORS" >&2
  exit 1
fi

SOURCE_P2_PARTUUID="$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$KNOWN_HOSTS" "$OPENWRT_HOST" "blkid -s PARTUUID -o value '${SOURCE_DISK}p2'")"
if [[ -z "$SOURCE_P2_PARTUUID" ]]; then
  echo "Failed to read source p2 PARTUUID" >&2
  exit 1
fi

P128_SIZE=$(( P128_END - P128_START + 1 ))
P1_SIZE=$(( P1_END - P1_START + 1 ))
P2_SIZE=$(( P2_END - P2_START + 1 ))
P3_SIZE=$(( P3_END - P3_START + 1 ))

echo "About to live-clone $OPENWRT_HOST:$SOURCE_DISK to $TARGET_DISK"
echo "Source disk bytes: $SRC_BYTES"
echo "Target disk bytes: $TARGET_BYTES"
echo "Used source partitions end at sector: $LAST_USED_END"
echo "Copy plan:"
echo "  p128 bios_grub: start=$P128_START size=$P128_SIZE"
echo "  p1 EFI/kernel : start=$P1_START size=$P1_SIZE"
echo "  p2 squashfs   : start=$P2_START size=$P2_SIZE"
echo "  p3 rootfs ext4: start=$P3_START size=$P3_SIZE"
diskutil info "$TARGET_DISK" | sed -n '1,80p'
echo
read -r "CONFIRM?Type CLONE to continue: "
if [[ "$CONFIRM" != "CLONE" ]]; then
  echo "Aborted."
  exit 1
fi

diskutil unmountDisk force "$TARGET_DISK"
sudo diskutil partitionDisk -noEFI "$TARGET_DISK" 4 GPTFormat \
  "%$EFI_GUID%" "%noformat%" 16MiB \
  ExFAT "%noformat%" 1024MiB \
  ExFAT "%noformat%" 4096MiB \
  "Free Space" dummy R >/dev/null
diskutil unmountDisk force "$TARGET_DISK"

copy_partition() {
  local src_part="$1"
  local dst_part="$2"
  echo "Cloning $src_part -> $dst_part"
  ssh -i "$SSH_KEY" \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="$KNOWN_HOSTS" \
    -o ServerAliveInterval=30 \
    "$OPENWRT_HOST" \
    "sync; dd if='$src_part' bs=8M | gzip -1" \
    | gunzip -c \
    | sudo dd of="$dst_part" bs=1m status=progress
}

copy_partition "${SOURCE_DISK}p1" "/dev/r${TARGET_DISK#/dev/}s1"
copy_partition "${SOURCE_DISK}p2" "/dev/r${TARGET_DISK#/dev/}s2"
copy_partition "${SOURCE_DISK}p3" "/dev/r${TARGET_DISK#/dev/}s3"

diskutil unmountDisk force "$TARGET_DISK"
TARGET_P2_PARTUUID="$(diskutil info -plist "${TARGET_DISK}s2" | plutil -extract DiskUUID raw -)"
if [[ -z "$TARGET_P2_PARTUUID" ]]; then
  echo "Failed to read target p2 DiskUUID" >&2
  exit 1
fi

MOUNT_OUTPUT="$(diskutil mount "${TARGET_DISK}s1")"
MOUNT_POINT="$(printf '%s\n' "$MOUNT_OUTPUT" | sed -n 's#.* at \(.*\)\.$#\1#p')"
if [[ -z "$MOUNT_POINT" ]]; then
  MOUNT_POINT="$(diskutil info -plist "${TARGET_DISK}s1" | plutil -extract MountPoint raw -)"
fi
if [[ -z "$MOUNT_POINT" || ! -d "$MOUNT_POINT" ]]; then
  echo "Failed to mount target EFI partition" >&2
  exit 1
fi

GRUB_CFG="$MOUNT_POINT/grub/grub.cfg"
if [[ ! -f "$GRUB_CFG" ]]; then
  echo "Target GRUB config not found: $GRUB_CFG" >&2
  exit 1
fi

/usr/bin/perl -0pi -e "s/\Q$SOURCE_P2_PARTUUID\E/$TARGET_P2_PARTUUID/g" "$GRUB_CFG"
sync
diskutil unmount "${TARGET_DISK}s1"
sync

echo "Final target partition map:"
sudo gpt show "$TARGET_DISK"
echo
echo "Updated target GRUB root PARTUUID: $TARGET_P2_PARTUUID"
diskutil eject "$TARGET_DISK"

echo "Live clone complete: $TARGET_DISK"
