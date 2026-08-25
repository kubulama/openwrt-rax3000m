#!/bin/bash
set -euo pipefail

SOURCE_NAME="${SOURCE_NAME:-openwrt}"
TARGET_DIR="${TARGET_DIR:-bin/targets/mediatek/filogic}"

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

echo "::group::buildinfo validation"
missing=0
for file in config.buildinfo feeds.buildinfo version.buildinfo; do
  if [ ! -s "$TARGET_DIR/$file" ]; then
    echo "Missing $TARGET_DIR/$file"
    missing=1
  fi
done

if [ "$missing" -ne 0 ]; then
  echo "Generating OpenWrt buildinfo files"
  make buildinfo V=s || yes_make buildinfo V=s
fi

for file in config.buildinfo feeds.buildinfo version.buildinfo; do
  if [ ! -s "$TARGET_DIR/$file" ]; then
    echo "ERROR: $TARGET_DIR/$file is still missing after make buildinfo"
    find bin/targets -maxdepth 4 -type f -name '*.buildinfo' -print || true
    exit 1
  fi
  ls -l "$TARGET_DIR/$file"
done
echo "::endgroup::"
