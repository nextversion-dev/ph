#!/usr/bin/env bash
#
# Build PharoNativeShell.app: a generic AppKit renderer that hosts widgets
# driven by a Pharo image over a localhost JSON-RPC connection.
#
# Outputs pharo-native-shell/build/PharoNativeShell.app.

set -eu

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P)"
ROOT_DIR="$(cd "${SCRIPTS_DIR}/.." ; pwd -P)"
SRC_DIR="${ROOT_DIR}/Sources/PharoNativeShell"
BUILD_DIR="${ROOT_DIR}/build"
APP_NAME="PharoNativeShell"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
EXEC_NAME="${APP_NAME}"

if ! command -v swiftc >/dev/null 2>&1; then
    echo "swiftc not found. Install Xcode Command Line Tools." >&2
    exit 1
fi

echo "Building ${APP_NAME}.app via swiftc"
echo "  src:    ${SRC_DIR}"
echo "  output: ${APP_BUNDLE}"

rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

SWIFT_FILES=$(find "${SRC_DIR}" -type f -name '*.swift' | sort)
if [ -z "${SWIFT_FILES}" ]; then
    echo "No Swift sources found under ${SRC_DIR}" >&2
    exit 1
fi

# shellcheck disable=SC2086
swiftc \
    -O \
    -target arm64-apple-macos13.0 \
    -framework AppKit \
    -framework Foundation \
    -framework Network \
    -o "${APP_BUNDLE}/Contents/MacOS/${EXEC_NAME}" \
    ${SWIFT_FILES}

cat > "${APP_BUNDLE}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${EXEC_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>org.pharo.native-shell</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>Pharo Native Shell</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
PLIST

printf 'APPL????' > "${APP_BUNDLE}/Contents/PkgInfo"

echo "Built: ${APP_BUNDLE}"
