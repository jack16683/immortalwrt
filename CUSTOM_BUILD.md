# Custom monthly ImmortalWrt firmware

This fork builds Ethan's x86_64 VM firmware on Ubuntu 24.04 on the first day of every month.

## Build policy

- Base source is fixed to the signed `v25.12.1` release commit
  `a3378d1a2c15beb2faf4b0bce9c00f07143efa29`.
- Official feeds remain pinned by the upstream release.
- `kenzo`, `nikki`, and `OpenClash` update from their configured branches each run.
- The resolved third-party feed commits are included with every release.
- Third-party feeds are disabled in runtime `distfeeds` to avoid invalid `packages.adb` URLs.
- Fresh installations use login user `root` with an empty password; the prepare step fails if upstream or an overlay changes this default.
- Attended Sysupgrade and DDNS clients are intentionally excluded; custom firmware upgrades come from this repository's verified GitHub Releases, while DDNS is handled externally.
- The VM image keeps VMXNET3, VirtIO, E1000/E1000E, USB core/HID, BBR, and the networking modules required by OpenClash and VPNs. Physical NIC, USB storage, i915/DRM, and unused removable-filesystem packages are explicitly excluded in `config.seed`.
- Firmware releases include every generated top-level x86_64 firmware image: BIOS/EFI IMG, QCOW2, VMDK, rootfs archives, kernel, manifests, and SHA256 checksums. ImageBuilder, SDK, and the per-package repository are excluded.

## Schedule

GitHub Actions runs at 10:00 Asia/Shanghai on the first day of each month. The workflow can also be started manually.

## Local preparation check

```bash
bash scripts/custom-build-prepare.sh
```

The full compile is intentionally performed by GitHub Actions.
