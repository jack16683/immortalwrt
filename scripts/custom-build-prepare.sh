#!/usr/bin/env bash
set -euo pipefail

readonly UPSTREAM_BRANCH="${IMMORTALWRT_BRANCH:-master}"
readonly OVERLAY_ROOT="${CUSTOM_BUILD_OVERLAY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
readonly META_DIR="${BUILD_META_DIR:-build-metadata}"

source_root="$(git rev-parse --show-toplevel)"
if [[ "$source_root" != "$PWD" ]]; then
  echo "error: run the prepare script from the root of the cloned ImmortalWrt source tree" >&2
  exit 1
fi

current_branch="$(git branch --show-current)"
if [[ "$current_branch" != "$UPSTREAM_BRANCH" ]]; then
  echo "error: expected ImmortalWrt branch $UPSTREAM_BRANCH, got ${current_branch:-detached HEAD}" >&2
  exit 1
fi

origin_url="$(git remote get-url origin 2>/dev/null || true)"
if [[ "$origin_url" != *"immortalwrt/immortalwrt"* ]]; then
  echo "error: source tree origin is not ImmortalWrt/immortalwrt: $origin_url" >&2
  exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo 'error: upstream source tree must be clean before applying the build configuration' >&2
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

for required_file in config.seed feeds.conf.append; do
  if [[ ! -f "$OVERLAY_ROOT/$required_file" ]]; then
    echo "error: missing build overlay file: $OVERLAY_ROOT/$required_file" >&2
    exit 1
  fi
done

# Use the official feed declarations exactly as shipped by the current
# upstream branch. On master these are rolling feeds, so feeds update -a
# resolves their latest current commits on every build.
for feed in packages luci routing telephony video; do
  if ! grep -Eq "^src-git ${feed}[[:space:]]" feeds.conf.default; then
    echo "error: expected official feed is missing from upstream feeds.conf.default: $feed" >&2
    exit 1
  fi
done
for feed in kenzo nikki openclash; do
  if grep -Eq "^src-git ${feed}[[:space:]]" feeds.conf.default; then
    echo "error: duplicate custom feed: $feed" >&2
    exit 1
  fi
done
cat "$OVERLAY_ROOT/feeds.conf.append" >> feeds.conf.default

./scripts/feeds update -a
./scripts/feeds install -a

# The official LuCI feed can also carry luci-app-openclash. Force the package
# link to the explicitly configured vernesong/OpenClash feed.
rm -f package/feeds/luci/luci-app-openclash
rm -f package/feeds/kenzo/luci-app-openclash
./scripts/feeds install -f -p openclash luci-app-openclash
openclash_path="$(readlink -f package/feeds/openclash/luci-app-openclash || true)"
if [[ "$openclash_path" != "$PWD/feeds/openclash/luci-app-openclash" ]]; then
  echo "error: luci-app-openclash resolved to unexpected path: $openclash_path" >&2
  exit 1
fi

cp "$OVERLAY_ROOT/config.seed" .config
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

kernel_config="$(find target/linux/x86 -maxdepth 1 -type f -name 'config-*' | sort -V | tail -n1)"
if [[ -z "$kernel_config" ]] || ! grep -qx 'CONFIG_EXT4_FS=y' "$kernel_config"; then
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

base_commit="$(git rev-parse HEAD)"
{
  printf 'base\t%s\t%s\n' "$base_commit" "$origin_url"
  for feed in packages luci routing telephony video kenzo nikki openclash; do
    printf '%s\t%s\t%s\n' \
      "$feed" \
      "$(git -C "feeds/$feed" rev-parse HEAD)" \
      "$(git -C "feeds/$feed" remote get-url origin)"
  done
} > "$META_DIR/source-revisions.tsv"

{
  printf 'base\t%s\n' "$base_commit"
  for feed in kenzo nikki openclash; do
    printf '%s\t%s\n' "$feed" "$(git -C "feeds/$feed" rev-parse HEAD)"
  done
} > "$META_DIR/custom-feeds.tsv"

echo 'Prepared configuration:'
echo "ImmortalWrt ${UPSTREAM_BRANCH}: ${base_commit}"
grep -E '^(CONFIG_TARGET_|CONFIG_PACKAGE_(luci-app-openclash|luci-compat|mihomo-meta|luci-app-lucky|luci-app-tailscale-community)|CONFIG_TARGET_ROOTFS_PARTSIZE|CONFIG_QCOW2_IMAGES|CONFIG_VMDK_IMAGES)' .config
