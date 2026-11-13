#!/bin/zsh
# make-app.sh —— 把專案組成可以雙擊啟動的 SmallPet.app。
#
# 用法（在專案根目錄）：
#     ./make-app.sh
#
# .app 其實只是一個有固定結構的資料夾：
#   SmallPet.app/Contents/Info.plist        App 的基本資訊
#   SmallPet.app/Contents/MacOS/SmallPet    執行檔
#   SmallPet.app/Contents/Resources/        圖片等資源
set -euo pipefail
cd "$(dirname "$0")"

APP="SmallPet.app"

echo "▶ 編譯 release 版…"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "▶ 組裝 $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/SmallPet" "$APP/Contents/MacOS/SmallPet"
# SwiftPM 把 Resources/ 包成 SmallPet_SmallPet.bundle，程式會到 Contents/Resources 找它。
cp -R "$BIN_DIR/SmallPet_SmallPet.bundle" "$APP/Contents/Resources/"

# LSUIElement = true：不顯示 Dock 圖示（跟程式裡的 .accessory 一致）。
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>             <string>SmallPet</string>
    <key>CFBundleDisplayName</key>      <string>SmallPet</string>
    <key>CFBundleIdentifier</key>       <string>local.smallpet</string>
    <key>CFBundleExecutable</key>       <string>SmallPet</string>
    <key>CFBundlePackageType</key>      <string>APPL</string>
    <key>CFBundleVersion</key>          <string>5</string>
    <key>CFBundleShortVersionString</key><string>1.3.0</string>
    <key>LSMinimumSystemVersion</key>   <string>13.0</string>
    <key>LSUIElement</key>              <true/>
    <key>NSHighResolutionCapable</key>  <true/>
</dict>
</plist>
PLIST

# 本機自簽（ad-hoc），讓 Apple Silicon 可以正常執行。
codesign --force --deep --sign - "$APP"

echo "✅ 完成：$(pwd)/$APP"
echo "   在 Finder 雙擊即可啟動，也可以拖到「應用程式」資料夾。"
