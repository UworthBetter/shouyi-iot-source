import { Device, Sensor, DeviceConfig } from '../model/Device';
import { Alert, AlertHandle, AlertTimelineNode, SafetyLogEntry } from '../model/Alert';
import { ActivityReport, HeatmapCell, TrendPoint } from '../model/ActivityRecord';
import { FamilyMember } from '../model/FamilyMember';

/**
 * 云端接口的请求 / 响应类型定义。
 * 与《云端接口设计草案.md》一一对应。
 * 学长服务器接口到位后，差异部分在这里做映射，不改业务层。
 */

// ==================== 通用 ====================

/** 统一响应包装 */
export interface CloudResponse<T> {
  code: number;
  message: string;
  data: T;
}

/** 分页响应 */
export interface PageData<T> {
  list: T[];
  total: number;
  page: number;
  pageSize: number;
}

// ==================== 设备端 ====================

export interface RegisterDeviceReq {
  deviceSn: string;
  deviceName: string;
  model: string;
  firmwareVersion: string;
  capabilities: string[];
  registerCode: string;
}

export interface RegisterDeviceResp {
  deviceId: string;
  deviceToken: string;
  familyId: string;
  config: DeviceConfig;
}

export interface HeartbeatReq {
  timestamp: number;
  battery: number;
  signal: number;
  networkType: string;
  firmwareVersion: string;
  sensorHealth: Record<string, boolean>;
  /**
   * 本次上报的心率（次/分钟），可选。
   * 设备未接入雷达/PPG 或本次未采到有效读数时缺省，
   * 服务端保留上一次读数并由新鲜度窗口判定是否过期，
   * 过期后界面展示 "-- 次/分钟"。
   */
  heartRate?: number;
}

export interface HeartbeatResp {
  serverTime: number;
  pendingCommands: string[];
  configChanged: boolean;
}

export interface ReadingItem {
  sensorType: string;
  timestamp: number;
  value: number;
  extra: Record<string, number | string>;
}

export interface UploadReadingsReq {
  batchId: string;
  readings: ReadingItem[];
}

export interface UploadReadingsResp {
  accepted: number;
  rejected: number;
}

export interface UploadAlertReq {
  alertId: string;
  alertType: string;
  level: string;
  timestamp: number;
  sensorType: string;
  triggerValue: number;
  threshold: number;
  description: string;
  localActions: string[];
}

export interface UploadAlertResp {
  alertId: string;
  serverAlertId: string;
  notified: string[];
  deduped: boolean;
}

// ==================== App 端 ====================

/** 设备列表项：设备信息 + 传感器摘要 + 未处置告警数 */
export interface DeviceListItem {
  device: Device;
  sensors: Sensor[];
  activeAlerts: number;
}

export interface DeviceStatusResp {
  device: Device;
  sensors: Sensor[];
  sosButtonOnline: boolean;
  sosButtonBattery: number;
  recentAlerts: Alert[];
}

export interface ReadingsQuery {
  deviceId: string;
  from: number;
  to: number;
  sensorType: string;
  /** 聚合粒度：raw / 5m / 1h / 1d */
  interval: string;
}

export interface ReadingsPoint {
  timestamp: number;
  value: number;
  extra: Record<string, number | string>;
}

export interface ReadingsResp {
  sensorType: string;
  interval: string;
  points: ReadingsPoint[];
}

export interface AlertQuery {
  deviceId: string;
  status: string;
  level: string;
  from: number;
  to: number;
  page: number;
  pageSize: number;
}

export interface AlertDetailResp {
  alert: Alert;
  timeline: AlertTimelineNode[];
}

export interface ConfirmAlertResp {
  alertId: string;
  status: string;
  confirmedAt: number;
}

export interface HandleAlertReq {
  result: string;
  note: string;
  /** 可选的阈值调整（误报反馈闭环） */
  adjustThresholdKey: string;
  adjustThresholdValue: number;
}

export interface HandleAlertResp {
  alertId: string;
  status: string;
  handledAt: number;
  thresholdAdjusted: boolean;
}

export interface ActivityReportResp {
  report: ActivityReport;
}

export interface ActivityDistributionResp {
  maxCount: number;
  cells: HeatmapCell[];
}

export interface SafetyLogQuery {
  deviceId: string;
  from: number;
  to: number;
  page: number;
  pageSize: number;
}

export interface FamilyMemberListResp {
  members: FamilyMember[];
}

/** 推送消息结构 */
export interface PushMessage {
  type: string;
  alertId: string;
  level: string;
  alertType: string;
  alertTypeName: string;
  deviceId: string;
  deviceName: string;
  timestamp: number;
  title: string;
  body: string;
}

/** 推送消息回调 */
export type PushListener = (msg: PushMessage) => void;
