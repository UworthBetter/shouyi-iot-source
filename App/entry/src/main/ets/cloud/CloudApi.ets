import {
  RegisterDeviceReq, RegisterDeviceResp, HeartbeatReq, HeartbeatResp,
  UploadReadingsReq, UploadReadingsResp, UploadAlertReq, UploadAlertResp,
  DeviceListItem, DeviceStatusResp, ReadingsQuery, ReadingsResp,
  AlertQuery, AlertDetailResp, ConfirmAlertResp, HandleAlertReq, HandleAlertResp,
  ActivityReportResp, ActivityDistributionResp, SafetyLogQuery,
  FamilyMemberListResp, PushListener, PageData
} from './CloudTypes';
import { DeviceConfig } from '../model/Device';
import { Alert, SafetyLogEntry } from '../model/Alert';

/**
 * 云端能力抽象接口。
 *
 * **这是整个 App 与云端之间唯一的契约。** 业务层与 UI 只依赖这个接口，
 * 不依赖任何具体实现。因此：
 *   · 学长接口文档未到时 → 注入 MockCloudAdapter，App 可完整跑通；
 *   · 接口文档到位后    → 只写 SeniorCloudAdapter，业务层与 UI 一行不改；
 *   · 若最终改用自建后端 → 只写 SelfHostedAdapter。
 *
 * 方法签名与《云端接口设计草案.md》一一对应。
 */
export interface CloudApi {

  // ==================== 设备端 ====================

  /** 设备注册（开发板首次上电时调用） */
  registerDevice(req: RegisterDeviceReq): Promise<RegisterDeviceResp>;

  /** 设备心跳 */
  heartbeat(deviceId: string, req: HeartbeatReq): Promise<HeartbeatResp>;

  /** 批量上报传感器读数 */
  uploadReadings(deviceId: string, req: UploadReadingsReq): Promise<UploadReadingsResp>;

  /** 上报告警事件 */
  uploadAlert(deviceId: string, req: UploadAlertReq): Promise<UploadAlertResp>;

  /** 拉取设备配置（阈值、上报间隔、语音文案） */
  fetchDeviceConfig(deviceId: string): Promise<DeviceConfig>;

  // ==================== App 端 ====================

  /** 获取家庭下全部设备与状态摘要 */
  getDeviceList(familyId: string): Promise<DeviceListItem[]>;

  /** 获取单台设备的实时状态 */
  getDeviceStatus(deviceId: string): Promise<DeviceStatusResp>;

  /** 查询历史读数（支持服务端聚合） */
  getReadings(query: ReadingsQuery): Promise<ReadingsResp>;

  /** 查询告警列表 */
  getAlerts(query: AlertQuery): Promise<PageData<Alert>>;

  /** 查询告警详情（含时间线） */
  getAlertDetail(alertId: string): Promise<AlertDetailResp>;

  /** 确认告警 */
  confirmAlert(alertId: string, remark: string): Promise<ConfirmAlertResp>;

  /** 填写处置结果（事件闭环） */
  handleAlert(alertId: string, req: HandleAlertReq): Promise<HandleAlertResp>;

  /**
   * 删除一条告警（仅 App 本地记录，IoTDA 无此接口）。
   * 只允许删已闭环的告警，调用方自行保证。
   */
  deleteAlert(alertId: string): Promise<boolean>;

  /**
   * 批量把当前全部「待处置」告警标记为已处置。
   * 返回实际处理条数。属于 App 侧批量闭环动作。
   */
  markAllPendingHandled(): Promise<number>;

  /**
   * 清空全部「待处置」告警（仅 App 本地记录）。
   * 返回实际删除条数。调用方必须先弹二次确认。
   */
  clearPendingAlerts(): Promise<number>;

  /**
   * 演示用：注入 count 条模拟告警（待处置），返回注入条数。
   * 给评委演示「告警到达 → 处置 → 删除」的完整闭环，节奏由演示者控制。
   */
  injectDemoAlerts(count: number): Promise<number>;

  /** 查询活动规律报告 */
  getActivityReport(deviceId: string, period: string, date: string): Promise<ActivityReportResp>;

  /** 查询活动时段分布（热力图数据源） */
  getActivityDistribution(deviceId: string, from: number, to: number): Promise<ActivityDistributionResp>;

  /** 查询居家安全日志 */
  getSafetyLogs(query: SafetyLogQuery): Promise<PageData<SafetyLogEntry>>;

  /** 查询家庭成员 */
  getFamilyMembers(familyId: string): Promise<FamilyMemberListResp>;

  // ==================== 推送 ====================

  /** 订阅告警推送 */
  subscribeAlerts(listener: PushListener): void;

  /** 取消订阅 */
  unsubscribeAlerts(): void;

  /** 当前使用的实现名称，用于界面展示与调试 */
  adapterName(): string;

  // ==================== 演示（仅 Mock 实现） ====================

  /**
   * 切换演示场景，用于答辩现场动态演示三色圆点体系。
   * 只有 MockCloudAdapter 实现；真实云端不实现，调用方需先判空。
   */
  setDemoScenario?(scenario: string): void;

  /** 读取当前演示场景 */
  getDemoScenario?(): string;
}
