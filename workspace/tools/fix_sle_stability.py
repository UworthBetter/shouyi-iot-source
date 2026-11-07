"""Patch terminal stack and gateway synchronous MQTT servicing (with backups)."""
from pathlib import Path
import shutil
import sys

def patch(path, changes):
    data = path.read_text(encoding="utf-8")
    original = data
    for old, new in changes:
        if new in data:
            continue
        if data.count(old) != 1:
            raise RuntimeError(f"Expected one anchor in {path}: {old[:80]!r}")
        data = data.replace(old, new, 1)
    if data != original:
        backup = path.with_suffix(path.suffix + ".bak_pre_stability")
        if not backup.exists():
            shutil.copy2(path, backup)
        path.write_text(data, encoding="utf-8", newline="\n")
    print(f"Verified stability patch: {path}")

if sys.argv[1] == "terminal":
    patch(Path("/root/fbb_bs2x/src/application/samples/products/sle_uart/sle_uart.c"), [
        ("#define SLE_UART_REPORT_INTERVAL_MS 2000", "#define SLE_UART_REPORT_INTERVAL_MS 2000\n#define SLE_UART_REPORT_STACK_SIZE 0x2000 /* SLE notify + formatting need more than 2 KB */"),
        ('"SLEUartRptTask", 0x800);', '"SLEUartRptTask", SLE_UART_REPORT_STACK_SIZE);'),
    ])
elif sys.argv[1] == "gateway":
    patch(Path(r"D:\sdk\nearlink\fbb_ws63\src\application\samples\bt\sle\sle_uart\sle_uart.c"), [
        ("    return MQTTClient_publishMessage(client, GW_PUB_TOPIC, &pubmsg, &token);",
         "    int32_t rc = MQTTClient_publishMessage(client, GW_PUB_TOPIC, &pubmsg, &token);\n"
         "    if (rc == MQTTCLIENT_SUCCESS) {\n"
         "        /* Synchronous client must process PUBACK before the next publish. */\n"
         "        rc = MQTTClient_waitForCompletion(client, token, 5000);\n"
         "    }\n"
         '    osal_printk("%s publish completion rc=%d\\r\\n", GW_LOG, rc);\n'
         "    return rc;"),
        ('        if (osal_msg_queue_read_copy(g_gw_pubq_id, rx_buf, &rx_len, 0xFFFFFFFF) != OSAL_SUCCESS) {\n            continue;\n        }',
         '        /* Keep servicing MQTT even when the SLE terminal is disconnected. */\n'
         '        if (osal_msg_queue_read_copy(g_gw_pubq_id, rx_buf, &rx_len, 100) != OSAL_SUCCESS) {\n'
         '            MQTTClient_yield();\n'
         '            if (MQTTClient_isConnected(client) == 0) {\n'
         '                g_gw_mqtt_ready = 0;\n'
         '                MQTTClient_destroy(&client);\n'
         '                client = NULL;\n'
         '                while (gw_mqtt_connect(&client) != 0) {\n'
         '                    osal_msleep(10000);\n'
         '                }\n'
         '                g_gw_mqtt_ready = 1;\n'
         '                osal_printk("%s gateway re-online\\r\\n", GW_LOG);\n'
         '            }\n'
         '            continue;\n'
         '        }'),
    ])
else:
    raise SystemExit("Expected terminal or gateway")
