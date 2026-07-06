#!/bin/bash
# ============================================
# ONLYOFFICE Desktop Editors v8.2.1 构建 DMG
# 输出兼容 Intel (x86_64) 和 Apple Silicon (arm64) 的通用 DMG
# ============================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DESKTOP_EDITORS_DIR="$SCRIPT_DIR/DesktopEditors"
DIST_DIR="$SCRIPT_DIR/dist"
XCODE_PROJ_DIR="$DESKTOP_EDITORS_DIR/desktop-apps/macos"
DMG_SOURCE="$DESKTOP_EDITORS_DIR/build_tools/out/mac_arm64/onlyoffice/desktopeditors"
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
echo ">>> [1/5] 检查构建输出..."

if [ ! -d "$DMG_SOURCE" ]; then
    echo "  ❌ 未找到 build_tools/out/，请先运行 install.command"
    read -p "按回车键退出..."
    exit 1
fi

echo "  ✅ build_tools/out/ 存在"
echo ""

# ============================================
# 2. 分别编译 arm64 和 x86_64
# ============================================
echo ">>> [2/5] 编译 Release 版本..."

# 获取项目根目录的绝对路径
PROJECT_ROOT="$(cd "$SCRIPT_DIR" && pwd)"

echo "  [2a] 编译 arm64..."
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
  2>&1 | grep -v "error: The specified item could not be found in the keychain" | tail -10

ARM_BUILD=$(find ~/Library/Developer/Xcode/DerivedData \
  -name "ONLYOFFICE.app" -path "*/Products/Release/*" | head -1)

if [ -n "$ARM_BUILD" ]; then
    echo "  ✅ arm64 编译完成"
else
    echo "  ❌ arm64 编译失败"
    read -p "按回车键退出..."
    exit 1
fi

echo "  [2b] 编译 x86_64..."
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
  2>&1 | grep -v "error: The specified item could not be found in the keychain" | tail -10

X86_BUILD=$(find ~/Library/Developer/Xcode/DerivedData \
  -name "ONLYOFFICE.app" -path "*/Products/Release/*" | head -1)

if [ -n "$X86_BUILD" ]; then
    echo "  ✅ x86_64 编译完成"
else
    echo "  ⚠️  x86_64 编译失败，将只包含 arm64"
fi

echo ""

# ============================================
# 3. 合成为 Universal Binary
# ============================================
echo ">>> [3/5] 合成 Universal Binary..."

mkdir -p "$DIST_DIR"
DIST_APP="$DIST_DIR/$APP_NAME"

# 复制 arm64 版本作为基础
rm -rf "$DIST_APP"
cp -R "$ARM_BUILD" "$DIST_APP"

if [ -n "$X86_BUILD" ] && [ "$ARM_BUILD" != "$X86_BUILD" ]; then
    echo "  ⏳ 合成 ONLYOFFICE 可执行文件..."
    lipo -create \
        "$ARM_BUILD/Contents/MacOS/ONLYOFFICE" \
        "$X86_BUILD/Contents/MacOS/ONLYOFFICE" \
        -output "$DIST_APP/Contents/MacOS/ONLYOFFICE"

    echo "  ⏳ 合成动态库..."
    for DYLIB in "$DIST_APP/Contents/Frameworks/"*.dylib; do
        DYLIB_NAME=$(basename "$DYLIB")
        X86_DYLIB="$X86_BUILD/Contents/Frameworks/$DYLIB_NAME"
        if [ -f "$X86_DYLIB" ]; then
            lipo -create "$DYLIB" "$X86_DYLIB" -output "$DYLIB" 2>/dev/null || true
        fi
    done

    for DYLIB in "$DIST_APP/Contents/Resources/converter/"*.dylib; do
        DYLIB_NAME=$(basename "$DYLIB")
        X86_DYLIB="$X86_BUILD/Contents/Resources/converter/$DYLIB_NAME"
        if [ -f "$X86_DYLIB" ]; then
            lipo -create "$DYLIB" "$X86_DYLIB" -output "$DYLIB" 2>/dev/null || true
        fi
    done

    echo "  ⏳ 合成 CEF Framework..."
    ARM_CEF="$ARM_BUILD/Contents/Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework"
    X86_CEF="$X86_BUILD/Contents/Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework"
    if [ -f "$ARM_CEF" ] && [ -f "$X86_CEF" ]; then
        lipo -create "$ARM_CEF" "$X86_CEF" \
            -output "$DIST_APP/Contents/Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework"
    fi

    echo "  ✅ Universal Binary 合成完成"
else
    echo "  ⚠️  仅 arm64（x86_64 编译失败或无差异）"
fi

# 验证
echo "  📋 架构信息:"
lipo -info "$DIST_APP/Contents/MacOS/ONLYOFFICE"
echo ""

# ============================================
# 4. Ad-hoc 签名
# ============================================
echo ">>> [4/5] Ad-hoc 签名..."

codesign --force --deep --sign - \
    "$DIST_APP/Contents/Frameworks/Chromium Embedded Framework.framework" 2>/dev/null || true
find "$DIST_APP/Contents/Frameworks" -name "*.dylib" \
    -exec codesign --force --sign - {} \; 2>/dev/null || true
find "$DIST_APP/Contents/Resources/converter" -name "*.dylib" \
    -exec codesign --force --sign - {} \; 2>/dev/null || true
codesign --force --sign - "$DIST_APP/Contents/MacOS/ONLYOFFICE" 2>/dev/null || true

echo "  ✅ 签名完成"
echo ""

# ============================================
# 5. 创建 DMG
# ============================================
echo ">>> [5/5] 创建 DMG..."

DMG_TMP="$DIST_DIR/${DMG_NAME}-tmp.dmg"
DMG_OUT="$DIST_DIR/${DMG_NAME}.dmg"

# 删除旧文件
rm -f "$DMG_TMP" "$DMG_OUT"

# 创建临时 DMG
echo "  ⏳ 创建 DMG 镜像..."
hdiutil create -size 600m -fs HFS+ -volname "$DMG_NAME" "$DMG_TMP" 2>&1 | tail -1

# 挂载临时 DMG
echo "  ⏳ 挂载 DMG..."
hdiutil attach "$DMG_TMP" -nobrowse 2>&1 | tail -1

# 复制 App + 卸载时的 Applications 快捷方式
echo "  ⏳ 复制内容..."
cp -R "$DIST_APP" /Volumes/"$DMG_NAME"/

# 创建 Applications 快捷方式
ln -sf /Applications /Volumes/"$DMG_NAME"/Applications 2>/dev/null || true

# 创建 .background 和 .DS_Store（美化 DMG 窗口）

# 卸载
echo "  ⏳ 卸载 DMG..."
hdiutil detach /Volumes/"$DMG_NAME" 2>&1 | tail -1

# 转换为压缩的只读 DMG
echo "  ⏳ 转换和压缩 DMG..."
hdiutil convert "$DMG_TMP" -format UDZO -imagekey zlib-level=9 -o "$DMG_OUT" 2>&1 | tail -1

# 清理
rm -f "$DMG_TMP"

echo "  ✅ DMG 创建完成"
echo ""

# ============================================
# 结果
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
