/* Shouyi single-hop SLE application relay. The terminal stays unchanged. */
#include "common_def.h"
#include "soc_osal.h"
#include "app_init.h"
#include "sle_uart_client.h"
#include "sle_uart_server.h"
#include "sle_errcode.h"
#include <string.h>
#include <stdio.h>

#define RELAY_MAX_INPUT 400
typedef struct {
    uint16_t len;
    uint8_t data[RELAY_MAX_INPUT];
} relay_packet_t;
static unsigned long g_relay_queue;
static uint32_t g_received;
static uint32_t g_forwarded;
static uint32_t g_dropped;
ssapc_write_param_t g_write_param;

static void relay_notification(uint8_t client_id, uint16_t conn_id,
                               ssapc_handle_value_t *data, errcode_t status)
{
    unused(client_id);
    if (status != 0 || data == NULL || data->data == NULL ||
        data->data_len == 0 || data->data_len > RELAY_MAX_INPUT || conn_id != g_conn_id) {
        return;
    }
    relay_packet_t packet;
    packet.len = data->data_len;
    memcpy(packet.data, data->data, packet.len);
    g_received++;
    if (osal_msg_queue_write_copy(g_relay_queue, &packet, sizeof(packet), 0) != OSAL_SUCCESS) {
        g_dropped++;
        osal_printk("[sy relay] queue drop=%u\r\n", g_dropped);
    }
}

static void *relay_task(const char *arg)
{
    unused(arg);
    if (osal_msg_queue_create("sy_relay", 8, &g_relay_queue, 0, sizeof(relay_packet_t)) != OSAL_SUCCESS) {
        osal_printk("[sy relay] queue creation failed\r\n");
        return NULL;
    }
    osal_printk("[sy relay] start: terminal -> sy-r-001 -> gateway; stack=8192\r\n");
    sle_uart_client_init(relay_notification, NULL);
    while (1) {
        relay_packet_t packet;
        uint32_t length = sizeof(packet);
        if (osal_msg_queue_read_copy(g_relay_queue, &packet, &length, 100) != OSAL_SUCCESS) {
            continue;
        }
        if (length != sizeof(packet) || packet.len == 0 || packet.len > RELAY_MAX_INPUT) {
            continue;
        }
        /* Keep one pending packet while the gateway reconnects. */
        while (!sle_uart_server_is_connected()) {
            osal_msleep(200);
        }
        char output[480];
        uint16_t n = packet.len;
        while (n && (packet.data[n - 1] == '\r' || packet.data[n - 1] == '\n' ||
                     packet.data[n - 1] == ' ' || packet.data[n - 1] == '\t')) {
            n--;
        }
        int out_len;
        if (n >= 2 && packet.data[0] == '{' && packet.data[n - 1] == '}') {
            out_len = snprintf(output, sizeof(output), "%.*s,\"via\":\"sy-r-001\"}\r\n",
                               (int)n - 1, (char *)packet.data);
        } else {
            memcpy(output, packet.data, packet.len);
            out_len = packet.len;
        }
        if (out_len <= 0 || out_len >= (int)sizeof(output)) {
            g_dropped++;
            continue;
        }
        errcode_t rc = sle_uart_server_send_notification((uint8_t *)output, (uint16_t)out_len);
        if (rc == 0) {
            g_forwarded++;
        } else {
            g_dropped++;
        }
        osal_printk("[sy relay] received=%u forwarded=%u dropped=%u rc=0x%x data=%.*s\r\n",
                    g_received, g_forwarded, g_dropped, rc, out_len, output);
    }
    return NULL;
}

static void relay_entry(void)
{
    /* app_run executes before scheduling starts; match the SDK sample's guard. */
    osal_kthread_lock();
    osal_task *task = osal_kthread_create((osal_kthread_handler)relay_task, 0, "ShouyiRelay", 0x2000);
    if (task != NULL) {
        osal_kthread_set_priority(task, 28);
    }
    osal_kthread_unlock();
}
app_run(relay_entry);
