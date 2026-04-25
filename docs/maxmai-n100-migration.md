# MaxMai N100 Dedicated Migration Kit

This repository copy is narrowed to a dedicated migration workflow for a single N100 router host.

## Fixed build contract

- Base version: `ImmortalWrt 24.10.5`
- Target artifact: `combined-efi.img.gz`
- Fixed network intent:
  - `eth0 = LAN`
  - `eth1 = WAN`
  - `LAN = 10.10.10.5/24`
  - `WAN = PPPoE`
  - `WireGuard = 10.10.11.1/24`
- Service scope:
  - `WireGuard`
  - `socat`
  - `ddns-go`
  - `ddns`
  - `lucky`
  - `SSR+`
- Explicitly not included in the first dedicated image:
  - `OpenClash`
  - `Passwall`
  - `MosDNS`
  - `ZeroTier`

## Private overlay contract

The dedicated workflow expects a private overlay repository checked out to `overlay-private/`.

Required paths under that private repo:

- `files/etc/config/network`
- `files/etc/config/firewall`
- `files/etc/config/dhcp`
- `files/etc/config/dropbear`
- `files/etc/config/system`
- `files/etc/config/socat`
- `files/etc/config/ddns`
- `files/etc/config/ddns-go`
- `files/etc/config/lucky`
- `files/etc/config/shadowsocksr`
- `files/etc/crontabs/root`
- `files/etc/dropbear/authorized_keys`

Optional but recommended:

- `files/etc/ddns-go/ddns-go-config.yaml`
- `files/etc/config/lucky.daji/`
- `files/etc/config/argon`
- `files/etc/config/luci`
- `files/etc/config/uhttpd`
- `files/etc/dropbear/dropbear_ed25519_host_key`
- `files/etc/dropbear/dropbear_rsa_host_key`

## GitHub Actions secrets

The dedicated workflow uses these secrets:

- `MAXMAI_OVERLAY_REPO`
  - format: `owner/repo`
- `MAXMAI_OVERLAY_SSH_KEY`
  - deploy key or personal SSH key that can read the private overlay repo

## Local helper flow

1. Extract the current OpenWrt backup into a local ignored overlay:
   - `tools/extract-maxmai-overlay-from-backup.sh`
2. Review the generated `overlay-private/` content.
3. Push a sanitized copy of `overlay-private/files/` into your private overlay GitHub repo.
4. Run the workflow `build-x86-64-maxmai-n100`.
5. Use:
   - `tools/clone-openwrt-to-usb-macos.sh` for USB-1 rollback media
   - `tools/write-local-image-to-usb-macos.sh` for USB-2 ImmortalWrt validation media
   - `tools/install-validated-usb-to-nvme.sh` from the validated USB-2 system to clone the validated USB onto the internal NVMe

## Notes

- USB-1 is a live block-level clone of the running OpenWrt disk. Run it only while the system is otherwise idle.
- USB-2 should be validated before using it as the source for the final NVMe installation.
- The final NVMe install script clones the validated USB-2 disk to the internal NVMe rather than downloading and writing a second image.
- `luci-app-socat` and its Chinese translation are resolved from the `openwrt.ai` x86_64 `kiddin9` feed during build because they are part of the current live system but not present in the base ImmortalWrt feed.
