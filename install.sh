#!/bin/bash
# Builds scattrd and installs it to /Applications, then launches it.
# Run this after code changes to update the installed copy.
set -euo pipefail
cd "$(dirname "$0")"

./build_app.sh

DEST="/Applications/scattrd.app"
echo "▶ Installing to $DEST …"

# Stop any running instances (project-dir or installed) so the new one takes over.
pkill -f "scattrd.app/Contents/MacOS/scattrd" 2>/dev/null || true

if ! rm -rf "$DEST" 2>/dev/null; then
    echo "  Need elevated permission to write to /Applications…"
    sudo rm -rf "$DEST"
    sudo cp -R "scattrd.app" "$DEST"
else
    cp -R "scattrd.app" "$DEST"
fi

# Re-sign (ad-hoc) at the final path for a consistent bundle identity.
codesign --force --deep --sign - "$DEST" >/dev/null 2>&1 || true

echo "✓ Installed to /Applications."
echo "  Launching…"
open "$DEST"
echo
echo "  Next: click 🧠 → Launch at Login to keep it always-on."
echo "  First time you focus a browser, click OK on the 'control browser' prompt."
