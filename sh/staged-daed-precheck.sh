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

echo "::group::kernel bpf validation"
kernel_config="$(find build_dir/target-* -path '*/linux-mediatek_filogic/linux-*/.config' -type f -print -quit || true)"
if [ -z "$kernel_config" ]; then
  echo "Missing mediatek kernel .config; rebuilding target before bpf-headers"
  make target/compile -j"$(nproc)" || yes_make target/compile -j1 V=s
  kernel_config="$(find build_dir/target-* -path '*/linux-mediatek_filogic/linux-*/.config' -type f -print -quit || true)"
fi
if [ -z "$kernel_config" ]; then
  echo "ERROR: mediatek kernel .config is still missing after target/compile"
  find build_dir/target-* -maxdepth 4 -type d -name 'linux-*' -print || true
  exit 1
fi
echo "kernel_config=$kernel_config"
make package/kernel/bpf-headers/compile V=s || yes_make package/kernel/bpf-headers/compile V=s
echo "::endgroup::"

echo "::group::daed package diagnostics"
grep -E 'CONFIG_PACKAGE_(daed|luci-app-daed|luci-i18n-daed)|CONFIG_DAE|CONFIG_DAED|CONFIG_KERNEL_DEBUG_INFO_BTF' .config || true
grep -nE 'corepack|pnpm|apps/web|webrender|dist/index.html' package/porxy/daed/Makefile || true
sed -n '1,260p' package/porxy/daed/Makefile || true
echo "::endgroup::"

rm -rf dl/go-mod-cache
make package/porxy/daed/clean V=s
make package/porxy/daed/compile -j"$(nproc)" V=s || {
  echo "::group::daed failure diagnostics"
  find build_dir -path '*/daed-*/apps/web/*' -type f | sort | tail -200 || true
  find build_dir -path '*/daed-*/apps/web/dist/*' -type f | sort | head -100 || true
  echo "::endgroup::"
  yes_make package/porxy/daed/compile -j1 V=s
}
