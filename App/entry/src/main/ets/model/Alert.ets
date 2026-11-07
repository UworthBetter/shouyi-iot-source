/**
 * 告警事件。
 * 本模块的核心实体 —— 从触发到处置闭环，全部围绕它展开。
 */
export class Alert {
  /** 告警唯一 ID（设备端生成 UUID，保证幂等） */
  alertId: string = '';
  /** 云端返回的告警 ID */
  serverAlertId: string = '';
  deviceId: string = '';
  deviceName: string = '';
  /** 告警类型，见 AlertType */
  alertType: string = '';
  /** 告警类型中文名，避免客户端重复映射 */
  alertTypeName: string = '';
  /** 等级 P0/P1/P2/P3 */
  level: string = '';
  /** 触发时间戳 */
  timestamp: number = 0;
  /** 触发时的实测值 */
  triggerValue: number = 0;
  /** 触发阈值 */
  threshold: number = 0;
  /** 描述文案 */
  description: string = '';
  /** 处理状态，见 AlertStatus */
  status: string = '';
  /** 已推送给哪些角色 */
  notifiedRoles: string[] = [];
  /** 处置记录 */
  handle: AlertHandle | undefined = undefined;

  /** 是否仍未处置 */
  isPending(): boolean {
    return this.status === 'pending' || this.status === 'confirmed';
  }

  /** 是否紧急（P0 需要特殊视觉处理） */
  isCritical(): boolean {
    return this.level === 'P0';
  }
}

/**
 * 处置记录（事件闭环的产物）。
 */
export class AlertHandle {
  /** 处置人姓名 */
  handlerName: string = '';
  /** 处置人角色 */
  handlerRole: string = '';
  /** 处置结果枚举值 */
  result: string = '';
  /** 处置结果中文名 */
  resultName: string = '';
  /** 补充说明 */
  note: string = '';
  /** 处置时间 */
  handledAt: number = 0;
  /** 是否同时调整了阈值（误报反馈闭环） */
  thresholdAdjusted: boolean = false;
}

/**
 * 告警时间线节点。
 * 让一条告警从触发到处置的全过程可视化 —— 答辩时的展示重点。
 */
export class AlertTimelineNode {
  time: number = 0;
  /** 事件类型：triggered / uploaded / notified / confirmed / handled / escalated */
  event: string = '';
  /** 展示文案 */
  text: string = '';

  static eventLabel(event: string): string {
    switch (event) {
      case 'triggered':
        return '触发';
      case 'uploaded':
        return '上报';
      case 'notified':
        return '推送';
      case 'confirmed':
        return '确认';
      case 'handled':
        return '处置';
      case 'escalated':
        return '升级';
      default:
        return '事件';
    }
  }
}

/**
 * 居家安全日志条目。
 * 把所有已处置的告警按时间排列，形成可回溯的时间线 —— 赛题要求的
 * "形成居家安全日志，便于长期跟踪老人生活状态"。
 */
export class SafetyLogEntry {
  logId: string = '';
  alertId: string = '';
  date: string = '';
  level: string = '';
  alertTypeName: string = '';
  triggeredAt: number = 0;
  handledAt: number = 0;
  handlerName: string = '';
  resultName: string = '';
  note: string = '';
}

/**
 * 阈值调整建议。
 * 误报反馈闭环的载体：用户标记误报后，提示是否放宽阈值。
 */
export class ThresholdSuggestion {
  /** 阈值键名 */
  key: string = '';
  /** 展示名 */
  label: string = '';
  /** 当前值 */
  currentValue: number = 0;
  /** 建议值 */
  suggestedValue: number = 0;
  /** 单位 */
  unit: string = '';
  /** 提示文案 */
  message: string = '';
}
