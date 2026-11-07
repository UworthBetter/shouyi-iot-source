#!/bin/bash
# 编译 bs21e (H2821/T板) 固件 — SDK 自带 b010 编译器
# 用法: bash build_bs21.sh [build.py参数...]   默认: standard-bs21e-1100e
set -e
export PATH="/c/Users/admin/AppData/Roaming/Python/Python311/Scripts:/c/Program Files/Microsoft VS Code/tools/Windows/gn:/c/Program Files/Microsoft VS Code/tools/Windows/ninja:/d/sdk/nearlink/fbb_bs2x/src/tools/bin/compiler/riscv/cc_riscv32_musl_b010/cc_riscv32_musl_fp_win/bin:$PATH"
export CMAKE_NINJA_FORCE_RESPONSE_FILE=1
cd /d/sdk/nearlink/fbb_bs2x/src
touch CMakeLists.txt   # 强制cmake重配置(Kconfig改动生效)
echo "== cmake: $(cmake --version | head -1) =="
TARGET=${1:-standard-bs21e-1100e}
"/c/Program Files/Microsoft VS Code/tools/python/python.exe" build.py "$TARGET"
