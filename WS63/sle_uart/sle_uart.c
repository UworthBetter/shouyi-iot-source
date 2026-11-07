/**
 * Copyright (c) HiSilicon (Shanghai) Technologies Co., Ltd. 2023-2026. All rights reserved.
 *
 * @if Eng
 * @brief Provides the entry and UART bridge tasks for the SLE UART sample.
 * @else
 * @brief 提供 SLE UART 案例入口及串口桥接任务。
 * @endif
 *
 * History: \n
 * 2024-05-18, Create file. \n
 */
#include "common_def.h"
#include "soc_osal.h"
#include "app_init.h"
#include "pinctrl.h"
#include "uart.h"
/* ---- shouyi gateway: wifi + mqtt (IoTDA) ---- */
#include "lwip/netifapi.h"
#include "wifi_hotspot.h"
#include "wifi_hotspot_config.h"
#include "wifi_device.h"
#include "MQTTClient.h"
#include "mbedtls/md.h"
extern int MQTTClient_init(void); /* porting entry, undeclared in header */
#include <stdio.h>
#include <stdlib.h>

#if defined(CONFIG_SAMPLE_SUPPORT_SLE_UART_SERVER_SAMPLE)
#include "sle_uart_server.h"
#include "sle_uart_server_adv.h"
#elif defined(CONFIG_SAMPLE_SUPPORT_SLE_UART_CLIENT_SAMPLE)
#include "sle_uart_client.h"
#include "sle_errcode.h"
#endif

#define SLE_UART_TASK_PRIO 28

/* ---- shouyi gateway state (client role only) ---- */
#if defined(CONFIG_SAMPLE_SUPPORT_SLE_UART_CLIENT_SAMPLE)
static unsigned long g_gw_pubq_id;
static uint32_t g_gw_pubq_drop = 0;
static volatile int g_gw_mqtt_ready = 0;
static void *sle_uart_gw_task(const char *arg);
static volatile int g_wifi_ip_up = 0;
static void gw_notify_publish(const uint8_t *data, uint16_t len);
#endif
#define SLE_UART_TASK_STACK_SIZE 0x1000
#define SLE_UART_DROP_LOG_INITIAL_COUNT 3U
#define SLE_UART_DROP_LOG_INTERVAL 100U

/* UART receive buffer shared with the driver. / 与串口驱动共享的接收缓冲区。 */
static uint8_t g_uart_rx_buffer[CONFIG_SLE_UART_RX_BUF_SIZE];

#if defined(CONFIG_SAMPLE_SUPPORT_SLE_UART_SERVER_SAMPLE)
/* SLE server role. / SLE 服务端。 */

unsigned long g_sle_uart_server_msgq_id;

/**
 * @if Eng
 * @brief Handles data received by the UART driver.
 * @else
 * @brief 处理串口驱动接收到的数据。
 * @endif
 */
static void sle_uart_server_rx_handler(const void *buffer, uint16_t length, bool error)
{
    if (error || buffer == NULL || length == 0) {
        osal_printk("[sle uart server] rx cb, error=%d, buf=%p, len=%u\r\n", error, buffer, length);
        return;
    }

    if (!sle_uart_server_is_connected()) {
        osal_printk("[sle uart server] uart rx dropped: not connected\r\n");
        return;
    }

    if (osal_msg_queue_write_copy(g_sle_uart_server_msgq_id, (void *)buffer, (uint32_t)length, 0) != OSAL_SUCCESS) {
        static uint32_t drop_cnt = 0;
        drop_cnt++;
        if (drop_cnt <= SLE_UART_DROP_LOG_INITIAL_COUNT || drop_cnt % SLE_UART_DROP_LOG_INTERVAL == 0) {
            osal_printk("[sle uart server] msgq full, dropped %u packets\r\n", drop_cnt);
        }
    }
}

/**
 * @if Eng
 * @brief Handles an SSAP write request.
 * @else
 * @brief 处理 SSAP 写请求。
 * @endif
 */
static void sle_uart_server_write_cbk(uint8_t server_id,
                                      uint16_t conn_id,
                                      ssaps_req_write_cb_t *write_cb_para,
                                      errcode_t status)
{
    unused(server_id);
    unused(conn_id);
    unused(status);

    if (write_cb_para->value == NULL || write_cb_para->length == 0) {
        return;
    }

    osal_printk("[sle uart server] recv %d bytes from client: %.*s\r\n", write_cb_para->length, write_cb_para->length,
                write_cb_para->value);
    /* Forward client data to UART. / 将客户端数据转发到串口。 */
    int32_t wr_ret = uapi_uart_write(CONFIG_UART_BUS_ID, write_cb_para->value, write_cb_para->length, 0);
    if (wr_ret < 0) {
        osal_printk("[sle uart server] uart write fail: 0x%x\r\n", wr_ret);
    }
}

/**
 * @if Eng
 * @brief Handles an SSAP read request.
 * @else
 * @brief 处理 SSAP 读请求。
 * @endif
 */
static void sle_uart_server_read_cbk(uint8_t server_id,
                                     uint16_t conn_id,
                                     ssaps_req_read_cb_t *read_cb_para,
                                     errcode_t status)
{
    unused(server_id);
    unused(conn_id);
    unused(read_cb_para);
    unused(status);
    /* Read requests are unused for transparent transmission. / 透传场景不处理读请求。 */
}

/**
 * @if Eng
 * @brief Runs the worker task implemented by \c sle_uart_server_task.
 * @else
 * @brief 运行 \c sle_uart_server_task 实现的工作任务。
 * @endif
 */
static errcode_t sle_uart_initialize_uart(const char *role)
{
    uart_attr_t uart_attr = {.baud_rate = CONFIG_SLE_UART_BAUDRATE,
                             .data_bits = UART_DATA_BIT_8,
                             .stop_bits = UART_STOP_BIT_1,
                             .parity = UART_PARITY_NONE};
    uart_pin_config_t pin_config = {
        .tx_pin = CONFIG_UART_TXD_PIN, .rx_pin = CONFIG_UART_RXD_PIN, .cts_pin = PIN_NONE, .rts_pin = PIN_NONE};
    uart_buffer_config_t buffer_config = {.rx_buffer = g_uart_rx_buffer, .rx_buffer_size = CONFIG_SLE_UART_RX_BUF_SIZE};

    osal_printk("[sle uart %s] pin config: bus=%d, tx=%d mode=%d, rx=%d mode=%d\r\n", role, CONFIG_UART_BUS_ID,
                CONFIG_UART_TXD_PIN, CONFIG_UART_TXD_PIN_MODE, CONFIG_UART_RXD_PIN, CONFIG_UART_RXD_PIN_MODE);
#if defined(CONFIG_PINCTRL_SUPPORT_IE)
    uapi_pin_set_ie(CONFIG_UART_RXD_PIN, PIN_IE_ENABLE);
#endif
    errcode_t ret = uapi_pin_set_mode(CONFIG_UART_TXD_PIN, CONFIG_UART_TXD_PIN_MODE);
    if (ret != ERRCODE_SUCC) {
        osal_printk("[sle uart %s] set tx pin mode fail: 0x%x\r\n", role, ret);
    }
    ret = uapi_pin_set_mode(CONFIG_UART_RXD_PIN, CONFIG_UART_RXD_PIN_MODE);
    if (ret != ERRCODE_SUCC) {
        osal_printk("[sle uart %s] set rx pin mode fail: 0x%x\r\n", role, ret);
    }

    uapi_uart_deinit(CONFIG_UART_BUS_ID);
    ret = uapi_uart_init(CONFIG_UART_BUS_ID, &pin_config, &uart_attr, NULL, &buffer_config);
    if (ret == ERRCODE_SUCC) {
        osal_printk("[sle uart %s] uart init ok, bus=%d, tx=%d, rx=%d, baud=%d\r\n", role, CONFIG_UART_BUS_ID,
                    CONFIG_UART_TXD_PIN, CONFIG_UART_RXD_PIN, CONFIG_SLE_UART_BAUDRATE);
    }
    return ret;
}

static void sle_uart_server_forward(void)
{
    uint8_t rx_buf[CONFIG_SLE_UART_MSGQ_ITEM_SIZE];
    uint32_t rx_len;

    while (1) {
        rx_len = CONFIG_SLE_UART_MSGQ_ITEM_SIZE;
        if (osal_msg_queue_read_copy(g_sle_uart_server_msgq_id, rx_buf, &rx_len, OSAL_WAIT_FOREVER) != OSAL_SUCCESS) {
            continue;
        }
        if (rx_len == 0) {
            continue;
        }
        osal_printk("[sle uart server] send notify %d bytes: %.*s\r\n", rx_len, rx_len, rx_buf);
        sle_uart_server_send_notification(rx_buf, (uint16_t)rx_len);
    }
}

static void *sle_uart_server_task(const char *arg)
{
    unused(arg);
    errcode_t ret;

    osal_printk("[sle uart server] task start.\r\n");

    /* 1. Create the message queue. / 1. 创建消息队列。 */
    if (osal_msg_queue_create("sle_uart_srv_msgq", CONFIG_SLE_UART_MSGQ_LEN, &g_sle_uart_server_msgq_id, 0,
                              CONFIG_SLE_UART_MSGQ_ITEM_SIZE) != OSAL_SUCCESS) {
        osal_printk("[sle uart server] msgq create failed!\r\n");
        return NULL;
    }
    ret = sle_uart_initialize_uart("server");
    if (ret != ERRCODE_SUCC) {
        osal_printk("[sle uart server] uart init fail: 0x%x\r\n", ret);
        return NULL;
    }

    /* 2. Configure UART pins. / 2. 配置串口引脚。 */
    /* 3. Initialize UART. / 3. 初始化串口。 */
    /* 4. Initialize the SLE server. / 4. 初始化 SLE 服务端。 */
    sle_uart_server_init(sle_uart_server_read_cbk, sle_uart_server_write_cbk);
    sle_uart_server_adv_init();
    osal_printk("[sle uart server] waiting for connection...\r\n");

    /* 5. Register the UART RX callback in ISR context. / 5. 注册在中断上下文执行的串口接收回调。 */
    ret = uapi_uart_register_rx_callback(CONFIG_UART_BUS_ID, UART_RX_CONDITION_FULL_OR_SUFFICIENT_DATA_OR_IDLE, 1,
                                         sle_uart_server_rx_handler);
    if (ret != ERRCODE_SUCC) {
        osal_printk("[sle uart server] register uart rx callback fail: 0x%x\r\n", ret);
        return NULL;
    } else {
        osal_printk("[sle uart server] uart rx callback registered ok\r\n");
    }

    /* 6. Forward queued UART data through SLE. / 6. 通过 SLE 转发队列中的串口数据。 */
    sle_uart_server_forward();
    return NULL;
}

#elif defined(CONFIG_SAMPLE_SUPPORT_SLE_UART_CLIENT_SAMPLE)
/* SLE client role. / SLE 客户端。 */

unsigned long g_sle_uart_client_msgq_id;

/* Write parameter populated during discovery and reused for sending. / 服务发现阶段填充并由发送任务复用的写参数。 */
ssapc_write_param_t g_write_param = {0};

/**
 * @if Eng
 * @brief Handles data received by the UART driver.
 * @else
 * @brief 处理串口驱动接收到的数据。
 * @endif
 */
static void sle_uart_client_rx_handler(const void *buffer, uint16_t length, bool error)
{
    if (error || buffer == NULL || length == 0) {
        osal_printk("[sle uart client] rx cb, error=%d, buf=%p, len=%u\r\n", error, buffer, length);
        return;
    }

    if (!sle_uart_client_is_connected()) {
        osal_printk("[sle uart client] uart rx dropped: not connected\r\n");
        return;
    }

    if (osal_msg_queue_write_copy(g_sle_uart_client_msgq_id, (void *)buffer, (uint32_t)length, 0) != OSAL_SUCCESS) {
        static uint32_t drop_cnt = 0;
        drop_cnt++;
        if (drop_cnt <= SLE_UART_DROP_LOG_INITIAL_COUNT || drop_cnt % SLE_UART_DROP_LOG_INTERVAL == 0) {
            osal_printk("[sle uart client] msgq full, dropped %u packets\r\n", drop_cnt);
        }
    }
}

/**
 * @if Eng
 * @brief Handles a notification received from the SLE server.
 * @else
 * @brief 处理从 SLE 服务端收到的通知。
 * @endif
 */
static void sle_uart_client_notification_cb(uint8_t client_id,
                                            uint16_t conn_id,
                                            ssapc_handle_value_t *data,
                                            errcode_t status)
{
    unused(client_id);
    unused(conn_id);

    if (status != ERRCODE_SLE_SUCCESS || data == NULL || data->data_len == 0) {
        osal_printk("[sle uart client] notify cb, status=%x, data=%p, len=%u\r\n", status, data,
                    data ? data->data_len : 0);
        return;
    }
    osal_printk("[sle uart client] recv %d bytes from server: %.*s\r\n", data->data_len, data->data_len, data->data);
    uapi_uart_write(CONFIG_UART_BUS_ID, data->data, data->data_len, 0);
    gw_notify_publish(data->data, data->data_len);
}

/**
 * @if Eng
 * @brief Handles completion of an SLE client write request.
 * @else
 * @brief 处理 SLE 客户端写请求完成事件。
 * @endif
 */
static void sle_uart_client_write_cfm_cb(uint8_t client_id,
                                         uint16_t conn_id,
                                         ssapc_write_result_t *write_result,
                                         errcode_t status)
{
    unused(client_id);
    unused(conn_id);
    unused(write_result);
    unused(status);
}

/**
 * @if Eng
 * @brief Runs the worker task implemented by \c sle_uart_client_task.
 * @else
 * @brief 运行 \c sle_uart_client_task 实现的工作任务。
 * @endif
 */
static errcode_t sle_uart_client_initialize_uart(void)
{
    uart_attr_t uart_attr = {.baud_rate = CONFIG_SLE_UART_BAUDRATE,
                             .data_bits = UART_DATA_BIT_8,
                             .stop_bits = UART_STOP_BIT_1,
                             .parity = UART_PARITY_NONE};
    uart_pin_config_t pin_config = {
        .tx_pin = CONFIG_UART_TXD_PIN, .rx_pin = CONFIG_UART_RXD_PIN, .cts_pin = PIN_NONE, .rts_pin = PIN_NONE};
    uart_buffer_config_t buffer_config = {.rx_buffer = g_uart_rx_buffer, .rx_buffer_size = CONFIG_SLE_UART_RX_BUF_SIZE};

    osal_printk("[sle uart %s] pin config: bus=%d, tx=%d mode=%d, rx=%d mode=%d\r\n", "client", CONFIG_UART_BUS_ID,
                CONFIG_UART_TXD_PIN, CONFIG_UART_TXD_PIN_MODE, CONFIG_UART_RXD_PIN, CONFIG_UART_RXD_PIN_MODE);
#if defined(CONFIG_PINCTRL_SUPPORT_IE)
    uapi_pin_set_ie(CONFIG_UART_RXD_PIN, PIN_IE_ENABLE);
#endif
    errcode_t ret = uapi_pin_set_mode(CONFIG_UART_TXD_PIN, CONFIG_UART_TXD_PIN_MODE);
    if (ret != ERRCODE_SUCC) {
        osal_printk("[sle uart %s] set tx pin mode fail: 0x%x\r\n", "client", ret);
    }
    ret = uapi_pin_set_mode(CONFIG_UART_RXD_PIN, CONFIG_UART_RXD_PIN_MODE);
    if (ret != ERRCODE_SUCC) {
        osal_printk("[sle uart %s] set rx pin mode fail: 0x%x\r\n", "client", ret);
    }

    uapi_uart_deinit(CONFIG_UART_BUS_ID);
    ret = uapi_uart_init(CONFIG_UART_BUS_ID, &pin_config, &uart_attr, NULL, &buffer_config);
    if (ret == ERRCODE_SUCC) {
        osal_printk("[sle uart client] uart init ok, bus=%d, tx=%d, rx=%d, baud=%d\r\n", CONFIG_UART_BUS_ID,
                    CONFIG_UART_TXD_PIN, CONFIG_UART_RXD_PIN, CONFIG_SLE_UART_BAUDRATE);
    }
    return ret;
}

static void sle_uart_client_forward(void)
{
    uint8_t data[CONFIG_SLE_UART_MSGQ_ITEM_SIZE];
    uint32_t data_len;

    while (1) {
        data_len = CONFIG_SLE_UART_MSGQ_ITEM_SIZE;
        if (osal_msg_queue_read_copy(g_sle_uart_client_msgq_id, data, &data_len, OSAL_WAIT_FOREVER) != OSAL_SUCCESS) {
            continue;
        }
        if (data_len == 0) {
            continue;
        }
        g_write_param.data = data;
        g_write_param.data_len = data_len;
        osal_printk("[sle uart client] send %d bytes: %.*s\r\n", data_len, data_len, data);
        ssapc_write_req(0, g_conn_id, &g_write_param);
    }
}

static void *sle_uart_client_task(const char *arg)
{
    /* SHOUYI_LOCAL_BRIDGE: no Wi-Fi prerequisite */
    unused(arg);
    errcode_t ret;

    osal_printk("[sle uart client] task start.\r\n");

    /* 1. Create the message queue. / 1. 创建消息队列。 */
    if (osal_msg_queue_create("sle_uart_cli_msgq", CONFIG_SLE_UART_MSGQ_LEN, &g_sle_uart_client_msgq_id, 0,
                              CONFIG_SLE_UART_MSGQ_ITEM_SIZE) != OSAL_SUCCESS) {
        osal_printk("[sle uart client] msgq create failed!\r\n");
        return NULL;
    }
    ret = sle_uart_client_initialize_uart();
    if (ret != ERRCODE_SUCC) {
        osal_printk("[sle uart client] uart init fail: 0x%x\r\n", ret);
        return NULL;
    }

    /* 2. Configure UART pins. / 2. 配置串口引脚。 */
    /* 3. Initialize UART. / 3. 初始化串口。 */
    /* 4. Initialize scanning, connection, pairing, MTU, and discovery. / 4. 初始化扫描、连接、配对、MTU 和服务发现。 */
    sle_uart_client_init(sle_uart_client_notification_cb, sle_uart_client_write_cfm_cb);
    osal_printk("[sle uart client] scanning for uart_server...\r\n");

    /* 5. Register the UART RX callback in ISR context. / 5. 注册在中断上下文执行的串口接收回调。 */
    ret = uapi_uart_register_rx_callback(CONFIG_UART_BUS_ID, UART_RX_CONDITION_FULL_OR_SUFFICIENT_DATA_OR_IDLE, 1,
                                         sle_uart_client_rx_handler);
    if (ret != ERRCODE_SUCC) {
        osal_printk("[sle uart client] register uart rx callback fail: 0x%x\r\n", ret);
        return NULL;
    } else {
        osal_printk("[sle uart client] uart rx callback registered ok\r\n");
    }

    /* 6. Forward queued UART data with SLE write requests. / 6. 使用 SLE 写请求转发队列中的串口数据。 */
    sle_uart_client_forward();
    return NULL;
}
#endif

/**
 * @if Eng
 * @brief Creates and starts the sample task.
 * @else
 * @brief 创建并启动案例任务。
 * @endif
 */
/* ================================================================
 * shouyi gateway: Wi-Fi STA + MQTT(IoTDA) + SLE 数据上云
 * ================================================================ */
#if defined(CONFIG_SAMPLE_SUPPORT_SLE_UART_CLIENT_SAMPLE)

#define GW_WIFI_SSID        "Redmi Turbo 3"
#define GW_WIFI_KEY         "xjcvbnmk"
#define GW_MQTT_URI         "tcp://2eb62113b2.st1.iotda-device.cn-north-4.myhuaweicloud.com:1883"
#define GW_AUTH_TIMESTAMP   "2026110312" /* 时间戳校验模式: 与pwd的HMAC配套, 官方允许非实时ts */
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
static volatile int g_wifi_scan_done = 0;
static volatile int g_wifi_connected = 0;

static void gw_wifi_scan_state_changed(int32_t state, int32_t size)
{
    unused(state);
    unused(size);
    osal_printk("%s wifi scan done\r\n", GW_LOG);
    g_wifi_scan_done = 1;
}

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
        if (!g_wifi_connected) {
            wifi_scan_info_stru result[20] = {0};
            uint32_t num = 0;
            int find_ap = 0;
            uint32_t i;
            osal_printk("%s ssid scan start\r\n", GW_LOG);
            {
                wifi_scan_params_stru scan_params = {0};
                int wait;
                scan_params.scan_type = WIFI_SSID_SCAN;
                scan_params.ssid_len = strlen(GW_WIFI_SSID);
                if (memcpy_s(scan_params.ssid, sizeof(scan_params.ssid),
                    GW_WIFI_SSID, strlen(GW_WIFI_SSID) + 1) != EOK) {
                    osal_msleep(2000);
                    continue;
                }
                g_wifi_scan_done = 0;
                if (wifi_sta_scan_advance(&scan_params) != 0) {
                    osal_printk("%s ssid scan req fail\r\n", GW_LOG);
                    osal_msleep(2000);
                    continue;
                }
                for (wait = 0; wait < 40 && !g_wifi_scan_done; wait++) {
                    osal_msleep(100);
                }
            }
            num = 20;
            osal_printk("%s scan done, reading results\r\n", GW_LOG);
            if (wifi_sta_get_scan_info(result, &num) != 0) {
                osal_printk("%s read fail\r\n", GW_LOG);
                osal_msleep(2000);
                continue;
            }
            osal_printk("%s scan results: %u\r\n", GW_LOG, num);
            for (i = 0; i < num; i++) {
                osal_printk("%s   ssid: %s\r\n", GW_LOG, (char *)result[i].ssid);
                if (strlen(GW_WIFI_SSID) == strlen(result[i].ssid) &&
                    memcmp(GW_WIFI_SSID, result[i].ssid, strlen(GW_WIFI_SSID)) == 0) {
                    find_ap = 1;
                }
            }
            if (!find_ap) {
                osal_printk("%s AP not found, rescan in 3s (check hotspot!)\r\n", GW_LOG);
                osal_msleep(3000);
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
                g_wifi_ip_up = 1;
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
    int32_t ret;
    static int g_mqtt_inited = 0; /* MQTTClient_init 全局只允许一次: 每次调用泄漏5个mutex */

    if (!g_mqtt_inited) {
        if (MQTTClient_init() != MQTTCLIENT_SUCCESS) {
            osal_printk("%s mqtt init fail (once)\r\n", GW_LOG);
            return -1;
        }
        g_mqtt_inited = 1;
    }
    conn_opts.keepAliveInterval = 30;
    conn_opts.cleansession = 1;
    conn_opts.username = GW_DEVICE_ID;
    /* IoTDA 时间戳校验: password = HEX(HMAC-SHA256(key=timestamp, msg=secret)) */
    {
        static char pwd_hex[65];
        static char client_id[96];
        const mbedtls_md_info_t *info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
        unsigned char digest[32];
        int hi;
        if (info == NULL || mbedtls_md_hmac(info, (const unsigned char *)GW_AUTH_TIMESTAMP,
            strlen(GW_AUTH_TIMESTAMP), (const unsigned char *)GW_DEVICE_SECRET,
            strlen(GW_DEVICE_SECRET), digest) != 0) {
            osal_printk("%s hmac calc fail\r\n", GW_LOG);
            return -1;
        }
        for (hi = 0; hi < 32; hi++) {
            (void)snprintf(&pwd_hex[hi * 2], 3, "%02x", digest[hi]);
        }
        pwd_hex[64] = 0;
        (void)snprintf(client_id, sizeof(client_id), "%s_0_0_%s", GW_DEVICE_ID, GW_AUTH_TIMESTAMP);
        conn_opts.password = pwd_hex;
        ret = MQTTClient_create(&client, GW_MQTT_URI, client_id,
                                MQTTCLIENT_PERSISTENCE_NONE, NULL);
        if (ret != MQTTCLIENT_SUCCESS) {
            osal_printk("%s mqtt create fail rc=%d\r\n", GW_LOG, ret);
            return -1;
        }
    }
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
    int32_t rc = MQTTClient_publishMessage(client, GW_PUB_TOPIC, &pubmsg, &token);
    if (rc == MQTTCLIENT_SUCCESS) {
        /* Synchronous client must process PUBACK before the next publish. */
        rc = MQTTClient_waitForCompletion(client, token, 5000);
    }
    osal_printk("%s publish completion rc=%d\r\n", GW_LOG, rc);
    return rc;
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
        /* Keep servicing MQTT even when the SLE terminal is disconnected. */
        if (osal_msg_queue_read_copy(g_gw_pubq_id, rx_buf, &rx_len, 100) != OSAL_SUCCESS) {
            MQTTClient_yield();
            if (MQTTClient_isConnected(client) == 0) {
                g_gw_mqtt_ready = 0;
                MQTTClient_destroy(&client);
                client = NULL;
                while (gw_mqtt_connect(&client) != 0) {
                    osal_msleep(10000);
                }
                g_gw_mqtt_ready = 1;
                osal_printk("%s gateway re-online\r\n", GW_LOG);
            }
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
            MQTTClient_disconnect(client, 10000);
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
{
    osal_task *task_handle = NULL;
    osal_kthread_lock();
#if defined(CONFIG_SAMPLE_SUPPORT_SLE_UART_SERVER_SAMPLE)
    task_handle =
        osal_kthread_create((osal_kthread_handler)sle_uart_server_task, 0, "SLEUartServer", SLE_UART_TASK_STACK_SIZE);
#elif defined(CONFIG_SAMPLE_SUPPORT_SLE_UART_CLIENT_SAMPLE)
    task_handle =
        osal_kthread_create((osal_kthread_handler)sle_uart_client_task, 0, "SLEUartClient", SLE_UART_TASK_STACK_SIZE);
#if defined(CONFIG_SAMPLE_SUPPORT_SLE_UART_CLIENT_SAMPLE)
    /* Local bridge variant: RK2206 owns cloud access and alarm decisions.
     * Do not start Wi-Fi scanning or MQTT retries on this gateway. */
    (void)sle_uart_gw_task;
    osal_printk("[sy bridge] local-only, UART1 TX=GPIO15 RX=GPIO16 115200\r\n");
#endif
#endif
    if (task_handle != NULL) {
        osal_kthread_set_priority(task_handle, SLE_UART_TASK_PRIO);
    }
    osal_kthread_unlock();
}

app_run(sle_uart_entry);
