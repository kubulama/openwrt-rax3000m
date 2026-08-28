#!/bin/bash
set -euo pipefail

SOURCE_NAME="${SOURCE_NAME:-openwrt}"

cd "$SOURCE_NAME"

echo "::group::packages cache validation"
stage_dir="staging_dir/packages/mediatek"

if [ ! -d "$stage_dir" ] || ! find "$stage_dir" -maxdepth 1 -type f -name '*.apk' -print -quit 2>/dev/null | grep -q .; then
  echo "No APK files in $stage_dir; restoring staged package index inputs from bin/packages."
  mkdir -p "$stage_dir"
  for src_dir in bin/packages/*/* bin/targets/mediatek/filogic/packages; do
    [ -d "$src_dir" ] || continue
    find "$src_dir" -maxdepth 1 -type f -name '*.apk' -exec cp -n {} "$stage_dir/" \;
  done
fi

if ! find "$stage_dir" -maxdepth 1 -type f -name '*.apk' -print -quit 2>/dev/null | grep -q .; then
  echo "ERROR: no APK files are available in $stage_dir for package/merge-index"
  echo "Run openwrt-staged or openwrt-staged-from-daed through the package compile stage first."
  exit 1
fi

package_dirs=(
  "$stage_dir"
  staging_dir/packages/packages
  bin/packages
  bin/targets/mediatek/filogic/packages
)
existing_dirs=()
for dir in "${package_dirs[@]}"; do
  [ -d "$dir" ] && existing_dirs+=("$dir")
done

if [ "${#existing_dirs[@]}" -eq 0 ] || ! find "${existing_dirs[@]}" -type f -name '*.apk' -print -quit 2>/dev/null | grep -q .; then
  echo "ERROR: no APK packages were restored from packages cache"
  echo "Run openwrt-staged-from-daed first to produce a packages cache."
  exit 1
fi

missing=0
for pkg in base-files libc libstdcpp6 mtd ntfs3-mount ubi-utils uboot-envtools; do
  if ! find "${existing_dirs[@]}" -type f \( -name "$pkg-*.apk" -o -name "$pkg"_*.apk \) -print -quit 2>/dev/null | grep -q .; then
    echo "Missing required APK in packages cache: $pkg"
    missing=1
  fi
done

if [ "$missing" -ne 0 ]; then
  echo "ERROR: packages cache is incomplete; do not use openwrt-staged-from-packages yet."
  echo "Run openwrt-staged-from-daed to compile packages and save a complete packages cache."
  echo "Available package cache sample:"
  find "${existing_dirs[@]}" -type f -name '*.apk' 2>/dev/null | sort | head -160 || true
  exit 1
fi

echo "Required APK packages are present."
for dir in "${existing_dirs[@]}"; do
  find "$dir" -type f -name '*.apk' 2>/dev/null | wc -l | awk -v dir="$dir" '{ print dir "_apk_count=" $1 }'
done
echo "::endgroup::"
