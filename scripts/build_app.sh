#!/usr/bin/env bash
set -euo pipefail

APP_NAME="RepoRadar"
WIDGET_NAME="RepoRadarWidget"
CONFIGURATION="${CONFIGURATION:-Release}"
DIST_DIR="dist"
BUILD_DIR="${DIST_DIR}/Build"
LOCAL_XCCONFIG="Configurations/Local.xcconfig"
LOCAL_XCCONFIG_TEMPLATE="Configurations/Local.xcconfig.template"

if [ ! -f "${LOCAL_XCCONFIG}" ]; then
  echo "Error: ${LOCAL_XCCONFIG} is missing."
  echo "Copy the template and set your Apple Developer Team ID:"
  echo "  cp ${LOCAL_XCCONFIG_TEMPLATE} ${LOCAL_XCCONFIG}"
  exit 1
fi

echo "==> Building and signing ${APP_NAME} (${CONFIGURATION})..."
mkdir -p "${DIST_DIR}"

xcodebuild -project RepoRadar.xcodeproj \
  -scheme RepoRadar \
  -configuration "${CONFIGURATION}" \
  -derivedDataPath "${BUILD_DIR}" \
  -allowProvisioningUpdates \
  build

APP_PATH="${BUILD_DIR}/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
if [ ! -d "${APP_PATH}" ]; then
  echo "Error: Built app not found at ${APP_PATH}"
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "${APP_PATH}"

rm -rf "${DIST_DIR}/${APP_NAME}.app"
cp -R "${APP_PATH}" "${DIST_DIR}/${APP_NAME}.app"
echo "✓ App bundle copied to ${DIST_DIR}/${APP_NAME}.app"

if [[ "${1:-}" == "--install" ]]; then
  if pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
    echo "==> Stopping running ${APP_NAME}..."
    killall "${APP_NAME}" 2>/dev/null || true
    sleep 0.5
  fi
  echo "==> Installing to /Applications/${APP_NAME}.app..."
  rm -rf "/Applications/${APP_NAME}.app"
  cp -R "${DIST_DIR}/${APP_NAME}.app" "/Applications/${APP_NAME}.app"
  # The widget extension runs as its own process and outlives the reinstall;
  # stop it so macOS relaunches it from the new bundle.
  if pgrep -x "${WIDGET_NAME}" >/dev/null 2>&1; then
    echo "==> Stopping running ${WIDGET_NAME}..."
    killall "${WIDGET_NAME}" 2>/dev/null || true
  fi
  pluginkit -a "/Applications/${APP_NAME}.app/Contents/PlugIns/RepoRadarWidget.appex"
  echo "✓ Installed to /Applications/${APP_NAME}.app"
  echo "==> Launching /Applications/${APP_NAME}.app..."
  open -a "/Applications/${APP_NAME}.app"
  echo "✓ Launched ${APP_NAME}"
fi
