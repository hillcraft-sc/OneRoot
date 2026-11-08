#!/bin/sh
# Installs OneRoot from the unpacked release tarball.
#
#   ./install.sh               install for you, under ~/.local
#   sudo ./install.sh --system install for everyone, under /usr/local
#   ./install.sh --uninstall   remove it (add --system if you installed that way)
#
# Needs GTK 4 and libadwaita 1.7+, GtkSourceView 5, libxml2, libcurl and bsdtar (libarchive).
set -eu

here=$(cd "$(dirname "$0")" && pwd)
prefix=$HOME/.local
uninstall=0
for arg in "$@"; do
    case $arg in
        --system) prefix=/usr/local ;;
        --uninstall) uninstall=1 ;;
        -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

id=com.hillcraft_sc.OneRoot
bin=$prefix/bin/oneroot
desktop=$prefix/share/applications/$id.desktop
metainfo=$prefix/share/metainfo/$id.metainfo.xml
icon=$prefix/share/icons/hicolor/256x256/apps/$id.png
# Tells the app it was installed by this script, so it (alone) checks GitHub for updates.
marker=$prefix/share/oneroot/install-method

refresh() {
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$prefix/share/applications" 2>/dev/null || true
    command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t "$prefix/share/icons/hicolor" 2>/dev/null || true
}

if [ $uninstall = 1 ]; then
    rm -f "$bin" "$desktop" "$metainfo" "$icon" "$marker"
    rmdir "$prefix/share/oneroot" 2>/dev/null || true
    refresh
    echo "Removed OneRoot from $prefix"
    exit 0
fi

for f in oneroot $id.desktop $id.metainfo.xml $id.png; do
    [ -f "$here/$f" ] || { echo "Missing $f: run this from the unpacked OneRoot folder." >&2; exit 1; }
done

install -Dm755 "$here/oneroot" "$bin"
install -Dm644 "$here/$id.desktop" "$desktop"
# Launchers often don't have ~/.local/bin on their PATH, so name the binary by its full path.
sed "s|^Exec=oneroot|Exec=$bin|" "$here/$id.desktop" > "$desktop"
install -Dm644 "$here/$id.metainfo.xml" "$metainfo"
install -Dm644 "$here/$id.png" "$icon"
mkdir -p "$(dirname "$marker")"
printf 'tarball\n' > "$marker"
refresh
echo "Installed OneRoot to $prefix"
case :$PATH: in *:$prefix/bin:*) ;; *) echo "Note: $prefix/bin isn't on your PATH; start OneRoot from your app launcher." ;; esac
