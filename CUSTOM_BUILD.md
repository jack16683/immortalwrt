# Custom monthly ImmortalWrt firmware

This fork builds Ethan's x86_64 VM firmware on the first day of every month.

## Build policy

- Base source is fixed to the signed `v25.12.1` release commit
  `a3378d1a2c15beb2faf4b0bce9c00f07143efa29`.
- Official feeds remain pinned by the upstream release.
- `kenzo`, `nikki`, and `OpenClash` update from their configured branches each run.
- The resolved third-party feed commits are included with every release.
- Third-party feeds are disabled in runtime `distfeeds` to avoid invalid `packages.adb` URLs.
- Firmware releases include compressed BIOS/EFI IMG and QCOW2 images, manifests, and SHA256 checksums.

## Schedule

GitHub Actions runs at 10:00 Asia/Shanghai on the first day of each month. The workflow can also be started manually.

## Local preparation check

```bash
bash scripts/custom-build-prepare.sh
```

The full compile is intentionally performed by GitHub Actions.
