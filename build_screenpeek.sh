#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_WORKSPACE_DIR="$(cd "$PROJECT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

APP_NAME="ScreenPeek"
BUNDLE_ID="com.hunglx.ScreenPeek"
APP_VERSION="${APP_VERSION:-1.4.1}"
APP_BUILD="${APP_BUILD:-9}"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
ROOT_APP_BUNDLE="$ROOT_WORKSPACE_DIR/$APP_NAME.app"
DIST_DIR="$PROJECT_DIR/dist"

STAGE_ROOT="$(mktemp -d /tmp/screenpeek_build.XXXXXX)"
trap 'rm -rf "$STAGE_ROOT"' EXIT
STAGE_APP="$STAGE_ROOT/$APP_NAME.app"
CONTENTS_DIR="$STAGE_APP/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "==> [1/5] Đang biên dịch $APP_NAME v$APP_VERSION (Swift Release Optimized)..."
swift build -c release -Xlinker -dead_strip --product "$APP_NAME"

BIN_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"

echo "==> [2/5] Đang đóng gói $APP_NAME.app..."
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp -X "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

echo "==> [3/5] Đang tạo biểu tượng ứng dụng AppIcon.icns..."
ICONSET_DIR="$STAGE_ROOT/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"
swift "$PROJECT_DIR/scripts/generate_icon.swift" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"

cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>vi</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>ScreenPeek</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${APP_BUILD}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>ScreenPeek cần quyền Ghi màn hình để hiển thị trực tiếp nội dung của màn hình kết nối (máy chiếu / màn hình phụ) trong cửa sổ thu nhỏ.</string>
</dict>
</plist>
EOF

echo "==> [4/5] Đang ký số (Ad-hoc Codesign)..."
xattr -cr "$STAGE_APP" 2>/dev/null || true
codesign --force --deep --sign - "$STAGE_APP"
codesign --verify --deep --strict "$STAGE_APP"

mkdir -p "$DIST_DIR"
VERSIONED_ZIP="$DIST_DIR/${APP_NAME}-v${APP_VERSION}-macOS.zip"
LATEST_ZIP="$DIST_DIR/${APP_NAME}.zip"
rm -f "$VERSIONED_ZIP" "$LATEST_ZIP"
ditto -c -k --norsrc --noextattr --keepParent "$STAGE_APP" "$VERSIONED_ZIP"
cp -f "$VERSIONED_ZIP" "$LATEST_ZIP"

rm -rf "$APP_BUNDLE"
ditto --norsrc --noextattr "$STAGE_APP" "$APP_BUNDLE"
xattr -cr "$APP_BUNDLE" 2>/dev/null || true
codesign --verify --deep --strict "$APP_BUNDLE"

if [ "$ROOT_WORKSPACE_DIR" != "$PROJECT_DIR" ]; then
    rm -rf "$ROOT_WORKSPACE_DIR/$APP_NAME.app"
    ditto --norsrc --noextattr "$STAGE_APP" "$ROOT_WORKSPACE_DIR/$APP_NAME.app"
    xattr -cr "$ROOT_WORKSPACE_DIR/$APP_NAME.app" 2>/dev/null || true
    codesign --verify --deep --strict "$ROOT_WORKSPACE_DIR/$APP_NAME.app"
fi

echo "==> [5/5] Hoàn tất! Ứng dụng v$APP_VERSION đã được tạo tại: $APP_BUNDLE và $ROOT_APP_BUNDLE"
