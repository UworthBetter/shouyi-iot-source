/**
 * @file    IotDaTypes.ets
 * @brief   华为云 IoTDA 响应结构定义
 *
 * 作用只有一个：把平台返回的 JSON 形状显式声明出来。
 * ArkTS 有两条硬约束（arkts-no-obj-literals-as-types /
 * arkts-no-untyped-obj-literals）：对象字面量不能当类型用，
 * 且对象字面量必须对应一个已声明的 class 或 interface。
 * 所以每层包装都必须写在这里，不能内联。
 *
 * 注意：这里的字段名是 IoTDA 的下划线风格，与项目 model/ 下的
 * 驼峰风格是两套东西。转换在 IotDaCloudAdapter 里做，不要混用。
 */

/** 设备列表响应 —— GET /v5/iot/{project_id}/devices */
export interface IotDaDeviceListResp {
  devices: IotDaDeviceBrief[];
  page: IotDaPage;
}

/** IoTDA 设备摘要。注意没有 battery/signal 这类字段，那些要从影子取。 */
export interface IotDaDeviceBrief {
  device_id: string;
  device_name: string;
  product_id: string;
  node_id: string;
  /** ONLINE / OFFLINE / ABNORMAL */
  status: string;
  create_time: string;
}

/**
 * 分页信息。实测（2026-10-21）：
 *   { "count": 1, "marker": "6ad84684df973925264e8645" }
 * 不是常见的 page_no/page_size/total。翻页时把 marker 回传即可。
 */
export interface IotDaPage {
  count: number;
  marker: string;
}

/** 设备详情响应 —— GET /v5/iot/{project_id}/devices/{device_id} */
export interface IotDaDeviceDetail {
  device_id: string;
  node_id: string;
  gateway_id: string;
  device_name: string;
  node_type: string;
  product_id: string;
  product_name: string;
  /** ONLINE / OFFLINE / ABNORMAL */
  status: string;
  create_time: string;
  /** 形如 20261021T045844Z */
  active_time: string;
  connection_status_update_time: string;
  fw_version: string | null;
  sw_version: string | null;
}

/**
 * 设备影子响应 —— GET /v5/iot/{project_id}/devices/{device_id}/shadow
 *
 * desired  = 应用侧期望值（下发但设备未确认）
 * reported = 设备最近一次实际上报   ← App 的实时数据就取这个
 * version  = 单调递增，每上报一次 +1，可用于判断数据是否变化
 */
export interface IotDaShadowResp {
  device_id: string;
  shadow: IotDaShadowService[];
}

/**
 * 影子里的一个"期望值/上报值"块。
 *
 * ⚠️ 实测结构（2026-10-21 真实响应，务必别改回去）：
 *   属性值包在 properties 里，外面还有一层，不是直接平铺！
 *   {
 *     "properties": { "gas": 813, "smoke": 293, ... },
 *     "event_time": "20261021T060239Z"
 *   }
 * 曾经按平铺写（reported.gas）导致读出来全是 undefined，
 * 而且不报错，页面只显示"无数据"——最难查的一类问题。
 */
export interface IotDaShadowValue {
  /** 设备未上报过时为 null */
  properties: Record<string, number | string | boolean> | null;
  /** 形如 20261021T060239Z，UTC */
  event_time: string | null;
}

export interface IotDaShadowService {
  service_id: string;
  desired: IotDaShadowValue;
  reported: IotDaShadowValue;
  version: number;
}

/** 命令下发响应 —— POST /v5/iot/{project_id}/devices/{device_id}/commands */
export interface IotDaCommandResp {
  command_id: string;
}

/**
 * 命令下发请求体。
 * command_name 必须与产品模型 control service 里的命令名完全一致：
 *   setThreshold / confirmAlert / handleAlert / playVoice / silence
 */
export class IotDaCommandReq {
  public service_id: string = 'control';
  public command_name: string = '';
  public paras: Record<string, string | number | boolean> = {};
}

/** 影子中 reported 的一个属性值。用于做越界判断。 */
export interface IotDaReportedValue {
  key: string;
  value: number | string | boolean;
}
