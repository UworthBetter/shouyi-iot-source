/**
 * @file    IotDaHttp.ets
 * @brief   华为云 IoTDA 应用侧 HTTP 层（最小可用版）
 *
 * 为什么不能复用项目里的 HttpClient：
 *   项目里的 HttpClient.request() 把响应信封写死成 `{code, message, data}`，
 *   并且要求 `code === 0` 才认为成功。华为云 IoTDA 完全不返回这个信封——
 *   成功时直接给业务对象，失败时给 `{error_code, error_msg}`。
 *   所以这里单独实现一层，不复用、也不改原文件。
 *
 * 用法：
 *   const http = new IotDaHttp('https://xxxx.iot-da-app.cn-north-4.myhuaweicloud.com', projectId);
 *   http.setToken(token);                       // IAM 拿到的 X-Subject-Token
 *   const shadow = await http.get<IotDaShadowResp>(`/v5/iot/${projectId}/devices/${deviceId}/shadow`);
 *
 * 注意：
 *   1. 所有应用侧 REST 都必须带 `X-Auth-Token` 头，token 由 IAM 换取；
 *   2. 路径里的 project_id / device_id 已由构造参数提供，调用方只传子路径；
 *   3. 本类只管传输与错误转换，不做任何业务映射（那部分在 IotDaCloudAdapter）。
 */

import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { IotDaAuth } from './IotDaAuth';
import { IotDaSigner, SignedHeaders } from './IotDaSigner';

/** 超时（毫秒），与项目 HttpClient 保持一致 */
const IOTDA_TIMEOUT_MS: number = 15000;

/** IoTDA 失败响应结构 —— 注意没有统一的 code/message/data 信封 */
export interface IotDaError {
  error_code: string;
  error_msg: string;
}

/** 统一异常，业务层只需捕获这一种 */
export class IotDaErrorException extends Error {
  public code: string;
  constructor(code: string, message: string) {
    super(message);
    this.code = code;
    this.name = 'IotDaErrorException';
  }
}

/**
 * 华为云 IoTDA 应用侧 HTTP 客户端。
 *
 * 只实现 get / post 两个动词：应用侧查设备、查影子用 GET，下发命令用 POST。
 */
export class IotDaHttp {
  private static readonly MODULE: string = 'IotDaHttp';

  /** 应用侧接入域名，例如 https://xxxx.iotda-app.cn-north-4.myhuaweicloud.com */
  private readonly baseUrl: string;
  /** 不带 scheme 的域名，签名时要用 */
  private readonly host: string;
  /** 项目 ID，从「我的凭证」页拿 */
  private readonly projectId: string;
  /** AK/SK 签名器 —— 推荐路径，不过期 */
  private signer: IotDaSigner | undefined = undefined;
  /** 备用路径：手工贴的 IAM token */
  private token: string = '';
  /** 备用路径：IAM 自动续期器 */
  private auth: IotDaAuth | undefined = undefined;

  constructor(baseUrl: string, projectId: string) {
    this.baseUrl = baseUrl;
    let h: string = baseUrl.replace('https://', '').replace('http://', '');
    if (h.endsWith('/')) {
      h = h.substring(0, h.length - 1);
    }
    this.host = h;
    this.projectId = projectId;
  }

  /** 挂上 AK/SK 签名器（推荐） */
  public setSigner(signer: IotDaSigner): void {
    this.signer = signer;
  }

  /** 设置 / 更新 IAM token。token 过期时重新换取后调用即可。 */
  public setToken(token: string): void {
    this.token = token;
  }

  /**
   * 挂上 IAM 自动续期器。
   * 设置后每次请求前都会取一次有效 token（内部有缓存，不会每次都打 IAM）。
   */
  public setAuth(auth: IotDaAuth): void {
    this.auth = auth;
  }

  public hasToken(): boolean {
    return this.token.length > 0;
  }

  /**
   * 发起 GET 请求。
   * @param subPath 以 /v5/iot/ 开头的子路径，用 `{...}` 占位符由调用方填好
   */
  public async get<T>(subPath: string): Promise<T> {
    return await this.send<T>(http.RequestMethod.GET, subPath, undefined);
  }

  /**
   * 发起 POST 请求。
   * @param subPath  子路径
   * @param body     请求体，必须是已声明的 class/interface 实例（ArkTS 不允许裸对象字面量）
   */
  public async post<T>(subPath: string, body: object | undefined): Promise<T> {
    return await this.send<T>(http.RequestMethod.POST, subPath, body);
  }

  /** 请求方法转大写字符串，签名要用 */
  private methodName(m: http.RequestMethod): string {
    switch (m) {
      case http.RequestMethod.POST:
        return 'POST';
      case http.RequestMethod.PUT:
        return 'PUT';
      case http.RequestMethod.DELETE:
        return 'DELETE';
      default:
        return 'GET';
    }
  }

  private async send<T>(method: http.RequestMethod, subPath: string, body: object | undefined): Promise<T> {
    const payload: string = body !== undefined ? JSON.stringify(body) : '';
    const url: string = `${this.baseUrl}${subPath}`;
    const req: http.HttpRequest = http.createHttp();

    const headers: Record<string, string> = {
      'Content-Type': 'application/json; charset=utf-8'
    };

    if (this.signer !== undefined && this.signer.isConfigured()) {
      // AK/SK 签名（推荐路径，不过期）
      const signed: SignedHeaders =
        await this.signer.sign(this.methodName(method), this.host, subPath, '', payload);
      headers['X-Sdk-Date'] = signed.sdkDate;
      headers['Authorization'] = signed.authorization;
      // 注意：不要手工设 Host，系统会按实际连接域名自动填，
      // 我们签名的 host 与它一致即可
    } else {
      // 备用：IAM token
      if (this.auth !== undefined) {
        try {
          this.token = await this.auth.getToken();
        } catch (e) {
          throw new IotDaErrorException('AUTH_FAILED', `取 IAM token 失败: ${(e as Error).message}`);
        }
      }
      headers['X-Auth-Token'] = this.token;
    }

    try {
      const resp: http.HttpResponse = await req.request(url, {
        method: method,
        header: headers,
        extraData: payload.length > 0 ? payload : undefined,
        connectTimeout: IOTDA_TIMEOUT_MS,
        readTimeout: IOTDA_TIMEOUT_MS
      });

      const text: string = typeof resp.result === 'string'
        ? resp.result
        : JSON.stringify(resp.result);

      return this.handleResponse<T>(resp.responseCode, text);
    } catch (err) {
      if (err instanceof IotDaErrorException) {
        throw err;
      }
      const e: BusinessError = err as BusinessError;
      throw new IotDaErrorException('NETWORK_ERROR', `网络请求失败: ${String(e.code)} ${e.message}`);
    } finally {
      req.destroy();
    }
  }

  /** 把 HTTP 响应转成业务对象或异常 */
  private handleResponse<T>(code: number, text: string): T {
    // IoTDA 的 HTTP 状态码：200 成功，400 参数错，401/403 鉴权错，404 不存在，429 限流
    if (code === 200 || code === 204) {
      // 实测踩坑：ArkTS 报 arkts-no-untyped-obj-literals，
      // `return {} as T` 这种空对象字面量不允许，统一补成 '{}' 再走 JSON.parse
      const body: string = text.length === 0 ? '{}' : text;
      try {
        return JSON.parse(body) as T;
      } catch (e) {
        throw new IotDaErrorException('PARSE_ERROR', `响应解析失败: ${(e as Error).message}`);
      }
    }

    // 失败时 IoTDA 返回 {error_code, error_msg}
    let msg: string = text;
    try {
      const parsed: IotDaError = JSON.parse(text) as IotDaError;
      if (parsed.error_msg !== undefined) {
        msg = `${parsed.error_code} ${parsed.error_msg}`;
      }
    } catch (e) {
      // 保持原始文本
    }
    throw new IotDaErrorException(`HTTP_${String(code)}`, msg);
  }
}
