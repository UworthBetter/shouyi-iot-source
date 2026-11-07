"""Replace terminal ping reports with GPIO11 PIR sampling in the WSL SDK."""
from pathlib import Path
import shutil
import re

source = Path('/root/fbb_bs2x/src/application/samples/products/sle_uart/sle_uart.c')
text = source.read_text(encoding='utf-8')
if 'SHOUYI_PIR_GPIO' in text:
    raise SystemExit('PIR patch already present')
start = text.index('static void *sle_uart_server_report_task(const char *arg)')
end = text.index('static void sle_uart_entry(void)', start)
replacement = r'''#define SHOUYI_PIR_GPIO S_MGPIO11
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
        osal_printk("[sy pir] GPIO11 init failed rc=0x%x\r\n", rc);
        return NULL;
    }
    osal_printk("[sy pir] GPIO11 warmup=60s\r\n");
    uint32_t warmup_ms = 0;
    char buf[128];
    while (1) {
        osal_msleep(SLE_UART_REPORT_INTERVAL_MS);
        if (warmup_ms < SHOUYI_PIR_WARMUP_MS) {
            warmup_ms += SLE_UART_REPORT_INTERVAL_MS;
        }
        int level = uapi_gpio_get_val(SHOUYI_PIR_GPIO) == GPIO_LEVEL_HIGH;
        osal_printk("[sy pir] GPIO11=%d ready=%d\r\n", level, warmup_ms >= SHOUYI_PIR_WARMUP_MS);
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

'''
text = text[:start] + replacement + text[end:]
text = text.replace('#include "uart.h"', '#include "uart.h"\n#include "gpio.h"\n#include "pinctrl.h"', 1)
backup = source.with_suffix('.c.bak_pre_pir')
if not backup.exists():
    shutil.copy2(source, backup)
# Keep sensor diagnostics; remove verbose sample UART diagnostics to fit flash.
text = re.sub(r'    osal_printk\("%s ssaps read request.*?;',
              '    unused(server_id); unused(conn_id); unused(read_cb_para); unused(status);', text, flags=re.S)
text = re.sub(r'    osal_printk\("%s ssaps write request.*?;',
              '    unused(server_id); unused(conn_id); unused(status);', text, flags=re.S)
text = text.replace('osal_printk("Clock config succ.\\r\\n");', '')
source.write_text(text, encoding='utf-8', newline='\n')
print(f'PIR patch applied: {source}')
