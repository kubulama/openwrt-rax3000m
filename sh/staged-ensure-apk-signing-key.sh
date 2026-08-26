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

echo "::group::apk signing key validation"
if [ ! -x staging_dir/host/bin/openssl ]; then
  echo "Missing staging_dir/host/bin/openssl; rebuilding OpenWrt host tools"
  make tools/openssl/install V=s || make tools/install -j"$(nproc)" || yes_make tools/install -j1 V=s
fi
if [ ! -x staging_dir/host/bin/openssl ]; then
  echo "ERROR: staging_dir/host/bin/openssl is still missing after rebuild"
  find staging_dir/host -maxdepth 3 -iname 'openssl' -print || true
  exit 1
fi

if [ ! -s private-key.pem ]; then
  echo "Generating private-key.pem for apk package index signing"
  staging_dir/host/bin/openssl ecparam -name prime256v1 -genkey -noout -out private-key.pem
  chmod 0600 private-key.pem
fi

if [ ! -s public-key.pem ]; then
  echo "Generating public-key.pem from private-key.pem"
  staging_dir/host/bin/openssl ec -in private-key.pem -pubout > public-key.pem
fi

for file in private-key.pem public-key.pem; do
  if [ ! -s "$file" ]; then
    echo "ERROR: $file is still missing after apk signing key generation"
    exit 1
  fi
  ls -l "$file"
done
echo "::endgroup::"
