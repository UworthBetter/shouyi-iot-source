#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
T板(bs21e) sle_uart server 增加"连接后周期上报"任务 —— 数据通路验证 + 终端周期上报业务骨架
每 2 秒: 若客户端已连接, 经 SLE notify 发一条测试 JSON 并在调试口打印
幂等: 重复运行自动跳过
"""
import shutil
import sys

SLE = "/root/fbb_bs2x/src/application/samples/products/sle_uart/sle_uart.c"

REPORT_TASK = (
    "/* ---- shouyi: periodic report task (data-path verify + terminal report skeleton) ---- */\n"
    "#define SLE_UART_REPORT_INTERVAL_MS 2000\n"
    "static uint32_t g_sle_uart_report_seq = 0;\n\n"
    "static void *sle_uart_server_report_task(const char *arg)\n"
    "{\n"
    "    unused(arg);\n"
    "    char buf[96];\n"
    "    while (1) {\n"
    "        osal_msleep(SLE_UART_REPORT_INTERVAL_MS);\n"
    "        if (!sle_uart_client_is_connected()) {\n"
    "            continue;\n"
    "        }\n"
    "        g_sle_uart_report_seq++;\n"
    "        int n = snprintf(buf, sizeof(buf),\n"
    "            \"{\\\"seq\\\":%u,\\\"dev\\\":\\\"sy-t-001\\\",\\\"ping\\\":true}\\r\\n\", g_sle_uart_report_seq);\n"
    "        if (n > 0 && n < (int)sizeof(buf)) {\n"
    "            sle_uart_server_send_report_by_handle((uint8_t *)buf, (uint16_t)n);\n"
    "            osal_printk(\"[sle uart server] report #%u sent %d bytes\\r\\n\", g_sle_uart_report_seq, n);\n"
    "        }\n"
    "    }\n"
    "    return NULL;\n"
    "}\n\n"
    "static void sle_uart_entry(void)\n"
)

ENTRY_ADD = (
    "    task_handle = osal_kthread_create((osal_kthread_handler)sle_uart_server_task, 0, \"SLEUartServerTask\",\n"
    "                                      SLE_UART_TASK_STACK_SIZE);\n"
    "    osal_task *rpt_handle = osal_kthread_create((osal_kthread_handler)sle_uart_server_report_task, 0,\n"
    "                                                \"SLEUartRptTask\", 0x800);\n"
    "    if (rpt_handle != NULL) {\n"
    "        osal_kthread_set_priority(rpt_handle, SLE_UART_TASK_PRIO);\n"
    "    }\n"
)

with open(SLE, "r", encoding="utf-8") as f:
    text = f.read()

if "sle_uart_server_report_task" in text:
    print("already patched, skip")
    sys.exit(0)

shutil.copyfile(SLE, SLE + ".bak_pre_periodic")

anchor_entry = "static void sle_uart_entry(void)\n"
if text.count(anchor_entry) != 1:
    sys.exit("entry anchor count=%d" % text.count(anchor_entry))
text = text.replace(anchor_entry, REPORT_TASK, 1)

anchor_create = ('    task_handle = osal_kthread_create((osal_kthread_handler)sle_uart_server_task, 0, "SLEUartServerTask",\n'
                 "                                      SLE_UART_TASK_STACK_SIZE);\n")
if anchor_create not in text:
    sys.exit("task-create anchor not found")
text = text.replace(anchor_create, ENTRY_ADD, 1)

# stdio for snprintf
anchor_inc = '#include "platform_core.h" /* shouyi: PIN_NONE & pin enums */\n'
if anchor_inc in text and "#include <stdio.h>" not in text:
    text = text.replace(anchor_inc, anchor_inc + "#include <stdio.h> /* shouyi: snprintf */\n", 1)

with open(SLE, "w", encoding="utf-8") as f:
    f.write(text)
print("periodic report task patched")
