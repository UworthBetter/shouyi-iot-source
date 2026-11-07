#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
C板(ws63 sle_uart client) → 网关固件补丁
在现有 SLE 客户端桥基础上增加: Wi-Fi STA(热点 Redmi Turbo 3) + MQTT(IoTDA 1883明文)
收到 T 的 SLE notify 后包成 monitor 属性上报( WiFi RSSI 实时值; T JSON 里的
temperature/humidity 若存在则透传 —— 传感器接入后网关零改动)。
幂等: 重复运行自动跳过。
"""
import shutil
import sys

SLE = r"D:\sdk\nearlink\fbb_ws63\src\application\samples\bt\sle\sle_uart\sle_uart.c"

with open(SLE, "r", encoding="utf-8") as f:
    text = f.read()

if "SLEGwTask" in text:
    print("already patched, skip")
    sys.exit(0)

shutil.copyfile(SLE, SLE + ".bak_pre_gw")
n = 0

def sub(old, new):
    global text, n
    if new in text:
        print("skip (already):", new[:50].replace("\n", "\\n"))
        return
    if old not in text:
        sys.exit("anchor not found:\n" + old)
    text = text.replace(old, new, 1)
    n += 1

# 1) includes
sub(
    '#include "common_def.h"\n#include "soc_osal.h"\n#include "app_init.h"\n#include "pinctrl.h"\n#include "uart.h"\n',
    '#include "common_def.h"\n#include "soc_osal.h"\n#include "app_init.h"\n#include "pinctrl.h"\n#include "uart.h"\n'
    '/* ---- shouyi gateway: wifi + mqtt (IoTDA) ---- */\n'
    '#include "lwip/netifapi.h"\n'
    '#include "wifi_hotspot.h"\n'
    '#include "wifi_hotspot_config.h"\n'
    '#include "wifi_device.h"\n'
    '#include "MQTTClient.h"\n'
    '#include <stdio.h>\n'
    '#include <stdlib.h>\n')

# 2) 状态与前向声明
sub(
    "#define SLE_UART_TASK_PRIO 28\n",
    "#define SLE_UART_TASK_PRIO 28\n\n"
    "/* ---- shouyi gateway state (client role only) ---- */\n"
    "#if defined(CONFIG_SAMPLE_SUPPORT_SLE_UART_CLIENT_SAMPLE)\n"
    'static unsigned long g_gw_pubq_id;\n'
    "static uint32_t g_gw_pubq_drop = 0;\n"
    "static volatile int g_gw_mqtt_ready = 0;\n"
    "static void *sle_uart_gw_task(const char *arg);\n"
    "static void gw_notify_publish(const uint8_t *data, uint16_t len);\n"
    "#endif\n")

# 3) notification_cb 挂钩: 收到服务器数据 → 投递到上报队列
sub(
    '    osal_printk("[sle uart client] recv %d bytes from server: %.*s\\r\\n", data->data_len, data->data_len, data->data);\n'
    "    uapi_uart_write(CONFIG_UART_BUS_ID, data->data, data->data_len, 0);\n"
    "}\n",
    '    osal_printk("[sle uart client] recv %d bytes from server: %.*s\\r\\n", data->data_len, data->data_len, data->data);\n'
    "    uapi_uart_write(CONFIG_UART_BUS_ID, data->data, data->data_len, 0);\n"
    "    gw_notify_publish(data->data, data->data_len);\n"
    "}\n")

# 4) 网关代码块 + 入口任务创建
GW_BLOCK = r'''
/* ================================================================
 * shouyi gateway: Wi-Fi STA + MQTT(IoTDA) + SLE 数据上云
 * ================================================================ */
#if defined(CONFIG_SAMPLE_SUPPORT_SLE_UART_CLIENT_SAMPLE)

#define GW_WIFI_SSID        "Redmi Turbo 3"
#define GW_WIFI_KEY         "xjcvbnmk"
#define GW_MQTT_URI         "tcp://2eb62113b2.st1.iotda-mqtt.cn-north-4.myhuaweicloud.com:1883"
#define GW_DEVICE_ID        "6ad6dbb77f2e6c302fa4ef57_sy-nearlink-001"
#define GW_DEVICE_SECRET    "shouyi-nl-2026"
#define GW_PUB_TOPIC        "$oc/devices/" GW_DEVICE_ID "/sys/properties/report"
#define GW_PUBQ_LEN         8
#define GW_PUBQ_ITEM        520
#define GW_TASK_STACK       0x2000
#define GW_TASK_PRIO        25
#define GW_LOG              "[sle gw]"

static void gw_notify_publish(const uint8_t *data, uint16_t len)
{
    if (g_gw_pubq_id == 0 || data == NULL || len == 0) {
        return;
    }
    uint16_t send_len = len;
    if (send_len > GW_PUBQ_ITEM) {
        send_len = GW_PUBQ_ITEM;
    }
    if (osal_msg_queue_write_copy(g_gw_pubq_id, (void *)data, (uint32_t)send_len, 0) != OSAL_SUCCESS) {
        g_gw_pubq_drop++;
        if (g_gw_pubq_drop <= 3 || g_gw_pubq_drop % 100 == 0) {
            osal_printk("%s pubq full, dropped %u\r\n", GW_LOG, g_gw_pubq_drop);
        }
    }
}

/* ---- Wi-Fi STA 事件回调(移植自 sta_sample) ---- */
#define GW_WIFI_NOT_AVALLIABLE 0
static void gw_wifi_scan_state_changed(int32_t state, int32_t size)
{
    unused(state);
    unused(size);
    osal_printk("%s wifi scan done\r\n", GW_LOG);
    g_wifi_scan_done = 1;
}

static volatile int g_wifi_scan_done = 0;
static volatile int g_wifi_connected = 0;

static void gw_wifi_connection_changed(int32_t state, const wifi_linked_info_stru *info, int32_t reason_code)
{
    unused(info);
    unused(reason_code);
    if (state == GW_WIFI_NOT_AVALLIABLE) {
        osal_printk("%s wifi connect fail, retry\r\n", GW_LOG);
        g_wifi_connected = 0;
        g_wifi_scan_done = 0;
    } else {
        osal_printk("%s wifi connect succ\r\n", GW_LOG);
        g_wifi_connected = 1;
    }
}

static wifi_event_stru g_gw_wifi_event_cb = {
    .wifi_event_connection_changed = gw_wifi_connection_changed,
    .wifi_event_scan_state_changed = gw_wifi_scan_state_changed,
};

static int32_t gw_wifi_sta_connect(void)
{
    wifi_sta_config_stru expected_bss = {0};
    struct netif *netif_p = NULL;
    uint32_t wait_count = 0;
    const char ifname[] = "wlan0";
    int32_t ret;

    if (wifi_register_event_cb(&g_gw_wifi_event_cb) != 0) {
        osal_printk("%s wifi event cb register fail\r\n", GW_LOG);
        return -1;
    }
    while (wifi_is_wifi_inited() == 0) {
        osal_msleep(100);
    }
    if (wifi_sta_enable() != 0) {
        osal_printk("%s wifi sta enable fail\r\n", GW_LOG);
        return -1;
    }
    osal_printk("%s wifi sta enabled, scan for \"%s\"\r\n", GW_LOG, GW_WIFI_SSID);

    while (1) {
        if (!g_wifi_scan_done && !g_wifi_connected) {
            wifi_scan_params_stru scan_params = {0};
            if (memcpy_s(scan_params.ssid, sizeof(scan_params.ssid), GW_WIFI_SSID, sizeof(GW_WIFI_SSID)) != EOK) {
                osal_msleep(1000);
                continue;
            }
            scan_params.scan_type = WIFI_SSID_SCAN;
            scan_params.ssid_len = strlen(GW_WIFI_SSID);
            ret = wifi_sta_scan_advance(&scan_params);
            if (ret != 0) {
                osal_printk("%s wifi scan fail 0x%x\r\n", GW_LOG, ret);
            }
            osal_msleep(2000);
            g_wifi_scan_done = 1; /* 结果处理一次, 扫不到就再扫 */
            continue;
        }
        if (!g_wifi_connected) {
            uint32_t num = 20;
            wifi_scan_info_stru result[20] = {0};
            int find_ap = 0;
            uint32_t i;
            if (wifi_sta_get_scan_info(result, &num) != 0 || num == 0) {
                g_wifi_scan_done = 0;
                osal_msleep(1000);
                continue;
            }
            for (i = 0; i < num; i++) {
                if (strlen(GW_WIFI_SSID) == strlen(result[i].ssid) &&
                    memcmp(GW_WIFI_SSID, result[i].ssid, strlen(GW_WIFI_SSID)) == 0) {
                    find_ap = 1;
                    break;
                }
            }
            if (!find_ap) {
                osal_printk("%s AP not found, rescan\r\n", GW_LOG);
                g_wifi_scan_done = 0;
                osal_msleep(2000);
                continue;
            }
            if (memcpy_s(expected_bss.ssid, sizeof(expected_bss.ssid), GW_WIFI_SSID, strlen(GW_WIFI_SSID)) != EOK) {
                continue;
            }
            if (memcpy_s(expected_bss.bssid, sizeof(expected_bss.bssid), result[i].bssid, 6) != EOK) {
                continue;
            }
            expected_bss.security_type = result[i].security_type;
            if (memcpy_s(expected_bss.pre_shared_key, sizeof(expected_bss.pre_shared_key),
                GW_WIFI_KEY, strlen(GW_WIFI_KEY)) != EOK) {
                continue;
            }
            expected_bss.ip_type = 1; /* DHCP */
            osal_printk("%s wifi connecting...\r\n", GW_LOG);
            if (wifi_sta_connect(&expected_bss) != 0) {
                g_wifi_scan_done = 0;
                osal_msleep(2000);
                continue;
            }
            osal_msleep(1000);
            continue;
        }
        /* 已关联: DHCP */
        netif_p = netifapi_netif_find((char *)ifname);
        if (netif_p == NULL) {
            osal_msleep(500);
            continue;
        }
        if (netifapi_dhcp_start(netif_p) != 0) {
            osal_printk("%s dhcp start fail\r\n", GW_LOG);
            osal_msleep(2000);
            continue;
        }
        wait_count = 0;
        while (wait_count < 300) { /* 最多等 30s */
            if (!ip_addr_isany(&(netif_p->ip_addr))) {
                osal_printk("%s wifi ready, ip up\r\n", GW_LOG);
                return 0;
            }
            osal_msleep(100);
            wait_count++;
        }
        osal_printk("%s dhcp timeout, retry all\r\n", GW_LOG);
        g_wifi_connected = 0;
        g_wifi_scan_done = 0;
    }
}

/* ---- MQTT ---- */
static int32_t gw_mqtt_connect(MQTTClient *client_out)
{
    MQTTClient client = NULL;
    MQTTClient_connectOptions conn_opts = MQTTClient_connectOptions_initializer;
    int32_t rc;

    if (MQTTClient_init() != MQTTCLIENT_SUCCESS) {
        osal_printk("%s mqtt init fail\r\n", GW_LOG);
        return -1;
    }
    rc = MQTTClient_create(&client, GW_MQTT_URI, GW_DEVICE_ID "_0_0",
                           MQTTCLIENT_PERSISTENCE_NONE, NULL);
    if (rc != MQTTCLIENT_SUCCESS) {
        osal_printk("%s mqtt create fail rc=%d\r\n", GW_LOG, rc);
        return -1;
    }
    conn_opts.keepAliveInterval = 30;
    conn_opts.cleansession = 1;
    conn_opts.username = GW_DEVICE_ID;
    conn_opts.password = GW_DEVICE_SECRET;
    conn_opts.connectTimeout = 10;
    rc = MQTTClient_connect(client, &conn_opts);
    if (rc != MQTTCLIENT_SUCCESS) {
        osal_printk("%s mqtt connect fail rc=%d\r\n", GW_LOG, rc);
        MQTTClient_destroy(&client);
        return -1;
    }
    osal_printk("%s mqtt connected to IoTDA\r\n", GW_LOG);
    *client_out = client;
    return 0;
}

static int32_t gw_mqtt_publish(MQTTClient client, const char *payload)
{
    MQTTClient_message pubmsg = MQTTClient_message_initializer;
    MQTTClient_deliveryToken token;
    pubmsg.payload = (void *)payload;
    pubmsg.payloadlen = (int)strlen(payload);
    pubmsg.qos = 1;
    pubmsg.retained = 0;
    return MQTTClient_publishMessage(client, GW_PUB_TOPIC, &pubmsg, &token);
}

/* ---- 网关主任务 ---- */
static void *sle_uart_gw_task(const char *arg)
{
    unused(arg);
    MQTTClient client = NULL;
    uint8_t rx_buf[GW_PUBQ_ITEM];
    uint32_t rx_len;

    if (osal_msg_queue_create("gw_pub_q", GW_PUBQ_LEN, (unsigned long *)&g_gw_pubq_id, 0, GW_PUBQ_ITEM)
        != OSAL_SUCCESS) {
        osal_printk("%s pubq create fail\r\n", GW_LOG);
        return NULL;
    }
    osal_printk("%s gw task up\r\n", GW_LOG);

    if (gw_wifi_sta_connect() != 0) {
        osal_printk("%s wifi final fail, gw exit\r\n", GW_LOG);
        return NULL;
    }

    while (client == NULL || MQTTClient_isConnected(client) == 0) {
        if (gw_mqtt_connect(&client) != 0) {
            osal_printk("%s mqtt retry in 10s\r\n", GW_LOG);
            osal_msleep(10000);
        }
    }
    g_gw_mqtt_ready = 1;
    osal_printk("%s gateway online\r\n", GW_LOG);

    while (1) {
        rx_len = GW_PUBQ_ITEM;
        if (osal_msg_queue_read_copy(g_gw_pubq_id, rx_buf, &rx_len, 0xFFFFFFFF) != OSAL_SUCCESS) {
            continue;
        }
        if (rx_len == 0) {
            continue;
        }
        rx_buf[rx_len < GW_PUBQ_ITEM ? rx_len : GW_PUBQ_ITEM - 1] = 0;
        /* 组 IoTDA 属性上报: rssi(实时的 WiFi 信号) + T JSON 里若带 temperature/humidity 则透传 */
        float temperature = 0.0f, humidity = 0.0f;
        int has_temp = 0, has_hum = 0;
        const char *p = strstr((const char *)rx_buf, "\"temperature\":");
        if (p != NULL) {
            temperature = (float)strtod(p + strlen("\"temperature\":"), NULL);
            has_temp = 1;
        }
        p = strstr((const char *)rx_buf, "\"humidity\":");
        if (p != NULL) {
            humidity = (float)strtod(p + strlen("\"humidity\":"), NULL);
            has_hum = 1;
        }
        int32_t rssi_val = 0;
        wifi_linked_info_stru ap_info;
        if (wifi_sta_get_ap_info(&ap_info) == 0) {
            rssi_val = ap_info.rssi;
        }
        char payload[512];
        int plen;
        int t_i = (int)temperature;
        int t_f = (int)(temperature * 10.0f) % 10;
        if (t_f < 0) { t_f = -t_f; }
        int h_i = (int)humidity;
        int h_f = (int)(humidity * 10.0f) % 10;
        if (h_f < 0) { h_f = -h_f; }
        if (has_temp && has_hum) {
            plen = snprintf(payload, sizeof(payload),
                "{\"services\":[{\"service_id\":\"monitor\",\"properties\":{"
                "\"rssi\":%d,\"temperature\":%d.%d,\"humidity\":%d.%d}}]}", rssi_val, t_i, t_f, h_i, h_f);
        } else if (has_temp) {
            plen = snprintf(payload, sizeof(payload),
                "{\"services\":[{\"service_id\":\"monitor\",\"properties\":{"
                "\"rssi\":%d,\"temperature\":%d.%d}}]}", rssi_val, t_i, t_f);
        } else {
            plen = snprintf(payload, sizeof(payload),
                "{\"services\":[{\"service_id\":\"monitor\",\"properties\":{\"rssi\":%d}}]}", rssi_val);
        }
        if (plen <= 0 || plen >= (int)sizeof(payload)) {
            continue;
        }
        osal_printk("%s publish %d bytes: %s\r\n", GW_LOG, plen, payload);
        if (gw_mqtt_publish(client, payload) != MQTTCLIENT_SUCCESS) {
            osal_printk("%s publish fail, reconnect\r\n", GW_LOG);
            g_gw_mqtt_ready = 0;
            MQTTClient_disconnect(client);
            MQTTClient_destroy(&client);
            client = NULL;
            while (gw_mqtt_connect(&client) != 0) {
                osal_msleep(10000);
            }
            g_gw_mqtt_ready = 1;
            osal_printk("%s gateway re-online\r\n", GW_LOG);
        }
    }
    return NULL;
}
#endif /* CONFIG_SAMPLE_SUPPORT_SLE_UART_CLIENT_SAMPLE */

static void sle_uart_entry(void)
'''

sub("\nstatic void sle_uart_entry(void)\n{", GW_BLOCK)

sub(
    '#elif defined(CONFIG_SAMPLE_SUPPORT_SLE_UART_CLIENT_SAMPLE)\n'
    '    task_handle =\n'
    '        osal_kthread_create((osal_kthread_handler)sle_uart_client_task, 0, "SLEUartClient", SLE_UART_TASK_STACK_SIZE);\n'
    '#endif\n',
    '#elif defined(CONFIG_SAMPLE_SUPPORT_SLE_UART_CLIENT_SAMPLE)\n'
    '    task_handle =\n'
    '        osal_kthread_create((osal_kthread_handler)sle_uart_client_task, 0, "SLEUartClient", SLE_UART_TASK_STACK_SIZE);\n'
    '#if defined(CONFIG_SAMPLE_SUPPORT_SLE_UART_CLIENT_SAMPLE)\n'
    '    osal_task *gw_handle =\n'
    '        osal_kthread_create((osal_kthread_handler)sle_uart_gw_task, 0, "SLEGwTask", GW_TASK_STACK_SIZE);\n'
    '    if (gw_handle != NULL) {\n'
    '        osal_kthread_set_priority(gw_handle, GW_TASK_PRIO);\n'
    '    }\n'
    '#endif\n'
    '#endif\n')

with open(SLE, "w", encoding="utf-8") as f:
    f.write(text)
print("gateway patched, %d edits (backup: .bak_pre_gw)" % n)
