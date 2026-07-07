#!/bin/bash
# ============================================
# ONLYOFFICE Desktop Editors v8.2.1 构建 DMG
# 输出兼容 Intel (x86_64) 和 Apple Silicon (arm64) 的通用 DMG
# ============================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DESKTOP_EDITORS_DIR="$SCRIPT_DIR/DesktopEditors"
DIST_DIR="$SCRIPT_DIR/dist"
XCODE_PROJ_DIR="$DESKTOP_EDITORS_DIR/desktop-apps/macos"
DMG_ARM_SOURCE="$DESKTOP_EDITORS_DIR/build_tools/out/mac_arm64/onlyoffice/desktopeditors"
DMG_X86_SOURCE="$DESKTOP_EDITORS_DIR/build_tools/out/mac_64/onlyoffice/desktopeditors"
DMG_X86_FILE="$SCRIPT_DIR/ONLYOFFICE-x86_64.dmg"
DMG_X86_URL="https://github.com/ONLYOFFICE/DesktopEditors/releases/download/v8.2.1/ONLYOFFICE-x86_64.dmg"
APP_NAME="ONLYOFFICE.app"
DMG_NAME="ONLYOFFICE-DesktopEditors-8.2.1"

echo "============================================"
echo " ONLYOFFICE Desktop Editors v8.2.1 构建 DMG"
echo "============================================"
echo ""

# ============================================
# 0. 确保用 Node.js v22
# ============================================
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
    source "$NVM_DIR/nvm.sh"
    nvm use 22 2>/dev/null || true
fi

# ============================================
# 1. 检查构建输出目录
# ============================================
echo ">>> [1/6] 检查构建输出..."

# 清理可能残留的挂载
hdiutil detach /Volumes/ONLYOFFICE 2>/dev/null || true
hdiutil detach "/Volumes/$DMG_NAME" 2>/dev/null || true

if [ ! -d "$DMG_ARM_SOURCE" ]; then
    echo "  ❌ 未找到 build_tools/out/mac_arm64/，请先运行 install.command"
    read -p "按回车键退出..."
    exit 1
fi

echo "  ✅ mac_arm64/ 存在"

# 确保 x86_64 目录存在（可能需要手动提取 DMG）
if [ ! -d "$DMG_X86_SOURCE" ]; then
    echo "  ⚠️  mac_64/ 不存在，尝试从 x86_64 DMG 提取..."
    if [ -f "$DMG_X86_FILE" ]; then
        hdiutil attach "$DMG_X86_FILE" -nobrowse 2>&1 | tail -1
        X86_DMG_APP="/Volumes/ONLYOFFICE/ONLYOFFICE.app"
        mkdir -p "$DMG_X86_SOURCE"
        cp -R "$X86_DMG_APP/Contents/Resources/converter" "$DMG_X86_SOURCE/" 2>/dev/null || true
        cp -R "$X86_DMG_APP/Contents/Frameworks/"* "$DMG_X86_SOURCE/" 2>/dev/null || true
        cp -R "$X86_DMG_APP/Contents/Resources/editors" "$DMG_X86_SOURCE/" 2>/dev/null || true
        rm -rf "$DMG_X86_SOURCE/editors/web-apps"
        cp -R "$DESKTOP_EDITORS_DIR/web-apps/deploy/web-apps" "$DMG_X86_SOURCE/editors/web-apps" 2>/dev/null || true
        mkdir -p "$DMG_X86_SOURCE/editors/web-apps/apps/api/documents"
        cp "$X86_DMG_APP/Contents/Resources/editors/web-apps/apps/api/documents/index.html" \
           "$DMG_X86_SOURCE/editors/web-apps/apps/api/documents/index.html" 2>/dev/null || true
        mkdir -p "$DMG_X86_SOURCE/login"
        cp "$DMG_ARM_SOURCE/login/index.html" "$DMG_X86_SOURCE/login/" 2>/dev/null || true
        cp "$DMG_ARM_SOURCE/login/noconnect.html" "$DMG_X86_SOURCE/login/" 2>/dev/null || true
        mkdir -p "$DMG_X86_SOURCE/login/fonts"
        mkdir -p "$DMG_X86_SOURCE/fonts"
        cp -R "$X86_DMG_APP/Contents/Resources/login/fonts/"* "$DMG_X86_SOURCE/fonts/" 2>/dev/null || true
        cp -R "$X86_DMG_APP/Contents/Resources/login/fonts/"* "$DMG_X86_SOURCE/login/fonts/" 2>/dev/null || true
        cp "$DMG_X86_SOURCE/login/index.html" "$DMG_X86_SOURCE/index.html" 2>/dev/null || true
        hdiutil detach /Volumes/ONLYOFFICE 2>/dev/null || true
        echo "     ✅ x86_64 已提取完成"
    else
        echo "  ⚠️  未找到 ONLYOFFICE-x86_64.dmg，无法编译 Intel 版本"
        echo "     可从以下地址下载: $DMG_X86_URL"
        echo "     将仅构建 arm64 DMG"
    fi
fi
echo ""

# ============================================
# 2. 分别编译 arm64 和 x86_64
# ============================================
echo ">>> [2/6] 编译 Release 版本..."

# 清理旧产物
rm -rf /tmp/oo_build 2>/dev/null
mkdir -p /tmp/oo_build

# 编译 arm64
echo "  [2a] 编译 arm64..."
rm -rf ~/Library/Developer/Xcode/DerivedData/ONLYOFFICE-* 2>/dev/null
cd "$XCODE_PROJ_DIR"
xcodebuild \
  -project ONLYOFFICE.xcodeproj \
  -scheme "ONLYOFFICE-arm" \
  -configuration Release \
  -arch arm64 \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  DEVELOPMENT_TEAM="" \
  ONLY_ACTIVE_ARCH=YES \
  2>&1 | grep -v "error: The specified item could not be found in the keychain" | tail -5

sleep 2
ARM_APP=$(find ~/Library/Developer/Xcode/DerivedData -name "ONLYOFFICE.app" -path "*/Products/Release/*" -type d | head -1)
if [ -d "$ARM_APP" ] && [ -f "$ARM_APP/Contents/MacOS/ONLYOFFICE" ]; then
    cp -R "$ARM_APP" /tmp/oo_build/ONLYOFFICE-arm.app
    echo "  ✅ arm64 编译完成"
else
    echo "  ❌ arm64 编译失败"
    read -p "按回车键退出..."
    exit 1
fi

# 编译 x86_64
echo "  [2b] 编译 x86_64..."
rm -rf ~/Library/Developer/Xcode/DerivedData/ONLYOFFICE-* 2>/dev/null
xcodebuild \
  -project ONLYOFFICE.xcodeproj \
  -scheme "ONLYOFFICE-x86_64" \
  -configuration Release \
  -arch x86_64 \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  DEVELOPMENT_TEAM="" \
  ONLY_ACTIVE_ARCH=YES \
  2>&1 | grep -v "error: The specified item could not be found in the keychain" | tail -5

sleep 2
X86_APP=$(find ~/Library/Developer/Xcode/DerivedData -name "ONLYOFFICE.app" -path "*/Products/Release/*" -type d | head -1)
HAS_X86=false
if [ -d "$X86_APP" ] && [ -f "$X86_APP/Contents/MacOS/ONLYOFFICE" ]; then
    cp -R "$X86_APP" /tmp/oo_build/ONLYOFFICE-x86_64.app
    echo "  ✅ x86_64 编译完成"
    HAS_X86=true
else
    echo "  ⚠️  x86_64 编译失败，将仅包含 arm64"
fi

echo ""

# ============================================
# 3. 合成为 Universal Binary
# ============================================
echo ">>> [3/6] 合成 Universal Binary..."

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
DIST_APP="$DIST_DIR/$APP_NAME"
rm -rf "$DIST_APP"

ARM_APP="/tmp/oo_build/ONLYOFFICE-arm.app"
X86_APP="/tmp/oo_build/ONLYOFFICE-x86_64.app"

# 以 arm64 为基础
cp -R "$ARM_APP" "$DIST_APP"

if [ "$HAS_X86" = true ]; then
    echo "  ⏳ 合成 ONLYOFFICE 可执行文件..."
    lipo -create \
        "$ARM_APP/Contents/MacOS/ONLYOFFICE" \
        "$X86_APP/Contents/MacOS/ONLYOFFICE" \
        -output "$DIST_APP/Contents/MacOS/ONLYOFFICE"

    echo "  ⏳ 合成 CEF Framework..."
    lipo -create \
        "$ARM_APP/Contents/Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework" \
        "$X86_APP/Contents/Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework" \
        -output "$DIST_APP/Contents/Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework" 2>/dev/null || true

    echo "  ⏳ 合成动态库..."
    find "$DIST_APP/Contents/Frameworks" -name "*.dylib" -print0 2>/dev/null | while IFS= read -r -d '' DYLIB; do
        NAME=$(basename "$DYLIB")
        X86_DYLIB="$X86_APP/Contents/Frameworks/$NAME"
        [ -f "$X86_DYLIB" ] && lipo -create "$DYLIB" "$X86_DYLIB" -output "$DYLIB" 2>/dev/null
    done
    find "$DIST_APP/Contents/Resources/converter" -name "*.dylib" -print0 2>/dev/null | while IFS= read -r -d '' DYLIB; do
        REL=$(echo "$DYLIB" | sed 's|.*/ONLYOFFICE.app/||')
        X86_DYLIB="$X86_APP/$REL"
        [ -f "$X86_DYLIB" ] && lipo -create "$DYLIB" "$X86_DYLIB" -output "$DYLIB" 2>/dev/null
    done

    echo "  ✅ Universal Binary 合成完成 (arm64 + x86_64)"
else
    echo "  ⚠️  仅 arm64"
fi

echo "  📋 架构信息:"
lipo -info "$DIST_APP/Contents/MacOS/ONLYOFFICE"
echo ""

# ============================================
# 4. Ad-hoc 签名
# ============================================
echo ">>> [4/6] Ad-hoc 签名..."

codesign --force --deep --sign - \
    "$DIST_APP/Contents/Frameworks/Chromium Embedded Framework.framework" 2>/dev/null || true
find "$DIST_APP/Contents/Frameworks" -name "*.dylib" \
    -exec codesign --force --sign - {} \; 2>/dev/null || true
find "$DIST_APP/Contents/Resources/converter" -name "*.dylib" \
    -exec codesign --force --sign - {} \; 2>/dev/null || true
find "$DIST_APP/Contents/Frameworks" -name "*.app" \
    -exec codesign --force --sign - {} \; 2>/dev/null || true
codesign --force --sign - "$DIST_APP/Contents/MacOS/ONLYOFFICE" 2>/dev/null || true
codesign --force --deep --sign - "$DIST_APP" 2>/dev/null || true

echo "  ✅ 签名完成"
echo ""

# ============================================
# 5. 创建 DMG
# ============================================
echo ">>> [5/6] 创建 DMG..."

DMG_TMP="$DIST_DIR/${DMG_NAME}-tmp.dmg"
DMG_OUT="$DIST_DIR/${DMG_NAME}.dmg"
rm -f "$DMG_TMP" "$DMG_OUT"

# 确保旧挂载已清理（避免 Read-only file system 错误）
hdiutil detach "/Volumes/$DMG_NAME" 2>/dev/null || true
sleep 1

# App 实际大小约 1.6GB，DMG 需要 2GB 空间
echo "  ⏳ 创建 DMG 镜像 (2GB)..."
hdiutil create -size 2g -fs HFS+ -volname "$DMG_NAME" "$DMG_TMP" 2>&1 | tail -1
hdiutil attach "$DMG_TMP" -nobrowse 2>&1 | tail -1

echo "  ⏳ 复制内容..."
cp -R "$DIST_APP" /Volumes/"$DMG_NAME"/ 2>&1 | tail -1
ln -sf /Applications /Volumes/"$DMG_NAME"/Applications 2>/dev/null || true

echo "  ⏳ 卸载 DMG..."
hdiutil detach /Volumes/"$DMG_NAME" 2>&1 | tail -1

echo "  ⏳ 压缩 DMG..."
hdiutil convert "$DMG_TMP" -format UDZO -imagekey zlib-level=9 -o "$DMG_OUT" 2>&1 | tail -1
rm -f "$DMG_TMP"

echo "  ✅ DMG 创建完成"
echo ""

# ============================================
# 6. 结果
# ============================================
echo "============================================"
echo " ✅ 构建完成！"
echo ""
echo " 📦 DMG 文件: $DMG_OUT"
echo " 📊 大小:     $(du -sh "$DMG_OUT" | cut -f1)"
echo " 🖥  架构:     $(lipo -info "$DIST_APP/Contents/MacOS/ONLYOFFICE" 2>/dev/null | sed 's/.*: //')"
echo " 📁 App:      $DIST_APP"
echo ""
echo " 🚀 用户收到 DMG 后双击挂载，拖拽 ONLYOFFICE.app 到 Applications 即可使用"
echo "============================================"

read -p "按回车键关闭本窗口..."
