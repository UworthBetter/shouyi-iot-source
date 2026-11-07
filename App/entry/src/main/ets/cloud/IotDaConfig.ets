/**
 * @file    IotDaConfig.ets
 * @brief   华为云 IoTDA 接入配置（集中管理，改这里就行）
 *
 * ⚠️ 本文件含 IAM 子用户密码。提交代码前请确认：
 *    - 不要推到公开仓库
 *    - 如果必须提交，把 PASSWORD 换成从本地文件读取，或改成环境注入
 *
 * 为什么用「子用户」而不是主账号：
 *    主账号属于华为账号体系，密码不走 IAM 的密码认证，
 *    调 /v3/auth/tokens 会一直 401。子用户是纯 IAM 用户，密码认证可用。
 */

export class IotDaConfig {
  /** 总开关：false 时回落到 MockCloudAdapter */
  static readonly ENABLED: boolean = true;

  /** 应用侧接入域名（控制台「总览 → 接入信息 → 应用接入 → HTTPS」）*/
  static readonly ENDPOINT: string = 'https://2eb62113b2.st1.iotda-app.cn-north-4.myhuaweicloud.com';

  /** 区域，用于 IAM 地址拼接 */
  static readonly REGION: string = 'cn-north-4';

  /** 项目 ID（「我的凭证 → 项目」）*/
  static readonly PROJECT_ID: string = '01a157285f937fd9b822aba3bd9ddd6f';

  /**
   * 设备 ID —— 注意格式是 {产品ID}_{设备标识码}
   * 不是另一个 24 位十六进制，MQTT 和 REST 通用这一个
   */
  static readonly DEVICE_ID: string = '6ad6dbb77f2e6c302fa4ef57_sy-rk2206-001';

  /** 家庭 ID，本地业务用，平台侧无对应概念 */
  static readonly FAMILY_ID: string = 'fam_0001';

  // ---------- IAM 子用户凭据 ----------

  /** 华为云账号名（「我的凭证」第一屏，注意末尾是 - 不是 _）*/
  static readonly DOMAIN_NAME: string = 'hid_gk2lr21z__-uc0-';

  /** IAM 子用户名 */
  static readonly USER_NAME: string = 'shouyi-app';

  /** 子用户密码 */
  static readonly PASSWORD: string = 'mmy262455';
}
