"""Install an isolated relay sample and select a reproducible build variant."""
from pathlib import Path
import argparse
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
SDK = Path(r"D:\sdk\nearlink\fbb_ws63\src")
SLE = SDK / "application/samples/bt/sle"
UART = SLE / "sle_uart"
CONFIG = SDK / "build/config/target_config/ws63/menuconfig/acore/ws63_liteos_app.config"
ARCHIVE = ROOT / "fw/configs"
ARCHIVE.mkdir(exist_ok=True)
BASE = ARCHIVE / "ws63_gateway_direct.config"
if not BASE.exists():
    shutil.copy2(CONFIG, BASE)

def replace_once(text, old, new):
    if text.count(old) != 1:
        raise RuntimeError(f"Expected one anchor: {old[:100]!r}")
    return text.replace(old, new, 1)

def edit_once(path, old, new):
    text = path.read_text(encoding="utf-8")
    if new in text:
        return
    backup = Path(str(path) + ".bak_pre_relay")
    if not backup.exists():
        shutil.copy2(path, backup)
    path.write_text(replace_once(text, old, new), encoding="utf-8", newline="\n")

def original(path):
    backup = Path(str(path) + ".bak_pre_relay")
    return (backup if backup.exists() else path).read_text(encoding="utf-8")

def install():
    target = SLE / "shouyi_relay"
    target.mkdir(exist_ok=True)
    generated = ROOT / "fw/relay_src"
    server_dir = UART / "sle_uart_server/src"
    client_dir = UART / "sle_uart_client/src"
    for name in ("sle_uart_server.h", "sle_uart_server_adv.h"):
        shutil.copy2(server_dir / name, generated / name)
    shutil.copy2(client_dir / "sle_uart_client.h", generated / "sle_uart_client.h")

    server = original(server_dir / "sle_uart_server.c")
    server = server.replace("static void sle_uart_server_connect_state_changed_cbk(",
                            "void relay_service_connection(")
    server = server.replace("sle_uart_server_connect_state_changed_cbk;", "relay_service_connection;")
    server = server.replace("static void sle_uart_server_pair_complete_cbk(", "void relay_service_pair(")
    server = server.replace("sle_uart_server_pair_complete_cbk;", "relay_service_pair;")
    # Server connection events are dispatched only for the upstream gateway.
    server = re.sub(r"        /\* Drain stale queued data\..*?\n        sle_start_announce",
                    "        sle_start_announce", server, count=1, flags=re.S)
    server = re.sub(r"static errcode_t sle_uart_server_conn_register_cbks\(void\)\n\{.*?\n\}\n",
                    "", server, count=1, flags=re.S)
    server = server.replace('addr->addr[BT_INDEX_4]);',
                            'addr->addr[BT_INDEX_4], addr->addr[SLE_ADDR_LEN - 1]);')
    start = server.index("errcode_t sle_uart_server_init(ssaps_read_request_callback")
    server = server[:start] + '''errcode_t sle_uart_server_init(ssaps_read_request_callback read_cb,
                                      ssaps_write_request_callback write_cb)
{
    g_read_cb = read_cb;
    g_write_cb = write_cb;
    errcode_t rc = sle_uart_server_ssaps_register_cbks();
    if (rc != 0) { return rc; }
    return sle_uart_server_add();
}
'''
    (generated / "relay_service.c").write_text(server, encoding="utf-8", newline="\n")

    adv = original(server_dir / "sle_uart_server_adv.c")
    adv = replace_once(adv, '"uart_server"', '"sy_relay"')
    adv = replace_once(adv, "0x01, 0x02, 0x03, 0x04, 0x05, 0x06", "0x01, 0x02, 0x03, 0x04, 0x05, 0x52")
    (generated / "relay_advertise.c").write_text(adv, encoding="utf-8", newline="\n")

    client = original(client_dir / "sle_uart_client.c")
    client = client.replace('#include "sle_uart_client.h"',
        '#include "sle_uart_client.h"\n#include "sle_uart_server.h"\n'
        '#include "sle_uart_server_adv.h"\n#include <string.h>\n'
        'void relay_service_connection(uint16_t, const sle_addr_t *, sle_acb_state_t, sle_pair_state_t, sle_disc_reason_t);\n'
        'void relay_service_pair(uint16_t, const sle_addr_t *, errcode_t);')
    client = replace_once(client, "    sle_uart_client_start_scan();\n}",
        '    if (status != 0) { return; }\n'
        '    if (sle_uart_server_init(NULL, NULL) != 0) {\n'
        '        osal_printk("[sy relay] server init failed\\r\\n");\n        return;\n    }\n'
        '    sle_uart_server_adv_init();\n    sle_uart_client_start_scan();\n}')
    client = replace_once(client, "    unused(addr);\n    unused(pair_state);",
        '    if (addr == NULL) { return; }\n'
        '    if (memcmp(addr->addr, g_remote_addr.addr, SLE_ADDR_LEN) != 0) {\n'
        '        relay_service_connection(conn_id, addr, conn_state, pair_state, disc_reason);\n'
        '        return;\n    }')
    client = re.sub(r"        /\* Drain stale queued data\..*?\n        sle_uart_client_start_scan",
                    "        sle_uart_client_start_scan", client, count=1, flags=re.S)
    anchor = '    osal_printk("%s pair complete conn_id:%d, addr:%02x***%02x%02x, status:%d\\r\\n",'
    client = replace_once(client, anchor,
        '    if (addr == NULL) { return; }\n'
        '    if (memcmp(addr->addr, g_remote_addr.addr, SLE_ADDR_LEN) != 0) {\n'
        '        relay_service_pair(conn_id, addr, status);\n        return;\n    }\n' + anchor)
    # Scan payloads are binary and are not guaranteed to be null-terminated.
    old = '    if (strstr((const char *)seek_result_data->data, SLE_UART_SERVER_NAME) != NULL) {'
    new = '''    bool matched = false;
    const size_t name_len = strlen(SLE_UART_SERVER_NAME);
    for (size_t i = 0; seek_result_data->data != NULL && i + name_len <= seek_result_data->data_length; i++) {
        if (memcmp(seek_result_data->data + i, SLE_UART_SERVER_NAME, name_len) == 0) {
            matched = true;
            break;
        }
    }
    if (matched) {'''
    client = replace_once(client, old, new)
    client = re.sub(r'    osal_printk\("%s scan data: %s\\r\\n", SLE_UART_CLIENT_LOG, seek_result_data->data\);',
                    '', client)
    (generated / "relay_client.c").write_text(client, encoding="utf-8", newline="\n")
    cmake = '''set(SOURCES ${SOURCES}
    ${CMAKE_CURRENT_SOURCE_DIR}/relay_main.c
    ${CMAKE_CURRENT_SOURCE_DIR}/relay_client.c
    ${CMAKE_CURRENT_SOURCE_DIR}/relay_service.c
    ${CMAKE_CURRENT_SOURCE_DIR}/relay_advertise.c)
set(PUBLIC_HEADER ${PUBLIC_HEADER} ${CMAKE_CURRENT_SOURCE_DIR})
set(SOURCES "${SOURCES}" PARENT_SCOPE)
set(PUBLIC_HEADER "${PUBLIC_HEADER}" PARENT_SCOPE)
'''
    (generated / "CMakeLists.txt").write_text(cmake, encoding="utf-8")
    for item in generated.iterdir():
        if item.is_file():
            shutil.copy2(item, target / item.name)

    kconfig = SLE / "Kconfig"
    edit_once(kconfig, "endchoice", '''config SAMPLE_SUPPORT_SHOUYI_RELAY
    bool "Shouyi SLE single-hop application relay"
    select SUPPORT_SLE_CENTRAL
    select SUPPORT_SLE_PERIPHERAL

endchoice

config SHOUYI_RELAY_GATEWAY
    bool "Gateway only connects to Shouyi relay"
    depends on SAMPLE_SUPPORT_SLE_UART_CLIENT_SAMPLE''')
    edit_once(kconfig,
        "if SAMPLE_SUPPORT_SLE_UART_SERVER_SAMPLE || SAMPLE_SUPPORT_SLE_UART_CLIENT_SAMPLE\n",
        "if SAMPLE_SUPPORT_SLE_UART_SERVER_SAMPLE || SAMPLE_SUPPORT_SLE_UART_CLIENT_SAMPLE || SAMPLE_SUPPORT_SHOUYI_RELAY\n")
    edit_once(SLE / "CMakeLists.txt", 'set(SOURCES "${SOURCES}" PARENT_SCOPE)',
        'if(DEFINED CONFIG_SAMPLE_SUPPORT_SHOUYI_RELAY)\n'
        '    add_subdirectory_if_exist(shouyi_relay)\nendif()\n\n'
        'set(SOURCES "${SOURCES}" PARENT_SCOPE)')
    edit_once(client_dir / "sle_uart_client.c",
        '#ifndef SLE_UART_SERVER_NAME\n#define SLE_UART_SERVER_NAME "uart_server"\n#endif',
        '#if defined(CONFIG_SHOUYI_RELAY_GATEWAY)\n#define SLE_UART_SERVER_NAME "sy_relay"\n'
        '#elif !defined(SLE_UART_SERVER_NAME)\n#define SLE_UART_SERVER_NAME "uart_server"\n#endif')

def select(variant):
    text = BASE.read_text(encoding="utf-8")
    if variant == "relay":
        text = replace_once(text, 'CONFIG_SAMPLE_SUPPORT_SLE_UART_CLIENT_SAMPLE=y',
                            '# CONFIG_SAMPLE_SUPPORT_SLE_UART_CLIENT_SAMPLE is not set')
        text += '\nCONFIG_SAMPLE_SUPPORT_SHOUYI_RELAY=y\nCONFIG_SUPPORT_SLE_CENTRAL=y\nCONFIG_SUPPORT_SLE_PERIPHERAL=y\n'
    elif variant == "gateway-relay":
        text += '\nCONFIG_SHOUYI_RELAY_GATEWAY=y\n'
    elif variant != "direct":
        raise ValueError(variant)
    CONFIG.write_text(text, encoding="utf-8", newline="\n")
    print("Selected variant:", variant)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("variant", choices=["relay", "gateway-relay", "direct"])
    args = parser.parse_args()
    install()
    select(args.variant)
