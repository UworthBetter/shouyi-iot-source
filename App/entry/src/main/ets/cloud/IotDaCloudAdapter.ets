import { CloudApi } from './CloudApi';
import { CloudError } from './HttpClient';
import {
  RegisterDeviceReq, RegisterDeviceResp, HeartbeatReq, HeartbeatResp,
  UploadReadingsReq, UploadReadingsResp, UploadAlertReq, UploadAlertResp,
  DeviceListItem, DeviceStatusResp, ReadingsQuery, ReadingsResp, ReadingsPoint,
  AlertQuery, AlertDetailResp, ConfirmAlertResp, HandleAlertReq, HandleAlertResp,
  ActivityReportResp, ActivityDistributionResp, SafetyLogQuery,
  FamilyMemberListResp, PushListener, PushMessage, PageData
} from './CloudTypes';
import { IotDaHttp } from './IotDaHttp';
import { IotDaHistorySample, IotDaLocalStore } from './IotDaLocalStore';
import {
  IotDaDeviceListResp, IotDaDeviceBrief, IotDaDeviceDetail,
  IotDaShadowResp, IotDaShadowValue, IotDaCommandReq, IotDaCommandResp
} from './IotDaTypes';
import { Device, Sensor, DeviceConfig } from '../model/Device';
import { Alert, AlertTimelineNode, SafetyLogEntry } from '../model/Alert';
import { ActivityDaily, ActivityReport, HeatmapCell, TrendPoint } from '../model/ActivityRecord';
import { FamilyMember } from '../model/FamilyMember';
import { CloudCode, SensorType, AlertType } from '../common/constants/AppConstants';
import { Logger } from '../common/utils/Logger';
import { DateUtil } from '../common/utils/DateUtil';

/** 影子里的属性键 —— 与 product_model.json 的 property_key 一一对应 */
class PKey {
  static readonly PIR: string = 'pir';
  static readonly PIR_RK2206: string = 'pirRk2206';
  static readonly PIR_H2821: string = 'pirH2821';
  static readonly ILLUMINATION: string = 'illumination';
  static readonly TEMP: string = 'temperature';
  static readonly HUM: string = 'humidity';
  static readonly GAS: string = 'gas';
  static readonly SOS: string = 'sos';
  static readonly ALARM: string = 'alarmActive';
}

/** 环形缓冲里的一条读数（带传感器类型，便于按类型过滤） */
class BufferedReading {
  timestamp: number = 0;
  value: number = 0;
  /** 仅温湿度传感器用：同一时刻的湿度值 */
  humidity: number = 0;
}

export class IotDaCloudAdapter implements CloudApi {
  private static readonly MODULE: string = 'IotDaCloudAdapter';

  private http: IotDaHttp;
  private projectId: string;
  private deviceId: string;
  private familyId: string;

  /** 本地存储：告警 / 日志 / 活动统计 / 家庭成员 */
  private store: IotDaLocalStore = new IotDaLocalStore();

  /**
   * 注入应用沙箱目录，开启本地持久化。
   * 不调用也能跑，只是告警/日志/活动统计不落盘。
   */
  initStore(filesDir: string): void {
    this.store.init(filesDir);
    this.history = this.store.loadHistory(Date.now());
    this.historyTime = this.history.length > 0 ? this.history[this.history.length - 1].timestamp : 0;
  }

  /** 轮询间隔：IoTDA 没有推送通道给应用侧，只能用轮询影子近似 */
  private static readonly POLL_MS: number = 4000;

  private listener: PushListener | undefined = undefined;
  private timerId: number = -1;
  /** 上一轮已激活的告警类型集合，用逗号拼接，用于去重（避免每 4 秒重复弹） */
  private prevSig: string = '';
  /** 上一轮的 PIR 状态，用于检测上升沿（活动计数） */
  private prevPir: boolean | undefined = undefined;
  private lastSampleAt: number = 0;
  private polling: boolean = false;
  private static readonly MAX_SAMPLE_AGE_MS: number = 30000;
  private static readonly GAS_ALARM_PPM: number = 400;

  private history: IotDaHistorySample[] = [];
  private historyTime: number = 0;
  /** 设备显示名，从最近一次查询里缓存下来，供告警文案使用 */
  private deviceName: string = '居家安全网关';

  constructor(http: IotDaHttp, projectId: string, deviceId: string, familyId: string) {
    this.http = http;
    this.projectId = projectId;
    this.deviceId = deviceId;
    this.familyId = familyId;
  }

  // ==================== 内部：影子 -> 领域模型 ====================

  private async fetchMonitor(deviceId: string): Promise<IotDaShadowValue | undefined> {
    const path: string = `/v5/iot/${this.projectId}/devices/${deviceId}/shadow`;
    const resp: IotDaShadowResp = await this.http.get<IotDaShadowResp>(path);
    return resp.shadow?.find(s => s.service_id === 'monitor')?.reported;
  }

  private reportTime(monitor: IotDaShadowValue | undefined): number {
    const raw: string = monitor?.event_time ?? '';
    const iso: string = /^\d{8}T\d{6}Z$/.test(raw)
      ? `${raw.slice(0, 4)}-${raw.slice(4, 6)}-${raw.slice(6, 11)}:${raw.slice(11, 13)}:${raw.slice(13)}`
      : raw;
    const ts: number = Date.parse(iso);
    return Number.isFinite(ts) ? ts : 0;
  }

  private fresh(timestamp: number): boolean {
    return timestamp > 0 && Math.abs(Date.now() - timestamp) <= IotDaCloudAdapter.MAX_SAMPLE_AGE_MS;
  }

  private buildDevice(brief: IotDaDeviceBrief, sensors: Sensor[], timestamp: number): Device {
    const d: Device = new Device();
    d.deviceId = brief.device_id;
    d.deviceSn = brief.node_id;
    d.deviceName = brief.device_name;
    d.online = brief.status === 'ONLINE';
    d.lastHeartbeat = timestamp;
    d.battery = -1;
    d.networkType = 'wifi';
    d.capabilities = sensors.map((s: Sensor) => s.sensorType);
    return d;
  }

  private sensor(deviceId: string, type: string, name: string, timestamp: number,
                 online: boolean, value: number, display: string, normal: boolean): Sensor {
    const sensor: Sensor = new Sensor();
    sensor.sensorId = `sen_${type}`;
    sensor.deviceId = deviceId;
    sensor.sensorType = type;
    sensor.name = name;
    sensor.value = value;
    sensor.displayValue = online ? display : '暂无实时读数';
    sensor.normal = normal;
    sensor.online = online;
    sensor.battery = -1;
    sensor.updatedAt = timestamp;
    return sensor;
  }

  private buildSensors(monitor: IotDaShadowValue | undefined, deviceId: string,
                       deviceOnline: boolean, timestamp: number): Sensor[] {
    const rep: Record<string, number | string | boolean> = monitor?.properties ?? {};
    const live: boolean = deviceOnline && this.fresh(timestamp);
    const pir = rep[PKey.PIR];
    const sos = rep[PKey.SOS];
    const temp = rep[PKey.TEMP];
    const humidity = rep[PKey.HUM];
    const gas = rep[PKey.GAS];
    const thAvailable: boolean = typeof temp === 'number' && typeof humidity === 'number';
    const activity: Sensor = this.sensor(deviceId, SensorType.PIR, '人体活动（汇总）', timestamp,
      live && typeof pir === 'boolean', pir === true ? 1 : 0, pir === true ? '有人活动' : '无活动', true);
    const today: string = DateUtil.formatDate(Date.now());
    const daily: ActivityDaily | undefined = this.store.loadDaily().find((day: ActivityDaily) =>
      day.deviceId === deviceId && day.date === today);
    activity.todayCount = daily?.totalCount ?? 0;
    const sensors: Sensor[] = [
      activity,
      this.sensor(deviceId, SensorType.TEMP_HUMIDITY, '温湿度', timestamp, live && thAvailable,
        typeof temp === 'number' ? temp : 0,
        thAvailable ? `${(temp as number).toFixed(1)}°C / ${(humidity as number).toFixed(0)}%` : '',
        thAvailable && (temp as number) >= 10 && (temp as number) <= 32
          && (humidity as number) >= 30 && (humidity as number) <= 70),
      this.sensor(deviceId, SensorType.GAS, '可燃气体（MQ-2）', timestamp, live && typeof gas === 'number',
        typeof gas === 'number' ? gas : 0, `${gas} ppm`,
        typeof gas === 'number' && gas <= IotDaCloudAdapter.GAS_ALARM_PPM && rep[PKey.ALARM] !== true),
      this.sensor(deviceId, SensorType.SOS_BUTTON, '紧急求助', timestamp, live && typeof sos === 'boolean',
        sos === true ? 1 : 0, sos === true ? '已触发' : '未触发', sos === false)
    ];
    const local = rep[PKey.PIR_RK2206];
    const remote = rep[PKey.PIR_H2821];
    const lux = rep[PKey.ILLUMINATION];
    if (typeof local === 'boolean') {
      sensors.push(this.sensor(deviceId, SensorType.PIR_RK2206, 'RK2206 板载人体活动', timestamp,
        live, local ? 1 : 0, local ? '有人活动' : '无活动', true));
    } else {
      activity.name = '人体活动（来源未拆分）';
    }
    if (typeof remote === 'number') {
      const valid: boolean = remote === 0 || remote === 1;
      const sensor: Sensor = this.sensor(deviceId, SensorType.PIR_H2821, 'H2821 星闪人体活动', timestamp,
        live && valid, remote === 1 ? 1 : 0, remote === 1 ? '有人活动' : '无活动', true);
      if (live && !valid) {
        sensor.displayValue = remote === -1 ? 'PIR 预热中' : '星闪链路无数据';
      }
      sensors.push(sensor);
    }
    if (typeof lux === 'number' && lux >= 0) {
      sensors.push(this.sensor(deviceId, SensorType.ILLUMINATION, 'RK2206 环境光照', timestamp,
        live, lux, `${lux.toFixed(1)} lx`, true));
    }
    return sensors;
  }


  // ==================== 真接口 1：设备列表 ====================

  /**
   * 设备列表。
   *
   * ⚠️ 首次启动时 IAM token / 网络状态可能还没就绪，第一次会拿到空列表。
   * 实测：首页第一次渲染显示「0 个传感器」，切一次页就正常。
   * 所以这里空结果自动重试一次（等 800ms），避免首页开屏是空的。
   */
  async getDeviceList(familyId: string): Promise<DeviceListItem[]> {
    let out: DeviceListItem[] = await this.fetchDeviceList();
    if (out.length === 0) {
      Logger.info(IotDaCloudAdapter.MODULE, 'getDeviceList 返回空，800ms 后重试一次');
      await this.delay(800);
      out = await this.fetchDeviceList();
    }
    return out;
  }

  private delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }

  /**
   * 确保 this.deviceId 有值（设备兜底解析）。
   *
   * AppConfig.deviceId 默认是空串，若用户不先打开首页就直接去预警中心标记告警，
   * confirmAlert / handleAlert 的 URL 会变成 /devices//commands，
   * 华为云回 IOTDA.000029。这里统一兜底：空则拉一次设备列表解析第一台。
   * 返回 false 表示没有绑定任何主机，调用方应放弃下发。
   */
  private async ensureDeviceId(): Promise<boolean> {
    if (this.deviceId.length > 0) {
      return true;
    }
    const devices: IotDaDeviceBrief[] = await this.fetchDevices();
    if (devices.length > 0) {
      this.deviceId = devices[0].device_id;
    }
    return this.deviceId.length > 0;
  }

  private async fetchDevices(): Promise<IotDaDeviceBrief[]> {
    const path: string = `/v5/iot/${this.projectId}/devices`;
    const resp: IotDaDeviceListResp = await this.http.get<IotDaDeviceListResp>(path);
    return resp.devices ?? [];
  }

  private async fetchDeviceList(): Promise<DeviceListItem[]> {
    const devices: IotDaDeviceBrief[] = await this.fetchDevices();
    const out: DeviceListItem[] = [];
    for (const brief of devices) {
      if (this.deviceId.length > 0 && brief.device_id !== this.deviceId) {
        continue;
      }
      let monitor: IotDaShadowValue | undefined;
      try {
        monitor = await this.fetchMonitor(brief.device_id);
      } catch (e) {
        Logger.warn(IotDaCloudAdapter.MODULE, `设备影子读取失败: ${brief.device_id}`);
      }
      const timestamp: number = this.reportTime(monitor);
      const sensors: Sensor[] = this.buildSensors(monitor, brief.device_id, brief.status === 'ONLINE', timestamp);
      out.push({
        device: this.buildDevice(brief, sensors, timestamp),
        sensors: sensors,
        activeAlerts: 0
      });
    }
    return out;
  }

  // ==================== 真接口 2：设备实时状态 ====================

  async getDeviceStatus(deviceId: string): Promise<DeviceStatusResp> {
    // deviceId 为空（页面调用方只关心当前家庭唯一主机时传 ''）时，
    // 先解析出真实 device_id，否则 URL 会缺尾巴变成 /devices/ ，
    // 华为云直接回 IOTDA.000029 path does not exist。
    let realId: string = deviceId;
    if (realId.length === 0) {
      if (!await this.ensureDeviceId()) {
        throw new Error('未绑定监护主机');
      }
      realId = this.deviceId;
      Logger.info(IotDaCloudAdapter.MODULE, `getDeviceStatus: deviceId 为空，已解析为 ${realId}`);
    }

    const detailPath: string = `/v5/iot/${this.projectId}/devices/${realId}`;
    const detail: IotDaDeviceDetail = await this.http.get<IotDaDeviceDetail>(detailPath);

    const monitor: IotDaShadowValue | undefined = await this.fetchMonitor(realId);
    const timestamp: number = this.reportTime(monitor);
    const properties = monitor?.properties;
    if (realId === this.deviceId && detail.status === 'ONLINE' && this.fresh(timestamp) && properties) {
      this.recordHistory(properties, timestamp);
    }

    const brief: IotDaDeviceBrief = {
      device_id: detail.device_id,
      device_name: detail.device_name,
      product_id: detail.product_id,
      node_id: detail.node_id,
      status: detail.status,
      create_time: detail.create_time
    };

    const sensors: Sensor[] = this.buildSensors(monitor, realId, detail.status === 'ONLINE', timestamp);
    const device: Device = this.buildDevice(brief, sensors, timestamp);
    device.model = detail.product_name ?? '';
    device.firmwareVersion = detail.fw_version ?? '';
    const resp: DeviceStatusResp = {
      device: device,
      sensors: sensors,
      sosButtonOnline: sensors.some((sensor: Sensor) => sensor.sensorType === SensorType.SOS_BUTTON && sensor.online),
      sosButtonBattery: -1,
      recentAlerts: []
    };
    return resp;
  }

  // ==================== 真接口 3：确认告警（下发命令） ====================

  async confirmAlert(alertId: string, remark: string): Promise<ConfirmAlertResp> {
    // 先落本地：确认动作是 App 侧行为，设备离线也应生效。
    // 与 handleAlert 同理，命令下发是「锦上添花」，不能被设备在线状态卡住。
    this.store.updateAlert(alertId, 'confirmed', '', '', '');

    try {
      if (await this.ensureDeviceId()) {
        const req: IotDaCommandReq = new IotDaCommandReq();
        req.service_id = 'control';
        req.command_name = 'confirmAlert';
        req.paras = { 'alertId': alertId, 'remark': remark };

        const path: string = `/v5/iot/${this.projectId}/devices/${this.deviceId}/commands`;
        const r: IotDaCommandResp = await this.http.post<IotDaCommandResp>(path, req);
        Logger.info(IotDaCloudAdapter.MODULE, `confirmAlert 下发 command_id=${r.command_id}`);
      }
    } catch (e) {
      Logger.warn(IotDaCloudAdapter.MODULE,
        `confirmAlert 设备命令下发失败（本地已确认，不影响）: ${(e as Error).message}`);
    }

    const resp: ConfirmAlertResp = {
      alertId: alertId,
      status: 'confirmed',
      confirmedAt: Date.now()
    };
    return resp;
  }

  // ==================== 真接口 4：处置告警（下发命令） ====================

  async handleAlert(alertId: string, reqBody: HandleAlertReq): Promise<HandleAlertResp> {
    const status: string = reqBody.result === 'false_alarm' ? 'false_alarm' : 'handled';
    const resultName: string = reqBody.result === 'false_alarm' ? '误报' : '已处置';

    // 先落本地（App 侧事件闭环）。告警列表本就是 App 侧数据，
    // 家属点了「已处置」就该立刻生效，不能被设备在线状态卡住。
    // 实测踩坑：设备离线时华为云回 IOTDA.014016 device is not online，
    // 若先下发命令再落库，处置就永远失败，告警只能一直堆在待处置里。
    const updated: Alert | undefined = this.store.updateAlert(
      alertId, status, reqBody.note, '家属', resultName);
    if (updated === undefined) {
      throw new Error(`本地无此告警: ${alertId}`);
    }

    // 再尽力下发设备命令（让设备停止声光报警）。设备离线 / 未绑定都不影响
    // 本地闭环，只记一条 warn 日志 —— 命令是「锦上添花」，本地处置才是必须。
    try {
      if (await this.ensureDeviceId()) {
        const req: IotDaCommandReq = new IotDaCommandReq();
        req.service_id = 'control';
        req.command_name = 'handleAlert';
        req.paras = { 'alertId': alertId, 'result': reqBody.result, 'note': reqBody.note };
        const path: string = `/v5/iot/${this.projectId}/devices/${this.deviceId}/commands`;
        const r: IotDaCommandResp = await this.http.post<IotDaCommandResp>(path, req);
        Logger.info(IotDaCloudAdapter.MODULE, `handleAlert 下发 command_id=${r.command_id}`);
      }
    } catch (e) {
      Logger.warn(IotDaCloudAdapter.MODULE,
        `handleAlert 设备命令下发失败（本地已闭环，不影响）: ${(e as Error).message}`);
    }

    // 写居家安全日志（赛题要求：处置结果留痕）
    const log: SafetyLogEntry = new SafetyLogEntry();
    log.logId = `log_${alertId}`;
    log.alertId = alertId;
    log.date = DateUtil.formatDate(updated.timestamp);
    log.level = updated.level;
    log.alertTypeName = updated.alertTypeName;
    log.triggeredAt = updated.timestamp;
    log.handledAt = Date.now();
    log.handlerName = '家属';
    log.resultName = resultName;
    log.note = reqBody.note;
    this.store.appendLog(log);

    const resp: HandleAlertResp = {
      alertId: alertId,
      status: status,
      handledAt: Date.now(),
      thresholdAdjusted: false
    };
    return resp;
  }

  /**
   * 删除告警（真接口 5 的配套清理动作）。
   *
   * 华为云没有"删除告警"接口（告警列表本就是 App 侧数据），
   * 所以这里只删本地 store。调用方（AlertCard）必须自己保证
   * 只删已闭环的告警。
   */
  async deleteAlert(alertId: string): Promise<boolean> {
    return this.store.deleteAlert(alertId);
  }

  /** 批量标记全部待处置为已处置（App 侧动作，设备命令不下发） */
  async markAllPendingHandled(): Promise<number> {
    return this.store.markAllPendingHandled('家属', '已处置', '批量标记已处置');
  }

  /** 清空全部待处置（仅本地记录，不影响安全日志/日报） */
  async clearPendingAlerts(): Promise<number> {
    return this.store.clearPending();
  }

  async injectDemoAlerts(count: number): Promise<number> {
    return 0;
  }

  // ==================== 门面：设备侧（App 不调用） ====================

  async registerDevice(req: RegisterDeviceReq): Promise<RegisterDeviceResp> {
    const resp: RegisterDeviceResp = {
      deviceId: this.deviceId,
      deviceToken: '',
      familyId: this.familyId,
      config: new DeviceConfig()
    };
    return resp;
  }

  async heartbeat(deviceId: string, req: HeartbeatReq): Promise<HeartbeatResp> {
    const resp: HeartbeatResp = {
      serverTime: Date.now(),
      pendingCommands: [],
      configChanged: false
    };
    return resp;
  }

  async uploadReadings(deviceId: string, req: UploadReadingsReq): Promise<UploadReadingsResp> {
    const resp: UploadReadingsResp = { accepted: 0, rejected: 0 };
    return resp;
  }

  async uploadAlert(deviceId: string, req: UploadAlertReq): Promise<UploadAlertResp> {
    const resp: UploadAlertResp = {
      alertId: req.alertId, serverAlertId: '', notified: [], deduped: false
    };
    return resp;
  }

  async fetchDeviceConfig(deviceId: string): Promise<DeviceConfig> {
    return new DeviceConfig();
  }

  // ==================== 门面：平台没有的接口 ====================

  async getReadings(query: ReadingsQuery): Promise<ReadingsResp> {
    // 分桶粒度：raw / 5m / 1h / 1d
    const bucketMs: number = query.interval === '5m' ? 300000
      : (query.interval === '1h' ? 3600000
        : (query.interval === '1d' ? 86400000 : 0));

    const src: BufferedReading[] = [];
    const from: number = Math.max(query.from, Date.now() - 86400000);
    for (let i: number = this.history.length - 1; i >= 0; i--) {
      const sample: IotDaHistorySample = this.history[i];
      if (sample.timestamp < from) {
        break;
      }
      const value = sample.values[query.sensorType];
      if (typeof value !== 'number' || (query.to > 0 && sample.timestamp > query.to)) {
        continue;
      }
      const reading: BufferedReading = new BufferedReading();
      reading.timestamp = sample.timestamp;
      reading.value = value;
      reading.humidity = sample.values[PKey.HUM] ?? 0;
      src.push(reading);
    }
    src.reverse();

    const points: ReadingsPoint[] = [];
    if (bucketMs === 0) {
      for (const b of src) {
        const p: ReadingsPoint = {
          timestamp: b.timestamp,
          value: b.value,
          extra: { 'humidity': b.humidity }
        };
        points.push(p);
      }
    } else {
      // 分桶求均值
      const binary: boolean = query.sensorType === SensorType.PIR || query.sensorType === SensorType.PIR_RK2206
        || query.sensorType === SensorType.PIR_H2821 || query.sensorType === SensorType.SOS_BUTTON;
      const keys: number[] = [];
      const times: number[] = [];
      const peaks: number[] = [];
      const vSum: number[] = [];
      const vCnt: number[] = [];
      const hSum: number[] = [];
      const hCnt: number[] = [];
      for (const b of src) {
        const k: number = Math.floor(b.timestamp / bucketMs);
        let idx: number = keys.indexOf(k);
        if (idx < 0) {
          keys.push(k);
          times.push(b.timestamp);
          peaks.push(b.value);
          vSum.push(0);
          vCnt.push(0);
          hSum.push(0);
          hCnt.push(0);
          idx = keys.length - 1;
        }
        times[idx] = b.timestamp;
        peaks[idx] = Math.max(peaks[idx], b.value);
        vSum[idx] = vSum[idx] + b.value;
        vCnt[idx] = vCnt[idx] + 1;
        if (b.humidity > 0) {
          hSum[idx] = hSum[idx] + b.humidity;
          hCnt[idx] = hCnt[idx] + 1;
        }
      }
      for (let i: number = 0; i < keys.length; i++) {
        const avg: number = vCnt[i] > 0 ? Math.round(vSum[i] / vCnt[i] * 100) / 100 : 0;
        const hum: number = hCnt[i] > 0 ? Math.round(hSum[i] / hCnt[i] * 10) / 10 : 0;
        const p: ReadingsPoint = {
          timestamp: times[i],
          value: binary ? peaks[i] : avg,
          extra: { 'humidity': hum }
        };
        points.push(p);
      }
    }

    const resp: ReadingsResp = {
      sensorType: query.sensorType,
      interval: query.interval,
      points: points
    };
    return resp;
  }

  private recordHistory(rep: Record<string, number | string | boolean>, ts: number): void {
    if (ts <= this.historyTime) {
      return;
    }
    const sample: IotDaHistorySample = new IotDaHistorySample();
    sample.timestamp = ts;
    const pir = rep[PKey.PIR];
    const temperature = rep[PKey.TEMP];
    const humidity = rep[PKey.HUM];
    const gas = rep[PKey.GAS];
    const sos = rep[PKey.SOS];
    if (typeof pir === 'boolean') {
      sample.values[SensorType.PIR] = pir ? 1 : 0;
    }
    if (typeof temperature === 'number' && typeof humidity === 'number') {
      sample.values[SensorType.TEMP_HUMIDITY] = temperature;
      sample.values[PKey.HUM] = humidity;
    }
    if (typeof gas === 'number') {
      sample.values[SensorType.GAS] = gas;
    }
    if (typeof sos === 'boolean') {
      sample.values[SensorType.SOS_BUTTON] = sos ? 1 : 0;
    }
    const local = rep[PKey.PIR_RK2206];
    const remote = rep[PKey.PIR_H2821];
    const lux = rep[PKey.ILLUMINATION];
    if (typeof local === 'boolean') {
      sample.values[SensorType.PIR_RK2206] = local ? 1 : 0;
    }
    if (remote === 0 || remote === 1) {
      sample.values[SensorType.PIR_H2821] = remote;
    }
    if (typeof lux === 'number' && lux >= 0) {
      sample.values[SensorType.ILLUMINATION] = lux;
    }
    if (Object.keys(sample.values).length === 0) {
      return;
    }

    this.historyTime = ts;
    this.history.push(sample);
    if (this.history[0].timestamp < ts - 86400000) {
      let first: number = 0;
      while (this.history[first].timestamp < ts - 86400000) {
        first++;
      }
      this.history = this.history.slice(first);
    }
    this.store.appendHistory(sample);
  }

  async getAlerts(query: AlertQuery): Promise<PageData<Alert>> {
    const all: Alert[] = this.store.loadAlerts();
    const filtered: Alert[] = [];
    for (const a of all) {
      if (query.status.length > 0 && query.status !== 'all' && a.status !== query.status) {
        continue;
      }
      if (query.level.length > 0 && query.level !== 'all' && a.level !== query.level) {
        continue;
      }
      filtered.push(a);
    }
    const ps: number = query.pageSize > 0 ? query.pageSize : 20;
    const page: number = query.page > 0 ? query.page : 1;
    const start: number = (page - 1) * ps;
    const resp: PageData<Alert> = {
      list: filtered.slice(start, start + ps),
      total: filtered.length,
      page: page,
      pageSize: ps
    };
    return resp;
  }

  async getAlertDetail(alertId: string): Promise<AlertDetailResp> {
    const all: Alert[] = this.store.loadAlerts();
    let hit: Alert | undefined = undefined;
    for (const a of all) {
      if (a.alertId === alertId) {
        hit = a;
        break;
      }
    }
    if (hit === undefined) {
      throw new CloudError(CloudCode.NOT_FOUND, `本地无此告警: ${alertId}`);
    }

    // 时间线由本地状态推导（平台不提供）
    const timeline: AlertTimelineNode[] = [];
    const t1: AlertTimelineNode = new AlertTimelineNode();
    t1.time = hit.timestamp;
    t1.event = 'triggered';
    t1.text = '设备端判定异常，已触发本地声光报警';
    timeline.push(t1);

    if (hit.status !== 'pending') {
      const t2: AlertTimelineNode = new AlertTimelineNode();
      t2.time = hit.timestamp;
      t2.event = 'confirmed';
      t2.text = '家属已确认告警';
      timeline.push(t2);
    }
    if (hit.handle !== undefined) {
      const t3: AlertTimelineNode = new AlertTimelineNode();
      t3.time = hit.handle.handledAt;
      t3.event = 'handled';
      t3.text = `已填写处置结果：${hit.handle.resultName}`;
      timeline.push(t3);
    }

    const resp: AlertDetailResp = { alert: hit, timeline: timeline };
    return resp;
  }

  async getActivityReport(deviceId: string, period: string, date: string): Promise<ActivityReportResp> {
    const resp: ActivityReportResp = { report: this.buildReport(period) };
    return resp;
  }

  async getActivityDistribution(deviceId: string, from: number, to: number): Promise<ActivityDistributionResp> {
    const cells: HeatmapCell[] = this.store.loadHourly();
    let max: number = 1;
    for (const c of cells) {
      if (c.count > max) {
        max = c.count;
      }
    }
    const resp: ActivityDistributionResp = { maxCount: max, cells: cells };
    return resp;
  }

  /**
   * 由本地累计的活动统计拼出报告。
   *
   * 数据来源：pollOnce 每 4 秒拉影子时检测 PIR 上升沿累加，
   * 因此报告里的数字是「App 在线的这段时间」的真实活动，不是编的。
   */
  private buildReport(period: string): ActivityReport {
    const days: number = period === 'month' ? 30 : (period === 'day' ? 1 : 7);
    const all: ActivityDaily[] = this.store.loadDaily();

    const r: ActivityReport = new ActivityReport();
    r.period = period;
    r.to = Date.now();
    const start: Date = new Date(r.to);
    start.setHours(0, 0, 0, 0);
    start.setDate(start.getDate() - days + 1);
    r.from = start.getTime();
    const fromDate: string = DateUtil.formatDate(r.from);
    const toDate: string = DateUtil.formatDate(r.to);
    const window: ActivityDaily[] = all.filter((day: ActivityDaily) => day.date >= fromDate && day.date <= toDate);
    r.compareWith = period === 'month' ? '上月' : '上周';

    let total: number = 0;
    let night: number = 0;
    const trend: TrendPoint[] = [];
    for (const d of window) {
      total = total + d.totalCount;
      night = night + d.nightCount;
      const p: TrendPoint = new TrendPoint();
      p.date = d.date;
      p.count = d.totalCount;
      trend.push(p);
    }
    r.totalCount = total;
    r.avgDailyCount = window.length > 0 ? Math.round(total / window.length * 10) / 10 : 0;
    r.nightActivityCount = night;
    r.daily = trend;

    // 小时分布与热力图
    const hourly: number[] = new Array<number>(24).fill(0);
    const cells: HeatmapCell[] = this.store.loadHourly().filter((cell: HeatmapCell) =>
      cell.date >= fromDate && cell.date <= toDate);
    for (const c of cells) {
      if (c.hour >= 0 && c.hour < 24) {
        hourly[c.hour] = hourly[c.hour] + c.count;
      }
    }
    r.hourlyDistribution = hourly;

    let activeHours: number = 0;
    let firstHour: number = -1;
    let lastHour: number = -1;
    for (let h: number = 0; h < 24; h++) {
      if (hourly[h] > 0) {
        activeHours = activeHours + 1;
        if (firstHour < 0) {
          firstHour = h;
        }
        lastHour = h;
      }
    }
    r.activeHours = activeHours;
    r.firstActivityTime = firstHour >= 0 ? this.hhmm(firstHour) : '--';
    r.lastActivityTime = lastHour >= 0 ? this.hhmm(lastHour) : '--';

    let maxCell: number = 1;
    for (const c of cells) {
      if (c.count > maxCell) {
        maxCell = c.count;
      }
    }
    r.heatmap = cells;
    r.maxHeatmapCount = maxCell;

    // 个人基线（14 天）与趋势
    const baseWin: ActivityDaily[] = all.slice(Math.max(0, all.length - 14));
    let bSum: number = 0;
    for (const d of baseWin) {
      bSum = bSum + d.totalCount;
    }
    const bAvg: number = baseWin.length > 0 ? bSum / baseWin.length : 0;
    let sq: number = 0;
    for (const d of baseWin) {
      const diff: number = d.totalCount - bAvg;
      sq = sq + diff * diff;
    }
    const bStd: number = baseWin.length > 0 ? Math.sqrt(sq / baseWin.length) : 0;
    r.baselineAvg = Math.round(bAvg * 10) / 10;
    r.baselineStdDev = Math.round(bStd * 10) / 10;

    if (bAvg > 0) {
      const change: number = (r.avgDailyCount - bAvg) / bAvg * 100;
      r.changePercent = Math.round(change * 10) / 10;
      r.trendDirection = change < -15 ? 'down' : (change > 15 ? 'up' : 'stable');
      r.insight = r.trendDirection === 'down'
        ? `日均活动 ${r.avgDailyCount} 次，较基线下降 ${Math.abs(r.changePercent)}%，建议关注`
        : (r.trendDirection === 'up'
          ? `日均活动 ${r.avgDailyCount} 次，较基线上升 ${r.changePercent}%，作息更活跃`
          : `日均活动 ${r.avgDailyCount} 次，与基线基本持平，作息稳定`);
    } else {
      r.trendDirection = 'stable';
      r.insight = '活动数据还在积累中，建议连续采集 3 天以上再观察趋势';
    }

    r.deviation = bStd > 0 ? Math.round((r.avgDailyCount - bAvg) / bStd * 100) / 100 : 0;
    r.baselineAbnormal = Math.abs(r.deviation) > 2;
    return r;
  }

  /** 0 → "00:00" */
  private hhmm(hour: number): string {
    const h: string = hour < 10 ? `0${hour}` : `${hour}`;
    return `${h}:00`;
  }

  async getSafetyLogs(query: SafetyLogQuery): Promise<PageData<SafetyLogEntry>> {
    const all: SafetyLogEntry[] = this.store.loadLogs();
    const ps: number = query.pageSize > 0 ? query.pageSize : 20;
    const page: number = query.page > 0 ? query.page : 1;
    const start: number = (page - 1) * ps;
    const resp: PageData<SafetyLogEntry> = {
      list: all.slice(start, start + ps),
      total: all.length,
      page: page,
      pageSize: ps
    };
    return resp;
  }

  async getFamilyMembers(familyId: string): Promise<FamilyMemberListResp> {
    const list: FamilyMember[] = this.store.loadMembers().filter((member: FamilyMember) =>
      !((member.userId === 'u_001' || member.userId === 'u_002') && member.phone === ''));
    const resp: FamilyMemberListResp = { members: list };
    return resp;
  }

  // ==================== 推送：影子轮询 ====================

  /**
   * 订阅告警。
   *
   * IoTDA 的应用侧没有面向 App 的实时推送通道（平台只提供订阅管理给服务器侧），
   * 所以这里用「轮询设备影子」近似：每 4 秒拉一次 reported，
   * 检测燃气 / 烟雾 / 求助是否越界，**只推新出现的类型**，避免每轮重复弹。
   */
  subscribeAlerts(listener: PushListener): void {
    if (this.listener !== undefined) {
      Logger.warn(IotDaCloudAdapter.MODULE, '已在轮询中，忽略重复订阅');
      return;
    }
    this.listener = listener;
    this.timerId = setInterval(() => {
      this.pollOnce().catch((e: Error) => {
        Logger.warn(IotDaCloudAdapter.MODULE, `影子轮询失败: ${e.message}`);
      });
    }, IotDaCloudAdapter.POLL_MS);
    Logger.info(IotDaCloudAdapter.MODULE, `开始轮询影子，间隔 ${IotDaCloudAdapter.POLL_MS}ms`);
  }

  unsubscribeAlerts(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
    this.listener = undefined;
    Logger.info(IotDaCloudAdapter.MODULE, '已停止影子轮询');
  }

  /** 使用新鲜的监护主机上报生成告警与采样历史。 */
  private async pollOnce(): Promise<void> {
    if (this.polling) {
      return;
    }
    this.polling = true;
    try {
      if (!await this.ensureDeviceId()) {
        return;
      }
      const id: string = this.deviceId;
      const detail: IotDaDeviceDetail = await this.http.get<IotDaDeviceDetail>(
        `/v5/iot/${this.projectId}/devices/${id}`);
      const monitor: IotDaShadowValue | undefined = await this.fetchMonitor(id);
      const ts: number = this.reportTime(monitor);
      const rep = monitor?.properties;
      if (detail.status !== 'ONLINE' || !this.fresh(ts) || rep === null || rep === undefined) {
        this.prevPir = undefined;
        return;
      }
      if (this.listener === undefined || ts <= this.lastSampleAt) {
        return;
      }
      this.deviceName = detail.device_name;
      const pir = rep[PKey.PIR];
      if (pir === true && this.prevPir === false && ts - this.lastSampleAt <= IotDaCloudAdapter.MAX_SAMPLE_AGE_MS) {
        this.store.recordActivity(id, DateUtil.formatDate(ts), new Date(ts).getHours(), ts);
      }
      this.prevPir = typeof pir === 'boolean' ? pir : undefined;
      this.lastSampleAt = ts;
      this.recordHistory(rep, ts);

      const active: string[] = [];
      const gas = rep[PKey.GAS];
      if (rep[PKey.SOS] === true) {
        active.push(AlertType.SOS_PRESSED);
      }
      if (rep[PKey.ALARM] === true && typeof gas === 'number') {
        active.push(AlertType.GAS_LEAK);
      }
      const prev: string[] = this.prevSig.split(',');
      for (const type of active) {
        if (prev.indexOf(type) < 0) {
          this.emitAlert(type, typeof gas === 'number' ? gas : 0, ts);
        }
      }
      this.prevSig = active.join(',');
    } finally {
      this.polling = false;
    }
  }

  private emitAlert(type: string, gas: number, timestamp: number): void {
    if (this.listener === undefined) {
      return;
    }
    const alertId: string = `iotda_${type}_${timestamp}`;
    if (this.store.loadAlerts().some((alert: Alert) => alert.alertId === alertId)) {
      return;
    }
    const level: string = AlertType.defaultLevelOf(type);
    const isGas: boolean = type === AlertType.GAS_LEAK;
    const desc: string = isGas ? '主控已触发 MQ-2 可燃气体报警' : '主控收到紧急求助信号';

    const alert: Alert = new Alert();
    alert.alertId = alertId;
    alert.serverAlertId = '';
    alert.deviceId = this.deviceId;
    alert.deviceName = this.deviceName;
    alert.alertType = type;
    alert.alertTypeName = AlertType.labelOf(type);
    alert.level = level;
    alert.timestamp = timestamp;
    alert.triggerValue = isGas ? gas : 1;
    alert.threshold = isGas ? IotDaCloudAdapter.GAS_ALARM_PPM : 0;
    alert.description = desc;
    alert.status = 'pending';
    alert.notifiedRoles = [];

    const msg: PushMessage = {
      type: 'alert',
      alertId: alert.alertId,
      level: level,
      alertType: type,
      alertTypeName: alert.alertTypeName,
      deviceId: this.deviceId,
      deviceName: this.deviceName,
      timestamp: timestamp,
      title: alert.alertTypeName,
      body: desc
    };
    Logger.info(IotDaCloudAdapter.MODULE, `推送告警 ${alert.alertTypeName} ${level}`);
    this.store.appendAlert(alert);
    this.listener(msg);
  }

  adapterName(): string {
    return '华为云 IoTDA';
  }
}
