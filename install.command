#!/bin/bash
# ============================================
# ONLYOFFICE Desktop Editors v8.2.1 一键安装编译
# ============================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DESKTOP_EDITORS_DIR="$SCRIPT_DIR/DesktopEditors"
DMG_FILE="$SCRIPT_DIR/ONLYOFFICE-arm.dmg"
DMG_URL="https://github.com/ONLYOFFICE/DesktopEditors/releases/download/v8.2.1/ONLYOFFICE-arm.dmg"
APP_DEST="$HOME/Applications/ONLYOFFICE.app"

echo "============================================"
echo " ONLYOFFICE Desktop Editors v8.2.1 安装编译"
echo "============================================"
echo ""

# ============================================
# 1. 环境检查
# ============================================
echo ">>> [1/9] 检查环境依赖..."

# Node.js v22 - 必须用 v22，v24 与旧版 Grunt 不兼容（util.isError 已移除）
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
    source "$NVM_DIR/nvm.sh"
    if nvm ls 2>/dev/null | grep -q "v22\."; then
        nvm use 22 2>/dev/null || true
        echo "  ✅ Node.js $(node -v)"
    else
        echo "  ❌ 未找到 Node.js v22，请安装: nvm install 22"
        read -p "按回车键退出..."
        exit 1
    fi
else
    echo "  ❌ 未找到 nvm，请先安装 nvm 和 Node.js v22"
    echo "     安装方法: curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash"
    read -p "按回车键退出..."
    exit 1
fi

# Xcode Command Line Tools
if ! xcode-select -p &>/dev/null; then
    echo "  ❌ 未找到 Xcode Command Line Tools，请运行: xcode-select --install"
    read -p "按回车键退出..."
    exit 1
fi
echo "  ✅ Xcode $(xcodebuild -version 2>/dev/null | head -1 | sed 's/Xcode //')"

# Homebrew
if ! which brew &>/dev/null; then
    echo "  ❌ 未找到 Homebrew，请先安装: /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    read -p "按回车键退出..."
    exit 1
fi

# Qt6
if ! brew list qt@6 &>/dev/null 2>&1; then
    echo "  ⏳ 安装 Qt6..."
    brew install qt@6
fi
echo "  ✅ Qt6 已安装"

echo ""

# ============================================
# 2. 下载官方 DMG（如果不存在）
# ============================================
echo ">>> [2/9] 下载官方 DMG (提取 CEF 内核 + 二进制组件)..."

if [ -f "$DMG_FILE" ]; then
    echo "  ✅ DMG 已存在 ($(du -sh "$DMG_FILE" | cut -f1))"
else
    echo "  ⏳ 下载中 (约 322MB)..."
    curl -L -o "$DMG_FILE" "$DMG_URL"
    echo "  ✅ 下载完成"
fi
echo ""

# ============================================
# 3. 构建 web-apps（前端界面）
# ============================================
echo ">>> [3/9] 构建 web-apps (源码编译前端界面)..."
echo "  ⚠️  使用 Node.js v22（v24 的 util.isError 已被移除，不兼容旧版 Grunt）"

WEBAPPS_BUILD_DIR="$DESKTOP_EDITORS_DIR/web-apps/build"

# 3a. 安装 npm 依赖
echo "  [3a] 安装 npm 依赖..."
# 跳过 phantomjs 下载（已废弃且下载极慢）
cd "$WEBAPPS_BUILD_DIR"
if [ ! -d "node_modules" ]; then
    npm install 2>&1 | tail -3
fi

# 3b. 移除 mobile 构建任务（桌面版不需要，且 framework7-react 缺失会导致构建失败）
echo "  [3b] 移除 mobile/forms 构建任务（桌面版不需要）..."
for JSON_FILE in documenteditor.json spreadsheeteditor.json presentationeditor.json; do
    if [ -f "$JSON_FILE" ]; then
        # 移除 deploy-app-mobile 和 deploy-app-forms
        if command -v python3 &>/dev/null; then
            python3 -c "
import json
with open('$JSON_FILE', 'r') as f:
    data = json.load(f)
if 'tasks' in data and 'deploy' in data['tasks']:
    deploy = data['tasks']['deploy']
    remove_tasks = ['deploy-app-mobile', 'deploy-app-forms']
    data['tasks']['deploy'] = [t for t in deploy if t not in remove_tasks]
    with open('$JSON_FILE', 'w') as f:
        json.dump(data, f, indent=4)
        f.write('\n')
"
        fi
    fi
done
echo "     ✅ 已处理"

# 3c. 运行 Grunt 构建
echo "  [3c] 运行 Grunt 构建..."
npx grunt 2>&1 | tail -5
echo "  ✅ web-apps 构建完成"
echo ""

# ============================================
# 4. 构建 loginpage（启动页）
# ============================================
echo ">>> [4/9] 构建 loginpage (启动页)..."

LOGINPAGE_BUILD_DIR="$DESKTOP_EDITORS_DIR/desktop-apps/common/loginpage/build"

cd "$LOGINPAGE_BUILD_DIR"

# 4a. 安装 npm 依赖
if [ ! -d "node_modules" ]; then
    npm install 2>&1 | tail -3
fi

# 4b. 修复 grunt-inline 符号链接（npm 安装后是断链，指向不存在的 ../plugins/grunt-inline）
echo "  [4b] 修复 grunt-inline 符号链接..."
ln -sf "$WEBAPPS_BUILD_DIR/plugins/grunt-inline" "$LOGINPAGE_BUILD_DIR/node_modules/grunt-inline"
echo "     ✅ 已修复"

# 4c. 运行 Grunt 构建
echo "  [4c] 运行 Grunt 构建..."
npx grunt 2>&1 | tail -3
echo "  ✅ loginpage 构建完成"
echo ""

# ============================================
# 5. 从 DMG 提取二进制并组装输出目录
# ============================================
echo ">>> [5/9] 从 DMG 提取二进制并组装输出目录..."

# 挂载 DMG
echo "  [5a] 挂载 DMG..."
hdiutil attach "$DMG_FILE" -nobrowse 2>&1 | tail -1
DMG_APP="/Volumes/ONLYOFFICE/ONLYOFFICE.app"

# 创建输出目录
OUT="$DESKTOP_EDITORS_DIR/build_tools/out/mac_arm64/onlyoffice/desktopeditors"
mkdir -p "$OUT"

# 复制二进制组件 (converter, Frameworks 等)
echo "  [5b] 复制二进制组件..."
cp -R "$DMG_APP/Contents/Resources/converter" "$OUT/" 2>/dev/null || true
cp -R "$DMG_APP/Contents/Frameworks/"* "$OUT/" 2>/dev/null || true

# 复制 editors 目录（包含 sdkjs, web-apps, webext）
echo "  [5c] 复制 editors 和 sdkjs..."
cp -R "$DMG_APP/Contents/Resources/editors" "$OUT/" 2>/dev/null || true

# 替换为源码编译的 web-apps
echo "  [5d] 替换为源码编译的 web-apps..."
rm -rf "$OUT/editors/web-apps"
cp -R "$DESKTOP_EDITORS_DIR/web-apps/deploy/web-apps" "$OUT/editors/web-apps"

# ⚠️ 关键修复：不要用源码的 deploy/sdkjs 覆盖！
# 源码的 SDKJS 构建不生成 sdk-all.js 引擎文件，必须保留 DMG 中的完整版本
echo "  [5e] 保留 DMG 原始 sdkjs（含 sdk-all.js 引擎）..."

# ⚠️ 修复 api/documents/index.html（源码构建未生成该文件）
echo "  [5f] 修复 api/documents/index.html..."
mkdir -p "$OUT/editors/web-apps/apps/api/documents"
cp "$DMG_APP/Contents/Resources/editors/web-apps/apps/api/documents/index.html" \
   "$OUT/editors/web-apps/apps/api/documents/index.html"

# 部署启动页
echo "  [5g] 部署启动页..."
mkdir -p "$OUT/login"
cp "$DESKTOP_EDITORS_DIR/desktop-apps/common/loginpage/deploy/index.html" "$OUT/login/"
cp "$DESKTOP_EDITORS_DIR/desktop-apps/common/loginpage/deploy/noconnect.html" "$OUT/login/"

# 复制 providers
cp -R "$DESKTOP_EDITORS_DIR/desktop-apps/common/loginpage/providers" "$OUT/" 2>/dev/null || true

# 复制 webext
rm -rf "$OUT/editors/webext" 2>/dev/null || true
cp -R "$DMG_APP/Contents/Resources/editors/webext" "$OUT/editors/" 2>/dev/null || true

# fonts 目录
mkdir -p "$OUT/fonts"
mkdir -p "$OUT/login/fonts" 2>/dev/null || true

# ⚠️ 关键修复：Xcode "Copy Library" 脚本期望 index.html 在 build_tools 根目录
# 但实际文件在 login/ 子目录中，需要复制一份到根目录
echo "  [5h] 修复 index.html 路径（Xcode Copy Library 脚本兼容）..."
cp "$OUT/login/index.html" "$OUT/index.html"

# 卸载 DMG
hdiutil detach /Volumes/ONLYOFFICE 2>/dev/null || true
echo "  ✅ 输出目录组装完成"
echo ""

# ============================================
# 6. 编译 Xcode 项目（macOS 原生外壳）
# ============================================
echo ">>> [6/9] 编译 Xcode 项目 (macOS 原生外壳)..."
echo "  ⚠️  keychain 签名警告可忽略（本地开发无需证书）"

XCODE_PROJ_DIR="$DESKTOP_EDITORS_DIR/desktop-apps/macos"
cd "$XCODE_PROJ_DIR"

xcodebuild \
  -project ONLYOFFICE.xcodeproj \
  -scheme "ONLYOFFICE-arm" \
  -configuration Debug \
  -arch arm64 \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  DEVELOPMENT_TEAM="" \
  2>&1 | grep -v "error: The specified item could not be found in the keychain" | tail -5

# 定位构建产物
BUILD_APP=$(find ~/Library/Developer/Xcode/DerivedData \
  -name "ONLYOFFICE.app" -path "*/Products/Debug/*" | head -1)

if [ -z "$BUILD_APP" ]; then
    echo "  ❌ 未找到构建产物"
else
    echo "  ✅ 编译完成: $BUILD_APP"
fi
echo ""

# ============================================
# 7. 复制到 Applications
# ============================================
echo ">>> [7/9] 安装到 ~/Applications..."

if [ -d "$APP_DEST" ]; then
    rm -rf "$APP_DEST"
fi
cp -R "$BUILD_APP" "$APP_DEST"
echo "  ✅ 已复制: $APP_DEST"
echo ""

# ============================================
# 8. Ad-hoc 签名
# ============================================
echo ">>> [8/9] Ad-hoc 签名..."

codesign --force --deep --sign - \
    "$APP_DEST/Contents/Frameworks/Chromium Embedded Framework.framework" 2>/dev/null || true
find "$APP_DEST/Contents/Frameworks" -name "*.dylib" \
    -exec codesign --force --sign - {} \; 2>/dev/null || true
find "$APP_DEST/Contents/Resources/converter" -name "*.dylib" \
    -exec codesign --force --sign - {} \; 2>/dev/null || true
codesign --force --sign - "$APP_DEST/Contents/MacOS/ONLYOFFICE" 2>/dev/null || true

echo "  ✅ 签名完成"
echo ""

# ============================================
# 9. 验证安装
# ============================================
echo ">>> [9/9] 验证安装..."

ERRORS=0

# 检查关键文件
check_file() {
    if [ -f "$1" ]; then
        echo "  ✅ $2"
    else
        echo "  ❌ 缺失: $2"
        ERRORS=$((ERRORS + 1))
    fi
}

check_file "$APP_DEST/Contents/MacOS/ONLYOFFICE" "MacOS/ONLYOFFICE 可执行文件"
check_file "$APP_DEST/Contents/Resources/login/index.html" "login/index.html (启动页)"
check_file "$APP_DEST/Contents/Resources/editors/web-apps/apps/api/documents/index.html" "api/documents/index.html (编辑器入口)"
check_file "$APP_DEST/Contents/Resources/editors/sdkjs/word/sdk-all.js" "sdkjs/word/sdk-all.js (文档引擎)"
check_file "$APP_DEST/Contents/Resources/editors/sdkjs/cell/sdk-all.js" "sdkjs/cell/sdk-all.js (表格引擎)"
check_file "$APP_DEST/Contents/Resources/editors/sdkjs/slide/sdk-all.js" "sdkjs/slide/sdk-all.js (演示引擎)"
check_file "$APP_DEST/Contents/Resources/editors/web-apps/apps/spreadsheeteditor/main/index.html" "spreadsheeteditor (表格编辑器)"
check_file "$APP_DEST/Contents/Resources/editors/web-apps/apps/documenteditor/main/index.html" "documenteditor (文档编辑器)"
check_file "$APP_DEST/Contents/Resources/editors/web-apps/apps/presentationeditor/main/index.html" "presentationeditor (演示编辑器)"
check_file "$APP_DEST/Contents/Resources/editors/web-apps/apps/pdfeditor/main/index.html" "pdfeditor (PDF 编辑器)"

echo ""
if [ $ERRORS -eq 0 ]; then
    echo "✅✅✅ 安装编译成功！"
    echo ""
    echo "双击 start.command 启动 ONLYOFFICE Desktop Editors"
    echo ""
else
    echo "⚠️  有 $ERRORS 个文件缺失，请检查日志排查问题"
fi

# 启动
echo "🚀 正在启动 ONLYOFFICE Desktop Editors..."
open "$APP_DEST"

read -p "按回车键关闭本窗口..."
