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

echo "::group::kernel config validation"
kernel_config="$(find build_dir/target-* -path '*/linux-mediatek_filogic/linux-*/.config' -type f -print -quit || true)"
if [ -z "$kernel_config" ]; then
  echo "Missing mediatek kernel .config; rebuilding target before kernel package compile"
  make target/compile -j"$(nproc)" || yes_make target/compile -j1 V=s
  kernel_config="$(find build_dir/target-* -path '*/linux-mediatek_filogic/linux-*/.config' -type f -print -quit || true)"
fi

if [ -z "$kernel_config" ]; then
  echo "ERROR: mediatek kernel .config is still missing after target/compile"
  find build_dir/target-* -maxdepth 4 -type d -name 'linux-*' -print || true
  exit 1
fi

echo "kernel_config=$kernel_config"
echo "::endgroup::"
