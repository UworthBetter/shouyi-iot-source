/*
 * Copyright (c) 2024 iSoftStone Education Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "smart_home.h"
#include "nearlink_bridge.h"

#include <stdio.h>
#include <stdbool.h>

#include "iot_errno.h"

#include "iot_pwm.h"
#include "iot_gpio.h"
#include "lz_hardware.h"
#include "su_03t.h"
#include "iot.h"
#include "lcd.h"
#include "picture.h"
#include "adc_key.h"
#include "components.h"
#include "lcd.h"
#include "string.h"

static bool auto_state = false;
static bool network_state = false;

/* ===== 守颐：本地声光报警与 SOS ===== */
#define BEEP_PORT EPWMDEV_PWM5_M0
#define GPIO_ALARM_LIGHT GPIO0_PA5
#define GPIO_BODY_INDUCTION GPIO0_PA3
#define GPIO_433_D0 GPIO0_PB0      /* 433 解码板 D0（点动：按下=高，松开=低） */
#define GPIO_DOOR_REED GPIO0_PB7   /* 门磁干簧管 NO 端（COM 接 GND：门关=闭合=低） */

bool g_alarm_active = false;   /* 阈值引擎置位，App 确认/处置后清零 */
bool g_sos = false;            /* 上键求助置位，App 确认/处置后清零 */

void alarm_dev_init(void)
{
    IoTGpioInit(GPIO_ALARM_LIGHT);
    IoTGpioSetDir(GPIO_ALARM_LIGHT, IOT_GPIO_DIR_OUT);
    IoTGpioInit(GPIO_BODY_INDUCTION);
    IoTGpioSetDir(GPIO_BODY_INDUCTION, IOT_GPIO_DIR_IN);
    IoTPwmInit(BEEP_PORT);
}

bool body_induction_get_state(void)
{
    IotGpioValue value = IOT_GPIO_VALUE0;
    IoTGpioGetInputVal(GPIO_BODY_INDUCTION, &value);
    return value != IOT_GPIO_VALUE0;
}

void alarm_tick(void)
{
    static bool last = false;
    bool on = (g_alarm_active || g_sos);
    if (on == last) {
        return;
    }
    if (on) {
        IoTPwmStart(BEEP_PORT, 20, 1000);
        IoTGpioSetOutputVal(GPIO_ALARM_LIGHT, IOT_GPIO_VALUE1);
    } else {
        IoTPwmStop(BEEP_PORT);
        IoTGpioSetOutputVal(GPIO_ALARM_LIGHT, IOT_GPIO_VALUE0);
    }
    last = on;
}
/* ===== 守颐 433 patch：433 遥控 SOS + 门磁干簧管 ===== */
bool door_reed_get_state(void)
{
    IotGpioValue value = IOT_GPIO_VALUE0;
    IoTGpioGetInputVal(GPIO_DOOR_REED, &value);
    return value == IOT_GPIO_VALUE0 ? false : true;   /* true=门开（断开被上拉为高） */
}

static void remote433_dev_init(void)
{
    IoTGpioInit(GPIO_433_D0);
    IoTGpioSetDir(GPIO_433_D0, IOT_GPIO_DIR_IN);
    IoTGpioInit(GPIO_DOOR_REED);
    IoTGpioSetDir(GPIO_DOOR_REED, IOT_GPIO_DIR_IN);
    /* B7 内部上拉必须在 IoTGpioInit 之后设置，否则会被冲掉 */
    PinctrlSet(GPIO_DOOR_REED, MUX_FUNC0, PULL_UP, DRIVE_LEVEL0);
}

void *remote433_scan_thread(void *arg)
{
    (void)arg;
    remote433_dev_init();
    printf("[sy 433] scan thread start (B0=433 D0, B7=door reed)\n");
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
            if (!last_433 && low_run >= 2) {
                /* 连续 200ms 稳定低电平之后的上升沿才算遥控按键（去抖） */
                g_sos = true;
                alarm_tick();   /* 立即开蜂鸣+红灯，不等主循环 */
                printf("[sy 433] remote pressed -> SOS\n");
            }
            low_run = 0;
            if (now433 != last_433) {
                printf("[sy 433] D0=1\n");
            }
        } else {
            if (low_run < 1000) {
                low_run++;
            }
            if (now433 != last_433) {
                printf("[sy 433] D0=0\n");
            }
        }
        if (nowDoor != last_door) {
            printf("[sy door] %s\n", nowDoor ? "OPEN" : "CLOSED");
            last_door = nowDoor;
        }
        idle++;
        if (idle >= 20) {   /* 约 6 秒心跳 */
            printf("[sy 433] B0=%d door=%d\n", now433 ? 1 : 0, nowDoor ? 1 : 0);
            idle = 0;
        }
        last_433 = now433;
        LOS_Msleep(100);   /* 100ms 轮询，降低按键响应延迟 */
    }
    return NULL;
}

/* ===== 守颐 433 patch end ===== */

void light_menu_entry(lcd_menu_t *menu);
void fan_menu_entry(lcd_menu_t *menu);

/* 风扇菜单的数据初始化*/
lcd_menu_t fan_menu={
    .img={
        .img=img_fan_off,
        .height=64,
        .width=64,
    },
    .is_selected=false,
    .text={
        .fc=LCD_MAGENTA,
        .bc=LCD_WHITE,
        .font_size=24,
        .name="风扇关",
    },
    .enterFunc=fan_menu_entry,
    .exitFunc=NULL,
    .base_x=100,
    .base_y=64,
 
};

/* 照明灯的菜单初始化数据*/
lcd_menu_t light_menu={
    .img={
        .img= img_light_off,
        .height=64,
        .width=64,
    },
    .is_selected=false,
    .text={
        .fc=LCD_MAGENTA,
        .bc=LCD_WHITE,
        .font_size=24,
        .name="灯光关",
    },
    .base_x=20,
    .base_y=64,
    .enterFunc=light_menu_entry,
    .exitFunc=NULL,
};

/* 温度面板的初始化数据*/
lcd_display_board_t temp_db={
    .img={
        .img= img_temp_normal,
        .height=48,
        .width=48,
    },
    .text={
        .fc=LCD_MAGENTA,
        .bc=LCD_WHITE,
        .font_size=24,
        .name="25.5°C",
    },
    .base_x=180,
    .base_y=64,
};

/* 湿度面板的初始化数据*/
lcd_display_board_t humi_db={
    .img={
        .img= img_humi,
        .height=48,
        .width=48,
    },
    .text={
        .fc=LCD_MAGENTA,
        .bc=LCD_WHITE,
        .font_size=24,
        .name="25.5°C",
    },
    .base_x=180,
    .base_y=120,
};

/* 亮度面板的初始化数据*/
lcd_display_board_t lum_db={
    .img={
        .img= img_lum,
        .height=48,
        .width=48,
    },
    .text={
        .fc=LCD_MAGENTA,
        .bc=LCD_WHITE,
        .font_size=24,
        .name="1234Lx",
    },
    .base_x=180,
    .base_y=174,
};
/* 所有的面板集合数组,方便遍历查询*/
lcd_display_board_t *lcd_dbs[] ={&temp_db,&humi_db,&lum_db};
/* 所有的菜单集合数组,方便遍历查询*/
lcd_menu_t *lcd_menus[] = {&light_menu,&fan_menu};
/* 菜单的个数*/
static int lcd_menu_number =  sizeof(lcd_menus)/sizeof(lcd_menu_t *);
/* 菜单的当前选中索引,在数组中的位置*/
static int menu_select_index = 0;

//菜单左和右的处理,需要考虑菜单个数的边界
void lcd_menu_selected_move_left()
{
    if(menu_select_index > 0){
        menu_select_index--;
    }
}

void lcd_menu_selected_move_right()
{
    if(menu_select_index <lcd_menu_number-1){
        menu_select_index++;
    }
}

/**
 * @brief 照明灯菜单按下确认按键
 * 
 * @param menu 
 */
void light_menu_entry(lcd_menu_t *menu)
{
    int light_state = get_light_state();
    if(light_state)
    {
        light_set_state(false);
        lcd_set_light_state(false);
    }else{
        light_set_state(true);
        lcd_set_light_state(true);
    }
}
/**
 * @brief  风扇菜单按下确认按键
 * 
 * @param menu 
 */
void fan_menu_entry(lcd_menu_t *menu)
{
   int motor_state = get_motor_state();
   if(motor_state)
   {
       motor_set_state(false);
       lcd_set_motor_state(false);
   }else{
       motor_set_state(true);
       lcd_set_motor_state(true);
   }
}


/***************************************************************
* 函数名称: lcd_dev_init
* 说    明: lcd初始化
* 参    数: 无
* 返 回 值: 无
***************************************************************/
void lcd_dev_init(void)
{
    lcd_init();
    lcd_fill(0, 0, LCD_W, LCD_H, LCD_WHITE);
}

/**
 * @brief 按键处理函数
 * 
 * @param key_no 按键号
 */
void smart_home_key_process(int key_no)
{
    printf("smart_home_key_process:%d\n",key_no);
    /* 报警状态下，任意按键 = 本地消音（App 侧确认/处置依然有效） */
    if (g_alarm_active || g_sos) {
        g_sos = false;
        g_alarm_active = false;
        return;
    }
    if(key_no == KEY_UP){
        /* 紧急求助：上键触发，声光报警直到 App 处置 */
        g_sos = true;
    }else if(key_no == KEY_DOWN){
        lcd_menu_entry(lcd_menus[menu_select_index]);

    }else if(key_no == KEY_LEFT){
        
        lcd_menu_selected_move_left();
    }else if(key_no == KEY_RIGHT){
        lcd_menu_selected_move_right();
    }
}
/**
 * @brief 物联网的指令处理函数
 * 
 * @param iot_cmd iot的指令
 */
void smart_home_iot_cmd_process(int iot_cmd)
{
    switch (iot_cmd)
    {
        case IOT_CMD_LIGHT_ON:
            light_set_state(true);
            lcd_set_light_state(true);
            break;
        case IOT_CMD_LIGHT_OFF:
            light_set_state(false);
            lcd_set_light_state(false);
            break;
        case IOT_CMD_MOTOR_ON:
            motor_set_state(true);
            lcd_set_motor_state(true);
            break;
        case IOT_CMD_MOTOR_OFF:
            motor_set_state(false);
            lcd_set_motor_state(false);
            break;
        case IOT_CMD_ALARM_MUTE:
            g_sos = false;
            g_alarm_active = false;
            break;
    }
}

/**
 * @brief 语音管家发出的指令
 * 
 * @param su03t_cmd 语音管家的指令
 */
void smart_home_su03t_cmd_process(int su03t_cmd)
{
    switch (su03t_cmd)
    {
        case light_state_on:
            light_set_state(true);
            lcd_set_light_state(true);
            break;
        case light_state_off:
            light_set_state(false);
            lcd_set_light_state(false);
            break;
        case motor_state_on:
            motor_set_state(true);
            lcd_set_motor_state(true);
            break;
        case motor_state_off:
            motor_set_state(false);
            lcd_set_motor_state(false);
            break;
        case temperature_get:
        {
            double temp,humi;

            sht30_read_data(&temp, &humi);
            su03t_send_double_msg(1, temp);
        }
            
            break;
        case humidity_get:
        {
            double temp,humi;
            sht30_read_data(&temp, &humi);

            su03t_send_double_msg(2, humi);
        }
            break;
        case illumination_get:
        {
            double lum;
            bh1750_read_data(&lum);
            su03t_send_double_msg(3, lum);
        }
            
            break;
        default:
            break;
    }
}


/***************************************************************
* 函数名称: lcd_load_ui
* 说    明: 加载lcd ui
* 参    数: 无
* 返 回 值: 无
***************************************************************/
void lcd_show_ui(void)
{
    /* Dedicated free row below the header; full-width padding clears old text. */
    char nl_raw[41];
    char nl_line[41];
    nearlink_bridge_status(nl_raw, sizeof(nl_raw));
    snprintf(nl_line, sizeof(nl_line), "%-40.40s", nl_raw);
    lcd_show_string(0, 38, (const uint8_t *)nl_line,
                    nearlink_bridge_online() ? LCD_GREEN : LCD_RED,
                    LCD_WHITE, 16, 0);

    /* 标题横幅：报警时红底白字"报警"，正常时白底红字"智慧家居" */
    if (g_alarm_active || g_sos) {
        lcd_fill(0, 0, LCD_W, 35, LCD_RED);
        lcd_show_chinese(136, 2, "报警", LCD_WHITE, LCD_RED, 24, 0);
    } else {
        lcd_fill(0, 0, LCD_W, 35, LCD_WHITE);
        lcd_show_chinese(96, 0, "智慧家居", LCD_RED, LCD_WHITE, 32, 0);
    }
    lcd_show_picture(280,0, 32,32, network_state? img_wifi_on : img_wifi_off);

    lcd_menu_update(lcd_menus ,lcd_menu_number,menu_select_index);

    lcd_menu_show(lcd_menus ,  lcd_menu_number);
    lcd_db_show(lcd_dbs, sizeof(lcd_dbs)/sizeof(lcd_display_board_t *));

    lcd_show_picture(0,176,177,58, img_logo);
}

/***************************************************************
* 函数名称: lcd_set_temperature
* 说    明: 设置温度显示
* 参    数: double temperature 温度
* 返 回 值: 无
***************************************************************/
void lcd_set_temperature(double temperature)
{
    sprintf(temp_db.text.name, "%.01f℃ ", temperature);
    /* 对温度做高温和正常的区分*/
    if(temperature > 35)
    {
        temp_db.text.fc = LCD_RED;
        temp_db.img.img = img_temp_high;
    }
    else
    {
       temp_db.text.fc = LCD_MAGENTA;
       temp_db.img.img = img_temp_normal;
    }
}

/***************************************************************
* 函数名称: lcd_set_humidity
* 说    明: 设置湿度显示
* 参    数: double humidity 湿度
* 返 回 值: 无
***************************************************************/
void lcd_set_humidity(double humidity)
{
    sprintf(humi_db.text.name, "%.01f%% ", humidity);

}

/***************************************************************
* 函数名称: lcd_set_illumination
* 说    明: 设置光照强度显示
* 参    数: double illumination 光照强度
* 返 回 值: 无
***************************************************************/
void lcd_set_illumination(double illumination)
{
    sprintf(lum_db.text.name, "%.01fLx ", illumination);

}

void lcd_set_network_state(int state){
    network_state = state;
}

/***************************************************************
* 函数名称: lcd_set_light_state
* 说    明: 设置灯状态显示
* 参    数: bool state true：显示"打开" false：显示"关闭"
* 返 回 值: 无
***************************************************************/
void lcd_set_light_state(bool state)
{
    
    strcpy(light_menu.text.name,state? "灯光开" :"灯光关");
    light_menu.img.img = state? img_light_on : img_light_off;
}

/***************************************************************
* 函数名称: lcd_set_motor_state
* 说    明: 设置电机状态显示
* 参    数: bool state true：显示"打开" false：显示"关闭"
* 返 回 值: 无
***************************************************************/
void lcd_set_motor_state(bool state)
{

    strcpy(fan_menu.text.name,state? "风扇开" :"风扇关");
    fan_menu.img.img = state? img_fan_on : img_fan_off;

}

/***************************************************************
* 函数名称: lcd_set_auto_state
* 说    明: 设置自动模式状态显示
* 参    数: bool state true：显示"打开" false：显示"关闭"
* 返 回 值: 无
***************************************************************/
void lcd_set_auto_state(bool state)
{



    // if (state)
    // {
    //     lcd_show_chinese(77, 204, "开启", LCD_RED, LCD_WHITE, 24, 0);
    // }
    // else
    // {
    //     lcd_show_chinese(77, 204, "关闭", LCD_RED, LCD_WHITE, 24, 0);
    // }
}
