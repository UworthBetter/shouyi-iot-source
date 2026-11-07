#!/bin/bash
# 烧录 ws63 固件
# 用法: bash flash_ws63.sh [COM口] [波特率] [fwpkg路径]
# 注意: 工具只等 30 秒 — 看到提示立刻按板子 RST
COM=${1:-COM7}
BAUD=${2:-460800}
FW=${3:-/d/sdk/nearlink/fbb_ws63/src/output/ws63/fwpkg/ws63-liteos-app/ws63-liteos-app_all.fwpkg}
FWWIN=$(cygpath -w "$FW")
echo "== 烧 $FWWIN -> $COM @$BAUD =="
echo "== 30秒内请按板子 RST! =="
cd "/c/Program Files/Microsoft VS Code/tools/BurnToolCmd"
./BurnToolCmd.exe --burn -n ws63 -m serial "$COM" "$BAUD" 0 0 -f "$FWWIN"
