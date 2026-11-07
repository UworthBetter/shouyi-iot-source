"""Apply in WSL. Prepare a UART0 receiver and move 433 to PB0; do not flash."""
from pathlib import Path
import shutil

root = Path(__file__).resolve().parents[1]
app = Path('/root/txsmart/vendor/isoftstone/rk2206/samples/e1_iot_smart_home_hwiot')
if not app.exists():
    raise SystemExit('Run under WSL Ubuntu-24.04 as root')
changes = {}

def replace(path, old, new):
    text = changes.get(path, path.read_text(encoding='utf-8'))
    if new in text:
        return
    assert text.count(old) == 1, f'Anchor mismatch: {path} {old!r}'
    changes[path] = text.replace(old, new, 1)

replace(app / 'BUILD.gn', '    "src/smart_home.c",',
        '    "src/smart_home.c",\n    "src/nearlink_bridge.c",\n    "src/nearlink_protocol.c",')
smart = app / 'src/smart_home.c'
replace(smart, '#include "smart_home.h"', '#include "smart_home.h"\n#include "nearlink_bridge.h"')
replace(smart, '#define GPIO_433_D0 GPIO0_PB6', '#define GPIO_433_D0 GPIO0_PB0')
replace(smart, 'return value != IOT_GPIO_VALUE0;',
        'return value != IOT_GPIO_VALUE0 || nearlink_bridge_motion();')
replace(smart, '[sy 433] scan thread start (B6=433 D0, B7=door reed)',
        '[sy 433] scan thread start (B0=433 D0, B7=door reed)')
replace(smart, '[sy 433] B6=%d door=%d', '[sy 433] B0=%d door=%d')
replace(smart, 'void lcd_show_ui(void)\n{', '''void lcd_show_ui(void)
{
    /* Dedicated free row below the header; full-width padding clears old text. */
    char nl_raw[41];
    char nl_line[41];
    nearlink_bridge_status(nl_raw, sizeof(nl_raw));
    snprintf(nl_line, sizeof(nl_line), "%-40.40s", nl_raw);
    lcd_show_string(0, 38, (const uint8_t *)nl_line,
                    nearlink_bridge_online() ? LCD_GREEN : LCD_RED,
                    LCD_WHITE, 16, 0);''')
ex = app / 'iot_smart_home_example.c'
replace(ex, '#include "smart_home.h"', '#include "smart_home.h"\n#include "nearlink_bridge.h"')
replace(ex, '    alarm_dev_init();', '    alarm_dev_init();\n    nearlink_bridge_init();')

# Validate every anchor before changing existing files. Back up pre-session edits.
for path, text in changes.items():
    backup = Path(str(path) + '.bak_pre_local_bridge')
    if not backup.exists():
        shutil.copy2(path, backup)
    path.write_text(text, encoding='utf-8', newline='\n')
for name in ('nearlink_bridge.c', 'nearlink_protocol.c'):
    shutil.copy2(root / 'fw/local_bridge' / name, app / 'src' / name)
for name in ('nearlink_bridge.h', 'nearlink_protocol.h'):
    shutil.copy2(root / 'fw/local_bridge' / name, app / 'include' / name)
print('Prepared RK2206 local bridge. IMPORTANT: 433 D0 now PB0, UART RX PB6. Not flashed.')
