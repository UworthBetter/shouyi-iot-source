#ifndef _IOT_H_
#define _IOT_H_

#include <stdbool.h>

typedef struct
{
    double illumination;
    double temperature;
    double humidity;
    bool motor_state;
    bool light_state;
    bool auto_state;
    /* 守颐 monitor 模型扩展字段 */
    bool pir;
    bool pir_rk2206;
    int pir_h2821;
    int  door;
    unsigned int smoke;
    unsigned int gas;
    bool sos;
    int  battery;
    bool alarm_active;
    int  rssi;
} e_iot_data;

#define IOT_CMD_LIGHT_ON 0x01
#define IOT_CMD_LIGHT_OFF 0x02
#define IOT_CMD_MOTOR_ON 0x03
#define IOT_CMD_MOTOR_OFF 0x04
#define IOT_CMD_AUTO_ON 0x05
#define IOT_CMD_AUTO_OFF 0x06
#define IOT_CMD_ALARM_MUTE 0x07

int wait_message();
void mqtt_init();
unsigned int mqtt_is_connected();
void send_msg_to_mqtt(e_iot_data *iot_data);

#endif // _IOT_H_