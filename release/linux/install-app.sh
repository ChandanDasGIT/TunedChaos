#!/bin/bash
# Installs Tuned Chaos for your user (no administrator rights needed):
#   the app in ~/.local/opt/TunedChaos, the TunedChaos command
#   in ~/.local/bin, a launcher entry and its icon. (Not in ~/.local/share/
#   TunedChaos: that holds your library and playlists.)
# Run it from the unpacked folder: ./install-app.sh. Running it again updates
# the app. Remove it with ./uninstall-app.sh (your music, settings and library stay).
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

# The app (an older copy is replaced; so is one from when it was called ChaoticMusicPlayer)
rm -rf "$target"
old="io.github.chandandasgit.ChaoticMusicPlayer"
rm -rf "$HOME/.local/opt/ChaoticMusicPlayer" "$bin/ChaoticMusicPlayer" "$apps/$old.desktop" "$icons/$old.svg"
mkdir -p "$target"
cp -a "$here/app/." "$target/"

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
