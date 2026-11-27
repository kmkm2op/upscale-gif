#!/usr/bin/env bash
# Install upscale-gif for the current user (no root needed):
#   ~/.local/share/upscale-gif     the program, upscaler, ffmpeg and models
#   ~/.local/bin/upscale-gif       the command
#   an "Upscale GIF" entry in the application menu, "Open with" for animations and videos,
#   a Dolphin right-click action, and a desktop shortcut
#
#   ./install.sh               install or update
#   ./install.sh --uninstall   remove everything again
set -euo pipefail

SRC=$(cd "$(dirname "$0")" && pwd)
DATA=${XDG_DATA_HOME:-$HOME/.local/share}
DEST=$DATA/upscale-gif
BIN=$HOME/.local/bin
APPS=$DATA/applications
SERVICEMENUS=$DATA/kio/servicemenus
DESKTOP=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")
MIME="image/gif;image/webp;image/apng;image/png;image/avif;video/mp4;video/webm;video/x-matroska;video/quicktime;"

files=("$BIN/upscale-gif" "$APPS/upscale-gif.desktop" "$SERVICEMENUS/upscale-gif.desktop" "$DESKTOP/upscale-gif.desktop")

if [[ ${1:-} == --uninstall ]]; then
    rm -f "${files[@]}"
    rm -rf "$DEST"
    command -v update-desktop-database >/dev/null && update-desktop-database -q "$APPS" 2>/dev/null || true
    echo "upscale-gif has been removed. (Your settings in ~/.config/upscale-gif.conf were kept.)"
    exit 0
fi

[[ -x $SRC/bin/upscayl-bin && -x $SRC/bin/ffmpeg ]] || { echo "Run this from the extracted upscale-gif folder." >&2; exit 1; }

echo "Installing to $DEST"
mkdir -p "$DATA" "$BIN" "$APPS" "$SERVICEMENUS"
if [[ $SRC != "$DEST" ]]; then
    rm -rf "$DEST.new"
    cp -r "$SRC" "$DEST.new"
    rm -rf "$DEST"
    mv "$DEST.new" "$DEST"
fi
ln -sf "$DEST/upscale-gif" "$BIN/upscale-gif"

entry() {   # entry FILE: an application entry that takes one file
    cat >"$1" <<EOF
[Desktop Entry]
Type=Application
Name=Upscale GIF
GenericName=Animation upscaler
Comment=Upscale an animation or video with AI
Exec="$DEST/upscale-gif" %f
Icon=$DEST/icon.svg
Terminal=false
Categories=Graphics;
MimeType=$MIME
EOF
}
entry "$APPS/upscale-gif.desktop"
if [[ -d $DESKTOP ]]; then
    entry "$DESKTOP/upscale-gif.desktop"
    chmod +x "$DESKTOP/upscale-gif.desktop"
    # GNOME only starts desktop launchers that are marked as trusted
    command -v gio >/dev/null && gio set "$DESKTOP/upscale-gif.desktop" metadata::trusted true 2>/dev/null || true
fi
cat >"$SERVICEMENUS/upscale-gif.desktop" <<EOF
[Desktop Entry]
Type=Service
X-KDE-ServiceTypes=KonqPopupMenu/Plugin
MimeType=$MIME
Actions=upscale

[Desktop Action upscale]
Name=Upscale with Upscale GIF
Icon=$DEST/icon.svg
Exec="$DEST/upscale-gif" %f
EOF
chmod +x "$SERVICEMENUS/upscale-gif.desktop"   # KDE 6 requires this
command -v update-desktop-database >/dev/null && update-desktop-database -q "$APPS" 2>/dev/null || true

# Check what can't be bundled
problems=()
command -v zenity >/dev/null || problems+=("zenity is missing, so the windows can't open (command-line use still works).
  Install it with your package manager, e.g. sudo apt install zenity / sudo dnf install zenity / sudo pacman -S zenity")
[[ $("$DEST/bin/upscayl-bin" -h 2>&1) == *model-scale* ]] \
    || problems+=("The upscaler can't start: $("$DEST/bin/upscayl-bin" -h 2>&1 | head -1)
  It needs glibc 2.35+ (Ubuntu 22.04, Debian 12, Fedora 36 or newer), libgomp and the Vulkan loader
  (e.g. sudo apt install libgomp1 libvulkan1 / sudo dnf install libgomp vulkan-loader)")
if ! check=$("$DEST/upscale-gif" -c 2>&1); then
    if [[ $check == *"NONE FOUND"* ]]; then
        problems+=("$(sed -n '/NONE FOUND/,/vulkaninfo/{/NONE FOUND/d; s/^  //; p}' <<<"$check")")
    else
        problems+=("Some checks failed; run: upscale-gif -c")
    fi
fi

echo
echo "Installed. Start \"Upscale GIF\" from the application menu or the desktop, right-click an"
echo "animation and choose Open with > Upscale GIF, or run: upscale-gif [file]"
[[ :$PATH: == *":$BIN:"* ]] || echo "(Add $BIN to your PATH to use the upscale-gif command.)"
for p in "${problems[@]}"; do printf '\nNote: %s\n' "$p"; done
