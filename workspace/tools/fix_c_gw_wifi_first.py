#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""网关改造为 WiFi 优先：DHCP 拿到 IP 前 SLE 客户端不找网; get_scan_info 前后加卡点打印"""

p = r"D:\sdk\nearlink\fbb_ws63\src\application\samples\bt\sle\sle_uart\sle_uart.c"
with open(p, "r", encoding="utf-8") as f:
    s = f.read()

# 1) 前向声明区加 g_wifi_ip_up
a1 = "static void *sle_uart_gw_task(const char *arg);\n"
assert a1 in s, "anchor1"
s = s.replace(a1, a1 + "static volatile int g_wifi_ip_up = 0;\n", 1)

# 2) DHCP 成功处置位
a2 = '                osal_printk("%s wifi ready, ip up\\r\\n", GW_LOG);\n                return 0;\n'
assert a2 in s, "anchor2"
s = s.replace(a2,
    '                osal_printk("%s wifi ready, ip up\\r\\n", GW_LOG);\n'
    "                g_wifi_ip_up = 1;\n"
    "                return 0;\n", 1)

# 3) SLE 客户端任务开头等 WiFi 就绪
a3 = (
    "static void *sle_uart_client_task(const char *arg)\n"
    "{\n"
)
assert a3 in s, "anchor3"
s = s.replace(a3, a3 +
    "    /* WiFi 优先: IP 未就绪前不占射频找网, 避免共存调度互卡 */\n"
    "    while (!g_wifi_ip_up) {\n"
    "        osal_msleep(500);\n"
    "    }\n", 1)

# 4) get_scan_info 前后卡点打印
a4 = (
    "                for (wait = 0; wait < 20 && !g_wifi_scan_done; wait++) {\n"
    "                    osal_msleep(100);\n"
    "                }\n"
    "                num = 20;\n"
)
assert a4 in s, "anchor4"
s = s.replace(a4, a4 +
    '                    osal_printk("%s ch%d read start\\r\\n", GW_LOG, ch);\n', 1)

with open(p, "w", encoding="utf-8") as f:
    f.write(s)
print("wifi-first patch applied")
