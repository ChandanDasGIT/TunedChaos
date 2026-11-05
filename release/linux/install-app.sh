#!/bin/bash
# Installs Tuned Chaos for your user (no administrator rights needed):
#   the app in ~/.local/opt/TunedChaos, the TunedChaos command
#   in ~/.local/bin, a launcher entry and its icon. (Not in ~/.local/share/
#   TunedChaos: that holds your library and playlists.)
# Run it from the unpacked folder: ./install-app.sh. Running it again updates
# the app (the app's own updater runs it too); until the new copy is complete,
# the old one stays as it was. Remove it with ./uninstall-app.sh (your music,
# settings and library stay).
set -euo pipefail

id=io.github.chandandasgit.TunedChaos
here="$(cd "$(dirname "$0")" && pwd)"
target="$HOME/.local/opt/TunedChaos"
data="${XDG_DATA_HOME:-$HOME/.local/share}"
bin="$HOME/.local/bin"
apps="$data/applications"
icons="$data/icons/hicolor/scalable/apps"

if [ ! -x "$here/app/AppRun" ]; then
    echo "Run this from the unpacked TunedChaos folder (app/AppRun is missing)." >&2
    exit 1
fi

# The app. The new copy goes next to the old one first and replaces it only
# once it's complete, so a failed copy (disk full...) leaves the old one working.
next="$target.new"
previous="$target.old"
restore() {
    rm -rf "$next"
    # (stopped between the two moves: the old copy goes back)
    if [ ! -e "$target" ] && [ -e "$previous" ]; then
        mv "$previous" "$target"
    fi
}
swapped=0
trap 'status=$?
if [ $status -ne 0 ]; then
    if [ $swapped = 1 ]; then
        echo "The app is installed, but its menu entry or command couldn'"'"'t be set up." >&2
    else
        restore
        echo "Not installed: the app you had is unchanged." >&2
    fi
fi' EXIT

rm -rf "$next" "$previous"
mkdir -p "$next"
cp -a "$here/app/." "$next/"
if [ ! -x "$next/AppRun" ] || [ ! -x "$next/usr/bin/TunedChaos" ] \
    || [ "$(cd "$here/app" && find . | wc -l)" != "$(cd "$next" && find . | wc -l)" ]; then
    echo "The copy is incomplete." >&2
    exit 1
fi
if [ -e "$target" ]; then
    mv "$target" "$previous"
fi
mv "$next" "$target"
swapped=1
rm -rf "$previous" # (a running copy carries on: its files stay until it closes)

# One from when it was called ChaoticMusicPlayer goes
old="io.github.chandandasgit.ChaoticMusicPlayer"
rm -rf "$HOME/.local/opt/ChaoticMusicPlayer" "$bin/ChaoticMusicPlayer" "$apps/$old.desktop" "$icons/$old.svg"

# Launcher entry and icon. Desktop files quote with "…"; inside, \ " ` $ are escaped.
quoted="\"$(printf '%s' "$target/AppRun" | sed -e 's/[\\"`$]/\\&/g')\""
sedEscape() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }
mkdir -p "$apps" "$icons"
# (keeps what follows the command: %U, the files to open)
sed -e "s|^Exec=[^ ]*|Exec=$(sedEscape "$quoted")|" "$target/usr/share/applications/$id.desktop" > "$apps/$id.desktop"
chmod 644 "$apps/$id.desktop"
install -m644 "$target/usr/share/icons/hicolor/scalable/apps/$id.svg" "$icons/$id.svg"
command -v update-desktop-database >/dev/null && update-desktop-database -q "$apps" || true

# The TunedChaos command
mkdir -p "$bin"
ln -sf "$target/AppRun" "$bin/TunedChaos"

echo "Tuned Chaos is installed."
echo "  Program : $target"
echo "  Command : $bin/TunedChaos"
echo "  Menu    : $apps/$id.desktop"
case ":$PATH:" in
    *":$bin:"*) ;;
    *) echo "Note: $bin is not on your PATH, so the TunedChaos command works only once you add it." ;;
esac
