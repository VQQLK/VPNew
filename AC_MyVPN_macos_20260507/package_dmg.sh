#!/bin/bash
# ============================================================
#  package_dmg.sh — Упаковка MyVPN.app в .dmg
#  Требования:
#    brew install create-dmg
#    Xcode 15+
# ============================================================
set -e

APP_NAME="MyVPN"
APP_VERSION="2.0.0"
SCHEME="MyVPN"
BUILD_DIR="build"
DMG_DIR="dist"
BUNDLE="${APP_NAME}.app"
DMG_NAME="${APP_NAME}-${APP_VERSION}.dmg"

echo "[1/4] Сборка через xcodebuild..."
xcodebuild \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "${BUILD_DIR}/${APP_NAME}.xcarchive" \
  archive

echo "[2/4] Экспорт .app..."
xcodebuild \
  -exportArchive \
  -archivePath "${BUILD_DIR}/${APP_NAME}.xcarchive" \
  -exportPath "${BUILD_DIR}/export" \
  -exportOptionsPlist ExportOptions.plist

mkdir -p "$DMG_DIR"

echo "[3/4] Создание .dmg..."
# Проверяем наличие иконки приложения — volicon опционален
ICON_ARG=""
if [ -f "${BUILD_DIR}/export/${BUNDLE}/Contents/Resources/AppIcon.icns" ]; then
  ICON_ARG="--volicon ${BUILD_DIR}/export/${BUNDLE}/Contents/Resources/AppIcon.icns"
fi

create-dmg \
  --volname "${APP_NAME}" \
  $ICON_ARG \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "${BUNDLE}" 175 190 \
  --hide-extension "${BUNDLE}" \
  --app-drop-link 425 190 \
  --no-internet-enable \
  "${DMG_DIR}/${DMG_NAME}" \
  "${BUILD_DIR}/export/${BUNDLE}"

echo "[4/4] Готово: ${DMG_DIR}/${DMG_NAME}"
echo ""
echo "Нотаризация (опционально, для Gatekeeper):"
echo "  xcrun notarytool submit ${DMG_DIR}/${DMG_NAME} \\"
echo "    --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID \\"
echo "    --password YOUR_APP_PASSWORD --wait"
echo "  xcrun stapler staple ${DMG_DIR}/${DMG_NAME}"
