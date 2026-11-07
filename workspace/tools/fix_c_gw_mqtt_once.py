#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""MQTT init 只做一次: paho MQTTClient_init 每次造5把全局mutex且无释放,
重试循环会把 LOSCCFG_BASE_IPC_MUX_LIMIT(20) 的池子耗尽"""

p = r"D:\sdk\nearlink\fbb_ws63\src\application\samples\bt\sle\sle_uart\sle_uart.c"
with open(p, "r", encoding="utf-8") as f:
    s = f.read()

old = (
    "    MQTTClient client = NULL;\n"
    "    MQTTClient_connectOptions conn_opts = MQTTClient_connectOptions_initializer;\n"
    "    int32_t rc;\n"
    "\n"
    "    if (MQTTClient_init() != MQTTCLIENT_SUCCESS) {\n"
    '        osal_printk("%s mqtt init fail\\r\\n", GW_LOG);\n'
    "        return -1;\n"
    "    }\n"
)
new = (
    "    MQTTClient client = NULL;\n"
    "    MQTTClient_connectOptions conn_opts = MQTTClient_connectOptions_initializer;\n"
    "    int32_t rc;\n"
    "    static int g_mqtt_inited = 0; /* MQTTClient_init 全局只允许一次: 每次调用泄漏5个mutex */\n"
    "\n"
    "    if (!g_mqtt_inited) {\n"
    "        if (MQTTClient_init() != MQTTCLIENT_SUCCESS) {\n"
    '            osal_printk("%s mqtt init fail (once)\\r\\n", GW_LOG);\n'
    "            return -1;\n"
    "        }\n"
    "        g_mqtt_inited = 1;\n"
    "    }\n"
)
assert old in s, "mqtt init block not found"
s = s.replace(old, new, 1)

with open(p, "w", encoding="utf-8") as f:
    f.write(s)
print("mqtt init-once patched")
