#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""网关扫描改全频段 WIFI_BASIC_SCAN：定向扫描只有目标AP应答，0结果无法鉴别RF问题"""

p = r"D:\sdk\nearlink\fbb_ws63\src\application\samples\bt\sle\sle_uart\sle_uart.c"
with open(p, "r", encoding="utf-8") as f:
    s = f.read()

old = (
    "        if (!g_wifi_scan_done && !g_wifi_connected) {\n"
    "            wifi_scan_params_stru scan_params = {0};\n"
    "            if (memcpy_s(scan_params.ssid, sizeof(scan_params.ssid), GW_WIFI_SSID, sizeof(GW_WIFI_SSID)) != EOK) {\n"
    "                osal_msleep(1000);\n"
    "                continue;\n"
    "            }\n"
    "            scan_params.scan_type = WIFI_SSID_SCAN;\n"
    "            scan_params.ssid_len = strlen(GW_WIFI_SSID);\n"
    "            ret = wifi_sta_scan_advance(&scan_params);\n"
)
new = (
    "        if (!g_wifi_scan_done && !g_wifi_connected) {\n"
    "            wifi_scan_params_stru scan_params = {0};\n"
    "            /* 全频段普通扫描: 鉴别RF问题 vs 热点问题; 邻居AP也应可见 */\n"
    "            scan_params.scan_type = WIFI_BASIC_SCAN;\n"
    "            scan_params.ssid_len = 0;\n"
    "            ret = wifi_sta_scan_advance(&scan_params);\n"
)
assert old in s, "scan anchor not found"
s = s.replace(old, new, 1)

with open(p, "w", encoding="utf-8") as f:
    f.write(s)
print("basic scan patched")
