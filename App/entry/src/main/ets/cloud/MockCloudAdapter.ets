import { CloudApi } from './CloudApi';
import {
  RegisterDeviceReq, RegisterDeviceResp, HeartbeatReq, HeartbeatResp,
  UploadReadingsReq, UploadReadingsResp, UploadAlertReq, UploadAlertResp,
  DeviceListItem, DeviceStatusResp, ReadingsQuery, ReadingsResp,
  AlertQuery, AlertDetailResp, ConfirmAlertResp, HandleAlertReq, HandleAlertResp,
  ActivityReportResp, ActivityDistributionResp, SafetyLogQuery,
  FamilyMemberListResp, PushListener, PushMessage, PageData, ReadingsPoint
} from './CloudTypes';
import { Device, Sensor, DeviceConfig } from '../model/Device';
import { Alert, AlertHandle, AlertTimelineNode, SafetyLogEntry } from '../model/Alert';
import { ActivityReport, ActivityDaily, HeatmapCell, TrendPoint } from '../model/ActivityRecord';
import { FamilyMember } from '../model/FamilyMember';
import {
  SensorType, AlertType, AlertLevel, AlertStatus, HandleResult,
  MemberRole, AppConstants
} from '../common/constants/AppConstants';
import { DateUtil, UuidUtil } from '../common/utils/DateUtil';
import { Logger } from '../common/utils/Logger';
import { ActivityAnalysisService, TrendResult } from '../service/ActivityAnalysisService';
import { ActivityBaseline } from '../model/ActivityRecord';

/**
 * Mock 云端实现。
 *
 * 用途：学长服务器接口文档未到位前，让 App 能够完整跑通全部页面与交互。
 * 特点：
 *   1. 数据确定性生成（固定种子），刷新后数据不跳变，便于演示与调试；
 *   2. 生成的数据符合真实老人的作息规律（6:30 起床、午休、21:30 入睡），
 *      使活动报告、热力图、趋势分析看起来真实；
 *   3. 内置告警历史与处置记录，事件闭环可完整走通。
 *
 * 切换到真实云端时，本类整体替换为 SeniorCloudAdapter，业务层无需改动。
 */
export class MockCloudAdapter implements CloudApi {
  private static readonly MODULE: string = 'MockCloudAdapter';
  private static readonly DEVICE_ID: string = 'dev_mock_0001';
  private static readonly FAMILY_ID: string = 'fam_mock_0001';

  private listener: PushListener | undefined = undefined;
  private device: Device = new Device();
  private sensors: Sensor[] = [];
  /** 演示场景：normal / warning / danger，仅供 Mock 与答辩演示使用 */
  private scenario: string = 'normal';
  private alerts: Alert[] = [];
  private activityDaily: ActivityDaily[] = [];
  private members: FamilyMember[] = [];
  private pushTimer: number = -1;

  constructor() {
    this.seedDevice();
    this.seedSensors();
    this.seedActivity();
    this.seedAlerts();
    this.seedMembers();
  }

  adapterName(): string {
    return 'Mock（本地模拟数据）';
  }

  // ==================== 数据初始化 ====================

  private seedDevice(): void {
    this.device.deviceId = MockCloudAdapter.DEVICE_ID;
    this.device.deviceSn = 'SY-2026-000123';
    this.device.deviceName = '客厅监护主机';
    this.device.model = 'OpenHarmony-DevBoard';
    this.device.firmwareVersion = '1.0.0';
    this.device.online = true;
    this.device.lastHeartbeat = DateUtil.now() - 12000;
    this.device.battery = 87;
    this.device.signal = 4;
    this.device.networkType = 'wifi';
    // 心率由监护主机上的毫米波雷达/PPG 采集，随心跳一并上报
    this.device.heartRate = 76;
    this.device.heartRateAt = DateUtil.now() - 18000;
    // 血氧 / 体温 / 步数同源采集，与心率同一批上报。
    // 体温刻意给 37.7℃：落在「关注」区间，演示时能同时看到绿色和橙色两种状态，
    // 比清一色"正常"更能说明这套三色体系是真的在判定，而不是写死的。
    this.device.spo2 = 95;
    this.device.bodyTemp = 37.7;
    this.device.steps = 1268;
    this.device.vitalsAt = DateUtil.now() - 18000;
    this.device.capabilities = [
      SensorType.PIR, SensorType.DOOR, SensorType.TEMP_HUMIDITY,
      SensorType.SOS_BUTTON, SensorType.SMOKE, SensorType.GAS,
      SensorType.HEART_RATE
    ];
  }

  private seedSensors(): void {
    const now: number = DateUtil.now();
    this.sensors = [];

    const pir: Sensor = new Sensor();
    pir.sensorId = 's_pir_01';
    pir.deviceId = MockCloudAdapter.DEVICE_ID;
    pir.sensorType = SensorType.PIR;
    pir.name = '人体活动';
    pir.value = 0;
    pir.lastTriggered = now - 3 * 60000;
    pir.todayCount = 42;
    pir.displayValue = `最后活动：${DateUtil.relative(pir.lastTriggered)}`;
    pir.normal = true;
    pir.updatedAt = now;
    this.sensors.push(pir);

    const door: Sensor = new Sensor();
    door.sensorId = 's_door_01';
    door.deviceId = MockCloudAdapter.DEVICE_ID;
    door.sensorType = SensorType.DOOR;
    door.name = '门窗状态';
    door.value = 0;
    door.lastChanged = now - 5 * 3600000;
    door.displayValue = '开合状态：已关闭';
    door.normal = true;
    door.updatedAt = now;
    this.sensors.push(door);

    const th: Sensor = new Sensor();
    th.sensorId = 's_th_01';
    th.deviceId = MockCloudAdapter.DEVICE_ID;
    th.sensorType = SensorType.TEMP_HUMIDITY;
    th.name = '温湿度';
    th.value = 24.5;
    th.displayValue = '温湿度：24.5℃ / 58%';
    th.normal = true;
    th.updatedAt = now;
    this.sensors.push(th);

    const smoke: Sensor = new Sensor();
    smoke.sensorId = 's_smoke_01';
    smoke.deviceId = MockCloudAdapter.DEVICE_ID;
    smoke.sensorType = SensorType.SMOKE;
    smoke.name = '烟雾监测';
    smoke.value = 12;
    smoke.displayValue = '烟雾浓度：正常';
    smoke.normal = true;
    smoke.updatedAt = now;
    this.sensors.push(smoke);

    const gas: Sensor = new Sensor();
    gas.sensorId = 's_gas_01';
    gas.deviceId = MockCloudAdapter.DEVICE_ID;
    gas.sensorType = SensorType.GAS;
    gas.name = '燃气监测';
    gas.value = 45;
    gas.displayValue = '气体浓度：正常';
    gas.normal = true;
    gas.updatedAt = now;
    this.sensors.push(gas);

    const sos: Sensor = new Sensor();
    sos.sensorId = 's_sos_01';
    sos.deviceId = MockCloudAdapter.DEVICE_ID;
    sos.sensorType = SensorType.SOS_BUTTON;
    sos.name = '紧急求助按钮';
    sos.value = 0;
    // 第二行统一走「标签：数值」，在线与否由右上角圆点表达
    sos.displayValue = '电量：92%';
    sos.normal = true;
    sos.online = true;
    sos.battery = 92;
    sos.updatedAt = now;
    this.sensors.push(sos);

    // 应用当前演示场景（默认 normal，即全部绿点）
    this.applyScenario();
  }

  /**
   * 切换演示场景。
   *
   * 用途：答辩现场动态演示整套卡片状态体系 ——
   *   normal   全部绿点
   *   warning  门窗长时间打开（普通监测类异常 → 黄）
   *   danger   燃气浓度超阈值（高危类异常 → 红）
   *   offline  主机与全部传感器断连（圆点转灰，卡片给【设备离线】）
   *
   * 四个场景串起来正好是一条完整的讲解线索：
   * 正常 → 普通异常 → 高危告警 → 断连，评委能一次看全三色加灰色的全部形态。
   * 只影响 Mock 数据。真实云端不走这条路径，接口层面也不暴露。
   */
  setDemoScenario(scenario: string): void {
    this.scenario = scenario;
    this.applyScenario();
  }

  getDemoScenario(): string {
    return this.scenario;
  }

  /**
   * 把场景落到设备与各传感器上。
   *
   * 每次先全量复位（包括 device.online），避免场景切换后状态残留 ——
   * 比如从 offline 切回 normal 时，若忘记恢复主机在线，
   * 首页会一直停在"离线 + 灰点"的状态上，演示时很难解释。
   */
  private applyScenario(): void {
    const now: number = DateUtil.now();
    this.device.online = true;
    for (const s of this.sensors) {
      s.normal = true;
      s.level = '';
      s.online = true;
    }

    if (this.scenario === 'warning') {
      // 门窗长时间敞开：普通监测类，只升级到黄色待关注
      const door: Sensor | undefined =
        this.sensors.find((s: Sensor) => s.sensorType === SensorType.DOOR);
      if (door !== undefined) {
        door.normal = false;
        door.value = 1;
        door.lastChanged = now - 42 * 60000;
        door.displayValue = '开合状态：已打开 42 分钟';
      }
    } else if (this.scenario === 'danger') {
      // 燃气泄漏 + 烟雾超阈值：高危类，直接进红色告警
      const gas: Sensor | undefined =
        this.sensors.find((s: Sensor) => s.sensorType === SensorType.GAS);
      if (gas !== undefined) {
        gas.normal = false;
        gas.value = 486;
        gas.displayValue = '气体浓度：超阈值 486ppm';
      }
      const smoke: Sensor | undefined =
        this.sensors.find((s: Sensor) => s.sensorType === SensorType.SMOKE);
      if (smoke !== undefined) {
        smoke.normal = false;
        smoke.value = 372;
        smoke.displayValue = '烟雾浓度：超阈值 372ppm';
      }
    } else if (this.scenario === 'offline') {
      // 主机断连：设备卡转"离线"，心率回落为 -- 次/分钟，
      // 六张卡片圆点全部转灰、第二行给【设备离线】。
      // 断连时缓存里的值已不可信，所以 Sensors/读数值一律不再展示。
      this.device.online = false;
      const stale: number = now - 18 * 60000;
      this.device.lastHeartbeat = stale;
      for (const s of this.sensors) {
        s.online = false;
        s.updatedAt = stale;
      }
    }
  }

  /**
   * 生成 30 天的活动数据。
   *
   * 关键：按真实老人的作息分布生成，而不是均匀随机。
   * 一天的活动集中在：6:30-11:00（上午）、14:00-17:00（下午）、19:00-21:30（晚间），
   * 12:00-13:30 午休、22:00-6:00 睡眠时段活动极少。
   *
   * 同时刻意让最近 3 天活动量略有下降，这样"规律变化提示"能被触发，
   * 演示时能看到完整效果。
   */
  private seedActivity(): void {
    const hoursWeight: number[] = [
      0.1, 0.0, 0.0, 0.0, 0.0, 0.3,   // 0-5 睡眠
      1.6, 2.4, 2.6, 2.2, 2.0, 1.8,   // 6-11 上午
      0.5, 0.6, 1.8, 2.0, 1.9, 1.7,   // 12-17 午休 + 下午
      1.9, 2.1, 1.6, 0.9, 0.4, 0.2    // 18-23 晚间 + 入睡
    ];

    this.activityDaily = [];
    const today: number = DateUtil.now();

    for (let d = 29; d >= 0; d--) {
      const dayTs: number = DateUtil.startOfDay(today - d * 86400000);
      const daily: ActivityDaily = new ActivityDaily();
      daily.deviceId = MockCloudAdapter.DEVICE_ID;
      daily.date = DateUtil.formatDate(dayTs);
      daily.dayStart = dayTs;

      // 确定性随机：用日期派生种子，保证每次生成结果一致
      const daySeed: number = (dayTs / 86400000) % 97;
      // 最近 3 天活动量下降，用于触发"规律变化提示"
      const declineFactor: number = d <= 2 ? 0.78 : 1.0;
      const baseFactor: number = 0.85 + (daySeed % 30) / 100;

      let total: number = 0;
      let activeHours: number = 0;
      let nightCount: number = 0;
      let firstActivity: number = 0;
      let lastActivity: number = 0;

      for (let h = 0; h < 24; h++) {
        const w: number = hoursWeight[h] * baseFactor * declineFactor;
        const count: number = Math.max(0, Math.round(w + ((daySeed * (h + 7)) % 3) - 1));
        if (count > 0) {
          total += count;
          activeHours++;
          const ts: number = dayTs + h * 3600000 + (daySeed % 50) * 60000;
          if (firstActivity === 0) {
            firstActivity = ts;
          }
          lastActivity = ts;
          if (h >= 22 || h < 6) {
            nightCount += count;
          }
        }
      }

      daily.totalCount = total;
      daily.activeHours = activeHours;
      daily.firstActivity = firstActivity;
      daily.lastActivity = lastActivity;
      daily.nightCount = nightCount;
      this.activityDaily.push(daily);
    }
    Logger.info(MockCloudAdapter.MODULE, `已生成 ${this.activityDaily.length} 天活动数据`);
  }

  /** 生成告警历史，含已处置记录，便于演示事件闭环 */
  private seedAlerts(): void {
    const now: number = DateUtil.now();
    this.alerts = [];

    // 已处置的 P1 告警（两天前）
    const a1: Alert = MockCloudAdapter.buildAlert(
      AlertType.NO_ACTIVITY, AlertLevel.P1, now - 2 * 86400000 - 3600000, 65, 60,
      '连续 65 分钟未检测到人体活动，超出该老人日常活动基线阈值', AlertStatus.HANDLED);
    const h1: AlertHandle = new AlertHandle();
    h1.handlerName = '子女·张';
    h1.handlerRole = MemberRole.CHILD;
    h1.result = HandleResult.GRID_WORKER;
    h1.resultName = HandleResult.labelOf(HandleResult.GRID_WORKER);
    h1.note = '网格员反馈老人一切正常，可能在午睡';
    h1.handledAt = a1.timestamp + 20 * 60000;
    a1.handle = h1;
    this.alerts.push(a1);

    // 已标记误报的 P2 告警（五天前）
    const a2: Alert = MockCloudAdapter.buildAlert(
      AlertType.TEMP_HUMIDITY_ABNORMAL, AlertLevel.P2, now - 5 * 86400000 - 7200000, 33.2, 32,
      '室内温度 33.2℃ 持续 20 分钟，超出老人舒适区间', AlertStatus.HANDLED);
    const h2: AlertHandle = new AlertHandle();
    h2.handlerName = '子女·张';
    h2.handlerRole = MemberRole.CHILD;
    h2.result = HandleResult.FALSE_ALARM;
    h2.resultName = HandleResult.labelOf(HandleResult.FALSE_ALARM);
    h2.note = '老人开了电暖器，属正常情况';
    h2.handledAt = a2.timestamp + 35 * 60000;
    h2.thresholdAdjusted = true;
    a2.handle = h2;
    this.alerts.push(a2);

    // 一条待确认的 P1 告警（昨天）
    const a3: Alert = MockCloudAdapter.buildAlert(
      AlertType.NO_ACTIVITY, AlertLevel.P1, now - 86400000 - 5400000, 92, 60,
      '连续 92 分钟未检测到人体活动，超出该老人日常活动基线阈值', AlertStatus.HANDLED);
    const h3: AlertHandle = new AlertHandle();
    h3.handlerName = '子女·张';
    h3.handlerRole = MemberRole.CHILD;
    h3.result = HandleResult.ELDER_NORMAL;
    h3.resultName = HandleResult.labelOf(HandleResult.ELDER_NORMAL);
    h3.note = '电话确认，老人在楼下散步';
    h3.handledAt = a3.timestamp + 12 * 60000;
    a3.handle = h3;
    this.alerts.push(a3);

    this.alerts.sort((a: Alert, b: Alert) => b.timestamp - a.timestamp);
  }

  private static buildAlert(alertType: string, level: string, timestamp: number,
    triggerValue: number, threshold: number, description: string, status: string): Alert {
    const a: Alert = new Alert();
    a.alertId = `alert_${Math.floor(timestamp / 1000)}_${alertType}`;
    a.serverAlertId = `sa_${Math.floor(timestamp / 1000)}`;
    a.deviceId = MockCloudAdapter.DEVICE_ID;
    a.deviceName = '客厅监护主机';
    a.alertType = alertType;
    a.alertTypeName = AlertType.labelOf(alertType);
    a.level = level;
    a.timestamp = timestamp;
    a.triggerValue = triggerValue;
    a.threshold = threshold;
    a.description = description;
    a.status = status;
    a.notifiedRoles = level === AlertLevel.P0
      ? [MemberRole.CHILD, MemberRole.GRID_WORKER, MemberRole.PROPERTY]
      : [MemberRole.CHILD];
    return a;
  }

  private seedMembers(): void {
    this.members = [];

    const child: FamilyMember = new FamilyMember();
    child.userId = 'u_001';
    child.name = '子女·张';
    child.role = MemberRole.CHILD;
    child.roleName = MemberRole.labelOf(MemberRole.CHILD);
    child.phone = '138****1234';
    child.canViewActivity = true;
    child.canHandle = true;
    this.members.push(child);

    const grid: FamilyMember = new FamilyMember();
    grid.userId = 'u_002';
    grid.name = '网格员·李';
    grid.role = MemberRole.GRID_WORKER;
    grid.roleName = MemberRole.labelOf(MemberRole.GRID_WORKER);
    grid.phone = '139****5678';
    grid.canViewActivity = false;
    grid.canHandle = true;
    this.members.push(grid);

    const prop: FamilyMember = new FamilyMember();
    prop.userId = 'u_003';
    prop.name = '物业值班';
    prop.role = MemberRole.PROPERTY;
    prop.roleName = MemberRole.labelOf(MemberRole.PROPERTY);
    prop.phone = '0371-****000';
    prop.canViewActivity = false;
    prop.canHandle = true;
    this.members.push(prop);
  }

  // ==================== 设备端接口 ====================

  async registerDevice(req: RegisterDeviceReq): Promise<RegisterDeviceResp> {
    Logger.info(MockCloudAdapter.MODULE, `[Mock] 设备注册 ${req.deviceSn}`);
    const resp: RegisterDeviceResp = {
      deviceId: MockCloudAdapter.DEVICE_ID,
      deviceToken: 'dt_mock_token',
      familyId: MockCloudAdapter.FAMILY_ID,
      config: new DeviceConfig()
    };
    return resp;
  }

  async heartbeat(deviceId: string, req: HeartbeatReq): Promise<HeartbeatResp> {
    this.device.lastHeartbeat = req.timestamp;
    this.device.battery = req.battery;
    this.device.signal = req.signal;
    this.device.online = true;
    // 心率随心跳上报。仅在带有效值时更新；缺省则保留上一次读数，
    // 由新鲜度窗口（HeartRateConst.STALE_MS）自然过期，
    // 界面随后自动回落为 "-- 次/分钟"，不会拿旧值冒充当前值。
    if (req.heartRate !== undefined && req.heartRate > 0) {
      this.device.heartRate = req.heartRate;
      this.device.heartRateAt = req.timestamp;
    }
    const resp: HeartbeatResp = {
      serverTime: DateUtil.now(),
      pendingCommands: [],
      configChanged: false
    };
    return resp;
  }

  async uploadReadings(deviceId: string, req: UploadReadingsReq): Promise<UploadReadingsResp> {
    const resp: UploadReadingsResp = { accepted: req.readings.length, rejected: 0 };
    return resp;
  }

  async uploadAlert(deviceId: string, req: UploadAlertReq): Promise<UploadAlertResp> {
    Logger.info(MockCloudAdapter.MODULE, `[Mock] 收到告警上报 ${req.alertType} ${req.level}`);
    const resp: UploadAlertResp = {
      alertId: req.alertId,
      serverAlertId: `sa_${DateUtil.now()}`,
      notified: req.level === AlertLevel.P0
        ? [MemberRole.CHILD, MemberRole.GRID_WORKER, MemberRole.PROPERTY]
        : [MemberRole.CHILD],
      deduped: false
    };
    return resp;
  }

  async fetchDeviceConfig(deviceId: string): Promise<DeviceConfig> {
    const cfg: DeviceConfig = new DeviceConfig();
    // 老人联系电话。真实环境由云端下发、本地配置维护；
    // 这里给演示值，好让预警列表的「联系老人」在答辩时真能跳到拨号盘。
    cfg.elderPhone = '13800001234';
    return cfg;
  }

  // ==================== App 端接口 ====================

  async getDeviceList(familyId: string): Promise<DeviceListItem[]> {
    const item: DeviceListItem = {
      device: this.device,
      sensors: this.sensors,
      activeAlerts: this.alerts.filter((a: Alert) => a.isPending()).length
    };
    return [item];
  }

  async getDeviceStatus(deviceId: string): Promise<DeviceStatusResp> {
    const sos: Sensor | undefined = this.sensors.find((s: Sensor) => s.sensorType === SensorType.SOS_BUTTON);
    const resp: DeviceStatusResp = {
      device: this.device,
      sensors: this.sensors,
      sosButtonOnline: sos !== undefined ? sos.online : false,
      sosButtonBattery: sos !== undefined ? sos.battery : 0,
      recentAlerts: this.alerts.slice(0, 3)
    };
    return resp;
  }

  async getReadings(query: ReadingsQuery): Promise<ReadingsResp> {
    // Mock 按聚合粒度生成趋势数据，模拟服务端聚合：
    // 日聚合给一天一条（30 天只有 30 个点），否则一小时一条。
    const points: ReadingsPoint[] = [];
    const stepMs: number = query.interval === '1d' ? 86400000 : 3600000;
    for (let t = query.from; t <= query.to; t += stepMs) {
      points.push({
        timestamp: t,
        value: this.readingValueOf(query.sensorType, t),
        extra: {}
      });
    }
    const resp: ReadingsResp = {
      sensorType: query.sensorType,
      interval: query.interval,
      points: points
    };
    return resp;
  }

  /**
   * 按传感器类型生成符合物理常识的历史读数。
   *
   * 用确定性函数（正弦 + 取模）而不是随机数：每次刷新曲线完全一致，
   * 演示时不会出现"刚讲完这张图，数据就变了"的尴尬。
   */
  private readingValueOf(sensorType: string, t: number): number {
    const h: number = DateUtil.hourOf(t);
    const day: number = Math.floor(t / 86400000);
    let v: number = 0;
    switch (sensorType) {
      case SensorType.TEMP_HUMIDITY:
        // 温度日变化：凌晨最低，午后最高
        v = 22 + 3.5 * Math.sin((h - 8) / 24 * 2 * Math.PI);
        break;
      case SensorType.PIR:
        // 白天有活动、夜间几乎为零
        v = (h >= 6 && h <= 21) ? 2 + Math.abs(Math.sin(h)) * 3 : 0;
        break;
      case SensorType.DOOR:
        // 一天开关若干次
        v = (h === 7 || h === 9 || h === 12 || h === 17 || h === 20) ? 1 : 0;
        break;
      case SensorType.SMOKE:
        // 常态在低位小幅波动，远低于阈值
        v = 8 + Math.abs(Math.sin(day * 0.7 + h * 0.3)) * 6;
        break;
      case SensorType.GAS:
        // 常态本底浓度
        v = 35 + Math.abs(Math.sin(day * 0.5 + h * 0.2)) * 20;
        break;
      case SensorType.HEART_RATE:
        v = 72 + 6 * Math.sin((h - 6) / 24 * 2 * Math.PI);
        break;
      default:
        v = 0;
    }
    return Math.round(v * 10) / 10;
  }

  async getAlerts(query: AlertQuery): Promise<PageData<Alert>> {
    let list: Alert[] = this.alerts.slice();
    if (query.status.length > 0) {
      list = list.filter((a: Alert) => a.status === query.status);
    }
    if (query.level.length > 0) {
      list = list.filter((a: Alert) => a.level === query.level);
    }
    if (query.from > 0) {
      list = list.filter((a: Alert) => a.timestamp >= query.from);
    }
    if (query.to > 0) {
      list = list.filter((a: Alert) => a.timestamp <= query.to);
    }
    list.sort((a: Alert, b: Alert) => b.timestamp - a.timestamp);

    const page: number = query.page > 0 ? query.page : 1;
    const size: number = query.pageSize > 0 ? query.pageSize : 20;
    const start: number = (page - 1) * size;
    const data: PageData<Alert> = {
      list: list.slice(start, start + size),
      total: list.length,
      page: page,
      pageSize: size
    };
    return data;
  }

  async getAlertDetail(alertId: string): Promise<AlertDetailResp> {
    const alert: Alert | undefined = this.alerts.find((a: Alert) => a.alertId === alertId);
    if (alert === undefined) {
      throw new Error(`未找到告警 ${alertId}`);
    }

    const timeline: AlertTimelineNode[] = [];
    timeline.push(MockCloudAdapter.node(alert.timestamp, 'triggered',
      `设备检测到「${alert.alertTypeName}」并触发本地声光报警`));
    timeline.push(MockCloudAdapter.node(alert.timestamp + 500, 'uploaded', '告警已上报云端'));
    for (const role of alert.notifiedRoles) {
      timeline.push(MockCloudAdapter.node(alert.timestamp + 800, 'notified',
        `已推送至${MemberRole.labelOf(role)}`));
    }
    if (alert.handle !== undefined) {
      timeline.push(MockCloudAdapter.node(alert.handle.handledAt - 600000, 'confirmed',
        `${alert.handle.handlerName}已确认告警`));
      timeline.push(MockCloudAdapter.node(alert.handle.handledAt, 'handled',
        `${alert.handle.handlerName}填写处置结果：${alert.handle.resultName}`));
    }

    const resp: AlertDetailResp = { alert: alert, timeline: timeline };
    return resp;
  }

  private static node(time: number, event: string, text: string): AlertTimelineNode {
    const n: AlertTimelineNode = new AlertTimelineNode();
    n.time = time;
    n.event = event;
    n.text = text;
    return n;
  }

  async confirmAlert(alertId: string, remark: string): Promise<ConfirmAlertResp> {
    const alert: Alert | undefined = this.alerts.find((a: Alert) => a.alertId === alertId);
    if (alert !== undefined) {
      alert.status = AlertStatus.CONFIRMED;
    }
    const resp: ConfirmAlertResp = {
      alertId: alertId,
      status: AlertStatus.CONFIRMED,
      confirmedAt: DateUtil.now()
    };
    return resp;
  }

  async handleAlert(alertId: string, req: HandleAlertReq): Promise<HandleAlertResp> {
    const alert: Alert | undefined = this.alerts.find((a: Alert) => a.alertId === alertId);
    if (alert !== undefined) {
      alert.status = AlertStatus.HANDLED;
      const h: AlertHandle = new AlertHandle();
      h.handlerName = '子女·张';
      h.handlerRole = MemberRole.CHILD;
      h.result = req.result;
      h.resultName = HandleResult.labelOf(req.result);
      h.note = req.note;
      h.handledAt = DateUtil.now();
      h.thresholdAdjusted = req.adjustThresholdKey.length > 0;
      alert.handle = h;
    }
    const resp: HandleAlertResp = {
      alertId: alertId,
      status: AlertStatus.HANDLED,
      handledAt: DateUtil.now(),
      thresholdAdjusted: req.adjustThresholdKey.length > 0
    };
    return resp;
  }

  /**
   * 删除告警（Mock 端从内存数组移除）。
   * 与 IoTDA 适配器行为一致：只删 App 侧记录。
   */
  async deleteAlert(alertId: string): Promise<boolean> {
    const before: number = this.alerts.length;
    this.alerts = this.alerts.filter((a: Alert) => a.alertId !== alertId);
    return this.alerts.length < before;
  }

  /** 批量标记全部待处置为已处置（内存数组操作） */
  async markAllPendingHandled(): Promise<number> {
    const now: number = DateUtil.now();
    let count: number = 0;
    for (const a of this.alerts) {
      if (a.status !== AlertStatus.PENDING) {
        continue;
      }
      a.status = AlertStatus.HANDLED;
      const h: AlertHandle = new AlertHandle();
      h.handlerName = '子女·张';
      h.handlerRole = MemberRole.CHILD;
      h.result = HandleResult.QUICK_MARKED;
      h.resultName = HandleResult.labelOf(HandleResult.QUICK_MARKED);
      h.note = '批量标记已处置';
      h.handledAt = now;
      h.thresholdAdjusted = false;
      a.handle = h;
      count = count + 1;
    }
    return count;
  }

  /** 清空全部待处置（内存数组操作） */
  async clearPendingAlerts(): Promise<number> {
    const before: number = this.alerts.length;
    this.alerts = this.alerts.filter((a: Alert) => a.status !== AlertStatus.PENDING);
    return before - this.alerts.length;
  }

  /** 演示用：注入 count 条待处置告警 */
  async injectDemoAlerts(count: number): Promise<number> {
    if (count <= 0) {
      return 0;
    }
    const now: number = DateUtil.now();
    const types: string[] = [AlertType.SMOKE_DETECTED, AlertType.GAS_LEAK, AlertType.NO_ACTIVITY,
      AlertType.TEMP_HUMIDITY_ABNORMAL, AlertType.SOS_PRESSED];
    let added: number = 0;
    for (let k: number = count - 1; k >= 0; k--) {
      const type: string = types[(Math.floor(now / 1000) + k) % types.length];
      const alert: Alert = new Alert();
      alert.alertId = `demo_${type}_${now}_${k}`;
      alert.deviceId = MockCloudAdapter.DEVICE_ID;
      alert.deviceName = '客厅监护主机';
      alert.alertType = type;
      alert.alertTypeName = AlertType.labelOf(type);
      alert.level = AlertType.defaultLevelOf(type);
      alert.timestamp = now - k * 30000;
      alert.triggerValue = 372;
      alert.threshold = 300;
      alert.description = `${AlertType.labelOf(type)}（演示）`;
      alert.status = AlertStatus.PENDING;
      alert.notifiedRoles = [MemberRole.CHILD];
      this.alerts.unshift(alert);
      added = added + 1;
    }
    return added;
  }

  /**
   * 生成活动报告。
   * Mock 端直接做聚合计算，真实环境由服务端返回。
   * 聚合逻辑与云端保持一致，因此本地算出的结论可直接用于演示。
   */
  async getActivityReport(deviceId: string, period: string, date: string): Promise<ActivityReportResp> {
    const days: number = period === 'month' ? 30 : (period === 'week' ? 7 : 1);
    const slice: ActivityDaily[] = this.activityDaily.slice(this.activityDaily.length - days);

    const report: ActivityReport = new ActivityReport();
    report.period = period;
    report.from = slice.length > 0 ? slice[0].dayStart : 0;
    report.to = DateUtil.now();

    // 汇总
    let total: number = 0;
    let nightTotal: number = 0;
    let firstTs: number = 0;
    let lastTs: number = 0;
    const hourly: number[] = new Array<number>(24).fill(0);

    for (const d of slice) {
      total += d.totalCount;
      nightTotal += d.nightCount;
      if (firstTs === 0 || (d.firstActivity > 0 && d.firstActivity < firstTs)) {
        firstTs = d.firstActivity;
      }
      if (d.lastActivity > lastTs) {
        lastTs = d.lastActivity;
      }
      report.daily.push({ date: d.date, count: d.totalCount } as TrendPoint);
      // 按小时拆分（Mock 用日均分布近似）
      const avgPerHour: number = d.activeHours > 0 ? d.totalCount / d.activeHours : 0;
      for (let h = 0; h < 24; h++) {
        hourly[h] += avgPerHour * MockCloudAdapter.hourWeight(h);
      }
    }

    report.totalCount = total;
    report.avgDailyCount = slice.length > 0 ? Math.round(total / slice.length * 10) / 10 : 0;
    report.nightActivityCount = nightTotal;
    report.firstActivityTime = DateUtil.formatTime(firstTs);
    report.lastActivityTime = DateUtil.formatTime(lastTs);
    report.activeHours = hourly.filter((v: number) => v > 0.5).length;
    report.hourlyDistribution = hourly.map((v: number) => Math.round(v));

    // 热力图
    for (const d of slice) {
      const avgPerHour: number = d.activeHours > 0 ? d.totalCount / d.activeHours : 0;
      for (let h = 0; h < 24; h++) {
        const c: number = Math.round(avgPerHour * MockCloudAdapter.hourWeight(h));
        if (c > 0) {
          const cell: HeatmapCell = new HeatmapCell();
          cell.date = d.date;
          cell.hour = h;
          cell.count = c;
          report.heatmap.push(cell);
        }
      }
    }
    report.maxHeatmapCount = report.heatmap.reduce((m: number, c: HeatmapCell) => Math.max(m, c.count), 1);

    // 趋势：与前一周期对比
    const prevSlice: ActivityDaily[] = this.activityDaily.slice(
      Math.max(0, this.activityDaily.length - days * 2), this.activityDaily.length - days);
    const trend: TrendResult = ActivityAnalysisService.computeTrend(slice, prevSlice);

    report.compareWith = period === 'month' ? '上月' : (period === 'week' ? '上周' : '昨日');
    report.changePercent = trend.changePercent;
    report.trendDirection = trend.direction;

    // 个人基线：与离线兜底路径共用同一套算法
    const baselineSlice: ActivityDaily[] = this.activityDaily.slice(
      Math.max(0, this.activityDaily.length - AppConstants.BASELINE_WINDOW_DAYS - days),
      this.activityDaily.length - days);
    const baseline: ActivityBaseline = ActivityAnalysisService.computeBaseline(baselineSlice);
    report.baselineAvg = baseline.avgDailyCount;
    report.baselineStdDev = baseline.stdDev;
    report.deviation = ActivityAnalysisService.deviationFromBaseline(trend.currentAvg, baseline);
    report.baselineAbnormal = Math.abs(report.deviation) >= AppConstants.BASELINE_DEVIATION_SIGMA;

    // 自然语言判断 —— 报告的灵魂。Mock 不再自带一套措辞，
    // 否则云端走线上、演示走本地，同一份数据能说出两种结论。
    report.insight = ActivityAnalysisService.buildInsight(report, baseline);

    const resp: ActivityReportResp = { report: report };
    return resp;
  }

  /** 24 小时活动权重，与 seedActivity 保持一致 */
  private static hourWeight(h: number): number {
    const w: number[] = [
      0.1, 0.0, 0.0, 0.0, 0.0, 0.3,
      1.6, 2.4, 2.6, 2.2, 2.0, 1.8,
      0.5, 0.6, 1.8, 2.0, 1.9, 1.7,
      1.9, 2.1, 1.6, 0.9, 0.4, 0.2
    ];
    return w[h];
  }

  async getActivityDistribution(deviceId: string, from: number, to: number): Promise<ActivityDistributionResp> {
    const resp: ActivityDistributionResp = {
      maxCount: 0,
      cells: []
    };
    for (const d of this.activityDaily) {
      if (d.dayStart < from || d.dayStart > to) {
        continue;
      }
      const avgPerHour: number = d.activeHours > 0 ? d.totalCount / d.activeHours : 0;
      for (let h = 0; h < 24; h++) {
        const c: number = Math.round(avgPerHour * MockCloudAdapter.hourWeight(h));
        if (c > 0) {
          const cell: HeatmapCell = new HeatmapCell();
          cell.date = d.date;
          cell.hour = h;
          cell.count = c;
          resp.cells.push(cell);
          resp.maxCount = Math.max(resp.maxCount, c);
        }
      }
    }
    return resp;
  }

  async getSafetyLogs(query: SafetyLogQuery): Promise<PageData<SafetyLogEntry>> {
    const list: SafetyLogEntry[] = [];
    for (const a of this.alerts) {
      if (a.handle === undefined) {
        continue;
      }
      const entry: SafetyLogEntry = new SafetyLogEntry();
      entry.logId = `log_${a.alertId}`;
      entry.alertId = a.alertId;
      entry.date = DateUtil.formatDate(a.timestamp);
      entry.level = a.level;
      entry.alertTypeName = a.alertTypeName;
      entry.triggeredAt = a.timestamp;
      entry.handledAt = a.handle.handledAt;
      entry.handlerName = a.handle.handlerName;
      entry.resultName = a.handle.resultName;
      entry.note = a.handle.note;
      list.push(entry);
    }
    list.sort((a: SafetyLogEntry, b: SafetyLogEntry) => b.triggeredAt - a.triggeredAt);

    const data: PageData<SafetyLogEntry> = {
      list: list,
      total: list.length,
      page: 1,
      pageSize: 20
    };
    return data;
  }

  async getFamilyMembers(familyId: string): Promise<FamilyMemberListResp> {
    const resp: FamilyMemberListResp = { members: this.members };
    return resp;
  }

  // ==================== 推送 ====================

  /**
   * Mock 推送：订阅后延迟若干秒推一条演示告警，用于演示"实时告警"效果。
   * 真实环境由 WebSocket 长连接或厂商推送承载。
   */
  subscribeAlerts(listener: PushListener): void {
    this.listener = listener;
    Logger.info(MockCloudAdapter.MODULE, '[Mock] 已订阅告警推送');
  }

  unsubscribeAlerts(): void {
    this.listener = undefined;
    if (this.pushTimer >= 0) {
      clearTimeout(this.pushTimer);
      this.pushTimer = -1;
    }
  }

  /** 手动触发一条模拟推送（供演示按钮调用） */
  emitMockPush(): void {
    if (this.listener === undefined) {
      return;
    }
    const msg: PushMessage = {
      type: 'alert',
      alertId: `alert_demo_${DateUtil.now()}`,
      level: AlertLevel.P1,
      alertType: AlertType.NO_ACTIVITY,
      alertTypeName: AlertType.labelOf(AlertType.NO_ACTIVITY),
      deviceId: MockCloudAdapter.DEVICE_ID,
      deviceName: '客厅监护主机',
      timestamp: DateUtil.now(),
      title: '预警：长时间无活动',
      body: '客厅监护主机已连续 68 分钟未检测到人体活动，已触发本地提醒，请及时确认'
    };
    this.listener(msg);
  }
}
