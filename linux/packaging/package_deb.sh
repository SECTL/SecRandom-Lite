#!/usr/bin/env bash
#
# Build a Debian package from a Flutter Linux release bundle.
#
# Layout produced by this script:
#   /usr/lib/secrandom-lite/          application binary, data and plugins
#   /usr/bin/secrandom-lite           launcher for the bundled binary
#   /usr/share/applications/          desktop entry
#   /usr/share/icons/hicolor/         application icon
#   /usr/share/doc/secrandom-lite/    copyright, changelog and MiSans notice
#
# Usage:
#   linux/packaging/package_deb.sh --version 1.0.2 --arch amd64 \
#       --bundle build/linux/x64/release/bundle \
#       --output build/SecRandom_Lite_1.0.2_linux_amd64.deb

set -euo pipefail

usage() {
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

VERSION=""
ARCH=""
BUNDLE=""
OUTPUT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --version)
            VERSION="${2:-}"
            shift 2
            ;;
        --arch)
            ARCH="${2:-}"
            shift 2
            ;;
        --bundle)
            BUNDLE="${2:-}"
            shift 2
            ;;
        --output)
            OUTPUT="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [ -z "$VERSION" ]; then
    echo "error: --version is required" >&2
    exit 2
fi

case "$VERSION" in
    *[!0-9A-Za-z.+~-]*|"")
        echo "error: invalid version: $VERSION" >&2
        exit 2
        ;;
esac

# The artifact keeps the upstream version, while the Debian package gets a
# revision so changelogs and future packaging updates have room to grow.
PACKAGE_VERSION="${VERSION}-1"

for tool in patchelf strip; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "error: $tool is required (install binutils and patchelf)" >&2
        exit 1
    fi
done

case "$ARCH" in
    amd64) FLUTTER_ARCH=x64 ;;
    arm64) FLUTTER_ARCH=arm64 ;;
    *)
        echo "error: --arch must be amd64 or arm64" >&2
        exit 2
        ;;
esac

if [ -z "$BUNDLE" ]; then
    BUNDLE="$REPO_ROOT/build/linux/$FLUTTER_ARCH/release/bundle"
fi

if [ ! -x "$BUNDLE/secrandom_lite" ]; then
    echo "error: no Flutter Linux bundle at $BUNDLE" >&2
    echo "       run 'flutter build linux --release' first, or pass --bundle" >&2
    exit 1
fi

if [ -z "$OUTPUT" ]; then
    OUTPUT="$REPO_ROOT/build/SecRandom_Lite_${VERSION}_linux_${ARCH}.deb"
fi
mkdir -p -- "$(dirname -- "$OUTPUT")"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/secrandom-deb.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT

PKGROOT="$WORK/pkg"
install -d \
    "$PKGROOT/DEBIAN" \
    "$PKGROOT/usr/bin" \
    "$PKGROOT/usr/lib/secrandom-lite" \
    "$PKGROOT/usr/share/applications" \
    "$PKGROOT/usr/share/icons/hicolor/512x512/apps" \
    "$PKGROOT/usr/share/doc/secrandom-lite" \
    "$PKGROOT/usr/share/man/man1" \
    "$PKGROOT/usr/share/lintian/overrides"

# Application files keep their relative layout so the $ORIGIN/lib RPATH works.
cp -a "$BUNDLE/." "$PKGROOT/usr/lib/secrandom-lite/"
chmod 0755 "$PKGROOT/usr/lib/secrandom-lite/secrandom_lite"
install -m 0755 "$SCRIPT_DIR/debian/secrandom-lite.sh" \
    "$PKGROOT/usr/bin/secrandom-lite"

# Flutter links plugin libraries with a build-tree RUNPATH. Replace it with
# $ORIGIN so the installed package never refers back to the build directory.
find "$PKGROOT/usr/lib/secrandom-lite/lib" -maxdepth 1 -name '*.so' \
    ! -name 'libapp.so' -print0 |
    while IFS= read -r -d '' lib; do
        patchelf --set-rpath '$ORIGIN' "$lib"
    done

# libapp.so is a Dart AOT snapshot, not a regular shared object, so leave it
# alone. Everything else can lose its debug symbols.
strip --strip-unneeded "$PKGROOT/usr/lib/secrandom-lite/secrandom_lite"
find "$PKGROOT/usr/lib/secrandom-lite/lib" -maxdepth 1 -name '*.so' \
    ! -name 'libapp.so' -exec strip --strip-unneeded {} +

install -m 0644 "$SCRIPT_DIR/debian/secrandom-lite.desktop" \
    "$PKGROOT/usr/share/applications/secrandom-lite.desktop"
install -m 0644 "$SCRIPT_DIR/icons/secrandom-lite-512.png" \
    "$PKGROOT/usr/share/icons/hicolor/512x512/apps/secrandom-lite.png"
install -m 0644 "$SCRIPT_DIR/debian/copyright" \
    "$PKGROOT/usr/share/doc/secrandom-lite/copyright"
install -m 0644 "$REPO_ROOT/assets/fonts/MiSans-NOTICE.txt" \
    "$PKGROOT/usr/share/doc/secrandom-lite/MiSans-NOTICE.txt"
install -m 0644 "$SCRIPT_DIR/debian/secrandom-lite.1" \
    "$PKGROOT/usr/share/man/man1/secrandom-lite.1"
gzip -9n "$PKGROOT/usr/share/man/man1/secrandom-lite.1"
install -m 0644 "$SCRIPT_DIR/debian/lintian-overrides" \
    "$PKGROOT/usr/share/lintian/overrides/secrandom-lite"

install -m 0755 "$SCRIPT_DIR/debian/postinst" "$PKGROOT/DEBIAN/postinst"
install -m 0755 "$SCRIPT_DIR/debian/postrm" "$PKGROOT/DEBIAN/postrm"

INSTALLED_SIZE="$(du -sk "$PKGROOT/usr" | cut -f1)"

{
    printf 'secrandom-lite (%s) unstable; urgency=medium\n\n' "$PACKAGE_VERSION"
    printf '  * Upstream release %s.\n\n' "$VERSION"
    printf ' -- LeafS825 <LeafS825@users.noreply.github.com>  %s\n' "$(date -R)"
} > "$PKGROOT/usr/share/doc/secrandom-lite/changelog.Debian"
gzip -9n "$PKGROOT/usr/share/doc/secrandom-lite/changelog.Debian"

sed \
    -e "s/@PACKAGE_VERSION@/$PACKAGE_VERSION/g" \
    -e "s/@ARCH@/$ARCH/g" \
    -e "s/@INSTALLED_SIZE@/$INSTALLED_SIZE/g" \
    "$SCRIPT_DIR/debian/control.in" > "$PKGROOT/DEBIAN/control"
chmod 0644 "$PKGROOT/DEBIAN/control"

(
    cd "$PKGROOT"
    find . -type f ! -path './DEBIAN/*' -printf '%P\0' \
        | sort -z \
        | xargs -0 md5sum
) > "$PKGROOT/DEBIAN/md5sums"

dpkg-deb --root-owner-group -Zxz --build "$PKGROOT" "$OUTPUT" >/dev/null

echo "Built: $OUTPUT"
