# Custom monthly ImmortalWrt firmware

This repository builds Ethan's x86_64 VM firmware on Ubuntu 24.04 on the first day of every month.

## Build policy

- Each run clones the latest ImmortalWrt `openwrt-25.12` stable branch instead of rebuilding a fixed historical release commit.
- The official `packages`, `luci`, `routing`, `telephony`, and `video` feeds follow their matching `openwrt-25.12` branches as declared by upstream ImmortalWrt.
- `kenzo`, `nikki`, and `OpenClash` update from their configured upstream branches each run.
- Every successful release records the exact ImmortalWrt base SHA plus all official and third-party feed SHAs in `source-revisions.tsv`, so the inputs remain traceable even though the build tracks moving stable branches.
- The custom repository is used as a build overlay/configuration repository; upstream ImmortalWrt source is cloned fresh into a separate build directory by GitHub Actions.
- Third-party feeds are disabled in runtime `distfeeds` to avoid invalid `packages.adb` URLs.
- Fresh installations use login user `root` with an empty password; the prepare step fails if upstream changes this default.
- Attended Sysupgrade and DDNS clients are intentionally excluded; custom firmware upgrades come from this repository's verified GitHub Releases, while DDNS is handled externally.
- The VM image keeps VMXNET3, VirtIO, E1000/E1000E, USB core/HID, BBR, and the networking modules required by OpenClash and VPNs. Physical NIC, USB storage, i915/DRM, and unused removable-filesystem packages are explicitly excluded in `config.seed`.
- Firmware releases include every generated top-level x86_64 firmware image: BIOS/EFI IMG, QCOW2, VMDK, rootfs archives, kernel, manifests, metadata, and SHA256 checksums. ImageBuilder, SDK, and the per-package repository are excluded.
- If a parallel build fails, CI automatically retries with `make -j1 V=s` to append a useful verbose failure trace to `build.log` before the job exits failed.
- A failed monthly build never replaces the previous successful GitHub Release.

## Schedule

GitHub Actions runs at 10:00 Asia/Shanghai on the first day of each month. The workflow can also be started manually.

## Local preparation check

The prepare script is intended to run from a clean clone of the ImmortalWrt stable source tree while pointing at this repository as the overlay. For example:

```bash
git clone --branch openwrt-25.12 --single-branch https://github.com/immortalwrt/immortalwrt.git source
cd source
CUSTOM_BUILD_OVERLAY_ROOT=/path/to/this/repository \
  bash /path/to/this/repository/scripts/custom-build-prepare.sh
```

The full compile is intentionally performed by GitHub Actions.
