#!/bin/bash
# ============================================
# ONLYOFFICE Desktop Editors v8.2.1 快速启动
# ============================================

APP="$HOME/Applications/ONLYOFFICE.app"

# 获取脚本所在目录（兼容双击打开）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_FILE="$SCRIPT_DIR/test_sales.xlsx"
# large_sample.xlsx

# 检查应用是否存在
if [ ! -d "$APP" ]; then
    echo "❌ ONLYOFFICE.app 未找到: $APP"
    echo "请先按照 README.md 中的步骤编译安装。"
    read -p "按回车键退出..."
    exit 1
fi

# 检查是否已在运行
RUNNING=$(ps aux | grep "[O]NLYOFFICE" | grep -v grep | wc -l)
if [ "$RUNNING" -gt 0 ]; then
    echo "⚠️  ONLYOFFICE 已在运行中"
    read -p "按回车键关闭本窗口..."
    exit 0
fi

# Ad-hoc 签名 (确保变更后仍可运行)
echo "🔐 正在签名..."
codesign --force --deep --sign - \
    "$APP/Contents/Frameworks/Chromium Embedded Framework.framework" 2>/dev/null
find "$APP/Contents/Frameworks" -name "*.dylib" \
    -exec codesign --force --sign - {} \; 2>/dev/null
find "$APP/Contents/Resources/converter" -name "*.dylib" \
    -exec codesign --force --sign - {} \; 2>/dev/null
codesign --force --sign - "$APP/Contents/MacOS/ONLYOFFICE" 2>/dev/null

# 启动
echo "🚀 正在启动 ONLYOFFICE Desktop Editors..."
open "$APP"

# 等待应用就绪（最多等待 30 秒）
echo -n "⏳ 等待 ONLYOFFICE 就绪"
MAX_WAIT=30
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
    if pgrep -f "ONLYOFFICE" > /dev/null 2>&1; then
        echo " ✅"
        break
    fi
    sleep 0.5
    ELAPSED=$(echo "$ELAPSED + 0.5" | bc)
    echo -n "."
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo " ⚠️ 超时"
fi

# 打开测试 Excel 文件
if [ -f "$TEST_FILE" ]; then
    echo "📊 正在打开 test_sales.xlsx..."
    open -a "$APP" "$TEST_FILE"
else
    echo "⚠️  test_sales.xlsx 未找到，跳过"
fi

# 检查结果
RUNNING=$(ps aux | grep "[O]NLYOFFICE" | grep -v grep | wc -l)
if [ "$RUNNING" -gt 0 ]; then
    echo "✅ ONLYOFFICE 已成功启动"
else
    echo "❌ 启动失败，请查看 README.md 排查问题"
fi

read -p "按回车键关闭本窗口..."
