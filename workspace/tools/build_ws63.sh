#!/bin/bash
# 编译 ws63 (H3863) 固件 — 直接在 SDK 内构建
# 用法: bash build_ws63.sh [build.py参数...]   例: bash build_ws63.sh ws63-liteos-app
set -e
export PATH="/c/Users/admin/AppData/Roaming/Python/Python311/Scripts:/c/Program Files/Microsoft VS Code/tools/Windows/cc_riscv32_musl_fp_win/bin:/c/Program Files/Microsoft VS Code/tools/Windows/gn:/c/Program Files/Microsoft VS Code/tools/Windows/ninja:$PATH"
# 关键: 响应文件, 否则 wpa_supplicant 超长命令行 CreateProcess 失败
export CMAKE_NINJA_FORCE_RESPONSE_FILE=1
cd /d/sdk/nearlink/fbb_ws63/src
# 强制 cmake 重新配置：改 Kconfig 后不加这步，mconfig.h 会更新但 add_subdirectory 不生效（坑过）
touch CMakeLists.txt
echo "== cmake: $(cmake --version | head -1) =="
"/c/Program Files/Microsoft VS Code/tools/python/python.exe" build.py "$@"
echo "== 产物: D:\\sdk\\nearlink\\fbb_ws63\\src\\output\\ws63\\fwpkg\\ws63-liteos-app\\ws63-liteos-app_all.fwpkg =="
