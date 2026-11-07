#include "nearlink_bridge.h"
#include "nearlink_protocol.h"
#include "iot_uart.h"
#include "iot_gpio.h"
#include "iot_errno.h"
#include "lz_hardware.h"
#include "los_task.h"
#include "los_tick.h"
#include <stdio.h>

/* UART0 RX=PB6. 433 D0 moves to PB0; PB7 remains a door GPIO.
 * RX only: never transmit on UART0 and never connect a second TX here. */
static volatile bool s_motion;
static volatile int s_pir_state = -2;
static volatile bool s_online;
static volatile bool s_started;
static volatile bool s_failed;
static volatile bool s_ready;
static volatile uint32_t s_rx_bytes;
static volatile uint32_t s_frames;

bool nearlink_bridge_motion(void) { return s_motion; }
bool nearlink_bridge_online(void) { return s_online; }
int nearlink_bridge_pir_state(void) { return s_pir_state; }

void nearlink_bridge_status(char *text, size_t size)
{
    const char *status = s_failed ? "ERR" : !s_started ? "INIT" :
                         !s_online ? "OFF" : !s_ready ? "WARM" : "ON";
    snprintf(text, size, "SLE:%s P:%u RX:%lu OK:%lu", status,
             (unsigned)s_motion, (unsigned long)s_rx_bytes, (unsigned long)s_frames);
}

static uint32_t now_ms(void)
{
    return (uint32_t)(LOS_TickCountGet() * 1000 / LOSCFG_BASE_CORE_TICK_PER_SECOND);
}

static void bridge_task(void *arg)
{
    (void)arg;
    IotUartAttribute attr = {0};
    attr.baudRate = 115200;
    attr.dataBits = IOT_UART_DATA_BIT_8;
    attr.parity = IOT_UART_PARITY_NONE;
    attr.stopBits = IOT_UART_STOP_BIT_1;
    attr.rxBlock = IOT_UART_BLOCK_STATE_NONE_BLOCK;
    attr.txBlock = IOT_UART_BLOCK_STATE_NONE_BLOCK;
    attr.pad = IOT_FLOW_CTRL_NONE;
    unsigned int rc = IoTUartInit(EUART0_M0, &attr);
    /* The HAL configures both pins. Restore unused TX=PB7 to door input,
     * including after an init failure, so the door's pull-up is preserved. */
    IoTGpioInit(GPIO0_PB7);
    IoTGpioSetDir(GPIO0_PB7, IOT_GPIO_DIR_IN);
    PinctrlSet(GPIO0_PB7, MUX_FUNC0, PULL_UP, DRIVE_LEVEL0);
    if (rc != IOT_SUCCESS) {
        s_failed = true;
        printf("[sy nearlink] UART0 init failed rc=%u\n", rc);
        return;
    }
    s_started = true;
    printf("[sy nearlink] UART0 RX=PB6 115200, 433 D0=PB0, TX disabled\n");
    nl_state state = {0};
    uint32_t printed = 0;
    while (1) {
        uint8_t bytes[64];
        int length = IoTUartRead(EUART0_M0, bytes, sizeof(bytes));
        uint32_t now = now_ms();
        if (length > 0 && length <= (int)sizeof(bytes)) {
            s_rx_bytes += (uint32_t)length;
            nl_feed(&state, bytes, (size_t)length, now);
        }
        bool online = nl_online(&state, now);
        bool motion = nl_motion(&state, now);
        if (online != s_online || state.accepted != printed) {
            printf("[sy nearlink] online=%d ready=%d pir=%d seq=%u good=%u bad=%u\n",
                   online, state.ready, motion, state.seq, state.accepted, state.rejected);
            printed = state.accepted;
        }
        s_online = online;
        s_motion = motion;
        s_ready = state.ready;
        s_pir_state = !online ? -2 : !state.ready ? -1 : motion ? 1 : 0;
        s_frames = state.accepted;
        LOS_Msleep(20);
    }
}

void nearlink_bridge_init(void)
{
    unsigned int id;
    TSK_INIT_PARAM_S task = {0};
    task.pfnTaskEntry = (TSK_ENTRY_FUNC)bridge_task;
    task.uwStackSize = 4096;
    task.usTaskPrio = 24;
    task.pcName = "nearlink rx";
    unsigned int rc = LOS_TaskCreate(&id, &task);
    if (rc != LOS_OK) {
        s_failed = true;
        printf("[sy nearlink] task creation failed rc=%u\n", rc);
    }
}
