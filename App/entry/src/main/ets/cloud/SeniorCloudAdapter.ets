import { CloudApi } from './CloudApi';
import { HttpClient, HttpMethod, HttpOptions, CloudError } from './HttpClient';
import {
  RegisterDeviceReq, RegisterDeviceResp, HeartbeatReq, HeartbeatResp,
  UploadReadingsReq, UploadReadingsResp, UploadAlertReq, UploadAlertResp,
  DeviceListItem, DeviceStatusResp, ReadingsQuery, ReadingsResp,
  AlertQuery, AlertDetailResp, ConfirmAlertResp, HandleAlertReq, HandleAlertResp,
  ActivityReportResp, ActivityDistributionResp, SafetyLogQuery,
  FamilyMemberListResp, PushListener, PushMessage, PageData
} from './CloudTypes';
import { DeviceConfig } from '../model/Device';
import { Alert, SafetyLogEntry } from '../model/Alert';
import { UuidUtil } from '../common/utils/DateUtil';
import { Logger } from '../common/utils/Logger';

/**
 * 本适配器内部使用的请求/响应包装类型。
 *
 * ArkTS 有两条硬性约束（`arkts-no-obj-literals-as-types` /
 * `arkts-no-untyped-obj-literals`）：
 *   1. 不能用对象字面量当类型（如 `request<{ list: X[] }>()`）；
 *   2. 对象字面量必须对应一个已声明的 class 或 interface。
 * 所以下面这些"形状"必须显式声明出来，不能内联。
 */
interface DeviceListResp {
  list: DeviceListItem[];
}

interface ConfirmAlertBody {
  remark: string;
}

interface ThresholdAdjustBody {
  key: string;
  value: number;
}

interface HandleAlertBody {
  result: string;
  note: string;
  adjustThreshold: ThresholdAdjustBody | null;
}

/**
 * 学长云端服务器的对接实现。
 *
 * ⚠️ **当前状态：接口文档未到位，本类为骨架。**
 *
 * 实现步骤（拿到接口文档后按序完成）：
 *   1. 对照《云端接口设计草案.md》最后一节的「对接字段映射表」，逐条填写实际路径；
 *   2. 若请求/响应字段名与本方案不一致，在本类的 `map*` 方法里做转换，
 *      **不要改动 CloudTypes 与业务层**；
 *   3. 若鉴权方式不同（如不是 X-Device-Token / Bearer），改 `buildOptions()`；
 *   4. 若推送不是 WebSocket，改 `subscribeAlerts()` 的实现；
 *   5. 完成 AppConfig.useMock = false 即可切换。
 *
 * 设计约束：本类只做「协议适配 + 字段映射」，不含任何业务逻辑。
 */
export class SeniorCloudAdapter implements CloudApi {
  private static readonly MODULE: string = 'SeniorCloudAdapter';

  private http: HttpClient;
  private accessToken: string = '';
  private deviceToken: string = '';
  private listener: PushListener | undefined = undefined;

  constructor(baseUrl: string) {
    this.http = new HttpClient(baseUrl);
  }

  /** 设置用户令牌（登录后调用） */
  setAccessToken(token: string): void {
    this.accessToken = token;
  }

  /** 设置设备令牌（设备端调用时使用） */
  setDeviceToken(token: string): void {
    this.deviceToken = token;
  }

  adapterName(): string {
    return '学长云端服务器';
  }

  /** 统一构造请求选项，集中注入鉴权与幂等 ID */
  private buildOptions(method: HttpMethod, path: string): HttpOptions {
    const o: HttpOptions = new HttpOptions();
    o.method = method;
    o.path = path;
    o.accessToken = this.accessToken;
    o.deviceToken = this.deviceToken;
    o.requestId = UuidUtil.generate();
    return o;
  }

  // ==================== 设备端 ====================

  async registerDevice(req: RegisterDeviceReq): Promise<RegisterDeviceResp> {
    // TODO(接口对接): 对照实际路径修改
    const o: HttpOptions = this.buildOptions(HttpMethod.POST, '/devices/register');
    o.body = req;
    return await this.http.request<RegisterDeviceResp>(o);
  }

  async heartbeat(deviceId: string, req: HeartbeatReq): Promise<HeartbeatResp> {
    const o: HttpOptions = this.buildOptions(HttpMethod.POST, `/devices/${deviceId}/heartbeat`);
    o.body = req;
    return await this.http.request<HeartbeatResp>(o);
  }

  async uploadReadings(deviceId: string, req: UploadReadingsReq): Promise<UploadReadingsResp> {
    const o: HttpOptions = this.buildOptions(HttpMethod.POST, `/devices/${deviceId}/readings`);
    o.body = req;
    return await this.http.request<UploadReadingsResp>(o);
  }

  async uploadAlert(deviceId: string, req: UploadAlertReq): Promise<UploadAlertResp> {
    const o: HttpOptions = this.buildOptions(HttpMethod.POST, `/devices/${deviceId}/alerts`);
    o.body = req;
    return await this.http.request<UploadAlertResp>(o);
  }

  async fetchDeviceConfig(deviceId: string): Promise<DeviceConfig> {
    const o: HttpOptions = this.buildOptions(HttpMethod.GET, `/devices/${deviceId}/config`);
    return await this.http.request<DeviceConfig>(o);
  }

  // ==================== App 端 ====================

  async getDeviceList(familyId: string): Promise<DeviceListItem[]> {
    const o: HttpOptions = this.buildOptions(HttpMethod.GET, `/families/${familyId}/devices`);
    const data: DeviceListResp = await this.http.request<DeviceListResp>(o);
    return data.list ?? [];
  }

  async getDeviceStatus(deviceId: string): Promise<DeviceStatusResp> {
    const o: HttpOptions = this.buildOptions(HttpMethod.GET, `/devices/${deviceId}/status`);
    return await this.http.request<DeviceStatusResp>(o);
  }

  async getReadings(query: ReadingsQuery): Promise<ReadingsResp> {
    const o: HttpOptions = this.buildOptions(HttpMethod.GET, `/devices/${query.deviceId}/readings`);
    o.query = {
      'from': `${query.from}`,
      'to': `${query.to}`,
      'sensorType': query.sensorType,
      'interval': query.interval
    };
    return await this.http.request<ReadingsResp>(o);
  }

  async getAlerts(query: AlertQuery): Promise<PageData<Alert>> {
    const o: HttpOptions = this.buildOptions(HttpMethod.GET, `/devices/${query.deviceId}/alerts`);
    o.query = {
      'status': query.status,
      'level': query.level,
      'from': `${query.from}`,
      'to': `${query.to}`,
      'page': `${query.page}`,
      'pageSize': `${query.pageSize}`
    };
    return await this.http.request<PageData<Alert>>(o);
  }

  async getAlertDetail(alertId: string): Promise<AlertDetailResp> {
    const o: HttpOptions = this.buildOptions(HttpMethod.GET, `/alerts/${alertId}`);
    return await this.http.request<AlertDetailResp>(o);
  }

  async confirmAlert(alertId: string, remark: string): Promise<ConfirmAlertResp> {
    const o: HttpOptions = this.buildOptions(HttpMethod.POST, `/alerts/${alertId}/confirm`);
    const body: ConfirmAlertBody = { remark: remark };
    o.body = body;
    return await this.http.request<ConfirmAlertResp>(o);
  }

  async handleAlert(alertId: string, req: HandleAlertReq): Promise<HandleAlertResp> {
    const o: HttpOptions = this.buildOptions(HttpMethod.POST, `/alerts/${alertId}/handle`);
    const body: HandleAlertBody = {
      result: req.result,
      note: req.note,
      adjustThreshold: null
    };
    // 误报反馈闭环：带上了阈值调整才组装 adjustThreshold 字段
    if (req.adjustThresholdKey.length > 0) {
      const adjust: ThresholdAdjustBody = {
        key: req.adjustThresholdKey,
        value: req.adjustThresholdValue
      };
      body.adjustThreshold = adjust;
    }
    o.body = body;
    return await this.http.request<HandleAlertResp>(o);
  }

  async getActivityReport(deviceId: string, period: string, date: string): Promise<ActivityReportResp> {
    const o: HttpOptions = this.buildOptions(HttpMethod.GET, `/devices/${deviceId}/activity/report`);
    o.query = { 'period': period, 'date': date };
    return await this.http.request<ActivityReportResp>(o);
  }

  /**
   * 删除告警（自建后端 REST 真删除）。
   * 与另外两个适配器语义一致：只删 App 侧这条记录。
   */
  async deleteAlert(alertId: string): Promise<boolean> {
    const o: HttpOptions = this.buildOptions(HttpMethod.DELETE, `/alerts/${alertId}`);
    await this.http.request<object>(o);
    return true;
  }

  /**
   * 批量标记全部待处置为已处置。
   * 后端暂无批量接口，这里拉一页待处置逐条走 handle 接口。
   * TODO(接口对接): 后端提供批量接口后替换为单次请求。
   */
  async markAllPendingHandled(): Promise<number> {
    const query: AlertQuery = {
      deviceId: '', status: 'pending', level: '',
      from: 0, to: 0, page: 1, pageSize: 200
    };
    const pending: PageData<Alert> = await this.getAlerts(query);
    let count: number = 0;
    for (const a of pending.list) {
      const req: HandleAlertReq = {
        result: 'resolved', note: '批量标记已处置',
        adjustThresholdKey: '', adjustThresholdValue: 0
      };
      await this.handleAlert(a.alertId, req);
      count = count + 1;
    }
    return count;
  }

  /**
   * 清空全部待处置。
   * 后端暂无批量接口，这里拉一页待处置逐条走删除接口。
   * TODO(接口对接): 后端提供批量接口后替换为单次请求。
   */
  async clearPendingAlerts(): Promise<number> {
    const query: AlertQuery = {
      deviceId: '', status: 'pending', level: '',
      from: 0, to: 0, page: 1, pageSize: 200
    };
    const pending: PageData<Alert> = await this.getAlerts(query);
    let count: number = 0;
    for (const a of pending.list) {
      await this.deleteAlert(a.alertId);
      count = count + 1;
    }
    return count;
  }

  /**
   * 演示注入：真实后端不提供该能力（告警应由设备上报）。
   * 这里返回 0，调用方按「未注入」处理即可，不影响主流程。
   */
  async injectDemoAlerts(count: number): Promise<number> {
    Logger.warn(SeniorCloudAdapter.MODULE, '真实云端不支持演示注入告警');
    return 0;
  }

  async getActivityDistribution(deviceId: string, from: number, to: number): Promise<ActivityDistributionResp> {
    const o: HttpOptions = this.buildOptions(HttpMethod.GET, `/devices/${deviceId}/activity/distribution`);
    o.query = { 'from': `${from}`, 'to': `${to}` };
    return await this.http.request<ActivityDistributionResp>(o);
  }

  async getSafetyLogs(query: SafetyLogQuery): Promise<PageData<SafetyLogEntry>> {
    const o: HttpOptions = this.buildOptions(HttpMethod.GET, `/devices/${query.deviceId}/logs`);
    o.query = {
      'from': `${query.from}`,
      'to': `${query.to}`,
      'page': `${query.page}`,
      'pageSize': `${query.pageSize}`
    };
    return await this.http.request<PageData<SafetyLogEntry>>(o);
  }

  async getFamilyMembers(familyId: string): Promise<FamilyMemberListResp> {
    const o: HttpOptions = this.buildOptions(HttpMethod.GET, `/families/${familyId}/members`);
    return await this.http.request<FamilyMemberListResp>(o);
  }

  // ==================== 推送 ====================

  /**
   * 订阅告警推送。
   *
   * TODO(接口对接): 按实际推送通道改写——
   *   · WebSocket：用 @kit.NetworkKit 的 webSocket 建立长连接，收到消息后转成 PushMessage 回调；
   *   · 厂商推送：接 Push Kit，在 EntryAbility 的 onNewWant 中接收；
   *   · 都不支持：降级为定时轮询 getAlerts(status=pending)，间隔见 AppConstants.POLL_INTERVAL_MS。
   */
  subscribeAlerts(listener: PushListener): void {
    this.listener = listener;
    Logger.warn(SeniorCloudAdapter.MODULE,
      '推送通道尚未对接，当前使用轮询降级方案（接口文档到位后替换本方法）');
    // 轮询降级：定时拉取未处置告警，避免完全收不到提醒
    this.startPolling();
  }

  unsubscribeAlerts(): void {
    this.listener = undefined;
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  private pollTimer: number = -1;

  private startPolling(): void {
    if (this.pollTimer >= 0) {
      return;
    }
    this.pollTimer = setInterval(() => {
      // TODO(接口对接): 轮询实现，当前留空避免无谓请求
    }, 30000);
  }
}
