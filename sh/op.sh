#!/bin/bash

function git_sparse_clone() {
  branch="$1" repourl="$2" && shift 2
  git clone --depth=1 -b $branch --single-branch --filter=blob:none --sparse $repourl
  repodir=$(echo $repourl | awk -F '/' '{print $(NF)}')
  cd $repodir && git sparse-checkout set $@
  mv -f $@ ../
  cd .. && rm -rf $repodir
}

set -x

apply_patch_once() {
    patch_file="$1"

    echo "Applying $patch_file ..."
    if patch -p1 --dry-run --silent < "$patch_file"; then
        patch -p1 --forward --no-backup-if-mismatch < "$patch_file"
    elif patch -R -p1 --dry-run --silent < "$patch_file"; then
        echo "Skipping $patch_file: already applied"
    else
        echo "ERROR: Failed to apply $patch_file"
        return 1
    fi
}

# kenrel Vermagic
sed -ie 's/^\(.\).*vermagic$/\1cp $(TOPDIR)\/.vermagic $(LINUX_DIR)\/.vermagic/' include/kernel-defaults.mk
grep HASH target/linux/generic/kernel-6.12 | awk -F'HASH-' '{print $2}' | awk '{print $1}' | md5sum | awk '{print $1}' > .vermagic

git clone -b packages --depth 1 --single-branch https://github.com/shiyu1314/openwrt-feeds package/xd
git clone -b porxy --depth 1 --single-branch https://github.com/shiyu1314/openwrt-feeds package/porxy

[ -f package/xd/smartdns/Makefile ] && sed -i -E \
  -e 's/[[:space:]]*PACKAGE_smartdns-ui:rust-bindgen\/host//g' \
  -e 's/[[:space:]]*rust-bindgen\/host//g' \
  -e 's/[[:space:]]*PACKAGE_smartdns-ui://g' \
  package/xd/smartdns/Makefile

# Use QiuSimons' newer daed/luci-app-daed packages while keeping package names
# compatible with the existing luci-app-daed selection.
rm -rf package/porxy/daed package/porxy/luci-app-daed
rm -rf qiu-luci-app-daed
git clone --depth=1 -b kix --single-branch --filter=blob:none --sparse https://github.com/QiuSimons/luci-app-daed qiu-luci-app-daed
pushd qiu-luci-app-daed || exit 1
git sparse-checkout set daed luci-app-daed
popd
mv -f qiu-luci-app-daed/daed qiu-luci-app-daed/luci-app-daed package/porxy/
rm -rf qiu-luci-app-daed

# Match daeuniverse/daed's declared package manager. Floating to latest pnpm
# can change lifecycle-script handling and make the frontend build flaky.
sed -i 's/npm install -g pnpm/npm install -g pnpm@10.24.0/' package/porxy/daed/Makefile
grep -Fq 'npm install -g pnpm@10.24.0' package/porxy/daed/Makefile || {
  echo "ERROR: failed to pin daed pnpm version"
  exit 1
}

# QiuSimons' current daed package builds the upstream monorepo with
# `pnpm build --filter daed`, which can leave apps/web/dist empty or leave
# workspace packages as browser-side bare imports. dae-wing embeds
# webrender/web at Go compile time, so install the pnpm workspace deps, build
# the shared web packages first, build apps/web explicitly, and fail early with
# diagnostics if assets are still missing or cannot run standalone in a browser.
python3 - <<'PY'
from pathlib import Path

path = Path("package/porxy/daed/Makefile")
lines = path.read_text().splitlines(keepends=True)
out = []
patched_install = False
patched_build = False
patched_copy = False

for line in lines:
    stripped = line.strip()
    if stripped == "pnpm install ; \\":
        out.extend([
            "\t\t\tpnpm install --frozen-lockfile || pnpm install --no-frozen-lockfile ; \\\n",
            "\t\t\tsed -i \"/@daeuniverse\\\\/dae-editor/a\\\\        '@daeuniverse/dae-lang-core': path.resolve(__dirname, '../../packages/dae-lang-core/src/index.ts'),\\\\n        '@daeuniverse/dae-lsp/server/browser': path.resolve(__dirname, '../../packages/dae-lsp/src/browser-server.ts'),\" apps/web/vite.config.ts ; \\\n",
        ])
        patched_install = True
        continue
    if stripped == "pnpm build --filter daed ; \\":
        out.extend([
            "\t\t\tpnpm --filter @daeuniverse/dae-lang-core build ; \\\n",
            "\t\t\tpnpm --filter @daeuniverse/dae-node-parser build ; \\\n",
            "\t\t\tpnpm --filter @daeuniverse/dae-lsp build ; \\\n",
            "\t\t\tpnpm --filter @daeuniverse/dae-editor build ; \\\n",
            "\t\t\tpnpm -C apps/web build ; \\\n",
        ])
        patched_build = True
        continue
    if "cp -rf $(DAED_BUILD_DIR)/apps/web/dist/* $(PKG_BUILD_DIR)/webrender/web" in line:
        out.extend([
            "\t\tcp -rf $(DAED_BUILD_DIR)/apps/web/dist/. $(PKG_BUILD_DIR)/webrender/web ; \\\n",
            "\t\ttest -s $(PKG_BUILD_DIR)/webrender/web/index.html || { echo \"ERROR: daed web assets were not generated\"; find $(DAED_BUILD_DIR)/apps -maxdepth 4 -type f | sort | tail -200; exit 1; } ; \\\n",
            "\t\tfind $(PKG_BUILD_DIR)/webrender/web -type f -print -quit | grep -q . || { echo \"ERROR: dae-wing webrender/web is empty\"; exit 1; } ; \\\n",
            "\t\tif grep -RInE \"^[[:space:]]*import[[:space:]]+(.*from[[:space:]]+)?[\\\"'][^./][^\\\"']*[\\\"']\" $(PKG_BUILD_DIR)/webrender/web/assets/*.js 2>/dev/null ; then echo \"ERROR: daed web assets contain browser-side bare module imports\"; exit 1; fi ; \\\n",
        ])
        patched_copy = True
        continue
    out.append(line)

missing = []
if not patched_install:
    missing.append("pnpm install")
if not patched_build:
    missing.append("pnpm build --filter daed")
if not patched_copy:
    missing.append("daed web asset copy")
if missing:
    raise SystemExit("ERROR: failed to patch daed Makefile sections: " + ", ".join(missing))

path.write_text("".join(out))
PY
grep -Fq 'pnpm -C apps/web build' package/porxy/daed/Makefile || {
  echo "ERROR: failed to patch daed web build command"
  exit 1
}
grep -Fq 'pnpm --filter @daeuniverse/dae-lsp build' package/porxy/daed/Makefile || {
  echo "ERROR: failed to patch daed workspace package build command"
  exit 1
}
grep -Fq '@daeuniverse/dae-lsp/server/browser' package/porxy/daed/Makefile || {
  echo "ERROR: failed to patch daed vite aliases"
  exit 1
}
grep -Fq 'browser-side bare module imports' package/porxy/daed/Makefile || {
  echo "ERROR: failed to patch daed browser asset validation"
  exit 1
}

# daed listens on plain HTTP by default. If LuCI is opened over HTTPS, the
# upstream iframe helper inherits the HTTPS scheme and points the browser at
# https://router:2023, which fails because daed is not serving TLS.
if [ -f package/porxy/luci-app-daed/luasrc/view/daed/daed.htm ]; then
  sed -i "s/var protocol = window.location.protocol;/var protocol = 'http:';/" \
    package/porxy/luci-app-daed/luasrc/view/daed/daed.htm
fi

# Keep the original daed dashboard assets embedded in dae-wing. QiuSimons'
# Makefile gzips larger JS/CSS assets and may remove the original files; on
# some builds the embedded dashboard then opens as a blank white page because
# the internal HTTP server/browser path does not serve those compressed assets
# correctly.
python3 - <<'PY'
from pathlib import Path

path = Path("package/porxy/daed/Makefile")
lines = path.read_text().splitlines(keepends=True)
out = []
removed = False
i = 0

while i < len(lines):
    line = lines[i]
    if "find $(PKG_BUILD_DIR)/webrender/web -type f -size +4k" in line:
        out.append('\t\techo "Keeping uncompressed daed dashboard assets for embedded web UI" ; \\\n')
        removed = True
        i += 1
        while i < len(lines):
            if lines[i].lstrip().startswith('";" ;'):
                i += 1
                break
            i += 1
        continue
    out.append(line)
    i += 1

if not removed:
    raise SystemExit("ERROR: failed to find daed dashboard asset gzip/delete rule")

path.write_text("".join(out))
PY
if grep -Fq 'webrender/web -type f -size +4k' package/porxy/daed/Makefile; then
  echo "ERROR: failed to remove daed dashboard asset gzip/delete rule"
  exit 1
fi

rm -rf feeds/luci/applications/{luci-app-dockerman,luci-app-samba4,luci-app-aria2,luci-app-diskman}
rm -rf feeds/packages/net/{samba4,v2ray-geodata,mosdns,sing-box,aria2,ariang,adguardhome}

# drop attendedsysupgrade
sed -i '/luci-app-attendedsysupgrade/d' \
    feeds/luci/collections/luci-nginx/Makefile \
    feeds/luci/collections/luci-ssl-openssl/Makefile \
    feeds/luci/collections/luci-ssl/Makefile \
    feeds/luci/collections/luci/Makefile
    
sed -i 's/+uhttpd /+luci-nginx /g' feeds/luci/collections/luci/Makefile
sed -i 's/+uhttpd-mod-ubus //' feeds/luci/collections/luci/Makefile
sed -i 's/+uhttpd /+luci-nginx /g' feeds/luci/collections/luci-light/Makefile
sed -i "s/+luci /+luci-nginx /g" feeds/luci/collections/luci-ssl-openssl/Makefile
sed -i "s/+luci /+luci-nginx /g" feeds/luci/collections/luci-ssl/Makefile
sed -i 's/+uhttpd +uhttpd-mod-ubus /+luci-nginx /g' feeds/packages/net/wg-installer/Makefile
sed -i '/uhttpd-mod-ubus/d' feeds/luci/collections/luci-light/Makefile
sed -i 's/+luci-nginx \\$/+luci-nginx/' feeds/luci/collections/luci-light/Makefile

pushd feeds/luci || exit 1
for patch in *.patch; do
    [ -f "$patch" ] || continue

    apply_patch_once "$patch" || {
        popd
        exit 1
    }
done
popd

filogic_mk="target/linux/mediatek/image/filogic.mk"
if ! grep -q "Device/jcg_q30-pro" "$filogic_mk"; then
    awk '
        /define Device\/openwrt_one/ && !inserted {
            print ""
            print "define Build/jcg-q30-pro-sysupgrade-bin"
            print "\tsh $(TOPDIR)/scripts/sysupgrade-tar.sh \\"
            print "\t\t--board $(if $(BOARD_NAME),$(BOARD_NAME),$(DEVICE_NAME)) \\"
            print "\t\t--kernel $@ \\"
            print "\t\t--rootfs $(IMAGE_ROOTFS) \\"
            print "\t\t$@.tar"
            print "\tmv $@.tar $@"
            print "endef"
            print ""
            print "define Device/jcg_q30-pro"
            print "  DEVICE_VENDOR := JCG"
            print "  DEVICE_MODEL := Q30 PRO"
            print "  DEVICE_DTS := mt7981b-jcg-q30-pro"
            print "  DEVICE_DTS_DIR := ../dts"
            print "  UBINIZE_OPTS := -E 5"
            print "  BLOCKSIZE := 128k"
            print "  PAGESIZE := 2048"
            print "  KERNEL_IN_UBI := 1"
            print "  UBOOTENV_IN_UBI := 1"
            print "  IMAGES := sysupgrade.bin sysupgrade.itb"
            print "  KERNEL := kernel-bin | gzip | \\"
            print "\tpad-to 64k"
            print "  IMAGE/sysupgrade.bin := append-kernel | \\"
            print "\tfit gzip $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb | \\"
            print "\tjcg-q30-pro-sysupgrade-bin | append-metadata"
            print "  IMAGE/sysupgrade.itb := append-kernel | \\"
            print "\tfit gzip $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb external-static-with-rootfs | append-metadata"
            print "  DEVICE_PACKAGES :="
            print "  ARTIFACTS := preloader.bin bl31-uboot.fip"
            print "  ARTIFACT/preloader.bin := mt7981-bl2 spim-nand-ddr3"
            print "  ARTIFACT/bl31-uboot.fip := mt7981-bl31-uboot jcg_q30-pro"
            print "endef"
            print "TARGET_DEVICES += jcg_q30-pro"
            print ""
            inserted = 1
        }
        { print }
    ' "$filogic_mk" > "$filogic_mk.tmp"
    mv "$filogic_mk.tmp" "$filogic_mk"
fi

for patch in *.patch; do
    [ -f "$patch" ] || continue

    if [ "$patch" = "005-mediatek-filogic-add-jcg-q30-pro.patch" ]; then
        echo "Skipping $patch: JCG Q30 PRO profile is managed by sh/op.sh"
        continue
    fi

    apply_patch_once "$patch" || {
        exit 1
    }
done


# rust
RUST_VERSION=1.95.0
RUST_HASH=62b67230754da642a264ca0cb9fc08820c54e2ed7b3baba0289876d4cdb48c08
sed -ri "s/(PKG_VERSION:=)[^\"]*/\1$RUST_VERSION/;s/(PKG_HASH:=)[^\"]*/\1$RUST_HASH/" feeds/packages/lang/rust/Makefile

# fstools
rm -rf package/system/fstools
git clone https://github.com/sbwml/package_system_fstools -b openwrt-25.12 package/system/fstools
# util-linux
rm -rf package/utils/util-linux
git clone https://github.com/sbwml/package_utils_util-linux -b openwrt-25.12 package/utils/util-linux

# nghttp3
rm -rf feeds/packages/libs/nghttp3
git clone https://github.com/sbwml/package_libs_nghttp3 package/libs/nghttp3

# ngtcp2
rm -rf feeds/packages/libs/ngtcp2
git clone https://github.com/sbwml/package_libs_ngtcp2 package/libs/ngtcp2

# curl - fix passwall `time_pretransfer` check
rm -rf feeds/packages/net/curl
git clone https://github.com/sbwml/feeds_packages_net_curl feeds/packages/net/curl

# nginx - latest version
rm -rf feeds/packages/net/nginx
git clone https://github.com/sbwml/feeds_packages_net_nginx feeds/packages/net/nginx -b openwrt-25.12
sed -i 's/procd_set_param stdout 1/procd_set_param stdout 0/g;s/procd_set_param stderr 1/procd_set_param stderr 0/g' feeds/packages/net/nginx/files/nginx.init

# nginx - ubus
sed -i 's/ubus_parallel_req 2/ubus_parallel_req 6/g' feeds/packages/net/nginx/files-luci-support/60_nginx-luci-support
sed -i '/ubus_parallel_req/a\        ubus_script_timeout 300;' feeds/packages/net/nginx/files-luci-support/60_nginx-luci-support

# nginx-util
sed -i '/\/etc\/nginx\/uci.conf.template/d' feeds/packages/net/nginx-util/Makefile

# uwsgi - fix timeout
sed -i '$a cgi-timeout = 600' feeds/packages/net/uwsgi/files-luci-support/luci-*.ini
sed -i '/limit-as/c\limit-as = 5000' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
# disable error log
sed -i "s/procd_set_param stderr 1/procd_set_param stderr 0/g" feeds/packages/net/uwsgi/files/uwsgi.init

# uwsgi - performance
sed -i 's/threads = 1/threads = 2/g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
sed -i 's/processes = 3/processes = 4/g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
sed -i 's/cheaper = 1/cheaper = 2/g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini

# rpcd - fix timeout
sed -i 's/option timeout 30/option timeout 60/g' package/system/rpcd/files/rpcd.config
sed -i 's#20) \* 1000#60) \* 1000#g' feeds/luci/modules/luci-base/htdocs/luci-static/resources/rpc.js

# luci-compat - remove extra line breaks from description
sed -i '/<br \/>/d' feeds/luci/modules/luci-compat/luasrc/view/cbi/full_valuefooter.htm


#golang 26.x
rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang -b 26.x feeds/packages/lang/golang

./scripts/feeds update -a
./scripts/feeds install -a

sed -i 's|/bin/login|/bin/login -f root|g' feeds/packages/utils/ttyd/files/ttyd.config


sudo rm -rf package/base-files/files/etc/banner

sed -i "s/%D %V %C/%D %V $(TZ=UTC-8 date +%Y.%m.%d)/" package/base-files/files/etc/openwrt_release

sed -i "s/%R/by $OP_author/" package/base-files/files/etc/openwrt_release

date=$(date +"%Y-%m-%d")


echo "                                                    " >> package/base-files/files/etc/banner
echo "  _______                     ________        __" >> package/base-files/files/etc/banner
echo " |       |.-----.-----.-----.|  |  |  |.----.|  |_" >> package/base-files/files/etc/banner
echo " |   -   ||  _  |  -__|     ||  |  |  ||   _||   _|" >> package/base-files/files/etc/banner
echo " |_______||   __|_____|__|__||________||__|  |____|" >> package/base-files/files/etc/banner
echo "          |__|" >> package/base-files/files/etc/banner
echo " -----------------------------------------------------" >> package/base-files/files/etc/banner
echo "         %D ${date} by $OP_author                     " >> package/base-files/files/etc/banner
echo " -----------------------------------------------------" >> package/base-files/files/etc/banner
