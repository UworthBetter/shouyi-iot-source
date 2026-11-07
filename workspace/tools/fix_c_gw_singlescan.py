#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""回退到单次 SSID 定向扫描+单次读结果（该路径从未卡死; 之前0结果实为热点自动关闭）。
保留: 找到后打印每个结果SSID便于核对。"""

p = r"D:\sdk\nearlink\fbb_ws63\src\application\samples\bt\sle\sle_uart\sle_uart.c"
with open(p, "r", encoding="utf-8") as f:
    s = f.read()

old = (
    "            uint32_t i;\n"
    "            int32_t ch;\n"
    '            osal_printk("%s full scan start (ch1-13)\\r\\n", GW_LOG);\n'
    "            for (ch = 1; ch <= 13 && find_ap == 0; ch++) {\n"
    "                wifi_scan_params_stru scan_params = {0};\n"
    "                int wait;\n"
    "                scan_params.scan_type = WIFI_CHANNEL_SCAN;\n"
    "                scan_params.channel_num = ch;\n"
    "                g_wifi_scan_done = 0;\n"
    "                if (wifi_sta_scan_advance(&scan_params) != 0) {\n"
    '                    osal_printk("%s ch%d scan req fail\\r\\n", GW_LOG, ch);\n'
    "                    continue;\n"
    "                }\n"
    "                for (wait = 0; wait < 20 && !g_wifi_scan_done; wait++) {\n"
    "                    osal_msleep(100);\n"
    "                }\n"
    "                num = 20;\n"
    '                    osal_printk("%s ch%d read start\\r\\n", GW_LOG, ch);\n'
    "                if (wifi_sta_get_scan_info(result, &num) != 0) {\n"
    '                    osal_printk("%s ch%d read fail\\r\\n", GW_LOG, ch);\n'
    "                    continue;\n"
    "                }\n"
    "                if (num == 0) {\n"
    "                    continue;\n"
    "                }\n"
    '                osal_printk("%s ch%d: %u APs\\r\\n", GW_LOG, ch, num);\n'
    "                for (i = 0; i < num; i++) {\n"
    '                    osal_printk("%s   ssid: %s\\r\\n", GW_LOG, (char *)result[i].ssid);\n'
    "                    if (strlen(GW_WIFI_SSID) == strlen(result[i].ssid) &&\n"
    "                        memcmp(GW_WIFI_SSID, result[i].ssid, strlen(GW_WIFI_SSID)) == 0) {\n"
    "                        find_ap = 1;\n"
    "                    }\n"
    "                }\n"
    "            }\n"
    "            if (!find_ap) {\n"
    '                osal_printk("%s AP not found anywhere, rescan in 3s\\r\\n", GW_LOG);\n'
    "                osal_msleep(3000);\n"
    "                continue;\n"
    "            }\n"
)

new = (
    "            uint32_t i;\n"
    '            osal_printk("%s ssid scan start\\r\\n", GW_LOG);\n'
    "            {\n"
    "                wifi_scan_params_stru scan_params = {0};\n"
    "                int wait;\n"
    "                scan_params.scan_type = WIFI_SSID_SCAN;\n"
    "                scan_params.ssid_len = strlen(GW_WIFI_SSID);\n"
    "                if (memcpy_s(scan_params.ssid, sizeof(scan_params.ssid),\n"
    "                    GW_WIFI_SSID, strlen(GW_WIFI_SSID) + 1) != EOK) {\n"
    "                    osal_msleep(2000);\n"
    "                    continue;\n"
    "                }\n"
    "                g_wifi_scan_done = 0;\n"
    "                if (wifi_sta_scan_advance(&scan_params) != 0) {\n"
    '                    osal_printk("%s ssid scan req fail\\r\\n", GW_LOG);\n'
    "                    osal_msleep(2000);\n"
    "                    continue;\n"
    "                }\n"
    "                for (wait = 0; wait < 40 && !g_wifi_scan_done; wait++) {\n"
    "                    osal_msleep(100);\n"
    "                }\n"
    "            }\n"
    "            num = 20;\n"
    '            osal_printk("%s scan done, reading results\\r\\n", GW_LOG);\n'
    "            if (wifi_sta_get_scan_info(result, &num) != 0) {\n"
    '                osal_printk("%s read fail\\r\\n", GW_LOG);\n'
    "                osal_msleep(2000);\n"
    "                continue;\n"
    "            }\n"
    '            osal_printk("%s scan results: %u\\r\\n", GW_LOG, num);\n'
    "            for (i = 0; i < num; i++) {\n"
    '                osal_printk("%s   ssid: %s\\r\\n", GW_LOG, (char *)result[i].ssid);\n'
    "                if (strlen(GW_WIFI_SSID) == strlen(result[i].ssid) &&\n"
    "                    memcmp(GW_WIFI_SSID, result[i].ssid, strlen(GW_WIFI_SSID)) == 0) {\n"
    "                    find_ap = 1;\n"
    "                }\n"
    "            }\n"
    "            if (!find_ap) {\n"
    '                osal_printk("%s AP not found, rescan in 3s (check hotspot!)\\r\\n", GW_LOG);\n'
    "                osal_msleep(3000);\n"
    "                continue;\n"
    "            }\n"
)

assert old in s, "channel scan block not found"
s = s.replace(old, new, 1)

with open(p, "w", encoding="utf-8") as f:
    f.write(s)
print("single ssid scan restored")
