#!/bin/bash
# Builds a proper "Desktop Bins Widget.app" bundle from the Swift package.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Desktop Bins Widget"
BUNDLE_ID="com.smanke.DesktopBinsWidget"
APP_DIR=".build/app/${APP_NAME}.app"

# Ask SwiftPM where this toolchain puts the product. The location has moved
# between toolchains (.build/apple/Products/Release, then .build/out/Products/
# Release with Swift 6.4), and an old toolchain's folder is left behind after an
# upgrade. Hardcoding the old path packaged a days-old binary inside freshly
# versioned 1.1.10 and 1.1.11 bundles: the version number changed, the code did not.
BIN_DIR=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)
UNIVERSAL_BIN="${BIN_DIR}/DesktopBinsWidget"

# Delete the product first, so whatever gets packaged was written by this run.
# Checking "newer than the sources" instead would refuse valid builds: SwiftPM
# doesn't relink when only a timestamp changes. With the old binary gone, even a
# no-op incremental build writes it again and passes the check below.
BUILD_STARTED=$(mktemp)
trap 'rm -f "${BUILD_STARTED}"' EXIT
# The check below compares whole seconds, and a no-op build can finish within
# the second the marker was made; step past it so a fresh binary always reads newer.
sleep 1
rm -f "${UNIVERSAL_BIN}"

echo "Building universal release binary (arm64 + x86_64)..."
swift build -c release --arch arm64 --arch x86_64

if [ ! -x "${UNIVERSAL_BIN}" ] || [ ! "${UNIVERSAL_BIN}" -nt "${BUILD_STARTED}" ]; then
  echo "ERROR: ${UNIVERSAL_BIN} was not written by this build; refusing to package it." >&2
  exit 1
fi
echo "Packaging ${UNIVERSAL_BIN}"

echo "Verifying architectures..."
lipo -info "${UNIVERSAL_BIN}"

echo "Assembling app bundle at ${APP_DIR}..."
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${UNIVERSAL_BIN}" "${APP_DIR}/Contents/MacOS/DesktopBinsWidget"
cp "Resources/Info.plist" "${APP_DIR}/Contents/Info.plist"
if [ -f "Resources/AppIcon.icns" ]; then
  cp "Resources/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
fi

# Prefer a real Developer ID identity over ad-hoc signing. Ad-hoc signatures
# have no stable designated requirement, so the app's identity changes on
# every rebuild and macOS silently revokes its Automation (Finder) grant each
# time. Signing with a certificate keeps that permission across builds.
# Override by exporting CODESIGN_IDENTITY.
SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "${SIGN_IDENTITY}" ]; then
  # `|| true` guards against head closing the pipe early, which would trip
  # pipefail even though the identity was found.
  SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "Developer ID Application" | head -n 1 | sed -E 's/.*"(.*)".*/\1/' || true)
fi

# The apple-events entitlement is required under the hardened runtime, or
# Finder automation is blocked before macOS can even ask the user for consent.
if [ -n "${SIGN_IDENTITY}" ]; then
  echo "Signing with: ${SIGN_IDENTITY}"
  # --timestamp gets a secure timestamp from Apple, which notarization
  # requires. It needs network access; without it the signature is still
  # valid locally but notarization will reject it.
  codesign --force --options runtime --timestamp \
    --entitlements "Resources/DesktopBinsWidget.entitlements" \
    --identifier "${BUNDLE_ID}" --sign "${SIGN_IDENTITY}" "${APP_DIR}"
else
  echo "WARNING: no Developer ID identity found — falling back to ad-hoc."
  echo "         Finder automation permission will need re-approving after each rebuild."
  codesign --force --options runtime \
    --entitlements "Resources/DesktopBinsWidget.entitlements" \
    --identifier "${BUNDLE_ID}" --sign - "${APP_DIR}"
fi

echo "Designated requirement (this is what TCC keys the permission on):"
codesign -d -r- "${APP_DIR}" 2>&1 | grep "designated" || true

echo "Embedded entitlements:"
codesign -d --entitlements - --xml "${APP_DIR}" 2>/dev/null | plutil -convert xml1 -o - - 2>/dev/null | grep -A1 apple-events || true

echo "Done: ${APP_DIR}"
echo "Move it to /Applications, then launch it, e.g.:"
echo "  cp -R \"${APP_DIR}\" /Applications/"
echo "  open \"/Applications/${APP_NAME}.app\""
