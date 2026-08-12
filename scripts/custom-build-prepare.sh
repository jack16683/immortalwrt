#!/usr/bin/env bash
set -euo pipefail

readonly BASE_COMMIT="a3378d1a2c15beb2faf4b0bce9c00f07143efa29"
readonly META_DIR="${BUILD_META_DIR:-build-metadata}"
readonly ALLOWED_PATHS_RE='^(\.github/workflows/custom-firmware\.yml|CUSTOM_BUILD\.md|config\.seed|feeds\.conf\.append|scripts/custom-build-prepare\.sh|build-history/)'

if ! git merge-base --is-ancestor "$BASE_COMMIT" HEAD; then
  echo "error: current branch is not based on ImmortalWrt v25.12.1 ($BASE_COMMIT)" >&2
  exit 1
fi

unexpected="$(git diff --name-only "$BASE_COMMIT"...HEAD | grep -Ev "$ALLOWED_PATHS_RE" || true)"
if [[ -n "$unexpected" ]]; then
  echo "error: upstream source files were changed outside the custom build overlay:" >&2
  printf '%s\n' "$unexpected" >&2
  exit 1
fi

if ! grep -qx 'root:x:0:0:root:/root:/bin/ash' package/base-files/files/etc/passwd; then
  echo 'error: default login user is no longer root' >&2
  exit 1
fi
if ! grep -qx 'root:::0:99999:7:::' package/base-files/files/etc/shadow; then
  echo 'error: default root password is no longer empty' >&2
  exit 1
fi
if [[ -e files/etc/passwd || -e files/etc/shadow ]]; then
  echo 'error: custom passwd/shadow overlay could override the empty root password' >&2
  exit 1
fi

for feed in kenzo nikki openclash; do
  if grep -Eq "^src-git ${feed}[[:space:]]" feeds.conf.default; then
    echo "error: duplicate custom feed: $feed" >&2
    exit 1
  fi
done
cat feeds.conf.append >> feeds.conf.default

./scripts/feeds update -a
./scripts/feeds install -a

# The official LuCI feed also carries luci-app-openclash. Force the package
# link to the explicitly configured vernesong/OpenClash feed.
rm -f package/feeds/luci/luci-app-openclash
rm -f package/feeds/kenzo/luci-app-openclash
./scripts/feeds install -f -p openclash luci-app-openclash
openclash_path="$(readlink -f package/feeds/openclash/luci-app-openclash || true)"
if [[ "$openclash_path" != "$PWD/feeds/openclash/luci-app-openclash" ]]; then
  echo "error: luci-app-openclash resolved to unexpected path: $openclash_path" >&2
  exit 1
fi

cp config.seed .config
make defconfig

required=(
  CONFIG_TARGET_x86_64
  CONFIG_PACKAGE_luci-app-openclash
  CONFIG_PACKAGE_luci-compat
  CONFIG_PACKAGE_mihomo-meta
  CONFIG_PACKAGE_luci-app-lucky
  CONFIG_PACKAGE_luci-app-tailscale-community
  CONFIG_PACKAGE_luci-app-netdata
  CONFIG_PACKAGE_luci-app-statistics
  CONFIG_PACKAGE_luci-app-zerotier
  CONFIG_PACKAGE_luci-app-upnp
  CONFIG_PACKAGE_luci-app-autoreboot
  CONFIG_PACKAGE_luci-app-ttyd
  CONFIG_PACKAGE_luci-app-wol
  CONFIG_PACKAGE_kmod-tcp-bbr
  CONFIG_PACKAGE_kmod-e1000
  CONFIG_PACKAGE_kmod-e1000e
  CONFIG_PACKAGE_kmod-vmxnet3
  CONFIG_PACKAGE_kmod-usb-core
  CONFIG_PACKAGE_kmod-usb-hid
  CONFIG_TARGET_ROOTFS_EXT4FS
  CONFIG_TARGET_ROOTFS_SQUASHFS
  CONFIG_QCOW2_IMAGES
  CONFIG_VMDK_IMAGES
)
for symbol in "${required[@]}"; do
  if ! grep -qx "${symbol}=y" .config; then
    echo "error: required config symbol is not enabled: $symbol" >&2
    exit 1
  fi
done

forbidden_packages=(
  attendedsysupgrade-common
  luci-app-attendedsysupgrade
  luci-i18n-attendedsysupgrade-zh-cn
  rpcd-mod-rpcsys
  ddns-scripts
  ddns-scripts-services
  qemu-ga
  open-vm-tools
  automount
  i915-firmware-dmc
  kmod-8139cp
  kmod-8139too
  kmod-amazon-ena
  kmod-amd-xgbe
  kmod-bnx2
  kmod-drm-i915
  kmod-dwmac-intel
  kmod-forcedeth
  kmod-fs-exfat
  kmod-fs-f2fs
  kmod-fs-ntfs3
  kmod-i40e
  kmod-igb
  kmod-igbvf
  kmod-igc
  kmod-ixgbe
  kmod-ixgbevf
  kmod-pcnet32
  kmod-r8101
  kmod-r8125
  kmod-r8126
  kmod-r8168
  kmod-tg3
  kmod-tulip
  kmod-usb-net
  kmod-usb-net-asix
  kmod-usb-net-asix-ax88179
  kmod-usb-net-rtl8150
  kmod-usb-net-rtl8152-vendor
  kmod-usb-storage
  kmod-usb-storage-extras
  kmod-usb-storage-uas
)
for package in "${forbidden_packages[@]}"; do
  if grep -qx "CONFIG_PACKAGE_${package}=y" .config; then
    echo "error: forbidden VM-image package was enabled: $package" >&2
    exit 1
  fi
done

if grep -qx 'CONFIG_ALL_KMODS=y' .config; then
  echo 'error: CONFIG_ALL_KMODS must remain disabled' >&2
  exit 1
fi

if ! grep -qx 'CONFIG_EXT4_FS=y' target/linux/x86/config-6.12; then
  echo 'error: x86 kernel no longer has built-in ext4 support' >&2
  exit 1
fi

if ! grep -qx 'CONFIG_TARGET_ROOTFS_PARTSIZE=1024' .config; then
  echo 'error: rootfs partition size must remain 1024 MiB' >&2
  exit 1
fi

for feed in kenzo nikki openclash; do
  if grep -qx "CONFIG_FEED_${feed}=y" .config; then
    echo "error: third-party feed ${feed} would leak into runtime distfeeds" >&2
    exit 1
  fi
done

mkdir -p "$META_DIR"
./scripts/diffconfig.sh > "$META_DIR/config.effective"
cp feeds.conf.default "$META_DIR/feeds.effective"
{
  printf 'base\t%s\n' "$BASE_COMMIT"
  for feed in kenzo nikki openclash; do
    printf '%s\t%s\n' "$feed" "$(git -C "feeds/$feed" rev-parse HEAD)"
  done
} > "$META_DIR/custom-feeds.tsv"

echo 'Prepared configuration:'
grep -E '^(CONFIG_TARGET_|CONFIG_PACKAGE_(luci-app-openclash|luci-compat|mihomo-meta|luci-app-lucky|luci-app-tailscale-community)|CONFIG_TARGET_ROOTFS_PARTSIZE|CONFIG_QCOW2_IMAGES|CONFIG_VMDK_IMAGES)' .config
