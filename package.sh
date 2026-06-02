#!/bin/bash
# Packages scattrd.app into distributable .zip and .dmg files under dist/.
set -euo pipefail
cd "$(dirname "$0")"

[ -d scattrd.app ] || ./build_app.sh

mkdir -p dist
rm -f dist/scattrd.zip dist/scattrd.dmg

echo "▶ Creating dist/scattrd.zip …"
# ditto preserves the bundle structure + code signature (better than `zip`).
ditto -c -k --keepParent scattrd.app dist/scattrd.zip

echo "▶ Creating dist/scattrd.dmg …"
STAGE="$(mktemp -d)"
cp -R scattrd.app "$STAGE/scattrd.app"
ln -s /Applications "$STAGE/Applications"          # drag-to-install target
hdiutil create -volname "scattrd" -srcfolder "$STAGE" \
    -ov -format UDZO dist/scattrd.dmg >/dev/null
rm -rf "$STAGE"

echo
echo "✓ Built:"
ls -lh dist/ | awk 'NR>1 {print "   "$9"  "$5}'
echo
echo "SHA-256:"
shasum -a 256 dist/scattrd.zip dist/scattrd.dmg | sed 's/^/   /'
