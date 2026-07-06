# ONLYOFFICE Desktop Editors v8.2.1 — macOS 源码编译与运行

本项目从 [ONLYOFFICE/DesktopEditors](https://github.com/ONLYOFFICE/DesktopEditors) 源码编译 v8.2.1 版本，在 macOS (Apple Silicon) 上运行。

## 项目结构

```
├── DesktopEditors/            # 主仓库 (v8.2.1)
│   ├── desktop-apps/          # macOS 原生外壳 (Xcode 项目)
│   ├── web-apps/              # 前端界面 (Grunt 构建)
│   ├── core/                  # C++ 格式转换引擎
│   ├── sdkjs/                 # JS SDK
│   ├── desktop-sdk/           # 桌面 SDK
│   ├── dictionaries/          # 拼写词典
│   └── build_tools/out/       # 组装的输出目录
├── ONLYOFFICE-arm.dmg         # v8.2.1 官方 DMG (用于提取二进制组件)
├── test_sales.xlsx            # 测试 Excel 文件
└── start_onlyoffice.command   # 快速启动脚本
```

## 编译架构说明

由于官方 `build_tools` 仅支持 Linux，macOS 编译采用混合方案：

| 组件 | 编译方式 |
|------|----------|
| `web-apps` (前端界面) | ✅ 从源码编译 (Grunt + npm) |
| `loginpage` (启动页) | ✅ 从源码编译 (Grunt + npm) |
| `desktop-apps` (macOS 原生壳) | ✅ 从源码编译 (Xcode) |
| `core` (格式转换引擎) | ⚠️ 从官方 DMG 提取二进制 |
| `CEF` (Chromium 内核) | ⚠️ 从官方 DMG 提取二进制 |

## 环境依赖

编译前确保已安装以下工具：

- **Xcode** (含 Command Line Tools)
- **Homebrew**
- **Node.js** (v24+)
- **Qt6** `brew install qt@6`
- **cmake** (项目目录已自带 `cmake-4.3.2-macos-universal/`)

## 完整构建步骤

### 1. 克隆仓库并切换版本

```bash
cd /path/to/your/workspace

# 克隆主仓库
git clone https://github.com/ONLYOFFICE/DesktopEditors.git
cd DesktopEditors

# 切换到 v8.2.1 标签
git checkout v8.2.1

# 拉取子模块
git submodule update --init --recursive
# 如果速度慢，可以逐个浅克隆：
# for m in desktop-apps desktop-sdk core sdkjs web-apps dictionaries; do
#     git clone --depth 1 https://github.com/ONLYOFFICE/$m.git $m
# done
```

### 2. 下载官方 DMG (提取二进制组件)

核心转换引擎 (x2t)、CEF 浏览器内核、格式解析库等大型 C++ 组件从官方 DMG 提取：

```bash
curl -L -o ONLYOFFICE-arm.dmg \
  "https://github.com/ONLYOFFICE/DesktopEditors/releases/download/v8.2.1/ONLYOFFICE-arm.dmg"
```

### 3. 构建 web-apps (前端界面)

```bash
cd DesktopEditors/web-apps/build
npm install
npx grunt
```

### 4. 构建 loginpage (启动页)

```bash
cd DesktopEditors/desktop-apps/common/loginpage/build
npm install
npx grunt
```

### 5. 从 DMG 提取二进制并组装输出目录

```bash
# 挂载 DMG
hdiutil attach ONLYOFFICE-arm.dmg -nobrowse
APP="/Volumes/ONLYOFFICE/ONLYOFFICE.app"

# 创建输出目录结构
OUT="DesktopEditors/build_tools/out/mac_arm64/onlyoffice/desktopeditors"
mkdir -p "$OUT"

# 复制二进制组件
cp -R "$APP/Contents/Resources/converter" "$OUT/"
cp -R "$APP/Contents/Frameworks/"* "$OUT/"

# 替换为源码编译的前端
rm -rf "$OUT/editors/web-apps" "$OUT/editors/sdkjs"
cp -R DesktopEditors/web-apps/deploy/web-apps "$OUT/editors/web-apps"
cp -R DesktopEditors/web-apps/deploy/sdkjs "$OUT/editors/sdkjs"

# 部署启动页
mkdir -p "$OUT/login"
cp DesktopEditors/desktop-apps/common/loginpage/deploy/index.html "$OUT/login/"
cp DesktopEditors/desktop-apps/common/loginpage/deploy/noconnect.html "$OUT/login/"

# 复制扩展资源
cp -R "$APP/Contents/Resources/editors/webext" "$OUT/editors/"
cp -R DesktopEditors/desktop-apps/common/loginpage/providers "$OUT/"
cp "$APP/Contents/Resources/login/fonts" "$OUT/" -R 2>/dev/null
mkdir -p "$OUT/fonts"

# 卸载 DMG
hdiutil detach /Volumes/ONLYOFFICE
```

### 6. 编译 Xcode 项目 (macOS 原生外壳)

```bash
cd DesktopEditors/desktop-apps/macos

xcodebuild \
  -project ONLYOFFICE.xcodeproj \
  -scheme "ONLYOFFICE-arm" \
  -configuration Debug \
  -arch arm64 \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  DEVELOPMENT_TEAM=""
```

构建产物在 Xcode DerivedData 中，可复制到 `/Applications`：

```bash
# 定位构建产物
BUILD_APP=$(find ~/Library/Developer/Xcode/DerivedData \
  -name "ONLYOFFICE.app" -path "*/Products/Debug/*" | head -1)

# 复制到 Applications
cp -R "$BUILD_APP" ~/Applications/ONLYOFFICE.app
```

### 7. 签名并运行

```bash
APP=~/Applications/ONLYOFFICE.app

# Ad-hoc 签名 (本地开发)
codesign --force --deep --sign - "$APP/Contents/Frameworks/Chromium Embedded Framework.framework"
find "$APP/Contents/Frameworks" -name "*.dylib" -exec codesign --force --sign - {} \;
find "$APP/Contents/Resources/converter" -name "*.dylib" -exec codesign --force --sign - {} \;
codesign --force --sign - "$APP/Contents/MacOS/ONLYOFFICE"

# 启动
open "$APP"
```

## 快速启动

**双击项目根目录下的 `start_onlyoffice.command`** 即可一键启动 ONLYOFFICE。

也可以从终端打开测试文件：

```bash
open -a ~/Applications/ONLYOFFICE.app test_sales.xlsx
```

## 测试文件

`test_sales.xlsx` — 包含销售数据表格，有表头、数据行、SUM 合计公式和格式化样式。

## 注意事项

- 编译过程中 Xcode 可能出现 keychain 签名错误，不影响实际使用
- 启动页 (`loginpage`) 必须使用 grunt 编译后的版本，不能使用单个源文件
- 如果应用显示 "Check your Internet connection"，说明启动页 HTML 未正确内联 CSS/JS
- 首次运行应用会提示移动到 Applications 文件夹，确认即可
