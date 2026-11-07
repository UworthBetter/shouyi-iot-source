#!/bin/bash
set -euo pipefail
task_root=/mnt/d/jishe/shouyi-iot
cd "$task_root"
gcc -std=c99 -Wall -Wextra -Werror -fsanitize=address,undefined -g \
    -I/root/txsmart/third_party/cJSON -Ifw/local_bridge \
    fw/local_bridge/nearlink_protocol.c tools/test_nearlink_protocol.c \
    /root/txsmart/third_party/cJSON/cJSON.c -lm -o /tmp/shouyi_nearlink_test
/tmp/shouyi_nearlink_test
python3 tools/fix_rk_link_dependencies.py
bash /root/build_rk.sh
python3 tools/verify_rk_image.py
mkdir -p fw/bins/rk2206_local_bridge
cp /root/txsmart/out/rk2206/isoftstone-rk2206/images/Firmware.img \
    fw/bins/rk2206_local_bridge/Firmware.img
sha256sum fw/bins/rk2206_local_bridge/Firmware.img
echo 'Verification and firmware archive complete; nothing flashed.'
