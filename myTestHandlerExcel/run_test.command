#!/bin/bash
# myTestHandlerExcel - 双击运行测试
cd "$(dirname "$0")"
echo "============================================"
echo "  oo-office:// 协议唤醒测试"
echo "  myTestHandlerExcel"
echo "============================================"
echo ""
node test_oooffice_wakeup.mjs
echo ""
read -p "按回车键关闭..."
