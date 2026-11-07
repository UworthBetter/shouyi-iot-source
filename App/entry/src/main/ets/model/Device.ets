/**
 * 设备（开发板主机）
 */
import { HeartRateConst, SensorStatus, SensorRisk, VitalsConst } from '../common/constants/AppConstants';

export class Device {
  /** 设备唯一 ID，由云端下发 */
  deviceId: string = '';
  /** 设备序列号 */
  deviceSn: string = '';
  /** 设备名称，如"客厅监护主机" */
  deviceName: string = '';
  /** 型号 */
  model: string = '';
  /** 固件版本 */
  firmwareVersion: string = '';
  /** 是否在线 */
  online: boolean = false;
  /** 最后心跳时间戳 */
  lastHeartbeat: number = 0;
  /** 主机电量（0-100），无电池时忽略 */
  battery: number = 0;
  /** 信号强度 0-5 */
  signal: number = 0;
  /** 网络类型：wifi / cellular / starflash */
  networkType: string = 'wifi';
  /** 当前未处置告警数 */
  activeAlerts: number = 0;
  /** 支持的能力清单 */
  capabilities: string[] = [];
  /**
   * 实时心率（次/分钟）。<= 0 表示当前没有可用读数
   * （设备未接入雷达/PPG、信号断开、或刚上电还没采集到）。
   */
  heartRate: number = 0;
  /** 心率最近一次成功采集的时间戳，0 表示从未采集 */
  heartRateAt: number = 0;

  /**
   * 以下三项由监护主机上的雷达 / PPG 模组采集，与心率同源、同批上报。
   * 它们不是挂在开发板上的独立传感器，所以不占用 GPIO / I2C / ADC 通道。
   */
  /** 血氧饱和度（%）。<= 0 表示当前没有可用读数 */
  spo2: number = 0;
  /** 体表温度（℃）。<= 0 表示当前没有可用读数 */
  bodyTemp: number = 0;
  /** 今日步数。<= 0 表示当前没有可用读数 */
  steps: number = 0;
  /** 生命体征最近一次采集的时间戳（心率/血氧/体温/步数共用），0 表示从未采集 */
  vitalsAt: number = 0;

  /** 是否低电量 */
  isLowBattery(): boolean {
    return this.battery > 0 && this.battery < 15;
  }

  /** 心跳是否超时（默认 10 分钟判定离线） */
  isHeartbeatTimeout(timeoutMs: number = 600000): boolean {
    return this.lastHeartbeat > 0 && (Date.now() - this.lastHeartbeat) > timeoutMs;
  }

  /**
   * 当前是否存在可用的心率读数。
   *
   * 四个条件缺一不可：设备在线、读数为正、有采集时间、且未超出新鲜度窗口。
   * 任一不满足都返回 false —— 界面据此展示 "-- 次/分钟"。
   * 特别注意设备离线的情况：缓存里可能还留着断连前的读数，
   * 把它当成本次结果展示才是真正危险的做法，所以这里直接判为无读数。
   */
  hasHeartRate(): boolean {
    if (!this.online) {
      return false;
    }
    if (this.heartRate <= 0 || this.heartRateAt <= 0) {
      return false;
    }
    return (Date.now() - this.heartRateAt) <= HeartRateConst.STALE_MS;
  }

  /** 心率是否落在静息正常区间 */
  isHeartRateNormal(): boolean {
    return HeartRateConst.isNormal(this.heartRate);
  }

  /**
   * 生命体征（血氧/体温/步数）是否有可用读数。
   * 判定口径与心率完全一致：设备在线 + 有采集时间 + 未超出新鲜度窗口。
   * 三项共用 vitalsAt，避免出现"心率是新的、血氧是三天前的"这种错配。
   */
  hasVitals(): boolean {
    if (!this.online) {
      return false;
    }
    if (this.vitalsAt <= 0) {
      return false;
    }
    return (Date.now() - this.vitalsAt) <= HeartRateConst.STALE_MS;
  }

  /** 血氧是否正常 */
  isSpo2Normal(): boolean {
    return this.spo2 >= VitalsConst.SPO2_MIN;
  }

  /** 体表温度是否正常 */
  isBodyTempNormal(): boolean {
    return this.bodyTemp >= VitalsConst.TEMP_MIN && this.bodyTemp <= VitalsConst.TEMP_MAX;
  }
}

/**
 * 传感器节点及其当前状态。
 * 一个设备下挂多个传感器，各自有独立的在线状态与当前值。
 */
export class Sensor {
  /** 传感器唯一 ID */
  sensorId: string = '';
  /** 所属设备 */
  deviceId: string = '';
  /** 传感器类型，见 SensorType */
  sensorType: string = '';
  /** 显示名称 */
  name: string = '';
  /** 当前值：数字量为 0/1，模拟量为实际数值 */
  value: number = 0;
  /** 供界面直接展示的文案，如"最后活动：3 分钟前" */
  displayValue: string = '';
  /** 最后一次触发时间（事件型传感器） */
  lastTriggered: number = 0;
  /** 最后一次状态变化时间 */
  lastChanged: number = 0;
  /** 今日触发次数 */
  todayCount: number = 0;
  /** 当前是否正常 */
  normal: boolean = true;
  /** 传感器自身是否在线（无线传感器需单独判断） */
  online: boolean = true;
  /** 传感器电量（无线传感器） */
  battery: number = 0;
  /** 最后更新时间 */
  updatedAt: number = 0;
  /**
   * 显式状态等级（normal / warning / danger），由数据层下发。
   * 留空时由 status() 按 online + normal + 风险分级自动推导。
   */
  level: string = '';

  /**
   * 卡片状态 —— 全应用唯一的状态出口。
   *
   * 优先级：离线 > 显式等级 > 风险分级推导。
   * 离线必须最先判：断连时缓存里的值已经不可信，
   * 再拿它去算"正常/异常"没有意义。
   */
  status(): string {
    if (!this.online) {
      return SensorStatus.OFFLINE;
    }
    if (this.level.length > 0) {
      return this.level;
    }
    if (this.normal) {
      return SensorStatus.NORMAL;
    }
    // 高危类（烟雾/燃气/SOS）异常直接进红，普通监测类先给黄
    return SensorRisk.abnormalStatus(this.sensorType);
  }

  /** 状态中文名，用于详情页与无障碍描述 */
  statusLabel(): string {
    return SensorStatus.labelOf(this.status());
  }

  /** 是否处于需要提醒的状态（黄或红） */
  isAbnormal(): boolean {
    const s: string = this.status();
    return s === SensorStatus.WARNING || s === SensorStatus.DANGER;
  }

  /**
   * 卡片第二行文案：统一为「标签：数值」。
   * 离线时给明确的【设备离线】，不留空白 —— 空白会被读成"页面没做"。
   */
  infoText(): string {
    if (!this.online) {
      return '【设备离线】';
    }
    return this.displayValue.length > 0 ? this.displayValue : '--';
  }
}

/**
 * 传感器读数（时序数据）。
 * 本地只缓存最近若干条，完整历史由云端提供。
 */
export class SensorReading {
  id: string = '';
  deviceId: string = '';
  sensorType: string = '';
  /** 采集时间戳 */
  timestamp: number = 0;
  /** 主值 */
  value: number = 0;
  /** 附加信息，JSON 字符串。如温湿度的 humidity、PIR 的 duration */
  extra: string = '';
}

/** 温湿度附加信息 */
export interface TempHumidityExtra {
  humidity: number;
}

/** 门窗附加信息 */
export interface DoorExtra {
  position: string;
}

/** 人体活动附加信息 */
export interface PirExtra {
  duration: number;
}

/** 设备配置（云端下发） */
export class DeviceConfig {
  configVersion: number = 0;
  heartbeatInterval: number = 60;
  readingsReportInterval: number = 300;
  /** 白天"长时间无活动"阈值（分钟） */
  noActivityMinutesDay: number = 120;
  /** 夜间"长时间无活动"阈值（分钟） */
  noActivityMinutesNight: number = 60;
  tempMin: number = 10;
  tempMax: number = 32;
  humidityMin: number = 30;
  humidityMax: number = 70;
  smokeThreshold: number = 300;
  gasThreshold: number = 300;
  /** 免打扰时段 */
  quietStart: string = '22:00';
  quietEnd: string = '06:00';
  /** 语音播报文案 */
  sosVoiceText: string = '我需要帮助';
  gasVoiceText: string = '检测到燃气泄漏，请立即开窗通风并离开';
  /**
   * 老人联系电话。
   * 供预警列表的「联系老人」快捷操作拨号使用。
   * 放在设备配置里而不是写死在代码中：号码属于用户数据，
   * 后续在「我的 → 设置」里维护。
   */
  elderPhone: string = '';
}
