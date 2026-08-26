#!/bin/bash
set -euo pipefail

SOURCE_NAME="${SOURCE_NAME:-openwrt}"

cd "$SOURCE_NAME"

echo "::group::packages cache validation"
if ! find bin/packages bin/targets/mediatek/filogic/packages -type f -name '*.apk' -print -quit 2>/dev/null | grep -q .; then
  echo "ERROR: no APK packages were restored from packages cache"
  echo "Run openwrt-staged-from-daed first to produce a packages cache."
  exit 1
fi

missing=0
for pkg in base-files libc libstdcpp6 mtd ntfs3-mount ubi-utils uboot-envtools; do
  if ! find bin/packages bin/targets/mediatek/filogic/packages -type f -name "$pkg-*.apk" -print -quit 2>/dev/null | grep -q .; then
    echo "Missing required APK in packages cache: $pkg"
    missing=1
  fi
done

if [ "$missing" -ne 0 ]; then
  echo "ERROR: packages cache is incomplete; do not use openwrt-staged-from-packages yet."
  echo "Run openwrt-staged-from-daed to compile packages and save a complete packages cache."
  echo "Available package cache sample:"
  find bin/packages bin/targets/mediatek/filogic/packages -type f -name '*.apk' 2>/dev/null | sort | head -100 || true
  exit 1
fi

echo "Required APK packages are present."
find bin/packages bin/targets/mediatek/filogic/packages -type f -name '*.apk' 2>/dev/null | wc -l | awk '{ print "apk_count=" $1 }'
echo "::endgroup::"
