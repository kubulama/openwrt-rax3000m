#!/bin/bash
set -euo pipefail

SOURCE_NAME="${SOURCE_NAME:-openwrt}"
REPO_URL="${REPO_URL:-https://github.com/shiyu1314/openwrt-source}"
REPO_BRANCH="${REPO_BRANCH:-openwrt-25.12}"
DIY_P1_SH="${DIY_P1_SH:-sh/op.sh}"
OP_IP="${OP_IP:-192.168.2.1}"
OP_author="${OP_author:-kubulama}"
CUSTOM_PLUGINS="${CUSTOM_PLUGINS:-luci-app-zerotier luci-app-socat luci-app-samba4 luci-theme-m3e luci-app-ttyd luci-app-diskman luci-app-daed luci-i18n-daed-zh-cn}"

sudo mkdir -p /workdir
sudo chown "$USER:$GROUPS" /workdir

if [ ! -d "/workdir/$SOURCE_NAME/.git" ]; then
  if [ -e "/workdir/$SOURCE_NAME" ]; then
    rm -rf "/workdir/${SOURCE_NAME}-src"
    git clone "$REPO_URL" "/workdir/${SOURCE_NAME}-src"
    shopt -s dotglob
    cp -a "/workdir/${SOURCE_NAME}-src/"* "/workdir/$SOURCE_NAME/"
    shopt -u dotglob
    rm -rf "/workdir/${SOURCE_NAME}-src"
  else
    git clone "$REPO_URL" "/workdir/$SOURCE_NAME"
  fi
fi

ln -sf "/workdir/$SOURCE_NAME" "$GITHUB_WORKSPACE/$SOURCE_NAME"
cd "$GITHUB_WORKSPACE/$SOURCE_NAME"

case "$REPO_BRANCH" in
  openwrt-25.12)
    if [ -n "${STAGED_RELEASE_TAG:-}" ]; then
      release_tag="$STAGED_RELEASE_TAG"
    else
      release_tag="$(git tag --sort=taggerdate --list 'v25.*' | tail -1)"
    fi
    git checkout "$release_tag"
    ;;
  *)
    echo "Unsupported REPO_BRANCH=$REPO_BRANCH"
    exit 1
    ;;
esac

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "release_tag=$release_tag" >> "$GITHUB_OUTPUT"
fi
echo "release_tag=$release_tag" >> "$GITHUB_ENV"

./scripts/feeds update -a

cd "$GITHUB_WORKSPACE"
[ -e patch ] && cp -rf patch/diy/*.patch "$SOURCE_NAME"
[ -e patch ] && cp -rf patch/luci/*.patch "$SOURCE_NAME/feeds/luci"

chmod +x "$DIY_P1_SH"
cd "$SOURCE_NAME"
"$GITHUB_WORKSPACE/$DIY_P1_SH"
cd "$GITHUB_WORKSPACE"

[ -e patch ] && cp -rf patch/nginx/luci.locations "$SOURCE_NAME/feeds/packages/net/nginx/files-luci-support"
[ -e patch ] && cp -rf patch/nginx/uci.conf.template "$SOURCE_NAME/feeds/packages/net/nginx-util/files"
[ -e files ] && mv files "$SOURCE_NAME/files"

cat <<'EOF' >> "$SOURCE_NAME/.config"
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_cmcc_rax3000m=y
CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_cmcc_rax3000m-emmc=y
CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_cmcc_rax3000m-nand=y
CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_cmcc_rax3000m-256m-nand=y
CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_cmcc_xr30-emmc=y
CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_cmcc_xr30-nand=y
CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_jcg_q30-pro=y
EOF

[ -e config ] && cat config/config-common >> "$SOURCE_NAME/.config"

sed -i "s/192.168.1.1/$OP_IP/" "$SOURCE_NAME/package/base-files/files/bin/config_generate"

IFS=' ' read -r -a plugins <<< "$CUSTOM_PLUGINS"
for plugin in "${plugins[@]}"; do
  echo "CONFIG_PACKAGE_${plugin}=y" >> "$SOURCE_NAME/.config"
done

cd "$SOURCE_NAME"
make defconfig
