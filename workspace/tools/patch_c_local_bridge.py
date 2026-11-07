"""Prepare a local-only SLE-to-UART gateway; retain cloud code for rollback."""
from pathlib import Path
import shutil

SDK = Path(r"D:\sdk\nearlink\fbb_ws63\src")
source = SDK / "application/samples/bt/sle/sle_uart/sle_uart.c"
text = source.read_text(encoding="utf-8")
marker = "/* SHOUYI_LOCAL_BRIDGE: no Wi-Fi prerequisite */"
if marker in text:
    print("Local bridge already installed")
    raise SystemExit(0)
old_wait = '''    /* WiFi 优先: IP 未就绪前不占射频找网, 避免共存调度互卡 */
    while (!g_wifi_ip_up) {
        osal_msleep(500);
    }
'''
assert old_wait in text, "Wi-Fi wait anchor missing"
text = text.replace(old_wait, "    " + marker + "\n", 1)
old_task = '''    osal_task *gw_handle =
        osal_kthread_create((osal_kthread_handler)sle_uart_gw_task, 0, "SLEGwTask", GW_TASK_STACK);
    if (gw_handle != NULL) {
        osal_kthread_set_priority(gw_handle, GW_TASK_PRIO);
    }'''
assert old_task in text, "Cloud task anchor missing"
text = text.replace(old_task, '''    /* Local bridge variant: RK2206 owns cloud access and alarm decisions.
     * Do not start Wi-Fi scanning or MQTT retries on this gateway. */
    (void)sle_uart_gw_task;
    osal_printk("[sy bridge] local-only, UART1 TX=GPIO15 RX=GPIO16 115200\\r\\n");''', 1)
shutil.copy2(source, str(source) + ".bak_pre_local_bridge")
source.write_text(text, encoding="utf-8", newline="\n")
print("Installed local-only gateway source; not flashed")
