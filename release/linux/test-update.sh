#!/bin/bash
# The in-app update, tested on the real packages (CI runs it on every release,
# in an old and a new distro: .github/workflows/build.yml). Each package is
# installed as a user would, then updates itself through its own launcher, so
# with the launcher's environment (its bundled libraries): how the 1.1.6
# updater broke on newer systems, where only a local build had been tried.
#   release/linux/test-update.sh <folder with the .tar.xz and .AppImage>
# Uses a throwaway home folder; needs tar and xz (as every system has).
set -euo pipefail

packages="$(cd "$1" && pwd)"
tarball="$(ls "$packages"/TunedChaos-*-linux-x86_64.tar.xz | sort -V | tail -1)"
appimage="$(ls "$packages"/TunedChaos-*-x86_64.AppImage | sort -V | tail -1)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export HOME="$work/home" XDG_DATA_HOME="$work/home/.local/share" XDG_CACHE_HOME="$work/home/.cache"
export XDG_CONFIG_HOME="$work/home/.config"
export APPIMAGE_EXTRACT_AND_RUN=1 # (no FUSE in containers)
mkdir -p "$HOME"

fail() { echo "FAILED: $*" >&2; exit 1; }

# ------------------------------------------------------------ the tarball
echo "== Tarball: $(basename "$tarball")"
mkdir "$work/unpacked"
tar -xJf "$tarball" -C "$work/unpacked"
bash "$(ls "$work"/unpacked/*/install-app.sh)"
launcher="$HOME/.local/bin/TunedChaos"
[ -x "$launcher" ] || fail "install-app.sh made no TunedChaos command"

# Twice: the second time, the copy the first update installed updates itself
for round in 1 2; do
    cp "$tarball" "$work/update.tar.xz"
    echo "-- update $round, through $launcher"
    "$launcher" --install-update "$work/update.tar.xz" || fail "the tarball's update (round $round)"
    [ -x "$HOME/.local/opt/TunedChaos/AppRun" ] || fail "no app after the update (round $round)"
    [ ! -e "$HOME/.local/opt/TunedChaos.new" ] && [ ! -e "$HOME/.local/opt/TunedChaos.old" ] \
        || fail "the update left a copy behind (round $round)"
    [ ! -e "$work/update.tar.xz" ] || fail "the download wasn't removed (round $round)"
done

# ------------------------------------------------------------ the AppImage
echo "== AppImage: $(basename "$appimage")"
mkdir -p "$HOME/Applications"
installed="$HOME/Applications/TunedChaos.AppImage"
cp "$appimage" "$installed"
chmod +x "$installed"
printf 'not the app\n' >> "$installed" # (so the update visibly replaces it)
cp "$appimage" "$work/update.AppImage"
"$installed" --install-update "$work/update.AppImage" || fail "the AppImage's update"
cmp -s "$appimage" "$installed" || fail "the AppImage wasn't replaced"
[ -x "$installed" ] || fail "the new AppImage can't be started"
[ ! -e "$HOME/Applications/.TunedChaos-update.AppImage" ] || fail "the AppImage's update left a copy behind"

echo "== Updates work"
