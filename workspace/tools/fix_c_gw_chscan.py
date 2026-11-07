#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""网关扫描改为逐信道(1..13)扫描：等效全频段+逐信道日志, 兼容驱动只支持 CHANNEL/SSID 类型的事实"""

p = r"D:\sdk\nearlink\fbb_ws63\src\application\samples\bt\sle\sle_uart\sle_uart.c"
with open(p, "r", encoding="utf-8") as f:
    s = f.read()

old = (
    "    while (1) {\n"
    "        if (!g_wifi_scan_done && !g_wifi_connected) {\n"
    "            wifi_scan_params_stru scan_params = {0};\n"
    "            /* 全频段普通扫描: 鉴别RF问题 vs 热点问题; 邻居AP也应可见 */\n"
    "            scan_params.scan_type = WIFI_BASIC_SCAN;\n"
    "            scan_params.ssid_len = 0;\n"
    "            ret = wifi_sta_scan_advance(&scan_params);\n"
    "            if (ret != 0) {\n"
    '                osal_printk("%s wifi scan fail 0x%x\\r\\n", GW_LOG, ret);\n'
    "            }\n"
    "            osal_msleep(2000);\n"
    "            g_wifi_scan_done = 1; /* 结果处理一次, 扫不到就再扫 */\n"
    "            continue;\n"
    "        }\n"
    "        if (!g_wifi_connected) {\n"
    "            uint32_t num = 20;\n"
    "            wifi_scan_info_stru result[20] = {0};\n"
    "            int find_ap = 0;\n"
    "            uint32_t i;\n"
    "            if (wifi_sta_get_scan_info(result, &num) != 0 || num == 0) {\n"
    "                g_wifi_scan_done = 0;\n"
    "                osal_msleep(1000);\n"
    "                continue;\n"
    "            }\n"
    "            for (i = 0; i < num; i++) {\n"
    "                if (strlen(GW_WIFI_SSID) == strlen(result[i].ssid) &&\n"
    "                    memcmp(GW_WIFI_SSID, result[i].ssid, strlen(GW_WIFI_SSID)) == 0) {\n"
    "                    find_ap = 1;\n"
    "                    break;\n"
    "                }\n"
    "            }\n"
    "            if (!find_ap) {\n"
    '                osal_printk("%s AP not found, rescan\\r\\n", GW_LOG);\n'
    "                g_wifi_scan_done = 0;\n"
    "                osal_msleep(2000);\n"
    "                continue;\n"
    "            }\n"
)

new = (
    "    while (1) {\n"
    "        if (!g_wifi_connected) {\n"
    "            wifi_scan_info_stru result[20] = {0};\n"
    "            uint32_t num = 0;\n"
    "            int find_ap = 0;\n"
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

assert old in s, "scan block anchor not found"
s = s.replace(old, new, 1)

# scan_done 变量现在只由回调置位，连接失败后的重扫标志不再需要, 但保留无妨。
with open(p, "w", encoding="utf-8") as f:
    f.write(s)
print("channel-loop scan patched")
