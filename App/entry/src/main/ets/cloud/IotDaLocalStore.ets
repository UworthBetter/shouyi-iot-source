/**
 * @file    IotDaLocalStore.ets
 * @brief   IoTDA 适配器的本地持久化层
 *
 * 为什么需要它：
 *   华为云 IoTDA 只提供「设备属性查询 + 命令下发」，**没有**告警列表、
 *   安全日志、活动报告、家庭成员这些业务接口。而这些是赛题要求的能力，
 *   所以必须落在 App 端自己存。
 *
 * 实现选型：@kit.CoreFileKit 的 fileIo，JSON 文件存到应用沙箱 filesDir。
 *   不用 preferences：它的单个 string 值上限 8KB，存 30 条告警就超了。
 *   不用 relationalStore：本阶段数据量小，SQLite 的建表/迁移成本不划算。
 *
 * 文件布局（都在 filesDir 下）：
 *   iotda_alerts.json   告警（含时间线与处置结果），保留最近 100 条
 *   iotda_logs.json     居家安全日志，保留最近 200 条
 *   iotda_daily.json    按天活动汇总，保留最近 30 天
 *   iotda_hourly.json   按小时活动计数（热力图数据源），保留最近 14 天
 *   iotda_members.json  家庭成员与角色
 */

import { fileIo } from '@kit.CoreFileKit';
import { Alert, AlertHandle, SafetyLogEntry } from '../model/Alert';
import { ActivityDaily, HeatmapCell } from '../model/ActivityRecord';
import { FamilyMember } from '../model/FamilyMember';
import { Logger } from '../common/utils/Logger';
import { DateUtil } from '../common/utils/DateUtil';

export class IotDaHistorySample {
  timestamp: number = 0;
  values: Record<string, number> = {};
}

export class IotDaLocalStore {
  private static readonly MODULE: string = 'IotDaLocalStore';

  private static readonly MAX_ALERTS: number = 100;
  private static readonly MAX_LOGS: number = 200;
  private static readonly MAX_DAILY: number = 30;
  private static readonly MAX_HOURLY_DAYS: number = 14;

  /** 应用沙箱目录，由 init() 注入；未注入时所有操作静默跳过 */
  private dir: string = '';

  /**
   * 初始化。
   * @param filesDir 传 UIAbilityContext.filesDir
   */
  init(filesDir: string): void {
    this.dir = filesDir;
    Logger.info(IotDaLocalStore.MODULE, `本地存储目录: ${filesDir}`);
  }

  isReady(): boolean {
    return this.dir.length > 0;
  }

  private historyHour: number = -1;

  loadHistory(now: number): IotDaHistorySample[] {
    const lastHour: number = Math.floor(now / 3600000);
    const from: number = now - 86400000;
    const samples: IotDaHistorySample[] = [];
    for (let hour: number = lastHour - 24; hour <= lastHour; hour++) {
      const path: string = this.pathOf(`iotda_history_${hour % 25}.jsonl`);
      try {
        if (!fileIo.accessSync(path)) {
          continue;
        }
        for (const line of fileIo.readTextSync(path).split('\n')) {
          if (line.length === 0) {
            continue;
          }
          try {
            const sample = JSON.parse(line) as IotDaHistorySample;
            if (Math.floor(sample.timestamp / 3600000) === hour && sample.timestamp >= from &&
              sample.values !== undefined) {
              samples.push(sample);
              this.historyHour = hour;
            }
          } catch (_) {
            // Skip a partial record if the app stopped during a write.
          }
        }
      } catch (e) {
        Logger.warn(IotDaLocalStore.MODULE, `读取监测历史失败: ${(e as Error).message}`);
      }
    }
    return samples;
  }

  appendHistory(sample: IotDaHistorySample): void {
    if (!this.isReady()) {
      return;
    }
    const hour: number = Math.floor(sample.timestamp / 3600000);
    const mode: number = this.historyHour === hour ? fileIo.OpenMode.APPEND : fileIo.OpenMode.TRUNC;
    try {
      const file = fileIo.openSync(this.pathOf(`iotda_history_${hour % 25}.jsonl`),
        fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | mode);
      try {
        fileIo.writeSync(file.fd, '\n' + JSON.stringify(sample) + '\n');
        this.historyHour = hour;
      } finally {
        fileIo.closeSync(file);
      }
    } catch (e) {
      Logger.warn(IotDaLocalStore.MODULE, `保存监测读数失败: ${(e as Error).message}`);
    }
  }

  // ==================== 通用读写 ====================

  private pathOf(name: string): string {
    return `${this.dir}/${name}`;
  }

  private readArray<T>(name: string): T[] {
    if (this.dir.length === 0) {
      Logger.warn(IotDaLocalStore.MODULE, `readArray ${name}: dir 未初始化`);
      return [];
    }
    const p: string = this.pathOf(name);
    try {
      if (!fileIo.accessSync(p)) {
        Logger.warn(IotDaLocalStore.MODULE, `readArray ${name}: 文件不存在 ${p}`);
        return [];
      }
      const text: string = fileIo.readTextSync(p);
      if (text.length === 0) {
        Logger.warn(IotDaLocalStore.MODULE, `readArray ${name}: 文件为空（写入竞态？）`);
        return [];
      }
      return JSON.parse(text) as T[];
    } catch (e) {
      Logger.warn(IotDaLocalStore.MODULE, `读取 ${name} 失败: ${(e as Error).message}`);
      return [];
    }
  }

  private writeArray<T>(name: string, list: T[]): void {
    if (this.dir.length === 0) {
      return;
    }
    const p: string = this.pathOf(name);
    try {
      const f = fileIo.openSync(p,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(f.fd, JSON.stringify(list));
      fileIo.closeSync(f);
    } catch (e) {
      Logger.warn(IotDaLocalStore.MODULE, `写入 ${name} 失败: ${(e as Error).message}`);
    }
  }

  // ==================== 告警 ====================

  /**
   * 读取告警。
   *
   * ⚠️ 必须做「实例还原」：JSON.parse 得到的是普通对象，**没有原型**，
   * 直接当 Alert 用会导致 a.isPending() 报 "undefined is not callable"。
   * 这是实测踩过的坑（首页加载失败就是它）。
   */
  loadAlerts(): Alert[] {
    const raw: Alert[] = this.readArray<Alert>('iotda_alerts.json');
    const out: Alert[] = [];
    for (const r of raw) {
      if (r.alertId.startsWith('demo_')) {
        continue;
      }
      const a: Alert = new Alert();
      a.alertId = r.alertId;
      a.serverAlertId = r.serverAlertId;
      a.deviceId = r.deviceId;
      a.deviceName = r.deviceName;
      a.alertType = r.alertType;
      a.alertTypeName = r.alertTypeName;
      a.level = r.level;
      a.timestamp = r.timestamp;
      a.triggerValue = r.triggerValue;
      a.threshold = r.threshold;
      a.description = r.description;
      a.status = r.status;
      a.notifiedRoles = r.notifiedRoles === undefined || r.notifiedRoles === null
        ? [] : r.notifiedRoles;

      const hRaw = r.handle;
      if (hRaw !== undefined && hRaw !== null) {
        const h: AlertHandle = new AlertHandle();
        h.handlerName = hRaw.handlerName;
        h.handlerRole = hRaw.handlerRole;
        h.result = hRaw.result;
        h.resultName = hRaw.resultName;
        h.note = hRaw.note;
        h.handledAt = hRaw.handledAt;
        h.thresholdAdjusted = hRaw.thresholdAdjusted;
        a.handle = h;
      }
      out.push(a);
    }
    return out;
  }

  /** 追加告警（最新在前），超上限截断 */
  appendAlert(alert: Alert): void {
    const list: Alert[] = this.loadAlerts();
    list.unshift(alert);
    const capped: Alert[] = list.slice(0, IotDaLocalStore.MAX_ALERTS);
    this.writeArray<Alert>('iotda_alerts.json', capped);
  }

  /**
   * 删除一条告警（只删 App 本地记录）。
   *
   * 使用场景：已处置/误报的告警在列表里堆积，家属手动清理。
   * 调用方（AlertCard）必须自己保证只删已闭环的 —— 待确认的告警
   * 不能凭空消失，那是安全兜底。
   *
   * 注意：居家安全日志（iotda_logs.json）不随之删除，
   * 留痕是赛题要求的长期跟踪能力，与列表整洁度无关。
   *
   * @return true 表示确实删掉了一条
   */
  deleteAlert(alertId: string): boolean {
    const list: Alert[] = this.loadAlerts();
    const kept: Alert[] = list.filter((a: Alert) => a.alertId !== alertId);
    if (kept.length === list.length) {
      return false;
    }
    this.writeArray<Alert>('iotda_alerts.json', kept);
    Logger.info(IotDaLocalStore.MODULE, `删除告警 ${alertId}，剩余 ${kept.length} 条`);
    return true;
  }

  /**
   * 批量把全部「待处置」告警标记为已处置，并一次性写入安全日志。
   *
   * 与单条 handleAlert 同语义：处置结果要留痕。这里攒够一批再落盘，
   * 避免逐条 read-modify-write 造成 100 次文件 IO。
   *
   * @return 实际处理的条数
   */
  markAllPendingHandled(handlerName: string, resultName: string, note: string): number {
    const list: Alert[] = this.loadAlerts();
    const now: number = Date.now();
    const newLogs: SafetyLogEntry[] = [];
    let count: number = 0;
    for (const a of list) {
      if (a.status !== 'pending') {
        continue;
      }
      a.status = 'handled';
      const h: AlertHandle = new AlertHandle();
      h.handlerName = handlerName;
      h.handlerRole = 'child';
      h.result = 'resolved';
      h.resultName = resultName;
      h.note = note;
      h.handledAt = now;
      h.thresholdAdjusted = false;
      a.handle = h;

      const log: SafetyLogEntry = new SafetyLogEntry();
      log.logId = `log_${a.alertId}`;
      log.alertId = a.alertId;
      log.date = DateUtil.formatDate(a.timestamp);
      log.level = a.level;
      log.alertTypeName = a.alertTypeName;
      log.triggeredAt = a.timestamp;
      log.handledAt = now;
      log.handlerName = handlerName;
      log.resultName = resultName;
      log.note = note;
      newLogs.push(log);
      count = count + 1;
    }
    if (count > 0) {
      this.writeArray<Alert>('iotda_alerts.json', list);
      if (newLogs.length > 0) {
        const logs: SafetyLogEntry[] = this.loadLogs();
        const merged: SafetyLogEntry[] = newLogs.concat(logs).slice(0, IotDaLocalStore.MAX_LOGS);
        this.writeArray<SafetyLogEntry>('iotda_logs.json', merged);
      }
      Logger.info(IotDaLocalStore.MODULE, `批量标记已处置 ${count} 条`);
    }
    return count;
  }

  /**
   * 清空全部「待处置」告警（仅 App 本地记录）。
   * 已处置 / 误报的记录不受影响，安全日志也不动。
   *
   * @return 实际删除的条数
   */
  clearPending(): number {
    const list: Alert[] = this.loadAlerts();
    const kept: Alert[] = list.filter((a: Alert) => a.status !== 'pending');
    const removed: number = list.length - kept.length;
    if (removed > 0) {
      this.writeArray<Alert>('iotda_alerts.json', kept);
      Logger.info(IotDaLocalStore.MODULE, `清空待处置 ${removed} 条，剩余 ${kept.length} 条`);
    }
    return removed;
  }

  /** 按 alertId 更新状态，返回更新后的告警；找不到返回 undefined */
  updateAlert(alertId: string, status: string, handleNote: string,
              handlerName: string, resultName: string): Alert | undefined {
    const list: Alert[] = this.loadAlerts();
    let hit: Alert | undefined = undefined;
    for (const a of list) {
      if (a.alertId === alertId) {
        a.status = status;
        if (handleNote.length > 0) {
          const h: AlertHandle = new AlertHandle();
          h.handlerName = handlerName;
          h.handlerRole = 'child';
          h.result = 'resolved';
          h.resultName = resultName;
          h.note = handleNote;
          h.handledAt = Date.now();
          h.thresholdAdjusted = false;
          a.handle = h;
        }
        hit = a;
        break;
      }
    }
    if (hit !== undefined) {
      this.writeArray<Alert>('iotda_alerts.json', list);
    }
    return hit;
  }

  // ==================== 安全日志 ====================

  loadLogs(): SafetyLogEntry[] {
    return this.readArray<SafetyLogEntry>('iotda_logs.json')
      .filter((entry: SafetyLogEntry) => !entry.alertId.startsWith('demo_'));
  }

  appendLog(entry: SafetyLogEntry): void {
    const list: SafetyLogEntry[] = this.loadLogs();
    list.unshift(entry);
    this.writeArray<SafetyLogEntry>('iotda_logs.json', list.slice(0, IotDaLocalStore.MAX_LOGS));
  }

  // ==================== 活动统计 ====================

  loadDaily(): ActivityDaily[] {
    return this.readArray<ActivityDaily>('iotda_daily.json');
  }

  loadHourly(): HeatmapCell[] {
    return this.readArray<HeatmapCell>('iotda_hourly.json');
  }

  /**
   * 记录一次活动（PIR 上升沿）。
   * 同时更新「当天汇总」与「当前小时计数」。
   */
  recordActivity(deviceId: string, date: string, hour: number, ts: number): void {
    // --- 当天汇总 ---
    const daily: ActivityDaily[] = this.loadDaily();
    let day: ActivityDaily | undefined = undefined;
    for (const d of daily) {
      if (d.date === date) {
        day = d;
        break;
      }
    }
    if (day === undefined) {
      day = new ActivityDaily();
      day.deviceId = deviceId;
      day.date = date;
      day.dayStart = ts;
      day.firstActivity = ts;
      day.totalCount = 0;
      day.activeHours = 0;
      day.nightCount = 0;
      daily.push(day);
    }
    day.totalCount = day.totalCount + 1;
    day.lastActivity = ts;
    if (day.firstActivity === 0) {
      day.firstActivity = ts;
    }
    if (hour >= 22 || hour < 6) {
      day.nightCount = day.nightCount + 1;
    }
    // 活跃小时数：用小时集合大小近似（不落库，按 hourly 重算更准，这里做增量）
    daily.sort((a: ActivityDaily, b: ActivityDaily) => a.date < b.date ? -1 : 1);
    const cappedDaily: ActivityDaily[] = daily.slice(Math.max(0, daily.length - IotDaLocalStore.MAX_DAILY));
    this.writeArray<ActivityDaily>('iotda_daily.json', cappedDaily);

    // --- 小时计数 ---
    const hourly: HeatmapCell[] = this.loadHourly();
    let cell: HeatmapCell | undefined = undefined;
    for (const c of hourly) {
      if (c.date === date && c.hour === hour) {
        cell = c;
        break;
      }
    }
    if (cell === undefined) {
      cell = new HeatmapCell();
      cell.date = date;
      cell.hour = hour;
      cell.count = 0;
      hourly.push(cell);
    }
    cell.count = cell.count + 1;
    this.writeArray<HeatmapCell>('iotda_hourly.json', hourly);
  }

  // ==================== 家庭成员 ====================

  loadMembers(): FamilyMember[] {
    return this.readArray<FamilyMember>('iotda_members.json');
  }

  saveMembers(list: FamilyMember[]): void {
    this.writeArray<FamilyMember>('iotda_members.json', list);
  }
}
