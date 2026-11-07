#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""修网关补丁的 4 处编译错误：声明顺序 / extern MQTTClient_init / disconnect 签名 / GW_TASK_STACK_SIZE 拼写"""

p = r"D:\sdk\nearlink\fbb_ws63\src\application\samples\bt\sle\sle_uart\sle_uart.c"
with open(p, "r", encoding="utf-8") as f:
    s = f.read()

# 1) 声明提前（volatile 变量移到回调前）
old = (
    'static void gw_wifi_scan_state_changed(int32_t state, int32_t size)\n'
    '{\n'
    '    unused(state);\n'
    '    unused(size);\n'
    '    osal_printk("%s wifi scan done\\r\\n", GW_LOG);\n'
    '    g_wifi_scan_done = 1;\n'
    '}\n'
    '\n'
    'static volatile int g_wifi_scan_done = 0;\n'
    'static volatile int g_wifi_connected = 0;\n'
)
new = (
    'static volatile int g_wifi_scan_done = 0;\n'
    'static volatile int g_wifi_connected = 0;\n'
    '\n'
    'static void gw_wifi_scan_state_changed(int32_t state, int32_t size)\n'
    '{\n'
    '    unused(state);\n'
    '    unused(size);\n'
    '    osal_printk("%s wifi scan done\\r\\n", GW_LOG);\n'
    '    g_wifi_scan_done = 1;\n'
    '}\n'
)
assert old in s, "anchor1 not found"
s = s.replace(old, new, 1)

# 2) extern MQTTClient_init（paho 头里没声明这个移植版入口）
a2 = '#include "MQTTClient.h"\n'
assert a2 in s, "anchor2 not found"
s = s.replace(a2, a2 + 'extern int MQTTClient_init(void); /* porting entry, undeclared in header */\n', 1)

# 3) disconnect 需要 timeout 参数
cnt = s.count("MQTTClient_disconnect(client);")
assert cnt == 1, "disconnect count=%d" % cnt
s = s.replace("MQTTClient_disconnect(client);", "MQTTClient_disconnect(client, 10000);", 1)

# 4) GW_TASK_STACK_SIZE → GW_TASK_STACK（入口任务创建处用错名）
a4 = '"SLEGwTask", GW_TASK_STACK_SIZE);'
assert a4 in s, "anchor4 not found"
s = s.replace(a4, '"SLEGwTask", GW_TASK_STACK);', 1)

with open(p, "w", encoding="utf-8") as f:
    f.write(s)
print("4 fixes applied")
