/**
 * Copyright (c) HiSilicon (Shanghai) Technologies Co., Ltd. 2023-2023. All rights reserved.
 *
 * Description: SLE UART Sample Source. \n
 *
 * History: \n
 * 2023-07-17, Create file. \n
 */
#include "common_def.h"
#include "soc_osal.h"
#include "app_init.h"
#include "uart.h"
#include "gpio.h"
#include "pinctrl.h"
#include "pm_clock.h"
#include "platform_core.h" /* shouyi: PIN_NONE & pin enums */
#include <stdio.h> /* shouyi: snprintf */
static errcode_t sle_uart_data_uart_init(void); /* shouyi fwd decl: helper is defined after the role blocks */
#include "sle_low_latency.h"
#if defined(CONFIG_SAMPLE_ENABLE_SLE_UART_SERVER)
#include "securec.h"
#include "sle_uart_server.h"
#include "sle_uart_server_adv.h"
#include "sle_device_discovery.h"
#include "sle_errcode.h"
#elif defined(CONFIG_SAMPLE_ENABLE_SLE_UART_CLIENT)
#define SLE_UART_TASK_STACK_SIZE            0x600
#define SLE_UART_SSAPC_PRINTF_LOG_INTERVAL     50
static uint16_t g_ssapc_recv_pkts = 0;
#include "sle_connection_manager.h"
#include "sle_ssap_client.h"
#include "sle_uart_client.h"
#endif  /* CONFIG_SAMPLE_ENABLE_SLE_UART_CLIENT */

#define SLE_UART_TASK_PRIO                  28
#define SLE_UART_TASK_DURATION_MS           2000
#if defined(CONFIG_SAMPLE_ENABLE_SLE_UART_SERVER)
#define SLE_UART_SERVER_DELAY_COUNT         5

#define SLE_UART_TASK_STACK_SIZE            0x1200
#define SLE_ADV_HANDLE_DEFAULT              1
#define SLE_UART_SERVER_MSG_QUEUE_LEN       5
#define SLE_UART_SERVER_MSG_QUEUE_MAX_SIZE  32
#define SLE_UART_SERVER_QUEUE_DELAY         0xFFFFFFFF
#define SLE_UART_SERVER_BUFF_MAX_SIZE       800
#ifdef CONFIG_SAMPLE_SUPPORT_PERFORMANCE_TYPE
#define SLE_UART_SERVER_SEND_BUFF_MAX_LEN   250
#else
#define SLE_UART_SERVER_SEND_BUFF_MAX_LEN   40
#endif
unsigned long g_sle_uart_server_msgqueue_id;
#define SLE_UART_SERVER_LOG                 "[sle uart server]"
static void ssaps_server_read_request_cbk(uint8_t server_id, uint16_t conn_id, ssaps_req_read_cb_t *read_cb_para,
    errcode_t status)
{
    unused(server_id); unused(conn_id); unused(read_cb_para); unused(status);
}
static void ssaps_server_write_request_cbk(uint8_t server_id, uint16_t conn_id, ssaps_req_write_cb_t *write_cb_para,
    errcode_t status)
{
    unused(server_id); unused(conn_id); unused(status);
    if ((write_cb_para->length > 0) && write_cb_para->value) {
        osal_printk("%s recv %u bytes from client: %.*s\r\n", SLE_UART_SERVER_LOG,
            write_cb_para->length, write_cb_para->length, (const char *)write_cb_para->value);
    }
    if ((write_cb_para->length > 0) && write_cb_para->value) {
        uapi_uart_write(CONFIG_SLE_UART_BUS, (uint8_t *)write_cb_para->value, write_cb_para->length, 0);
    }
}

#ifdef CONFIG_SAMPLE_SUPPORT_LOW_LATENCY_TYPE
uint8_t g_buff[SLE_UART_SERVER_BUFF_MAX_SIZE] = {0};
uint16_t g_uart_buff_len = 0;
uint8_t g_buff_data_valid = 0;
#endif
static void sle_uart_server_read_int_handler(const void *buffer, uint16_t length, bool error)
{
    unused(error);
    osal_printk("%s uart rx %u bytes: %.*s\r\n", SLE_UART_SERVER_LOG, length, length,
        (const char *)buffer);
    if (sle_uart_client_is_connected()) {
#ifdef CONFIG_SAMPLE_SUPPORT_LOW_LATENCY_TYPE
    g_buff_data_valid = 1;
    g_uart_buff_len = 0;
    (void)memcpy_s(g_buff, SLE_UART_SERVER_SEND_BUFF_MAX_LEN, buffer, length);
    g_uart_buff_len = length;
#else
    sle_uart_server_send_report_by_handle(buffer, length);
#endif
    } else {
        osal_printk("%s sle client is not connected! \r\n", SLE_UART_SERVER_LOG);
    }
}

#ifdef CONFIG_SAMPLE_SUPPORT_LOW_LATENCY_TYPE
uint8_t *sle_uart_low_latency_tx_cbk(uint16_t *len)
{
#ifdef CONFIG_SAMPLE_SUPPORT_PERFORMANCE_TYPE
    if (sle_uart_client_is_connected()) {
        g_uart_buff_len = SLE_UART_SERVER_SEND_BUFF_MAX_LEN;
        g_buff_data_valid = 1;
    }
#endif
    if (g_buff_data_valid == 0) {
        return NULL;
    }
    if (g_uart_buff_len == 0) {
        return NULL;
    }
    *len = g_uart_buff_len;
    g_buff_data_valid = 0;
    return g_buff;
}

void sle_uart_low_latency_tx_cbk_register(void)
{
    sle_low_latency_tx_callbacks_t cbk_func = {0};
    cbk_func.low_latency_tx_cb = sle_uart_low_latency_tx_cbk;
    sle_low_latency_tx_register_callbacks(&cbk_func);
}
#endif

static void sle_uart_server_create_msgqueue(void)
{
    if (osal_msg_queue_create("sle_uart_server_msgqueue", SLE_UART_SERVER_MSG_QUEUE_LEN, \
        (unsigned long *)&g_sle_uart_server_msgqueue_id, 0, SLE_UART_SERVER_MSG_QUEUE_MAX_SIZE) != OSAL_SUCCESS) {
        osal_printk("^%s sle_uart_server_create_msgqueue message queue create failed!\n", SLE_UART_SERVER_LOG);
    }
}

static void sle_uart_server_delete_msgqueue(void)
{
    osal_msg_queue_delete(g_sle_uart_server_msgqueue_id);
}

static void sle_uart_server_write_msgqueue(uint8_t *buffer_addr, uint16_t buffer_size)
{
    int msg_ret = osal_msg_queue_write_copy(g_sle_uart_server_msgqueue_id, (void *)buffer_addr,
        (uint32_t)buffer_size, 0);
    if (msg_ret != OSAL_SUCCESS) {
        osal_printk("msg queue write copy fail.");
        osal_vfree(buffer_addr);
    }
}

static int32_t sle_uart_server_receive_msgqueue(uint8_t *buffer_addr, uint32_t *buffer_size)
{
    return osal_msg_queue_read_copy(g_sle_uart_server_msgqueue_id, (void *)buffer_addr, \
                                    buffer_size, SLE_UART_SERVER_QUEUE_DELAY);
}
static void sle_uart_server_rx_buf_init(uint8_t *buffer_addr, uint32_t *buffer_size)
{
    *buffer_size = SLE_UART_SERVER_MSG_QUEUE_MAX_SIZE;
    (void)memset_s(buffer_addr, *buffer_size, 0, *buffer_size);
}

static void *sle_uart_server_task(const char *arg)
{
    unused(arg);
    uint8_t rx_buf[SLE_UART_SERVER_MSG_QUEUE_MAX_SIZE] = {0};
    uint32_t rx_length = SLE_UART_SERVER_MSG_QUEUE_MAX_SIZE;
    uint8_t sle_connect_state[] = "sle_dis_connect";
    sle_dev_register_cbks();
    sle_uart_server_create_msgqueue();
    sle_uart_server_register_msg(sle_uart_server_write_msgqueue);
    sle_uart_server_init(ssaps_server_read_request_cbk, ssaps_server_write_request_cbk);
#ifdef CONFIG_SAMPLE_SUPPORT_LOW_LATENCY_TYPE
    sle_uart_low_latency_tx_cbk_register();
#endif
    sle_uart_server_adv_init();
    sle_uart_data_uart_init();
    errcode_t ret = uapi_uart_register_rx_callback(CONFIG_SLE_UART_BUS,
                                                   UART_RX_CONDITION_FULL_OR_SUFFICIENT_DATA_OR_IDLE,
                                                   1, sle_uart_server_read_int_handler);
    if (ret != ERRCODE_SUCC) {
        osal_printk("%s Register uart callback fail.[%x]\r\n", SLE_UART_SERVER_LOG, ret);
        return NULL;
    }
    while (1) {
        sle_uart_server_rx_buf_init(rx_buf, &rx_length);
        sle_uart_server_receive_msgqueue(rx_buf, &rx_length);
        if (strncmp((const char *)rx_buf, (const char *)sle_connect_state, sizeof(sle_connect_state)) == 0) {
            ret = sle_start_announce(SLE_ADV_HANDLE_DEFAULT);
            if (ret != ERRCODE_SLE_SUCCESS) {
                osal_printk("%s sle_connect_state_changed_cbk,sle_start_announce fail :%02x\r\n",
                    SLE_UART_SERVER_LOG, ret);
            }
        }
        osal_msleep(SLE_UART_TASK_DURATION_MS);
    }
    sle_uart_server_delete_msgqueue();
    return NULL;
}
#elif defined(CONFIG_SAMPLE_ENABLE_SLE_UART_CLIENT)

void sle_uart_notification_cb(uint8_t client_id, uint16_t conn_id, ssapc_handle_value_t *data,
    errcode_t status)
{
    unused(client_id);
    unused(conn_id);
    unused(status);
    if (++g_ssapc_recv_pkts % SLE_UART_SSAPC_PRINTF_LOG_INTERVAL == 0) {
        osal_printk("sle_uart_notification_cb, recv pkts %u, pkt_len %u\r\n", g_ssapc_recv_pkts, data->data_len);
    }
    uapi_uart_write(CONFIG_SLE_UART_BUS, (uint8_t *)(data->data), data->data_len, 0);
}

void sle_uart_indication_cb(uint8_t client_id, uint16_t conn_id, ssapc_handle_value_t *data,
    errcode_t status)
{
    unused(client_id);
    unused(conn_id);
    unused(status);
    osal_printk("\n sle uart recived data : %s\r\n", data->data);
    uapi_uart_write(CONFIG_SLE_UART_BUS, (uint8_t *)(data->data), data->data_len, 0);
}

static void sle_uart_client_read_int_handler(const void *buffer, uint16_t length, bool error)
{
    unused(error);
    osal_printk("[sle uart client] uart rx %u bytes\r\n", length);
    ssapc_write_param_t *sle_uart_send_param = get_g_sle_uart_send_param();
    uint16_t g_sle_uart_conn_id = get_g_sle_uart_conn_id();
    sle_uart_send_param->data_len = length;
    sle_uart_send_param->data = (uint8_t *)buffer;
    ssapc_write_req(0, g_sle_uart_conn_id, sle_uart_send_param);
}

static void *sle_uart_client_task(const char *arg)
{
    unused(arg);
    sle_uart_client_sample_dev_cbk_register();
    sle_uart_data_uart_init();
    errcode_t ret = uapi_uart_register_rx_callback(CONFIG_SLE_UART_BUS,
                                                   UART_RX_CONDITION_FULL_OR_SUFFICIENT_DATA_OR_IDLE,
                                                   1, sle_uart_client_read_int_handler);
    if (ret != ERRCODE_SUCC) {
        osal_printk("Register uart callback fail.");
        return NULL;
    }

    return NULL;
}
#endif  /* CONFIG_SAMPLE_ENABLE_SLE_UART_CLIENT */

/* ---- shouyi: data uart bridge init ----
 * UART_BUS_2(L1): porting 表引脚为 PIN_NONE, claim_pins 不碰物理引脚,
 * 不干扰日志口(bus1)/烧录口(bus0)。tx/rx 传 17/18 仅为通过参数校验。
 * 后续接实体传感器时, 改 uart_porting.c 的 g_pin_config_map[UART_BUS_2] 换真实引脚。
 */
#define SLE_UART_DATA_BAUD 115200
static uint8_t g_sle_uart_data_rx_buffer[512];

static errcode_t sle_uart_data_uart_init(void)
{
    uart_attr_t attr = {0};
    attr.baud_rate = SLE_UART_DATA_BAUD;
    attr.data_bits = UART_DATA_BIT_8;
    attr.stop_bits = UART_STOP_BIT_1;
    attr.parity = UART_PARITY_NONE;
    uart_pin_config_t pins = {0};
    pins.tx_pin = S_MGPIO17;
    pins.rx_pin = S_MGPIO18;
    pins.cts_pin = PIN_NONE;
    pins.rts_pin = PIN_NONE;
    uart_buffer_config_t buf = {0};
    buf.rx_buffer = g_sle_uart_data_rx_buffer;
    buf.rx_buffer_size = sizeof(g_sle_uart_data_rx_buffer);
    uapi_uart_deinit((uart_bus_t)CONFIG_SLE_UART_BUS);
    errcode_t ret = uapi_uart_init((uart_bus_t)CONFIG_SLE_UART_BUS, &pins, &attr, NULL, &buf);
    osal_printk("[sle uart] data uart init bus=%d ret=0x%x\r\n", CONFIG_SLE_UART_BUS, ret);
    return ret;
}

/* ---- shouyi: periodic report task (data-path verify + terminal report skeleton) ---- */
#define SLE_UART_REPORT_INTERVAL_MS 2000
#define SLE_UART_REPORT_STACK_SIZE 0x2000 /* SLE notify + formatting need more than 2 KB */
static uint32_t g_sle_uart_report_seq = 0;

#define SHOUYI_PIR_GPIO S_MGPIO21
#define SHOUYI_PIR_WARMUP_MS 60000

static void *sle_uart_server_report_task(const char *arg)
{
    unused(arg);
    uapi_gpio_init();
    errcode_t rc = uapi_pin_set_mode(SHOUYI_PIR_GPIO, HAL_PIO_FUNC_GPIO);
    if (rc == ERRCODE_SUCC) {
        rc = uapi_pin_set_ie(SHOUYI_PIR_GPIO, PIN_IE_1);
    }
    if (rc == ERRCODE_SUCC) {
        rc = uapi_pin_set_pull(SHOUYI_PIR_GPIO, PIN_PULL_DOWN);
    }
    if (rc == ERRCODE_SUCC) {
        rc = uapi_gpio_set_dir(SHOUYI_PIR_GPIO, GPIO_DIRECTION_INPUT);
    }
    if (rc != ERRCODE_SUCC) {
        osal_printk("[sy pir] GPIO21 init failed rc=0x%x\r\n", rc);
        return NULL;
    }
    osal_printk("[sy pir] GPIO21 warmup=60s\r\n");
    uint32_t warmup_ms = 0;
    char buf[128];
    while (1) {
        osal_msleep(SLE_UART_REPORT_INTERVAL_MS);
        if (warmup_ms < SHOUYI_PIR_WARMUP_MS) {
            warmup_ms += SLE_UART_REPORT_INTERVAL_MS;
        }
        int level = uapi_gpio_get_val(SHOUYI_PIR_GPIO) == GPIO_LEVEL_HIGH;
        osal_printk("[sy pir] GPIO21=%d ready=%d\r\n", level, warmup_ms >= SHOUYI_PIR_WARMUP_MS);
        if (!sle_uart_client_is_connected()) {
            continue;
        }
        g_sle_uart_report_seq++;
        int n = snprintf(buf, sizeof(buf),
            "{\"seq\":%u,\"dev\":\"sy-t-001\",\"pir\":%s,\"pirReady\":%s}\r\n",
            g_sle_uart_report_seq, level ? "true" : "false",
            warmup_ms >= SHOUYI_PIR_WARMUP_MS ? "true" : "false");
        if (n > 0 && n < (int)sizeof(buf)) {
            sle_uart_server_send_report_by_handle((uint8_t *)buf, (uint16_t)n);
            osal_printk("[sy pir] tx %s", buf);
        }
    }
    return NULL;
}

static void sle_uart_entry(void)
{
    osal_task *task_handle = NULL;
    if (uapi_clock_control(CLOCK_CONTROL_FREQ_LEVEL_CONFIG, CLOCK_FREQ_LEVEL_HIGH) == ERRCODE_SUCC) {
        
    } else {
        osal_printk("Clock config fail.\r\n");
    }
    osal_kthread_lock();
#if defined(CONFIG_SAMPLE_ENABLE_SLE_UART_SERVER)
    task_handle = osal_kthread_create((osal_kthread_handler)sle_uart_server_task, 0, "SLEUartServerTask",
                                      SLE_UART_TASK_STACK_SIZE);
    osal_task *rpt_handle = osal_kthread_create((osal_kthread_handler)sle_uart_server_report_task, 0,
                                                "SLEUartRptTask", SLE_UART_REPORT_STACK_SIZE);
    if (rpt_handle != NULL) {
        osal_kthread_set_priority(rpt_handle, SLE_UART_TASK_PRIO);
    }
#elif defined(CONFIG_SAMPLE_ENABLE_SLE_UART_CLIENT)
    task_handle = osal_kthread_create((osal_kthread_handler)sle_uart_client_task, 0, "SLEUartDongleTask",
                                      SLE_UART_TASK_STACK_SIZE);
#endif /* CONFIG_SAMPLE_ENABLE_SLE_UART_CLIENT */
    if (task_handle != NULL) {
        osal_kthread_set_priority(task_handle, SLE_UART_TASK_PRIO);
    }
    osal_kthread_unlock();
}

/* Run the sle_uart_entry. */
app_run(sle_uart_entry);