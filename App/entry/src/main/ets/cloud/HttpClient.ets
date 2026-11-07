import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CloudResponse } from './CloudTypes';
import { CloudCode } from '../common/constants/AppConstants';
import { Logger } from '../common/utils/Logger';

/** 请求方法 */
export enum HttpMethod {
  GET = 'GET',
  POST = 'POST',
  PUT = 'PUT',
  DELETE = 'DELETE'
}

/** 请求选项 */
export class HttpOptions {
  method: HttpMethod = HttpMethod.GET;
  /** 路径，如 /devices/register */
  path: string = '';
  /** 查询参数 */
  query: Record<string, string> = {};
  /** 请求体 */
  body: object | undefined = undefined;
  /** 设备令牌（设备端调用时使用） */
  deviceToken: string = '';
  /** 用户令牌（App 端调用时使用） */
  accessToken: string = '';
  /** 幂等 ID */
  requestId: string = '';
}

/** 统一错误 */
export class CloudError extends Error {
  code: number;
  constructor(code: number, message: string) {
    super(message);
    this.code = code;
  }
}

/**
 * HTTP 客户端封装。
 *
 * 职责：
 * 1. 统一拼接 URL 与查询参数；
 * 2. 注入鉴权头（设备令牌 / 用户令牌）；
 * 3. 注入幂等 ID；
 * 4. 解析统一响应结构，把业务错误码转成异常；
 * 5. 超时与网络异常的统一处理。
 *
 * 业务层不直接使用本类，只通过 CloudApi 接口访问云端。
 */
export class HttpClient {
  private static readonly MODULE: string = 'HttpClient';
  private static readonly TIMEOUT_MS: number = 15000;
  private baseUrl: string = '';

  constructor(baseUrl: string) {
    this.baseUrl = baseUrl;
  }

  /** 发起请求并解析统一响应结构 */
  async request<T>(options: HttpOptions): Promise<T> {
    const url: string = this.buildUrl(options);
    const request: http.HttpRequest = http.createHttp();

    const headers: Record<string, string> = {
      'Content-Type': 'application/json; charset=utf-8'
    };
    if (options.deviceToken.length > 0) {
      headers['X-Device-Token'] = options.deviceToken;
    }
    if (options.accessToken.length > 0) {
      headers['Authorization'] = `Bearer ${options.accessToken}`;
    }
    if (options.requestId.length > 0) {
      headers['X-Request-Id'] = options.requestId;
    }

    try {
      const resp: http.HttpResponse = await request.request(url, {
        method: HttpClient.toRequestMethod(options.method),
        header: headers,
        extraData: options.body !== undefined ? JSON.stringify(options.body) : undefined,
        connectTimeout: HttpClient.TIMEOUT_MS,
        readTimeout: HttpClient.TIMEOUT_MS
      });

      if (resp.responseCode !== 200) {
        Logger.error(HttpClient.MODULE, `${options.method} ${options.path} HTTP ${resp.responseCode}`);
        throw new CloudError(CloudCode.SERVER_ERROR, `服务返回 ${resp.responseCode}`);
      }

      const text: string = typeof resp.result === 'string' ? resp.result : JSON.stringify(resp.result);
      const parsed: CloudResponse<T> = JSON.parse(text) as CloudResponse<T>;

      if (parsed.code !== CloudCode.OK) {
        Logger.warn(HttpClient.MODULE, `${options.path} 业务错误 ${parsed.code}: ${parsed.message}`);
        throw new CloudError(parsed.code, parsed.message);
      }
      return parsed.data;
    } catch (err) {
      if (err instanceof CloudError) {
        throw err;
      }
      const e: BusinessError = err as BusinessError;
      Logger.error(HttpClient.MODULE, `${options.method} ${options.path} 失败: ${e.code} ${e.message}`);
      throw new CloudError(CloudCode.SERVICE_UNAVAILABLE, '网络不可用，请稍后重试');
    } finally {
      request.destroy();
    }
  }

  /** 拼接完整 URL */
  private buildUrl(options: HttpOptions): string {
    let url: string = `${this.baseUrl}${options.path}`;
    const keys: string[] = Object.keys(options.query);
    if (keys.length > 0) {
      const pairs: string[] = keys.map((k: string) => `${encodeURIComponent(k)}=${encodeURIComponent(options.query[k])}`);
      url += `?${pairs.join('&')}`;
    }
    return url;
  }

  private static toRequestMethod(m: HttpMethod): http.RequestMethod {
    switch (m) {
      case HttpMethod.POST:
        return http.RequestMethod.POST;
      case HttpMethod.PUT:
        return http.RequestMethod.PUT;
      case HttpMethod.DELETE:
        return http.RequestMethod.DELETE;
      default:
        return http.RequestMethod.GET;
    }
  }
}
