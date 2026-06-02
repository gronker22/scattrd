#!/bin/bash
# Builds FocusTracker and wraps it into a double-clickable .app bundle.
#
# NOTE: This compiles with `swiftc` directly instead of SwiftPM. This machine's
# Command Line Tools are internally inconsistent (a partial update left SwiftPM's
# PackageDescription library mismatched, and a stale `module.modulemap` that
# duplicates `bridging.modulemap`). We work around the duplicate with a VFS
# overlay — see detect logic below. No system files are modified.
set -euo pipefail
cd "$(dirname "$0")"

SDK="$(xcrun --show-sdk-path)"
SWIFT_INC="$(xcode-select -p)/usr/include/swift"
BUILD_DIR=".build"
FIX_DIR="$BUILD_DIR/toolchain-fix"
mkdir -p "$BUILD_DIR"

# --- Work around the duplicate SwiftBridging modulemap, if present -----------
OVERLAY_ARGS=()
if [ -f "$SWIFT_INC/module.modulemap" ] && [ -f "$SWIFT_INC/bridging.modulemap" ] \
   && grep -q "SwiftBridging" "$SWIFT_INC/module.modulemap"; then
    echo "▶ Detected duplicate SwiftBridging modulemap — applying VFS overlay."
    mkdir -p "$FIX_DIR"
    EMPTY="$PWD/$FIX_DIR/empty.modulemap"
    OVERLAY="$PWD/$FIX_DIR/overlay.yaml"
    printf '// intentionally empty (overlay to dedupe SwiftBridging)\n' > "$EMPTY"
    cat > "$OVERLAY" <<JSON
{
  "version": 0,
  "case-sensitive": false,
  "roots": [
    { "type": "file",
      "name": "$SWIFT_INC/module.modulemap",
      "external-contents": "$EMPTY" }
  ]
}
JSON
    OVERLAY_ARGS=(-vfsoverlay "$OVERLAY")
fi

# --- Compile ----------------------------------------------------------------
BIN="$BUILD_DIR/scattrd"
echo "▶ Compiling (release)…"
swiftc -O \
    -target arm64-apple-macosx13.0 \
    -sdk "$SDK" \
    "${OVERLAY_ARGS[@]}" \
    -framework AppKit -framework IOKit -framework UserNotifications -framework ServiceManagement -framework WebKit -lsqlite3 \
    -o "$BIN" \
    Sources/FocusTracker/*.swift

# --- Wrap into an .app bundle -----------------------------------------------
APP="scattrd.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/scattrd"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>scattrd</string>
    <key>CFBundleDisplayName</key>     <string>scattrd</string>
    <key>CFBundleIdentifier</key>      <string>com.scattrd.app</string>
    <key>CFBundleExecutable</key>      <string>scattrd</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>CFBundleShortVersionString</key> <string>0.1</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
    <key>NSHumanReadableCopyright</key><string>scattrd — local-only focus tracker. Your data never leaves this Mac.</string>
    <key>NSAppleEventsUsageDescription</key><string>scattrd reads the active tab's web address in your browser to measure which sites fragment your focus. Only the domain is stored, locally on this Mac.</string>
</dict>
</plist>
PLIST

# Ad-hoc codesign so the menubar item and notifications behave.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "✓ Built $APP"
echo "  Run:  open $APP        (look for the 🧠 icon in the menubar)"
echo "  Quit: click the icon → Quit scattrd"
