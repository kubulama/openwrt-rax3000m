#!/bin/bash
set -euo pipefail

SOURCE_NAME="${SOURCE_NAME:-openwrt}"

yes_make() {
  local rc
  set +e
  set +o pipefail
  yes n | make "$@"
  rc="${PIPESTATUS[1]}"
  set -e
  set -o pipefail
  return "$rc"
}

cd "$SOURCE_NAME"

echo "::group::host toolchain validation"
if [ ! -x staging_dir/host/bin/libdeflate-gzip ]; then
  echo "Missing staging_dir/host/bin/libdeflate-gzip; rebuilding OpenWrt libdeflate host tool"
  rm -rf build_dir/host/libdeflate-* build_dir/hostpkg/libdeflate-*
  rm -f staging_dir/host/stamp/.libdeflate* staging_dir/hostpkg/stamp/.libdeflate*
  make tools/libdeflate/clean V=s || true
  make package/libs/libdeflate/host/clean V=s || true
  make tools/libdeflate/install V=s || make tools/install -j"$(nproc)" || yes_make tools/install -j1 V=s
  [ -x staging_dir/host/bin/libdeflate-gzip ] || make package/libs/libdeflate/host/compile V=s || true
fi
if [ ! -x staging_dir/host/bin/libdeflate-gzip ]; then
  echo "ERROR: staging_dir/host/bin/libdeflate-gzip is still missing after rebuild"
  find staging_dir/host -maxdepth 3 \( -iname '*libdeflate*' -o -iname '*gzip*' \) || true
  exit 1
fi
if ! find staging_dir/toolchain-* -path '*/bin/aarch64-openwrt-linux-musl-gcc' -type f -executable -print -quit | grep -q .; then
  echo "Missing aarch64-openwrt-linux-musl-gcc; rebuilding OpenWrt toolchain"
  make toolchain/install -j"$(nproc)" || yes_make toolchain/install -j1 V=s
fi
ls -l staging_dir/host/bin/libdeflate-gzip || true
find staging_dir/toolchain-* -path '*/bin/aarch64-openwrt-linux-musl-gcc' -type f -executable -print -quit || true
echo "::endgroup::"
