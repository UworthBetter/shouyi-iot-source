/**
 * 时间工具。
 * 云端约定使用毫秒时间戳，时区统一东八区。
 */
export class DateUtil {
  /** 当前毫秒时间戳 */
  static now(): number {
    return new Date().getTime();
  }

  /** 某天零点的毫秒时间戳 */
  static startOfDay(timestamp: number): number {
    const d: Date = new Date(timestamp);
    d.setHours(0, 0, 0, 0);
    return d.getTime();
  }

  /** N 天前的零点时间戳 */
  static daysAgo(days: number): number {
    return DateUtil.startOfDay(DateUtil.now() - days * 86400000);
  }

  /** 格式化为 yyyy-MM-dd */
  static formatDate(timestamp: number): string {
    if (timestamp <= 0) {
      return '—';
    }
    const d: Date = new Date(timestamp);
    const p = (n: number): string => n < 10 ? `0${n}` : `${n}`;
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
  }

  /** 格式化为 MM-dd */
  static formatShortDate(timestamp: number): string {
    if (timestamp <= 0) {
      return '—';
    }
    const d: Date = new Date(timestamp);
    const p = (n: number): string => n < 10 ? `0${n}` : `${n}`;
    return `${p(d.getMonth() + 1)}-${p(d.getDate())}`;
  }

  /** 格式化为 HH:mm */
  static formatTime(timestamp: number): string {
    if (timestamp <= 0) {
      return '—';
    }
    const d: Date = new Date(timestamp);
    const p = (n: number): string => n < 10 ? `0${n}` : `${n}`;
    return `${p(d.getHours())}:${p(d.getMinutes())}`;
  }

  static formatSampleTime(timestamp: number): string {
    const seconds: number = new Date(timestamp).getSeconds();
    return `${DateUtil.formatTime(timestamp)}:${seconds < 10 ? '0' : ''}${seconds}`;
  }

  /** 格式化为 yyyy-MM-dd HH:mm */
  static format(timestamp: number): string {
    if (timestamp <= 0) {
      return '—';
    }
    return `${DateUtil.formatDate(timestamp)} ${DateUtil.formatTime(timestamp)}`;
  }

  /** 相对时间描述，用于"最后活动""最后同步"等场景 */
  static relative(timestamp: number): string {
    if (timestamp <= 0) {
      return '暂无记录';
    }
    const diff: number = DateUtil.now() - timestamp;
    if (diff < 0) {
      return '刚刚';
    }
    if (diff < 60000) {
      return '刚刚';
    }
    if (diff < 3600000) {
      return `${Math.floor(diff / 60000)} 分钟前`;
    }
    if (diff < 86400000) {
      return `${Math.floor(diff / 3600000)} 小时前`;
    }
    return `${Math.floor(diff / 86400000)} 天前`;
  }

  /** 取小时（0-23） */
  static hourOf(timestamp: number): number {
    return new Date(timestamp).getHours();
  }
}

/**
 * 通用工具。
 */
export class UuidUtil {
  static generate(): string {
    const s: string[] = [];
    const hex: string = '0123456789abcdef';
    for (let i = 0; i < 32; i++) {
      s.push(hex.charAt(Math.floor(Math.random() * 16)));
    }
    return `${s.slice(0, 8).join('')}-${s.slice(8, 12).join('')}-${s.slice(12, 16).join('')}`
      + `-${s.slice(16, 20).join('')}-${s.slice(20).join('')}`;
  }
}
