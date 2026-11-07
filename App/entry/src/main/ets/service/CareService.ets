import { AppConfig } from '../cloud/CloudApiFactory';
import { CloudApi } from '../cloud/CloudApi';
import {
  AlertQuery, HandleAlertReq, PushMessage, PushListener, DeviceListItem, DeviceStatusResp,
  ReadingsQuery, ReadingsResp
} from '../cloud/CloudTypes';
import { Alert, SafetyLogEntry, ThresholdSuggestion } from '../model/Alert';
import { ActivityReport } from '../model/ActivityRecord';
import { FamilyMember } from '../model/FamilyMember';
import { DeviceConfig } from '../model/Device';
import { ActivityAnalysisService } from './ActivityAnalysisService';
import { NetworkMonitor } from './NetworkMonitor';
import { AppConstants, AlertStatus, AlertType, MemberRole } from '../common/constants/AppConstants';
import { DateUtil } from '../common/utils/DateUtil';
import { Logger } from '../common/utils/Logger';

/**
 * 业务服务门面。
 *
 * 表现层只与本类交互，不直接接触 CloudApi。
 * 职责：
 *   1. 转发云端调用（屏蔽具体适配器）；
 *   2. 缓存最近一次结果，供离线时展示；
 *   3. 做跨接口的组合（如告警列表 + 处置记录 → 居家安全日志）；
 *   4. 承载业务规则（如按角色过滤可见内容）。
 */
export class CareService {
  private static readonly MODULE: string = 'CareService';
  private static readonly FAMILY_ID: string = 'fam_mock_0001';

  private cloud: CloudApi = AppConfig.getCloudApi();

  /** 离线缓存：最近一次成功拉取的数据 */
  private cacheDevices: DeviceListItem[] = [];
  private cacheAlerts: Alert[] = [];
  private cacheReport: ActivityReport | undefined = undefined;
  private cacheMembers: FamilyMember[] = [];

  /** 当前登录用户角色，决定可见范围 */
  private currentRole: string = MemberRole.CHILD;

  constructor() {
    this.cloud = AppConfig.getCloudApi();
  }

  /** 云端实现名称，供界面展示 */
  cloudName(): string {
    return this.cloud.adapterName();
  }

  setRole(role: string): void {
    this.currentRole = role;
  }

  getRole(): string {
    return this.currentRole;
  }

  /** 当前角色是否可查看活动报告（隐私边界） */
  canViewActivity(): boolean {
    return MemberRole.canViewActivity(this.currentRole);
  }

  // ==================== 演示（仅 Mock 可用） ====================

  /**
   * 当前是否跑在 Mock 数据上。
   * 演示入口只在 Mock 下显示 —— 真实云端不允许切场景。
   */
  isMock(): boolean {
    return this.cloud.setDemoScenario !== undefined;
  }

  /**
   * 切换演示场景：normal / warning / danger。
   * 真实云端不实现该方法，这里静默返回 false，不影响主流程。
   */
  setDemoScenario(scenario: string): boolean {
    if (this.cloud.setDemoScenario === undefined) {
      return false;
    }
    this.cloud.setDemoScenario(scenario);
    return true;
  }

  /** 读取当前演示场景；非 Mock 返回空串 */
  demoScenario(): string {
    if (this.cloud.getDemoScenario === undefined) {
      return '';
    }
    return this.cloud.getDemoScenario();
  }

  // ==================== 设备 ====================

  /** 拉取设备列表；离线时返回缓存 */
  async loadDevices(): Promise<DeviceListItem[]> {
    if (!NetworkMonitor.isOnline()) {
      Logger.info(CareService.MODULE, '离线，返回缓存的设备列表');
      return this.cacheDevices;
    }
    try {
      const list: DeviceListItem[] = await this.cloud.getDeviceList(CareService.FAMILY_ID);
      this.cacheDevices = list;
      return list;
    } catch (err) {
      Logger.warn(CareService.MODULE, `拉取设备列表失败，降级用缓存: ${(err as Error).message}`);
      return this.cacheDevices;
    }
  }

  /** 拉取设备实时状态 */
  async loadDeviceStatus(deviceId: string): Promise<DeviceStatusResp | undefined> {
    try {
      return await this.cloud.getDeviceStatus(deviceId);
    } catch (err) {
      Logger.warn(CareService.MODULE, `拉取设备状态失败: ${(err as Error).message}`);
      return undefined;
    }
  }

  /**
   * 拉取指定传感器的历史读数。
   * 用于实时状态页的历史曲线。
   */
  async loadReadings(sensorType: string, from: number, to: number,
    interval: string = '1h'): Promise<ReadingsResp | undefined> {
    try {
      const query: ReadingsQuery = {
        deviceId: '',
        from: from,
        to: to,
        sensorType: sensorType,
        interval: interval
      };
      return await this.cloud.getReadings(query);
    } catch (err) {
      Logger.warn(CareService.MODULE, `拉取历史读数失败: ${(err as Error).message}`);
      return undefined;
    }
  }

  // ==================== 告警 ====================

  /**
   * 拉取告警列表。
   *
   * ⚠️ 这里不能加"离线就走缓存"的门控：getAlerts 只读 App 本地存储
   * （IoTDA 没有告警列表接口），根本不走网络。实测踩坑：NetworkMonitor
   * 判定离线时走了 filterCachedAlerts，而每个页面 new 自己的 CareService，
   * 新实例 cacheAlerts 是空的 —— 预警中心打开显示 0 条，首页角标却还是
   * 76。离线也能看告警才对，所以只在本地读失败时才降级到内存缓存。
   */
  async loadAlerts(status: string = '', level: string = '', days: number = 30): Promise<Alert[]> {
    try {
      const query: AlertQuery = {
        deviceId: '',
        status: status,
        level: level,
        from: DateUtil.daysAgo(days),
        to: DateUtil.now(),
        page: 1,
        pageSize: 100
      };
      const page = await this.cloud.getAlerts(query);
      this.cacheAlerts = page.list;
      return page.list;
    } catch (err) {
      Logger.warn(CareService.MODULE, `拉取告警失败，降级用缓存: ${(err as Error).message}`);
      return this.filterCachedAlerts(status, level);
    }
  }

  private filterCachedAlerts(status: string, level: string): Alert[] {
    let list: Alert[] = this.cacheAlerts.slice();
    if (status.length > 0) {
      list = list.filter((a: Alert) => a.status === status);
    }
    if (level.length > 0) {
      list = list.filter((a: Alert) => a.level === level);
    }
    return list;
  }

  /** 未处置告警数，用于角标 */
  async countPendingAlerts(): Promise<number> {
    const list: Alert[] = await this.loadAlerts(AlertStatus.PENDING);
    return list.length;
  }

  static notifyAlertsChanged(): void {
    const current: number = AppStorage.get<number>('alertRefreshTick') ?? 0;
    AppStorage.setOrCreate('alertRefreshTick', current + 1);
  }

  /** 告警详情 */
  async loadAlertDetail(alertId: string) {
    return await this.cloud.getAlertDetail(alertId);
  }

  /** 确认告警 */
  async confirmAlert(alertId: string, remark: string): Promise<boolean> {
    try {
      await this.cloud.confirmAlert(alertId, remark);
      CareService.notifyAlertsChanged();
      return true;
    } catch (err) {
      Logger.error(CareService.MODULE, `确认告警失败: ${(err as Error).message}`);
      return false;
    }
  }

  /**
   * 提交处置结果（事件闭环）。
   * 若同时带了阈值调整，一并提交，形成误报反馈闭环。
   */
  async handleAlert(alertId: string, result: string, note: string,
    adjustKey: string = '', adjustValue: number = 0): Promise<boolean> {
    try {
      const req: HandleAlertReq = {
        result: result,
        note: note,
        adjustThresholdKey: adjustKey,
        adjustThresholdValue: adjustValue
      };
      await this.cloud.handleAlert(alertId, req);
      CareService.notifyAlertsChanged();
      Logger.info(CareService.MODULE, `告警 ${alertId} 已处置：${result}`);
      return true;
    } catch (err) {
      Logger.error(CareService.MODULE, `提交处置结果失败: ${(err as Error).message}`);
      return false;
    }
  }

  /**
   * 删除一条告警（仅本地记录）。
   *
   * 只删告警本身：居家安全日志、活动统计（日报/周报/月报的数据源）
   * 都不动 —— 日志是留痕，活动数据与告警列表无关。
   * 已闭环（已处置/误报）才允许删，待确认的由 UI 层拦截。
   */
  async deleteAlert(alertId: string): Promise<boolean> {
    try {
      const ok: boolean = await this.cloud.deleteAlert(alertId);
      if (ok) {
        CareService.notifyAlertsChanged();
        Logger.info(CareService.MODULE, `告警 ${alertId} 已删除`);
      }
      return ok;
    } catch (err) {
      Logger.error(CareService.MODULE, `删除告警失败: ${(err as Error).message}`);
      return false;
    }
  }

  /**
   * 批量把全部待处置告警标记为已处置，返回处理条数。
   * 只动 App 侧记录：安全日志照常留痕，活动报告数据不受影响。
   */
  async markAllPendingHandled(): Promise<number> {
    try {
      const n: number = await this.cloud.markAllPendingHandled();
      CareService.notifyAlertsChanged();
      Logger.info(CareService.MODULE, `批量标记已处置 ${n} 条`);
      return n;
    } catch (err) {
      Logger.error(CareService.MODULE, `批量标记已处置失败: ${(err as Error).message}`);
      return 0;
    }
  }

  /**
   * 清空全部待处置告警，返回删除条数。
   * 只删告警本身；安全日志、活动统计（日报/周报/月报数据源）都不动。
   */
  async clearPendingAlerts(): Promise<number> {
    try {
      const n: number = await this.cloud.clearPendingAlerts();
      CareService.notifyAlertsChanged();
      Logger.info(CareService.MODULE, `清空待处置 ${n} 条`);
      return n;
    } catch (err) {
      Logger.error(CareService.MODULE, `清空待处置失败: ${(err as Error).message}`);
      return 0;
    }
  }

  /**
   * 演示用：注入 count 条模拟告警，返回实际注入条数。
   * 给评委演示「告警到达 → 处置 → 删除」的闭环，节奏可控。
   */
  async injectDemoAlerts(count: number): Promise<number> {
    if (!this.isMock()) {
      return 0;
    }
    try {
      const n: number = await this.cloud.injectDemoAlerts(count);
      Logger.info(CareService.MODULE, `演示注入告警 ${n} 条`);
      return n;
    } catch (err) {
      Logger.error(CareService.MODULE, `演示注入告警失败: ${(err as Error).message}`);
      return 0;
    }
  }

  /**
   * 拉取设备配置。
   * 预警列表的「联系老人」要用其中的老人联系电话。
   */
  async fetchDeviceConfig(): Promise<DeviceConfig | undefined> {
    try {
      return await this.cloud.fetchDeviceConfig('');
    } catch (err) {
      Logger.error(CareService.MODULE, `拉取设备配置失败: ${(err as Error).message}`);
      return undefined;
    }
  }

  /**
   * 生成阈值调整建议。
   * 统计近期同类告警被标记误报的次数，交给分析引擎判断是否建议放宽。
   */
  async buildThresholdSuggestion(alertType: string): Promise<ThresholdSuggestion | undefined> {
    const alerts: Alert[] = await this.loadAlerts('', '', 30);
    const falseAlarms: number = alerts.filter((a: Alert) =>
      a.alertType === alertType && a.status === AlertStatus.FALSE_ALARM).length;

    const config = await this.cloud.fetchDeviceConfig('');
    let current: number = 60;
    if (alertType === AlertType.NO_ACTIVITY) {
      current = config.noActivityMinutesNight;
    } else if (alertType === AlertType.TEMP_HUMIDITY_ABNORMAL) {
      current = config.tempMax;
    }
    return ActivityAnalysisService.suggestThreshold(alertType, current, falseAlarms);
  }

  // ==================== 活动报告 ====================

  /** 拉取活动报告 */
  async loadActivityReport(period: string = 'week'): Promise<ActivityReport | undefined> {
    try {
      const resp = await this.cloud.getActivityReport('', period, DateUtil.formatDate(DateUtil.now()));
      this.cacheReport = resp.report;
      return resp.report;
    } catch (err) {
      Logger.warn(CareService.MODULE, `拉取活动报告失败，降级用缓存: ${(err as Error).message}`);
      return this.cacheReport;
    }
  }

  /** 拉取居家安全日志 */
  async loadSafetyLogs(days: number = 30): Promise<SafetyLogEntry[]> {
    try {
      const page = await this.cloud.getSafetyLogs({
        deviceId: '',
        from: DateUtil.daysAgo(days),
        to: DateUtil.now(),
        page: 1,
        pageSize: 100
      });
      return page.list;
    } catch (err) {
      Logger.warn(CareService.MODULE, `拉取安全日志失败: ${(err as Error).message}`);
      return [];
    }
  }

  // ==================== 家庭成员 ====================

  async loadMembers(): Promise<FamilyMember[]> {
    try {
      const resp = await this.cloud.getFamilyMembers(CareService.FAMILY_ID);
      this.cacheMembers = resp.members;
      return resp.members;
    } catch (err) {
      Logger.warn(CareService.MODULE, `拉取家庭成员失败: ${(err as Error).message}`);
      return this.cacheMembers;
    }
  }

  /**
   * 被监护老人的姓名（同步读取）。
   *
   * 只用于导出报告的落款。成员列表尚未拉到时退回 null，
   * 调用方自行决定兜底文案 —— 不在服务层塞一个假名字进去。
   */
  boundElderName(): string | undefined {
    if (this.cacheMembers.length === 0) {
      return undefined;
    }
    // 成员表里没有"老人"角色标记，取第一位有姓名的成员作为落款
    const first: FamilyMember | undefined = this.cacheMembers[0];
    if (first === undefined || first.name.length === 0) {
      return undefined;
    }
    return first.name;
  }

  // ==================== 推送 ====================

  /** 订阅告警推送 */
  subscribeAlerts(listener: PushListener): void {
    this.cloud.subscribeAlerts(listener);
  }

  /** 取消订阅 */
  unsubscribeAlerts(): void {
    this.cloud.unsubscribeAlerts();
  }

  /** 构造告警推送的展示文案（供通知栏使用） */
  static buildPushTitle(msg: PushMessage): string {
    if (msg.level === 'P0') {
      return `紧急：${msg.alertTypeName}`;
    }
    if (msg.level === 'P1') {
      return `预警：${msg.alertTypeName}`;
    }
    return `提醒：${msg.alertTypeName}`;
  }
}
