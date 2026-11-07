"""Add distinct sensor sources to the RK2206 monitor payload."""
from pathlib import Path

workspace = Path(__file__).resolve().parents[1]
app = Path('/root/txsmart/vendor/isoftstone/rk2206/samples/e1_iot_smart_home_hwiot')
changes = {}


def replace(path, old, new):
    src = changes.get(path, path.read_text(encoding='utf-8'))
    if new in src:
        return
    if src.count(old) != 1:
        raise SystemExit(f'Unexpected source in {path}: {old!r}')
    changes[path] = src.replace(old, new, 1)


for directory in (workspace / 'fw/local_bridge', app / 'include'):
    replace(directory / 'nearlink_bridge.h', 'bool nearlink_bridge_online(void);',
            'bool nearlink_bridge_online(void);\n/* -2: no link, -1: warming, 0: idle, 1: motion */\nint nearlink_bridge_pir_state(void);')
for directory in (workspace / 'fw/local_bridge', app / 'src'):
    bridge = directory / 'nearlink_bridge.c'
    replace(bridge, 'static volatile bool s_motion;',
            'static volatile bool s_motion;\nstatic volatile int s_pir_state = -2;')
    replace(bridge, 'bool nearlink_bridge_online(void) { return s_online; }',
            'bool nearlink_bridge_online(void) { return s_online; }\nint nearlink_bridge_pir_state(void) { return s_pir_state; }')
    replace(bridge, '        s_ready = state.ready;',
            '        s_ready = state.ready;\n        s_pir_state = !online ? -2 : !state.ready ? -1 : motion ? 1 : 0;')

replace(app / 'src/smart_home.c', 'return value != IOT_GPIO_VALUE0 || nearlink_bridge_motion();',
        'return value != IOT_GPIO_VALUE0;')
example = app / 'iot_smart_home_example.c'
replace(example, '        pir = body_induction_get_state();',
        '        pir = body_induction_get_state();\n        int nearlink_pir = nearlink_bridge_pir_state();')
replace(example, '            iot_data.pir = pir;',
        '            iot_data.pir = pir || nearlink_pir == 1;\n            iot_data.pir_rk2206 = pir;\n            iot_data.pir_h2821 = nearlink_pir;')
replace(app / 'include/iot.h', '    bool pir;', '    bool pir;\n    bool pir_rk2206;\n    int pir_h2821;')
replace(app / 'src/iot.c', '    cJSON_AddBoolToObject(pro_obj, "pir", iot_data->pir);',
        '''    cJSON_AddBoolToObject(pro_obj, "pir", iot_data->pir);
    cJSON_AddBoolToObject(pro_obj, "pirRk2206", iot_data->pir_rk2206);
    cJSON_AddNumberToObject(pro_obj, "pirH2821", iot_data->pir_h2821);
    cJSON_AddNumberToObject(pro_obj, "illumination", iot_data->illumination);''')
replace(app / 'src/iot.c', '    strcpy(payload, palyload_str);',
        '''    if (palyload_str == NULL || strlen(palyload_str) >= sizeof(payload)) {
      cJSON_free(palyload_str);
      cJSON_Delete(root);
      return;
    }
    strcpy(payload, palyload_str);''')
replace(app / 'src/drv_sensors.c',
        '''    IoTI2cRead(I2C_HANDLE, BH1750_I2C_ADDRESS, recv_data, receive_len);
    *dat = (float)(((recv_data[0] << 8) + recv_data[1]) / 1.2);''',
        '''    if (IoTI2cRead(I2C_HANDLE, BH1750_I2C_ADDRESS, recv_data, receive_len) != 0) {
        *dat = -1;
        return;
    }
    *dat = (float)(((recv_data[0] << 8) + recv_data[1]) / 1.2);''')

for path, src in changes.items():
    path.write_text(src, encoding='utf-8', newline='\n')
