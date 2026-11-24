#!/bin/sh
# build-apk.sh — assemble an ImmortalWrt / OpenWrt .apk using SDK's host apk tool
set -eu

BINARY="$1"
VERSION="$2"
ARCH="$3"       # e.g. x86_64
OUTDIR="$4"
APK_TOOL="${5:-apk}"

[ -f "$BINARY" ] || { echo "binary not found: $BINARY" >&2; exit 1; }
case "$VERSION" in
    v*) VERSION="${VERSION#v}" ;;
esac

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

ROOTFS="$WORK/rootfs"
SCRIPTS="$WORK/scripts"
mkdir -p "$ROOTFS/usr/bin" "$ROOTFS/etc/init.d" "$ROOTFS/etc/sing-box-easy" "$ROOTFS/etc/config" "$SCRIPTS"

install -m 755 "$BINARY" "$ROOTFS/usr/bin/sing-box-easy"
install -m 755 "$SCRIPT_DIR/files/sing-box-easy.init" "$ROOTFS/etc/init.d/sing-box-easy"
install -m 644 "$REPO_ROOT/app.yml.example" "$ROOTFS/etc/sing-box-easy/app.yml.example"
install -m 644 "$REPO_ROOT/app.yml.example" "$ROOTFS/etc/sing-box-easy/app.yml"
install -m 644 "$SCRIPT_DIR/files/uci-sing-box-easy" "$ROOTFS/etc/config/sing-box-easy"

# LuCI
mkdir -p "$ROOTFS/usr/share/luci/menu.d" \
         "$ROOTFS/usr/share/rpcd/acl.d" \
         "$ROOTFS/www/luci-static/resources/view/sing-box-easy"

install -m 644 "$SCRIPT_DIR/files/luci/menu.d/luci-app-sing-box-easy.json" \
    "$ROOTFS/usr/share/luci/menu.d/luci-app-sing-box-easy.json"
install -m 644 "$SCRIPT_DIR/files/luci/acl.d/luci-app-sing-box-easy.json" \
    "$ROOTFS/usr/share/rpcd/acl.d/luci-app-sing-box-easy.json"
install -m 644 "$SCRIPT_DIR/files/luci/view/sing-box-easy/panel.js" \
    "$ROOTFS/www/luci-static/resources/view/sing-box-easy/panel.js"

# Conffiles
mkdir -p "$ROOTFS/lib/apk/packages"
cat > "$ROOTFS/lib/apk/packages/sing-box-easy.conffiles" <<EOF
/etc/sing-box-easy/app.yml
/etc/config/sing-box-easy
EOF

# Maintainer scripts
cat > "$SCRIPTS/post-install" <<'EOS'
#!/bin/sh
[ -f /etc/sing-box-easy/app.yml ] || cp /etc/sing-box-easy/app.yml.example /etc/sing-box-easy/app.yml

if [ -z "${IPKG_INSTROOT:-}" ]; then
    if [ -x /sbin/uci ] || command -v uci >/dev/null 2>&1; then
        port=$(sed -n 's/^[[:space:]]*port:[[:space:]]*"\{0,1\}\([0-9]\{1,\}\)"\{0,1\}[[:space:]]*$/\1/p' \
            /etc/sing-box-easy/app.yml 2>/dev/null | head -n 1)
        if [ -n "$port" ]; then
            uci -q set sing-box-easy.main=sing-box-easy
            uci -q set sing-box-easy.main.port="$port"
            uci -q commit sing-box-easy
        fi
    fi

    [ -x /etc/init.d/rpcd ] && /etc/init.d/rpcd reload >/dev/null 2>&1
    rm -f /tmp/luci-indexcache* /tmp/luci-modulecache/* 2>/dev/null

    /etc/init.d/sing-box-easy enable
    /etc/init.d/sing-box-easy start
fi
exit 0
EOS

cat > "$SCRIPTS/pre-deinstall" <<'EOS'
#!/bin/sh
if [ -z "${IPKG_INSTROOT:-}" ]; then
    /etc/init.d/sing-box-easy stop || true
    /etc/init.d/sing-box-easy disable || true
fi
exit 0
EOS
chmod +x "$SCRIPTS/post-install" "$SCRIPTS/pre-deinstall"

mkdir -p "$OUTDIR"
APK_OUT="$OUTDIR/sing-box-easy_${VERSION}_${ARCH}.apk"

SOURCE_DATE_EPOCH=0 "$APK_TOOL" mkpkg \
  --info "name:sing-box-easy" \
  --info "version:$VERSION" \
  --info "description:Web panel for managing sing-box configurations and lifecycle" \
  --info "arch:$ARCH" \
  --info "license:GPL-3.0" \
  --info "maintainer:ywjdlq" \
  --script "post-install:$SCRIPTS/post-install" \
  --script "post-upgrade:$SCRIPTS/post-install" \
  --script "pre-deinstall:$SCRIPTS/pre-deinstall" \
  --files "$ROOTFS" \
  --output "$APK_OUT"

echo "Built APK: $APK_OUT"
EOF
chmod +x packaging/openwrt/build-apk.sh
