#!/bin/bash
# Removes what install-app.sh installed (also a copy from when the app was
# called ChaoticMusicPlayer). Your music, settings, library and
# playlists (~/.config and ~/.local/share/TunedChaos) are kept.
set -euo pipefail

id=io.github.chandandasgit.TunedChaos
data="${XDG_DATA_HOME:-$HOME/.local/share}"
target="$HOME/.local/opt/TunedChaos"

old=io.github.chandandasgit.ChaoticMusicPlayer
for file in "$data/applications/$id.desktop" "$data/icons/hicolor/scalable/apps/$id.svg" "$HOME/.local/bin/TunedChaos" "$target" \
            "$target.new" "$target.old" \
            "$data/applications/$old.desktop" "$data/icons/hicolor/scalable/apps/$old.svg" \
            "$HOME/.local/bin/ChaoticMusicPlayer" "$HOME/.local/opt/ChaoticMusicPlayer"; do
    if [ -e "$file" ]; then
        rm -rf -- "$file"
        echo "Removed $file"
    fi
done
command -v update-desktop-database >/dev/null && update-desktop-database -q "$data/applications" || true
echo "Your settings and library are still in ~/.config and ~/.local/share/TunedChaos."
