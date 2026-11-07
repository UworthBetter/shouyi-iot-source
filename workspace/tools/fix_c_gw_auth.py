#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""网关认证改为 IoTDA 官方时间戳校验模式（对齐 SDK ble_gateway_iotda 样例与 RK2206 实测）:
clientId = {deviceId}_0_0_{ts}; password = HEX(HMAC-SHA256(key=ts, msg=secret))
域名同时换成 RK2206 同款 iotda-device 端点"""

p = r"D:\sdk\nearlink\fbb_ws63\src\application\samples\bt\sle\sle_uart\sle_uart.c"
with open(p, "r", encoding="utf-8") as f:
    s = f.read()

# 1) 域名换 iotda-device（RK2206 实测可用端点）
a1 = '#define GW_MQTT_URI         "tcp://2eb62113b2.st1.iot-mqtts.cn-north-4.myhuaweicloud.com:1883"'
assert a1 in s, "uri anchor"
s = s.replace(a1,
    '#define GW_MQTT_URI         "tcp://2eb62113b2.st1.iotda-device.cn-north-4.myhuaweicloud.com:1883"\n'
    '#define GW_AUTH_TIMESTAMP   "2026110312" /* 时间戳校验模式: 与pwd的HMAC配套, 官方允许非实时ts */', 1)

# 2) include mbedtls md
a2 = '#include "MQTTClient.h"\n'
assert a2 in s, "incl anchor"
s = s.replace(a2, a2 + '#include "mbedtls/md.h"\n', 1)

# 3) 认证三件套改为时间戳模式
a3 = (
    "    conn_opts.keepAliveInterval = 30;\n"
    "    conn_opts.cleansession = 1;\n"
    "    conn_opts.username = GW_DEVICE_ID;\n"
    "    conn_opts.password = GW_DEVICE_SECRET;\n"
)
assert a3 in s, "conn opts anchor"
s = s.replace(a3,
    "    conn_opts.keepAliveInterval = 30;\n"
    "    conn_opts.cleansession = 1;\n"
    "    conn_opts.username = GW_DEVICE_ID;\n"
    "    /* IoTDA 时间戳校验: password = HEX(HMAC-SHA256(key=timestamp, msg=secret)) */\n"
    "    {\n"
    "        static char pwd_hex[65];\n"
    "        static char client_id[96];\n"
    "        const mbedtls_md_info_t *info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);\n"
    "        unsigned char digest[32];\n"
    "        int hi;\n"
    "        if (info == NULL || mbedtls_md_hmac(info, (const unsigned char *)GW_AUTH_TIMESTAMP,\n"
    "            strlen(GW_AUTH_TIMESTAMP), (const unsigned char *)GW_DEVICE_SECRET,\n"
    "            strlen(GW_DEVICE_SECRET), digest) != 0) {\n"
    '            osal_printk("%s hmac calc fail\\r\\n", GW_LOG);\n'
    "            return -1;\n"
    "        }\n"
    "        for (hi = 0; hi < 32; hi++) {\n"
    "            (void)snprintf(&pwd_hex[hi * 2], 3, \"%02x\", digest[hi]);\n"
    "        }\n"
    "        pwd_hex[64] = 0;\n"
    '        (void)snprintf(client_id, sizeof(client_id), "%s_0_0_%s", GW_DEVICE_ID, GW_AUTH_TIMESTAMP);\n'
    "        conn_opts.password = pwd_hex;\n"
    "        ret = MQTTClient_create(&client, GW_MQTT_URI, client_id,\n"
    "                                MQTTCLIENT_PERSISTENCE_NONE, NULL);\n"
    "        if (ret != MQTTCLIENT_SUCCESS) {\n"
    '            osal_printk("%s mqtt create fail rc=%d\\r\\n", GW_LOG, ret);\n'
    "            return -1;\n"
    "        }\n"
    "    }\n", 1)

# 4) 删掉旧的统一 create（client_id 常量版）
a4 = (
    "    rc = MQTTClient_create(&client, GW_MQTT_URI, GW_DEVICE_ID \"_0_0\",\n"
    "                           MQTTCLIENT_PERSISTENCE_NONE, NULL);\n"
    "    if (rc != MQTTCLIENT_SUCCESS) {\n"
    '        osal_printk("%s mqtt create fail rc=%d\\r\\n", GW_LOG, rc);\n'
    "        return -1;\n"
    "    }\n"
)
assert a4 in s, "old create anchor"
s = s.replace(a4, "", 1)

with open(p, "w", encoding="utf-8") as f:
    f.write(s)
print("auth mode patched")
