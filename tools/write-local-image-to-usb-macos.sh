#!/bin/zsh
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 /path/to/image.img.gz /dev/diskN" >&2
  exit 1
fi

IMAGE="$1"
TARGET_DISK="$2"

if [[ ! -f "$IMAGE" ]]; then
  echo "Image not found: $IMAGE" >&2
  exit 1
fi

if [[ ! "$TARGET_DISK" =~ ^/dev/disk[0-9]+$ ]]; then
  echo "Target must be a whole disk device like /dev/disk4" >&2
  exit 1
fi

RAW_DISK="${TARGET_DISK/disk/rdisk}"

echo "About to write image $IMAGE to $TARGET_DISK"
diskutil info "$TARGET_DISK" | sed -n '1,80p'
echo
read -r "CONFIRM?Type ERASE to continue: "
if [[ "$CONFIRM" != "ERASE" ]]; then
  echo "Aborted."
  exit 1
fi

diskutil unmountDisk force "$TARGET_DISK"

if [[ "$IMAGE" == *.gz ]]; then
  set +e
  gzip -dc "$IMAGE" | sudo dd of="$RAW_DISK" bs=1m status=progress
  pipe_status=("${pipestatus[@]}")
  set -e

  gzip_status="${pipe_status[1]}"
  dd_status="${pipe_status[2]}"

  if [[ "$dd_status" -ne 0 ]]; then
    exit "$dd_status"
  fi

  if [[ "$gzip_status" -ne 0 && "$gzip_status" -ne 2 ]]; then
    exit "$gzip_status"
  fi
else
  sudo dd if="$IMAGE" of="$RAW_DISK" bs=1m status=progress
fi

sync
diskutil eject "$TARGET_DISK"
echo "USB image write complete: $TARGET_DISK"
