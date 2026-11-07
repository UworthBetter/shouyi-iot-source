#!/usr/bin/env python3
"""守颐：RK2206 接入 433 遥控 SOS（GPIO0_B6）+ 门磁干簧管（GPIO0_B7）。

改动（幂等，带标记防重入）：
  smart_home.c
    - 新增引脚定义（B6=433 D0、B7=门磁）、door_reed_get_state()、remote433_scan_thread()
    - B7 用 PinctrlSet 配内部上拉：门磁 COM 接 GND，闭合=低=门关，
      门开=断开=上拉高，全程无需外接电阻
    - 433 去抖：连续 3 次采样（900ms）稳定低电平后的上升沿才置 g_sos
    - 电平变化即时打印 + 约 6 秒心跳打印，用于接线验证
  smart_home.h
    - 导出 door_reed_get_state / remote433_scan_thread
  iot_smart_home_example.c
    - iot_data.door 从写死 0 改为门磁实读（1=门开，与 App 语义一致）
    - 新建第 4 个任务跑 433/门磁扫描
"""

import sys

MARK = "/* ===== 守颐 433 patch"
SMART_HOME_C = "/root/txsmart/vendor/isoftstone/rk2206/samples/e1_iot_smart_home_hwiot/src/smart_home.c"
SMART_HOME_H = "/root/txsmart/vendor/isoftstone/rk2206/samples/e1_iot_smart_home_hwiot/include/smart_home.h"
EXAMPLE_C = "/root/txsmart/vendor/isoftstone/rk2206/samples/e1_iot_smart_home_hwiot/iot_smart_home_example.c"

# 引脚定义（插到 GPIO_BODY_INDUCTION 之后）
PIN_DEFINES = """#define GPIO_433_D0 GPIO0_PB6      /* 433 解码板 D0（点动：按下=高，松开=低） */
#define GPIO_DOOR_REED GPIO0_PB7   /* 门磁干簧管 NO 端（COM 接 GND：门关=闭合=低） */"""

# 函数块（插到 alarm_tick 结束之后）
NEW_BLOCK_SMART_HOME_C = MARK + '''：433 遥控 SOS + 门磁干簧管 ===== */
bool door_reed_get_state(void)
{
    IotGpioValue value = IOT_GPIO_VALUE0;
    IoTGpioGetInputVal(GPIO_DOOR_REED, &value);
    return value == IOT_GPIO_VALUE0 ? false : true;   /* true=门开（断开被上拉为高） */
}

static void remote433_dev_init(void)
{
    /* B7 内部上拉：门开时触点断开，引脚靠上拉保持高电平，无需外接电阻 */
    PinctrlSet(GPIO_DOOR_REED, MUX_FUNC0, PULL_UP, DRIVE_LEVEL0);
    IoTGpioInit(GPIO_433_D0);
    IoTGpioSetDir(GPIO_433_D0, IOT_GPIO_DIR_IN);
    IoTGpioInit(GPIO_DOOR_REED);
    IoTGpioSetDir(GPIO_DOOR_REED, IOT_GPIO_DIR_IN);
}

void *remote433_scan_thread(void *arg)
{
    (void)arg;
    remote433_dev_init();
    printf("[sy 433] scan thread start (B6=433 D0, B7=door reed)\\n");
    IotGpioValue d0 = IOT_GPIO_VALUE0;
    bool last_433 = false;
    bool last_door = false;
    int low_run = 0;
    int idle = 0;
    while (1) {
        IoTGpioGetInputVal(GPIO_433_D0, &d0);
        bool now433 = (d0 != IOT_GPIO_VALUE0);
        bool nowDoor = door_reed_get_state();

        if (now433) {
            if (!last_433 && low_run >= 3) {
                /* 连续 900ms 稳定低电平之后的上升沿才算遥控按键（去抖） */
                g_sos = true;
                printf("[sy 433] remote pressed -> SOS\\n");
            }
            low_run = 0;
            if (now433 != last_433) {
                printf("[sy 433] D0=1\\n");
            }
        } else {
            if (low_run < 1000) {
                low_run++;
            }
            if (now433 != last_433) {
                printf("[sy 433] D0=0\\n");
            }
        }
        if (nowDoor != last_door) {
            printf("[sy door] %s\\n", nowDoor ? "OPEN" : "CLOSED");
            last_door = nowDoor;
        }
        idle++;
        if (idle >= 20) {   /* 约 6 秒心跳 */
            printf("[sy 433] B6=%d door=%d\\n", now433 ? 1 : 0, nowDoor ? 1 : 0);
            idle = 0;
        }
        last_433 = now433;
        LOS_Msleep(300);
    }
    return NULL;
}

/* ===== 守颐 433 patch end ===== */'''

ANCHOR_ALARM_TICK_END = """        IoTGpioSetOutputVal(GPIO_ALARM_LIGHT, IOT_GPIO_VALUE0);
    }
    last = on;
}
"""
ANCHOR_DEFINE_PIR = "#define GPIO_BODY_INDUCTION GPIO0_PA3"
ANCHOR_H_SOS = "extern bool g_sos;"
NEW_H_LINES = """extern bool g_sos;
bool door_reed_get_state(void);
void *remote433_scan_thread(void *arg);"""
ANCHOR_INCLUDE_GPIO = '#include "iot_gpio.h"'
ANCHOR_DOOR_ZERO = "            iot_data.door = 0;  /* 门磁未接线，恒为关 */"
NEW_DOOR_LINE = "            iot_data.door = door_reed_get_state() ? 1 : 0;  /* 门磁干簧管：1=门开 */"
ANCHOR_TASK3_DECL = "    TSK_INIT_PARAM_S task_3 = {0};"
NEW_TASK4_DECL = """    TSK_INIT_PARAM_S task_3 = {0};
    TSK_INIT_PARAM_S task_4 = {0};"""
ANCHOR_THREAD3_DECL = "    unsigned int thread_id_3;"
NEW_THREAD4_DECL = """    unsigned int thread_id_3;
    unsigned int thread_id_4;"""
ANCHOR_TASK3_CREATE = """    ret = LOS_TaskCreate(&thread_id_3, &task_3);
    if (ret != LOS_OK)
    {
        printf("Falied to create task ret:0x%x\\n", ret);
        return;
    }
}
"""
NEW_TASK3_CREATE = """    ret = LOS_TaskCreate(&thread_id_3, &task_3);
    if (ret != LOS_OK)
    {
        printf("Falied to create task ret:0x%x\\n", ret);
        return;
    }

    task_4.pfnTaskEntry = (TSK_ENTRY_FUNC)remote433_scan_thread;
    task_4.uwStackSize = 4096;
    task_4.pcName = "remote433 thread";
    task_4.usTaskPrio = 24;
    ret = LOS_TaskCreate(&thread_id_4, &task_4);
    if (ret != LOS_OK)
    {
        printf("Falied to create 433 task ret:0x%x\\n", ret);
    }
}
"""


def read(path: str) -> str:
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def write(path: str, text: str) -> None:
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def main() -> int:
    ok = True

    # ---------- smart_home.c ----------
    src = read(SMART_HOME_C)
    if MARK in src:
        print("smart_home.c: 已打过补丁，跳过")
    else:
        missing = [n for n, a in [("iot_gpio.h include", ANCHOR_INCLUDE_GPIO),
                                  ("引脚定义锚点", ANCHOR_DEFINE_PIR),
                                  ("alarm_tick 结尾", ANCHOR_ALARM_TICK_END)] if a not in src]
        if missing:
            print("smart_home.c: 缺锚点 %s" % missing)
            ok = False
        else:
            src = src.replace(ANCHOR_INCLUDE_GPIO,
                              ANCHOR_INCLUDE_GPIO + '\n#include "lz_hardware.h"', 1)
            src = src.replace(ANCHOR_DEFINE_PIR,
                              ANCHOR_DEFINE_PIR + "\n" + PIN_DEFINES, 1)
            src = src.replace(ANCHOR_ALARM_TICK_END,
                              ANCHOR_ALARM_TICK_END + NEW_BLOCK_SMART_HOME_C + "\n", 1)
            write(SMART_HOME_C, src)
            print("smart_home.c: 补丁完成")

    # ---------- smart_home.h ----------
    hdr = read(SMART_HOME_H)
    if "door_reed_get_state" in hdr:
        print("smart_home.h: 已打过补丁，跳过")
    elif ANCHOR_H_SOS not in hdr:
        print("smart_home.h: 找不到 g_sos 锚点")
        ok = False
    else:
        hdr = hdr.replace(ANCHOR_H_SOS, NEW_H_LINES, 1)
        write(SMART_HOME_H, hdr)
        print("smart_home.h: 补丁完成")

    # ---------- iot_smart_home_example.c ----------
    ex = read(EXAMPLE_C)
    if "door_reed_get_state() ? 1 : 0" in ex:
        print("iot_smart_home_example.c: 已打过补丁，跳过")
    else:
        missing = [n for n, a in [("door 锚点", ANCHOR_DOOR_ZERO),
                                  ("task_3 声明", ANCHOR_TASK3_DECL),
                                  ("thread_id_3 声明", ANCHOR_THREAD3_DECL),
                                  ("task_3 创建", ANCHOR_TASK3_CREATE)] if a not in ex]
        if missing:
            print("iot_smart_home_example.c: 缺锚点 %s" % missing)
            ok = False
        else:
            ex = ex.replace(ANCHOR_DOOR_ZERO, NEW_DOOR_LINE, 1)
            ex = ex.replace(ANCHOR_TASK3_DECL, NEW_TASK4_DECL, 1)
            ex = ex.replace(ANCHOR_THREAD3_DECL, NEW_THREAD4_DECL, 1)
            ex = ex.replace(ANCHOR_TASK3_CREATE, NEW_TASK3_CREATE, 1)
            write(EXAMPLE_C, ex)
            print("iot_smart_home_example.c: 补丁完成")

    print("OK" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
