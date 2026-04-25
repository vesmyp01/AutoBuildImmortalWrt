# USB-2 ImmortalWrt Image Postmortem

Date: 2026-04-25

## Status

The previously written USB-2 ImmortalWrt image must be treated as invalid for N100 migration validation.

USB-1, the cloned OpenWrt rollback disk, boots and serves the Mac on Wi-Fi correctly. The same Mac failed to reach `10.10.10.5` when USB-2 was booted, which points to an ImmortalWrt image/config problem rather than a Mac-only issue.

## Confirmed Findings

- The generated USB-2 rootfs did not contain `/etc/config/wireless`.
- The generated USB-2 rootfs did not contain the current OpenWrt backup's `/etc/firewall.user`.
- The generated USB-2 manifest/rootfs did not include the required AP wireless stack, including `wpad-openssl`, `iw`, `iwinfo`, `wireless-regdb`, or Wi-Fi driver modules.
- The old upstream `files/etc/uci-defaults/99-custom.sh` existed in the local source tree and has been removed to avoid future accidental inclusion.
- The final USB-2 rootfs did not include `99-custom.sh`; the main observed problem is missing wireless config and missing wireless packages.
- The current `network`, `dhcp`, and `firewall` files in the generated rootfs matched the private overlay, so the immediate LAN failure is not explained by those three files being copied incorrectly.
- The `.img.gz` emitted `trailing garbage ignored` when decompressed locally. This may be tolerated by some pipelines, but the next image should be regenerated cleanly and revalidated before writing to USB.

## Fix Requirements

- Treat `/etc/config/wireless` as a required private overlay file.
- Include the current OpenWrt backup's optional system files where present: `/etc/firewall.user`, `/etc/hosts`, `/etc/rc.local`, and `/etc/sysctl.conf`.
- Include AP support packages: `wpad-openssl`, `iw`, `iwinfo`, `wireless-regdb`, and `kmod-mac80211`.
- Include the likely N100 PCIe Wi-Fi driver family packages, with manifest checks to fail the build if critical wireless packages are missing.
- Rebuild USB-2 from the corrected recipe.
- Before writing the rebuilt image to USB, inspect the generated manifest/rootfs and confirm both `/etc/config/wireless` and the AP package stack are present.

## Do Not Use

Do not use the old USB-2 ImmortalWrt image for final NVMe installation or further migration validation.
