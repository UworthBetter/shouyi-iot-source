#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
T板(H2821/bs21e) sle_uart 服务端启用补丁
1. standard_bs21e_1100e.config: 开 SAMPLE_ENABLE + products + SLE_UART server, 数据串口 bus=2
2. sle_uart.c: 加数据串口初始化 + 收发两端调试打印 (SLE<->应用 数据通路验证用)
数据串口选 UART_BUS_2(L1): porting 表里引脚为 PIN_NONE, claim_pins 不动任何物理引脚,
绝不干扰 日志口(bus1) / 烧录口(bus0)。传 17/18 只为通过 init 参数校验。
"""
import shutil
import sys

ROOT = "/root/fbb_bs2x/src"
CFG = ROOT + "/build/config/target_config/bs21e/menuconfig/acore/standard_bs21e_1100e.config"
SLE = ROOT + "/application/samples/products/sle_uart/sle_uart.c"


def patch_config():
    with open(CFG, "r", encoding="utf-8") as f:
        text = f.read()
    bak = CFG + ".bak_pre_sle"
    shutil.copyfile(CFG, bak)
    old = "# CONFIG_SAMPLE_ENABLE is not set"
    if old not in text:
        if "CONFIG_SAMPLE_ENABLE=y" in text:
            print("config: SAMPLE_ENABLE already on, skip replace")
        else:
            sys.exit("config: anchor line not found!")
    else:
        text = text.replace(old, "CONFIG_SAMPLE_ENABLE=y", 1)
    add = (
        "CONFIG_ENABLE_PRODUCTS_SAMPLE=y\n"
        "CONFIG_SAMPLE_SUPPORT_SLE_UART=y\n"
        "CONFIG_SAMPLE_ENABLE_SLE_UART_SERVER=y\n"
        "CONFIG_SLE_UART_BUS=2\n"
    )
    for line in add.splitlines():
        key = line.split("=")[0]
        if key + "=" in text:
            print("config: %s already set, skip" % key)
            add = add.replace(line + "\n", "")
    if add:
        if not text.endswith("\n"):
            text += "\n"
        text += "# --- shouyi: enable sle_uart server sample ---\n" + add
    with open(CFG, "w", encoding="utf-8") as f:
        f.write(text)
    print("config patched (backup: %s)" % bak)


def patch_sle_uart():
    with open(SLE, "r", encoding="utf-8") as f:
        text = f.read()
    bak = SLE + ".bak_pre_sle"
    shutil.copyfile(SLE, bak)
    n = 0

    def sub(old, new, cnt=1):
        nonlocal text, n
        if new in text:
            print("sle_uart.c: already patched (skip): %s..." % new[:40])
            return
        if old not in text:
            sys.exit("sle_uart.c: anchor not found:\n" + old)
        text = text.replace(old, new, cnt)
        n += 1

    # 1) include platform_core.h (PIN_NONE / S_MGPIO17/18 / uart_bus_t)
    sub('#include "pm_clock.h"\n',
        '#include "pm_clock.h"\n#include "platform_core.h" /* shouyi: PIN_NONE & pin enums */\n')

    # 2) 数据串口初始化助手: 插在 sle_uart_entry 之前(两个角色分支之外的公共区)
    helper = (
        "/* ---- shouyi: data uart bridge init ----\n"
        " * UART_BUS_2(L1): porting 表引脚为 PIN_NONE, claim_pins 不碰物理引脚,\n"
        " * 不干扰日志口(bus1)/烧录口(bus0)。tx/rx 传 17/18 仅为通过参数校验。\n"
        " * 后续接实体传感器时, 改 uart_porting.c 的 g_pin_config_map[UART_BUS_2] 换真实引脚。\n"
        " */\n"
        "#define SLE_UART_DATA_BAUD 115200\n"
        "static uint8_t g_sle_uart_data_rx_buffer[512];\n\n"
        "static errcode_t sle_uart_data_uart_init(void)\n"
        "{\n"
        "    uart_attr_t attr = {0};\n"
        "    attr.baud_rate = SLE_UART_DATA_BAUD;\n"
        "    attr.data_bits = UART_DATA_BIT_8;\n"
        "    attr.stop_bits = UART_STOP_BIT_1;\n"
        "    attr.parity = UART_PARITY_NONE;\n"
        "    uart_pin_config_t pins = {0};\n"
        "    pins.tx_pin = S_MGPIO17;\n"
        "    pins.rx_pin = S_MGPIO18;\n"
        "    pins.cts_pin = PIN_NONE;\n"
        "    pins.rts_pin = PIN_NONE;\n"
        "    uart_buffer_config_t buf = {0};\n"
        "    buf.rx_buffer = g_sle_uart_data_rx_buffer;\n"
        "    buf.rx_buffer_size = sizeof(g_sle_uart_data_rx_buffer);\n"
        "    uapi_uart_deinit((uart_bus_t)CONFIG_SLE_UART_BUS);\n"
        "    errcode_t ret = uapi_uart_init((uart_bus_t)CONFIG_SLE_UART_BUS, &pins, &attr, NULL, &buf);\n"
        "    osal_printk(\"[sle uart] data uart init bus=%d ret=0x%x\\r\\n\", CONFIG_SLE_UART_BUS, ret);\n"
        "    return ret;\n"
        "}\n\n"
        "static void sle_uart_entry(void)\n"
    )
    sub("static void sle_uart_entry(void)\n", helper)

    # 3) 服务端: 收到客户端 SLE 写请求时打印数据内容
    sub(
        '    osal_printk("%s ssaps write request callback cbk server_id:0x%x, conn_id:0x%x, handle:0x%x, status:0x%x\\r\\n",\n'
        "        SLE_UART_SERVER_LOG, server_id, conn_id, write_cb_para->handle, status);\n",
        '    osal_printk("%s ssaps write request callback cbk server_id:0x%x, conn_id:0x%x, handle:0x%x, status:0x%x\\r\\n",\n'
        "        SLE_UART_SERVER_LOG, server_id, conn_id, write_cb_para->handle, status);\n"
        "    if ((write_cb_para->length > 0) && write_cb_para->value) {\n"
        '        osal_printk("%s recv %u bytes from client: %.*s\\r\\n", SLE_UART_SERVER_LOG,\n'
        "            write_cb_para->length, write_cb_para->length, (const char *)write_cb_para->value);\n"
        "    }\n")

    # 4) 服务端: UART 收到数据打印(空中→应用方向证据)
    sub(
        "static void sle_uart_server_read_int_handler(const void *buffer, uint16_t length, bool error)\n"
        "{\n"
        "    unused(error);\n",
        "static void sle_uart_server_read_int_handler(const void *buffer, uint16_t length, bool error)\n"
        "{\n"
        "    unused(error);\n"
        '    osal_printk("%s uart rx %u bytes: %.*s\\r\\n", SLE_UART_SERVER_LOG, length, length,\n'
        "        (const char *)buffer);\n")

    # 5) 服务端任务: 注册 rx 回调前先初始化数据串口
    sub(
        "    sle_uart_server_adv_init();\n"
        "    errcode_t ret = uapi_uart_register_rx_callback(CONFIG_SLE_UART_BUS,",
        "    sle_uart_server_adv_init();\n"
        "    sle_uart_data_uart_init();\n"
        "    errcode_t ret = uapi_uart_register_rx_callback(CONFIG_SLE_UART_BUS,")

    # 6) 客户端任务: 同样初始化数据串口(角色对称, 将来 T 当客户端也能用)
    sub(
        "    sle_uart_client_sample_dev_cbk_register();\n"
        "    errcode_t ret = uapi_uart_register_rx_callback(CONFIG_SLE_UART_BUS,",
        "    sle_uart_client_sample_dev_cbk_register();\n"
        "    sle_uart_data_uart_init();\n"
        "    errcode_t ret = uapi_uart_register_rx_callback(CONFIG_SLE_UART_BUS,")

    # 7) 客户端 UART 收到数据打印
    sub(
        "static void sle_uart_client_read_int_handler(const void *buffer, uint16_t length, bool error)\n"
        "{\n"
        "    unused(error);\n",
        "static void sle_uart_client_read_int_handler(const void *buffer, uint16_t length, bool error)\n"
        "{\n"
        "    unused(error);\n"
        '    osal_printk("[sle uart client] uart rx %u bytes\\r\\n", length);\n')

    with open(SLE, "w", encoding="utf-8") as f:
        f.write(text)
    print("sle_uart.c patched, %d edits (backup: %s)" % (n, bak))


if __name__ == "__main__":
    patch_config()
    patch_sle_uart()
    print("ALL DONE")
