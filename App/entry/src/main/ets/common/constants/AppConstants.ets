/**
 * 全局常量。
 * 集中管理数据库名、表名、云端配置键等跨模块共享字面量。
 */
export class AppConstants {
  /** 本地缓存数据库 */
  static readonly DB_NAME: string = 'shouyi_cache.db';
  static readonly DB_VERSION: number = 1;

  /** Preferences 文件名 */
  static readonly PREF_NAME: string = 'shouyi_pref';
  /** Preferences 键：登录令牌 */
  static readonly KEY_ACCESS_TOKEN: string = 'access_token';
  /** Preferences 键：家庭 ID */
  static readonly KEY_FAMILY_ID: string = 'family_id';
  /** Preferences 键：当前用户角色 */
  static readonly KEY_USER_ROLE: string = 'user_role';
  /** Preferences 键：最近一次同步时间 */
  static readonly KEY_LAST_SYNC: string = 'last_sync_time';
  /** Preferences 键：是否使用 Mock 云端 */
  static readonly KEY_USE_MOCK: string = 'use_mock_cloud';

  /** 云端接口地址（待学长接口文档到位后填入） */
  static readonly CLOUD_BASE_URL: string = 'https://api.example.com/api/v1';

  /** 轮询间隔（毫秒）。推送通道可用时自动降级为长连接 */
  static readonly POLL_INTERVAL_MS: number = 30000;

  /** 本地缓存保留的历史读数条数上限 */
  static readonly MAX_CACHED_READINGS: number = 500;

  /** 活动报告默认查询天数 */
  static readonly REPORT_DAYS_WEEK: number = 7;
  static readonly REPORT_DAYS_MONTH: number = 30;

  /** 个人活动基线计算窗口（天） */
  static readonly BASELINE_WINDOW_DAYS: number = 14;

  /** 规律变化提示阈值：活动量下降超过该比例时提示 */
  static readonly DECLINE_THRESHOLD_PERCENT: number = 20;

  /** 基线偏离告警阈值（标准差倍数） */
  static readonly BASELINE_DEVIATION_SIGMA: number = 2;
}

/**
 * 心率展示与判定常量。
 *
 * 展示规则集中在这里，避免各页面各写一套：
 *   - 有有效读数 → "76 次/分钟"
 *   - 信号断开 / 暂未采集 → "-- 次/分钟"
 * 后者不留空，是为了让家属能区分"没测到"和"页面没做"，
 * 也避免空白格被误读成"心率正常但没显示"。
 */
export class HeartRateConst {
  /** 静息心率正常区间下限（次/分钟）。老年人静息参考 60–100 */
  static readonly NORMAL_MIN: number = 60;
  /** 静息心率正常区间上限 */
  static readonly NORMAL_MAX: number = 100;
  /** 读数新鲜度窗口（毫秒）。超时未上报即视为"暂未采集到" */
  static readonly STALE_MS: number = 300000;
  /** 无读数时的占位符 */
  static readonly PLACEHOLDER: string = '--';
  /** 单位文案 */
  static readonly UNIT: string = '次/分钟';

  /**
   * 统一生成展示文案。
   * @param bpm 心率读数，<= 0 表示无
   * @param valid 读数是否有效（已采集且未超时）
   */
  static display(bpm: number, valid: boolean): string {
    if (valid && bpm > 0) {
      return `${bpm} ${HeartRateConst.UNIT}`;
    }
    return `${HeartRateConst.PLACEHOLDER} ${HeartRateConst.UNIT}`;
  }

  /** 是否落在静息正常区间 */
  static isNormal(bpm: number): boolean {
    return bpm >= HeartRateConst.NORMAL_MIN && bpm <= HeartRateConst.NORMAL_MAX;
  }
}

/**
 * 生命体征判定阈值（心率之外的三项）。
 *
 * 口径按老年人放宽：
 *   - 血氧低于 95% 需关注（健康成年人通常 ≥ 98%，老年人 95% 已属偏低）
 *   - 体温 36.0–37.2℃ 为正常，37.3℃ 起算发热
 *   - 步数没有"正常值"，只看当天是否有活动，所以不设阈值
 *
 * 这些值集中在这里而不是散在页面里：首页、实时状态、预警中心
 * 都要用同一套口径，否则同一个人在两页看到"正常"和"关注"会互相矛盾。
 */
export class VitalsConst {
  /** 血氧正常下限（%） */
  static readonly SPO2_MIN: number = 95;
  /** 体温正常下限（℃） */
  static readonly TEMP_MIN: number = 36.0;
  /** 体温正常上限（℃） */
  static readonly TEMP_MAX: number = 37.2;
}

/** 本地缓存表名 */
export class TableName {
  static readonly DEVICE: string = 'device';
  static readonly SENSOR: string = 'sensor';
  static readonly READING: string = 'sensor_reading';
  static readonly ALERT: string = 'alert';
  static readonly ALERT_HANDLE: string = 'alert_handle';
  static readonly ACTIVITY_DAILY: string = 'activity_daily';
  static readonly MEMBER: string = 'family_member';
}

/** 传感器类型 */
export class SensorType {
  static readonly PIR: string = 'pir';
  static readonly PIR_RK2206: string = 'pir_rk2206';
  static readonly PIR_H2821: string = 'pir_h2821';
  static readonly ILLUMINATION: string = 'illumination';
  static readonly DOOR: string = 'door';
  static readonly TEMP_HUMIDITY: string = 'temp_humidity';
  static readonly SMOKE: string = 'smoke';
  static readonly GAS: string = 'gas';
  static readonly SOS_BUTTON: string = 'sos_button';
  static readonly BATTERY: string = 'battery';
  /** 心率（毫米波雷达 / PPG 采集，挂载在监护主机上） */
  static readonly HEART_RATE: string = 'heart_rate';

  /** 中文名映射 */
  static labelOf(type: string): string {
    switch (type) {
      case SensorType.PIR:
        return '人体活动（汇总）';
      case SensorType.PIR_RK2206:
        return 'RK2206 板载人体活动';
      case SensorType.PIR_H2821:
        return 'H2821 星闪人体活动';
      case SensorType.ILLUMINATION:
        return '环境光照';
      case SensorType.DOOR:
        return '门窗状态';
      case SensorType.TEMP_HUMIDITY:
        return '温湿度';
      case SensorType.SMOKE:
        return '烟雾';
      case SensorType.GAS:
        return '燃气';
      case SensorType.SOS_BUTTON:
        return '紧急求助按钮';
      case SensorType.BATTERY:
        return '电量';
      case SensorType.HEART_RATE:
        return '心率';
      default:
        return '未知传感器';
    }
  }
}

/**
 * 传感器卡片状态 —— 三色圆点体系 + 离线灰。
 *
 * 全应用只有这四种状态，圆点颜色与之一一对应，不再各处自定：
 *   NORMAL  绿 · 一切正常
 *   WARNING 黄 · 待关注（如门窗长时间打开、温湿度偏离舒适区间）
 *   DANGER  红 · 高危（燃气泄漏 / 烟雾触发 / SOS 按下）
 *   OFFLINE 灰 · 设备断开连接，读数不可信
 *
 * 灰色刻意不复用红色：离线是"看不到"，不是"出事了"，
 * 混用会让家属把断连误判成事故，反而拉低告警的可信度。
 */
export class SensorStatus {
  static readonly NORMAL: string = 'normal';
  static readonly WARNING: string = 'warning';
  static readonly DANGER: string = 'danger';
  static readonly OFFLINE: string = 'offline';

  static labelOf(status: string): string {
    switch (status) {
      case SensorStatus.NORMAL:
        return '正常';
      case SensorStatus.WARNING:
        return '待关注';
      case SensorStatus.DANGER:
        return '高危';
      case SensorStatus.OFFLINE:
        return '设备离线';
      default:
        return '未知';
    }
  }
}

/**
 * 传感器风险分级 —— 安全优先级设计的核心。
 *
 * 高危类（烟雾 / 燃气 / SOS）：一旦异常直接进红色告警，走最高优先级推送。
 *   这三个是"会出人命"的量，没有中间态，不允许降级成黄色。
 * 普通监测类（人体活动 / 门窗 / 温湿度）：异常先给黄色提醒，
 *   由子女判断是否需要升级，避免误报打扰。
 */
export class SensorRisk {
  static readonly HIGH: string = 'high';
  static readonly NORMAL: string = 'normal';

  /** 该传感器类型属于哪个风险等级 */
  static gradeOf(sensorType: string): string {
    switch (sensorType) {
      case SensorType.SMOKE:
      case SensorType.GAS:
      case SensorType.SOS_BUTTON:
        return SensorRisk.HIGH;
      default:
        return SensorRisk.NORMAL;
    }
  }

  static isHighRisk(sensorType: string): boolean {
    return SensorRisk.gradeOf(sensorType) === SensorRisk.HIGH;
  }

  /** 异常时应该落到哪个状态：高危→红，普通→黄 */
  static abnormalStatus(sensorType: string): string {
    return SensorRisk.isHighRisk(sensorType) ? SensorStatus.DANGER : SensorStatus.WARNING;
  }
}

/** 告警等级 */
export class AlertLevel {
  static readonly P0: string = 'P0';
  static readonly P1: string = 'P1';
  static readonly P2: string = 'P2';
  static readonly P3: string = 'P3';

  static labelOf(level: string): string {
    switch (level) {
      case AlertLevel.P0:
        return '紧急';
      case AlertLevel.P1:
        return '高风险';
      case AlertLevel.P2:
        return '需关注';
      case AlertLevel.P3:
        return '提示';
      default:
        return '未知';
    }
  }

  /** 排序权重，数值越小越紧急 */
  static weightOf(level: string): number {
    switch (level) {
      case AlertLevel.P0:
        return 0;
      case AlertLevel.P1:
        return 1;
      case AlertLevel.P2:
        return 2;
      default:
        return 3;
    }
  }
}

/** 告警类型 */
export class AlertType {
  static readonly SOS_PRESSED: string = 'sos_pressed';
  static readonly GAS_LEAK: string = 'gas_leak';
  static readonly SMOKE_DETECTED: string = 'smoke_detected';
  static readonly NO_ACTIVITY: string = 'no_activity';
  static readonly TEMP_HUMIDITY_ABNORMAL: string = 'temp_humidity_abnormal';
  static readonly DOOR_ABNORMAL: string = 'door_abnormal';
  static readonly DEVICE_OFFLINE: string = 'device_offline';
  static readonly LOW_BATTERY: string = 'low_battery';

  static labelOf(type: string): string {
    switch (type) {
      case AlertType.SOS_PRESSED:
        return '紧急求助';
      case AlertType.GAS_LEAK:
        return '燃气泄漏';
      case AlertType.SMOKE_DETECTED:
        return '烟雾报警';
      case AlertType.NO_ACTIVITY:
        return '长时间无活动';
      case AlertType.TEMP_HUMIDITY_ABNORMAL:
        return '温湿度异常';
      case AlertType.DOOR_ABNORMAL:
        return '门窗异常';
      case AlertType.DEVICE_OFFLINE:
        return '设备离线';
      case AlertType.LOW_BATTERY:
        return '电量低';
      default:
        return '未知告警';
    }
  }

  /** 该类型的默认等级 */
  static defaultLevelOf(type: string): string {
    switch (type) {
      case AlertType.SOS_PRESSED:
      case AlertType.GAS_LEAK:
      case AlertType.SMOKE_DETECTED:
        return AlertLevel.P0;
      case AlertType.NO_ACTIVITY:
        return AlertLevel.P1;
      case AlertType.TEMP_HUMIDITY_ABNORMAL:
      case AlertType.DOOR_ABNORMAL:
        return AlertLevel.P2;
      default:
        return AlertLevel.P3;
    }
  }
}

/** 告警处理状态 */
export class AlertStatus {
  static readonly PENDING: string = 'pending';
  static readonly CONFIRMED: string = 'confirmed';
  static readonly HANDLED: string = 'handled';
  static readonly FALSE_ALARM: string = 'false_alarm';

  static labelOf(status: string): string {
    switch (status) {
      case AlertStatus.PENDING:
        return '待确认';
      case AlertStatus.CONFIRMED:
        return '已确认';
      case AlertStatus.HANDLED:
        return '已处置';
      case AlertStatus.FALSE_ALARM:
        return '误报';
      default:
        return '未知';
    }
  }
}

/** 处置结果枚举 */
export class HandleResult {
  static readonly GRID_WORKER: string = 'contacted_grid_worker';
  static readonly PROPERTY: string = 'contacted_property';
  static readonly SELF_HANDLED: string = 'self_handled';
  static readonly ELDER_NORMAL: string = 'elder_normal';
  /**
   * 列表页一步标记，未填写具体处置结果。
   * 与 ELDER_NORMAL 这类"带结论"的结果分开：
   * 安全类 App 不能替用户写结论，快速标记只记录"已阅"。
   */
  static readonly QUICK_MARKED: string = 'quick_marked';
  static readonly FALSE_ALARM: string = 'false_alarm';
  static readonly OTHER: string = 'other';

  static labelOf(result: string): string {
    switch (result) {
      case HandleResult.GRID_WORKER:
        return '已联系社区网格员上门查看';
      case HandleResult.PROPERTY:
        return '已联系物业';
      case HandleResult.SELF_HANDLED:
        return '已自行处理';
      case HandleResult.ELDER_NORMAL:
        return '老人一切正常';
      case HandleResult.QUICK_MARKED:
        return '已快速标记，未填写处置详情';
      case HandleResult.FALSE_ALARM:
        return '误报';
      case HandleResult.OTHER:
        return '其他';
      default:
        return '未知';
    }
  }

  /** 供处置页面直接渲染的预设选项 */
  static all(): string[] {
    return [
      HandleResult.GRID_WORKER, HandleResult.PROPERTY, HandleResult.SELF_HANDLED,
      HandleResult.ELDER_NORMAL, HandleResult.FALSE_ALARM, HandleResult.OTHER
    ];
  }
}

/** 家庭成员角色 */
export class MemberRole {
  static readonly CHILD: string = 'child';
  static readonly GRID_WORKER: string = 'grid_worker';
  static readonly PROPERTY: string = 'property';
  static readonly MAINTAINER: string = 'maintainer';

  static labelOf(role: string): string {
    switch (role) {
      case MemberRole.CHILD:
        return '子女';
      case MemberRole.GRID_WORKER:
        return '社区网格员';
      case MemberRole.PROPERTY:
        return '物业值班';
      case MemberRole.MAINTAINER:
        return '维护人员';
      default:
        return '未知角色';
    }
  }

  /** 是否可查看活动报告（隐私边界：仅直系家属） */
  static canViewActivity(role: string): boolean {
    return role === MemberRole.CHILD;
  }

  /** 是否可处置告警 */
  static canHandle(role: string): boolean {
    return role !== MemberRole.MAINTAINER;
  }
}

/** 云端调用结果码 */
export class CloudCode {
  static readonly OK: number = 0;
  static readonly PARAM_ERROR: number = 1001;
  static readonly TOKEN_INVALID: number = 1002;
  static readonly NO_PERMISSION: number = 1003;
  static readonly NOT_FOUND: number = 1004;
  static readonly RATE_LIMITED: number = 1005;
  static readonly DEVICE_NOT_REGISTERED: number = 2001;
  static readonly DEVICE_BOUND_ELSEWHERE: number = 2002;
  static readonly SERVER_ERROR: number = 3001;
  static readonly SERVICE_UNAVAILABLE: number = 3002;
}
