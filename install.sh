#!/bin/bash
set -euo pipefail

APP_BUNDLE="/Applications/SetLeds.app"
PLIST_DEST="$HOME/Library/LaunchAgents/org.inonio.setleds.plist"
LABEL="org.inonio.setleds"

# Check for binary argument
if [[ $# -lt 1 ]]; then
  echo "Usage: ./install.sh <path-to-SetLeds-binary>"
  echo "Example: ./install.sh Source/build/Release/SetLeds"
  exit 1
fi

BINARY="$(stat -f "%N" "${1}")"

if [[ ! -f "${BINARY}" ]]; then
  echo "Error: No file found at ${BINARY}"
  exit 1
fi

# Unload existing agent if present
echo "Stopping existing agent (if any) .."
launchctl unload "${PLIST_DEST}" 2>/dev/null || true

# Create .app bundle (required for macOS Accessibility permissions)
echo "Creating app bundle at ${APP_BUNDLE} .."
mkdir -p "${APP_BUNDLE}/Contents/MacOS"

cp "${BINARY}" "${APP_BUNDLE}/Contents/MacOS/SetLeds"
chmod +x "${APP_BUNDLE}/Contents/MacOS/SetLeds"

cat > "${APP_BUNDLE}/Contents/Info.plist" <<'INFOPLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>SetLeds</string>
	<key>CFBundleIdentifier</key>
	<string>org.inonio.setleds</string>
	<key>CFBundleName</key>
	<string>SetLeds</string>
	<key>CFBundleVersion</key>
	<string>1.0</string>
	<key>LSUIElement</key>
	<true/>
</dict>
</plist>
INFOPLIST

# Code sign if a developer identity is available
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -1 | sed 's/.*"\(.*\)".*/\1/' || true)
if [[ -n "${IDENTITY}" ]]; then
  echo "Signing app bundle with: ${IDENTITY}"
  codesign --force --sign "${IDENTITY}" "${APP_BUNDLE}"
else
  echo "No Apple Development signing identity found, signing ad-hoc .."
  codesign --force --sign - "${APP_BUNDLE}"
fi

# Install LaunchAgent plist
echo "Installing LaunchAgent .."
mkdir -p "$HOME/Library/LaunchAgents"
sed -e "s|%%BINARYPATH%%|${APP_BUNDLE}/Contents/MacOS/SetLeds|g" \
  org.inonio.setleds.plist.template > "${PLIST_DEST}"

# Load and start
echo "Loading LaunchAgent .."
launchctl load -w "${PLIST_DEST}"

echo ""
echo "Done! SetLeds is now running as a user LaunchAgent."
echo ""
echo "IMPORTANT: If this is the first install, grant Accessibility permission:"
echo "  System Settings → Privacy & Security → Accessibility"
echo "  Click +, navigate to /Applications/SetLeds.app"
echo ""
echo "Logs: tail -f /tmp/setleds.stdout /tmp/setleds.stderr"
